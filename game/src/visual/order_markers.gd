class_name OrderMarkers
extends Node3D
## Ground overlay that answers "what did I just order, where, and what have I got selected?". For
## every squad and lone unit the command bar is addressing it outlines the standing order — the
## area held, the region explored, the patrol route, the unit escorted, the destination marched on
## — previews the same shape under the cursor while an order waits for its target, and rings what
## is selected but draws no ring of its own (a building's footprint, a site, a loot bag).
## Everything is one unshaded mesh of soft-edged bands laid on the terrain: line primitives are one
## pixel wide and vanish against the map, and a hard-edged band reads as a sticker. Routes are
## dashed, areas unbroken. Reads the World, never changes it.

const PREVIEW := Color("#ffd36a")
const HOSTILE := Color("#ff6a4a")
const LONE := Color("#7fe0ff")  # units that serve in no squad and so have no squad colour
const INVALID := Color("#ff4d4d")
const SELECT := Color("#ffe9a8")  # what the player has selected but that has no ring of its own
const MAX_SEGMENTS := 128  # enough that even the explore circle keeps chords near SAMPLE_STEP
const SAMPLE_STEP := 1.5  # metres between ground samples along a ribbon
const WIDTH := 0.34  # bright core of a zone/order band; persistent zones need clear contrast
const GLOW := 0.28  # soft falloff either side of the core
const DASH := 1.7  # dash length of a route line
const DASH_GAP := 0.85  # gap between dashes
const LIFT := 0.14  # metres above the ground, clear of terrain sampling
const SIGNATURE_GRID := 2.0  # metres a shape must move before the overlay is rebuilt
const MARKER_R := 1.0

var w: World
var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _signature := ""


func setup(world: World) -> void:
	name = "OrderMarkers"
	w = world
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# The overlay answers "where did I point?", so it stays readable: with depth testing a route
	# through the settlement is chopped into fragments by every roof it passes behind. The soft
	# rims keep it from reading as a sticker.
	_material.no_depth_test = true
	_material.render_priority = 5
	_mesh = MeshInstance3D.new()
	_mesh.name = "OrderShapes"
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


## `squad_ids`: the squads the command bar addresses. `units`: addressed units that serve in no
## squad. `preview`: the order still waiting for its target, {"type", "pos", "from", "valid"}, or
## {} when no order is pending. `focus`: what is selected but has no ring of its own — a building
## ({"rect": Rect2i}) or a place ({"at": Vector2, "r": float}).
func refresh(squad_ids: Array, units: Array, preview: Dictionary, focus: Dictionary = {}) -> void:
	if w == null:
		return
	var shapes: Array[Dictionary] = []
	for id_variant: Variant in squad_ids:
		var squad := w.get_squad(int(id_variant))
		if squad != null and not squad.members.is_empty():
			_order_shapes(w.squad_ai.center(squad), squad.order, squad.color(), squad.mem.get("hold", null), shapes)
	for unit_variant: Variant in units:
		var unit := unit_variant as Unit
		if unit != null and unit.alive and not unit.order.is_empty():
			_order_shapes(unit.pos, unit.order, LONE, null, shapes)
	if focus.has("rect"):
		var r: Rect2i = focus["rect"]
		var corners := [Vector2(r.position), Vector2(r.end.x, r.position.y), Vector2(r.end), Vector2(r.position.x, r.end.y)]
		for i in 4:
			_line(shapes, corners[i], corners[(i + 1) % 4], SELECT, false)
	elif focus.has("at"):
		_circle(shapes, focus["at"], float(focus.get("r", 2.0)), SELECT)
	if not preview.is_empty():
		_preview_shapes(preview, shapes)
	var signature := _signature_of(shapes)
	if signature == _signature:
		return
	_signature = signature
	_mesh.mesh = _build(shapes)


## One standing order drawn from where its owner is (`center`) towards what it was pointed at.
func _order_shapes(center: Vector2, order: Dictionary, color: Color, hold: Variant, shapes: Array[Dictionary]) -> void:
	match str(order.get("type", "")):
		"move", "visit":
			var goal: Vector2 = order.get("pos", center)
			_line(shapes, center, goal, color)
			_marker(shapes, goal, color)
		"attack":
			var goal := _attack_anchor(order, center)
			_line(shapes, center, goal, HOSTILE)
			_circle(shapes, goal, 3.0, HOSTILE)
		"defend", "hold":
			var goal: Vector2 = order.get("pos", center)
			_circle(shapes, goal, float(order.get("radius", 10.0)), color)
			_marker(shapes, goal, color)
		"explore":
			var goal: Vector2 = order.get("pos", center)
			_circle(shapes, goal, float(order.get("radius", SquadAI.EXPLORE_RADIUS)), color)
			_marker(shapes, goal, color)
		"patrol":
			var points: Array = order.get("points", [])
			for i in points.size():
				_line(shapes, points[i], points[(i + 1) % points.size()], color)
				_marker(shapes, points[i], color)
		"escort":
			var guarded := w.get_unit(int(order.get("target", -1)))
			if guarded != null and guarded.alive:
				_line(shapes, center, guarded.pos, color)
				_circle(shapes, guarded.pos, 2.2, color)
		"retreat", "return":
			_line(shapes, center, w.home_pos(), color)
			_marker(shapes, w.home_pos(), color)
		"auto":
			_circle(shapes, w.home_pos(), 4.0, color)
		"gather":
			_marker(shapes, Vector2(order.get("tile", Vector2i(center))) + Vector2(0.5, 0.5), color)
		"idle":
			_marker(shapes, hold if hold is Vector2 else center, color)


func _attack_anchor(order: Dictionary, fallback: Vector2) -> Vector2:
	var target := w.get_unit(int(order.get("target", -1)))
	if target != null and target.alive:
		return target.pos
	var site: Dictionary = w.sites.get(int(order.get("site", -1)), {})
	if not site.is_empty():
		return Vector2(site["center"]) + Vector2(0.5, 0.5)
	return order.get("pos", fallback)


func _preview_shapes(preview: Dictionary, shapes: Array[Dictionary]) -> void:
	var at: Vector2 = preview.get("pos", Vector2.ZERO)
	var from: Vector2 = preview.get("from", at)
	var color: Color = PREVIEW if bool(preview.get("valid", true)) else INVALID
	match str(preview.get("type", "")):
		"move":
			_line(shapes, from, at, color)
			_marker(shapes, at, color)
		"attack":
			_line(shapes, from, at, HOSTILE)
			_circle(shapes, at, 3.0, HOSTILE)
		"defend":
			_circle(shapes, at, 10.0, color)
			_marker(shapes, at, color)
		"explore":
			_circle(shapes, at, SquadAI.EXPLORE_RADIUS, color)
			_marker(shapes, at, color)
		"patrol":
			_line(shapes, from, at, color)
			_marker(shapes, from, color)
			_marker(shapes, at, color)
		"escort":
			_circle(shapes, at, 2.2, color)
			_marker(shapes, at, color)


func _circle(shapes: Array[Dictionary], center: Vector2, radius: float, color: Color) -> void:
	shapes.append({"c": center, "r": maxf(0.5, radius), "col": color})


## A route the owner will walk is dashed; an outline that bounds an area is unbroken.
func _line(shapes: Array[Dictionary], a: Vector2, b: Vector2, color: Color, dash: bool = true) -> void:
	if a.distance_squared_to(b) > 0.25:
		shapes.append({"a": a, "b": b, "col": color, "dash": dash})


## Destination pin: a small ring with four ticks springing out of it, which stays readable on any
## terrain colour without a crosshair cutting the middle out.
func _marker(shapes: Array[Dictionary], at: Vector2, color: Color) -> void:
	_circle(shapes, at, MARKER_R * 0.55, color)
	for corner: Vector2 in [Vector2(0.707, 0.707), Vector2(0.707, -0.707), Vector2(-0.707, 0.707), Vector2(-0.707, -0.707)]:
		shapes.append({"a": at + corner * MARKER_R * 0.7, "b": at + corner * MARKER_R * 1.2, "col": color, "dash": false})


## Cheap fingerprint so the mesh is only rebuilt when a shape actually moved or changed colour.
## Rounded to SIGNATURE_GRID: the squad end of an escort or march line follows a walking squad,
## and rebuilding the whole overlay every stride is not worth the pixels it moves.
func _signature_of(shapes: Array[Dictionary]) -> String:
	var parts := PackedStringArray()
	for s: Dictionary in shapes:
		if s.has("r"):
			parts.append("c%.0f,%.0f,%.0f,%d" % [s["c"].x / SIGNATURE_GRID, s["c"].y / SIGNATURE_GRID, s["r"], s["col"].to_rgba32()])
		else:
			parts.append("l%.0f,%.0f,%.0f,%.0f,%d" % [s["a"].x / SIGNATURE_GRID, s["a"].y / SIGNATURE_GRID, s["b"].x / SIGNATURE_GRID, s["b"].y / SIGNATURE_GRID, s["col"].to_rgba32()])
	return "|".join(parts)


func _build(shapes: Array[Dictionary]) -> Mesh:
	if shapes.is_empty():
		return null
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	for s: Dictionary in shapes:
		if s.has("r"):
			_ring(im, s["c"], s["r"], s["col"])
		else:
			ribbon(im, w, s["a"], s["b"], s["col"], DASH if bool(s.get("dash", false)) else 0.0)
	im.surface_end()
	return im


## Circle laid on the ground: a bright rim with the same soft falloff as a ribbon.
func _ring(im: ImmediateMesh, center: Vector2, radius: float, color: Color) -> void:
	var steps := clampi(int(radius * 4.0), 24, MAX_SEGMENTS)
	var before := Vector2.RIGHT
	for i in range(1, steps + 1):
		var angle := TAU * float(i) / float(steps)
		var after := Vector2(cos(angle), sin(angle))
		_band(im, w, center + before * radius, before, center + after * radius, after, color)
		before = after


## Flat ground ribbon from `a` to `b`, sampled so it follows the terrain. `dash` > 0 draws it as a
## dashed route (dashes and gaps of that length) instead of one unbroken band. Also used for the
## gather-zone outlines: one-pixel line primitives vanish against the map.
static func ribbon(im: ImmediateMesh, world: World, a: Vector2, b: Vector2, color: Color, dash: float = 0.0) -> void:
	var span := b - a
	var length := span.length()
	if length < 0.01:
		return
	var dir := span / length
	if dash <= 0.0:
		# overshoot by half a width so corners and joints close up
		_sampled(im, world, a - dir * WIDTH * 0.5, b + dir * WIDTH * 0.5, dir.orthogonal(), color)
		return
	var travelled := 0.0
	while travelled < length:
		var end := minf(travelled + dash, length)
		_sampled(im, world, a + dir * travelled, a + dir * end, dir.orthogonal(), color)
		travelled += dash + DASH_GAP


## Splits a straight run into pieces short enough to hug the ground under it.
static func _sampled(im: ImmediateMesh, world: World, from: Vector2, to: Vector2, side: Vector2, color: Color) -> void:
	var steps := maxi(1, int(ceil(from.distance_to(to) / SAMPLE_STEP)))
	for i in steps:
		_band(im, world, from.lerp(to, float(i) / float(steps)), side,
			from.lerp(to, float(i + 1) / float(steps)), side, color)


## One straight piece of band: a bright core with a rim that fades to nothing on both sides, so the
## mark reads as a soft light lying on the ground instead of a hard-edged sticker. Each end carries
## its own sideways direction, which is what lets a circle close up without kinks. The ground is
## sampled once per end and reused across the width — a band is under half a metre wide, and
## sampling every corner made the overlay the most expensive thing on screen.
static func _band(im: ImmediateMesh, world: World, p0: Vector2, s0: Vector2, p1: Vector2, s1: Vector2, color: Color) -> void:
	var y0 := maxf(world.height_at(p0), 0.0) + LIFT
	var y1 := maxf(world.height_at(p1), 0.0) + LIFT
	var half := WIDTH * 0.5
	var c0 := s0 * half
	var c1 := s1 * half
	var e0 := s0 * (half + GLOW)
	var e1 := s1 * (half + GLOW)
	var faded := Color(color.r, color.g, color.b, 0.0)
	_quad(im, p0 - e0, y0, p1 - e1, y1, p1 - c1, p0 - c0, faded, faded, color, color)
	_quad(im, p0 - c0, y0, p1 - c1, y1, p1 + c1, p0 + c0, color, color, color, color)
	_quad(im, p0 + c0, y0, p1 + c1, y1, p1 + e1, p0 + e0, color, color, faded, faded)


## Quad across the band: `p0`/`p3` sit at height `y0`, `p1`/`p2` at height `y1`.
static func _quad(im: ImmediateMesh, p0: Vector2, y0: float, p1: Vector2, y1: float, p2: Vector2, p3: Vector2,
		c0: Color, c1: Color, c2: Color, c3: Color) -> void:
	var points := [Vector3(p0.x, y0, p0.y), Vector3(p1.x, y1, p1.y), Vector3(p2.x, y1, p2.y), Vector3(p3.x, y0, p3.y)]
	var colors := [c0, c1, c2, c3]
	for i: int in [0, 1, 2, 2, 3, 0]:
		im.surface_set_color(colors[i])
		im.surface_add_vertex(points[i])


## Shared mesh for the mark drawn under a unit: a flat disc of faint light with a bright rim that
## fades out on both sides. Vertex colours carry the shape, so one mesh serves every colour —
## tint it with the material's albedo. A TorusMesh reads as a chunky 3D tube under a painted
## sprite, which is what this replaces.
static func unit_mark(radius: float = 0.56, rim: float = 0.15, fill: float = 0.14) -> ArrayMesh:
	var steps := 40
	var bands := [[0.0, fill], [radius - rim, fill], [radius - rim * 0.4, 1.0], [radius + rim * 1.6, 0.0]]
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	for i in steps:
		var a0 := TAU * float(i) / float(steps)
		var a1 := TAU * float(i + 1) / float(steps)
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		for b in bands.size() - 1:
			var r0: float = bands[b][0]
			var r1: float = bands[b + 1][0]
			var k0 := Color(1, 1, 1, bands[b][1])
			var k1 := Color(1, 1, 1, bands[b + 1][1])
			for entry: Array in [[d0 * r0, k0], [d1 * r0, k0], [d1 * r1, k1], [d1 * r1, k1], [d0 * r1, k1], [d0 * r0, k0]]:
				verts.append(entry[0])
				colors.append(entry[1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
