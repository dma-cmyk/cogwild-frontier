class_name UiTheme
extends RefCounted
## Shared look of the HUD (dark navy panels with thin gold borders, cream text, serif titles) and
## small widget helpers so every panel is built the same way.

const PANEL := Color(0.075, 0.1, 0.16, 0.9)
const PANEL_LIGHT := Color(0.12, 0.16, 0.24, 0.95)
const BORDER := Color("#b8944a")
const BORDER_DIM := Color(0.45, 0.4, 0.3, 0.8)
const TEXT := Color("#efe4c8")
const TEXT_DIM := Color("#a9a18c")
const ACCENT := Color("#5fd0ff")
const GOOD := Color("#7ddc6e")
const BAD := Color("#ff7a66")
const GOLD := Color("#e6c268")

static var _theme: Theme
static var title_font: Font
static var body_font: Font
static var bold_font: Font


static func clear_cache() -> void:
	_theme = null
	title_font = null
	body_font = null
	bold_font = null


static func theme() -> Theme:
	if _theme != null:
		return _theme
	title_font = load("res://assets/fonts/NotoSerif-Bold.ttf")
	body_font = load("res://assets/fonts/NotoSans-Regular.ttf")
	bold_font = load("res://assets/fonts/NotoSans-SemiBold.ttf")
	var system := SystemFont.new()
	system.font_names = PackedStringArray(["Noto Sans CJK JP"])
	var regular: Font = load("res://assets/fonts/CogwildCJK-Regular.otf")
	regular.fallbacks = [system]
	# Replace the 4 MB bold face with synthetic weight; glyph stroke weight may differ slightly
	# and missing CJK glyphs fall through to the system font (including typed rare kanji).
	var bold := FontVariation.new()
	bold.base_font = regular
	bold.variation_embolden = 0.45
	bold.fallbacks = [system]
	body_font.fallbacks = [regular]
	bold_font.fallbacks = [bold]
	title_font.fallbacks = [bold]
	var t := Theme.new()
	t.default_font = body_font
	t.default_font_size = 18
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.55))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_stylebox("panel", "PanelContainer", panel_box())
	t.set_stylebox("panel", "Panel", panel_box())
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.set_stylebox(state, "Button", button_box(state))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", TEXT_DIM * Color(1, 1, 1, 0.6))
	t.set_color("icon_normal_color", "Button", Color.WHITE)
	t.set_color("icon_disabled_color", "Button", Color(1, 1, 1, 0.35))
	t.set_font("font", "Button", bold_font)
	t.set_font_size("font_size", "Button", 16)
	t.set_stylebox("fill", "ProgressBar", flat(GOOD, 3))
	t.set_stylebox("background", "ProgressBar", flat(Color(0.05, 0.06, 0.09, 0.9), 3))
	t.set_stylebox("panel", "TooltipPanel", panel_box())
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_stylebox("slider", "HSlider", flat(Color(0.2, 0.22, 0.3), 3))
	t.set_stylebox("grabber_area", "HSlider", flat(BORDER, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", flat(GOLD, 3))
	t.set_stylebox("normal", "LineEdit", flat(Color(0.05, 0.07, 0.11, 0.95), 4, BORDER_DIM))
	t.set_stylebox("focus", "LineEdit", flat(Color(0.05, 0.07, 0.11, 0.95), 4, BORDER))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_stylebox("tab_selected", "TabBar", button_box("pressed"))
	t.set_stylebox("tab_unselected", "TabBar", button_box("normal"))
	t.set_stylebox("tab_hovered", "TabBar", button_box("hover"))
	_theme = t
	return t


static func flat(c: Color, radius: int = 6, border: Color = Color.TRANSPARENT, bw: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(radius)
	if border.a > 0.0:
		s.border_color = border
		s.set_border_width_all(maxi(1, bw if bw > 0 else 2))
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s


static func panel_box() -> StyleBoxFlat:
	var s := flat(PANEL, 8, BORDER, 2)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 6
	return s


static func button_box(state: String) -> StyleBoxFlat:
	var bg := Color(0.12, 0.16, 0.25, 0.95)
	var br := BORDER_DIM
	match state:
		"hover":
			bg = Color(0.17, 0.22, 0.34, 0.98)
			br = BORDER
		"pressed":
			bg = Color(0.09, 0.2, 0.3, 1.0)
			br = ACCENT
		"disabled":
			bg = Color(0.1, 0.11, 0.15, 0.8)
			br = Color(0.3, 0.3, 0.3, 0.6)
		"focus":
			var e := flat(Color(0, 0, 0, 0), 6, Color(1, 1, 1, 0.2), 1)
			return e
	return flat(bg, 6, br, 2)


static func label(text: String, size: int = 18, color: Color = TEXT, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font:
		l.add_theme_font_override("font", font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func title(text: String, size: int = 26) -> Label:
	theme()
	return label(text, size, TEXT, title_font)


static func icon(id: String, size: int = 28) -> TextureRect:
	var r := TextureRect.new()
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(size, size)
	r.texture = Icons.get_icon(id)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func button(text: String, icon_id: String = "", tooltip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	if icon_id != "":
		b.icon = Icons.get_icon(icon_id)
		b.expand_icon = true
		# Expanded icons do not contribute to the Button's minimum size.
		if text.is_empty():
			b.custom_minimum_size = Vector2(36, 36)
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	return b


static func bar(color: Color, height: int = 10) -> ProgressBar:
	var p := ProgressBar.new()
	p.show_percentage = false
	p.custom_minimum_size = Vector2(0, height)
	p.max_value = 1.0
	p.step = 0.001
	p.add_theme_stylebox_override("fill", flat(color, 3))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func hbox(sep: int = 6) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


static func vbox(sep: int = 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


static func panel() -> PanelContainer:
	theme()
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_box())
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


static func fmt(n: float) -> String:
	var a := absf(n)
	if a >= 10000.0:
		return "%.1fk" % (n / 1000.0)
	if a >= 1000.0:
		var s := str(int(n))
		return s.substr(0, s.length() - 3) + "," + s.substr(s.length() - 3)
	return str(int(round(n)))
