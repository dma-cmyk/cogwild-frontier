class_name RosterPanel
extends PanelContainer
## List of everyone in the company (squads, settlers, machines) with what they are doing.
## Click a row to select and centre the camera.

var g: Game
var hud: Hud
var _list: VBoxContainer
var _sig := ""


func setup(game: Game, h: Hud) -> void:
	g = game
	hud = h
	name = "Roster"
	add_theme_stylebox_override("panel", UiTheme.panel_box())
	# Rows are Buttons whose contents hang off anchors, so they add no width of their own: without
	# an explicit right edge the panel collapsed to the width of the group headings and every name
	# and activity was clipped away.
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 10
	offset_right = 430
	offset_top = -840
	offset_bottom = -120
	var v := UiTheme.vbox(6)
	add_child(v)
	var head := UiTheme.hbox(8)
	head.add_child(UiTheme.title(Loc.t("Company"), 22))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close := UiTheme.button("", "ui_close", Loc.t("Close"))
	close.pressed.connect(func() -> void: visible = false)
	head.add_child(close)
	v.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_list = UiTheme.vbox(3)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	visible = false


func toggle() -> void:
	visible = not visible
	_sig = ""
	refresh()


func refresh() -> void:
	if not visible:
		return
	var units: Array = g.world.unit_list.filter(func(u: Unit) -> bool: return u.is_player() and u.alive)
	# the signature has to cover everything a row draws, or a promotion, a rename or a new order
	# leaves the open roster showing yesterday's news
	var sig := ""
	for u: Unit in units:
		sig += "%d:%s:%d:%s:%s;" % [u.id, u.name, u.char_level(), str(u.squad_id), hud.info_panel._activity(u)]
	if sig == _sig:
		return
	_sig = sig
	for c in _list.get_children():
		c.queue_free()
	for group: Array in [["Squads", func(u: Unit) -> bool: return u.squad_id >= 0],
			["Settlers", func(u: Unit) -> bool: return u.squad_id < 0 and u.is_person()],
			["Machines", func(u: Unit) -> bool: return u.squad_id < 0 and u.is_machine()]]:
		var members: Array = units.filter(group[1])
		if members.is_empty():
			continue
		_list.add_child(UiTheme.label("%s (%d)" % [Loc.t(str(group[0])), members.size()], 16, UiTheme.GOLD))
		for u: Unit in members:
			var b := Button.new()
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(0, 40)
			var h := UiTheme.hbox(6)
			h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			h.offset_left = 6
			b.add_child(h)
			var portrait := TextureRect.new()
			portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			portrait.custom_minimum_size = Vector2(34, 34)
			portrait.texture = hud.portraits.get_portrait("u%d" % u.id, u.dna, 128)
			portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
			h.add_child(portrait)
			h.add_child(UiTheme.icon(u.class_icon(), 26))
			var nm := UiTheme.label("%s  Lv.%d" % [u.name, u.char_level()], 14, UiTheme.TEXT, UiTheme.bold_font)
			nm.custom_minimum_size = Vector2(160, 0)
			nm.clip_text = true
			h.add_child(nm)
			var act := UiTheme.label(hud.info_panel._activity(u), 13, UiTheme.TEXT_DIM)
			act.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			act.clip_text = true
			h.add_child(act)
			var uid := u.id
			b.pressed.connect(func() -> void:
				var uu := g.world.get_unit(uid)
				if uu:
					g.select_units([uid])
					g.focus_pos(uu.pos))
			_list.add_child(b)
