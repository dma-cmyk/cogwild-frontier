class_name ProductionPanel
extends PanelContainer
## Read-only production overview, with the existing pay-now workshop queue controls.
## Rows survive progress updates; only added/removed facilities change the row structure.

var g: Game
var hud: Hud
var _stocks: Dictionary = {}
var _harvest: Label
var _farms: Label
var _workers: Label
var _list: VBoxContainer
var _rows: Dictionary = {}
var _detail: Label
var _controls: VBoxContainer
var _selected := -1
var _control_id := -1
var _language := ""
var _title: Label
var _help: Label
var _stock_hint: Label
var _close: Button
var _empty: Label


func setup(game: Game, h: Hud) -> void:
	g = game
	hud = h
	name = "ProductionPanel"
	theme = UiTheme.theme()
	add_theme_stylebox_override("panel", UiTheme.panel_box())
	mouse_filter = Control.MOUSE_FILTER_STOP
	var body := UiTheme.vbox(8)
	add_child(body)
	var head := UiTheme.hbox(8)
	body.add_child(head)
	_title = UiTheme.title("", 23)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_close = UiTheme.button("", "ui_close")
	_close.name = "ProductionClose"
	_close.focus_mode = Control.FOCUS_ALL
	_close.pressed.connect(close_window)
	head.add_child(_close)
	var stock_row := GridContainer.new()
	stock_row.columns = World.RESOURCES.size()
	stock_row.add_theme_constant_override("h_separation", 12)
	body.add_child(stock_row)
	for resource: String in World.RESOURCES:
		var label := _text(stock_row, "", 15)
		label.name = "Stock_" + resource
		_stocks[resource] = label
	_stock_hint = _text(body, "", 13)
	_help = _text(body, "", 14)
	var columns := UiTheme.hbox(14)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(columns)
	var overview := _scroll_body(columns)
	(overview.get_parent() as ScrollContainer).size_flags_stretch_ratio = 1.1
	_harvest = _text(overview, "", 14)
	_harvest.name = "HarvestStatus"
	_farms = _text(overview, "", 14)
	_farms.name = "FarmStatus"
	_workers = _text(overview, "", 14)
	_workers.name = "HarvestWorkers"
	_list = UiTheme.vbox(8)
	overview.add_child(_list)
	_empty = _text(overview, "", 15)
	var selected_body := _scroll_body(columns)
	_detail = _text(selected_body, "", 15)
	_detail.name = "SelectedProductionStatus"
	_controls = UiTheme.vbox(8)
	selected_body.add_child(_controls)
	visible = false
	layout()


func open() -> void:
	visible = true
	var b: Building = g.world.buildings.get(g.sel_building)
	if b and _included(b):
		_selected = b.id
	layout()
	refresh(true)


func close_window() -> void:
	visible = false


func layout() -> void:
	var viewport := get_viewport_rect().size
	var width := minf(1080.0, viewport.x - 40.0)
	var height := minf(760.0, viewport.y - 280.0)
	position = (viewport - Vector2(width, height)) * 0.5
	size = Vector2(width, height)


func refresh(_force: bool = false) -> void:
	if not visible or g == null:
		return
	var w := g.world
	if _language != Loc.language:
		_language = Loc.language
		_title.text = Loc.t("production.title")
		_close.tooltip_text = Loc.t("production.close")
		_help.text = Loc.t("production.allocation")
		_stock_hint.text = Loc.t("production.net_hint")
	var rates := w.economy.rates()
	for resource: String in World.RESOURCES:
		(_stocks[resource] as Label).text = Loc.t("production.stock", {
			"resource": Loc.t(resource), "amount": int(w.res.get(resource, 0)),
			"rate": ("%+.1f" % float(rates[resource])) if rates.has(resource) else Loc.t("production.sampling")})
	_update_harvest(w)
	var ids: Array[int] = []
	for b: Building in w.buildings.values():
		if not _included(b):
			continue
		ids.append(b.id)
		if not _rows.has(b.id):
			_add_building(b)
		var row: Dictionary = _rows[b.id]
		(row["name"] as Label).text = _building_name(b)
		(row["status"] as Label).text = _process_text(w, b) + "\n" + _building_status(w, b)
		(row["bar"] as ProgressBar).value = _progress(w, b)
		(row["button"] as Button).text = Loc.t("production.selected" if b.id == _selected else "production.select")
	for id: int in _rows.keys():
		if not ids.has(id):
			var node: Control = _rows[id]["root"]
			_list.remove_child(node)
			node.queue_free()
			_rows.erase(id)
	if not ids.has(_selected):
		_selected = -1
		for id: int in ids:
			if (w.buildings[id] as Building).type == "workshop":
				_selected = id
				break
		if _selected < 0 and not ids.is_empty():
			_selected = ids[0]
	_empty.visible = ids.is_empty()
	_empty.text = Loc.t("production.no_buildings")
	var selected: Building = w.buildings.get(_selected)
	_detail.text = (_building_name(selected) + "\n" + building_text(w, selected)) if selected else Loc.t("production.choose")
	var next_id := selected.id if selected and selected.is_built() and selected.type == "workshop" else -1
	if next_id != _control_id:
		_control_id = next_id
		for child in _controls.get_children():
			_controls.remove_child(child)
			child.queue_free()
		if next_id >= 0:
			build_controls(_controls, g, hud, selected, refresh)
	for child in _controls.get_children():
		if child is WorkshopControls:
			child.refresh()


static func _included(b: Building) -> bool:
	return b.faction == "player" and (not b.is_built() or b.type in ["smelter", "workshop", "windmill"])


func _add_building(b: Building) -> void:
	var card := UiTheme.panel()
	card.name = "ProductionBuilding_%d" % b.id
	card.set_meta("building_id", b.id)
	_list.add_child(card)
	var box := UiTheme.vbox(5)
	card.add_child(box)
	var title := _text(box, "", 16)
	var status := _text(box, "", 14)
	var bar := UiTheme.bar(UiTheme.ACCENT)
	box.add_child(bar)
	var button := UiTheme.button(Loc.t("production.select"), "ui_target")
	button.name = "ProductionFocus_%d" % b.id
	button.set_meta("building_id", b.id)
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(func() -> void:
		if not g.world.buildings.has(b.id):
			return
		_selected = b.id
		g.select_building(b.id)
		g.focus_pos(b.center())
		refresh())
	box.add_child(button)
	_rows[b.id] = {"root": card, "name": title, "status": status, "bar": bar, "button": button}


static func _text(parent: Node, value: String, font_size: int = 14) -> Label:
	var label := UiTheme.label(value, font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


static func _scroll_body(parent: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var body := UiTheme.vbox(10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	return body


static func _building_name(b: Building) -> String:
	return Loc.t("production.building_name", {"name": Loc.t(b.display_name()), "id": b.id})


static func _resources(resources: Dictionary) -> String:
	return Loc.t("production.resources", {"value": {"resources": resources}}) if not resources.is_empty() else Loc.t("production.none")


static func _machine_name(arch: String) -> String:
	for table: String in ["robots", "airships", "units"]:
		if DB.has_def(table, arch):
			return Loc.def_name(table, arch)
	return arch


static func _progress(w: World, b: Building) -> float:
	if not b.is_built():
		return b.progress
	if b.type == "smelter":
		return clampf(b.recipe_t / maxf(0.1, float(b.def().get("recipe", {}).get("time", 8.0))), 0.0, 1.0)
	if b.type == "workshop" and not b.queue.is_empty():
		return clampf(b.prod_t / maxf(0.1, float(w.colony._archetype(str(b.queue[0])).get("build_time", 60.0))), 0.0, 1.0)
	return 1.0 if b.type == "windmill" else 0.0


static func _process_text(w: World, b: Building) -> String:
	if not b.is_built():
		return Loc.t("production.construction", {"percent": int(b.progress * 100.0), "needs": _resources(b.needs), "delivered": _resources(b.delivered)})
	match b.type:
		"smelter":
			var recipe: Dictionary = b.def().get("recipe", {})
			return Loc.t("production.recipe", {"input": _resources(recipe.get("in", {})), "output": _resources(recipe.get("out", {})), "percent": int(_progress(w, b) * 100.0), "seconds": recipe.get("time", 8.0)})
		"workshop":
			if b.queue.is_empty():
				return Loc.t("production.queue_empty")
			return Loc.t("production.assembling", {"machine": _machine_name(str(b.queue[0])), "percent": int(_progress(w, b) * 100.0), "count": b.queue.size()})
		"windmill":
			return Loc.t("production.windmill", {"rate": b.def().get("energy_per_min", 0.0), "cap": int(Economy.ENERGY_CAP)})
	return ""


static func _assigned(w: World, b: Building) -> Array[Unit]:
	var result: Array[Unit] = []
	for id: int in b.workers:
		var u := w.get_unit(id)
		if u and w.colony.is_worker(u) and int(u.job.get("building", -1)) == b.id and str(u.job.get("type", "")) in ["operate", "build", "haul"]:
			result.append(u)
	return result


static func _worker_status(w: World, u: Unit) -> String:
	var job := str(u.job.get("type", ""))
	var phase := str(u.job.get("phase", ""))
	if job == "operate" and u.is_person() and w.is_night():
		return Loc.t("production.worker.night")
	if job == "operate" and phase == "work":
		var facility: Building = w.buildings.get(int(u.job.get("building", -1)))
		if facility and facility.type == "smelter" and int(w.res.get("ore", 0)) < 2:
			return Loc.t("production.worker.no_ore")
		if facility and facility.type == "workshop" and facility.queue.is_empty():
			return Loc.t("production.worker.queue_empty")
		return Loc.t("production.worker.operating")
	if job == "deliver" or (job == "haul" and phase == "deliver"):
		return Loc.t("production.worker.deliver", {"amount": u.carry_amount, "resource": Loc.t(u.carry_res)})
	if job == "haul":
		return Loc.t("production.worker.fetch")
	if phase == "go":
		return Loc.t("production.worker.on_way")
	if job == "farm":
		return Loc.t("production.worker." + str(u.job.get("action", "farm")), {"seconds": "%.1f" % maxf(0.0, float(u.job.get("t", 0.0)))})
	if job == "gather":
		var info := Tiles.res_info(w.res_at(u.job.get("tile", Vector2i.ZERO)))
		var percent := int(clampf(1.0 - float(u.job.get("t", 0.0)) / maxf(0.1, float(u.job.get("dur", 1.0))), 0.0, 1.0) * 100.0)
		return Loc.t("production.worker.gather", {"resource": Loc.t(str(info.get("yield", ""))), "percent": percent})
	return Loc.t("production.worker." + job)


static func _building_status(w: World, b: Building) -> String:
	if b.is_built() and b.type == "windmill":
		return Loc.t("production.energy_full" if int(w.res.get("energy", 0)) >= int(Economy.ENERGY_CAP) else "production.automatic")
	var assigned := _assigned(w, b)
	var reasons := PackedStringArray()
	if b.is_built() and b.type == "smelter" and int(w.res.get("ore", 0)) < 2:
		reasons.append(Loc.t("production.no_ore", {"amount": int(w.res.get("ore", 0))}))
	if not assigned.is_empty():
		for u: Unit in assigned:
			reasons.append(Loc.t("production.worker_line", {"name": u.name, "status": _worker_status(w, u)}))
	else:
		reasons.append(Loc.t("production.unassigned"))
	var priority := "operate" if b.is_built() else ("haul" if not b.needs.is_empty() else "build")
	if int(w.priorities.get(priority, 2)) == 0:
		reasons.append(Loc.t("production.priority_off", {"priority": Loc.t("production.priority." + priority)}))
	if b.is_built() and b.type in ["workshop", "smelter"] and assigned.is_empty():
		var eligible := 0
		var awake := 0
		for u: Unit in w.unit_list:
			if not w.colony.is_worker(u) or u.kind == "robot":
				continue
			eligible += 1
			if not u.is_person() or not w.is_night():
				awake += 1
		if eligible == 0:
			reasons.append(Loc.t("production.no_operator"))
		elif awake == 0:
			reasons.append(Loc.t("production.night"))
	return "\n".join(reasons)


static func building_text(w: World, b: Building) -> String:
	if b == null or not _included(b):
		return ""
	return _process_text(w, b) + "\n" + _building_status(w, b)


func _update_harvest(w: World) -> void:
	var nodes: Dictionary = {}
	var zone_counts := {"logging": 0, "mining": 0, "forage": 0}
	var visited: Dictionary = {}
	for zone: Dictionary in w.zones:
		var type := str(zone["type"])
		if not zone_counts.has(type):
			continue
		zone_counts[type] = int(zone_counts[type]) + 1
		var rect: Rect2i = zone["rect"]
		for x in range(rect.position.x, rect.end.x):
			for y in range(rect.position.y, rect.end.y):
				var tile := Vector2i(x, y)
				if visited.has(tile):
					continue
				var resource := w.res_at(tile)
				if Tiles.zone_for(resource) != type or w.res_amount_at(tile) <= 0:
					continue
				visited[tile] = true
				var output := str(Tiles.res_info(resource).get("yield", ""))
				nodes[output] = int(nodes.get(output, 0)) + w.res_amount_at(tile)
	var harvest_lines := PackedStringArray([Loc.t("production.harvest")])
	for type: String in zone_counts:
		harvest_lines.append(Loc.t("production.zones", {"type": Loc.t("production.zone." + type), "count": zone_counts[type]}))
	harvest_lines.append(Loc.t("production.harvest_remaining", {"resources": _resources(nodes)}))
	if visited.is_empty():
		harvest_lines.append(Loc.t("production.no_nodes"))
	if int(w.priorities.get("gather", 2)) == 0:
		harvest_lines.append(Loc.t("production.priority_off", {"priority": Loc.t("production.priority.gather")}))
	_harvest.text = "\n".join(harvest_lines)
	var stages := [0, 0, 0, 0]
	var growth := 0.0
	for farm: Dictionary in w.farm.values():
		var stage := int(farm.get("stage", 0))
		stages[stage] += 1
		if stage == 2:
			growth += float(farm.get("growth", 0.0))
	_farms.text = Loc.t("production.farm", {"till": stages[0], "plant": stages[1], "grow": stages[2], "ready": stages[3], "percent": int(growth / maxf(1.0, float(stages[2])) * 100.0)})
	if int(w.priorities.get("farm", 2)) == 0:
		_farms.text += "\n" + Loc.t("production.priority_off", {"priority": Loc.t("production.priority.farm")})
	var workers := PackedStringArray()
	var gatherers := 0
	var farmers := 0
	for u: Unit in w.unit_list:
		if not w.colony.is_worker(u):
			continue
		var type := str(u.job.get("type", ""))
		if type == "gather":
			gatherers += 1
		elif type == "farm":
			farmers += 1
		if type in ["gather", "farm", "deliver"]:
			workers.append(Loc.t("production.worker_line", {"name": u.name, "status": _worker_status(w, u)}))
	if gatherers == 0:
		workers.append(Loc.t("production.no_gatherer"))
	if farmers == 0 and int(stages[0]) + int(stages[1]) + int(stages[3]) > 0:
		workers.append(Loc.t("production.no_farmer"))
	if w.is_night():
		workers.append(Loc.t("production.harvest_night"))
	_workers.text = "\n".join(workers)


static func build_controls(body: VBoxContainer, game: Game, h: Hud, b: Building, changed: Callable) -> void:
	if b.type != "workshop" or b.faction != "player" or not b.is_built():
		return
	var controls := WorkshopControls.new()
	body.add_child(controls)
	controls.setup(game, h, b, changed)


class WorkshopControls extends VBoxContainer:
	var game: Game
	var building: Building
	var changed: Callable
	var heading: Label
	var queue_label: Label
	var options: Dictionary = {}

	func setup(g: Game, _hud: Hud, b: Building, callback: Callable) -> void:
		game = g
		building = b
		changed = callback
		name = "ProductionQueueControls"
		add_theme_constant_override("separation", 8)
		heading = ProductionPanel._text(self, "", 14)
		queue_label = ProductionPanel._text(self, "", 14)
		queue_label.name = "ProductionQueueOrder"
		for arch: String in b.def().get("produces", []):
			var option := UiTheme.vbox(3)
			add_child(option)
			var button := UiTheme.button("")
			button.name = "ProductionQueue_" + arch
			button.set_meta("archetype", arch)
			button.set_meta("building_id", b.id)
			button.focus_mode = Control.FOCUS_ALL
			button.pressed.connect(_enqueue.bind(arch))
			option.add_child(button)
			var cost := ProductionPanel._text(option, "", 14)
			cost.name = "ProductionCost_" + arch
			var reason := ProductionPanel._text(option, "", 13)
			reason.name = "ProductionReason_" + arch
			options[arch] = {"button": button, "cost": cost, "reason": reason}
		# InfoPanel shares these controls but does not own their refresh loop.
		# Only labels/disabled flags update; controls retain hover and keyboard focus.
		var timer := Timer.new()
		timer.wait_time = 0.3
		timer.timeout.connect(refresh)
		add_child(timer)
		timer.start()
		refresh()

	func _reason(arch: String) -> String:
		var reasons := PackedStringArray()
		if game.world.buildings.get(building.id) != building or not building.is_built() or building.faction != "player":
			reasons.append(Loc.t("production.workshop_unavailable"))
		if building.queue.size() >= 5:
			reasons.append(Loc.t("production.queue_full"))
		var cost: Dictionary = game.world.colony._archetype(arch).get("cost", {})
		for resource: String in cost:
			var have := int(game.world.res.get(resource, 0))
			var need := int(cost[resource])
			if have < need:
				reasons.append(Loc.t("production.shortage", {"resource": Loc.t(resource), "have": have, "need": need, "missing": need - have}))
		return "\n".join(reasons)

	func refresh() -> void:
		if not is_visible_in_tree():
			return
		heading.text = Loc.t("production.queue_help")
		var order := PackedStringArray([Loc.t("production.queue_count", {"count": building.queue.size()})])
		for index in building.queue.size():
			order.append(Loc.t("production.queue_entry", {"index": index + 1, "machine": ProductionPanel._machine_name(str(building.queue[index])), "state": Loc.t("production.queue_progress", {"percent": int(ProductionPanel._progress(game.world, building) * 100.0)}) if index == 0 else Loc.t("production.queue_waiting")}))
		queue_label.text = "\n".join(order)
		for arch: String in options:
			var row: Dictionary = options[arch]
			var button: Button = row["button"]
			var ad := game.world.colony._archetype(arch)
			button.text = Loc.t("production.enqueue", {"machine": ProductionPanel._machine_name(arch)})
			button.clip_text = true
			var cost_text := Loc.t("production.cost", {"resources": ProductionPanel._resources(ad.get("cost", {})), "seconds": ad.get("build_time", 60)})
			(row["cost"] as Label).text = cost_text
			var reason := _reason(arch)
			button.disabled = not reason.is_empty()
			button.tooltip_text = cost_text + "\n" + (reason if not reason.is_empty() else Loc.t("production.affordable"))
			(row["reason"] as Label).text = reason if not reason.is_empty() else Loc.t("production.affordable")
			(row["reason"] as Label).add_theme_color_override("font_color", UiTheme.BAD if not reason.is_empty() else UiTheme.GOOD)

	func _enqueue(arch: String) -> void:
		# Recheck at click time; progress, other controls and spending can change between refreshes.
		var reason := _reason(arch)
		if not reason.is_empty():
			game.toast.emit(reason, "bad")
			Sfx.play(&"ui_error")
			refresh()
			return
		var cost: Dictionary = game.world.colony._archetype(arch).get("cost", {})
		if game.world.economy.pay(cost):
			building.queue.append(arch)
			Sfx.play(&"ui_confirm")
			refresh()
			if changed.is_valid():
				changed.call()
