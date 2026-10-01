class_name HistoryPanel
extends PanelContainer
## Stable snapshot while reading; incoming events are available through Refresh latest.

const PAGE_SIZE := 20
const FILTERS := ["all", "bad", "discover", "loot", "levelup", "good", "info"]

var g: Game
var hud: Hud
var _records: Array = []
var _page := 0
var _pending_count := 0
var _dirty := true
var _title: Label
var _summary: Label
var _search: LineEdit
var _filter: OptionButton
var _latest: Button
var _previous: Button
var _next: Button
var _page_label: Label
var _scroll: ScrollContainer
var _list: VBoxContainer


func setup(game: Game, h: Hud) -> void:
	g = game
	hud = h
	name = "HistoryPanel"
	add_theme_stylebox_override("panel", UiTheme.panel_box())
	var body := UiTheme.vbox(10)
	add_child(body)
	var head := UiTheme.hbox(8)
	_title = UiTheme.title("", 24)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close := UiTheme.button("", "ui_close", Loc.t("Close"))
	close.name = "CloseHistory"
	close.pressed.connect(close_window)
	head.add_child(close)
	body.add_child(head)
	_summary = UiTheme.label("", 15, UiTheme.TEXT_DIM)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_summary)
	var tools := UiTheme.hbox(8)
	_search = LineEdit.new()
	_search.name = "HistorySearch"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.custom_minimum_size = Vector2(240, 38)
	_search.text_changed.connect(func(_value: String) -> void:
		_page = 0
		_dirty = true
		refresh())
	tools.add_child(_search)
	_filter = OptionButton.new()
	_filter.name = "HistoryFilter"
	_filter.custom_minimum_size = Vector2(150, 38)
	_filter.item_selected.connect(func(_index: int) -> void:
		_page = 0
		_dirty = true
		refresh())
	tools.add_child(_filter)
	_latest = UiTheme.button(Loc.t("history.refresh"), "ui_bell")
	_latest.name = "RefreshHistory"
	_latest.pressed.connect(_show_latest)
	tools.add_child(_latest)
	body.add_child(tools)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_scroll)
	_list = UiTheme.vbox(8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	var pages := UiTheme.hbox(12)
	_previous = UiTheme.button("")
	_previous.name = "HistoryPrevious"
	_previous.pressed.connect(func() -> void:
		_page -= 1
		_dirty = true
		refresh())
	pages.add_child(_previous)
	_page_label = UiTheme.label("", 16, UiTheme.GOLD)
	_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pages.add_child(_page_label)
	_next = UiTheme.button("")
	_next.name = "HistoryNext"
	_next.pressed.connect(func() -> void:
		_page += 1
		_dirty = true
		refresh())
	pages.add_child(_next)
	body.add_child(pages)
	g.world.notified.connect(func(_note: Dictionary) -> void:
		if visible:
			_pending_count += 1)
	Loc.language_changed.connect(func() -> void:
		_dirty = true
		refresh(true))
	visible = false
	layout()


func layout() -> void:
	var screen := g.get_viewport().get_visible_rect().size
	var width := minf(840.0, screen.x - 32.0)
	var height := minf(700.0, screen.y - 160.0)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left = -width * 0.5
	offset_right = width * 0.5
	offset_top = -height * 0.5
	offset_bottom = height * 0.5


func open() -> void:
	visible = true
	layout()
	_show_latest()


func close_window() -> void:
	visible = false


func _show_latest() -> void:
	_records = g.world.notifications.duplicate()
	_page = 0
	_pending_count = 0
	_dirty = true
	refresh(true)


func refresh(force: bool = false) -> void:
	if not visible:
		return
	_summary.text = Loc.t("history.retention", {"count": _records.size(), "limit": World.NOTIFICATION_LIMIT})
	_latest.text = Loc.t("history.refresh_pending", {"count": _pending_count}) if _pending_count > 0 else Loc.t("history.refresh")
	if not _dirty and not force:
		return
	_dirty = false
	_title.text = Loc.t("history.title")
	_search.placeholder_text = Loc.t("history.search")
	_previous.text = Loc.t("history.previous")
	_next.text = Loc.t("history.next")
	if _filter.item_count != FILTERS.size():
		_filter.clear()
		for category: String in FILTERS:
			_filter.add_item(Loc.t("history.filter." + category))
	else:
		for index in FILTERS.size():
			_filter.set_item_text(index, Loc.t("history.filter." + FILTERS[index]))
	var matches: Array = []
	var query := _search.text.strip_edges().to_lower()
	var category: String = FILTERS[maxi(0, _filter.selected)]
	for index in range(_records.size() - 1, -1, -1):
		var note: Dictionary = _records[index]
		if category != "all" and str(note.get("kind", "info")) != category:
			continue
		if not query.is_empty() and not Loc.message(note).to_lower().contains(query):
			continue
		matches.append(note)
	var pages := maxi(1, ceili(float(matches.size()) / PAGE_SIZE))
	_page = clampi(_page, 0, pages - 1)
	_previous.disabled = _page == 0
	_next.disabled = _page >= pages - 1
	_page_label.text = Loc.t("history.page", {"page": _page + 1, "pages": pages, "count": matches.size()})
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if matches.is_empty():
		var empty := UiTheme.label(Loc.t("history.empty" if _records.is_empty() else "history.no_match"), 18, UiTheme.TEXT_DIM)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(empty)
	else:
		for index in range(_page * PAGE_SIZE, mini((_page + 1) * PAGE_SIZE, matches.size())):
			_list.add_child(_row(matches[index]))
	_scroll.scroll_vertical = 0


func _row(note: Dictionary) -> Control:
	var row := UiTheme.panel()
	var body := UiTheme.vbox(4)
	row.add_child(body)
	var head := UiTheme.hbox(8)
	var kind := str(note.get("kind", "info"))
	head.add_child(UiTheme.icon(str(Hud.KIND_ICON.get(kind, "ui_bell")), 22))
	var stamp := Loc.t("history.filter." + kind)
	if note.has("day"):
		stamp = Loc.t("history.day", {"day": int(note["day"])}) + "  " + stamp
	if note.has("hour"):
		var minutes := clampi(int(float(note["hour"]) * 60.0), 0, 1439)
		stamp += "  %02d:%02d" % [minutes / 60, minutes % 60]
	var date := UiTheme.label(stamp, 14, Hud.KIND_COLOR.get(kind, UiTheme.TEXT_DIM))
	date.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(date)
	if _has_target(note):
		var jump := UiTheme.button(Loc.t("history.show_location"), "ui_target")
		jump.add_theme_font_size_override("font_size", 13)
		jump.set_meta("history_note", note)
		jump.pressed.connect(func() -> void:
			close_window()
			hud._note_clicked(note)
			Sfx.play(&"ui_select"))
		head.add_child(jump)
	body.add_child(head)
	var text := UiTheme.label(Loc.message(note), 17, Hud.KIND_COLOR.get(kind, UiTheme.TEXT))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(text)
	return row


func _has_target(note: Dictionary) -> bool:
	if note.get("pos") is Vector2:
		return true
	if g.world.sites.has(int(note.get("site", -1))) or g.world.buildings.has(int(note.get("building", -1))):
		return true
	var unit := g.world.get_unit(int(note.get("unit", -1)))
	return unit != null and unit.alive
