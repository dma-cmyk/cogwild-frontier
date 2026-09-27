class_name SquadPicker
extends PopupPanel

var g: Game
var hud: Hud
var target_squad_id := -1
var rows: VBoxContainer
var _rows_scroll: ScrollContainer
var _summary: Label
var _confirm_button: Button
var _selected_ids: Dictionary = {}

func setup(game: Game, h: Hud) -> void:
	g = game
	hud = h
	name = "SquadPicker"
	position = Vector2(180, 180)
	size = Vector2(480, 460)
	var outer := UiTheme.vbox(6)
	var frame := UiTheme.panel()
	var frame_style: StyleBoxFlat = UiTheme.panel_box()
	frame_style.bg_color.a = 0.98
	frame.add_theme_stylebox_override("panel", frame_style)
	frame.add_child(outer)
	add_child(frame)
	var head := UiTheme.hbox(8)
	head.add_child(UiTheme.title(Loc.t("Add squad members"), 19))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var close := UiTheme.button("", "ui_close", Loc.t("Close"))
	close.custom_minimum_size = Vector2(44, 44)
	close.pressed.connect(hide)
	head.add_child(close)
	outer.add_child(head)
	_summary = UiTheme.label("", 14, UiTheme.TEXT_DIM)
	outer.add_child(_summary)
	_rows_scroll = ScrollContainer.new()
	_rows_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rows_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(_rows_scroll)
	rows = UiTheme.vbox(4)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_scroll.add_child(rows)
	_confirm_button = UiTheme.button(Loc.t("Add selected"), "ui_people")
	_confirm_button.custom_minimum_size = Vector2(0, 44)
	_confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_button.pressed.connect(_confirm_add)
	outer.add_child(_confirm_button)


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("cancel"):
		return
	if g.input_ctl.mode != "":
		g.input_ctl.set_mode("")
		get_viewport().set_input_as_handled()
		call_deferred("_reopen")
	else:
		hide()
		get_viewport().set_input_as_handled()


func open_for(squad_id: int, selected_units: Array[int] = []) -> void:
	target_squad_id = squad_id
	_selected_ids.clear()
	for unit_id: int in selected_units:
		_selected_ids[unit_id] = true
	_rebuild()
	_reopen()


func _reopen() -> void:
	var popup_size := Vector2i(480, 460)
	if hud._compact:
		var screen := App.screen_size()
		popup_size = Vector2i(roundi(minf(480.0, screen.x - 24.0)), roundi(minf(460.0, screen.y - 24.0)))
		_rows_scroll.custom_minimum_size = Vector2(0, maxf(120.0, float(popup_size.y) - 138.0))
	else:
		_rows_scroll.custom_minimum_size = Vector2(440, 330)
	size = Vector2(popup_size)
	popup_centered(popup_size)


func button_for_unit(unit_id: int) -> CheckButton:
	for row: Control in rows.get_children():
		if int(row.get_meta("unit_id", -1)) == unit_id:
			return row.get_child(2) as CheckButton
	return null


func _rebuild() -> void:
	for child in rows.get_children():
		child.queue_free()
	var squad := g.world.get_squad(target_squad_id)
	if squad == null:
		_update_selection_controls()
		return
	var candidates: Array[Unit] = []
	for unit: Unit in g.world.unit_list:
		if unit.alive and unit.is_player() and unit.kind != "airship" and not squad.members.has(unit.id):
			candidates.append(unit)
	candidates.sort_custom(func(a: Unit, b: Unit) -> bool:
		var a_idle: bool = a.order.is_empty() and str(a.job.get("type", "idle")) == "idle"
		var b_idle: bool = b.order.is_empty() and str(b.job.get("type", "idle")) == "idle"
		if a_idle != b_idle:
			return a_idle
		return a.pos.distance_squared_to(g.world.home_pos()) < b.pos.distance_squared_to(g.world.home_pos()))
	var candidate_ids: Dictionary = {}
	for unit: Unit in candidates:
		candidate_ids[unit.id] = true
	for unit_id: Variant in _selected_ids.keys():
		if not candidate_ids.has(int(unit_id)):
			_selected_ids.erase(unit_id)
	var slots := maxi(0, 6 - squad.members.size())
	var selected_ids: Array[int] = []
	for unit_id: Variant in _selected_ids.keys():
		selected_ids.append(int(unit_id))
	selected_ids.sort()
	while selected_ids.size() > slots:
		_selected_ids.erase(selected_ids.pop_back())
	for unit: Unit in candidates:
		var row := UiTheme.hbox(8)
		row.set_meta("unit_id", unit.id)
		row.custom_minimum_size = Vector2(0, 58)
		var portrait := TextureRect.new()
		portrait.texture = hud.portraits.get_portrait("u%d" % unit.id, unit.dna, 64)
		portrait.custom_minimum_size = Vector2(44, 44)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(portrait)
		var detail := UiTheme.vbox(1)
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		detail.add_child(UiTheme.label(unit.name, 15))
		var role := Loc.t(unit.display_role()) if unit.is_person() else Loc.t(unit.kind.capitalize())
		var context := Loc.t("Job: %s") % Loc.t(str(unit.job.get("type", unit.order.get("type", "idle"))).capitalize())
		if unit.squad_id >= 0:
			var old := g.world.get_squad(unit.squad_id)
			if old:
				context = Loc.t("Member of %s") % old.name
		detail.add_child(UiTheme.label("%s · Lv.%d · %s" % [role, unit.char_level(), context], 12, UiTheme.TEXT_DIM))
		row.add_child(detail)
		var select := CheckButton.new()
		select.custom_minimum_size = Vector2(44, 44)
		select.focus_mode = Control.FOCUS_NONE
		select.button_pressed = _selected_ids.has(unit.id)
		var uid := unit.id
		select.toggled.connect(func(checked: bool) -> void: _on_candidate_toggled(uid, checked))
		row.add_child(select)
		rows.add_child(row)
	if candidates.is_empty():
		rows.add_child(UiTheme.label(Loc.t("No eligible units."), 15, UiTheme.TEXT_DIM))
	_update_selection_controls()


func _on_candidate_toggled(unit_id: int, checked: bool) -> void:
	var squad := g.world.get_squad(target_squad_id)
	if squad == null:
		return
	var button := button_for_unit(unit_id)
	if checked and (squad.members.size() >= 6 or (_selected_ids.size() >= 6 - squad.members.size() and not _selected_ids.has(unit_id))):
		if button:
			button.set_pressed_no_signal(false)
		return
	if checked:
		_selected_ids[unit_id] = true
	else:
		_selected_ids.erase(unit_id)
	_update_selection_controls()


func _update_selection_controls() -> void:
	var squad := g.world.get_squad(target_squad_id)
	var slots := maxi(0, 6 - squad.members.size()) if squad else 0
	var selected_count := _selected_ids.size()
	if slots == 0:
		_summary.text = Loc.t("Squad is full (%d/6).") % (squad.members.size() if squad else 0)
	else:
		_summary.text = Loc.t("%d selected · %d slots available") % [selected_count, slots]
	_confirm_button.text = Loc.t("Add %d selected") % selected_count
	_confirm_button.disabled = squad == null or selected_count == 0 or selected_count > slots
	for row: Control in rows.get_children():
		var unit_id := int(row.get_meta("unit_id", -1))
		var selected := _selected_ids.has(unit_id)
		var button := row.get_child(2) as CheckButton
		button.disabled = not selected and (slots == 0 or selected_count >= slots)


func _confirm_add() -> void:
	var squad := g.world.get_squad(target_squad_id)
	if squad == null:
		hide()
		return
	var unit_ids: Array[int] = []
	for unit_id: Variant in _selected_ids.keys():
		unit_ids.append(int(unit_id))
	unit_ids.sort()
	var added := 0
	for unit_id: int in unit_ids:
		var unit := g.world.get_unit(unit_id)
		if unit and unit.alive and g.world.assign_to_squad(unit, squad):
			g.world.combat.enlist(unit)
			added += 1
	if added == 0:
		_rebuild()
		return
	hud.squad_panel.all_squads_active = false
	g.select_squad(squad.id)
	hud._update_commands()
	hud.add_note({"key": "ui.squad.joined", "params": {"count": added, "name": squad.name}, "kind": "info"}, 3.0)
	hide()
