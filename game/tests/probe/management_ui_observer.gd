extends Node
## UI fixture only: completed facilities, market presence, sufficient currency and old records.
## No production speed/stat boosts, no user save writes. Transactions and production run normally.

var g: Game
var workshop_id := -1
var smelter_id := -1
var village_id := -1
var post_id := -1
var ship_id := -1
var receipt: Dictionary = {}
var machines_before: Array[int] = []
var archive_count := 0


func setup(game: Game) -> void:
	g = game
	g.set_speed(0)
	for resource: String in ["wood", "stone", "ore", "metal", "gold", "energy"]:
		g.world.res[resource] = 200
	workshop_id = _complete_facility("workshop")
	smelter_id = _complete_facility("smelter")
	g.world.priorities["operate"] = 3
	for u: Unit in g.world.unit_list:
		if u.alive and u.is_player() and u.kind == "airship":
			ship_id = u.id
			break
	village_id = g.dbg_station_squad_at("village")
	if village_id >= 0:
		var site: Dictionary = g.world.sites[village_id]
		g.world.diplomacy.change_relation(village_id, -g.world.diplomacy.relation(village_id), "probe")
		g.world.diplomacy.stock_of(village_id)
		site["purse"] = 400
	post_id = _reveal("trade_post")
	for index in 45:
		g.world.notify("Archive record %03d" % index, "info", g.world.home_pos(), {"building": g.world.hearth_id})
	archive_count = g.world.notifications.size()
	for unit: Unit in g.world.unit_list:
		machines_before.append(unit.id)
	g.focus_home()
	g.clear_selection()


func _reveal(kind: String) -> int:
	var id := g.dbg_reveal_site(kind)
	if id >= 0 and not bool(g.world.sites[id].get("discovered", false)):
		g.world.factions._discover(g.world.sites[id], null)
	return id


func _complete_facility(type: String) -> int:
	var id := g.dbg_plan_building(type)
	if id < 0:
		return id
	var b: Building = g.world.buildings[id]
	b.progress = 1.0
	b.hp = b.max_hp()
	b.needs.clear()
	b.delivered.clear()
	g.world.building_changed.emit(b)
	return id


func _find(node_name: String) -> Control:
	var stack: Array[Node] = [g.hud]
	while not stack.is_empty():
		var node := stack.pop_back() as Node
		if node is Control and node.name == node_name and (node as Control).is_visible_in_tree():
			return node as Control
		for child: Node in node.get_children():
			stack.append(child)
	return null


func button_pos(node_name: String) -> Vector2:
	var control := _find(node_name)
	if control == null:
		return Vector2(-1, -1)
	var parent := control.get_parent()
	while parent != null and not (parent is ScrollContainer):
		parent = parent.get_parent()
	if parent is ScrollContainer:
		(parent as ScrollContainer).ensure_control_visible(control)
	return control.get_global_transform_with_canvas() * (control.size * 0.5)


func click(node_name: String) -> bool:
	return g.dbg_click(button_pos(node_name))


func disabled(node_name: String) -> bool:
	var button := _find(node_name) as Button
	return button != null and button.disabled


func label_text(node_name: String) -> String:
	var label := _find(node_name) as Label
	return label.text if label else ""


func type_query(node_name: String, value: String) -> bool:
	var edit := _find(node_name) as LineEdit
	if edit == null:
		return false
	edit.grab_focus()
	edit.clear()
	for index in value.length():
		for pressed: bool in [true, false]:
			var event := InputEventKey.new()
			event.pressed = pressed
			event.unicode = value.unicode_at(index)
			Input.parse_input_event(event)
	return true


func station_market() -> void:
	village_id = g.dbg_station_squad_at("village")
	if village_id >= 0:
		g.world.squad_ai.order_squad(g.world.squads[0],
			{"type": "defend", "pos": Vector2(g.world.sites[village_id]["center"]) + Vector2(0.5, 0.5)})


func visible_trade_history() -> bool:
	var sales := false
	var purchases := false
	var readable := 0
	var stack: Array[Node] = [g.hud.history._list]
	while not stack.is_empty():
		var node := stack.pop_back() as Node
		if node.has_meta("history_note"):
			var note: Dictionary = node.get_meta("history_note")
			sales = sales or str(note.get("key", "")) == "sim.trade.resource_sold"
			purchases = purchases or str(note.get("key", "")) == "sim.trade.resource_bought"
		if node is Label and (node as Label).text.contains(Loc.t("wood")) and (node as Label).text.contains("10"):
			readable += 1
		for child: Node in node.get_children():
			stack.append(child)
	return sales and purchases and readable >= 2


func remember_balances() -> void:
	receipt = g.world.res.duplicate()


func paid_machine_once() -> bool:
	var cost: Dictionary = g.world.colony._archetype("work_bot").get("cost", {})
	for resource: String in cost:
		if int(g.world.res.get(resource, 0)) != int(receipt.get(resource, 0)) - int(cost[resource]):
			return false
	var b: Building = g.world.buildings.get(workshop_id)
	return b != null and b.queue == ["work_bot"]


func production_finished() -> bool:
	var b: Building = g.world.buildings.get(workshop_id)
	if b == null or not b.queue.is_empty():
		return false
	for note: Dictionary in g.world.notifications:
		if str(note.get("key", "")) == "sim.colony.machine_built":
			var unit := g.world.get_unit(int(note.get("unit", -1)))
			return unit != null and unit.alive and not machines_before.has(unit.id) \
				and str(unit.DB_archetype().get("id", "")) == "work_bot"
	return false


func set_resource(resource: String, amount: int) -> void:
	g.world.res[resource] = amount


func market_sale_succeeded() -> bool:
	return int(g.world.res.get("wood", 0)) == int(receipt.get("wood", 0)) - 10 \
		and int(g.world.res.get("gold", 0)) > int(receipt.get("gold", 0)) \
		and str(g.world.notifications.back().get("key", "")) == "sim.trade.resource_sold"


func market_buy_succeeded() -> bool:
	return int(g.world.res.get("wood", 0)) == int(receipt.get("wood", 0)) + 10 \
		and int(g.world.res.get("gold", 0)) < int(receipt.get("gold", 0)) \
		and str(g.world.notifications.back().get("key", "")) == "sim.trade.resource_bought"


func set_merchant_purse(amount: int) -> void:
	g.world.sites[village_id]["purse"] = amount


func prepare_places() -> void:
	g.world.day = maxi(2, g.world.day)
	g.world.dungeons.on_new_day()
	_reveal("dungeon")
	_reveal("ruins")
	g.focus_home()
	g.clear_selection()


func directory_respects_discovery() -> bool:
	for key: String in g.hud.places._rows:
		if key.begins_with("site_"):
			var id := int(key.substr(5))
			var site: Dictionary = g.world.sites.get(id, {})
			if not bool(site.get("discovered", false)) or str(site.get("kind", "")) == "dungeon_floor":
				return false
	return true


func search_is_facility_only() -> bool:
	if g.hud.places._rows.is_empty():
		return false
	for key: String in g.hud.places._rows:
		if not key.begins_with("building_"):
			return false
	return g.hud.places._rows.has("building_%d" % workshop_id)


func map_pos(pos: Vector2) -> Vector2:
	return g.hud.minimap._map.get_global_transform_with_canvas() * g.hud.minimap._w2m(pos)


func move_mouse(pos: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = g.get_viewport().get_final_transform() * pos
	event.global_position = event.position
	Input.parse_input_event(event)


func drag_map() -> void:
	var map := g.hud.minimap._map
	var begin := map.get_global_transform_with_canvas() * Vector2(205, 205)
	var end := map.get_global_transform_with_canvas() * Vector2(175, 195)
	var transform := g.get_viewport().get_final_transform()
	for step in 6:
		var at := begin.lerp(end, float(step) / 5.0)
		if step == 0 or step == 5:
			var button := InputEventMouseButton.new()
			button.button_index = MOUSE_BUTTON_LEFT
			button.pressed = step == 0
			button.button_mask = MOUSE_BUTTON_MASK_LEFT if button.pressed else 0
			button.position = transform * at
			button.global_position = button.position
			Input.parse_input_event(button)
		else:
			var motion := InputEventMouseMotion.new()
			motion.button_mask = MOUSE_BUTTON_MASK_LEFT
			motion.position = transform * at
			motion.global_position = motion.position
			motion.relative = transform.basis_xform((end - begin) / 5.0)
			Input.parse_input_event(motion)
