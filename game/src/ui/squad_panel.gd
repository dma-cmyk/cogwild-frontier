class_name SquadPanel
extends PanelContainer
## Bottom-centre squad panel: squad tabs, the selected squad's name, size and current activity,
## member cards (portrait, class, level, health and energy) and the retreat threshold.

var g: Game
var hud: Hud
var _body: VBoxContainer
var _head: HBoxContainer
var _tabs: HBoxContainer
var _tabs_scroll: ScrollContainer
var _name: Label
var _count: Label
var _state: Label
var _cards: HBoxContainer
var _card_scroll: ScrollContainer
var _slider: HSlider
var _slider_label: Label
var _add_btn: Button
var _split_selected_btn: Button
var _rename_btn: Button
var _expand_btn: Button
var _close_btn: Button
var _rename_edit: LineEdit
var _auto_toggle: CheckButton
var _tab_new_btn: Button
var _disband_btn: Button
var _picker_btn: Button
var _foot: HBoxContainer
var _actions: HBoxContainer
var _shown_model := ""
var _compact := false
var _stance_select: OptionButton
var _formation_select: OptionButton
var _card_refs: Array = []  # [unit_id, hp_bar, en_bar, lv_label, frame]
var _picker: SquadPicker
var all_squads_active := false
var _renaming := false
var _compact_collapsed := false
var _last_quick_squad_id := -1
var _layout_initialized := false
var _last_quick_squad_msec := 0

func setup(game: Game, h: Hud) -> void:
	g = game
	hud = h
	name = "SquadPanel"
	clip_contents = true
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -655
	offset_right = -80
	offset_top = -206
	offset_bottom = -10
	_body = UiTheme.vbox(5)
	add_child(_body)
	_head = UiTheme.hbox(6)
	var head := _head
	_body.add_child(head)
	head.add_child(UiTheme.icon("ui_squad", 24))
	_name = UiTheme.title(Loc.t("No squad"), 18)
	_name.custom_minimum_size = Vector2(100, 0)
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.clip_text = true
	head.add_child(_name)
	_rename_btn = UiTheme.button("", "ui_rename", Loc.t("Rename squad"))
	_rename_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rename_btn.custom_minimum_size = Vector2(32, 30)
	_rename_btn.pressed.connect(_begin_rename)
	head.add_child(_rename_btn)
	_rename_edit = LineEdit.new()
	_rename_edit.max_length = 16
	_rename_edit.custom_minimum_size = Vector2(160, 32)
	_rename_edit.visible = false
	_rename_edit.text_submitted.connect(_commit_rename)
	_rename_edit.focus_exited.connect(_commit_rename)
	_rename_edit.gui_input.connect(_rename_input)
	head.add_child(_rename_edit)
	_count = UiTheme.label("", 16, UiTheme.TEXT_DIM)
	head.add_child(_count)
	_state = UiTheme.label("", 14, UiTheme.ACCENT)
	_state.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_state.clip_text = true
	head.add_child(_state)
	_tabs = UiTheme.hbox(4)
	_tabs.mouse_filter = Control.MOUSE_FILTER_PASS
	_tabs_scroll = ScrollContainer.new()
	_tabs_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_tabs_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs_scroll.custom_minimum_size.y = 44
	_tabs_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs_scroll.add_child(_tabs)
	head.add_child(_tabs_scroll)
	_tab_new_btn = UiTheme.button(Loc.t("＋ New squad"), "ui_squad", Loc.t("Create a squad from selected units, or start an empty squad."))
	_tab_new_btn.custom_minimum_size = Vector2(140, 44)
	_tab_new_btn.pressed.connect(_on_new)
	head.add_child(_tab_new_btn)
	_expand_btn = UiTheme.button("", "ui_expand", Loc.t("Squad menu"))
	_expand_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_expand_btn.visible = false
	_expand_btn.custom_minimum_size = Vector2(32, 32)
	_expand_btn.pressed.connect(func() -> void: _set_compact_collapsed(not _compact_collapsed))
	head.add_child(_expand_btn)
	_close_btn = UiTheme.button("", "ui_close", Loc.t("Close squad menu"))
	_close_btn.visible = false
	_close_btn.pressed.connect(func() -> void:
		visible = false
		hud._squad_toggle.visible = true)
	head.add_child(_close_btn)
	_card_scroll = ScrollContainer.new()
	_card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_card_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_card_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(_card_scroll)
	_cards = UiTheme.hbox(6)
	_card_scroll.add_child(_cards)
	_foot = UiTheme.hbox(8)
	_body.add_child(_foot)
	_foot.add_child(UiTheme.icon("cmd_retreat", 20))
	_slider_label = UiTheme.label(Loc.t("Retreat at %d%%") % 30, 14, UiTheme.TEXT_DIM)
	_slider_label.custom_minimum_size = Vector2(110, 0)
	_foot.add_child(_slider_label)
	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 0.6
	_slider.step = 0.05
	_slider.custom_minimum_size = Vector2(76, 18)
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.focus_mode = Control.FOCUS_NONE
	_slider.tooltip_text = Loc.t("The squad falls back to the hearth when its total health drops below this.")
	_slider.value_changed.connect(_on_threshold)
	_foot.add_child(_slider)
	_stance_select = OptionButton.new()
	var stance_labels: Array[String] = ["Aggressive", "Balanced", "Cautious", "Hold"]
	var stance_icons: Array[String] = ["stance_aggressive", "stance_balanced", "stance_cautious", "stance_hold"]
	for i in stance_labels.size():
		_stance_select.add_item(Loc.t(stance_labels[i]))
		_stance_select.set_item_icon(i, Icons.get_icon(stance_icons[i]))
	_stance_select.tooltip_text = Loc.t("Aggressive: chase and strike. Balanced: standard orders. Cautious: kite and retreat early. Hold: stay near the order point.")
	_stance_select.focus_mode = Control.FOCUS_NONE
	_stance_select.item_selected.connect(_on_tactics_changed)
	_foot.add_child(_stance_select)
	_formation_select = OptionButton.new()
	for label: String in ["Line", "Wedge", "Loose"]:
		_formation_select.add_item(Loc.t(label))
	_formation_select.tooltip_text = Loc.t("Line: broad front. Wedge: pointed advance. Loose: wider spacing.")
	_formation_select.focus_mode = Control.FOCUS_NONE
	_formation_select.item_selected.connect(_on_tactics_changed)
	_foot.add_child(_formation_select)
	_auto_toggle = CheckButton.new()
	_auto_toggle.text = Loc.t("Auto abilities")
	_auto_toggle.tooltip_text = Loc.t("Let squad members use abilities automatically.")
	_auto_toggle.toggled.connect(func(enabled: bool) -> void:
		var squad := _squad()
		if squad:
			squad.auto_abilities = enabled)
	_foot.add_child(_auto_toggle)
	Loc.language_changed.connect(_refresh_tactic_labels)
	_actions = UiTheme.hbox(6)
	_add_btn = UiTheme.button(Loc.t("Add selected"), "ui_people", Loc.t("Add selected units to this squad."))
	_add_btn.pressed.connect(_on_add)
	_actions.add_child(_add_btn)
	_picker_btn = UiTheme.button(Loc.t("Add member"), "ui_people", Loc.t("Choose a unit to add to this squad."))
	_picker_btn.pressed.connect(_open_picker)
	_actions.add_child(_picker_btn)
	_split_selected_btn = UiTheme.button(Loc.t("One-person squad"), "ui_squad", Loc.t("Create a squad for the selected worker."))
	_split_selected_btn.pressed.connect(_split_selected_into_own_squad)
	_actions.add_child(_split_selected_btn)
	_disband_btn = UiTheme.button(Loc.t("Disband"), "ui_close", Loc.t("Disband this squad and return its members to work."))
	_disband_btn.pressed.connect(_confirm_disband)
	_actions.add_child(_disband_btn)
	_foot.add_child(_actions)
	_picker = SquadPicker.new()
	add_child(_picker)
	_picker.setup(g, hud)
func picker_open() -> bool:
	return _picker.visible


func close_picker() -> void:
	_picker.hide()


func keep_picker_open_after_mode_cancel() -> void:
	_picker.call_deferred("popup_centered", Vector2i(440, 460))


func set_compact(compact: bool) -> void:
	if _layout_initialized and _compact == compact:
		return
	_layout_initialized = true
	_compact = compact
	_compact_collapsed = compact
	_body.add_theme_constant_override("separation", 4 if compact else 5)
	_expand_btn.visible = compact
	_expand_btn.custom_minimum_size = Vector2(44, 44)
	_close_btn.custom_minimum_size = Vector2(44, 44)
	_rename_btn.custom_minimum_size = Vector2(44, 44) if compact else Vector2(32, 30)
	_tab_new_btn.custom_minimum_size = Vector2(156, 44)
	_tabs_scroll.custom_minimum_size.y = 56 if compact else 44
	_stance_select.custom_minimum_size = Vector2(120, 44) if compact else Vector2(98, 30)
	_formation_select.custom_minimum_size = Vector2(104, 44) if compact else Vector2(86, 30)
	_auto_toggle.custom_minimum_size = Vector2(144, 44) if compact else Vector2(122, 30)
	for child in _actions.get_children():
		(child as Control).custom_minimum_size = Vector2(0, 44 if compact else 30)
	# phones: the member actions get their own row so the expanded panel stays narrow enough to
	# sit beside the details drawer
	var actions_parent: Node = _body if compact else _foot
	if _actions.get_parent() != actions_parent:
		_actions.get_parent().remove_child(_actions)
		actions_parent.add_child(_actions)
	_apply_compact_layout()
	refresh(true)


func _set_compact_collapsed(collapsed: bool) -> void:
	_compact_collapsed = collapsed
	_apply_compact_layout()
	refresh(true)


func _apply_compact_layout() -> void:
	var collapsed := _compact and _compact_collapsed
	# SVG chevrons: symbol glyphs such as ▾ are missing from the web build's fonts
	_expand_btn.icon = Icons.get_icon("ui_expand" if collapsed else "ui_collapse")
	_expand_btn.tooltip_text = Loc.t("Squad menu")
	_head.get_child(0).visible = not collapsed
	_name.visible = not collapsed
	_rename_btn.visible = _rename_btn.visible and not collapsed
	_rename_edit.visible = false if collapsed else _renaming
	_count.visible = not collapsed
	_state.visible = not collapsed
	_close_btn.visible = false
	if _card_scroll.get_parent() != _body:
		_card_scroll.get_parent().remove_child(_card_scroll)
		_body.add_child(_card_scroll)
		_body.move_child(_card_scroll, 1)
	_card_scroll.custom_minimum_size = Vector2(0, 54) if collapsed else Vector2(0, 124) if _compact else Vector2(6.0 * 106.0 + 5.0 * 6.0, 118)
	_cards.custom_minimum_size = Vector2(0, 52) if collapsed else Vector2.ZERO
	_foot.visible = not collapsed and _squad() != null
	_actions.visible = not collapsed and (_squad() != null or _split_selected_btn.visible)
func _begin_rename() -> void:
	var squad := _squad()
	if squad == null:
		return
	_renaming = true
	_rename_edit.text = squad.name
	_name.visible = false
	_rename_btn.visible = false
	_rename_edit.visible = true
	_rename_edit.grab_focus()
	_rename_edit.select_all()


func _commit_rename(_submitted_text: String = "") -> void:
	if not _renaming:
		return
	_renaming = false
	var squad := _squad()
	var clean_name := _rename_edit.text.strip_edges()
	if squad and not clean_name.is_empty():
		squad.name = clean_name
		g.world.squads_changed.emit()
	_rename_edit.visible = false
	_name.visible = true
	_rename_btn.visible = true
	refresh(true)
	hud._update_commands()


func _rename_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_renaming = false
		_rename_edit.visible = false
		_name.visible = true
		_rename_btn.visible = true
		_rename_edit.release_focus()
		_rename_edit.accept_event()


func _squad() -> Squad:
	return g.world.get_squad(g.viewed_squad_id)
func fallback_if_empty(squad_id: int) -> void:
	var emptied := g.world.get_squad(squad_id)
	if emptied == null or not emptied.members.is_empty() or g.viewed_squad_id != squad_id:
		return
	for squad: Squad in g.world.squads:
		if squad.id != squad_id and not squad.members.is_empty():
			g.viewed_squad_id = squad.id
			return
	for squad: Squad in g.world.squads:
		if squad.id != squad_id:
			g.viewed_squad_id = squad.id
			return
	g.viewed_squad_id = squad_id




func _open_picker() -> void:
	var s := _squad()
	if s:
		_picker.open_for(s.id)


func _confirm_disband() -> void:
	var s := _squad()
	if s == null:
		return
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = Loc.t("Disband %s? Members will return to work.") % s.name
	dialog.confirmed.connect(func() -> void:
		if not g.world.disband_squad(s.id):
			return
		all_squads_active = false
		g.clear_selection()
		g.viewed_squad_id = g.world.squads[0].id if not g.world.squads.is_empty() else -1
		if g.viewed_squad_id >= 0:
			g.view_squad(g.viewed_squad_id)
		hud._update_commands()
		refresh(true))
	add_child(dialog)
	dialog.popup_centered()

func refresh(force: bool) -> void:
	var target_ids := hud.command_squad_ids()
	var s: Squad = _squad() if target_ids.size() == 1 and not all_squads_active else null
	var members: Array = hud.command_units()
	_rebuild_tabs(_squad())
	var member_ids: Array[String] = []
	for unit: Unit in members:
		member_ids.append(str(unit.id))
	var model := ("all:" if all_squads_active else "squads:%s:" % str(target_ids)) + ",".join(member_ids)
	if force or model != _shown_model:
		_shown_model = model
		_rebuild_cards(members, s)
	_cards.visible = true
	_name.add_theme_color_override("font_color", s.color().lerp(UiTheme.TEXT, 0.35) if s else UiTheme.TEXT)
	if all_squads_active:
		_name.text = Loc.t("All squads")
		_count.text = Loc.t("%d selected") % members.size()
	elif s:
		_name.text = s.name
		_count.text = "%d/6" % s.members.size()
	else:
		_name.text = Loc.t("%d squads") % target_ids.size() if target_ids.size() > 1 else Loc.t("No squad")
		_count.text = Loc.t("%d selected") % members.size() if not members.is_empty() else ""
	_state.text = _state_text(s) if s else _state_text_for_members(members)
	# The tab still shows a squad when the orders address a selected villager or drone — and that
	# is exactly when the player reaches for "Add selected", so these follow the tab, not the
	# recipient of the orders.
	var tab_squad: Squad = s if s != null else (_squad() if target_ids.is_empty() and not all_squads_active else null)
	_rename_btn.visible = tab_squad != null
	var add_count := 0
	if tab_squad:
		for unit: Unit in g.selected_units():
			if unit.is_player() and unit.squad_id != tab_squad.id and unit.kind != "airship":
				add_count += 1
	_add_btn.visible = tab_squad != null and add_count > 0
	_add_btn.text = Loc.t("Add %d selected") % add_count
	_add_btn.disabled = tab_squad == null or tab_squad.members.size() >= 6
	_picker_btn.visible = tab_squad != null
	_picker_btn.disabled = tab_squad == null or tab_squad.members.size() >= 6
	_tab_new_btn.disabled = g.world.squads.size() >= World.MAX_SQUADS
	_tab_new_btn.text = Loc.t("＋ New squad (%d/9)") % g.world.squads.size() if _tab_new_btn.disabled else Loc.t("＋ New squad")
	_tab_new_btn.tooltip_text = Loc.t("Maximum 9 squads (hotkeys 1–9).") if _tab_new_btn.disabled else Loc.t("Create a squad from selected units, or start an empty squad.")
	var selected := g.selected_units()
	var split_unit: Unit = selected[0] if selected.size() == 1 else null
	_split_selected_btn.visible = split_unit != null and split_unit.is_player() and split_unit.kind != "airship" and split_unit.squad_id < 0
	var focus := g.focus_unit()
	_disband_btn.visible = tab_squad != null
	_actions.visible = tab_squad != null or _split_selected_btn.visible
	_foot.visible = tab_squad != null or _actions.visible
	for i in range(3, 6):
		_foot.get_child(i).visible = s != null
	if _compact:
		offset_bottom = -80.0
		offset_top = offset_bottom - (122.0 if _compact_collapsed else 292.0)
	else:
		offset_top = offset_bottom
	_apply_compact_layout()
	if s:
		_stance_select.select(["aggressive", "balanced", "cautious", "hold"].find(s.stance))
		_formation_select.select(["line", "wedge", "loose"].find(s.formation))
		_slider.value = s.retreat_threshold
		_slider_label.text = Loc.t("Retreat at %d%%") % int(s.retreat_threshold * 100)
		_auto_toggle.set_pressed_no_signal(s.auto_abilities)
	for ref: Array in _card_refs:
		var u := g.world.get_unit(int(ref[0]))
		if u == null:
			continue
		(ref[1] as ProgressBar).value = u.hp_ratio() if u.alive else 0.0
		var en := u.energy / maxf(1.0, float(u.stats.get("energy_max", 100.0))) if u.is_person() else float(g.world.res.get("energy", 0)) / 100.0
		(ref[2] as ProgressBar).value = clampf(en, 0.0, 1.0)
		(ref[3] as Label).text = "Lv.%d" % u.char_level()
		var frame: PanelContainer = ref[4]
		var sel := focus != null and focus.id == u.id
		var col := UiTheme.ACCENT if sel else (UiTheme.BAD if u.state == Unit.State.DOWNED or not u.alive else UiTheme.BORDER_DIM)
		frame.add_theme_stylebox_override("panel", UiTheme.flat(Color(0.08, 0.11, 0.17, 0.95), 6, col, 2))


func _state_text_for_members(members: Array) -> String:
	if members.is_empty():
		return ""
	var common := ""
	for unit: Unit in members:
		var activity := str(unit.order.get("type", unit.job.get("type", "idle")))
		if unit.state == Unit.State.DOWNED:
			activity = "Downed"
		if common.is_empty():
			common = activity
		elif common != activity:
			common = "Mixed orders"
			break
	return Loc.t("Now: %s") % Loc.t(common.capitalize())

func _state_text(s: Squad) -> String:
	var order := str(s.order.get("type", "idle"))
	var activity := s.state
	if activity == "" or activity == "holding":
		activity = "Holding position" if order == "idle" else order.capitalize()
	var activity_key := activity.capitalize()
	if activity == "Holding position":
		activity_key = activity
	return Loc.t(order.capitalize()) + " · " + Loc.t(activity_key)


func _rebuild_tabs(current: Squad) -> void:
	var ids: Array[int] = []
	var names: Array[String] = []
	for squad: Squad in g.world.squads:
		ids.append(squad.id)
		names.append(squad.name)
	var current_id := current.id if current else -1
	if _tabs.get_meta("ids", []) == ids and _tabs.get_meta("names", []) == names \
			and _tabs.get_meta("cur", -1) == current_id and _tabs.get_meta("all", false) == all_squads_active \
			and _tabs.get_meta("language", "") == Loc.language:
		return
	_tabs.set_meta("ids", ids)
	_tabs.set_meta("names", names)
	_tabs.set_meta("cur", current_id)
	_tabs.set_meta("all", all_squads_active)
	_tabs.set_meta("language", Loc.language)
	for child in _tabs.get_children():
		child.queue_free()
	var all_button := UiTheme.button(Loc.t("All squads") if not _compact else "", "ui_squad", Loc.t("Give orders to every squad."))
	all_button.custom_minimum_size = Vector2(48 if _compact else 88, 48 if _compact else 44)
	if all_squads_active:
		all_button.add_theme_stylebox_override("normal", UiTheme.button_box("pressed"))
	all_button.pressed.connect(func() -> void:
		all_squads_active = true
		refresh(true)
		hud._update_commands())
	_tabs.add_child(all_button)
	for i in g.world.squads.size():
		var squad: Squad = g.world.squads[i]
		var button := UiTheme.button(str(i + 1) if _compact else "%d %s" % [i + 1, squad.name.left(12)], "", Loc.t("Select %s (key %d)") % [squad.name, i + 1])
		button.custom_minimum_size = Vector2(48 if _compact else 104, 48 if _compact else 44)
		button.add_theme_font_size_override("font_size", 13)
		if current and squad.id == current.id and not all_squads_active:
			button.add_theme_stylebox_override("normal", UiTheme.button_box("pressed"))
		var squad_id := squad.id
		button.pressed.connect(func() -> void: _activate_squad(squad_id))
		_tabs.add_child(button)


func _activate_squad(squad_id: int) -> void:
	var now := Time.get_ticks_msec()
	var center := _last_quick_squad_id == squad_id and now - _last_quick_squad_msec <= 450
	_last_quick_squad_id = squad_id
	_last_quick_squad_msec = now
	_show_squad(squad_id)
	if center:
		var squad := g.world.get_squad(squad_id)
		if squad and not squad.members.is_empty():
			g.focus_pos(g.world.squad_ai.center(squad))


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not (event as InputEventKey).pressed or (event as InputEventKey).echo:
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	var index := -1
	for i in 9:
		if event.is_action_pressed("squad_%d" % (i + 1)):
			index = i
			break
	if index < 0:
		return
	if index >= g.world.squads.size():
		return
	_activate_squad(g.world.squads[index].id)
	get_viewport().set_input_as_handled()


func _show_squad(squad_id: int) -> void:
	all_squads_active = false
	g.clear_selection()
	g.view_squad(squad_id)
	hud._update_commands()
	refresh(true)

func _focus_card_member(unit_id: int) -> void:
	all_squads_active = false
	g.focus_member(unit_id)
	hud._update_commands()
	hud.info_panel.refresh(true)
	hud.info_panel.open_drawer()


func _rebuild_cards(members: Array, squad: Squad) -> void:
	for child in _cards.get_children():
		child.queue_free()
	_card_refs.clear()
	for unit: Unit in members:
		if _compact and _compact_collapsed:
			var mini := Button.new()
			mini.custom_minimum_size = Vector2(48, 48)
			mini.tooltip_text = "%s — %s" % [unit.name, Loc.t("Click to focus this member's details.")]
			var mini_pic := TextureRect.new()
			mini_pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			mini_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			mini_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			mini_pic.texture = hud.portraits.get_portrait("u%d" % unit.id, unit.dna, 128)
			mini_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			mini.add_child(mini_pic)
			var mini_unit_id := unit.id
			mini.pressed.connect(func() -> void: _focus_card_member(mini_unit_id))
			_cards.add_child(mini)
			continue
		var frame := PanelContainer.new()
		frame.set_meta("unit_id", unit.id)
		frame.add_theme_stylebox_override("panel", UiTheme.flat(Color(0.08, 0.11, 0.17, 0.95), 6, UiTheme.BORDER_DIM, 2))
		frame.custom_minimum_size = Vector2(128, 124) if _compact else Vector2(106, 136)
		frame.mouse_filter = Control.MOUSE_FILTER_STOP
		frame.tooltip_text = "%s — %s. %s" % [unit.name, Loc.t(unit.display_role()), Loc.t("Click to focus this member's details.")]
		var body := UiTheme.vbox(2)
		frame.add_child(body)
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var portrait := Control.new()
		portrait.custom_minimum_size = Vector2(72, 66)
		portrait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(portrait)
		var pic := TextureRect.new()
		pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.texture = hud.portraits.get_portrait("u%d" % unit.id, unit.dna, 128)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.add_child(pic)
		var member_squad := g.world.get_squad(unit.squad_id)
		var unit_id := unit.id
		if member_squad and member_squad.members.size() > 1:
			var split := UiTheme.button("", "ui_squad", Loc.t("Split into own squad"))
			split.set_meta("card_action", "split")
			split.custom_minimum_size = Vector2(44, 44) if _compact else Vector2(26, 26)
			split.anchor_left = 0.0
			split.anchor_right = 0.0
			split.anchor_top = 0.0
			split.anchor_bottom = 0.0
			split.offset_left = 0.0
			split.offset_top = 0.0
			split.offset_right = 44.0 if _compact else 26.0
			split.offset_bottom = 44.0 if _compact else 26.0
			split.pressed.connect(func() -> void: _make_own_squad(unit_id))
			portrait.add_child(split)
		if member_squad:
			var remove := UiTheme.button("", "ui_close", Loc.t("Return this member to work."))
			remove.set_meta("card_action", "remove")
			remove.custom_minimum_size = Vector2(44, 44) if _compact else Vector2(26, 26)
			remove.anchor_left = 1.0
			remove.anchor_right = 1.0
			remove.anchor_top = 0.0
			remove.anchor_bottom = 0.0
			remove.offset_left = -44.0 if _compact else -26.0
			remove.offset_top = 0.0
			remove.offset_right = 0.0
			remove.offset_bottom = 44.0 if _compact else 26.0
			remove.pressed.connect(func() -> void: _remove_member(unit_id))
			portrait.add_child(remove)
		var name_label := UiTheme.label(unit.name, 12)
		name_label.clip_text = true
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(name_label)
		var details := UiTheme.hbox(3)
		details.add_child(UiTheme.icon(unit.class_icon(), 18))
		var level := UiTheme.label("Lv.%d" % unit.char_level(), 12)
		details.add_child(level)
		body.add_child(details)
		details.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var hp := UiTheme.bar(Color("#58d65a"), 7)
		hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(hp)
		var energy := UiTheme.bar(Color("#4f9dff"), 5)
		energy.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(energy)
		frame.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				frame.accept_event()
				if not (event as InputEventMouseButton).pressed:
					return
				_focus_card_member(unit_id)
				if (event as InputEventMouseButton).double_click:
					var focused := g.world.get_unit(unit_id)
					if focused:
						g.focus_pos(focused.pos))
		_cards.add_child(frame)
		_card_refs.append([unit.id, hp, energy, level, frame])
	if squad and _compact and _compact_collapsed and members.size() < 6:
		var mini_add := Button.new()
		mini_add.text = "+"
		mini_add.tooltip_text = Loc.t("Add a squad member")
		mini_add.custom_minimum_size = Vector2(48, 48)
		mini_add.add_theme_font_size_override("font_size", 24)
		mini_add.pressed.connect(func() -> void:
			_set_compact_collapsed(false)
			_open_picker())
		_cards.add_child(mini_add)
	elif squad:
		for _i in range(members.size(), 6):
			var slot := Button.new()
			slot.text = "+"
			slot.tooltip_text = Loc.t("Add a squad member")
			slot.custom_minimum_size = Vector2(128, 124) if _compact else Vector2(106, 136)
			slot.add_theme_stylebox_override("normal", UiTheme.flat(Color(0.08, 0.11, 0.17, 0.18), 6, Color(0, 0, 0, 0), 0))
			slot.add_theme_stylebox_override("hover", UiTheme.flat(Color(0.12, 0.16, 0.24, 0.48), 6, Color(0, 0, 0, 0), 0))
			slot.add_theme_font_size_override("font_size", 32)
			slot.draw.connect(func() -> void: _draw_dashed_slot(slot))
			slot.pressed.connect(_open_picker)
			_cards.add_child(slot)

func _draw_dashed_slot(slot: Button) -> void:
	var rect := Rect2(Vector2(5.0, 5.0), slot.size - Vector2(10.0, 10.0))
	var color := Color(0.7, 0.76, 0.88, 0.42)
	var dash_length := 5.0
	var stride := 10.0
	var x := rect.position.x
	while x < rect.end.x - 4.0:
		slot.draw_line(Vector2(x, rect.position.y), Vector2(minf(x + dash_length, rect.end.x), rect.position.y), color, 1.0)
		slot.draw_line(Vector2(x, rect.end.y), Vector2(minf(x + dash_length, rect.end.x), rect.end.y), color, 1.0)
		x += stride
	var y := rect.position.y
	while y < rect.end.y - 4.0:
		slot.draw_line(Vector2(rect.position.x, y), Vector2(rect.position.x, minf(y + dash_length, rect.end.y)), color, 1.0)
		slot.draw_line(Vector2(rect.end.x, y), Vector2(rect.end.x, minf(y + dash_length, rect.end.y)), color, 1.0)
		y += stride



func _split_selected_into_own_squad() -> void:
	var selected := g.selected_units()
	if selected.size() == 1:
		_make_own_squad(selected[0].id)


func _make_own_squad(unit_id: int) -> void:
	var unit := g.world.get_unit(unit_id)
	if unit == null or not unit.is_player() or unit.kind == "airship":
		return
	var old_squad := g.world.get_squad(unit.squad_id)
	if old_squad and old_squad.members.size() == 1:
		all_squads_active = false
		g.select_squad(old_squad.id)
		hud._update_commands()
		return
	var own_squad := g.world.create_squad(Loc.t("%s's squad") % unit.name)
	if own_squad == null:
		hud.add_note({"text": Loc.t("Maximum 9 squads (hotkeys 1–9)."), "kind": "info"}, 3.0)
		refresh(true)
		return
	if not g.world.assign_to_squad(unit, own_squad):
		g.world.disband_squad(own_squad.id)
		return
	g.world.combat.enlist(unit)
	all_squads_active = false
	g.select_squad(own_squad.id)
	hud._update_commands()

func _card_action_button(unit_id: int, action: String) -> Button:
	for frame in _cards.get_children():
		if int(frame.get_meta("unit_id", -1)) != unit_id:
			continue
		for node in frame.find_children("*", "Button", true, false):
			var button := node as Button
			if str(button.get_meta("card_action", "")) == action:
				return button
	return null


func split_button_for_unit(unit_id: int) -> Button:
	return _card_action_button(unit_id, "split")


func remove_button_for_unit(unit_id: int) -> Button:
	return _card_action_button(unit_id, "remove")


func _remove_member(unit_id: int) -> void:
	var unit := g.world.get_unit(unit_id)
	if unit == null or unit.squad_id < 0:
		return
	var squad := g.world.get_squad(unit.squad_id)
	if squad == null:
		return
	var squad_id := squad.id
	var was_all_squads := all_squads_active
	g.world.unassign_from_squad(unit)
	if not was_all_squads:
		fallback_if_empty(squad_id)
		var current := _squad()
		if current:
			g.select_squad(current.id)
		else:
			g.clear_selection()
	hud._update_commands()
	refresh(true)


func _on_threshold(v: float) -> void:
	var s := _squad()
	if s:
		s.retreat_threshold = v
		_slider_label.text = Loc.t("Retreat at %d%%") % int(v * 100)


func _on_add() -> void:
	var squad := _squad()
	if squad == null:
		return
	var added := 0
	for unit: Unit in g.selected_units():
		if unit.is_player() and unit.squad_id != squad.id and unit.kind != "airship" and g.world.assign_to_squad(unit, squad):
			g.world.combat.enlist(unit)
			added += 1
	if added > 0:
		hud.add_note({"key": "ui.squad.joined", "params": {"count": added, "name": squad.name}, "kind": "info"}, 3.0)
	elif squad.members.size() >= 6:
		hud.add_note({"text": Loc.t("A squad can have at most 6 members."), "kind": "info"}, 3.0)
	else:
		hud.add_note({"text": Loc.t("Select settlers or machines outside this squad first."), "kind": "info"}, 3.0)
	refresh(true)


func _on_new() -> void:
	if g.world.squads.size() >= World.MAX_SQUADS:
		hud.add_note({"text": Loc.t("Maximum 9 squads (hotkeys 1–9)."), "kind": "info"}, 3.0)
		return
	var picked: Array[Unit] = []
	for unit: Unit in g.selected_units():
		if unit.is_player() and unit.kind != "airship":
			picked.append(unit)
	var squad_name := Loc.t("%s's squad") % picked[0].name if picked.size() == 1 else ""
	var squad := g.world.create_squad(squad_name)
	if squad == null:
		hud.add_note({"text": Loc.t("Maximum 9 squads (hotkeys 1–9)."), "kind": "info"}, 3.0)
		refresh(true)
		return
	var added := 0
	for index: int in mini(picked.size(), 6):
		var unit := picked[index]
		if g.world.assign_to_squad(unit, squad):
			g.world.combat.enlist(unit)
			added += 1
	if added > 0:
		g.world.squad_ai.order_squad(squad, {"type": "idle"})
	all_squads_active = false
	g.select_squad(squad.id)
	hud._update_commands()
	hud.add_note({"key": "ui.squad.formed", "params": {"name": squad.name}, "kind": "good"}, 3.0)
	if picked.size() > 6:
		hud.add_note({"text": Loc.t("A squad can have at most 6 members."), "kind": "info"}, 3.0)
	elif added == 0:
		_open_picker()

func _on_tactics_changed(_index: int) -> void:
	var s := _squad()
	if s == null:
		return
	var stances := ["aggressive", "balanced", "cautious", "hold"]
	var formations := ["line", "wedge", "loose"]
	s.stance = stances[_stance_select.selected]
	s.formation = formations[_formation_select.selected]
	var center := g.world.squad_ai.center(s)
	g.world.fx.emit(StringName("tactic_stance|" + s.stance), Vector3(center.x, 0.0, center.y), Color("#ffd36a"))


func _refresh_tactic_labels() -> void:
	var stance_labels := ["Aggressive", "Balanced", "Cautious", "Hold"]
	for i in stance_labels.size():
		_stance_select.set_item_text(i, Loc.t(stance_labels[i]))
	_stance_select.tooltip_text = Loc.t("Aggressive: chase and strike. Balanced: standard orders. Cautious: kite and retreat early. Hold: stay near the order point.")
	var formation_labels := ["Line", "Wedge", "Loose"]
	for i in formation_labels.size():
		_formation_select.set_item_text(i, Loc.t(formation_labels[i]))
	_formation_select.tooltip_text = Loc.t("Line: broad front. Wedge: pointed advance. Loose: wider spacing.")
	_rename_btn.tooltip_text = Loc.t("Rename squad")
	_close_btn.tooltip_text = Loc.t("Close squad menu")
	_picker_btn.text = Loc.t("Add member")
	_picker_btn.tooltip_text = Loc.t("Choose a unit to add to this squad.")
	_split_selected_btn.text = Loc.t("One-person squad")
	_split_selected_btn.tooltip_text = Loc.t("Create a squad for the selected worker.")
	_tab_new_btn.text = Loc.t("＋ New squad") if g.world.squads.size() < World.MAX_SQUADS else Loc.t("＋ New squad (%d/9)") % g.world.squads.size()
	_tab_new_btn.tooltip_text = Loc.t("Create a squad from selected units, or start an empty squad.")
	_disband_btn.text = Loc.t("Disband")
	_disband_btn.tooltip_text = Loc.t("Disband this squad and return its members to work.")
	_auto_toggle.text = Loc.t("Auto abilities")
	_auto_toggle.tooltip_text = Loc.t("Let squad members use abilities automatically.")
	var squad := _squad()
	if squad:
		_slider_label.text = Loc.t("Retreat at %d%%") % int(squad.retreat_threshold * 100)
	refresh(true)
