class_name PlacesPanel
extends PanelContainer
## Read-only directory of known surface sites and owned facilities. Never generates map data.

const FILTERS := ["all", "sites", "facilities", "dungeon", "ruins", "trade", "hostile"]
var g: Game
var hud: Hud
var _title: Label
var _hint: Label
var _count: Label
var _search: LineEdit
var _filter: OptionButton
var _close: Button
var _list: VBoxContainer
var _rows: Dictionary = {}
var _empty: Label


func setup(game: Game, h: Hud) -> void:
	g = game
	hud = h
	name = "PlacesPanel"
	add_theme_stylebox_override("panel", UiTheme.panel_box())
	var body := UiTheme.vbox(8)
	add_child(body)
	var head := UiTheme.hbox(8)
	_title = UiTheme.title("", 23)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_close = UiTheme.button("", "ui_close")
	_close.name = "PlacesClose"
	_close.pressed.connect(close_window)
	head.add_child(_close)
	body.add_child(head)
	_hint = UiTheme.label("", 14, UiTheme.TEXT_DIM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_hint)
	var tools := UiTheme.hbox(8)
	_search = LineEdit.new()
	_search.name = "PlacesSearch"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.custom_minimum_size.y = 36
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_text: String) -> void: refresh(true))
	tools.add_child(_search)
	_filter = OptionButton.new()
	_filter.name = "PlacesFilter"
	_filter.custom_minimum_size = Vector2(190, 36)
	for key: String in FILTERS:
		_filter.add_item(Loc.t("places.filter." + key))
	_filter.item_selected.connect(func(_index: int) -> void: refresh(true))
	tools.add_child(_filter)
	body.add_child(tools)
	_count = UiTheme.label("", 13, UiTheme.GOLD)
	body.add_child(_count)
	var scroll := ScrollContainer.new()
	scroll.name = "PlacesScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	_list = UiTheme.vbox(6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_empty = UiTheme.label("", 15, UiTheme.TEXT_DIM)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(_empty)
	visible = false
	layout()


func layout() -> void:
	var screen := g.get_viewport().get_visible_rect().size
	var width := minf(790.0, screen.x - 32.0)
	var height := minf(660.0, screen.y - 110.0)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -width * 0.5
	offset_right = width * 0.5
	offset_top = -height * 0.5
	offset_bottom = height * 0.5


func open() -> void:
	visible = true
	layout()
	refresh(true)
	_search.grab_focus()


func close_window() -> void:
	visible = false
	_search.release_focus()


static func known_surface(st: Dictionary) -> bool:
	return not st.is_empty() and bool(st.get("discovered", false)) and str(st.get("kind", "")) != "dungeon_floor"


static func site_name(st: Dictionary) -> String:
	return Loc.t(Loc.generated(st, "name"))


static func site_type(st: Dictionary) -> String:
	var kind := str(st.get("kind", ""))
	if kind in ["ruins", "dungeon"]:
		return Loc.t("places.type." + kind)
	return Loc.t("site_kind." + kind)


static func facility_name(b: Building) -> String:
	return b.name if not b.name.is_empty() else Loc.def_name("buildings", b.type)


func refresh(_force: bool = false) -> void:
	if not visible:
		return
	_title.text = Loc.t("places.title")
	_hint.text = Loc.t("places.hint")
	_close.tooltip_text = Loc.t("places.close")
	_search.placeholder_text = Loc.t("places.search")
	for i in FILTERS.size():
		_filter.set_item_text(i, Loc.t("places.filter." + str(FILTERS[i])))
	var query := _search.text.strip_edges().to_lower()
	var filter := str(FILTERS[maxi(0, _filter.selected)])
	var present := {}
	for sid: Variant in g.world.sites:
		var st: Dictionary = g.world.sites[sid]
		if not known_surface(st):
			continue
		var kind := str(st.get("kind", ""))
		if filter == "facilities" or (filter in ["dungeon", "ruins"] and kind != filter):
			continue
		if filter == "trade" and kind not in ["trade_post", "village", "town"]:
			continue
		if filter == "hostile" and not _hostile(st):
			continue
		var title := site_name(st)
		var type := site_type(st)
		if not query.is_empty() and not (title + " " + type).to_lower().contains(query):
			continue
		var key := "site_%d" % int(sid)
		present[key] = true
		_update_row(key, "site", int(sid), title, type, _site_status(st), Vector2(st["center"]))
	if filter in ["all", "facilities"]:
		for bid: Variant in g.world.buildings:
			var b: Building = g.world.buildings[bid]
			if b.faction != "player":
				continue
			var title := facility_name(b)
			var type := Loc.def_name("buildings", b.type)
			if not query.is_empty() and not (title + " " + type).to_lower().contains(query):
				continue
			var key := "building_%d" % b.id
			present[key] = true
			var status := Loc.t("places.built") if b.is_built() else Loc.t("places.constructing") % roundi(b.progress * 100.0)
			status = Loc.t("places.level") % b.level + " · " + status
			_update_row(key, "building", b.id, title, type, status, b.center())
	for key: String in _rows.keys():
		if not present.has(key):
			var row: Dictionary = _rows[key]
			(row["panel"] as Control).queue_free()
			_rows.erase(key)
	_count.text = Loc.t("places.count") % present.size()
	_empty.text = Loc.t("places.empty")
	_empty.visible = present.is_empty()


func _hostile(st: Dictionary) -> bool:
	return not bool(st.get("cleared", false)) and (bool(st.get("hostile", false)) or (g.world.diplomacy.is_community(st) and int(st.get("relation", 0)) <= Diplomacy.HOSTILE_AT))


func _site_status(st: Dictionary) -> String:
	var parts := PackedStringArray()
	if bool(st.get("ruined", false)):
		parts.append(Loc.t("places.ruined"))
	if _hostile(st):
		parts.append(Loc.t("places.hostile"))
	elif bool(st.get("cleared", false)):
		parts.append(Loc.t("places.cleared"))
	if bool(st.get("looted", false)):
		parts.append(Loc.t("places.looted"))
	if str(st.get("kind", "")) == "dungeon":
		parts.append(Loc.t("places.dungeon.stats") % [int(st.get("difficulty", 1)), int(st.get("floors", 1))])
		# Only entrance metadata is read: no floor layout, enemies or loot are inspected.
		var visited := false
		for floor_id: Variant in st.get("floor_sids", []):
			if int(floor_id) >= 0:
				visited = true
		var expiry := int(st.get("spawn_day", g.world.day)) + (Dungeons.ABANDONED_DAYS if visited else Dungeons.UNVISITED_DAYS)
		if str(st.get("state", "open")) == "cleared":
			expiry = int(st.get("cleared_day", g.world.day)) + Dungeons.CLEARED_DAYS
		parts.append(Loc.t("places.dungeon.expiry") % maxi(0, expiry - g.world.day))
	if parts.is_empty():
		parts.append(Loc.t("places.discovered"))
	return " · ".join(parts)


func _update_row(key: String, kind: String, id: int, title: String, type: String, status: String, pos: Vector2) -> void:
	if not _rows.has(key):
		var panel := UiTheme.panel()
		panel.name = "Place_" + key
		panel.set_meta("place_kind", kind)
		panel.set_meta("place_id", id)
		var line := UiTheme.hbox(12)
		panel.add_child(line)
		var labels := UiTheme.vbox(3)
		labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(labels)
		var heading := UiTheme.label("", 17, UiTheme.TEXT, UiTheme.bold_font)
		heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		labels.add_child(heading)
		var detail := UiTheme.label("", 14, UiTheme.TEXT_DIM)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		labels.add_child(detail)
		var location := UiTheme.label("", 13, UiTheme.TEXT_DIM)
		location.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		labels.add_child(location)
		var button := UiTheme.button(Loc.t("places.focus"), "ui_target")
		button.name = "Focus_" + key
		button.set_meta("place_kind", kind)
		button.set_meta("place_id", id)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.pressed.connect(_focus.bind(kind, id))
		line.add_child(button)
		_list.add_child(panel)
		_rows[key] = {"panel": panel, "heading": heading, "detail": detail, "location": location, "button": button}
	var row: Dictionary = _rows[key]
	(row["heading"] as Label).text = title
	(row["detail"] as Label).text = type + " · " + status
	(row["location"] as Label).text = Loc.t("places.location") % [roundi(pos.distance_to(g.world.home_pos())), roundi(pos.x), roundi(pos.y)]
	(row["button"] as Button).text = Loc.t("places.focus")
	(row["button"] as Button).tooltip_text = Loc.t("places.focus.hint")


func _focus(kind: String, id: int) -> void:
	if kind == "site":
		var st: Dictionary = g.world.sites.get(id, {})
		if not known_surface(st):
			refresh(true)
			return
		close_window()
		g.select_site(id)
		g.focus_pos(Vector2(st["center"]))
	else:
		var b: Building = g.world.buildings.get(id)
		if b == null or b.faction != "player":
			refresh(true)
			return
		close_window()
		g.select_building(id)
		g.focus_pos(b.center())
