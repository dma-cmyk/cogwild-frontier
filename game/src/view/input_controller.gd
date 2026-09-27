class_name InputController
extends Node
## Mouse & keyboard interaction with the world: hover, click and box selection, right-click
## context orders, targeted commands from the command bar, building placement with a validity
## preview, and zone painting.

const PICK_PX := 26.0
const DRAG_PX := 8.0
const ORDER_LABEL := {"move": "Move", "attack": "Attack", "defend": "Defend", "explore": "Explore", "patrol": "Patrol", "escort": "Escort"}

var g: Game
var mode := ""  # "" | "cmd:<type>" | "build:<type>" | "zone:<type>"
var hover_unit: Unit
var hover_info := ""
var hover_ground: Variant = null
var drag_start := Vector2.ZERO
var dragging := false
var drag_rect := Rect2()
var zone_start: Variant = null
var _left_down := false
var _ghost: Node3D
var _ghost_type := ""
var _foot: MeshInstance3D
var _foot_mats := {}
var _last_reason := ""
var box_select_mode := false
var _touches: Dictionary = {}
var _touch_start := Vector2.ZERO
var _touch_last := Vector2.ZERO
var _touch_id := -1
var _pinch_distance := 0.0
var _twist_last_angle := 0.0
var _twist_accum := 0.0
var _twist_fired := false
var _touch_moved := false
var _touch_long_pressed := false
var _touch_elapsed := 0.0
var _touch_build_point: Variant = null


## True while a finger rests on the world long enough to show what is under it.
func is_long_pressing() -> bool:
	return _touch_id >= 0 and _touch_long_pressed


func confirm_touch_build() -> void:
	if not mode.begins_with("build:") or not (_touch_build_point is Vector3):
		return
	hover_ground = _touch_build_point
	_place(mode.substr(6), false)


func cancel_touch_mode() -> void:
	if mode != "":
		set_mode("")


var _wall_start: Variant = null


func setup(game: Game) -> void:
	g = game
	process_priority = -100  # Cancel orders before focused popups consume Escape.
	_foot = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE
	_foot.mesh = pm
	_foot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_foot.visible = false
	g.add_child(_foot)


func _mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _foot_mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = c
		m.no_depth_test = true
		m.render_priority = 4
		_foot_mats[key] = m
	return _foot_mats[key]


func set_mode(m: String) -> void:
	mode = m
	_touch_build_point = null
	_left_down = false
	zone_start = null
	_wall_start = null
	if _ghost:
		_ghost.queue_free()
		_ghost = null
		_ghost_type = ""
	_foot.visible = false
	g.view.set_show_zones(m.begins_with("zone:"))
	g.notify_mode(m)


# --- picking -------------------------------------------------------------------------------

var _mouse_pos := Vector2(-1, -1)


## Mouse position tracked from input events (works with real and synthetic input alike).
func _mouse() -> Vector2:
	return _mouse_pos if _mouse_pos.x >= 0.0 else g.get_viewport().get_mouse_position()


func _input(event: InputEvent) -> void:
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if event.is_action_pressed("cancel") and mode != "":
		var preserve_picker := g.hud != null and g.hud.squad_panel.picker_open()
		set_mode("")
		if preserve_picker:
			g.hud.squad_panel.keep_picker_open_after_mode_cancel()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMouse:
		_mouse_pos = (event as InputEventMouse).position


func _handle_touch(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touches[touch.index] = touch.position
			if _touches.size() == 1:
				_touch_id = touch.index
				_touch_start = touch.position
				_touch_last = touch.position
				_touch_moved = false
				_touch_long_pressed = false
				_touch_elapsed = 0.0
				_mouse_pos = touch.position
			elif _touches.size() == 2:
				_touch_id = -1
				_touch_moved = true
				_pinch_distance = _touch_distance()
				_twist_last_angle = _touch_pair_angle()
				_twist_accum = 0.0
				_twist_fired = false
			get_viewport().set_input_as_handled()
		else:
			if not _touches.has(touch.index):
				return
			var last_count := _touches.size()
			_touches.erase(touch.index)
			if last_count >= 2:
				if _touches.size() == 1:
					for id: int in _touches.keys():
						if id >= 0:
							_touch_id = id
							_touch_last = _touches[id]
							_touch_start = _touch_last
							_touch_elapsed = 0.0
							_touch_moved = true
							break
			elif touch.index == _touch_id:
				if not _touch_moved and not _touch_long_pressed:
					_touch_tap(touch.position)
				elif _is_line_build() and hover_ground is Vector3:
					_place(mode.substr(6), false)
				elif mode.begins_with("zone:"):
					_finish_zone(mode.substr(5))
				elif box_select_mode and dragging:
					_box_select(drag_rect)
				_left_down = false
				dragging = false
				_touch_id = -1
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if not _touches.has(drag.index):
			return
		_touches[drag.index] = drag.position
		if _touches.size() >= 2:
			var old_distance := _pinch_distance
			var new_distance := _touch_distance()
			var center := _touch_center()
			if old_distance > 1.0:
				g.rig.zoom_at(center, old_distance / maxf(1.0, new_distance))
			_pinch_distance = new_distance
			var angle := _touch_pair_angle()
			_twist_accum += wrapf(angle - _twist_last_angle, -PI, PI)
			_twist_last_angle = angle
			if not _twist_fired and absf(_twist_accum) >= deg_to_rad(40.0):
				g.rig.rotate_step(1 if _twist_accum > 0.0 else -1)
				_twist_fired = true
			_touch_moved = true
		elif drag.index == _touch_id:
			var delta := drag.position - _touch_last
			_touch_last = drag.position
			_mouse_pos = drag.position
			if drag.position.distance_to(_touch_start) > DRAG_PX:
				_touch_moved = true
				if mode.begins_with("build:") or mode.begins_with("zone:"):
					_left_down = true
					drag_start = _touch_start
					hover_ground = g.rig.screen_to_ground(drag.position)
					if mode.begins_with("build:") and hover_ground is Vector3:
						if not _is_line_build():
							_touch_build_point = hover_ground
						elif not (_wall_start is Vector2i):
							var start_ground: Variant = g.rig.screen_to_ground(_touch_start)
							if start_ground is Vector3:
								_wall_start = _tile_at(start_ground)
					_update_ghost()
					if mode.begins_with("zone:"):
						_update_zone_preview()
				elif box_select_mode:
					_left_down = true
					drag_start = _touch_start
					dragging = true
					drag_rect = Rect2(drag_start, drag.position - drag_start).abs()
				else:
					g.rig.pan_screen(delta)
			get_viewport().set_input_as_handled()
func _touch_distance() -> float:
	var points: Array[Vector2] = []
	for id: int in _touches:
		if id >= 0:
			points.append(_touches[id])
	if points.size() < 2:
		return 0.0
	return points[0].distance_to(points[1])


func _touch_center() -> Vector2:
	var points: Array[Vector2] = []
	for id: int in _touches:
		if id >= 0:
			points.append(_touches[id])
	if points.size() < 2:
		return _touch_last
	return (points[0] + points[1]) * 0.5


func _touch_pair_angle() -> float:
	var ids: Array = _touches.keys()
	if ids.size() < 2:
		return 0.0
	ids.sort()
	var first: Vector2 = _touches[ids[0]]
	var second: Vector2 = _touches[ids[1]]
	return (second - first).angle()


func _touch_tap(p: Vector2) -> void:
	_mouse_pos = p
	hover_ground = g.rig.screen_to_ground(p)
	if mode.begins_with("cmd:"):
		_target_command(mode.substr(4), p)
		set_mode("")
	elif mode.begins_with("ability:"):
		_target_ability(mode.substr(8), p)
		set_mode("")
	elif mode.begins_with("build:"):
		if hover_ground is Vector3:
			_touch_build_point = hover_ground
			if _is_line_build():
				if _wall_start is Vector2i:
					_place(mode.substr(6), false)
				else:
					_wall_start = _tile_at(hover_ground)
	elif mode.begins_with("zone:"):
		_left_press(p)
		_left_release(p, false)
	else:
		# a tap selects units and buildings; with a selection, a tap on an enemy or on open ground
		# gives the same context order as a right click on desktop
		var target := pick_unit(p, true, true)
		var building: Building = g.world.building_at(_tile_at(hover_ground)) if hover_ground is Vector3 else null
		var ordering := not g.selected_units().is_empty()
		if target:
			ordering = ordering and g.world.hostile("player", target.faction)
		elif building:
			ordering = false
		if ordering:
			_context_order(p)
		else:
			_click_select(p, false, true)




## Unit nearest to screen point `sp`; `finger` widens the reach for touch taps.
func pick_unit(sp: Vector2, prefer_hostile: bool = false, finger: bool = false) -> Unit:
	var best: Unit = null
	var best_d := PICK_PX * clampf(28.0 / g.rig.zoom, 0.6, 2.2) * (1.6 if finger else 1.0)
	for id: int in g.view.unit_views:
		var v: UnitView = g.view.unit_views[id]
		if not v.visible or not v.u.alive:
			continue
		var h := v._bar_h * 0.45
		var p := g.rig.world_to_screen(v.global_position + Vector3(0, h, 0))
		var d := p.distance_to(sp)
		if v.u.kind == "airship":
			d *= 0.35
		if prefer_hostile and g.world.hostile("player", v.u.faction):
			d *= 0.6
		if d < best_d:
			best_d = d
			best = v.u
	return best


func _tile_at(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x)), int(floor(p.z)))


func site_at(t: Vector2i) -> int:
	for sid: int in g.world.sites:
		var st: Dictionary = g.world.sites[sid]
		if not g.world.is_explored(st["center"]):
			continue
		var c := Vector2(st["center"])
		if Vector2(t).distance_to(c) <= maxf(3.0, float(g.world.gen.sites[sid].get("flat_radius", 4)) * 0.6):
			return sid
	return -1
func loot_at(t: Vector2i) -> int:
	var best_id := -1
	var best_distance := 1.5
	for id: int in g.world.loot_bags:
		var bag: Dictionary = g.world.loot_bags[id]
		var d := Vector2(t).distance_to(Vector2(bag.get("pos", Vector2.ZERO)))
		if d <= best_distance:
			best_distance = d
			best_id = id
	return best_id


# --- frame ---------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _touch_id >= 0 and _touches.has(_touch_id) and not _touch_moved and not _touch_long_pressed:
		_touch_elapsed += _delta
		if _touch_elapsed >= 0.45:
			_touch_long_pressed = true
			_mouse_pos = _touch_last
			var unit := pick_unit(_touch_last, false, true)
			if unit or hover_ground is Vector3:
				_click_select(_touch_last, false, true)
			g.hud.show_touch_detail(_describe_hover())
	var sp := _mouse()
	hover_ground = g.rig.screen_to_ground(sp)
	var over_ui := g.hud.is_mouse_over_ui()
	var hu: Unit = null if over_ui else pick_unit(sp, mode == "cmd:attack")
	if hu != hover_unit:
		if hover_unit and g.view.unit_views.has(hover_unit.id):
			(g.view.unit_views[hover_unit.id] as UnitView).hovered = false
		hover_unit = hu
		if hu and g.view.unit_views.has(hu.id):
			(g.view.unit_views[hu.id] as UnitView).hovered = true
	hover_info = _describe_hover()
	if mode.begins_with("build:"):
		_update_ghost()
	elif mode.begins_with("zone:"):
		_update_zone_preview()
	if _left_down and not dragging and mode == "" and sp.distance_to(drag_start) > DRAG_PX:
		dragging = true
	if dragging:
		drag_rect = Rect2(drag_start, sp - drag_start).abs()


func _describe_hover() -> String:
	if hover_unit:
		var u := hover_unit
		var tag := ""
		if g.world.hostile("player", u.faction):
			tag = " [" + Loc.t("hostile") + "]"
		elif u.faction != "player":
			tag = " [%s]" % Loc.t(u.faction)
		return "%s — %s Lv.%d%s" % [u.name, Loc.t(u.display_role()), u.char_level(), tag]
	if hover_ground is Vector3:
		var t := _tile_at(hover_ground)
		if not g.world.is_explored(t):
			return Loc.t("Unexplored")
		var b := g.world.building_at(t)
		if b:
			return "%s%s" % [Loc.def_name("buildings", b.type), "" if b.is_built() else Loc.t(" (under construction %d%%)") % int(b.progress * 100)]
		var sid := site_at(t)
		if sid >= 0:
			var st: Dictionary = g.world.sites[sid]
			return "%s — %s%s" % [st["name"], Loc.t(str(FactionAI.KIND_LABEL.get(st["kind"], st["kind"]))), Loc.t(" (cleared)") if st.get("cleared", false) and st.get("hostile", false) else ""]
		var loot_id := loot_at(t)
		if loot_id >= 0:
			var bag: Dictionary = g.world.loot_bags[loot_id]
			return Loc.t("Loot bag — tier %d") % int(bag.get("tier", 0))
		var r := g.world.res_at(t)
		if r != Tiles.Res.NONE:
			var info := Tiles.res_info(r)
			return Loc.t("%s (%d %s)") % [Loc.t(str(info["id"]).replace("_", " ").capitalize()), g.world.res_amount_at(t), Loc.t(str(info.get("yield", "")))]
		if g.world.farm.has(t):
			var f: Dictionary = g.world.farm[t]
			var stages := ["untilled", "tilled", "growing %d%%" % int(float(f["growth"]) * 100), "ripe"]
			return Loc.t("Field: %s") % Loc.t(stages[int(f["stage"])])
		return Loc.t(Tiles.NAMES[g.world.terrain_at(t)])
	return ""


# --- input ---------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_handle_touch(event)
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_left_press(mb.position)
			else:
				_left_release(mb.position, mb.shift_pressed)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if mode != "":
				set_mode("")
			else:
				_context_order(mb.position)
	elif event.is_action_pressed("cancel"):
		if mode != "":
			set_mode("")
			g.get_viewport().set_input_as_handled()

func _left_press(p: Vector2) -> void:
	_left_down = true
	drag_start = p
	if mode.begins_with("zone:") and hover_ground is Vector3:
		zone_start = _tile_at(hover_ground)
	if _is_line_build() and hover_ground is Vector3:
		_wall_start = _tile_at(hover_ground)


func _left_release(p: Vector2, shift: bool) -> void:
	# a release whose press landed on the HUD (e.g. a card rebuilt mid-click) is not a world click
	if not _left_down:
		return
	var was_drag := dragging
	_left_down = false
	dragging = false
	if mode.begins_with("cmd:"):
		_target_command(mode.substr(4), p)
		if not shift:
			set_mode("")
		return
	if mode.begins_with("ability:"):
		_target_ability(mode.substr(8), p)
		if not shift:
			set_mode("")
		return
	if mode.begins_with("build:"):
		_place(mode.substr(6), shift)
		return
	if mode.begins_with("zone:"):
		_finish_zone(mode.substr(5))
		return
	if was_drag:
		_box_select(drag_rect)
		return
	_click_select(p, shift)


func _click_select(p: Vector2, shift: bool, finger: bool = false) -> void:
	var u := pick_unit(p, false, finger)
	if u:
		if shift and u.is_player():
			var ids := g.sel_units.duplicate()
			if ids.has(u.id):
				ids.erase(u.id)
			else:
				ids.append(u.id)
			g.select_units(ids)
		elif u.is_player() and u.squad_id >= 0 and not g.sel_units.has(u.id):
			g.select_squad(u.squad_id)
			g.sel_units.erase(u.id)
			g.sel_units.push_front(u.id)
			g.selection_changed.emit()
		else:
			g.select_units([u.id])
		if u.is_player() and u.squad_id >= 0 and g.hud != null:
			g.hud.squad_panel.all_squads_active = false
			g.hud._update_commands()
		Sfx.play(&"ui_select")
		return
	if hover_ground is Vector3:
		var t := _tile_at(hover_ground)
		var b := g.world.building_at(t)
		if b:
			g.select_building(b.id)
			Sfx.play(&"ui_select")
			return
		var loot_id := loot_at(t)
		if loot_id >= 0:
			g.select_loot(loot_id)
			Sfx.play(&"ui_select")
			return
		var sid := site_at(t)
		if sid >= 0:
			g.select_site(sid)
			Sfx.play(&"ui_select")
			return
	g.clear_selection()


func _box_select(r: Rect2) -> void:
	var ids: Array = []
	for id: int in g.view.unit_views:
		var v: UnitView = g.view.unit_views[id]
		if not v.visible or not v.u.alive or not v.u.is_player():
			continue
		var sp := g.rig.world_to_screen(v.global_position + Vector3(0, 0.5, 0))
		if r.has_point(sp):
			ids.append(id)
	if ids.is_empty():
		g.clear_selection()
	else:
		g.select_units(ids)
		Sfx.play(&"ui_select")


## Right click: attack what is hostile, gather resources, otherwise move.
func _context_order(p: Vector2) -> void:
	var units: Array = g.hud.command_units() if g.hud != null else g.selected_units()
	if units.is_empty():
		return
	var target := pick_unit(p, true)
	if target and g.world.hostile("player", target.faction):
		issue("attack", {"target": target.id})
		return
	if not (hover_ground is Vector3):
		return
	var t := _tile_at(hover_ground)
	var sid := site_at(t)
	if sid >= 0 and bool(g.world.sites[sid].get("hostile", false)) and not bool(g.world.sites[sid].get("cleared", false)):
		issue("attack", {"site": sid, "pos": Vector2(g.world.sites[sid]["center"])})
		return
	if sid >= 0 and str(g.world.sites[sid]["kind"]) == "village" and not bool(g.world.sites[sid].get("ruined", false)):
		# friendly village: walk over and open the market (hostile ones fell through to attack above)
		var squad_ids: Dictionary = {}
		for u: Unit in units:
			if u.squad_id >= 0:
				squad_ids[u.squad_id] = true
		if squad_ids.is_empty():
			issue("move", {"pos": Vector2(g.world.sites[sid]["center"]) + Vector2(0.5, 0.5)})
			return
		for squad_id: int in squad_ids:
			g.world.squad_ai.order_squad(g.world.get_squad(squad_id),
				{"type": "visit", "site": sid, "pos": Vector2(g.world.sites[sid]["center"])})
		g.toast.emit(Loc.t("Heading to the village to trade."), "info")
		Sfx.play(&"ui_confirm")
		return
	if sid >= 0 and str(g.world.sites[sid]["kind"]) == "trade_post":
		for u: Unit in units:
			if u.kind == "airship":
				g.world.squad_ai.order_unit(u, {"type": "trade", "site": sid, "phase": "out"})
				g.toast.emit("%s sets course for %s." % [u.name, g.world.sites[sid]["name"]], "info")
				return
	var r := g.world.res_at(t)
	if r != Tiles.Res.NONE and str(Tiles.res_info(r).get("job", "")) != "":
		var workers := units.filter(func(u: Unit) -> bool: return u.squad_id < 0 and u.labor == "worker")
		if not workers.is_empty():
			for u: Unit in workers:
				g.world.squad_ai.order_gather(u, t)
			g.toast.emit(Loc.t("Gathering."), "info")
			Sfx.play(&"ui_confirm")
			return
	issue("move", {"pos": Vector2(hover_ground.x, hover_ground.z)})


func _target_ability(ability_id: String, screen_pos: Vector2) -> void:
	var prefer_hostile := false
	for unit: Unit in g.selected_units():
		if g.world.combat.ability_ids(unit).has(ability_id):
			prefer_hostile = str(g.world.combat.ability_info(unit, ability_id).get("target", "")) == "enemy"
			break
	var target_unit := pick_unit(screen_pos, prefer_hostile)
	var target_pos := Vector2(hover_ground.x, hover_ground.z) if hover_ground is Vector3 else Vector2.ZERO
	var used := 0
	var reason := ""
	for unit: Unit in g.selected_units():
		var info := g.world.combat.ability_info(unit, ability_id)
		var target: Dictionary = {}
		match str(info.get("target", "none")):
			"enemy":
				if target_unit and g.world.hostile("player", target_unit.faction):
					target = {"unit": target_unit.id}
			"ally":
				if target_unit and target_unit.is_player():
					target = {"unit": target_unit.id}
			"ground":
				if hover_ground is Vector3:
					target = {"pos": target_pos}
			"none":
				target = {}
		if target.is_empty() and str(info.get("target", "none")) != "none":
			reason = "no_target"
			continue
		var result := g.world.combat.use_ability(unit, ability_id, target)
		if result == "":
			used += 1
		else:
			reason = result
	if used == 0 and reason != "":
		var reason_keys := {
			"cooldown": "reason.cooldown",
			"no_target": "reason.no_target",
			"downed": "reason.downed",
			"unknown": "reason.unknown",
		}
		g.toast.emit(Loc.t(str(reason_keys.get(reason, "reason.unknown"))), "info")
	elif used > 0:
		g.toast.emit(Loc.t("%d used ability: %s") % [used, Loc.t(ability_id.replace("_", " ").capitalize())], "good")


func _target_command(type: String, p: Vector2) -> void:
	var target := pick_unit(p, type == "attack")
	var params := {}
	match type:
		"attack":
			if target and g.world.hostile("player", target.faction):
				params = {"target": target.id}
			elif hover_ground is Vector3:
				var sid := site_at(_tile_at(hover_ground))
				if sid >= 0 and bool(g.world.sites[sid].get("hostile", false)):
					params = {"site": sid, "pos": Vector2(g.world.sites[sid]["center"])}
				else:
					params = {"pos": Vector2(hover_ground.x, hover_ground.z)}
		"escort":
			if target and target.is_player():
				params = {"target": target.id}
			else:
				g.toast.emit(Loc.t("Pick one of your units to escort."), "bad")
				return
		_:
			if not (hover_ground is Vector3):
				return
			params = {"pos": Vector2(hover_ground.x, hover_ground.z)}
	issue(type, params)


## Sends an order to the selected squad and/or individually selected units.
func issue(type: String, params: Dictionary = {}) -> void:
	var units: Array = g.hud.command_units() if g.hud != null else g.selected_units()
	if units.is_empty():
		return
	var order := params.duplicate()
	order["type"] = type
	if type == "explore":
		order["radius"] = float(params.get("radius", SquadAI.EXPLORE_RADIUS))
	if type == "defend":
		order["radius"] = 10.0
	if type == "patrol":
		var c := Vector2.ZERO
		for u: Unit in units:
			c += u.pos
		order["points"] = [c / units.size(), params.get("pos", c / units.size())]
	var squads := {}
	for u: Unit in units:
		if u.squad_id >= 0:
			squads[u.squad_id] = true
		else:
			var o := order.duplicate()
			if u.kind == "airship" and type == "move":
				o = {"type": "move", "pos": params["pos"]}
			g.world.squad_ai.order_unit(u, o)
	for sid: int in squads:
		g.world.squad_ai.order_squad(g.world.get_squad(sid), order.duplicate())
	if params.has("pos"):
		g.view.add_child(_order_marker(params["pos"], type))
	Sfx.play(&"ui_confirm")
	g.toast.emit(Loc.t("%s ordered.") % Loc.t(str(ORDER_LABEL.get(type, type.capitalize()))), "info")


func _order_marker(p: Vector2, type: String) -> Node3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.5
	tm.outer_radius = 0.65
	mi.mesh = tm
	mi.material_override = _mat(Color("#ff6a4a") if type == "attack" else Color("#7fe0ff"))
	mi.position = Vector3(p.x, maxf(g.world.height_at(p), 0.0) + 0.1, p.y)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(0.2, 1, 0.2), 0.6).from(Vector3(1.6, 1, 1.6))
	tw.tween_callback(mi.queue_free)
	return mi


# --- building placement ----------------------------------------------------------------------

func _is_line_build() -> bool:
	return mode in ["build:wall", "build:bridge_segment", "build:cliff_stairs"]


func _ghost_origin(type: String) -> Vector2i:
	var d := DB.get_def("buildings", type)
	var size := Vector2i(int(d["size"][0]), int(d["size"][1]))
	var p: Vector3 = hover_ground
	return Vector2i(int(round(p.x - size.x * 0.5)), int(round(p.z - size.y * 0.5)))


func _update_ghost() -> void:
	var type := mode.substr(6)
	if not (hover_ground is Vector3):
		if _ghost:
			_ghost.visible = false
		_foot.visible = false
		return
	if _ghost_type != type:
		if _ghost:
			_ghost.queue_free()
		_ghost = BuildingVisuals.create(type, "frontier", 7, 1)
		_ghost.set_construction(1.0)
		g.add_child(_ghost)
		_ghost_type = type
	var d := DB.get_def("buildings", type)
	var size := Vector2i(int(d["size"][0]), int(d["size"][1]))
	var o := _ghost_origin(type)
	var reason := g.world.can_place(type, o)
	if _is_line_build() and _wall_start is Vector2i and _left_down:
		reason = ""
	_last_reason = reason
	var c := Vector2(o) + Vector2(size) * 0.5
	_ghost.visible = true
	_ghost.position = Vector3(c.x, g.world.height_at(c), c.y)
	_foot.visible = true
	_foot.scale = Vector3(size.x, 1, size.y)
	_foot.position = Vector3(c.x, maxf(g.world.height_at(c), 0.0) + 0.12, c.y)
	_foot.material_override = _mat(Color(0.3, 1.0, 0.4, 0.35) if reason == "" else Color(1.0, 0.3, 0.25, 0.4))


func ghost_reason() -> String:
	return _last_reason


func _place(type: String, keep: bool) -> void:
	if not (hover_ground is Vector3):
		return
	if _is_line_build() and _wall_start is Vector2i:
		var a: Vector2i = _wall_start
		var b := _tile_at(hover_ground)
		var n := 0
		var steps := maxi(absi(b.x - a.x), absi(b.y - a.y))
		for i in steps + 1:
			var t := Vector2i(roundi(lerpf(a.x, b.x, float(i) / maxf(1.0, steps))), roundi(lerpf(a.y, b.y, float(i) / maxf(1.0, steps))))
			if g.world.can_place(type, t) == "":
				g.world.place_building(type, t)
				n += 1
		_wall_start = null
		g.toast.emit(Loc.t("%d building segments planned.") % n if n > 0 else Loc.t("No room for building segments there."), "info" if n > 0 else "bad")
		if n > 0:
			Sfx.play(&"build_place")
		return
	var o := _ghost_origin(type)
	var reason := g.world.can_place(type, o)
	if reason != "":
		g.toast.emit(Loc.t(reason), "bad")
		Sfx.play(&"ui_error")
		return
	var b := g.world.place_building(type, o)
	Sfx.play(&"build_place")
	g.toast.emit(Loc.t("%s: construction site placed. Settlers will haul materials and build it.") % Loc.def_name("buildings", type), "good")
	if not keep and not _is_line_build():
		set_mode("")


# --- zones ---------------------------------------------------------------------------------

func _zone_rect() -> Rect2i:
	var a: Vector2i = zone_start
	var b := _tile_at(hover_ground) if hover_ground is Vector3 else a
	var mn := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	var mx := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
	return Rect2i(mn, mx - mn + Vector2i.ONE)


func _update_zone_preview() -> void:
	if not (zone_start is Vector2i) or not _left_down:
		if hover_ground is Vector3:
			var t := _tile_at(hover_ground)
			_foot.visible = true
			_foot.scale = Vector3.ONE
			_foot.position = Vector3(t.x + 0.5, maxf(g.world.height_at(Vector2(t) + Vector2(0.5, 0.5)), 0.0) + 0.12, t.y + 0.5)
			_foot.material_override = _mat(Color(1, 1, 1, 0.3))
		return
	var r := _zone_rect()
	var c := Vector2(r.position) + Vector2(r.size) * 0.5
	_foot.visible = true
	_foot.scale = Vector3(r.size.x, 1, r.size.y)
	_foot.position = Vector3(c.x, maxf(g.world.height_at(c), 0.0) + 0.15, c.y)
	var col: Color = WorldView.ZONE_COLORS.get(mode.substr(5), Color(1, 0.4, 0.4))
	_foot.material_override = _mat(Color(col.r, col.g, col.b, 0.3))


func zone_count(type: String) -> int:
	if not (zone_start is Vector2i) or not _left_down:
		return -1
	var r := _zone_rect()
	var n := 0
	for x in range(r.position.x, r.end.x):
		for z in range(r.position.y, r.end.y):
			var rr := g.world.res_at(Vector2i(x, z))
			if type == "farm":
				n += 1
			elif rr != Tiles.Res.NONE and Tiles.zone_for(rr) == type:
				n += 1
	return n


func _finish_zone(type: String) -> void:
	if not (zone_start is Vector2i):
		return
	var r := _zone_rect()
	zone_start = null
	if type == "clear":
		var n := g.world.remove_zones_in(r)
		g.toast.emit(Loc.t("%d zone(s) removed.") % n, "info")
		return
	if r.size.x * r.size.y > 900:
		g.toast.emit(Loc.t("Zone too large (max 30×30)."), "bad")
		return
	var z := g.world.add_zone(type, r)
	if z.is_empty():
		g.toast.emit(Loc.t("Nothing to farm there — pick open grass."), "bad")
		Sfx.play(&"ui_error")
	else:
		g.toast.emit(Loc.t("%s zone designated. Idle workers will get to it.") % Loc.t(type.capitalize()), "good")
		Sfx.play(&"ui_confirm")
