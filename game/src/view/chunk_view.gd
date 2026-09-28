class_name ChunkView
extends Node3D
## Renders one chunk: terrain painted with the generated ground textures (per-vertex weights of
## eight layers blended in terrain.gdshader; steep faces turn to rock), static 3D decor such as
## bridge planks merged into a second surface, a water plane where needed, and MultiMeshes for
## props: painted billboards (trees, rocks, ore, bushes, grass, flowers, reeds) from the prop
## atlas, procedural meshes for anything without painted art.
## Terrain is rebuilt only when the ground changes; props when resources change.

const S := ChunkData.S
const TERRAIN_ROWS_PER_SLICE := 8
const PROP_VARIANTS_MAX := 2
const SHADOW_PROPS := ["tree_pine", "tree_oak", "tree_birch", "tree_dead", "rock_large", "ore_iron", "ore_crystal"]
## Ground texture layer per tile type (Tiles enum order). Layers: 0 grass, 1 meadow, 2 forest
## floor, 3 sand, 4 dirt, 5 rock, 6 farmland, 7 paving (tools/art/process.py TERRAIN_LAYERS).
const TILE_LAYER := [3, 3, 3, 0, 1, 2, 4, 5, 5, 4, 4, 6, 7]
## Meadow tiles are part grass so the brightness blend leaves flower patches, not a carpet.
const MEADOW_FLOWERS := 0.42
## Props drawn with another prop's painting.
const SPRITE_ALIAS := {"berry_bush_empty": "bush"}
## Wind sway (metres at the top) per painted prop; one MultiMesh per value: trees, plants, rest.
const SWAY := {"tree_pine": 0.07, "tree_oak": 0.07, "tree_birch": 0.07, "tree_dead": 0.07, "reeds": 0.04,
	"grass_tuft": 0.04, "flowers": 0.04, "bush": 0.04, "berry_bush": 0.04}
const SPRITE_DECOR := ["grass_tuft", "flowers", "reeds", "rock_small", "rock_large"]

static var _terrain_mat: ShaderMaterial
static var _water_mat: ShaderMaterial
static var _mesh_arrays: Dictionary = {}  # "prop:variant" -> [verts, normals, colors]
static var _card_quad: QuadMesh

var w: World
var ch: ChunkData
var terrain_mi: MeshInstance3D
var water_mi: MeshInstance3D
var props_root: Node3D
var built_version := -1
var built_res_version := -1
var _rock_tint := false
var _terrain_build_generation: int = 0


static func clear_cache() -> void:
	_terrain_mat = null
	_water_mat = null
	_mesh_arrays.clear()
	_card_quad = null


static func terrain_material() -> ShaderMaterial:
	if _terrain_mat == null:
		_terrain_mat = ShaderMaterial.new()
		_terrain_mat.shader = load("res://src/visual/shaders/terrain.gdshader")
		var layers := load("res://assets/textures/terrain_array.png") if ResourceLoader.exists("res://assets/textures/terrain_array.png") else null
		_terrain_mat.set_shader_parameter("layers", layers)
		# the importer produces a CompressedTexture2DArray (a TextureLayered, not a Texture2DArray)
		var ok := layers is TextureLayered and (layers as TextureLayered).get_layered_type() == TextureLayered.LAYERED_TYPE_2D_ARRAY
		_terrain_mat.set_shader_parameter("use_layers", ok)
		_terrain_mat.set_shader_parameter("detail_enabled", Quality.terrain_detail_enabled())
	return _terrain_mat



func apply_terrain_detail(enabled: bool) -> void:
	terrain_material().set_shader_parameter("detail_enabled", enabled)

static func water_material() -> ShaderMaterial:
	if _water_mat == null:
		_water_mat = ShaderMaterial.new()
		_water_mat.shader = load("res://src/visual/shaders/water.gdshader")
	return _water_mat


func setup(world: World, chunk: ChunkData, immediate: bool = false) -> void:
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
	await rebuild_terrain(immediate)
	# the view may leave the tree while it builds (a load swaps the whole world view)
	if not is_inside_tree():
		return
	if not immediate:
		await get_tree().process_frame
	if is_inside_tree():
		rebuild_props()


## Rebuild whatever changed since the last build.
func refresh() -> void:
	if ch.version != built_version:
		await rebuild_terrain()
	if ch.res_version != built_res_version:
		await get_tree().process_frame
		if is_inside_tree():
			rebuild_props()


# --- terrain ------------------------------------------------------------------------------

func _tile_type(t: Vector2i) -> int:
	var tt := w.terrain_at(t) if w.chunk_at_tile(t) != null else -1
	if tt < 0:
		var lx := clampi(t.x - ch.cx * S, 0, S - 1)
		var lz := clampi(t.y - ch.cz * S, 0, S - 1)
		tt = ch.terrain[lz * S + lx]
	return tt


func rebuild_terrain(immediate: bool = false) -> void:
	var profile := World.profile_chunks()
	var prep_start_usec: int = Time.get_ticks_usec() if profile else 0
	_terrain_build_generation += 1
	var build_generation: int = _terrain_build_generation
	var terrain_version: int = ch.version
	var ox := ch.cx * S
	var oz := ch.cz * S
	# tile layers and brightness jitter including a one-tile border (smooth blends across chunks)
	var n := S + 2
	var tl := PackedInt32Array()
	var tj := PackedFloat32Array()
	var tcol := PackedColorArray()
	tl.resize(n * n)
	tj.resize(n * n)
	tcol.resize(n * n)
	for z in range(-1, S + 1):
		for x in range(-1, S + 1):
			var t := Vector2i(ox + x, oz + z)
			var tt := _tile_type(t)
			var k := (z + 1) * n + (x + 1)
			tl[k] = int(TILE_LAYER[tt])
			tj[k] = 0.95 + RngUtil.hash01(w.seed, t.x, t.y, 91) * 0.1
			tcol[k] = Tiles.COLORS[tt]
	if not immediate:
		await get_tree().process_frame
		if not is_inside_tree() or build_generation != _terrain_build_generation or ch.version != terrain_version:
			return
	# per grid vertex: tint (linear) and two RGBA weight sets for the 8 layers
	var vn := (S + 1) * (S + 1)
	var vt := PackedColorArray()
	var vw0 := PackedColorArray()
	var vw1 := PackedColorArray()
	var vcol := PackedColorArray()
	vt.resize(vn)
	vw0.resize(vn)
	vw1.resize(vn)
	vcol.resize(vn)
	for z in S + 1:
		for x in S + 1:
			var wts := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
			var bright := 0.0
			var col := Color(0, 0, 0)
			for k: int in [z * n + x, z * n + x + 1, (z + 1) * n + x, (z + 1) * n + x + 1]:
				if tl[k] == 1:
					wts[0] += 0.25 * (1.0 - MEADOW_FLOWERS)
					wts[1] += 0.25 * MEADOW_FLOWERS
				else:
					wts[tl[k]] += 0.25
				bright += tj[k] * 0.25
				col += tcol[k] * 0.25
			var h := ch.heights[z * (S + 1) + x]
			if h > 6.0:
				bright *= 1.0 + clampf((h - 6.0) / 30.0, 0.0, 0.14)
			var i := z * (S + 1) + x
			vt[i] = Color(bright, bright, bright)
			vw0[i] = Color(wts[0], wts[1], wts[2], wts[3])
			vw1[i] = Color(wts[4], wts[5], wts[6], wts[7])
			vcol[i] = col
		if not immediate and (z + 1) % TERRAIN_ROWS_PER_SLICE == 0:
			await get_tree().process_frame
			if not is_inside_tree() or build_generation != _terrain_build_generation or ch.version != terrain_version:
				return
	if profile:
		print("PERF_TERRAIN_PREP key=(%d,%d) ms=%.2f" % [ch.cx, ch.cz, (Time.get_ticks_usec() - prep_start_usec) / 1000.0])
	var slice_start_usec: int = Time.get_ticks_usec() if profile else 0
	var slice_first_row := 0
	var use_layers := bool(terrain_material().get_shader_parameter("use_layers"))
	_rock_tint = not use_layers
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var cw0 := PackedFloat32Array()
	var cw1 := PackedFloat32Array()
	var nv := S * S * 6
	verts.resize(nv)
	norms.resize(nv)
	cols.resize(nv)
	cw0.resize(nv * 4)
	cw1.resize(nv * 4)
	var buf := [verts, norms, cols, cw0, cw1]
	var vi := 0
	for z in S:
		for x in S:
			var i00 := z * (S + 1) + x
			var i10 := i00 + 1
			var i01 := i00 + S + 1
			var i11 := i01 + 1
			var p00 := Vector3(x, ch.heights[i00], z)
			var p10 := Vector3(x + 1, ch.heights[i10], z)
			var p01 := Vector3(x, ch.heights[i01], z + 1)
			var p11 := Vector3(x + 1, ch.heights[i11], z + 1)
			var cliff := ch.terrain[z * S + x] == Tiles.CLIFF
			var vt_ := vt if use_layers else vcol
			# split along the diagonal with the smaller height difference
			if absf(p00.y - p11.y) <= absf(p10.y - p01.y):
				vi = _tri(buf, vi, p00, p11, p10, i00, i11, i10, vt_, vw0, vw1, cliff)
				vi = _tri(buf, vi, p00, p01, p11, i00, i01, i11, vt_, vw0, vw1, cliff)
			else:
				vi = _tri(buf, vi, p00, p01, p10, i00, i01, i10, vt_, vw0, vw1, cliff)
				vi = _tri(buf, vi, p10, p01, p11, i10, i01, i11, vt_, vw0, vw1, cliff)
		if not immediate and (z + 1) % TERRAIN_ROWS_PER_SLICE == 0 and z + 1 < S:
			if profile:
				print("PERF_TERRAIN_ROWS key=(%d,%d) rows=%d-%d ms=%.2f" % [
					ch.cx, ch.cz, slice_first_row, z, (Time.get_ticks_usec() - slice_start_usec) / 1000.0])
			await get_tree().process_frame
			if not is_inside_tree() or build_generation != _terrain_build_generation or ch.version != terrain_version:
				return
			slice_first_row = z + 1
			slice_start_usec = Time.get_ticks_usec() if profile else 0
	if profile:
		print("PERF_TERRAIN_ROWS key=(%d,%d) rows=%d-%d ms=%.2f" % [
			ch.cx, ch.cz, slice_first_row, S - 1, (Time.get_ticks_usec() - slice_start_usec) / 1000.0])
	var finalize_start_usec: int = Time.get_ticks_usec() if profile else 0
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_CUSTOM0] = cw0
	arrays[Mesh.ARRAY_CUSTOM1] = cw1
	var flags := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	mesh.surface_set_material(0, terrain_material())
	_add_decor_surface(mesh)
	if not is_inside_tree() or build_generation != _terrain_build_generation or ch.version != terrain_version:
		return
	terrain_mi.mesh = mesh
	_rebuild_water()
	built_version = terrain_version
	if profile:
		print("PERF_TERRAIN_FINAL key=(%d,%d) ms=%.2f" % [ch.cx, ch.cz, (Time.get_ticks_usec() - finalize_start_usec) / 1000.0])


## Appends one terrain triangle (points counter-clockwise seen from above) in Godot's clockwise
## front-face order with a flat normal; steep faces shift their layer weights to rock.
## buf = [verts, normals, tints, weights0, weights1].
func _tri(buf: Array, vi: int, a: Vector3, b: Vector3, c: Vector3, ia: int, ib: int, ic: int,
		tint: PackedColorArray, w0: PackedColorArray, w1: PackedColorArray, cliff: bool) -> int:
	var nrm := (b - a).cross(c - a).normalized()
	var point_1: Vector3 = c
	var point_2: Vector3 = b
	var index_1: int = ic
	var index_2: int = ib
	if nrm.y < 0.0:
		nrm = -nrm
		point_1 = b
		point_2 = c
		index_1 = ib
		index_2 = ic
	var steep := clampf((0.8 - nrm.y) / 0.35, 0.0, 1.0)
	if cliff:
		steep = maxf(steep, 0.75)
	var verts: PackedVector3Array = buf[0]
	var norms: PackedVector3Array = buf[1]
	var cols: PackedColorArray = buf[2]
	var cw0: PackedFloat32Array = buf[3]
	var cw1: PackedFloat32Array = buf[4]
	for k in 3:
		var point: Vector3 = a
		var vid: int = ia
		if k == 1:
			point = point_1
			vid = index_1
		elif k == 2:
			point = point_2
			vid = index_2
		var ww0 := w0[vid].lerp(Color(0, 0, 0, 0), steep)
		var ww1 := w1[vid].lerp(Color(0, 1, 0, 0), steep)
		var tc := tint[vid]
		if steep > 0.0 and _rock_tint:
			tc = tc.lerp(Color("#8f887b"), steep)
		verts[vi + k] = point
		norms[vi + k] = nrm
		cols[vi + k] = tc.srgb_to_linear()
		var o := (vi + k) * 4
		cw0[o] = ww0.r
		cw0[o + 1] = ww0.g
		cw0[o + 2] = ww0.b
		cw0[o + 3] = ww0.a
		cw1[o] = ww1.r
		cw1[o + 1] = ww1.g
		cw1[o + 2] = ww1.b
		cw1[o + 3] = ww1.a
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
		if prop == "stump" or (prop in SPRITE_DECOR and not SpriteLibrary.prop_variants(prop).is_empty()):
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
	var profile := World.profile_chunks()
	var props_start_usec: int = Time.get_ticks_usec() if profile else 0
	built_res_version = ch.res_version
	for c in props_root.get_children():
		c.queue_free()
	var groups := {}  # "prop:variant" -> Array[Transform3D] (procedural meshes)
	var cards := {}  # sway -> Array of [position, size, atlas rect, tint]
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
			if prop in ["grass_tuft", "flowers", "reeds"] and not _keep_prop(prop, x, z):
				continue
			var h1 := float((variant * 37) % 100) / 100.0
			var jx := (h1 - 0.5) * 0.3
			var jz := (float((variant * 61) % 100) / 100.0 - 0.5) * 0.3
			var px := x + 0.5 + jx
			var pz := z + 0.5 + jz
			var scale := 0.85 + h1 * 0.3
			if prop in ["rock_large", "ore_iron", "ore_crystal"]:
				px = x + 0.5
				pz = z + 0.5
			var pos := Vector3(px, ch.height_local(px, pz), pz)
			if _add_card(cards, prop, variant, pos, scale):
				continue
			var vc := mini(PROP_VARIANTS_MAX, maxi(1, PropMeshes.variant_count(prop)))
			var xf := Transform3D(Basis(Vector3.UP, float(variant) * 0.73).scaled(Vector3.ONE * scale), pos)
			_group(groups, "%s:%d" % [prop, variant % vc], xf)
	for d: Array in ch.decor:
		var prop := str(d[0])
		var lx := float(d[1])
		var lz := float(d[2])
		var pos := Vector3(lx, ch.height_local(lx, lz), lz)
		var hv := int(absf(lx * 7.0 + lz * 13.0))
		if prop == "stump":
			if not _add_card(cards, prop, hv, pos, 1.0):
				_group(groups, "stump:0", Transform3D(Basis(Vector3.UP, float(d[3])), pos))
			continue
		if not (prop in SPRITE_DECOR):
			continue
		var i := clampi(int(lz), 0, S - 1) * S + clampi(int(lx), 0, S - 1)
		if ch.res_type[i] != Tiles.Res.NONE and prop in ["grass_tuft", "flowers"]:
			continue
		if prop in ["grass_tuft", "flowers", "reeds"] and not _keep_prop(prop, int(lx * 10.0), int(lz * 10.0)):
			continue
		if prop == "reeds":
			pos.y = maxf(pos.y, -0.25)
		var sc := float(d[4]) * (0.6 if prop == "rock_large" else 1.0)
		if prop in ["grass_tuft", "flowers"]:
			# painted clumps read as dots when small and evenly spread: fewer, larger ones
			if hv % 3 != 0:
				continue
			sc *= 1.5
		_add_card(cards, prop, hv, pos, sc)
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
	_build_cards(cards)
	if profile:
		print("PERF_PROPS key=(%d,%d) ms=%.2f" % [ch.cx, ch.cz, (Time.get_ticks_usec() - props_start_usec) / 1000.0])

func _keep_prop(prop: String, x: int, z: int) -> bool:
	var density := Quality.prop_density()
	if density >= 1.0:
		return true
	return RngUtil.hash01(ch.cx * 131 + x, ch.cz * 71 + z, prop.hash() & 0xFFFF) < density


func _group(groups: Dictionary, key: String, xf: Transform3D) -> void:
	if not groups.has(key):
		groups[key] = []
	(groups[key] as Array).append(xf)


## Queues a painted billboard for `prop` (false when the prop has no painting).
func _add_card(cards: Dictionary, prop: String, variant: int, pos: Vector3, scale: float) -> bool:
	var sprite_id := str(SPRITE_ALIAS.get(prop, prop))
	var variants := SpriteLibrary.prop_variants(sprite_id)
	if variants.is_empty():
		return false
	var v: Dictionary = variants[posmod(variant, variants.size())]
	var rect: Array = v["rect"]
	var h := float(v.get("height_m", 1.0)) * scale
	var size := Vector2(h * float(rect[2]) / float(rect[3]), h)
	var atlas := SpriteLibrary.prop_atlas_size()
	var uv := Color(float(rect[0]) / atlas.x, float(rect[1]) / atlas.y, float(rect[2]) / atlas.x, float(rect[3]) / atlas.y)
	var hv := RngUtil.hash01(ch.cx * 131 + int(pos.x * 10.0), ch.cz * 71 + int(pos.z * 10.0), 7)
	var tint := Color(0.94 + hv * 0.1, 0.95 + (1.0 - hv) * 0.08, 0.94 + hv * 0.06)
	if prop == "berry_bush_empty":
		tint = tint * Color(0.85, 0.9, 0.8)
	var sway := float(SWAY.get(sprite_id, 0.0))
	if not cards.has(sway):
		cards[sway] = []
	(cards[sway] as Array).append([pos, size, uv, tint])
	return true


## One MultiMesh of camera-facing cards per sway amount (trees, plants, rocks).
func _build_cards(cards: Dictionary) -> void:
	if cards.is_empty():
		return
	if _card_quad == null:
		_card_quad = QuadMesh.new()
		_card_quad.size = Vector2.ONE
	for sway: float in cards:
		var list: Array = cards[sway]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = _card_quad
		mm.instance_count = list.size()
		for k in list.size():
			var e: Array = list[k]
			var size: Vector2 = e[1]
			mm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3(size.x, size.y, 1.0)), e[0]))
			mm.set_instance_custom_data(k, e[2])
			mm.set_instance_color(k, e[3])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Cards_%d" % int(sway * 100.0)
		mmi.multimesh = mm
		mmi.material_override = SpriteLibrary.prop_material(sway)
		mmi.custom_aabb = AABB(Vector3(-8.0, -6.0, -8.0), Vector3(S + 16.0, 48.0, S + 16.0))
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if sway >= 0.06 or sway == 0.0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		props_root.add_child(mmi)
