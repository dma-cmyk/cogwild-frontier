extends Control
## Title screen: new game with character creation (name, race, role, look, company banner,
## world seed) and a live 3D preview; continue / load saved games; quit.

const COLORS := [["Azure", "#3a5da8"], ["Crimson", "#a83a3a"], ["Forest", "#3f7f45"], ["Violet", "#6a4aa0"], ["Teal", "#2f8a8a"], ["Amber", "#b8862e"]]
const HAIRS := ["short", "long", "ponytail", "bun", "mohawk", "bald", "braids", "wild"]
const HAIR_COLORS := ["#2b1d14", "#5a3a22", "#8a5a2e", "#c9a45a", "#e0d2b0", "#a83a2a", "#4a4a4a", "#e8e8e8", "#3a5da8"]

var _menu: VBoxContainer
var _left: VBoxContainer
var _create: PanelContainer
var _load_box: VBoxContainer
var _name: LineEdit
var _company: LineEdit
var _seed: LineEdit
var _race := "human"
var _role := "settler"
var _gender := "female"
var _look_seed := 1
var _hair_i := -1
var _hair_col_i := -1
var _color_i := 0
var _char: Dictionary = {}
var _preview_vp: SubViewport
var _preview_node: Node3D
var _summary: RichTextLabel
var _race_buttons: Dictionary = {}
var _role_buttons: Dictionary = {}
var _color_buttons: Array = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rng.randomize()
	var bg := TextureRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.texture = load("res://assets/ui/title_keyart.jpg")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var shade := ColorRect.new()
	shade.position = Vector2.ZERO
	shade.size = Vector2(700, 1080)
	shade.color = Color(0.025, 0.035, 0.055, 0.72)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var left := UiTheme.vbox(14)
	left.position = Vector2(120, 150)
	left.custom_minimum_size = Vector2(520, 0)
	add_child(left)
	_left = left
	var t := UiTheme.title("Cogwild Frontier", 64)
	t.add_theme_color_override("font_color", UiTheme.GOLD)
	left.add_child(t)
	var sub := UiTheme.label(Loc.t("Settle a living frontier. Command your squads — or trust them and watch."), 20, UiTheme.TEXT)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(sub)
	_menu = UiTheme.vbox(10)
	_menu.custom_minimum_size = Vector2(360, 0)
	left.add_child(_menu)
	_menu.add_child(_big_button(Loc.t("New frontier"), "ui_play", _open_create))
	var latest := _latest_slot()
	if latest >= 0:
		_menu.add_child(_big_button(Loc.t("Continue"), "ui_load", func() -> void: App.load_game(latest)))
	_menu.add_child(_big_button(Loc.t("Load"), "ui_save", _toggle_load))
	_menu.add_child(_big_button(Loc.t("Quit"), "ui_close", func() -> void: get_tree().quit()))
	_load_box = UiTheme.vbox(6)
	_load_box.visible = false
	left.add_child(_load_box)
	var credit := UiTheme.label(Loc.t("A playable vertical slice · Godot %s · procedural + image-generated art") % Engine.get_version_info()["string"], 14, UiTheme.TEXT_DIM)
	credit.position = Vector2(24, 1040)
	add_child(credit)
	var language: HBoxContainer = Loc.language_selector()
	language.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	language.offset_left = -300
	language.offset_right = -24
	language.offset_top = 20
	language.offset_bottom = 62
	add_child(language)
	Loc.language_changed.connect(func() -> void: get_tree().reload_current_scene.call_deferred())
	Sfx.start_music()


func _big_button(text: String, icon: String, cb: Callable) -> Button:
	var b := UiTheme.button(text, icon)
	b.custom_minimum_size = Vector2(360, 56)
	b.add_theme_font_size_override("font_size", 22)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func() -> void:
		Sfx.play(&"ui_confirm")
		cb.call())
	return b


func _latest_slot() -> int:
	var best := -1
	var best_t := ""
	for slot in [0, 1, 2, 3]:
		var info := SaveGame.info(slot)
		if bool(info.get("exists", false)) and not bool(info.get("damaged", false)):
			var t := str(info.get("saved_at", ""))
			if t > best_t:
				best_t = t
				best = slot
	return best


func _toggle_load() -> void:
	_load_box.visible = not _load_box.visible
	for c in _load_box.get_children():
		c.queue_free()
	for slot in [0, 1, 2, 3]:
		var info := SaveGame.info(slot)
		if not bool(info.get("exists", false)):
			continue
		var s: int = slot
		var label := "%s — %s" % [Loc.t("Quick save") if slot == 0 else Loc.t("Slot %d") % slot,
			Loc.t("damaged file") if info.get("damaged", false) else Loc.t("%s, day %d, %d people") % [info.get("company", ""), int(info.get("day", 1)), int(info.get("population", 0))]]
		var b := UiTheme.button(label, "ui_load")
		b.custom_minimum_size = Vector2(360, 40)
		b.disabled = bool(info.get("damaged", false))
		b.pressed.connect(func() -> void: App.load_game(s))
		_load_box.add_child(b)
	if _load_box.get_child_count() == 0:
		_load_box.add_child(UiTheme.label(Loc.t("No saved games yet."), 16, UiTheme.TEXT_DIM))


# --- character creation --------------------------------------------------------------------

func _build_create() -> void:
	_create = UiTheme.panel()
	_create.add_theme_stylebox_override("panel", UiTheme.flat(Color(0.025, 0.035, 0.055, 0.93), 10, UiTheme.BORDER, 1))
	_create.visible = false
	add_child(_create)
	_create.position = Vector2(700, 90)
	_create.custom_minimum_size = Vector2(1120, 900)
	var h := UiTheme.hbox(18)
	_create.add_child(h)
	var form := UiTheme.vbox(8)
	form.custom_minimum_size = Vector2(640, 0)
	h.add_child(form)
	form.add_child(UiTheme.title(Loc.t("Your founder"), 28))
	var nrow := UiTheme.hbox(6)
	nrow.add_child(_field_label(Loc.t("Name")))
	_name = LineEdit.new()
	_name.custom_minimum_size = Vector2(330, 38)
	_name.max_length = 28
	_name.text_changed.connect(func(_t: String) -> void: _refresh_summary())
	nrow.add_child(_name)
	var dice := UiTheme.button("", "ui_gear", Loc.t("Random name"))
	dice.pressed.connect(_random_name)
	nrow.add_child(dice)
	form.add_child(nrow)
	form.add_child(_field_label(Loc.t("Race")))
	var rrow := UiTheme.hbox(6)
	for r: Dictionary in DB.entries("races"):
		if not bool(r.get("playable", true)):
			continue
		var id := str(r["id"])
		var b := UiTheme.button(Loc.def_name("races", id))
		b.custom_minimum_size = Vector2(150, 38)
		b.tooltip_text = Loc.def_text("races", id, "description")
		b.pressed.connect(func() -> void:
			_race = id
			_regenerate(true))
		rrow.add_child(b)
		_race_buttons[id] = b
	form.add_child(rrow)
	form.add_child(_field_label(Loc.t("Role — a starting point, not a class")))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for r: Dictionary in DB.entries("roles"):
		if not bool(r.get("playable", false)):
			continue
		var id := str(r["id"])
		var b := UiTheme.button(Loc.def_name("roles", id), str(r.get("class_icon", "")))
		b.custom_minimum_size = Vector2(152, 40)
		b.tooltip_text = Loc.def_text("roles", id, "description")
		b.pressed.connect(func() -> void:
			_role = id
			_regenerate(true))
		grid.add_child(b)
		_role_buttons[id] = b
	form.add_child(grid)
	form.add_child(_field_label(Loc.t("Look")))
	var lrow := UiTheme.hbox(6)
	for spec: Array in [["Randomize", func() -> void:
			_look_seed = _rng.randi()
			_hair_i = -1
			_hair_col_i = -1
			_regenerate(false)],
			["Hair style", func() -> void:
				_hair_i = (_hair_i + 1) % HAIRS.size()
				_apply_look()],
			["Hair colour", func() -> void:
				_hair_col_i = (_hair_col_i + 1) % HAIR_COLORS.size()
				_apply_look()],
			["Gender", func() -> void:
				_gender = {"female": "male", "male": "nonbinary", "nonbinary": "female"}[_gender]
				_regenerate(false)]]:
		var b := UiTheme.button(Loc.t(str(spec[0])))
		b.custom_minimum_size = Vector2(150, 38)
		b.pressed.connect(spec[1])
		lrow.add_child(b)
	form.add_child(lrow)
	form.add_child(_field_label(Loc.t("Company & banner")))
	var crow := UiTheme.hbox(6)
	_company = LineEdit.new()
	_company.custom_minimum_size = Vector2(300, 38)
	_company.max_length = 26
	_company.text = Loc.t("Frontier Company")
	crow.add_child(_company)
	for i in COLORS.size():
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(38, 38)
		sw.focus_mode = Control.FOCUS_NONE
		sw.tooltip_text = Loc.t(str(COLORS[i][0]))
		sw.add_theme_stylebox_override("normal", UiTheme.flat(Color(str(COLORS[i][1])), 6, UiTheme.BORDER_DIM, 2))
		sw.add_theme_stylebox_override("hover", UiTheme.flat(Color(str(COLORS[i][1])).lightened(0.2), 6, UiTheme.BORDER, 2))
		var idx := i
		sw.pressed.connect(func() -> void:
			_color_i = idx
			_regenerate(false))
		crow.add_child(sw)
		_color_buttons.append(sw)
	form.add_child(crow)
	form.add_child(_field_label(Loc.t("World seed — the same seed always makes the same world")))
	var srow := UiTheme.hbox(6)
	_seed = LineEdit.new()
	_seed.custom_minimum_size = Vector2(220, 38)
	_seed.text = str(_rng.randi_range(1, 999999))
	srow.add_child(_seed)
	var sd := UiTheme.button(Loc.t("New seed"), "ui_gear")
	sd.pressed.connect(func() -> void: _seed.text = str(_rng.randi_range(1, 999999)))
	srow.add_child(sd)
	form.add_child(srow)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	form.add_child(spacer)
	var brow := UiTheme.hbox(10)
	var back := UiTheme.button(Loc.t("Back"), "ui_close")
	back.custom_minimum_size = Vector2(160, 50)
	back.pressed.connect(func() -> void:
		_create.visible = false
		_menu.visible = true
		_left.visible = true)
	brow.add_child(back)
	var start := UiTheme.button(Loc.t("Found the settlement"), "ui_play")
	start.custom_minimum_size = Vector2(320, 50)
	start.add_theme_font_size_override("font_size", 20)
	start.pressed.connect(_start)
	brow.add_child(start)
	form.add_child(brow)
	# preview
	var right := UiTheme.vbox(8)
	right.custom_minimum_size = Vector2(420, 0)
	h.add_child(right)
	var svc := SubViewportContainer.new()
	svc.custom_minimum_size = Vector2(420, 420)
	svc.stretch = true
	right.add_child(svc)
	_preview_vp = SubViewport.new()
	_preview_vp.own_world_3d = true
	_preview_vp.transparent_bg = true
	_preview_vp.msaa_3d = Viewport.MSAA_2X
	svc.add_child(_preview_vp)
	var sun := LookDev.make_sun()
	sun.shadow_enabled = false
	_preview_vp.add_child(sun)
	var env := WorldEnvironment.new()
	var e := LookDev.make_environment()
	e.background_mode = Environment.BG_CLEAR_COLOR
	env.environment = e
	_preview_vp.add_child(env)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.9
	cam.position = Vector3(2.2, 1.9, 2.6)
	cam.look_at_from_position(cam.position, Vector3(0, 0.62, 0))
	_preview_vp.add_child(cam)
	var ground := MeshInstance3D.new()
	var k := MeshKit.new()
	k.cylinder(Vector3(0, -0.12, 0), 0.12, 0.75, Color("#6f9a52"), 14, Color("#79ad4f"))
	ground.mesh = k.build()
	ground.material_override = MeshKit.preview_material()
	_preview_vp.add_child(ground)
	_summary = RichTextLabel.new()
	_summary.bbcode_enabled = true
	_summary.fit_content = true
	_summary.custom_minimum_size = Vector2(420, 300)
	_summary.add_theme_font_size_override("normal_font_size", 16)
	_summary.add_theme_color_override("default_color", UiTheme.TEXT)
	right.add_child(_summary)


func _field_label(t: String) -> Label:
	return UiTheme.label(t, 16, UiTheme.GOLD, UiTheme.bold_font)


func _open_create() -> void:
	if _create == null:
		_build_create()
	_menu.visible = false
	_left.visible = false
	_load_box.visible = false
	_create.visible = true
	_look_seed = _rng.randi()
	var races := DB.ids("races")
	_race = str(races[_rng.randi_range(0, races.size() - 1)]) if not races.is_empty() else "human"
	_regenerate(true)
	_random_name()


func _random_name() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var n := NameGen.person(rng, _race, _gender if _gender != "nonbinary" else "neutral")
	_name.text = str(n.get("full", "Founder"))
	_refresh_summary()


## Rebuilds the founder record. keep_look=false re-rolls stats but keeps the look seed.
func _regenerate(_new_stats: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_race, _role, _gender, _look_seed])
	_char = NpcGen.generate(rng, {"race": _race, "role": _role, "gender": _gender, "talent": "skilled"})
	_apply_look()
	for id: String in _race_buttons:
		(_race_buttons[id] as Button).add_theme_stylebox_override("normal", UiTheme.button_box("pressed" if id == _race else "normal"))
	for id: String in _role_buttons:
		(_role_buttons[id] as Button).add_theme_stylebox_override("normal", UiTheme.button_box("pressed" if id == _role else "normal"))


func _apply_look() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _look_seed
	var color := Color(str(COLORS[_color_i][1]))
	var dna := AppearanceGen.character(rng, _race, _role, "frontier", color, _gender)
	if _hair_i >= 0:
		dna["hair"] = HAIRS[_hair_i]
	if _hair_col_i >= 0:
		dna["hair_color"] = HAIR_COLORS[_hair_col_i]
	_char["appearance"] = dna
	# show the equipped starting weapon/armour on the preview
	var u := Unit.new()
	u.character = _char
	u.dna = dna
	u.labor = "soldier"
	CharacterFactory.sync_dna(u)
	_show_preview(u.dna)
	_refresh_summary()


func _show_preview(dna: Dictionary) -> void:
	if _preview_node:
		_preview_node.queue_free()
	_preview_node = UnitVisualFactory.create(dna)
	_preview_vp.add_child(_preview_node)
	MeshKit.apply_preview_material(_preview_node)


func _process(delta: float) -> void:
	if _preview_node and _create.visible:
		_preview_node.rotation.y += delta * 0.6


func _refresh_summary() -> void:
	if _char.is_empty():
		return
	var race := DB.get_def("races", _race)
	var role := DB.get_def("roles", _role)
	var skills: Dictionary = _char.get("skills", {})
	var ids := skills.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(skills[a]) > int(skills[b]))
	var top := []
	for i in mini(3, ids.size()):
		top.append("%s %d" % [Loc.def_name("skills", str(ids[i])), int(skills[ids[i]])])
	var traits := []
	for tid: String in _char.get("traits", []):
		traits.append(Loc.def_name("traits", tid))
	var items := []
	for slot: String in ["weapon", "armor", "gadget"]:
		var it: Variant = (_char.get("equipment", {}) as Dictionary).get(slot)
		if it is Dictionary:
			items.append(Loc.item_name(it))
	_summary.text = Loc.t("[font_size=22][b]%s[/b][/font_size]\n%s %s\n[color=#a9a18c]%s[/color]\n\n[color=#e6c268]Strengths:[/color] %s\n[color=#e6c268]Traits:[/color] %s\n[color=#e6c268]Gear:[/color] %s\n\n[i]%s[/i]") % [
		_name.text if _name else "", Loc.def_name("races", _race), Loc.def_name("roles", _role), Loc.def_text("roles", _role, "description"),
		", ".join(PackedStringArray(top)), ", ".join(PackedStringArray(traits)), ", ".join(PackedStringArray(items)), Loc.generated(_char, "quirk")]


func _start() -> void:
	var nm := _name.text.strip_edges()
	if nm == "":
		nm = "Founder"
	_char["name"] = nm
	var parts := nm.split(" ", false)
	_char["given"] = parts[0] if parts.size() > 0 else nm
	_char["family"] = " ".join(parts.slice(1)) if parts.size() > 1 else ""
	_char["nickname"] = ""
	var seed := int(_seed.text) if _seed.text.is_valid_int() else absi(_seed.text.hash())
	seed = clampi(seed, 1, 2147483646)
	App.start_new_game(seed, _char, _company.text.strip_edges(), Color(str(COLORS[_color_i][1])))
