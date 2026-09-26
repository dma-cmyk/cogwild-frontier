class_name MeshKit
extends RefCounted
## Low-poly procedural mesh builder shared by every visual module.
##
## - Flat-shaded, vertex-coloured triangles merged into ONE surface that uses the shared toon
##   material (toon_vc.gdshader): one draw call per built mesh.
## - Colours are authored in sRGB (Color("#3a5da8")) and converted to linear on emit.
## - Alpha < 1 marks an emissive part (emission = colour * (1 - alpha)); build such colours with
##   MeshKit.glow(color, strength).
## - Transform stack: push()/push_trs() compose local transforms so parts are authored in local
##   space (e.g. an arm relative to the shoulder); pop() restores the parent frame.
## - Primitives orient their faces automatically (outward from the primitive centre), so callers
##   never think about winding. Conventions: 1 unit = 1 m, +Y up, model front = +Z.

const SHADER_PATH := "res://src/visual/shaders/toon_vc.gdshader"

static var _material: ShaderMaterial
static var _mm_material: ShaderMaterial
static var _preview_material: ShaderMaterial

## Per-face brightness variation for a hand-painted look (0 disables).
var shade_jitter := 0.035

var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()
var _stack: Array[Transform3D] = [Transform3D.IDENTITY]


## Shared material for all MeshKit meshes.
static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load(SHADER_PATH)
	return _material


## Variant for MultiMeshInstance3D.material_override: multiplies colour by INSTANCE_CUSTOM.rgb
## when INSTANCE_CUSTOM.a > 0.5 (enable use_custom_data on the MultiMesh).
static func multimesh_material() -> ShaderMaterial:
	if _mm_material == null:
		_mm_material = ShaderMaterial.new()
		_mm_material.shader = load(SHADER_PATH)
		_mm_material.set_shader_parameter("use_instance_tint", true)
	return _mm_material


## Variant for portraits / previews rendered outside the map (no fog of war).
static func preview_material() -> ShaderMaterial:
	if _preview_material == null:
		_preview_material = ShaderMaterial.new()
		_preview_material.shader = load(SHADER_PATH)
		_preview_material.set_shader_parameter("no_fog", true)
	return _preview_material


## Applies preview_material() to every MeshInstance3D under node.
static func apply_preview_material(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = preview_material()
	for c in node.get_children():
		apply_preview_material(c)


## Releases cached materials (called on exit so no resources outlive the scene tree).
static func clear_cache() -> void:
	_material = null
	_mm_material = null
	_preview_material = null


## Colour flagged as emissive. strength 0..1 (1 = fully glowing).
static func glow(col: Color, strength: float = 1.0) -> Color:
	return Color(col.r, col.g, col.b, clampf(1.0 - strength, 0.0, 0.999))


# --- transform stack -------------------------------------------------------------------------

func push(xf: Transform3D) -> void:
	_stack.push_back(_stack.back() * xf)


## Push translate / rotate (degrees, applied Y then X then Z) / scale.
func push_trs(pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> void:
	var b := Basis.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)), EULER_ORDER_YXZ)
	push(Transform3D(b.scaled(scl), pos))


func pop() -> void:
	if _stack.size() > 1:
		_stack.pop_back()


func current() -> Transform3D:
	return _stack.back()


# --- raw triangles ---------------------------------------------------------------------------

## Triangle in local space; a, b, c counter-clockwise when seen from the visible side.
## Mirrored transforms (negative scale) keep the visible side correct.
func tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var xf: Transform3D = _stack.back()
	if xf.basis.determinant() < 0.0:
		_emit(xf * a, xf * c, xf * b, col)
	else:
		_emit(xf * a, xf * b, xf * c, col)


## Quad a-b-c-d (counter-clockwise from the visible side).
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	tri(a, b, c, col)
	tri(a, c, d, col)


## Triangle oriented so its normal points away from `inside` (local space).
func tri_out(a: Vector3, b: Vector3, c: Vector3, inside: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.dot((a + b + c) / 3.0 - inside) < 0.0:
		tri(a, c, b, col)
	else:
		tri(a, b, c, col)


func quad_out(a: Vector3, b: Vector3, c: Vector3, d: Vector3, inside: Vector3, col: Color) -> void:
	tri_out(a, b, c, inside, col)
	tri_out(a, c, d, inside, col)


func _emit(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-14:
		return
	n = n.normalized()
	var lin := col.srgb_to_linear()
	lin.a = col.a
	if shade_jitter > 0.0:
		var centre := (a + b + c) / 3.0
		var h := RngUtil.hash01(int(centre.x * 97.0), int(centre.y * 89.0), int(centre.z * 83.0))
		var f := 1.0 + (h - 0.5) * 2.0 * shade_jitter
		lin = Color(lin.r * f, lin.g * f, lin.b * f, lin.a)
	# Godot treats clockwise triangles as front faces: emit a, c, b.
	_v.push_back(a)
	_v.push_back(c)
	_v.push_back(b)
	for i in 3:
		_n.push_back(n)
		_c.push_back(lin)


# --- primitives (all in local space of the current transform) --------------------------------

## Axis-aligned box. top_col (optional) colours the +Y face differently.
func box(center: Vector3, size: Vector3, col: Color, top_col: Variant = null) -> void:
	var h := size * 0.5
	var p := [
		center + Vector3(-h.x, -h.y, -h.z), center + Vector3(h.x, -h.y, -h.z),
		center + Vector3(h.x, -h.y, h.z), center + Vector3(-h.x, -h.y, h.z),
		center + Vector3(-h.x, h.y, -h.z), center + Vector3(h.x, h.y, -h.z),
		center + Vector3(h.x, h.y, h.z), center + Vector3(-h.x, h.y, h.z)]
	var tc: Color = top_col if top_col is Color else col
	quad_out(p[4], p[5], p[6], p[7], center, tc)  # top
	quad_out(p[0], p[1], p[2], p[3], center, col)  # bottom
	quad_out(p[0], p[1], p[5], p[4], center, col)  # -z
	quad_out(p[3], p[2], p[6], p[7], center, col)  # +z
	quad_out(p[0], p[3], p[7], p[4], center, col)  # -x
	quad_out(p[1], p[2], p[6], p[5], center, col)  # +x


## Truncated cone along +Y from base_center. r_top = 0 makes a cone. top_col colours the top cap.
func frustum(base_center: Vector3, height: float, r_bottom: float, r_top: float, col: Color,
		segments: int = 8, caps: bool = true, top_col: Variant = null) -> void:
	var inside := base_center + Vector3(0, height * 0.5, 0)
	var tc: Color = top_col if top_col is Color else col
	var top := base_center + Vector3(0, height, 0)
	for i in segments:
		var a0 := TAU * float(i) / segments
		var a1 := TAU * float(i + 1) / segments
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var b0 := base_center + d0 * r_bottom
		var b1 := base_center + d1 * r_bottom
		var t0 := top + d0 * r_top
		var t1 := top + d1 * r_top
		if r_top > 0.0001:
			quad_out(b0, b1, t1, t0, inside, col)
			if caps:
				tri_out(top, t0, t1, inside, tc)
		else:
			tri_out(b0, b1, top, inside, col)
		if caps and r_bottom > 0.0001:
			tri_out(base_center, b1, b0, inside, col)


func cylinder(base_center: Vector3, height: float, radius: float, col: Color, segments: int = 8, top_col: Variant = null) -> void:
	frustum(base_center, height, radius, radius, col, segments, true, top_col)


func cone(base_center: Vector3, height: float, radius: float, col: Color, segments: int = 8) -> void:
	frustum(base_center, height, radius, 0.0, col, segments, true)


## Low-poly ellipsoid. segments around Y, rings from bottom to top.
func ellipsoid(center: Vector3, radii: Vector3, col: Color, segments: int = 8, rings: int = 5) -> void:
	for r in rings:
		var p0 := PI * float(r) / rings - PI * 0.5
		var p1 := PI * float(r + 1) / rings - PI * 0.5
		for s in segments:
			var a0 := TAU * float(s) / segments
			var a1 := TAU * float(s + 1) / segments
			var v00 := center + Vector3(cos(p0) * cos(a0) * radii.x, sin(p0) * radii.y, cos(p0) * sin(a0) * radii.z)
			var v01 := center + Vector3(cos(p0) * cos(a1) * radii.x, sin(p0) * radii.y, cos(p0) * sin(a1) * radii.z)
			var v10 := center + Vector3(cos(p1) * cos(a0) * radii.x, sin(p1) * radii.y, cos(p1) * sin(a0) * radii.z)
			var v11 := center + Vector3(cos(p1) * cos(a1) * radii.x, sin(p1) * radii.y, cos(p1) * sin(a1) * radii.z)
			if r == 0:
				tri_out(v00, v11, v10, center, col)
			elif r == rings - 1:
				tri_out(v00, v01, v10, center, col)
			else:
				quad_out(v00, v01, v11, v10, center, col)


func sphere(center: Vector3, radius: float, col: Color, segments: int = 8, rings: int = 5) -> void:
	ellipsoid(center, Vector3(radius, radius, radius), col, segments, rings)


## Four-sided pyramid (hip roofs, spikes). size_xz = base width (x) and depth (z).
func pyramid(base_center: Vector3, size_xz: Vector2, height: float, col: Color) -> void:
	var hx := size_xz.x * 0.5
	var hz := size_xz.y * 0.5
	var apex := base_center + Vector3(0, height, 0)
	var inside := base_center + Vector3(0, height * 0.3, 0)
	var c := [base_center + Vector3(-hx, 0, -hz), base_center + Vector3(hx, 0, -hz),
		base_center + Vector3(hx, 0, hz), base_center + Vector3(-hx, 0, hz)]
	for i in 4:
		tri_out(c[i], c[(i + 1) % 4], apex, inside, col)
	quad_out(c[0], c[1], c[2], c[3], inside, col)


## Gable roof / triangular prism standing on base_center; ridge runs along X.
## size = (length along X, height, depth along Z). overhang extends the roof slopes past the base.
func gable(base_center: Vector3, size: Vector3, roof_col: Color, end_col: Color, overhang: float = 0.0) -> void:
	var hx := size.x * 0.5 + overhang
	var hz := size.z * 0.5 + overhang
	var y0 := base_center.y - overhang * (size.y / maxf(size.z * 0.5, 0.001))
	var ridge_y := base_center.y + size.y
	var inside := base_center + Vector3(0, size.y * 0.35, 0)
	var x0 := base_center.x - hx
	var x1 := base_center.x + hx
	var zf := base_center.z + hz
	var zb := base_center.z - hz
	var zc := base_center.z
	# slopes
	quad_out(Vector3(x0, y0, zf), Vector3(x1, y0, zf), Vector3(x1, ridge_y, zc), Vector3(x0, ridge_y, zc), inside, roof_col)
	quad_out(Vector3(x0, y0, zb), Vector3(x1, y0, zb), Vector3(x1, ridge_y, zc), Vector3(x0, ridge_y, zc), inside, roof_col)
	# gable ends (inset to the wall line so the overhang reads as roof)
	var ex0 := base_center.x - size.x * 0.5
	var ex1 := base_center.x + size.x * 0.5
	var ez := size.z * 0.5
	tri_out(Vector3(ex0, base_center.y, zc - ez), Vector3(ex0, base_center.y, zc + ez), Vector3(ex0, ridge_y, zc), inside, end_col)
	tri_out(Vector3(ex1, base_center.y, zc - ez), Vector3(ex1, base_center.y, zc + ez), Vector3(ex1, ridge_y, zc), inside, end_col)
	# underside
	quad_out(Vector3(x0, y0, zf), Vector3(x1, y0, zf), Vector3(x1, y0, zb), Vector3(x0, y0, zb), inside + Vector3(0, 1, 0), roof_col.darkened(0.3))


## Cylinder between two points (limbs, poles, pipes, cables).
func tube(a: Vector3, b: Vector3, radius: float, col: Color, segments: int = 6) -> void:
	var dir := b - a
	var length := dir.length()
	if length < 0.0001:
		return
	var y := dir / length
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	push(Transform3D(Basis(x, y, z), a))
	cylinder(Vector3.ZERO, length, radius, col, segments)
	pop()


## Torus around local +Y (wheels, rings, balloon bands).
func torus(center: Vector3, radius: float, tube_radius: float, col: Color, segments: int = 10, sides: int = 5) -> void:
	for i in segments:
		var a0 := TAU * float(i) / segments
		var a1 := TAU * float(i + 1) / segments
		for j in sides:
			var b0 := TAU * float(j) / sides
			var b1 := TAU * float(j + 1) / sides
			var p := [_torus_pt(center, radius, tube_radius, a0, b0), _torus_pt(center, radius, tube_radius, a1, b0),
				_torus_pt(center, radius, tube_radius, a1, b1), _torus_pt(center, radius, tube_radius, a0, b1)]
			var ring_c0 := center + Vector3(cos(a0), 0, sin(a0)) * radius
			var ring_c1 := center + Vector3(cos(a1), 0, sin(a1)) * radius
			tri_out(p[0], p[1], p[2], (ring_c0 + ring_c1) * 0.5, col)
			tri_out(p[0], p[2], p[3], (ring_c0 + ring_c1) * 0.5, col)


func _torus_pt(center: Vector3, r: float, t: float, a: float, b: float) -> Vector3:
	var ring := Vector3(cos(a), 0, sin(a))
	return center + ring * (r + cos(b) * t) + Vector3(0, sin(b) * t, 0)


## Flat shape in the local XY plane extruded along Z by `thickness` (flags, blades, fins, leaves).
## points: polygon outline (any winding, may be concave).
func plate(points: PackedVector2Array, thickness: float, col: Color, back_col: Variant = null) -> void:
	var pts := points
	if Geometry2D.is_polygon_clockwise(pts):
		pts = pts.duplicate()
		pts.reverse()
	var idx := Geometry2D.triangulate_polygon(pts)
	if idx.is_empty():
		return
	var hz := thickness * 0.5
	var bc: Color = back_col if back_col is Color else col
	for i in range(0, idx.size(), 3):
		var a := pts[idx[i]]
		var b := pts[idx[i + 1]]
		var c := pts[idx[i + 2]]
		if (b - a).cross(c - a) < 0.0:
			var t := b
			b = c
			c = t
		tri(Vector3(a.x, a.y, hz), Vector3(b.x, b.y, hz), Vector3(c.x, c.y, hz), col)  # CCW in XY -> faces +Z
		tri(Vector3(a.x, a.y, -hz), Vector3(c.x, c.y, -hz), Vector3(b.x, b.y, -hz), bc)
	for i in pts.size():
		var p0 := pts[i]
		var p1 := pts[(i + 1) % pts.size()]
		# outline is CCW, so the outward side normal is (dy, -dx)
		quad(Vector3(p0.x, p0.y, -hz), Vector3(p1.x, p1.y, -hz), Vector3(p1.x, p1.y, hz), Vector3(p0.x, p0.y, hz), col.darkened(0.15))


## Polygon in the local XZ plane (points are (x, z)) extruded upward from y0 to y1
## (walls, plinths, plots). top_col colours the +Y face.
func prism_xz(points: PackedVector2Array, y0: float, y1: float, col: Color, top_col: Variant = null) -> void:
	var tc: Color = top_col if top_col is Color else col
	# Rotation mapping plate X -> X, plate Y -> -Z, plate Z (extrusion) -> +Y.
	var flipped := PackedVector2Array()
	for p in points:
		flipped.push_back(Vector2(p.x, -p.y))
	push(Transform3D(Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP), Vector3(0, (y0 + y1) * 0.5, 0)))
	plate(flipped, y1 - y0, tc, col)
	pop()


# --- composition & output ---------------------------------------------------------------------

## Append another kit's triangles through the current transform (mirror-safe).
func append(other: MeshKit) -> void:
	var xf: Transform3D = _stack.back()
	var basis_n := xf.basis.inverse().transposed()
	var order := [0, 2, 1] if xf.basis.determinant() < 0.0 else [0, 1, 2]
	for t in range(0, other._v.size(), 3):
		for k: int in order:
			_v.push_back(xf * other._v[t + k])
			_n.push_back((basis_n * other._n[t + k]).normalized())
			_c.push_back(other._c[t + k])


func is_empty() -> bool:
	return _v.is_empty()


func vertex_count() -> int:
	return _v.size()


func triangle_count() -> int:
	return _v.size() / 3


func get_aabb() -> AABB:
	if _v.is_empty():
		return AABB()
	var box_ := AABB(_v[0], Vector3.ZERO)
	for p in _v:
		box_ = box_.expand(p)
	return box_


## Build (or append a surface to) an ArrayMesh using the shared material.
func build(mesh: ArrayMesh = null) -> ArrayMesh:
	var out := mesh if mesh != null else ArrayMesh.new()
	if _v.is_empty():
		return out
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v
	arrays[Mesh.ARRAY_NORMAL] = _n
	arrays[Mesh.ARRAY_COLOR] = _c
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	out.surface_set_material(out.get_surface_count() - 1, material())
	return out


func clear() -> void:
	_v.clear()
	_n.clear()
	_c.clear()
	_stack = [Transform3D.IDENTITY]
