class_name SettingsPanel
extends Control
## Compact modal settings UI shared by the title screen and pause menu.

const TRACK_IDS: Array[String] = ["auto", "shuffle", "off", "title", "frontier_day", "workshop", "night", "battle"]
const QUALITY_IDS: Array[String] = ["auto", "low", "medium", "high"]
const QUALITY_LABELS: Array[String] = ["Auto", "Low", "Medium", "High"]
const SCALE_IDS: Array[String] = ["auto", "small", "normal", "large"]
const SCALE_LABELS: Array[String] = ["Auto", "Small", "Normal", "Large"]
const SPEECH_IDS: Array[String] = ["all", "combat", "off"]
const SPEECH_LABELS: Array[String] = ["All", "Combat only", "Off"]
const AUDIO_SETTINGS := [
	["Master", "audio/master"], ["Music", "audio/music"],
	["SFX", "audio/sfx"], ["Ambience", "audio/ambience"],
]
var _panel: PanelContainer


static func open(parent: Node) -> Control:
	var modal := SettingsPanel.new()
	modal.name = "SettingsPanel"
	parent.add_child(modal)
	if not Loc.language_changed.is_connected(modal._on_language_changed):
		Loc.language_changed.connect(modal._on_language_changed)
	modal._build()
	return modal


func _exit_tree() -> void:
	if Loc.language_changed.is_connected(_on_language_changed):
		Loc.language_changed.disconnect(_on_language_changed)


func _on_language_changed() -> void:
	_build()


func _build() -> void:
	for child in get_children():
		child.queue_free()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_panel = UiTheme.panel()
	add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.offset_left = -460
	_panel.offset_right = 460
	_panel.offset_top = -250
	_panel.offset_bottom = 250
	var layout := UiTheme.vbox(6)
	_panel.add_child(layout)
	var header := UiTheme.hbox(12)
	layout.add_child(header)
	var title := UiTheme.title(Loc.t("Settings"), 25)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := UiTheme.button(Loc.t("Close"), "ui_close")
	close.custom_minimum_size = Vector2(120, 44)
	close.pressed.connect(queue_free)
	header.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	var body := UiTheme.vbox(7)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	body.add_child(_section(Loc.t("Language")))
	var language := Loc.language_selector()
	language.custom_minimum_size.y = 44
	var lang_option := language.get_child(1) as OptionButton
	lang_option.custom_minimum_size = Vector2(160, 44)
	body.add_child(language)
	body.add_child(_section(Loc.t("Sound")))
	body.add_child(_track_row())
	for entry: Array in AUDIO_SETTINGS:
		body.add_child(_volume_row(str(entry[0]), str(entry[1])))
	body.add_child(_section(Loc.t("Graphics")))
	body.add_child(_choice_row(Loc.t("Quality"), "graphics/quality", QUALITY_IDS, QUALITY_LABELS))
	body.add_child(_section(Loc.t("Interface")))
	body.add_child(_choice_row(Loc.t("Speech bubbles"), "interface/speech", SPEECH_IDS, SPEECH_LABELS))
	body.add_child(_choice_row(Loc.t("UI size"), "interface/ui_scale", SCALE_IDS, SCALE_LABELS))


func _section(text: String) -> Label:
	return UiTheme.label(text, 17, UiTheme.GOLD)


func _track_row() -> HBoxContainer:
	var row := UiTheme.hbox(10)
	row.custom_minimum_size.y = 44
	var label := UiTheme.label(Loc.t("Music track"), 16)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(250, 44)
	for i in TRACK_IDS.size():
		option.add_item(Sfx.track_name(TRACK_IDS[i]), i)
	var current := str(Settings.get_value("audio/music_track"))
	var index := TRACK_IDS.find(current)
	option.select(index if index >= 0 else 0)
	option.item_selected.connect(func(selected: int) -> void:
		Settings.set_value("audio/music_track", TRACK_IDS[selected]))
	row.add_child(option)
	return row


func _volume_row(label_text: String, key: String) -> HBoxContainer:
	var row := UiTheme.hbox(10)
	row.custom_minimum_size.y = 44
	var label := UiTheme.label(Loc.t(label_text), 16)
	label.custom_minimum_size.x = 145
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = clampf(float(Settings.get_value(key)), 0.0, 1.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(220, 44)
	var percent := UiTheme.label("%d%%" % roundi(slider.value * 100.0), 15, UiTheme.TEXT_DIM)
	percent.custom_minimum_size.x = 52
	slider.value_changed.connect(func(value: float) -> void:
		percent.text = "%d%%" % roundi(value * 100.0)
		Settings.set_value(key, value))
	row.add_child(slider)
	row.add_child(percent)
	return row


func _choice_row(label_text: String, key: String, ids: Array[String], labels: Array[String]) -> HBoxContainer:
	var row := UiTheme.hbox(10)
	row.custom_minimum_size.y = 44
	var label := UiTheme.label(label_text, 16)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(250, 44)
	for i in ids.size():
		option.add_item(Loc.t(labels[i]), i)
	var selected := ids.find(str(Settings.get_value(key)))
	option.select(selected if selected >= 0 else 0)
	option.item_selected.connect(func(index: int) -> void: Settings.set_value(key, ids[index]))
	row.add_child(option)
	return row


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		queue_free()
		get_viewport().set_input_as_handled()
