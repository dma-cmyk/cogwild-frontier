class_name WorldView
extends Node3D
## Presents the World: chunk terrain/props, player buildings, site structures, units, loot,
## projectiles, crops, zone outlines, fog-of-war texture and the day/night light. Reads the sim
## and listens to its signals; never changes simulation state.

const FIRST_VIEW_CHUNKS := 2  # chunk radius around home built synchronously at setup
const SITE_STYLE := {"bandit_camp": "bandit", "machine_outpost": "ancient", "trade_post": "merchant",
	"village": "neutral",
	"wanderer_camp": "neutral", "ruins": "neutral", "wreck": "neutral", "crystal_grove": "neutral", "ore_field": "neutral"}

var w: World
var chunk_views: Dictionary = {}
var unit_views: Dictionary = {}
var building_views: Dictionary = {}  # id -> BuildingVisual
var site_views: Dictionary = {}  # site id -> Node3D
var loot_views: Dictionary = {}
var sun: DirectionalLight3D
var env: WorldEnvironment
var fog_tex: ImageTexture
var alpha := 1.0
var show_zones := false
var ghost: Node3D
var _chunk_queue: Array = []
var _chunk_building := false
var _initial_chunk_keys: Dictionary = {}
var _crops_dirty := true
var _crop_root: Node3D
var _zone_mesh: MeshInstance3D
var _squad_markers: SquadMarkers
var _zones_dirty := true
var _fog_t := 0.0
var _projectiles: Array = []
var _time_scale := 1.0
var _pending_site_visuals: Array[int] = []
var _queued_site_visuals: Dictionary = {}
var _pending_unit_views: Array[int] = []
var _queued_unit_views: Dictionary = {}
var _initializing_views := true


func setup(world: World) -> void:
	w = world
	name = "WorldView"
	sun = LookDev.make_sun()
	sun.add_to_group("quality_sun")
	add_child(sun)
	env = WorldEnvironment.new()
	env.environment = LookDev.make_environment()
	add_child(env)
	Quality.level_changed.connect(_on_quality_changed)
	_apply_quality(Quality.level())
	_crop_root = Node3D.new()
	_crop_root.name = "Crops"
	add_child(_crop_root)
	_zone_mesh = MeshInstance3D.new()
	_zone_mesh.name = "Zones"
	_zone_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_zone_mesh)
	_squad_markers = SquadMarkers.new()
	add_child(_squad_markers)
	_squad_markers.setup(w)
	fog_tex = ImageTexture.create_from_image(w.fog_image)
	RenderingServer.global_shader_parameter_set("fog_tex", fog_tex)
	RenderingServer.global_shader_parameter_set("fog_rect", Vector4(w.gen.min_tile, w.gen.min_tile, w.W, w.W))
	RenderingServer.global_shader_parameter_set("fog_enabled", 1.0)
	# Warm the shared resource/loot atlas during loading, not on the first hauling frame.
	SpriteLibrary.icon_texture("res_wood")
	SpriteLibrary.icon_image("res_wood", 32)
	w.chunk_ready.connect(_on_chunk_ready)
	w.chunk_changed.connect(_on_chunk_changed)
	w.unit_added.connect(_add_unit)
	w.unit_removed.connect(_remove_unit)
	w.unit_changed.connect(_on_unit_changed)
	w.building_added.connect(_add_building)
	w.building_removed.connect(_remove_building)
	w.building_changed.connect(_on_building_changed)
	w.site_changed.connect(_on_site_changed)
	w.loot_added.connect(_add_loot)
	w.loot_removed.connect(_remove_loot)
	w.fx.connect(_on_fx)
	w.projectile_fired.connect(_on_projectile)
	w.farm_changed.connect(func(_t: Vector2i) -> void: _crops_dirty = true)
	w.zones_changed.connect(func() -> void: _zones_dirty = true)
	# Build the initial terrain synchronously during loading. Exploration builds are serialized:
	# only one chunk coroutine may consume its row slice on any frame.
	var home_key := w.chunk_key(Vector2i(w.home_pos()))
	var keys: Array = w.chunks.keys()
	_initial_chunk_keys.clear()
	for key: Vector2i in keys:
		_initial_chunk_keys[key] = true
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - home_key).length_squared() < (b - home_key).length_squared())
	# Initial chunk data is already complete, so adjacent meshes can sample their borders on first build.
	for key: Vector2i in keys:
		if absi(key.x - home_key.x) <= FIRST_VIEW_CHUNKS and absi(key.y - home_key.y) <= FIRST_VIEW_CHUNKS:
			_build_chunk(key, true)
		elif not _chunk_queue.has(key):
			_chunk_queue.append(key)
	for b: Building in w.buildings.values():
		_add_building(b)
	for sid: int in w.sites:
		_on_site_changed(sid)
	for u: Unit in w.unit_list:
		_add_unit(u)
	for bag: Dictionary in w.loot_bags.values():
		_add_loot(bag)
	_initializing_views = false


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set("fog_enabled", 0.0)
	RenderingServer.global_shader_parameter_set("night_amount", 0.0)


# --- chunks --------------------------------------------------------------------------------

func _on_chunk_ready(key: Vector2i) -> void:
	if not _chunk_queue.has(key):
		_chunk_queue.append(key)


func _on_chunk_changed(key: Vector2i) -> void:
	if chunk_views.has(key) and not _chunk_queue.has(key):
		_chunk_queue.append(key)


func _build_chunk(key: Vector2i, immediate: bool = false) -> void:
	var ch: ChunkData = w.chunks.get(key)
	if ch == null:
		return
	var is_initial_chunk := _initial_chunk_keys.has(key)
	_initial_chunk_keys.erase(key)
	if chunk_views.has(key):
		await (chunk_views[key] as ChunkView).refresh()
		return
	var cv := ChunkView.new()
	add_child(cv)
	chunk_views[key] = cv
	await cv.setup(w, ch, immediate)
	# neighbours re-blend their border colours once
	if is_initial_chunk:
		return
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: ChunkView = chunk_views.get(key + d)
		if n:
			n.built_version = -1
			if not _chunk_queue.has(key + d):
				_chunk_queue.append(key + d)


# --- buildings & sites -----------------------------------------------------------------------

func _add_building(b: Building) -> void:
	var v := BuildingVisuals.create(b.type, "frontier" if b.faction == "player" else "neutral", b.variant, b.level)
	v.name = "Building_%d" % b.id
	var c := b.center()
	v.position = Vector3(c.x, w.ground_y(c), c.y)
	v.rotation.y = b.rot * PI * 0.5
	add_child(v)
	v.set_construction(b.progress)
	building_views[b.id] = v
	v.set_meta("level", b.level)


func _on_quality_changed(level: String) -> void:
	_apply_quality(level)


func _apply_quality(_level: String) -> void:
	if sun != null:
		sun.shadow_enabled = Quality.shadows_enabled()
		var shadow_distance := 60.0 if _level == "low" else (100.0 if _level == "medium" else 150.0)
		sun.directional_shadow_max_distance = shadow_distance
	if not chunk_views.is_empty():
		var first_chunk: ChunkView = chunk_views.values()[0]
		first_chunk.apply_terrain_detail(Quality.terrain_detail_enabled())
	for key: Vector2i in chunk_views:
		(chunk_views[key] as ChunkView).built_res_version = -1
		if not _chunk_queue.has(key):
			_chunk_queue.append(key)


func _remove_building(b: Building) -> void:
	var v: Node = building_views.get(b.id)
	if v:
		v.queue_free()
		building_views.erase(b.id)


func _on_building_changed(b: Building) -> void:
	var v: BuildingVisual = building_views.get(b.id)
	if v == null:
		return
	if int(v.get_meta("level", 1)) != b.level:
		_remove_building(b)
		_add_building(b)
		return
	v.set_construction(b.progress)
	var c := b.center()
	v.position.y = w.ground_y(c)


func _on_site_changed(sid: int) -> void:
	var st: Dictionary = w.sites.get(sid, {})
	var g: Dictionary = w.gen.sites.get(sid, {})
	if st.is_empty() or g.is_empty():
		return
	var root: Node3D = site_views.get(sid)
	if root == null:
		root = Node3D.new()
		root.name = "Site_%d" % sid
		add_child(root)
		site_views[sid] = root
	var list: Array = (g.get("structures", []) as Array) + (st.get("extra", []) as Array)
	if root.get_child_count() < list.size() and not _queued_site_visuals.has(sid):
		_pending_site_visuals.append(sid)
		_queued_site_visuals[sid] = Engine.get_process_frames()


func _build_next_site_visual() -> void:
	if _pending_site_visuals.is_empty():
		return
	var queued_sid: int = _pending_site_visuals[0]
	if int(_queued_site_visuals.get(queued_sid, -1)) >= Engine.get_process_frames():
		return
	var sid: int = _pending_site_visuals.pop_front()
	_queued_site_visuals.erase(sid)
	var st: Dictionary = w.sites.get(sid, {})
	var g: Dictionary = w.gen.sites.get(sid, {})
	var root: Node3D = site_views.get(sid)
	if st.is_empty() or g.is_empty() or root == null:
		return
	var list: Array = (g.get("structures", []) as Array) + (st.get("extra", []) as Array)
	var i := root.get_child_count()
	if i >= list.size():
		return
	var s: Dictionary = list[i]
	var sz: Vector2i = s["size"]
	var o: Vector2i = s["origin"]
	var rot := int(s.get("rot", 0))
	var v := BuildingVisuals.create(str(s["type"]), str(SITE_STYLE.get(str(st["kind"]), "neutral")), sid * 31 + i, 1)
	var c := Vector2(o) + Vector2(sz) * 0.5
	v.position = Vector3(c.x, w.height_at(c), c.y)
	v.rotation.y = rot * PI * 0.5
	root.add_child(v)
	v.set_construction(1.0)
	v.set_active(str(s["type"]) in ["campfire", "machine_foundry", "machine_spire"])
	if root.get_child_count() < list.size() and not _queued_site_visuals.has(sid):
		_pending_site_visuals.append(sid)
		_queued_site_visuals[sid] = Engine.get_process_frames()
# --- units ---------------------------------------------------------------------------------

func _add_unit(u: Unit) -> void:
	if unit_views.has(u.id) or _queued_unit_views.has(u.id):
		return
	if not _initializing_views:
		_pending_unit_views.append(u.id)
		_queued_unit_views[u.id] = Engine.get_process_frames()
		return
	_build_unit_view(u)


func _build_unit_view(u: Unit) -> void:
	var v := UnitView.new()
	add_child(v)
	v.setup(w, u)
	unit_views[u.id] = v


func _build_next_unit_view() -> void:
	if _pending_unit_views.is_empty():
		return
	var queued_id: int = _pending_unit_views[0]
	if int(_queued_unit_views.get(queued_id, -1)) >= Engine.get_process_frames():
		return
	var id: int = _pending_unit_views.pop_front()
	_queued_unit_views.erase(id)
	var u := w.get_unit(id)
	if u != null and u.alive and not unit_views.has(id):
		_build_unit_view(u)


func _remove_unit(u: Unit) -> void:
	_queued_unit_views.erase(u.id)
	var v: Node = unit_views.get(u.id)
	if v:
		v.queue_free()
		unit_views.erase(u.id)


func _on_unit_changed(u: Unit) -> void:
	var v: UnitView = unit_views.get(u.id)
	if v:
		v.rebuild_visual()


# --- loot ----------------------------------------------------------------------------------

func _add_loot(bag: Dictionary) -> void:
	var n := Node3D.new()
	var tier := int(bag.get("tier", -1))
	var painted := SpriteLibrary.icon_texture("loot_chest" if tier >= 3 else "loot_sack")
	if painted != null:
		var card := Sprite3D.new()
		card.texture = painted
		card.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		card.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		card.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		card.shaded = true
		card.pixel_size = 0.75 / float(painted.get_width())
		card.offset = Vector2(0.0, painted.get_height() * 0.45)
		n.add_child(card)
	else:
		var mi := MeshInstance3D.new()
		mi.mesh = PropMeshes.get_mesh("loot_bag", 0)
		n.add_child(mi)
	if tier >= 3:
		var k := MeshKit.new()
		var col := Icons.quality_color(Combat.quality_for_tier(tier))
		k.sphere(Vector3(0, 0.9, 0), 0.12, MeshKit.glow(col, 0.9), 6, 4)
		var g := MeshInstance3D.new()
		g.mesh = k.build()
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(g)
	var p: Vector2 = bag["pos"]
	n.position = Vector3(p.x, w.ground_y(p), p.y)
	add_child(n)
	loot_views[int(bag["id"])] = n


func _remove_loot(id: int) -> void:
	var n: Node = loot_views.get(id)
	if n:
		n.queue_free()
		loot_views.erase(id)


# --- effects -------------------------------------------------------------------------------

func _on_fx(kind: StringName, pos: Vector3, color: Color) -> void:
	if not _visible_pos(Vector2(pos.x, pos.z)):
		return
	var kind_text := str(kind)
	if kind_text.begins_with("combat_damage|") or kind_text.begins_with("combat_heal|") or kind_text.begins_with("combat_ability|") or kind_text.begins_with("combat_tactic|") or kind_text.begins_with("combat_miss|") or kind_text == "combat_miss":
		Vfx.spawn_combat_text(self, kind, pos, color)
		return
	if kind_text == "explosion_small":
		var scene: Node = get_tree().current_scene
		if scene != null:
			var rig: CameraRig = scene.get("rig") as CameraRig
			if rig != null and rig.cam != null and Vector2(rig.target.x - pos.x, rig.target.z - pos.z).length() <= 18.0:
				var screen_pos := rig.cam.unproject_position(pos)
				if rig.cam.get_viewport().get_visible_rect().has_point(screen_pos):
					rig.request_shake(0.18, 0.16)
	Vfx.spawn(self, kind, pos, color)


func _visible_pos(p: Vector2) -> bool:
	return w.is_explored(Vector2i(int(floor(p.x)), int(floor(p.y))))


func _on_projectile(from: Vector3, to: Vector3, kind: String, flight: float) -> void:
	if not _visible_pos(Vector2(to.x, to.z)) and not _visible_pos(Vector2(from.x, from.z)):
		return
	var mi := MeshInstance3D.new()
	mi.mesh = PropMeshes.get_mesh(kind if PropMeshes.variant_count(kind) > 0 else "arrow", 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_projectiles.append({"node": mi, "from": from, "to": to, "t": 0.0, "dur": maxf(0.05, flight),
		"arc": 0.0 if kind in ["bullet", "blaster_bolt"] else clampf(from.distance_to(to) * 0.08, 0.2, 2.5)})


func set_time_scale(s: float) -> void:
	_time_scale = s


func _update_projectiles(delta: float) -> void:
	for p: Dictionary in _projectiles.duplicate():
		p["t"] = float(p["t"]) + delta * _time_scale
		var k := clampf(float(p["t"]) / float(p["dur"]), 0.0, 1.0)
		var a: Vector3 = p["from"]
		var b: Vector3 = p["to"]
		var pos := a.lerp(b, k) + Vector3(0, sin(k * PI) * float(p["arc"]), 0)
		var nxt := a.lerp(b, minf(1.0, k + 0.05)) + Vector3(0, sin(minf(1.0, k + 0.05) * PI) * float(p["arc"]), 0)
		var node: Node3D = p["node"]
		node.position = pos
		if nxt.distance_to(pos) > 0.001:
			node.look_at(nxt, Vector3.UP, true)
		if k >= 1.0:
			node.queue_free()
			_projectiles.erase(p)


# --- crops & zones -------------------------------------------------------------------------

func _rebuild_crops() -> void:
	_crops_dirty = false
	for c in _crop_root.get_children():
		c.queue_free()
	var groups := {}
	for t: Vector2i in w.farm:
		var f: Dictionary = w.farm[t]
		var st := int(f["stage"])
		var c := Vector2(t) + Vector2(0.5, 0.5)
		var y := w.height_at(c)
		var base := Transform3D(Basis(), Vector3(c.x, y, c.y))
		if st >= 1:
			_group(groups, "tilled_soil", base)
		if st >= 2:
			var crop := str(f.get("crop", "wheat"))
			var stage := 3 if st == 3 else clampi(int(float(f["growth"]) * 3.0), 0, 2)
			_group(groups, "crop_%s_%d" % [crop, stage], base)
	for key: String in groups:
		var list: Array = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = PropMeshes.get_mesh(key, 0)
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_crop_root.add_child(mmi)


func _group(groups: Dictionary, key: String, xf: Transform3D) -> void:
	if not groups.has(key):
		groups[key] = []
	(groups[key] as Array).append(xf)


const ZONE_COLORS := {"logging": Color("#7fd36b"), "mining": Color("#c9b7a0"), "forage": Color("#ff7a9a"), "farm": Color("#e8c45a")}


func _rebuild_zones() -> void:
	_zones_dirty = false
	if not show_zones or w.zones.is_empty():
		_zone_mesh.mesh = null
		return
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.render_priority = 5
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	for z: Dictionary in w.zones:
		var r: Rect2i = z["rect"]
		var col: Color = ZONE_COLORS.get(str(z["type"]), Color.WHITE)
		var pts := [Vector2(r.position), Vector2(r.end.x, r.position.y), Vector2(r.end), Vector2(r.position.x, r.end.y)]
		for i in 4:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % 4]
			var n := int(ceil(a.distance_to(b)))
			for k in n:
				var p0 := a.lerp(b, float(k) / n)
				var p1 := a.lerp(b, float(k + 1) / n)
				im.surface_set_color(col)
				im.surface_add_vertex(Vector3(p0.x, maxf(w.height_at(p0), 0.0) + 0.08, p0.y))
				im.surface_set_color(col)
				im.surface_add_vertex(Vector3(p1.x, maxf(w.height_at(p1), 0.0) + 0.08, p1.y))
	im.surface_end()
	_zone_mesh.mesh = im


func set_show_zones(on: bool) -> void:
	if show_zones != on:
		show_zones = on
		_zones_dirty = true


# --- frame ---------------------------------------------------------------------------------

func _build_queued_chunk() -> void:
	_chunk_building = true
	await _build_chunk(_chunk_queue.pop_front())
	_chunk_building = false


func _process(delta: float) -> void:
	# A streamed chunk runs one row slice per frame; unit and site visuals share the remaining
	# frames so camps, villages and newcomers still appear while the explorer keeps revealing land.
	# Only the frame that starts a new chunk (its tile preparation) skips visual construction.
	var chunk_started := false
	if not _chunk_building and not _chunk_queue.is_empty():
		_build_queued_chunk()
		chunk_started = true
	if not chunk_started:
		var unit_pending := not _pending_unit_views.is_empty()
		var site_pending := not _pending_site_visuals.is_empty()
		var unit_first := Engine.get_process_frames() % 2 == 0
		if unit_pending and (not site_pending or unit_first):
			_build_next_unit_view()
		elif site_pending:
			_build_next_site_visual()
		elif unit_pending:
			_build_next_unit_view()
	for v: UnitView in unit_views.values():
		v.sync(alpha, delta)
	for b: Building in w.buildings.values():
		var bv: BuildingVisual = building_views.get(b.id)
		if bv:
			var active := b.is_built() and (b.active or b.active_t > 0.0 or b.type in ["hearth", "windmill"])
			bv.set_active(active)
	for sid: int in site_views:
		var st: Dictionary = w.sites.get(sid, {})
		(site_views[sid] as Node3D).visible = w.is_explored(st.get("center", Vector2i.ZERO))
	for id: int in loot_views:
		var node: Node3D = loot_views[id]
		node.rotation.y += delta * 1.5
	_update_projectiles(delta)
	_cull_t -= delta
	if _cull_t <= 0.0:
		_cull_t = 0.25
		_cull_chunks()
	if _crops_dirty:
		_rebuild_crops()
	if _zones_dirty:
		_rebuild_zones()
	_fog_t -= delta
	if w.fog_dirty and _fog_t <= 0.0:
		_fog_t = 0.25
		w.refresh_fog_image()
		fog_tex.update(w.fog_image)
	if _squad_markers != null:
		_squad_markers.refresh(w)
	_update_light()

var _cull_t := 0.0
var cam_target := Vector3.ZERO
var cam_zoom := LookDev.ZOOM_DEFAULT


## Hides chunks far outside the camera view: frustum culling already skips them for the main
## pass, but this also keeps them out of the shadow pass and saves their per-frame cost.
func _cull_chunks() -> void:
	var c := Vector2(cam_target.x, cam_target.z)
	var reach := cam_zoom * 1.35 + 34.0
	for key: Vector2i in chunk_views:
		var cv: ChunkView = chunk_views[key]
		var cc := Vector2(key * ChunkData.S) + Vector2(ChunkData.S, ChunkData.S) * 0.5
		cv.visible = cc.distance_to(c) < reach


func _update_light() -> void:
	var night := w.night_amount()
	var h := w.hour()
	RenderingServer.global_shader_parameter_set("night_amount", night)
	var day_col := Color("#fff0d4")
	var dusk_col := Color("#ffb070")
	var dusk := clampf(1.0 - absf(h - 19.0) / 2.0, 0.0, 1.0) + clampf(1.0 - absf(h - 6.5) / 1.5, 0.0, 1.0)
	sun.light_color = day_col.lerp(dusk_col, clampf(dusk, 0.0, 1.0) * 0.7).lerp(Color("#8fa6e0"), night)
	sun.light_energy = lerpf(1.2, 0.45, night)
	var e := env.environment
	e.ambient_light_color = Color("#b4c0d6").lerp(Color("#7080b0"), night)
	e.ambient_light_energy = lerpf(0.62, 0.55, night)
	e.background_color = Color("#8ea6bb").lerp(Color("#1c2438"), night)

func _ready() -> void:
	var cache_sweep_timer := Timer.new()
	cache_sweep_timer.name = "SpriteCacheSweep"
	cache_sweep_timer.wait_time = 5.0
	cache_sweep_timer.timeout.connect(_prune_sprite_cache)
	add_child(cache_sweep_timer)
	cache_sweep_timer.start()


func _prune_sprite_cache() -> void:
	SpriteLibrary.prune_unused(get_tree().root)
