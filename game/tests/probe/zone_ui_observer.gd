extends "res://tests/probe/management_ui_observer.gd"

var origin := Vector2i.ZERO
var drag_end := Vector2i.ZERO
var expected_farm := 0
var farm_before := 0

func setup_zones(game: Game) -> void:
	g = game
	g.set_speed(0)
	g.clear_selection()
	g.world.zones.clear()
	g.world.zones_changed.emit()
	origin = g.world.gen.start_tile + Vector2i(12, 10)
	g.world.reveal(Vector2(origin), 25.0)
	g.rig.edge_scroll = false
	g.rig.focus(Vector3(origin.x + 4, 0, origin.y + 3), true)
	g.rig.zoom_goal = 30.0

func open_tools() -> void:
	g.hud.build_menu.toggle("gather")

func screen_tile(tile: Vector2i) -> Vector2:
	var pos := Vector2(tile) + Vector2(0.5, 0.5)
	return g.rig.world_to_screen(Vector3(pos.x, maxf(g.world.height_at(pos), -0.05), pos.y))

func motion(tile: Vector2i) -> void:
	var event := InputEventMouseMotion.new()
	event.position = g.get_viewport().get_final_transform() * screen_tile(tile)
	event.global_position = event.position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(event)

func button(tile: Vector2i, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = g.get_viewport().get_final_transform() * screen_tile(tile)
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(event)

func begin_rect(x: int, y: int, width: int, height: int) -> void:
	var start := origin + Vector2i(x, y)
	drag_end = start + Vector2i(width - 1, height - 1)
	motion(start)
	button(start, true)

func move_end() -> void:
	motion(drag_end)

func end_rect() -> void:
	button(drag_end, false)

func shape_is(count: int, tiles: int) -> bool:
	var total := 0
	var found := 0
	for zone: Dictionary in g.world.zones:
		if zone["type"] == "logging":
			found += 1
			total += zone["tiles"].size()
	return found == count and total == tiles

func has_tile(x: int, y: int) -> bool:
	return g.world.has_zone_tile("logging", origin + Vector2i(x, y))

func prepare_farm() -> void:
	g.input_ctl.set_mode("zone:farm")
	farm_before = g.world.farm.size()
	expected_farm = 0
	for x in range(8):
		for y in range(6):
			expected_farm += int(g.world.can_farm_at(origin + Vector2i(x, y)))

func farm_preview_matches() -> bool:
	return g.input_ctl.zone_count("farm") == expected_farm and expected_farm > 0 and expected_farm < 48

func farm_applied() -> bool:
	return g.world.farm.size() - farm_before == expected_farm

func save_shape_survives() -> bool:
	var loaded := SaveGame.from_dict(JSON.parse_string(JSON.stringify(SaveGame.to_dict(g.world))))
	var ok := loaded.zones.size() == g.world.zones.size()
	for zone: Dictionary in g.world.zones:
		var matching := false
		for other: Dictionary in loaded.zones:
			if zone["id"] == other["id"]:
				matching = zone["tiles"] == other["tiles"]
		ok = ok and matching
	loaded.dispose()
	return ok
