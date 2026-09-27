class_name Game
extends Node3D
## Game scene root: creates or loads the World, advances the fixed simulation tick according to
## the game speed (pause / x1 / x2 / x4), and wires the view, camera, input and HUD together.

signal selection_changed
signal speed_changed(speed: int)
signal mode_changed(mode: String)
signal toast(text: String, kind: String)

const SPEEDS := [0, 1, 2, 4]
const MAX_TICKS_PER_FRAME := 12

var world: World
var view: WorldView
var rig: CameraRig
var input_ctl: InputController
var hud: Hud
var ai: AiEnrichment
var speed := 1
var _last_speed := 1
var _acc := 0.0

# selection
var sel_units: Array = []  # unit ids
var sel_squad := -1
var sel_building := -1
var sel_site := -1
var sel_loot := -1

var viewed_squad_id := -1

func _ready() -> void:
	var req := App.pending
	App.pending = {}
	match str(req.get("mode", "")):
		"load":
			var r := SaveGame.load_slot(int(req.get("slot", 1)))
			if r.has("world"):
				world = r["world"]
			else:
				push_warning("Load failed: %s" % r.get("error", "?"))
		"new":
			var p: Dictionary = req.get("player", {})
			world = NewGame.create(int(req.get("seed", 1)), p, str(req.get("company", "")), req.get("color", Color("#3a5da8")))
	if world == null:
		var seed := int(req.get("seed", 0))
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--world-seed="):
				seed = int(arg.substr(13))
		if seed == 0 and OS.get_environment("COGWILD_WORLD_SEED").is_valid_int():
			seed = int(OS.get_environment("COGWILD_WORLD_SEED"))
		if seed == 0:
			seed = randi() % 1000000 + 1
		world = NewGame.create(seed)
	_build_scene()


func _build_scene() -> void:
	view = WorldView.new()
	add_child(view)
	view.setup(world)
	rig = CameraRig.new()
	rig.name = "CameraRig"
	rig.world = world
	add_child(rig)
	rig.yaw_step_finished.connect(func() -> void:
		get_tree().call_group(BuildingVisual.BACK_VIEW_GROUP, &"update_card_view"))
	var home := world.home_pos()
	rig.focus(Vector3(home.x, 0, home.y), true)
	input_ctl = InputController.new()
	input_ctl.name = "Input"
	add_child(input_ctl)
	input_ctl.setup(self)
	hud = Hud.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(self)
	ai = AiEnrichment.new()
	ai.name = "AiEnrichment"
	add_child(ai)
	if ai.is_enabled():
		for u: Unit in world.player_people():
			ai.enrich_character(u.character)
		world.unit_added.connect(func(u: Unit) -> void:
			if u.is_person() and (u.is_player() or not u.named.is_empty()):
				ai.enrich_character(u.character))
		world.notified.connect(func(n: Dictionary) -> void:
			if n.has("item_uid"):
				for it: Dictionary in world.armory:
					if int(it.get("uid", 0)) == int(n["item_uid"]):
						ai.enrich_item(it))
		ai.enriched.connect(func(_k: String, _t: Variant) -> void: hud.info_panel.refresh(true))
	if world.squads.size() > 0:
		view_squad(world.squads[0].id)

func _exit_tree() -> void:
	if world:
		world.dispose()
	Caches.clear_all()


func set_speed(s: int) -> void:
	if s > 0:
		_last_speed = s
	speed = s
	view.set_time_scale(float(s))
	speed_changed.emit(s)


func toggle_pause() -> void:
	set_speed(0 if speed > 0 else _last_speed)


func speed_step(dir: int) -> void:
	var i := SPEEDS.find(speed)
	set_speed(SPEEDS[clampi(i + dir, 0, SPEEDS.size() - 1)])


func _process(delta: float) -> void:
	if speed > 0:
		_acc += minf(delta, 0.1) * speed
		var n := 0
		while _acc >= World.TICK and n < MAX_TICKS_PER_FRAME:
			world.tick()
			_acc -= World.TICK
			n += 1
		if n == MAX_TICKS_PER_FRAME:
			_acc = minf(_acc, World.TICK)
	else:
		# keep streaming chunks while paused so the view stays complete
		world.process_chunk_queue(1)
	view.alpha = clampf(_acc / World.TICK, 0.0, 1.0) if speed > 0 else 1.0
	view.cam_target = rig.target
	view.cam_zoom = rig.zoom
	_update_camera_bounds()


var _bounds_t := 0.0


func _update_camera_bounds() -> void:
	_bounds_t -= get_process_delta_time()
	if _bounds_t > 0.0:
		return
	_bounds_t = 1.0
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for key: Vector2i in world.chunks:
		var o := Vector2(key * World.S)
		mn = mn.min(o)
		mx = mx.max(o + Vector2(World.S, World.S))
	if mn.x < INF:
		rig.bounds = Rect2(mn + Vector2(8, 8), mx - mn - Vector2(16, 16))


func _unhandled_input(event: InputEvent) -> void:
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if event.is_action_pressed("toggle_pause"):
		toggle_pause()
	elif event.is_action_pressed("speed_up"):
		speed_step(1)
	elif event.is_action_pressed("speed_down"):
		speed_step(-1)
	elif event.is_action_pressed("quicksave"):
		quick_save(0)
	elif event.is_action_pressed("quickload"):
		App.load_game(0)
	elif event.is_action_pressed("focus_home"):
		focus_home()
	if event.is_action_pressed("squad_cycle") and not world.squads.is_empty():
		var idx := 0
		for i in world.squads.size():
			if world.squads[i].id == sel_squad:
				idx = (i + 1) % world.squads.size()
		select_squad(world.squads[idx].id)
		focus_selection()


# --- verification helpers (used by automated probe scenarios, e.g. tests/probe/*.json) ---------
## Number of buildings currently showing their painted back view.
func dbg_back_views_shown() -> int:
	var shown := 0
	for node: Node in get_tree().get_nodes_in_group(BuildingVisual.BACK_VIEW_GROUP):
		if (node as BuildingVisual)._showing_back:
			shown += 1
	return shown


func dbg_touch_press(index: int, pos: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = pos
	event.pressed = true
	input_ctl._handle_touch(event)


func dbg_touch_drag(index: int, pos: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = pos
	input_ctl._handle_touch(event)


func dbg_touch_release(index: int, pos: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = pos
	event.pressed = false
	input_ctl._handle_touch(event)

## Reveals the nearest site of a kind (generating its chunks) and returns its id, or -1.
func dbg_reveal_site(kind: String) -> int:
	var best := -1
	var best_d := INF
	for g: Dictionary in world.gen.sites.values():
		if str(g["kind"]) == kind:
			var d := Vector2(g["center"]).distance_to(world.home_pos())
			if d < best_d:
				best_d = d
				best = int(g["id"])
	if best < 0:
		return -1
	var c: Vector2i = world.gen.sites[best]["center"]
	var key := world.chunk_key(c)
	for oz in range(-1, 2):
		for ox in range(-1, 2):
			world.ensure_chunk(key + Vector2i(ox, oz))
	world.reveal(Vector2(c), 14.0)
	return best


## Orders a construction site of a type at the nearest valid spot around the hearth (the settlers
## still haul and build it). Returns the building id or -1.
func dbg_plan_building(type: String, min_r: int = 6) -> int:
	var d := DB.get_def("buildings", type)
	var size := Vector2i(int(d["size"][0]), int(d["size"][1]))
	var c := Vector2i(world.home_pos())
	for r in range(min_r, 30):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if absi(dx) != r and absi(dz) != r:
					continue
				var o := c + Vector2i(dx, dz) - size / 2
				if world.can_place(type, o) == "" and NewGame._clearance(world, o, size):
					return world.place_building(type, o).id
	return -1


## Probe helper: use real world terrain and construction APIs for crossing acceptance shots.
func dbg_prepare_crossing_probe(kind: String) -> bool:
	var feature := "river" if kind in ["swim", "bridge"] else "cliff"
	var base := world.chunk_key(world.gen.start_tile)
	for ring in range(7):
		for cz in range(-ring, ring + 1):
			for cx in range(-ring, ring + 1):
				if ring > 0 and absi(cx) != ring and absi(cz) != ring:
					continue
				var ch := world.ensure_chunk(base + Vector2i(cx, cz))
				for i in ch.terrain.size():
					var tile := Vector2i(ch.cx * ChunkData.S + i % ChunkData.S,
						ch.cz * ChunkData.S + i / ChunkData.S)
					var is_feature := world.gen.is_river_water(float(tile.x) + 0.5, float(tile.y) + 0.5) \
						and Tiles.is_water(ch.terrain[i]) if feature == "river" else ch.terrain[i] == Tiles.CLIFF
					if not is_feature:
						continue
					if kind == "stairs":
						var local_tile := tile - Vector2i(ch.cx * ChunkData.S, ch.cz * ChunkData.S)
						if local_tile.x < 4 or local_tile.y < 4 or local_tile.x >= ChunkData.S - 4 \
								or local_tile.y >= ChunkData.S - 4:
							continue
						var nearby_trees := 0
						for decor_item: Array in ch.decor:
							if not str(decor_item[0]).begins_with("tree_"):
								continue
							if absf(float(decor_item[1]) - float(local_tile.x) - 0.5) <= 3.5 \
									and absf(float(decor_item[2]) - float(local_tile.y) - 0.5) <= 3.5:
								nearby_trees += 1
						if nearby_trees > 1:
							continue
						var nearby_tree_resources := 0
						for dx in range(-3, 4):
							for dz in range(-3, 4):
								if Tiles.is_tree(world.res_at(tile + Vector2i(dx, dz))):
									nearby_tree_resources += 1
						if nearby_tree_resources > 0:
							continue
					if kind in ["swim", "climb"]:
						var sides := _dbg_crossing_probe_sides(tile, feature)
						if sides.size() != 2:
							continue
						world.reveal(Vector2(tile), 40.0)
						var path := world.find_path(Vector2(sides[0]) + Vector2(0.5, 0.5),
							Vector2(sides[1]) + Vector2(0.5, 0.5))
						var crosses := false
						for point: Vector2 in path:
							var step := Vector2i(floori(point.x), floori(point.y))
							if feature == "river":
								crosses = crosses or world.gen.is_river_water(float(step.x) + 0.5, float(step.y) + 0.5)
							else:
								crosses = crosses or world.terrain_at(step) == Tiles.CLIFF
						if not crosses:
							continue
						for unit: Unit in world.unit_list:
							if not unit.alive or unit.faction != "player" or unit.kind != "character":
								continue
							unit.pos = Vector2(tile) + Vector2(0.5, 0.5)
							var moved := false
							if kind == "swim":
								var squad := world.get_squad(unit.squad_id)
								if squad == null:
									continue
								world.squad_ai.order_squad(squad,
									{"type": "move", "pos": Vector2(sides[1]) + Vector2(0.5, 0.5)})
								moved = unit.moving
							else:
								moved = world.move_unit(unit, Vector2(sides[1]) + Vector2(0.5, 0.5))
							if moved:
								rig.zoom_goal = 12.0
								rig.focus(Vector3(tile.x + 0.5, world.ground_y(Vector2(tile) + Vector2(0.5, 0.5)),
									tile.y + 0.5), true)
								return true
					elif kind in ["bridge", "stairs"]:
						var line: Array[Vector2i] = [tile]
						for axis: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
							var trial: Array[Vector2i] = [tile]
							for step in range(1, 3):
								var next := tile + axis * step
								var matches := world.gen.is_river_water(float(next.x) + 0.5, float(next.y) + 0.5) \
									if feature == "river" else world.terrain_at(next) == Tiles.CLIFF
								if not matches:
									break
								trial.append(next)
							if trial.size() > line.size():
								line = trial
						if kind == "stairs" and line.size() < 3:
							continue
						world.reveal(Vector2(tile), 40.0)
						world.economy.add("wood", maxi(0, 300 - int(world.res.get("wood", 0))))
						world.economy.add("stone", maxi(0, 300 - int(world.res.get("stone", 0))))
						world.priorities["build"] = 3
						world.priorities["haul"] = 3
						world.priorities["gather"] = 0
						world.priorities["farm"] = 0
						world.priorities["operate"] = 0
						for worker: Unit in world.unit_list:
							if worker.faction == "player" and worker.kind == "character" and worker.squad_id < 0:
								world.colony.release(worker)
						var building_type := "bridge_segment" if kind == "bridge" else "cliff_stairs"
						var planned: Array[Vector2i] = []
						var can_build_line := true
						for segment: Vector2i in line:
							if world.can_place(building_type, segment) != "":
								can_build_line = false
								break
						if can_build_line:
							for segment: Vector2i in line:
								world.place_building(building_type, segment)
								planned.append(segment)
						if (kind == "stairs" and planned.size() >= 3) \
								or (kind != "stairs" and not planned.is_empty()):
							rig.zoom_goal = 12.0
							rig.focus(Vector3(tile.x + 0.5, world.ground_y(Vector2(tile) + Vector2(0.5, 0.5)),
								tile.y + 0.5), true)
							return true
	return false


func _dbg_crossing_probe_sides(tile: Vector2i, feature: String) -> Array[Vector2i]:
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	for direction: Vector2i in directions:
		var start := tile - direction
		var goal := tile + direction
		for depth in 4:
			var is_feature := world.gen.is_river_water(float(start.x) + 0.5, float(start.y) + 0.5) \
				if feature == "river" else world.terrain_at(start) == Tiles.CLIFF
			if not is_feature:
				break
			start -= direction
		for depth in 4:
			var is_feature := world.gen.is_river_water(float(goal.x) + 0.5, float(goal.y) + 0.5) \
				if feature == "river" else world.terrain_at(goal) == Tiles.CLIFF
			if not is_feature:
				break
			goal += direction
		world.ensure_chunk(world.chunk_key(start))
		world.ensure_chunk(world.chunk_key(goal))
		if world.is_walkable(start) and world.is_walkable(goal):
			return [start, goal]
	return []


func dbg_walk_on_crossing(building_type: String) -> bool:
	var buildings := world.buildings_of(building_type, true)
	if buildings.is_empty():
		return false
	var crossing: Building = buildings[0]
	for unit: Unit in world.unit_list:
		if unit.alive and unit.faction == "player" and unit.kind == "character":
			var origin := crossing.origin
			for direction: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var start := origin + direction
				world.ensure_chunk(world.chunk_key(start))
				if world.is_walkable(start):
					unit.pos = Vector2(start) + Vector2(0.5, 0.5)
					var target := Vector2(origin) + Vector2(0.5, 0.5)
					if not world.move_unit(unit, target):
						continue
					rig.zoom_goal = 12.0
					rig.focus(Vector3(origin.x + 0.5, world.ground_y(target), origin.y + 0.5), true)
					return Vector2i(floori(unit.goal.x), floori(unit.goal.y)) == origin
	return false


func dbg_stage_unit_on_crossing(building_type: String) -> bool:
	var buildings := world.buildings_of(building_type, true)
	if buildings.is_empty():
		return false
	var crossing: Building = buildings[buildings.size() / 2]
	var deck_pos := Vector2(crossing.origin) + Vector2(0.5, 0.5)
	for unit: Unit in world.unit_list:
		if not unit.alive or unit.faction != "player" or unit.kind != "character":
			continue
		unit.pos = deck_pos
		unit.prev_pos = deck_pos
		unit.path = PackedVector2Array()
		unit.path_i = 0
		unit.moving = false
		unit.goal = deck_pos
		unit.state = Unit.State.IDLE
		rig.zoom_goal = 12.0
		rig.focus(Vector3(deck_pos.x, world.ground_y(deck_pos), deck_pos.y), true)
		return true
	return false


## Centres the camera on the nearest site of a kind.
func dbg_focus_site(kind: String) -> void:
	var sid := dbg_reveal_site(kind)
	if sid >= 0:
		rig.focus(Vector3(world.gen.sites[sid]["center"].x, 0, world.gen.sites[sid]["center"].y), true)


## Sends squad 0 to attack the nearest site of a kind. Returns the site id.
func dbg_attack_site(kind: String) -> int:
	var sid := dbg_reveal_site(kind)
	if sid >= 0 and not world.squads.is_empty():
		world.squad_ai.order_squad(world.squads[0], {"type": "attack", "site": sid, "pos": Vector2(world.gen.sites[sid]["center"])})
		select_squad(world.squads[0].id)
	return sid


## Places squad 0 just outside the nearest site of a kind (probes of village trade and diplomacy)
## and focuses the camera there. Returns the site id.
func dbg_station_squad_at(kind: String) -> int:
	var sid := dbg_reveal_site(kind)
	if sid < 0 or world.squads.is_empty():
		return sid
	var c := Vector2(world.gen.sites[sid]["center"]) + Vector2(0.5, 0.5)
	var i := 0
	for id: int in world.squads[0].members:
		var u := world.get_unit(id)
		var t := world.nearest_walkable(Vector2i(c + Vector2(6.0 + float(i % 3), 2.0 + float(i / 3))), 6)
		if u and t.x != -99999:
			world.stop_unit(u)
			u.pos = Vector2(t) + Vector2(0.5, 0.5)
		i += 1
	world.reveal(c, 20.0)
	rig.focus(Vector3(c.x, 0, c.y), true)
	return sid


func quick_save(slot: int) -> void:
	var err := SaveGame.save(world, slot)
	if err == "":
		toast.emit(Loc.t("Saved (slot %s).") % Loc.t("quick" if slot == 0 else str(slot)), "good")
	else:
		toast.emit(Loc.t("Save failed: %s") % Loc.t(err), "bad")


func focus_home() -> void:
	var h := world.home_pos()
	rig.focus(Vector3(h.x, 0, h.y))


func focus_pos(p: Vector2) -> void:
	rig.focus(Vector3(p.x, 0, p.y))


# --- selection -----------------------------------------------------------------------------

func clear_selection() -> void:
	sel_units.clear()
	sel_squad = -1
	sel_building = -1
	sel_site = -1
	sel_loot = -1
	_refresh_rings()
	selection_changed.emit()

func select_units(ids: Array) -> void:
	sel_units = ids.duplicate()
	sel_building = -1
	sel_site = -1
	sel_loot = -1
	sel_squad = -1
	# A squad's member click updates the persistent viewed squad; unrelated selections do not.
	if not ids.is_empty():
		var sq := -2
		for id: int in ids:
			var u := world.get_unit(id)
			if u == null:
				continue
			if sq == -2:
				sq = u.squad_id
			elif sq != u.squad_id:
				sq = -1
		if sq >= 0:
			sel_squad = sq
			viewed_squad_id = sq
	_refresh_rings()
	selection_changed.emit()

func select_squad(id: int) -> void:
	var s := world.get_squad(id)
	if s == null:
		return
	sel_units = s.members.duplicate()
	sel_squad = id
	viewed_squad_id = id
	sel_building = -1
	sel_site = -1
	sel_loot = -1
	_refresh_rings()
	selection_changed.emit()


func view_squad(id: int) -> void:
	if world.get_squad(id) == null:
		return
	viewed_squad_id = id
	selection_changed.emit()




func select_building(id: int) -> void:
	clear_selection()
	sel_building = id
	selection_changed.emit()


func select_site(id: int) -> void:
	clear_selection()
	sel_site = id
	selection_changed.emit()
func select_loot(id: int) -> void:
	if not world.loot_bags.has(id):
		return
	clear_selection()
	sel_loot = id
	selection_changed.emit()


## Shows a squad member in the details panel while keeping the whole squad selected.
func focus_member(id: int) -> void:
	var u := world.get_unit(id)
	if u == null:
		return
	if u.squad_id >= 0:
		if sel_squad != u.squad_id:
			select_squad(u.squad_id)
		else:
			viewed_squad_id = u.squad_id
	sel_units.erase(id)
	sel_units.push_front(id)
	_refresh_rings()
	selection_changed.emit()


## The unit shown in the character panel (first selected, or the leader of the squad).
func focus_unit() -> Unit:
	for id: int in sel_units:
		var u := world.get_unit(id)
		if u and u.alive:
			return u
	return null


func selected_units() -> Array:
	var out: Array = []
	for id: int in sel_units:
		var u := world.get_unit(id)
		if u and u.alive and u.is_player():
			out.append(u)
	return out


func focus_selection() -> void:
	var us := selected_units()
	if us.is_empty():
		return
	var c := Vector2.ZERO
	for u: Unit in us:
		c += u.pos
	focus_pos(c / us.size())


func _refresh_rings() -> void:
	for id: int in view.unit_views:
		var v: UnitView = view.unit_views[id]
		v.selected = sel_units.has(id)
		var s := world.get_squad(v.u.squad_id) if v.u.squad_id >= 0 else null
		v.squad_color = s.color() if (s and sel_squad == s.id) else Color.TRANSPARENT


func notify_mode(m: String) -> void:
	mode_changed.emit(m)
