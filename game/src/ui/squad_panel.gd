class_name SquadPanel
extends PanelContainer
## Bottom-centre squad panel: squad tabs, the selected squad's name, size and current activity,
## member cards (portrait, class, level, health and energy) and the retreat threshold.

var g: Game
var hud: Hud
var _tabs: HBoxContainer
var _name: Label
var _count: Label
var _state: Label
var _cards: HBoxContainer
var _slider: HSlider
var _slider_label: Label
var _add_btn: Button
var _shown_squad := -99
var _shown_members: Array = []
var _foot: HBoxContainer
var _actions: HBoxContainer
var _compact := false
var _stance_select: OptionButton
var _formation_select: OptionButton
var _card_refs: Array = []  # [unit_id, hp_bar, en_bar, lv_label, frame]


func setup(game: Game, h: Hud) -> void:
	g = game
	hud = h
	name = "SquadPanel"
	add_theme_stylebox_override("panel", UiTheme.panel_box())
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -655
	offset_right = -80
	offset_top = -206
	offset_bottom = -10
	var v := UiTheme.vbox(6)
	add_child(v)
	var head := UiTheme.hbox(8)
	v.add_child(head)
	head.add_child(UiTheme.icon("ui_squad", 26))
	_name = UiTheme.title(Loc.t("No squad"), 20)
	head.add_child(_name)
	_count = UiTheme.label("", 18, UiTheme.TEXT_DIM)
	head.add_child(_count)
	_state = UiTheme.label("", 15, UiTheme.ACCENT)
	_state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_state.clip_text = true
	head.add_child(_state)
	_tabs = UiTheme.hbox(4)
	_tabs.mouse_filter = Control.MOUSE_FILTER_PASS
	head.add_child(_tabs)
	_cards = UiTheme.hbox(6)
	_cards.custom_minimum_size = Vector2(0, 118)
	v.add_child(_cards)
	_foot = UiTheme.hbox(8)
	v.add_child(_foot)
	var foot := _foot
	foot.add_child(UiTheme.icon("cmd_retreat", 20))
	_slider_label = UiTheme.label(Loc.t("Retreat at %d%%") % 30, 14, UiTheme.TEXT_DIM)
	_slider_label.custom_minimum_size = Vector2(130, 0)
	foot.add_child(_slider_label)
	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 0.6
	_slider.step = 0.05
	_slider.custom_minimum_size = Vector2(96, 18)
	_slider.focus_mode = Control.FOCUS_NONE
	_slider.tooltip_text = Loc.t("The squad falls back to the hearth when its total health drops below this.")
	_slider.value_changed.connect(_on_threshold)
	foot.add_child(_slider)
	_stance_select = OptionButton.new()
	for label: String in ["Aggressive", "Balanced", "Cautious", "Hold"]:
		_stance_select.add_item(Loc.t(label))
	_stance_select.tooltip_text = Loc.t("Aggressive: chase and strike. Balanced: standard orders. Cautious: kite and retreat early. Hold: stay near the order point.")
	_stance_select.focus_mode = Control.FOCUS_NONE
	_stance_select.item_selected.connect(_on_tactics_changed)
	foot.add_child(_stance_select)
	_formation_select = OptionButton.new()
	for label: String in ["Line", "Wedge", "Loose"]:
		_formation_select.add_item(Loc.t(label))
	_formation_select.tooltip_text = Loc.t("Line: broad front. Wedge: pointed advance. Loose: wider spacing.")
	_formation_select.focus_mode = Control.FOCUS_NONE
	_formation_select.item_selected.connect(_on_tactics_changed)
	foot.add_child(_formation_select)
	Loc.language_changed.connect(_refresh_tactic_labels)
	_actions = UiTheme.hbox(8)
	v.add_child(_actions)
	_add_btn = UiTheme.button(Loc.t("Add selected"), "ui_people", Loc.t("Draft the selected settlers or machines into this squad (max 6)."))
	_add_btn.custom_minimum_size = Vector2(0, 30)
	_add_btn.pressed.connect(_on_add)
	_actions.add_child(_add_btn)
	var esc := UiTheme.button(Loc.t("Escort"), "cmd_escort", Loc.t("Escort (Y): follow and protect one of your units — e.g. the airship or a work bot."))
	esc.custom_minimum_size = Vector2(0, 30)
	esc.pressed.connect(func() -> void:
		if g.selected_units().is_empty():
			hud.add_note({"text": Loc.t("Select a squad first."), "kind": "info"}, 3.0)
		else:
			g.input_ctl.set_mode("cmd:escort"))
	_actions.add_child(esc)
	var new_btn := UiTheme.button(Loc.t("New squad"), "ui_squad", Loc.t("Form a new squad from the selected units."))
	new_btn.custom_minimum_size = Vector2(0, 30)
	new_btn.pressed.connect(_on_new)
	_actions.add_child(new_btn)

func set_compact(compact: bool) -> void:
	_compact = compact
	if _foot:
		for i in 3:
			_foot.get_child(i).visible = not compact
		for child in _actions.get_children():
			(child as Control).custom_minimum_size = Vector2(0, 44 if compact else 30)
		_stance_select.custom_minimum_size = Vector2(112, 44 if compact else 30)
		_formation_select.custom_minimum_size = Vector2(96, 44 if compact else 30)
	for ref: Array in _card_refs:
		var frame: PanelContainer = ref[4]
		frame.custom_minimum_size = Vector2(68, 88) if compact else Vector2(84, 116)
	for child in _cards.get_children():
		for item in child.get_children():
			if item is VBoxContainer and item.get_child_count() > 0:
				var pic := item.get_child(0) as TextureRect
				pic.custom_minimum_size = Vector2(56, 46) if compact else Vector2(72, 66)
	_cards.custom_minimum_size = Vector2(0, 90 if compact else 118)

func _squad() -> Squad:
	if g.sel_squad >= 0:
		return g.world.get_squad(g.sel_squad)
	var fu := g.focus_unit()
	if fu and fu.squad_id >= 0:
		return g.world.get_squad(fu.squad_id)
	return g.world.squads[0] if not g.world.squads.is_empty() else null


func refresh(force: bool) -> void:
	var s := _squad()
	_rebuild_tabs(s)
	if s == null:
		_name.text = Loc.t("No squad")
		_count.text = ""
		_state.text = ""
		return
	if force or s.id != _shown_squad or s.members != _shown_members:
		_shown_squad = s.id
		_shown_members = s.members.duplicate()
		_rebuild_cards(s)
	_name.text = s.name
	_name.add_theme_color_override("font_color", s.color().lerp(UiTheme.TEXT, 0.35))
	_count.text = "%d/6" % s.members.size()
	_state.text = _state_text(s)
	_stance_select.select(["aggressive", "balanced", "cautious", "hold"].find(s.stance))
	_formation_select.select(["line", "wedge", "loose"].find(s.formation))
	var focus := g.focus_unit()
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


func _state_text(s: Squad) -> String:
	if not s.state_message.is_empty():
		return Loc.message(s.state_message)
	var o := str(s.order.get("type", "idle"))
	var st := s.state
	if st == "" or st == "holding":
		return Loc.t("Holding position") if o == "idle" else Loc.t(o.capitalize())
	return Loc.t(st.capitalize()) if not st.begins_with("auto") else Loc.t("Auto — ") + Loc.t(st.substr(6))


func _rebuild_tabs(current: Squad) -> void:
	var ids: Array = []
	for s: Squad in g.world.squads:
		ids.append(s.id)
	if _tabs.get_meta("ids", []) == ids and _tabs.get_meta("cur", -1) == (current.id if current else -1) and _tabs.get_meta("language", "") == Loc.language:
		return
	_tabs.set_meta("ids", ids)
	_tabs.set_meta("language", Loc.language)
	_tabs.set_meta("cur", current.id if current else -1)
	for c in _tabs.get_children():
		c.queue_free()
	for i in g.world.squads.size():
		var s: Squad = g.world.squads[i]
		var b := UiTheme.button("%d %s" % [i + 1, s.name.split(" ")[0]], "", Loc.t("Select %s (key %d)") % [s.name, i + 1])
		b.custom_minimum_size = Vector2(0, 28)
		b.add_theme_font_size_override("font_size", 13)
		if current and s.id == current.id:
			b.add_theme_stylebox_override("normal", UiTheme.button_box("pressed"))
		var sid := s.id
		b.pressed.connect(func() -> void:
			g.select_squad(sid)
			g.focus_selection())
		_tabs.add_child(b)


func _rebuild_cards(s: Squad) -> void:
	for c in _cards.get_children():
		c.queue_free()
	_card_refs.clear()
	for id: int in s.members:
		var u := g.world.get_unit(id)
		if u == null:
			continue
		var frame := PanelContainer.new()
		frame.add_theme_stylebox_override("panel", UiTheme.flat(Color(0.08, 0.11, 0.17, 0.95), 6, UiTheme.BORDER_DIM, 2))
		frame.custom_minimum_size = Vector2(68, 88) if _compact else Vector2(84, 116)
		frame.mouse_filter = Control.MOUSE_FILTER_STOP
		frame.tooltip_text = "%s — %s" % [u.name, Loc.t(u.display_role())]
		var v := UiTheme.vbox(2)
		frame.add_child(v)
		var pic := TextureRect.new()
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.custom_minimum_size = Vector2(56, 46) if _compact else Vector2(72, 66)
		pic.texture = hud.portraits.get_portrait("u%d" % u.id, u.dna, 128)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(pic)
		var row := UiTheme.hbox(2)
		row.add_child(UiTheme.icon(u.class_icon(), 18))
		var lv := UiTheme.label("Lv.%d" % u.char_level(), 13)
		row.add_child(lv)
		v.add_child(row)
		var hp := UiTheme.bar(Color("#58d65a"), 7)
		v.add_child(hp)
		var en := UiTheme.bar(Color("#4f9dff"), 5)
		v.add_child(en)
		var uid := u.id
		frame.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				g.focus_member(uid)
				if (ev as InputEventMouseButton).double_click:
					var fu := g.world.get_unit(uid)
					if fu:
						g.focus_pos(fu.pos))
		_cards.add_child(frame)
		_card_refs.append([u.id, hp, en, lv, frame])


func _on_threshold(v: float) -> void:
	var s := _squad()
	if s:
		s.retreat_threshold = v
		_slider_label.text = Loc.t("Retreat at %d%%") % int(v * 100)


func _on_add() -> void:
	var s := _squad()
	if s == null:
		return
	var n := 0
	for u: Unit in g.selected_units():
		if u.squad_id < 0 and u.kind != "airship" and g.world.assign_to_squad(u, s):
			g.world.combat.enlist(u)
			n += 1
	hud.add_note({"key": "ui.squad.joined", "params": {"count": n, "name": s.name}, "kind": "info"} if n > 0 else {"text": Loc.t("Select settlers or machines outside a squad first."), "kind": "info"}, 3.0)
	refresh(true)


func _on_new() -> void:
	var picked: Array = []
	for u: Unit in g.selected_units():
		if u.kind != "airship":
			picked.append(u)
	if picked.is_empty():
		hud.add_note({"text": Loc.t("Select settlers or machines to form a squad."), "kind": "info"}, 3.0)
		return
	var s := g.world.create_squad()
	for u: Unit in picked:
		if g.world.assign_to_squad(u, s):
			g.world.combat.enlist(u)
	g.world.squad_ai.order_squad(s, {"type": "idle"})
	g.select_squad(s.id)
	hud.add_note({"key": "ui.squad.formed", "params": {"name": s.name}, "kind": "good"}, 3.0)


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
