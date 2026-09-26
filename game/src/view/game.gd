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
		select_squad(world.squads[0].id)


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
	for i in 4:
		if event.is_action_pressed("squad_%d" % (i + 1)) and i < world.squads.size():
			select_squad(world.squads[i].id)
			focus_selection()
	if event.is_action_pressed("squad_cycle") and not world.squads.is_empty():
		var idx := 0
		for i in world.squads.size():
			if world.squads[i].id == sel_squad:
				idx = (i + 1) % world.squads.size()
		select_squad(world.squads[idx].id)
		focus_selection()


# --- verification helpers (used by automated probe scenarios, e.g. tests/probe/*.json) ---------

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


func quick_save(slot: int) -> void:
	var err := SaveGame.save(world, slot)
	if err == "":
		toast.emit("Saved (slot %s)." % ("quick" if slot == 0 else str(slot)), "good")
	else:
		toast.emit("Save failed: " + err, "bad")


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
	_refresh_rings()
	selection_changed.emit()


func select_units(ids: Array) -> void:
	sel_units = ids.duplicate()
	sel_building = -1
	sel_site = -1
	sel_squad = -1
	# a selection that is exactly one squad selects that squad
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
		if sq >= 0 and ids.size() == 1:
			sel_squad = sq
		elif sq >= 0:
			sel_squad = sq
	_refresh_rings()
	selection_changed.emit()


func select_squad(id: int) -> void:
	var s := world.get_squad(id)
	if s == null:
		return
	sel_units = s.members.duplicate()
	sel_squad = id
	sel_building = -1
	sel_site = -1
	_refresh_rings()
	selection_changed.emit()


func select_building(id: int) -> void:
	clear_selection()
	sel_building = id
	selection_changed.emit()


func select_site(id: int) -> void:
	clear_selection()
	sel_site = id
	selection_changed.emit()


## Shows a squad member in the details panel while keeping the whole squad selected.
func focus_member(id: int) -> void:
	var u := world.get_unit(id)
	if u == null:
		return
	if u.squad_id >= 0 and sel_squad != u.squad_id:
		select_squad(u.squad_id)
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
