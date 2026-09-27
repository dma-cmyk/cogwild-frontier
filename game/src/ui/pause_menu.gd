class_name PauseMenu
extends Control
## Esc menu: pauses the game; resume, save/load, settings, controls and back to title.

var g: Game
var _panel: PanelContainer
var _scroll: ScrollContainer
var _box: VBoxContainer
var _speed_before := 1


func setup(game: Game) -> void:
	g = game
	name = "PauseMenu"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel = UiTheme.panel()
	add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_fit_panel()
	get_viewport().size_changed.connect(_fit_panel)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(_scroll)
	_box = UiTheme.vbox(8)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_box)
	visible = false


func _fit_panel() -> void:
	if not is_instance_valid(_panel):
		return
	var viewport_size := get_viewport_rect().size
	var width := minf(520.0, maxf(280.0, viewport_size.x - 24.0))
	var height := minf(660.0, maxf(240.0, viewport_size.y - 24.0))
	_panel.offset_left = -width * 0.5
	_panel.offset_right = width * 0.5
	_panel.offset_top = -height * 0.5
	_panel.offset_bottom = height * 0.5


func open() -> void:
	if visible:
		return
	_speed_before = g.speed
	g.set_speed(0)
	_rebuild()
	visible = true


func close() -> void:
	visible = false
	g.set_speed(_speed_before if _speed_before > 0 else 1)


func _rebuild() -> void:
	for c in _box.get_children():
		c.queue_free()
	_box.add_child(UiTheme.title(Loc.t("Paused — Day %d") % g.world.day, 26))
	_box.add_child(Loc.language_selector())
	_box.add_child(_btn(Loc.t("Resume"), "ui_play", close))
	_box.add_child(UiTheme.label(Loc.t("Save"), 16, UiTheme.GOLD))
	for slot in [1, 2, 3]:
		var info := SaveGame.info(slot)
		var s: int = slot
		_box.add_child(_btn(Loc.t("Slot %d — %s") % [slot, _describe(info)], "ui_save", func() -> void:
			g.quick_save(s)
			_rebuild()))
	_box.add_child(UiTheme.label(Loc.t("Load"), 16, UiTheme.GOLD))
	for slot in [0, 1, 2, 3]:
		var info := SaveGame.info(slot)
		if not bool(info.get("exists", false)):
			continue
		var s: int = slot
		_box.add_child(_btn("%s — %s" % [Loc.t("Quick save") if slot == 0 else Loc.t("Slot %d") % slot, _describe(info)], "ui_load", func() -> void: App.load_game(s)))
	_box.add_child(_btn(Loc.t("Settings"), "ui_gear", func() -> void: SettingsPanel.open(self)))
	_box.add_child(_btn(Loc.t("Controls (F1)"), "ui_scroll", func() -> void:
		close()
		g.hud._help.visible = true))
	_box.add_child(_btn(Loc.t("Quit to title"), "ui_close", func() -> void: App.to_title()))


func _describe(info: Dictionary) -> String:
	if not bool(info.get("exists", false)):
		return Loc.t("empty")
	if bool(info.get("damaged", false)):
		return Loc.t("damaged file")
	return Loc.t("%s, day %d, %d people") % [info.get("company", ""), int(info.get("day", 1)), int(info.get("population", 0))]


func _btn(text: String, icon: String, cb: Callable) -> Button:
	var b := UiTheme.button(text, icon)
	b.custom_minimum_size = Vector2(0, 40)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(cb)
	return b


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("cancel"):
		if get_node_or_null("SettingsPanel") != null:
			return
		close()
		get_viewport().set_input_as_handled()
