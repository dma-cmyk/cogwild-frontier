class_name ChunkView
extends Node3D
## Renders one chunk: flat-shaded terrain with blended vertex colours (+ static decor such as
## grass, flowers, reeds and bridge planks merged into a second surface), a water plane where
## needed, and MultiMeshes for harvestable props (trees, rocks, ore, bushes, stumps).
## Terrain is rebuilt only when the ground changes; props when resources change.

const S := ChunkData.S
const ROCK := Color("#8f887b")
const PROP_VARIANTS_MAX := 2
const SHADOW_PROPS := ["tree_pine", "tree_oak", "tree_birch", "tree_dead", "rock_large", "ore_iron", "ore_crystal"]

static var _terrain_mat: ShaderMaterial
static var _water_mat: ShaderMaterial
static var _mesh_arrays: Dictionary = {}  # "prop:variant" -> [verts, normals, colors]

var w: World
var ch: ChunkData
var terrain_mi: MeshInstance3D
var water_mi: MeshInstance3D
var props_root: Node3D
var built_version := -1
var built_res_version := -1


static func clear_cache() -> void:
	_terrain_mat = null
	_water_mat = null
	_mesh_arrays.clear()


static func terrain_material() -> ShaderMaterial:
	if _terrain_mat == null:
		_terrain_mat = ShaderMaterial.new()
		_terrain_mat.shader = load("res://src/visual/shaders/terrain.gdshader")
	return _terrain_mat


static func water_material() -> ShaderMaterial:
	if _water_mat == null:
		_water_mat = ShaderMaterial.new()
		_water_mat.shader = load("res://src/visual/shaders/water.gdshader")
	return _water_mat


func setup(world: World, chunk: ChunkData) -> void:
	w = world
	ch = chunk
	name = "Chunk_%d_%d" % [ch.cx, ch.cz]
	position = Vector3(ch.cx * S, 0.0, ch.cz * S)
	terrain_mi = MeshInstance3D.new()
	terrain_mi.name = "Terrain"
	add_child(terrain_mi)
	props_root = Node3D.new()
	props_root.name = "Props"
	add_child(props_root)
	rebuild_terrain()
	rebuild_props()


## Rebuild whatever changed since the last build.
func refresh() -> void:
	if ch.version != built_version:
		rebuild_terrain()
	if ch.res_version != built_res_version:
		rebuild_props()


# --- terrain ------------------------------------------------------------------------------

func _tile_color(t: Vector2i) -> Color:
	var tt := w.terrain_at(t) if w.chunk_at_tile(t) != null else -1
	if tt < 0:
		var lx := clampi(t.x - ch.cx * S, 0, S - 1)
		var lz := clampi(t.y - ch.cz * S, 0, S - 1)
		tt = ch.terrain[lz * S + lx]
	var c: Color = Tiles.COLORS[tt]
	var h := RngUtil.hash01(w.seed, t.x, t.y, 91)
	var f := 0.96 + h * 0.08
	return Color(c.r * f, c.g * f, c.b * f)


func rebuild_terrain() -> void:
	built_version = ch.version
	var ox := ch.cx * S
	var oz := ch.cz * S
	# tile colours including a one-tile border (for smooth blending across chunks)
	var tc := PackedColorArray()
	tc.resize((S + 2) * (S + 2))
	for z in range(-1, S + 1):
		for x in range(-1, S + 1):
			tc[(z + 1) * (S + 2) + (x + 1)] = _tile_color(Vector2i(ox + x, oz + z))
	var cc := PackedColorArray()
	cc.resize((S + 1) * (S + 1))
	for z in S + 1:
		for x in S + 1:
			var a := tc[z * (S + 2) + x]
			var b := tc[z * (S + 2) + x + 1]
			var c := tc[(z + 1) * (S + 2) + x]
			var d := tc[(z + 1) * (S + 2) + x + 1]
			var avg := (a + b + c + d) * 0.25
			var h := ch.heights[z * (S + 1) + x]
			if h > 6.0:
				avg = avg.lightened(clampf((h - 6.0) / 30.0, 0.0, 0.18))
			cc[z * (S + 1) + x] = avg
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(S * S * 6)
	norms.resize(S * S * 6)
	cols.resize(S * S * 6)
	var vi := 0
	for z in S:
		for x in S:
			var h00 := ch.heights[z * (S + 1) + x]
			var h10 := ch.heights[z * (S + 1) + x + 1]
			var h01 := ch.heights[(z + 1) * (S + 1) + x]
			var h11 := ch.heights[(z + 1) * (S + 1) + x + 1]
			var p00 := Vector3(x, h00, z)
			var p10 := Vector3(x + 1, h10, z)
			var p01 := Vector3(x, h01, z + 1)
			var p11 := Vector3(x + 1, h11, z + 1)
			var c00 := cc[z * (S + 1) + x]
			var c10 := cc[z * (S + 1) + x + 1]
			var c01 := cc[(z + 1) * (S + 1) + x]
			var c11 := cc[(z + 1) * (S + 1) + x + 1]
			var cliff := ch.terrain[z * S + x] == Tiles.CLIFF
			# split along the diagonal with the smaller height difference
			if absf(h00 - h11) <= absf(h10 - h01):
				vi = _tri(verts, norms, cols, vi, p00, p11, p10, c00, c11, c10, cliff)
				vi = _tri(verts, norms, cols, vi, p00, p01, p11, c00, c01, c11, cliff)
			else:
				vi = _tri(verts, norms, cols, vi, p00, p01, p10, c00, c01, c10, cliff)
				vi = _tri(verts, norms, cols, vi, p10, p01, p11, c10, c01, c11, cliff)
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, terrain_material())
	_add_decor_surface(mesh)
	terrain_mi.mesh = mesh
	_rebuild_water()


## Appends one terrain triangle (a, b, c counter-clockwise seen from above) in Godot's clockwise
## front-face order, flat normal, steep faces blended to rock.
func _tri(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, vi: int,
		a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc_: Color, cliff: bool) -> int:
	var n := (b - a).cross(c - a).normalized()
	if n.y < 0.0:
		n = -n
		var tmp := b
		b = c
		c = tmp
		var tc := cb
		cb = cc_
		cc_ = tc
	var steep := clampf((0.8 - n.y) / 0.35, 0.0, 1.0)
	if cliff:
		steep = maxf(steep, 0.75)
	if steep > 0.0:
		ca = ca.lerp(ROCK, steep)
		cb = cb.lerp(ROCK, steep)
		cc_ = cc_.lerp(ROCK, steep)
	verts[vi] = a
	verts[vi + 1] = c
	verts[vi + 2] = b
	for k in 3:
		norms[vi + k] = n
	cols[vi] = ca.srgb_to_linear()
	cols[vi + 1] = cc_.srgb_to_linear()
	cols[vi + 2] = cb.srgb_to_linear()
	return vi + 3


static func _arrays_for(prop: String, variant: int) -> Array:
	var key := "%s:%d" % [prop, variant]
	if not _mesh_arrays.has(key):
		var m := PropMeshes.get_mesh(prop, variant)
		if m == null or m.get_surface_count() == 0:
			_mesh_arrays[key] = []
		else:
			var a := m.surface_get_arrays(0)
			_mesh_arrays[key] = [a[Mesh.ARRAY_VERTEX], a[Mesh.ARRAY_NORMAL], a[Mesh.ARRAY_COLOR], a[Mesh.ARRAY_INDEX]]
	return _mesh_arrays[key]


func _add_decor_surface(mesh: ArrayMesh) -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	for d: Array in ch.decor:
		var prop := str(d[0])
		if prop == "stump":
			continue
		var lx := float(d[1])
		var lz := float(d[2])
		var i := clampi(int(lz), 0, S - 1) * S + clampi(int(lx), 0, S - 1)
		if ch.res_type[i] != Tiles.Res.NONE and prop in ["grass_tuft", "flowers"]:
			continue
		var y := ch.height_local(lx, lz)
		if prop == "reeds":
			y = maxf(y, -0.25)
		var sc := float(d[4])
		if prop == "rock_large" or prop == "rock_small":
			sc *= 0.55 if prop == "rock_large" else 0.8
			y -= 0.12
		var xf := Transform3D(Basis(Vector3.UP, float(d[3])).scaled(Vector3.ONE * sc), Vector3(lx, y, lz))
		_append_mesh(verts, norms, cols, prop, int(abs(int(lx * 7.0 + lz * 13.0))) % maxi(1, PropMeshes.variant_count(prop)), xf)
	# bridge planks over water on trail crossings
	var deck := float(w.gen.t["bridge_deck"])
	for z in S:
		for x in S:
			if ch.terrain[z * S + x] != Tiles.BRIDGE:
				continue
			var t := Vector2i(ch.cx * S + x, ch.cz * S + z)
			var along_x := _is_path(t + Vector2i(1, 0)) or _is_path(t + Vector2i(-1, 0))
			var along_z := _is_path(t + Vector2i(0, 1)) or _is_path(t + Vector2i(0, -1))
			var rot := PI * 0.5 if (along_z and not along_x) else 0.0
			var xf := Transform3D(Basis(Vector3.UP, rot), Vector3(x + 0.5, deck - 0.05, z + 0.5))
			_append_mesh(verts, norms, cols, "bridge_plank", 0, xf)
	if verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, MeshKit.material())


func _is_path(t: Vector2i) -> bool:
	var tt := w.terrain_at(t)
	return tt == Tiles.BRIDGE or tt == Tiles.TRAIL


func _append_mesh(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, prop: String, variant: int, xf: Transform3D) -> void:
	var arr := _arrays_for(prop, variant)
	if arr.is_empty():
		return
	var v: PackedVector3Array = arr[0]
	var n: PackedVector3Array = arr[1]
	var c: PackedColorArray = arr[2]
	var idx: Variant = arr[3]
	var nb := xf.basis.orthonormalized()
	if idx is PackedInt32Array and not (idx as PackedInt32Array).is_empty():
		for k: int in idx:
			verts.append(xf * v[k])
			norms.append(nb * n[k])
			cols.append(c[k])
	else:
		for k in v.size():
			verts.append(xf * v[k])
			norms.append(nb * n[k])
			cols.append(c[k])


func _rebuild_water() -> void:
	var need := false
	for hh in ch.heights:
		if hh < 0.02:
			need = true
			break
	if not need:
		if water_mi:
			water_mi.queue_free()
			water_mi = null
		return
	if water_mi == null:
		water_mi = MeshInstance3D.new()
		water_mi.name = "Water"
		water_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var pm := PlaneMesh.new()
		pm.size = Vector2(S, S)
		pm.material = water_material()
		water_mi.mesh = pm
		water_mi.position = Vector3(S * 0.5, 0.0, S * 0.5)
		add_child(water_mi)


# --- props ---------------------------------------------------------------------------------

func rebuild_props() -> void:
	built_res_version = ch.res_version
	for c in props_root.get_children():
		c.queue_free()
	var groups := {}  # "prop:variant" -> Array[Transform3D]
	for z in S:
		for x in S:
			var i := z * S + x
			var r := ch.res_type[i]
			var prop := ""
			var variant := int(ch.res_var[i])
			if r != Tiles.Res.NONE:
				prop = str(Tiles.res_info(r).get("id", ""))
			elif ch.regrow.has(i):
				prop = "berry_bush_empty"
			if prop == "":
				continue
			var vc := mini(PROP_VARIANTS_MAX, maxi(1, PropMeshes.variant_count(prop)))
			var v := variant % vc
			var h1 := float((variant * 37) % 100) / 100.0
			var jx := (h1 - 0.5) * 0.3
			var jz := (float((variant * 61) % 100) / 100.0 - 0.5) * 0.3
			var px := x + 0.5 + jx
			var pz := z + 0.5 + jz
			var scale := 0.85 + h1 * 0.3
			if prop in ["rock_large", "ore_iron", "ore_crystal"]:
				px = x + 0.5
				pz = z + 0.5
			var xf := Transform3D(Basis(Vector3.UP, float(variant) * 0.73).scaled(Vector3.ONE * scale), Vector3(px, ch.height_local(px, pz), pz))
			var key := "%s:%d" % [prop, v]
			if not groups.has(key):
				groups[key] = []
			(groups[key] as Array).append(xf)
	for d: Array in ch.decor:
		if str(d[0]) != "stump":
			continue
		var xf := Transform3D(Basis(Vector3.UP, float(d[3])), Vector3(float(d[1]), ch.height_local(float(d[1]), float(d[2])), float(d[2])))
		if not groups.has("stump:0"):
			groups["stump:0"] = []
		(groups["stump:0"] as Array).append(xf)
	for key: String in groups:
		var parts := key.split(":")
		var prop := parts[0]
		var list: Array = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = PropMeshes.get_mesh(prop, int(parts[1]))
		mm.instance_count = list.size()
		for k in list.size():
			var xf: Transform3D = list[k]
			mm.set_instance_transform(k, xf)
			var hv := RngUtil.hash01(ch.cx * 131 + k, ch.cz * 71 + k, prop.hash() & 0xFFFF)
			var tint := Color(0.92 + hv * 0.14, 0.94 + (1.0 - hv) * 0.1, 0.92 + hv * 0.1, 1.0)
			mm.set_instance_custom_data(k, tint)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = MeshKit.multimesh_material()
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if prop in SHADOW_PROPS else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		props_root.add_child(mmi)
