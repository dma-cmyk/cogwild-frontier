class_name Hud
extends CanvasLayer
## In-game HUD modelled on the reference layout: resources and time on top, notifications on the
## left, minimap bottom-left, squad panel and command bar bottom-centre, selection details on the
## right. Reads the Game/World state; sends orders through the InputController and systems.

const RES_ORDER := ["wood", "stone", "ore", "metal", "food", "gold"]
const KIND_ICON := {"good": "ui_star", "bad": "ui_skull", "discover": "ui_target", "loot": "ui_chest", "levelup": "ui_star", "info": "ui_bell"}
const KIND_COLOR := {"good": UiTheme.GOOD, "bad": UiTheme.BAD, "discover": UiTheme.ACCENT, "loot": UiTheme.GOLD, "levelup": UiTheme.GOLD, "info": UiTheme.TEXT}
const COMMANDS := [["move", "Move", "cmd_move", "M"], ["attack", "Attack", "cmd_attack", "F"], ["defend", "Defend", "cmd_defend", "H"],
	["explore", "Explore", "cmd_explore", "X"], ["patrol", "Patrol", "cmd_patrol", "P"], ["escort", "Escort", "cmd_escort", "Y"],
	["auto", "Auto", "cmd_auto", "U"], ["retreat", "Retreat", "cmd_retreat", "R"]]
## Ability shortcut slots bound in App ("ability_1".."ability_9").
const ABILITY_HOTKEYS := 9

var g: Game
var root: Control
var portraits: PortraitRenderer
var info_panel: InfoPanel
var squad_panel: SquadPanel
var minimap: Minimap
var build_menu: BuildMenu
var pause_menu: PauseMenu
var roster: RosterPanel
var villages: VillageHud
var _note_queue: Array[Dictionary] = []
var _res_labels: Dictionary = {}
var _rate_labels: Dictionary = {}
var _pop_label: Label
var _energy_label: Label
var _energy_rate: Label
var _day_label: Label
var _sun_icon: TextureRect
var _speed_buttons: Array = []
var _notes: VBoxContainer
var _cmd_buttons: Dictionary = {}
var _tooltip: Label
var _tooltip_panel: PanelContainer
var _box: Panel
var _mode_hint: Label
var _trade_panel: PanelContainer
var _trade_list: VBoxContainer
var _trade_count := -1
var _trade_dismissed := -2  # trader id whose wares were closed by the player
var _help: PanelContainer
var _t := 0.0
var _seen_notes := 0
var _top_bar: Control
var _command_panel: Control
var _command_scroll: ScrollContainer
var _command_stack: VBoxContainer
var _command_row: HBoxContainer
var _order_row: HBoxContainer
var _order_buttons: Array[Button] = []
var _touch_controls: Control
var _box_select_button: Button
var _minimap_button: Button
var _rotate_left: Button
var _rotate_right: Button
var _details_button: Button
var _place_confirm: Button
var _portrait_panel: PanelContainer
var _top_row: HBoxContainer
var _compact := false
var _recipient_label: Label
var _recipient_icon: TextureRect
var _recipient_swatch: ColorRect
var _ability_row: HBoxContainer
var _ability_scroll: ScrollContainer
var _ability_separator: VSeparator
var _colony_buttons: Array[Button] = []
var _ability_signature := ""
var _ability_buttons: Dictionary = {}
var _squad_toggle: Button
var _ability_shortcuts: Array[String] = []


func setup(game: Game) -> void:
	g = game
	layer = 5
	root = Control.new()
	root.name = "Root"
	root.theme = UiTheme.theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var speech: SpeechBubbles = SpeechBubbles.new()
	root.add_child(speech)
	speech.setup(g)
	portraits = PortraitRenderer.new()
	add_child(portraits)
	_build_top_bar()
	_build_notifications()
	minimap = Minimap.new()
	root.add_child(minimap)
	minimap.setup(g)
	squad_panel = SquadPanel.new()
	root.add_child(squad_panel)
	squad_panel.setup(g, self)
	_squad_toggle = UiTheme.button(Loc.t("Squad menu"), "ui_squad")
	_squad_toggle.custom_minimum_size = Vector2(108, 44)
	_squad_toggle.anchor_left = 0.0
	_squad_toggle.anchor_right = 0.0
	_squad_toggle.anchor_top = 0.0
	_squad_toggle.anchor_bottom = 0.0
	_squad_toggle.offset_left = 8
	_squad_toggle.offset_right = 116
	_squad_toggle.offset_top = 64
	_squad_toggle.offset_bottom = 108
	_squad_toggle.pressed.connect(func() -> void:
		squad_panel.visible = not squad_panel.visible
		_squad_toggle.visible = not squad_panel.visible)
	root.add_child(_squad_toggle)
	_build_command_bar()
	info_panel = InfoPanel.new()
	root.add_child(info_panel)
	info_panel.setup(g, self)
	build_menu = BuildMenu.new()
	root.add_child(build_menu)
	build_menu.setup(g)
	roster = RosterPanel.new()
	root.add_child(roster)
	roster.setup(g, self)
	villages = VillageHud.new()
	root.add_child(villages)
	villages.setup(g, self)
	_build_trade_panel()
	_build_touch_controls()
	get_viewport().size_changed.connect(_update_responsive)
	_update_responsive()
	_build_overlays()
	pause_menu = PauseMenu.new()
	root.add_child(pause_menu)
	pause_menu.setup(g)
	g.selection_changed.connect(_on_selection)
	g.speed_changed.connect(_on_speed)
	g.toast.connect(func(text: String, kind: String) -> void: add_note({"text": text, "kind": kind}, 4.0))
	g.mode_changed.connect(_on_mode)
	g.world.notified.connect(_on_world_note)
	_on_speed(g.speed)
	_seen_notes = g.world.notifications.size()
	for n: Dictionary in g.world.notifications.slice(maxi(0, g.world.notifications.size() - 3)):
		add_note(n, 12.0)
	Sfx.start_music()
	Loc.language_changed.connect(_refresh_language)



func _refresh_language() -> void:
	_update_top()
	_squad_toggle.text = Loc.t("Squad menu")
	_on_mode(g.input_ctl.mode)
	info_panel.refresh(true)
	squad_panel.refresh(true)
	for i in _colony_buttons.size():
		_colony_buttons[i].text = Loc.t("Build" if i == 0 else "Gather")
	for command: Array in COMMANDS:
		var id := str(command[0])
		var button: Button = _cmd_buttons[id]
		var box := button.get_child(0) as VBoxContainer
		(box.get_child(1) as Label).text = Loc.t(str(command[1]))
		button.tooltip_text = "%s (%s)\\n%s" % [Loc.t(str(command[1])), command[3], Loc.t(_cmd_help(id))]
	_update_commands()
	roster._sig = ""
	roster.refresh()
	villages.trade_window._signature = ""
	villages.diplomacy_panel._signature = ""
	villages.refresh()
	_trade_count = -1
	_update_trade()
	if is_instance_valid(_rotate_left):
		_rotate_left.tooltip_text = Loc.t("Rotate camera left (Q)")
		_rotate_right.tooltip_text = Loc.t("Rotate camera right (E)")
	if build_menu.visible:
		build_menu._rebuild()
	if pause_menu.visible:
		pause_menu._rebuild()


func is_mouse_over_ui() -> bool:
	var c := root.get_viewport().gui_get_hovered_control()
	return c != null and c != root


# --- top bar -----------------------------------------------------------------------------------

func _build_top_bar() -> void:
	var bar := UiTheme.panel()
	bar.name = "TopBar"
	root.add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 8
	bar.offset_right = -8
	bar.offset_top = 6
	bar.offset_bottom = 62
	var h := UiTheme.hbox(10)
	bar.add_child(h)
	_top_bar = bar
	_top_row = h
	var crest := UiTheme.icon("ui_crest", 40)
	h.add_child(crest)
	var name_l := UiTheme.title(g.world.company_name, 20)
	name_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # proper noun chosen by the player
	name_l.custom_minimum_size = Vector2(180, 0)
	name_l.clip_text = true
	h.add_child(name_l)
	for r: String in RES_ORDER:
		h.add_child(_res_entry(r, "res_" + r))
	var pop := UiTheme.hbox(4)
	pop.add_child(UiTheme.icon("res_pop", 28))
	_pop_label = UiTheme.label("0/0", 20, UiTheme.TEXT, UiTheme.bold_font)
	pop.add_child(_pop_label)
	pop.tooltip_text = Loc.t("Population / housing. New settlers arrive when there is free housing and food.")
	pop.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(pop)
	var en := UiTheme.hbox(4)
	en.add_child(UiTheme.icon("res_energy", 28))
	_energy_label = UiTheme.label("0", 20, UiTheme.TEXT, UiTheme.bold_font)
	en.add_child(_energy_label)
	_energy_rate = UiTheme.label("", 14, UiTheme.GOOD)
	en.add_child(_energy_rate)
	en.tooltip_text = Loc.t("Energy powers robots, drones and airships. Windmills generate it; aether crystals store it.")
	en.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(en)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(spacer)
	_sun_icon = UiTheme.icon("ui_sun", 30)
	h.add_child(_sun_icon)
	_day_label = UiTheme.title("Day 1", 20)
	_day_label.custom_minimum_size = Vector2(150, 0)
	h.add_child(_day_label)
	var speeds := [[0, "ui_pause", "Pause (Space)"], [1, "ui_play", "Normal speed"], [2, "ui_fast", "Fast (x2)"], [4, "ui_faster", "Fastest (x4)"]]
	for s: Array in speeds:
		var b := UiTheme.button("", str(s[1]), Loc.t(str(s[2])))
		b.custom_minimum_size = Vector2(44, 40)
		b.toggle_mode = true
		var sp := int(s[0])
		b.pressed.connect(func() -> void: g.set_speed(sp))
		h.add_child(b)
		_speed_buttons.append([sp, b])
	var menu := UiTheme.button("", "ui_menu", Loc.t("Menu (Esc)"))
	menu.custom_minimum_size = Vector2(44, 40)
	menu.pressed.connect(func() -> void: pause_menu.open())
	h.add_child(menu)


func _res_entry(r: String, icon_id: String) -> Control:
	var h := UiTheme.hbox(4)
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	h.tooltip_text = Loc.t(str({"wood": "Wood — felled in logging zones", "stone": "Stone — quarried in mining zones",
		"ore": "Ore — mined, smelted into metal", "metal": "Metal — from the smelter and salvage",
		"food": "Food — farms and berry bushes; everyone eats daily", "gold": "Gold — trade runs and loot"}.get(r, r)))
	h.add_child(UiTheme.icon(icon_id, 28))
	var v := UiTheme.label("0", 20, UiTheme.TEXT, UiTheme.bold_font)
	v.custom_minimum_size = Vector2(48, 0)
	h.add_child(v)
	var rate := UiTheme.label("", 14, UiTheme.GOOD)
	rate.custom_minimum_size = Vector2(40, 0)
	h.add_child(rate)
	_res_labels[r] = v
	_rate_labels[r] = rate
	return h


func _build_touch_controls() -> void:
	_touch_controls = Control.new()
	_touch_controls.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_touch_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_touch_controls)
	_rotate_left = UiTheme.button("", "ui_rotate_left", Loc.t("Rotate camera left (Q)"))
	_rotate_left.custom_minimum_size = Vector2(40, 40)
	_rotate_left.pressed.connect(func() -> void: g.rig.rotate_step(-1))
	_touch_controls.add_child(_rotate_left)
	_rotate_right = UiTheme.button("", "ui_rotate_right", Loc.t("Rotate camera right (E)"))
	_rotate_right.custom_minimum_size = Vector2(40, 40)
	_rotate_right.pressed.connect(func() -> void: g.rig.rotate_step(1))
	_touch_controls.add_child(_rotate_right)
	_box_select_button = UiTheme.button(Loc.t("Box"), "ui_target", Loc.t("Toggle drag box selection"))
	_box_select_button.custom_minimum_size = Vector2(88, 44)
	_box_select_button.anchor_left = 1.0
	_box_select_button.anchor_right = 1.0
	_box_select_button.offset_left = -192
	_box_select_button.offset_right = -104
	_box_select_button.offset_top = 72
	_box_select_button.offset_bottom = 116
	_box_select_button.pressed.connect(func() -> void:
		g.input_ctl.box_select_mode = not g.input_ctl.box_select_mode
		_box_select_button.add_theme_stylebox_override("normal", UiTheme.button_box("pressed" if g.input_ctl.box_select_mode else "normal")))
	_touch_controls.add_child(_box_select_button)
	_minimap_button = UiTheme.button(Loc.t("Map"), "ui_search")
	_minimap_button.custom_minimum_size = Vector2(88, 44)
	_minimap_button.anchor_left = 1.0
	_minimap_button.anchor_right = 1.0
	_minimap_button.offset_left = -96
	_minimap_button.offset_right = -8
	_minimap_button.offset_top = 72
	_minimap_button.offset_bottom = 116
	_minimap_button.pressed.connect(_toggle_minimap)
	_touch_controls.add_child(_minimap_button)
	_details_button = UiTheme.button(Loc.t("Details"), "ui_people")
	_details_button.custom_minimum_size = Vector2(100, 44)
	_details_button.anchor_left = 1.0
	_details_button.anchor_right = 1.0
	_details_button.offset_left = -108
	_details_button.offset_right = -8
	_details_button.offset_top = 124
	_details_button.offset_bottom = 168
	_details_button.pressed.connect(func() -> void: info_panel.toggle_drawer())
	_touch_controls.add_child(_details_button)
	_place_confirm = UiTheme.button(Loc.t("Confirm"), "ui_play")
	_place_confirm.custom_minimum_size = Vector2(120, 48)
	_place_confirm.anchor_left = 1.0
	_place_confirm.anchor_right = 1.0
	_place_confirm.anchor_top = 1.0
	_place_confirm.anchor_bottom = 1.0
	_place_confirm.offset_left = -260
	_place_confirm.offset_right = -136
	_place_confirm.offset_top = -64
	_place_confirm.offset_bottom = -12
	_place_confirm.pressed.connect(g.input_ctl.confirm_touch_build)
	_touch_controls.add_child(_place_confirm)
	var cancel := UiTheme.button(Loc.t("Cancel"), "ui_close")
	cancel.custom_minimum_size = Vector2(120, 48)
	cancel.anchor_left = 1.0
	cancel.anchor_right = 1.0
	cancel.anchor_top = 1.0
	cancel.anchor_bottom = 1.0
	cancel.offset_left = -128
	cancel.offset_right = -8
	cancel.offset_top = -64
	cancel.offset_bottom = -12
	cancel.pressed.connect(g.input_ctl.cancel_touch_mode)
	_touch_controls.add_child(cancel)
	_portrait_panel = UiTheme.panel()
	_portrait_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_portrait_panel.offset_left = -220
	_portrait_panel.offset_right = 220
	_portrait_panel.offset_top = -100
	_portrait_panel.offset_bottom = 100
	var portrait_box := UiTheme.vbox(12)
	portrait_box.add_child(UiTheme.title(Loc.t("Rotate your device to landscape"), 22))
	portrait_box.add_child(UiTheme.label(Loc.t("This frontier is designed for landscape play."), 16))
	var continue_button := UiTheme.button(Loc.t("Continue anyway"), "ui_play")
	continue_button.custom_minimum_size = Vector2(0, 48)
	continue_button.pressed.connect(func() -> void: _portrait_panel.hide())
	portrait_box.add_child(continue_button)
	_portrait_panel.add_child(portrait_box)
	_touch_controls.add_child(_portrait_panel)
	_update_responsive()


func show_touch_detail(text: String) -> void:
	info_panel.open_drawer()
	_tooltip.text = Loc.t(text)
	_tooltip_panel.visible = text != ""
	_tooltip_panel.position = Vector2(12, 70)


func _toggle_minimap() -> void:
	minimap.visible = not minimap.visible
	if _compact:
		_rotate_left.visible = minimap.visible
		_rotate_right.visible = minimap.visible
		root.move_child(_touch_controls, -1)


func _update_responsive() -> void:
	if not is_instance_valid(root):
		return
	var size := App.screen_size()
	var layout_size := get_viewport().get_visible_rect().size
	_compact = size.x < 950.0 or size.y < 560.0
	_recipient_label.custom_minimum_size = Vector2(100, 0) if _compact else Vector2(150, 0)
	squad_panel.set_compact(_compact)
	if is_instance_valid(_portrait_panel):
		_portrait_panel.visible = size.y > size.x
		var portrait_width := minf(440.0, maxf(280.0, size.x - 24.0))
		_portrait_panel.offset_left = -portrait_width * 0.5
		_portrait_panel.offset_right = portrait_width * 0.5
	if _compact:
		_squad_toggle.visible = false
		squad_panel.visible = true
		squad_panel.anchor_left = 0.0
		squad_panel.anchor_right = 0.0
		squad_panel.anchor_top = 1.0
		squad_panel.anchor_bottom = 1.0
		squad_panel.offset_left = 8
		squad_panel.offset_right = 480
		squad_panel.offset_bottom = -8
		squad_panel.grow_horizontal = Control.GROW_DIRECTION_END
		squad_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
		minimap.anchor_left = 0.0
		minimap.anchor_right = 0.0
		minimap.anchor_top = 0.0
		minimap.anchor_bottom = 0.0
		minimap.offset_left = 8
		minimap.offset_right = 8 + Minimap.SIZE + 24 + 52
		minimap.offset_top = 124
		minimap.offset_bottom = 124 + Minimap.SIZE + 30
		minimap.visible = false
		root.move_child(minimap, -1)
		info_panel.anchor_top = 0.0
		info_panel.anchor_bottom = 0.0
		info_panel.anchor_left = 1.0
		info_panel.anchor_right = 1.0
		info_panel.offset_left = -340.0
		info_panel.offset_right = -8
		info_panel.offset_top = 176
		info_panel.offset_bottom = layout_size.y - 112
		_notes.custom_minimum_size.x = minf(340.0, size.x * 0.42)
		for pair: Array in _speed_buttons:
			(pair[1] as Button).custom_minimum_size = Vector2(40, 44)
	else:
		_squad_toggle.visible = false
		_squad_toggle.custom_minimum_size = Vector2(108, 44)
		# Squad roster bottom-left beside the minimap; it sizes itself to its content and grows
		# upward, so the command bar can sit apart from it at the bottom right.
		squad_panel.visible = true
		squad_panel.anchor_left = 0.0
		squad_panel.anchor_right = 0.0
		squad_panel.anchor_top = 1.0
		squad_panel.anchor_bottom = 1.0
		squad_panel.grow_horizontal = Control.GROW_DIRECTION_END
		squad_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
		squad_panel.offset_left = 10 + Minimap.SIZE + 24 + 52 + 8
		squad_panel.offset_right = squad_panel.offset_left
		squad_panel.offset_bottom = -10
		squad_panel.offset_top = -10
		info_panel.anchor_top = 1.0
		info_panel.anchor_bottom = 1.0
		info_panel.offset_left = -352
		info_panel.offset_right = -10
		minimap.anchor_left = 0.0
		minimap.anchor_right = 0.0
		minimap.anchor_top = 1.0
		minimap.anchor_bottom = 1.0
		minimap.offset_left = 10
		minimap.offset_right = 10 + Minimap.SIZE + 24 + 52
		minimap.offset_top = -(Minimap.SIZE + 30)
		minimap.offset_bottom = -10
		minimap.visible = true
	if is_instance_valid(_rotate_left) and is_instance_valid(_rotate_right):
		if _compact:
			for pair: Array in [[_rotate_left, 18.0], [_rotate_right, 66.0]]:
				var button := pair[0] as Button
				button.custom_minimum_size = Vector2(44, 44)
				button.anchor_left = 0.0
				button.anchor_right = 0.0
				button.anchor_top = 0.0
				button.anchor_bottom = 0.0
				button.offset_left = float(pair[1])
				button.offset_right = float(pair[1]) + 44.0
				button.offset_top = 124.0 + Minimap.SIZE - 52.0
				button.offset_bottom = 124.0 + Minimap.SIZE - 8.0
				button.visible = minimap.visible
		else:
			for pair: Array in [[_rotate_left, 10.0 + Minimap.SIZE - 112.0], [_rotate_right, 10.0 + Minimap.SIZE - 74.0]]:
				var button := pair[0] as Button
				button.custom_minimum_size = Vector2(32, 32)
				button.add_theme_font_size_override("font_size", 14)
				button.anchor_left = 0.0
				button.anchor_right = 0.0
				button.anchor_top = 1.0
				button.anchor_bottom = 1.0
				button.offset_left = float(pair[1])
				button.offset_right = float(pair[1]) + 32.0
				button.offset_top = -(Minimap.SIZE + 30.0) + 2.0
				button.offset_bottom = -(Minimap.SIZE + 30.0) + 34.0
				button.visible = true
	if is_instance_valid(_box_select_button):
		var touch_ui := App.is_touch() or App.is_mobile_web()
		_box_select_button.visible = touch_ui
		_minimap_button.visible = touch_ui or _compact
		_details_button.visible = _compact
		_place_confirm.visible = touch_ui and g.input_ctl.mode.begins_with("build:")
		_touch_controls.get_child(_touch_controls.get_child_count() - 2).visible = touch_ui and g.input_ctl.mode != ""
	if _compact and _top_row:
		_top_row.add_theme_constant_override("separation", 4)
		_top_row.get_child(1).visible = false
		for i in RES_ORDER.size():
			var entry := _top_row.get_child(i + 2) as HBoxContainer
			(entry.get_child(0) as Control).custom_minimum_size = Vector2(20, 20)
			(entry.get_child(1) as Label).custom_minimum_size = Vector2(32, 0)
			(entry.get_child(1) as Label).add_theme_font_size_override("font_size", 15)
			entry.get_child(2).visible = false
		var pop_row := _top_row.get_child(8) as HBoxContainer
		(pop_row.get_child(0) as Control).custom_minimum_size = Vector2(20, 20)
		_pop_label.add_theme_font_size_override("font_size", 15)
		var energy_row := _top_row.get_child(9) as HBoxContainer
		(energy_row.get_child(0) as Control).custom_minimum_size = Vector2(20, 20)
		_energy_rate.visible = false
		_energy_label.add_theme_font_size_override("font_size", 15)
		(_top_row.get_child(11) as Control).custom_minimum_size = Vector2(22, 22)
		_day_label.custom_minimum_size = Vector2(100, 0)
		_day_label.add_theme_font_size_override("font_size", 15)
		if size.x < 700.0:
			_top_row.get_child(0).visible = false
			for index in [4, 5, 7]:
				_top_row.get_child(index).visible = false
			_top_row.get_child(11).visible = false
			for index in [2, 3, 6]:
				var entry := _top_row.get_child(index) as HBoxContainer
				(entry.get_child(0) as Control).custom_minimum_size = Vector2(18, 18)
				(entry.get_child(1) as Label).custom_minimum_size = Vector2(28, 0)
				(entry.get_child(1) as Label).add_theme_font_size_override("font_size", 13)
			_pop_label.add_theme_font_size_override("font_size", 13)
			_energy_label.add_theme_font_size_override("font_size", 13)
			_day_label.custom_minimum_size = Vector2(62, 0)
			_day_label.add_theme_font_size_override("font_size", 13)
			for pair: Array in _speed_buttons:
				(pair[1] as Button).custom_minimum_size = Vector2(40, 40)
		else:
			for index in [0, 4, 5, 7, 11]:
				_top_row.get_child(index).visible = true
	elif _top_row:
		_top_row.add_theme_constant_override("separation", 10)
		_top_row.get_child(1).visible = true
		for i in RES_ORDER.size():
			var entry := _top_row.get_child(i + 2) as HBoxContainer
			(entry.get_child(0) as Control).custom_minimum_size = Vector2(28, 28)
			(entry.get_child(1) as Label).custom_minimum_size = Vector2(48, 0)
			(entry.get_child(1) as Label).add_theme_font_size_override("font_size", 20)
			entry.get_child(2).visible = true
		_energy_rate.visible = true
		_day_label.custom_minimum_size = Vector2(150, 0)
		_day_label.add_theme_font_size_override("font_size", 20)
		for pair: Array in _speed_buttons:
			(pair[1] as Button).custom_minimum_size = Vector2(44, 40)
	if _compact:
		_command_row.add_theme_constant_override("separation", 3)
		_recipient_label.visible = false
		_recipient_icon.custom_minimum_size = Vector2(24, 24)
		_recipient_swatch.custom_minimum_size = Vector2(4, 24)
		for colony_button: Button in _colony_buttons:
			colony_button.custom_minimum_size = Vector2(48, 48)
			colony_button.add_theme_font_size_override("font_size", 10)
		for button: Button in _cmd_buttons.values():
			button.custom_minimum_size = Vector2(48, 48)
			var box := button.get_child(0) as VBoxContainer
			(box.get_child(0) as TextureRect).custom_minimum_size = Vector2(22, 22)
			(box.get_child(1) as Label).add_theme_font_size_override("font_size", 9)
		for button: Button in _ability_buttons.values():
			button.custom_minimum_size = Vector2(48, 48)
		_ability_scroll.custom_minimum_size.y = 48
	else:
		_command_row.add_theme_constant_override("separation", 6)
		_recipient_label.visible = true
		_recipient_icon.custom_minimum_size = Vector2(22, 22)
		_recipient_swatch.custom_minimum_size = Vector2(6, 24)
		for colony_button: Button in _colony_buttons:
			colony_button.custom_minimum_size = Vector2(96, 58)
		for button: Button in _cmd_buttons.values():
			button.custom_minimum_size = Vector2(66, 58)
			var box := button.get_child(0) as VBoxContainer
			(box.get_child(0) as TextureRect).custom_minimum_size = Vector2(26, 26)
			(box.get_child(1) as Label).add_theme_font_size_override("font_size", 12)
		for button: Button in _ability_buttons.values():
			button.custom_minimum_size = Vector2(58, 58)
		_ability_scroll.custom_minimum_size.y = 58
	_update_ability_scroll_width()
	if _compact:
		_command_panel.anchor_left = 0.0
		_command_panel.anchor_right = 1.0
		_command_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_command_panel.offset_left = 8
		_command_panel.offset_right = -8
		_command_panel.offset_bottom = -8
	else:
		# Bottom-right, apart from the squad roster; sized to its two rows of buttons.
		_command_panel.anchor_left = 1.0
		_command_panel.anchor_right = 1.0
		_command_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_command_panel.offset_left = -10
		_command_panel.offset_right = -10
		_command_panel.offset_bottom = -10
	_command_panel.anchor_top = 1.0
	_command_panel.anchor_bottom = 1.0
	_command_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_configure_command_rows()
	_update_command_bar_height()


func _configure_command_rows() -> void:
	if not is_instance_valid(_command_row):
		return
	if _compact:
		_command_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_order_row.visible = false
		for button: Button in _order_buttons:
			if button.get_parent() == _order_row:
				_order_row.remove_child(button)
				_command_row.add_child(button)
				_command_row.move_child(button, _ability_separator.get_index())
	else:
		_command_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_order_row.visible = true
		for button: Button in _order_buttons:
			if button.get_parent() == _command_row:
				_command_row.remove_child(button)
				_order_row.add_child(button)
	_command_scroll.scroll_horizontal = 0
func _on_speed(s: int) -> void:
	for pair: Array in _speed_buttons:
		(pair[1] as Button).set_pressed_no_signal(int(pair[0]) == s)


func _update_top() -> void:
	var w := g.world
	var rates := w.economy.rates()
	for r: String in RES_ORDER:
		(_res_labels[r] as Label).text = UiTheme.fmt(float(w.res.get(r, 0)))
		var rt := float(rates.get(r, 0.0))
		var rl: Label = _rate_labels[r]
		rl.text = "" if absf(rt) < 0.5 else ("%+d" % int(round(rt)))
		rl.add_theme_color_override("font_color", UiTheme.GOOD if rt >= 0.0 else UiTheme.BAD)
	_pop_label.text = "%d/%d" % [w.population(), w.housing()]
	_energy_label.text = UiTheme.fmt(float(w.res.get("energy", 0)))
	var eb := w.economy.energy_balance_per_min()
	_energy_rate.text = "%+.0f" % eb if absf(eb) >= 0.5 else ""
	_energy_rate.add_theme_color_override("font_color", UiTheme.GOOD if eb >= 0.0 else UiTheme.BAD)
	var h := w.hour()
	_day_label.text = Loc.t("Day %d  %02d:%02d") % [w.day, int(h), int(fmod(h, 1.0) * 60.0)]
	_sun_icon.texture = Icons.get_icon("ui_moon" if w.is_night() else "ui_sun")


# --- notifications -----------------------------------------------------------------------------

func _build_notifications() -> void:
	_notes = UiTheme.vbox(6)
	_notes.name = "Notifications"
	root.add_child(_notes)
	_notes.position = Vector2(12, 74)
	_notes.custom_minimum_size = Vector2(470, 0)


func _on_world_note(n: Dictionary) -> void:
	# World notes arrive from inside a sim tick, often several at once (a level-up and a title);
	# a Japanese toast costs ~20 ms to lay out, so they are built one per frame from _process.
	_note_queue.append(n)
	while _note_queue.size() > 6:
		_note_queue.pop_front()
	match str(n.get("kind", "")):
		"discover":
			Sfx.play(&"discover")
		"loot":
			Sfx.play(&"rare_loot" if int(n.get("tier", 0)) >= 5 else &"loot")
		"levelup":
			Sfx.play(&"levelup")
		"bad":
			Sfx.play(&"alert")
		"good":
			if n.has("building"):
				Sfx.play(&"build_done")


func add_note(n: Dictionary, life: float) -> void:
	var p := PanelContainer.new()
	var box := UiTheme.flat(Color(0.06, 0.08, 0.13, 0.86), 6, Color(KIND_COLOR.get(str(n.get("kind", "info")), UiTheme.TEXT), 0.55), 1)
	box.content_margin_left = 8
	box.content_margin_right = 10
	p.add_theme_stylebox_override("panel", box)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.custom_minimum_size = Vector2(340 if _compact else 470, 0)
	var h := UiTheme.hbox(8)
	p.add_child(h)
	h.add_child(UiTheme.icon(str(KIND_ICON.get(str(n.get("kind", "info")), "ui_bell")), 22))
	var l := UiTheme.label(Loc.message(n), 16, KIND_COLOR.get(str(n.get("kind", "info")), UiTheme.TEXT))
	Loc.language_changed.connect(func() -> void:
		if is_instance_valid(l):
			l.text = Loc.message(n))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(290 if _compact else 420, 0)
	h.add_child(l)
	p.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			_note_clicked(n)
			p.queue_free())
	_notes.add_child(p)
	while _notes.get_child_count() > (3 if _compact else 6):
		var old := _notes.get_child(0)
		_notes.remove_child(old)
		old.queue_free()
	var tw := p.create_tween()
	tw.tween_interval(life)
	tw.tween_property(p, "modulate:a", 0.0, 0.8)
	tw.tween_callback(p.queue_free)


func _note_clicked(n: Dictionary) -> void:
	if n.has("unit"):
		var u := g.world.get_unit(int(n["unit"]))
		if u and u.alive:
			if u.is_player():
				g.select_units([u.id])
			g.focus_pos(u.pos)
			return
	if n.has("site"):
		g.select_site(int(n["site"]))
	if n.get("pos") is Vector2:
		g.focus_pos(n["pos"])


# --- command bar -------------------------------------------------------------------------------

func _build_command_bar() -> void:
	var panel := UiTheme.panel()
	panel.name = "CommandBar"
	root.add_child(panel)
	_command_panel = panel
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 330
	panel.offset_right = 1912
	panel.offset_top = -150
	panel.offset_bottom = -8
	_command_scroll = ScrollContainer.new()
	_command_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_command_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(_command_scroll)
	_command_stack = VBoxContainer.new()
	_command_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_command_stack.add_theme_constant_override("separation", 4)
	_command_scroll.add_child(_command_stack)
	_command_row = UiTheme.hbox(6)
	_command_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_order_row = UiTheme.hbox(6)
	_order_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_command_stack.add_child(_command_row)
	_command_stack.add_child(_order_row)
	var recipient := UiTheme.hbox(4)
	_recipient_swatch = ColorRect.new()
	_recipient_swatch.custom_minimum_size = Vector2(6, 24)
	recipient.add_child(_recipient_swatch)
	_recipient_icon = UiTheme.icon("ui_squad", 22)
	recipient.add_child(_recipient_icon)
	_recipient_label = UiTheme.label(Loc.t("No squad"), 13)
	_recipient_label.custom_minimum_size = Vector2(126, 0)
	_recipient_label.clip_text = true
	recipient.add_child(_recipient_label)
	_command_row.add_child(recipient)
	var colony_row := UiTheme.hbox(4)
	for entry: Array in [["build", "Build", "cmd_build"], ["gather", "Gather", "cmd_gather"]]:
		var colony_button := UiTheme.button(Loc.t(str(entry[1])), str(entry[2]))
		colony_button.custom_minimum_size = Vector2(88, 54)
		colony_button.tooltip_text = Loc.t(_cmd_help(str(entry[0])))
		var command_id := str(entry[0])
		colony_button.pressed.connect(func() -> void: command(command_id))
		colony_row.add_child(colony_button)
		_colony_buttons.append(colony_button)
	_command_row.add_child(colony_row)
	for command: Array in COMMANDS:
		var id := str(command[0])
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(52, 50)
		button.tooltip_text = "%s (%s)\\n%s" % [Loc.t(str(command[1])), command[3], Loc.t(_cmd_help(id))]
		var box := UiTheme.vbox(2)
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		button.add_child(box)
		var icon := UiTheme.icon(str(command[2]), 22)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(icon)
		var label := UiTheme.label(Loc.t(str(command[1])), 10)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(label)
		button.pressed.connect(func() -> void: command(id))
		_order_row.add_child(button)
		_order_buttons.append(button)
		_cmd_buttons[id] = button
	_ability_separator = VSeparator.new()
	_ability_separator.visible = false
	_command_row.add_child(_ability_separator)
	_ability_scroll = ScrollContainer.new()
	_ability_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_ability_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_ability_scroll.custom_minimum_size.y = 56
	_ability_scroll.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_ability_scroll.visible = false
	_command_row.add_child(_ability_scroll)
	_ability_row = UiTheme.hbox(5)
	_ability_row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_ability_scroll.add_child(_ability_row)

func _cmd_help(id: String) -> String:
	return {"move": "Click a destination.", "attack": "Click an enemy or camp (right-click also attacks).",
		"defend": "Hold an area and engage anything that comes close.", "explore": "Pick a region: they explore it, loot what they find and report back.",
		"build": "Place buildings for your settlers to construct.", "gather": "Designate logging, mining, forage and farm zones; set work priorities.",
		"patrol": "Walk between here and the clicked point, fighting on the way.", "escort": "Follow and protect one of your units.",
		"auto": "Full delegation: defend home, explore, clear weak camps, patrol.",
		"retreat": "Fall back to the hearth to heal, then resume."}.get(id, "")


func command_squad_ids() -> Array[int]:
	var ids: Array[int] = []
	if squad_panel.all_squads_active:
		for squad: Squad in g.world.squads:
			if not squad.members.is_empty():
				ids.append(squad.id)
		return ids
	var selected: Dictionary = {}
	for unit: Unit in g.selected_units():
		if unit.squad_id >= 0:
			selected[unit.squad_id] = true
	if not selected.is_empty():
		for squad_id_variant in selected.keys():
			ids.append(int(squad_id_variant))
		ids.sort()
		return ids
	var viewed := g.world.get_squad(g.viewed_squad_id)
	if viewed:
		ids.append(viewed.id)
	return ids


func command_units() -> Array:
	var units: Array = []
	for squad_id: int in command_squad_ids():
		var squad := g.world.get_squad(squad_id)
		if squad == null:
			continue
		for unit_id: int in squad.members:
			var unit := g.world.get_unit(unit_id)
			if unit:
				units.append(unit)
	return units


func _select_command_recipients(squad_ids: Array[int]) -> void:
	var unit_ids: Array[int] = []
	var focus := g.focus_unit()
	if focus and squad_ids.has(focus.squad_id):
		unit_ids.append(focus.id)
	for squad_id: int in squad_ids:
		var squad := g.world.get_squad(squad_id)
		if squad == null:
			continue
		for unit_id: int in squad.members:
			if not unit_ids.has(unit_id):
				unit_ids.append(unit_id)
	if not unit_ids.is_empty():
		g.select_units(unit_ids)


func command(id: String) -> void:
	Sfx.play(&"ui_select")
	if id == "build" or id == "gather":
		build_menu.toggle(id)
		return
	var squad_ids := command_squad_ids()
	if squad_ids.is_empty():
		add_note({"text": Loc.t("Select a squad first."), "kind": "info"}, 3.0)
		return
	_select_command_recipients(squad_ids)
	if id == "auto" or id == "retreat":
		g.input_ctl.issue(id)
		return
	g.input_ctl.set_mode("cmd:" + id)


func _update_commands() -> void:
	var squad_ids := command_squad_ids()
	var active := ""
	if not squad_ids.is_empty():
		var first := g.world.get_squad(squad_ids[0])
		active = str(first.order.get("type", "")) if first else ""
		for squad_id: int in squad_ids.slice(1):
			var squad := g.world.get_squad(squad_id)
			if squad == null or str(squad.order.get("type", "")) != active:
				active = ""
				break
	var recipient_color: Color = UiTheme.BORDER_DIM
	if squad_panel.all_squads_active:
		_recipient_label.text = Loc.t("All squads")
		recipient_color = UiTheme.ACCENT
	elif squad_ids.size() == 1:
		var squad := g.world.get_squad(squad_ids[0])
		_recipient_label.text = squad.name if squad else Loc.t("No squad")
		recipient_color = squad.color() if squad else UiTheme.BORDER_DIM
	elif squad_ids.size() > 1:
		_recipient_label.text = Loc.t("%d squads") % squad_ids.size()
		recipient_color = UiTheme.ACCENT
	else:
		_recipient_label.text = Loc.t("No squad")
	_recipient_label.tooltip_text = _recipient_label.text
	_recipient_swatch.color = recipient_color
	_recipient_icon.texture = Icons.get_icon("ui_squad" if not squad_ids.is_empty() else "ui_target")
	for id: String in _cmd_buttons:
		var button: Button = _cmd_buttons[id]
		button.disabled = squad_ids.is_empty()
		var on := (g.input_ctl.mode == "cmd:" + id) or (active != "" and active == id)
		button.add_theme_stylebox_override("normal", UiTheme.button_box("pressed" if on else "normal"))
	squad_panel.refresh(false)
	_refresh_abilities(command_units())
	_update_command_bar_height()


func _update_command_bar_height() -> void:
	if _command_panel == null:
		return
	if _compact:
		_command_panel.offset_top = _command_panel.offset_bottom - 64.0
		if is_instance_valid(info_panel):
			# the drawer is top-anchored on phones while the bar is bottom-anchored: convert the
			# bar's top edge to an absolute position before ending the drawer above it
			var bar_top := _command_panel.anchor_top * get_viewport().get_visible_rect().size.y + _command_panel.offset_top
			info_panel.offset_bottom = bar_top - 8.0
		return
	# Desktop: the panel grows upward to its two rows; the details panel ends above it.
	_command_panel.offset_top = _command_panel.offset_bottom
	var bar_height := _command_panel.get_combined_minimum_size().y
	info_panel.offset_bottom = _command_panel.offset_bottom - bar_height - 10.0


func _refresh_abilities(units: Array) -> void:
	var grouped: Dictionary = {}
	for unit: Unit in units:
		for group_ability_id: String in g.world.combat.ability_ids(unit):
			if not grouped.has(group_ability_id):
				grouped[group_ability_id] = []
			(grouped[group_ability_id] as Array).append(unit)
	var signature_ids: Array = grouped.keys()
	signature_ids.sort()
	var signature_parts: Array[String] = []
	for signature_variant in signature_ids:
		var signature_ability_id := str(signature_variant)
		var owner_ids: Array[int] = []
		for owner: Unit in grouped[signature_ability_id]:
			owner_ids.append(owner.id)
		owner_ids.sort()
		var owner_keys: Array[String] = []
		for owner_id: int in owner_ids:
			owner_keys.append(str(owner_id))
		signature_parts.append("%s:%s" % [signature_ability_id, ",".join(owner_keys)])
	var signature := ";".join(signature_parts)
	if signature != _ability_signature:
		_rebuild_ability_row(grouped)
		_ability_signature = signature
	_ability_scroll.visible = not grouped.is_empty()
	_ability_separator.visible = not grouped.is_empty()
	if grouped.is_empty():
		return
	var ability_ids: Array = grouped.keys()
	ability_ids.sort()
	for ability_variant in ability_ids:
		var ability_id := str(ability_variant)
		var owners: Array = grouped[ability_id]
		var button: Button = _ability_buttons.get(ability_id)
		if button == null:
			continue
		var ready_count := 0
		var remaining := 0.0
		var cooldown := 0.0
		var ability_name := ability_id.replace("_", " ").capitalize()
		for unit: Unit in owners:
			var info := g.world.combat.ability_info(unit, ability_id)
			if bool(info.get("ready", false)):
				ready_count += 1
			else:
				remaining = maxf(remaining, float(info.get("cooldown_left", 0.0)))
			cooldown = maxf(cooldown, float(info.get("cooldown", 0.0)))
			ability_name = Loc.t(str(info.get("name", ability_name)))
		button.disabled = ready_count == 0
		var badge := button.get_meta("ability_badge") as Label
		badge.text = "%d/%d" % [ready_count, owners.size()]
		var cooldown_overlay := button.get_meta("cooldown_overlay") as ColorRect
		var ratio := clampf(remaining / cooldown, 0.0, 1.0) if cooldown > 0.0 else (1.0 if remaining > 0.0 else 0.0)
		cooldown_overlay.visible = ratio > 0.0
		cooldown_overlay.offset_bottom = -16.0 + 32.0 * ratio
		var key_label := _ability_key_label(_ability_shortcuts.find(ability_id))
		var status := Loc.t("Ready: %d/%d") % [ready_count, owners.size()]
		if ready_count == 0:
			status += " · %.0fs" % remaining
		button.tooltip_text = ("%s (%s) · %s" % [ability_name, key_label, status]) if key_label != "" else ("%s · %s" % [ability_name, status])


## Key bound to the ability shortcut slot `index` (App's "ability_N" actions), or "".
func _ability_key_label(index: int) -> String:
	if index < 0 or index >= ABILITY_HOTKEYS:
		return ""
	for event: InputEvent in InputMap.action_get_events("ability_%d" % (index + 1)):
		if event is InputEventKey:
			var key := event as InputEventKey
			return OS.get_keycode_string(key.keycode if key.keycode != KEY_NONE else key.physical_keycode)
	return ""



func _rebuild_ability_row(grouped: Dictionary) -> void:
	_ability_shortcuts.clear()
	_ability_buttons.clear()
	for child in _ability_row.get_children():
		if child is Button:
			child.queue_free()
	var ability_ids: Array = grouped.keys()
	ability_ids.sort()
	for ability_variant in ability_ids:
		var ability_id := str(ability_variant)
		var shortcut := _ability_shortcuts.size()
		if shortcut < ABILITY_HOTKEYS:
			_ability_shortcuts.append(ability_id)
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(48, 48) if _compact else Vector2(58, 58)
		button.set_meta("ability_id", ability_id)
		var icon := TextureRect.new()
		icon.anchor_left = 0.5
		icon.anchor_right = 0.5
		icon.anchor_top = 0.5
		icon.anchor_bottom = 0.5
		icon.offset_left = -16
		icon.offset_right = 16
		icon.offset_top = -16
		icon.offset_bottom = 16
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = Icons.get_icon("abl_" + ability_id)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(icon)
		var cooldown_overlay := ColorRect.new()
		cooldown_overlay.color = Color(0.02, 0.03, 0.06, 0.62)
		cooldown_overlay.anchor_left = 0.5
		cooldown_overlay.anchor_right = 0.5
		cooldown_overlay.anchor_top = 0.5
		cooldown_overlay.anchor_bottom = 0.5
		cooldown_overlay.offset_left = -16
		cooldown_overlay.offset_right = 16
		cooldown_overlay.offset_top = -16
		cooldown_overlay.offset_bottom = -16
		cooldown_overlay.visible = false
		cooldown_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(cooldown_overlay)
		button.set_meta("cooldown_overlay", cooldown_overlay)
		var badge := Label.new()
		badge.anchor_left = 1.0
		badge.anchor_right = 1.0
		badge.anchor_top = 1.0
		badge.anchor_bottom = 1.0
		badge.offset_left = -34
		badge.offset_right = 0
		badge.offset_top = -16
		badge.offset_bottom = 0
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_theme_font_size_override("font_size", 9)
		badge.add_theme_color_override("font_color", Color.WHITE)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(badge)
		button.set_meta("ability_badge", badge)
		var aid: String = ability_id
		button.pressed.connect(func() -> void: _activate_ability(aid))
		_ability_buttons[ability_id] = button
		_ability_row.add_child(button)
	_update_ability_scroll_width()


func _update_ability_scroll_width() -> void:
	var width := 0.0
	for button: Button in _ability_buttons.values():
		width += button.custom_minimum_size.x
	if _ability_buttons.size() > 1:
		width += 5.0 * float(_ability_buttons.size() - 1)
	_ability_scroll.custom_minimum_size.x = maxf(48.0 if _compact else 56.0, width)


func _activate_ability(ability_id: String) -> void:
	var owners: Array = []
	var target_type := "none"
	for unit: Unit in command_units():
		if g.world.combat.ability_ids(unit).has(ability_id):
			owners.append(unit)
			target_type = str(g.world.combat.ability_info(unit, ability_id).get("target", target_type))
	if owners.is_empty():
		return
	if target_type == "none":
		var used := 0
		var failure := ""
		for unit: Unit in owners:
			if bool(g.world.combat.ability_info(unit, ability_id).get("ready", false)):
				failure = g.world.combat.use_ability(unit, ability_id, {})
				if failure == "":
					used += 1
		if failure != "":
			var reason_keys := {
				"cooldown": "reason.cooldown",
				"no_target": "reason.no_target",
				"downed": "reason.downed",
				"unknown": "reason.unknown",
			}
			add_note({"text": Loc.t(str(reason_keys.get(failure, "reason.unknown"))), "kind": "info"}, 2.0)
		elif used > 0:
			add_note({"text": Loc.t("%d used ability: %s") % [used, Loc.t(ability_id.replace("_", " ").capitalize())], "kind": "good"}, 2.0)
	else:
		_select_command_recipients(command_squad_ids())
		g.input_ctl.set_mode("ability:" + ability_id)



func ability_button_for(ability_id: String) -> Button:
	for child in _ability_row.get_children():
		if child is Button and str((child as Button).get_meta("ability_id", "")) == ability_id:
			return child as Button
	return null


func _unhandled_key_input(event: InputEvent) -> void:
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	for i in mini(ABILITY_HOTKEYS, _ability_shortcuts.size()):
		if event.is_action_pressed("ability_%d" % (i + 1)):
			_activate_ability(_ability_shortcuts[i])
			get_viewport().set_input_as_handled()
			return
	for c: Array in COMMANDS:
		if event.is_action_pressed("cmd_" + str(c[0])):
			command(str(c[0]))
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("cmd_build"):
		command("build")
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("cmd_gather"):
		command("gather")
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("toggle_help"):
		_help.visible = not _help.visible
	elif event.is_action_pressed("cancel") and g.input_ctl.mode == "":
		if villages.close_top():
			pass
		elif squad_panel.picker_open():
			squad_panel.close_picker()
		elif build_menu.visible:
			build_menu.hide()
		elif _help.visible:
			_help.hide()
		elif info_panel.mobile_collapsed == false and (App.is_touch() or App.is_mobile_web()):
			info_panel.mobile_collapsed = true
			info_panel.visible = false
		else:
			pause_menu.open()
		get_viewport().set_input_as_handled()

# --- trade -------------------------------------------------------------------------------------

func _build_trade_panel() -> void:
	_trade_panel = UiTheme.panel()
	_trade_panel.name = "Trade"
	root.add_child(_trade_panel)
	_trade_panel.anchor_left = 0.5
	_trade_panel.anchor_right = 0.5
	_trade_panel.offset_left = -300
	_trade_panel.offset_right = 300
	_trade_panel.offset_top = 76
	var v := UiTheme.vbox(6)
	_trade_panel.add_child(v)
	var head := UiTheme.hbox(8)
	var t := UiTheme.title(Loc.t("Merchant airship at the dock"), 20)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := UiTheme.button("", "ui_close", Loc.t("Hide the wares until the next visit"))
	close.pressed.connect(func() -> void: _trade_dismissed = g.world.factions.trader_id)
	head.add_child(close)
	v.add_child(head)
	_trade_list = UiTheme.vbox(4)
	v.add_child(_trade_list)
	_trade_panel.visible = false


func _update_trade() -> void:
	var offers: Array = g.world.factions.trade_offers
	_trade_panel.visible = not offers.is_empty() and _trade_dismissed != g.world.factions.trader_id
	if offers.size() == _trade_count:
		return
	_trade_count = offers.size()
	for c in _trade_list.get_children():
		c.queue_free()
	for i in offers.size():
		var o: Dictionary = offers[i]
		var it: Dictionary = o["item"]
		var h := UiTheme.hbox(8)
		var ic := TextureRect.new()
		ic.texture = Icons.item_icon(it, 48)
		ic.custom_minimum_size = Vector2(40, 40)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		h.add_child(ic)
		var l := UiTheme.label("%s  (%s)" % [Loc.item_name(it), Loc.def_name("items/qualities", str(it.get("quality", "")))], 16, Icons.quality_color(str(it.get("quality", "common"))))
		l.tooltip_text = "\n".join(ItemGen.describe(it))
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		var b := UiTheme.button(Loc.t("Buy %d") % int(o["price"]), "res_gold")
		b.custom_minimum_size = Vector2(120, 36)
		var idx := i
		b.pressed.connect(func() -> void:
			var err := g.world.factions.buy_offer(idx)
			if err != "":
				add_note({"text": Loc.t(err), "kind": "bad"}, 3.0)
			else:
				Sfx.play(&"coin")
			_trade_count = -1)
		h.add_child(b)
		_trade_list.add_child(h)


# --- overlays ----------------------------------------------------------------------------------

func _build_overlays() -> void:
	_box = Panel.new()
	var sb := UiTheme.flat(Color(0.4, 0.8, 1.0, 0.12), 2, Color(0.5, 0.85, 1.0, 0.9), 1)
	_box.add_theme_stylebox_override("panel", sb)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.visible = false
	root.add_child(_box)
	_tooltip_panel = PanelContainer.new()
	_tooltip_panel.add_theme_stylebox_override("panel", UiTheme.flat(Color(0.05, 0.07, 0.11, 0.9), 5, UiTheme.BORDER_DIM, 1))
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip = UiTheme.label("", 15)
	_tooltip_panel.add_child(_tooltip)
	root.add_child(_tooltip_panel)
	_mode_hint = UiTheme.label("", 18, UiTheme.GOLD, UiTheme.bold_font)
	_mode_hint.anchor_left = 0.5
	_mode_hint.anchor_right = 0.5
	_mode_hint.offset_left = -400
	_mode_hint.offset_right = 400
	_mode_hint.offset_top = 70
	_mode_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_mode_hint)
	_help = UiTheme.panel()
	_help.visible = false
	root.add_child(_help)
	_help.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_help.offset_left = -360
	_help.offset_right = 360
	_help.offset_top = -300
	_help.offset_bottom = 300
	var v := UiTheme.vbox(4)
	_help.add_child(v)
	v.add_child(UiTheme.title(Loc.t("Controls"), 26))
	for line: String in [
		"Left click: select unit / squad / building / site     Drag: box-select",
		"Right click: move · attack enemy or camp · gather resource · trade (airship on a trade post)",
		"W A S D / arrows / screen edge / middle drag: pan     Wheel: zoom     Q / E: rotate 90°",
		"1–9 or Tab: select squads (press twice to centre)     Home: back to the hearth",
		"Z C V T N J K O I: squad abilities (shown on the command bar)",
		"M Move  F Attack  H Defend  X Explore  P Patrol  Y Escort  U Auto  R Retreat",
		"B Build menu  G Gather zones & work priorities",
		"Space: pause     [ ] or , . : game speed",
		"Quick save: F5 (Ctrl+S on web)  Quick load: F9 (Ctrl+L on web)  Esc: cancel / menu  F1: help",
		"",
		"Tip: give orders and watch — settlers work zones on their own, squads on Auto",
		"defend, explore and clear weak camps, the drone scouts, the airship trades.",
	]:
		v.add_child(UiTheme.label(Loc.t(line), 17))
		v.add_child(UiTheme.label(Loc.t("Touch: tap to select or order; drag to pan; pinch to zoom; twist with two fingers to rotate. Use Box for rectangle selection."), 16))


func _on_mode(m: String) -> void:
	var text := ""
	if m.begins_with("cmd:"):
		text = Loc.t("%s: click a target  (right-click / Esc to cancel, Shift to keep)") % Loc.t(m.substr(4).capitalize())
	elif m.begins_with("ability:"):
		text = Loc.t("Target %s (right-click / Esc to cancel)") % Loc.t(m.substr(8).replace("_", " ").capitalize())
	elif m.begins_with("build:"):
		text = Loc.t("Place %s  (right-click / Esc to cancel, Shift to place several)") % Loc.def_name("buildings", m.substr(6))
	elif m.begins_with("zone:"):
		text = Loc.t("Drag a rectangle to mark a %s zone  (right-click / Esc to cancel)") % Loc.t(m.substr(5))
	if App.is_touch() or App.is_mobile_web():
		if m.begins_with("cmd:") or m.begins_with("ability:"):
			text = Loc.t("Tap the target for %s  (Cancel to leave)") % Loc.t(m.substr(m.find(":") + 1).capitalize())
		elif m.begins_with("build:"):
			text = Loc.t("Tap a site for placement, then confirm or cancel.")
		elif m.begins_with("zone:"):
			text = Loc.t("Drag a rectangle to mark a %s zone  (Cancel to leave)") % Loc.t(m.substr(5))
	_mode_hint.text = text
	_update_responsive()


func _on_selection() -> void:
	info_panel.refresh(true)
	# not forced: rebuilding the member cards here would free the card under a click between
	# its press and release, so the release fell through to the world and cleared the selection
	squad_panel.refresh(false)


func _process(delta: float) -> void:
	if not _note_queue.is_empty():
		add_note(_note_queue.pop_front(), 9.0)
	_t -= delta
	if _t <= 0.0:
		_t = 0.25
		_update_top()
		_update_commands()
		_update_trade()
		info_panel.refresh(false)
		squad_panel.refresh(false)
		roster.refresh()
		villages.refresh()
	var ic := g.input_ctl
	_box.visible = ic.dragging
	if ic.dragging:
		_box.position = ic.drag_rect.position / root.get_global_transform_with_canvas().get_scale()
		_box.size = ic.drag_rect.size / root.get_global_transform_with_canvas().get_scale()
	var tip := ic.hover_info
	if ic.mode.begins_with("build:") and ic.ghost_reason() != "":
		tip = Loc.t("Can't build: %s") % Loc.t(ic.ghost_reason())
	elif ic.mode.begins_with("zone:"):
		var n := ic.zone_count(ic.mode.substr(5))
		if n >= 0:
			tip = Loc.t("%d %s") % [n, Loc.t("tiles" if ic.mode.ends_with("farm") else "resource nodes")]
	var touch_ui := App.is_touch() or App.is_mobile_web()
	if touch_ui and ic.mode == "" and not ic.is_long_pressing():
		tip = ""  # no hover on touch screens: the tip shows while a finger is held down
	_tooltip_panel.visible = tip != "" and not is_mouse_over_ui()
	if _tooltip_panel.visible:
		_tooltip.text = Loc.t(tip)
		var mp := root.get_local_mouse_position()
		var tip_position := mp + (Vector2(18, -64) if touch_ui else Vector2(18, 22))
		if _compact and info_panel.visible:
			var tip_size := _tooltip_panel.get_combined_minimum_size()
			var drawer_rect := info_panel.get_global_rect()
			if Rect2(tip_position, tip_size).intersects(drawer_rect):
				tip_position.x = maxf(8.0, drawer_rect.position.x - tip_size.x - 8.0)
		_tooltip_panel.position = tip_position
		_tooltip_panel.size = Vector2.ZERO
