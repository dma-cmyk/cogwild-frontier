class_name DiplomacyPanel
extends PanelContainer
## Overview of every known village: race, relation tier and bar, what they want and whether a
## trade is possible right now. Clicking a row selects the village and centres the camera.

var g: Game
var hud: Hud
var _list: VBoxContainer
var _signature := ""


func setup(game: Game, h: Hud) -> void:
	g = game
	hud = h
	name = "DiplomacyPanel"
	add_theme_stylebox_override("panel", UiTheme.panel_box())
	var v := UiTheme.vbox(6)
	add_child(v)
	var head := UiTheme.hbox(8)
	var title := UiTheme.title(Loc.t("Neighbours"), 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := UiTheme.button("", "ui_close", Loc.t("Close"))
	close.pressed.connect(func() -> void: visible = false)
	head.add_child(close)
	v.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	_list = UiTheme.vbox(4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	visible = false
	layout()


func layout() -> void:
	var screen := g.get_viewport().get_visible_rect().size
	var w := minf(560.0, screen.x - 24.0)
	var h := minf(440.0, screen.y - 88.0)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -w * 0.5
	offset_right = w * 0.5
	offset_top = -h * 0.5
	offset_bottom = h * 0.5


func toggle() -> void:
	visible = not visible
	if visible:
		layout()
		_signature = ""
		refresh()


func refresh() -> void:
	if not visible:
		return
	var villages := g.world.diplomacy.known_villages()
	var signature := ""
	for st: Dictionary in villages:
		signature += "%d:%d:%d;" % [int(st["id"]), int(st.get("relation", 0)),
			int(bool(st.get("ruined", false)))]
	if signature == _signature:
		return
	_signature = signature
	for c in _list.get_children():
		c.queue_free()
	if villages.is_empty():
		_list.add_child(UiTheme.label(Loc.t("No villages found yet. Explore — the folk out there trade."), 15, UiTheme.TEXT_DIM))
		return
	for st: Dictionary in villages:
		_list.add_child(_row(st))


func _row(st: Dictionary) -> Control:
	var sid := int(st["id"])
	var value := int(st.get("relation", 0))
	var tier := Diplomacy.tier_for(value)
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 58)
	var h := UiTheme.hbox(8)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 8
	h.offset_right = -8
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(h)
	var ic := UiTheme.icon(str(st.get("icon", "poi_village")), 30)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(ic)
	var v := UiTheme.vbox(1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var nm := UiTheme.label(str(st["name"]), 15, UiTheme.TEXT, UiTheme.bold_font)
	nm.clip_text = true
	v.add_child(nm)
	var detail := Loc.t("%s · %d people") % [Loc.def_name("races", str(st.get("race", ""))),
		int(st.get("population", 0))]
	var request: Dictionary = st.get("request", {})
	if bool(st.get("ruined", false)):
		detail += Loc.t("  ·  in ruins")
	elif not request.is_empty():
		detail += Loc.t("  ·  wants %d %s") % [int(request.get("amount", 0)), Loc.t(str(request.get("resource", "food")))]
	v.add_child(UiTheme.label(detail, 13, UiTheme.TEXT_DIM))
	var right := UiTheme.vbox(2)
	right.custom_minimum_size = Vector2(120, 0)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(right)
	right.add_child(UiTheme.label("%s %d" % [Loc.t(tier), value], 14, VillagePanel.tier_color(tier)))
	var bar := UiTheme.bar(VillagePanel.tier_color(tier), 8)
	bar.value = clampf((float(value) + 100.0) / 200.0, 0.0, 1.0)
	right.add_child(bar)
	button.pressed.connect(func() -> void:
		g.select_site(sid)
		g.focus_pos(Vector2(st["center"]))
		visible = false)
	return button
