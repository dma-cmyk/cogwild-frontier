class_name PauseMenu
extends Control
## Esc menu: pauses the game; resume, save to slots 1-3, load (quick slot or 1-3), controls,
## music volume, back to title.

var g: Game
var _panel: PanelContainer
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
	_panel.offset_left = -260
	_panel.offset_right = 260
	_panel.offset_top = -330
	_panel.offset_bottom = 330
	_box = UiTheme.vbox(8)
	_panel.add_child(_box)
	visible = false


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
	var vol := UiTheme.hbox(8)
	vol.add_child(UiTheme.label(Loc.t("Music"), 15))
	var sl := HSlider.new()
	sl.min_value = -40
	sl.max_value = 0
	sl.value = Sfx.music_db
	sl.custom_minimum_size = Vector2(220, 20)
	sl.focus_mode = Control.FOCUS_NONE
	sl.value_changed.connect(func(v: float) -> void: Sfx.set_music_volume(v))
	vol.add_child(sl)
	_box.add_child(vol)
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
		close()
		get_viewport().set_input_as_handled()
