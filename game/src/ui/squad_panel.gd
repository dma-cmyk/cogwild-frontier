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
	_name = UiTheme.title("No squad", 20)
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
	var foot := UiTheme.hbox(8)
	v.add_child(foot)
	foot.add_child(UiTheme.icon("cmd_retreat", 20))
	_slider_label = UiTheme.label("Retreat at 30%", 14, UiTheme.TEXT_DIM)
	_slider_label.custom_minimum_size = Vector2(104, 0)
	foot.add_child(_slider_label)
	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 0.6
	_slider.step = 0.05
	_slider.custom_minimum_size = Vector2(96, 18)
	_slider.focus_mode = Control.FOCUS_NONE
	_slider.tooltip_text = "The squad falls back to the hearth when its total health drops below this."
	_slider.value_changed.connect(_on_threshold)
	foot.add_child(_slider)
	_add_btn = UiTheme.button("Add selected", "ui_people", "Draft the selected settlers or machines into this squad (max 6).")
	_add_btn.custom_minimum_size = Vector2(0, 30)
	_add_btn.pressed.connect(_on_add)
	foot.add_child(_add_btn)
	var esc := UiTheme.button("Escort", "cmd_escort", "Escort (Y): follow and protect one of your units — e.g. the airship or a work bot.")
	esc.custom_minimum_size = Vector2(0, 30)
	esc.pressed.connect(func() -> void:
		if g.selected_units().is_empty():
			hud.add_note({"text": "Select a squad first.", "kind": "info"}, 3.0)
		else:
			g.input_ctl.set_mode("cmd:escort"))
	foot.add_child(esc)
	var new_btn := UiTheme.button("New squad", "ui_squad", "Form a new squad from the selected units.")
	new_btn.custom_minimum_size = Vector2(0, 30)
	new_btn.pressed.connect(_on_new)
	foot.add_child(new_btn)


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
		_name.text = "No squad"
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
	_slider.set_value_no_signal(s.retreat_threshold)
	_slider_label.text = "Retreat at %d%%" % int(s.retreat_threshold * 100)
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
	var o := str(s.order.get("type", "idle"))
	var st := s.state
	if st == "" or st == "holding":
		return "Holding position" if o == "idle" else o.capitalize()
	return st.capitalize() if not st.begins_with("auto") else "Auto — " + st.substr(6)


func _rebuild_tabs(current: Squad) -> void:
	var ids: Array = []
	for s: Squad in g.world.squads:
		ids.append(s.id)
	if _tabs.get_meta("ids", []) == ids and _tabs.get_meta("cur", -1) == (current.id if current else -1):
		return
	_tabs.set_meta("ids", ids)
	_tabs.set_meta("cur", current.id if current else -1)
	for c in _tabs.get_children():
		c.queue_free()
	for i in g.world.squads.size():
		var s: Squad = g.world.squads[i]
		var b := UiTheme.button("%d %s" % [i + 1, s.name.split(" ")[0]], "", "Select %s (key %d)" % [s.name, i + 1])
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
		frame.custom_minimum_size = Vector2(84, 116)
		frame.mouse_filter = Control.MOUSE_FILTER_STOP
		frame.tooltip_text = "%s — %s" % [u.name, u.display_role()]
		var v := UiTheme.vbox(2)
		frame.add_child(v)
		var pic := TextureRect.new()
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.custom_minimum_size = Vector2(72, 66)
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
		_slider_label.text = "Retreat at %d%%" % int(v * 100)


func _on_add() -> void:
	var s := _squad()
	if s == null:
		return
	var n := 0
	for u: Unit in g.selected_units():
		if u.squad_id < 0 and u.kind != "airship" and g.world.assign_to_squad(u, s):
			g.world.combat.enlist(u)
			n += 1
	hud.add_note({"text": "%d joined %s." % [n, s.name] if n > 0 else "Select settlers or machines outside a squad first.", "kind": "info"}, 3.0)
	refresh(true)


func _on_new() -> void:
	var picked: Array = []
	for u: Unit in g.selected_units():
		if u.kind != "airship":
			picked.append(u)
	if picked.is_empty():
		hud.add_note({"text": "Select settlers or machines to form a squad.", "kind": "info"}, 3.0)
		return
	var s := g.world.create_squad()
	for u: Unit in picked:
		if g.world.assign_to_squad(u, s):
			g.world.combat.enlist(u)
	g.world.squad_ai.order_squad(s, {"type": "idle"})
	g.select_squad(s.id)
	hud.add_note({"text": "%s formed." % s.name, "kind": "good"}, 3.0)
