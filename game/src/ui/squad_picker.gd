class_name SquadPicker
extends PopupPanel

var g: Game
var hud: Hud
var target_squad_id := -1
var rows: VBoxContainer

func setup(game: Game, h: Hud) -> void:
	g = game
	hud = h
	name = "SquadPicker"
	position = Vector2(180, 180)
	size = Vector2(430, 420)
	var outer := UiTheme.vbox(6)
	var frame := UiTheme.panel()
	var frame_style: StyleBoxFlat = UiTheme.panel_box()
	frame_style.bg_color.a = 0.98
	frame.add_theme_stylebox_override("panel", frame_style)
	frame.add_child(outer)
	add_child(frame)
	var head := UiTheme.hbox(8)
	head.add_child(UiTheme.title(Loc.t("Add squad members"), 19))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var close := UiTheme.button("", "ui_close", Loc.t("Close"))
	close.custom_minimum_size = Vector2(44, 44)
	close.pressed.connect(hide)
	head.add_child(close)
	outer.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 350)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	rows = UiTheme.vbox(4)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("cancel"):
		return
	if g.input_ctl.mode != "":
		g.input_ctl.set_mode("")
		get_viewport().set_input_as_handled()
		call_deferred("popup_centered", Vector2i(440, 460))
	else:
		hide()
		get_viewport().set_input_as_handled()


func open_for(squad_id: int) -> void:
	target_squad_id = squad_id
	_rebuild()
	popup_centered(Vector2i(440, 460))

func button_for_unit(unit_id: int) -> Button:
	for row in rows.get_children():
		if int(row.get_meta("unit_id", -1)) == unit_id:
			return row.get_child(2) as Button
	return null


func _rebuild() -> void:
	for child in rows.get_children():
		child.queue_free()
	var squad := g.world.get_squad(target_squad_id)
	if squad == null:
		return
	var candidates: Array[Unit] = []
	for unit: Unit in g.world.unit_list:
		if unit.alive and unit.is_player() and unit.kind != "airship" and not squad.members.has(unit.id):
			candidates.append(unit)
	candidates.sort_custom(func(a: Unit, b: Unit) -> bool:
		var a_idle: bool = a.order.is_empty() and str(a.job.get("type", "idle")) == "idle"
		var b_idle: bool = b.order.is_empty() and str(b.job.get("type", "idle")) == "idle"
		if a_idle != b_idle:
			return a_idle
		return a.pos.distance_squared_to(g.world.home_pos()) < b.pos.distance_squared_to(g.world.home_pos()))
	for unit: Unit in candidates:
		var row := UiTheme.hbox(8)
		row.set_meta("unit_id", unit.id)
		row.custom_minimum_size = Vector2(0, 54)
		var portrait := TextureRect.new()
		portrait.texture = hud.portraits.get_portrait("u%d" % unit.id, unit.dna, 64)
		portrait.custom_minimum_size = Vector2(44, 44)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(portrait)
		var detail := UiTheme.vbox(1)
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		detail.add_child(UiTheme.label(unit.name, 15))
		var role := Loc.t(unit.display_role()) if unit.is_person() else Loc.t(unit.kind.capitalize())
		var current := Loc.t("No squad")
		if unit.squad_id >= 0:
			var old := g.world.get_squad(unit.squad_id)
			if old:
				current = old.name
		var activity := Loc.t(str(unit.order.get("type", unit.job.get("type", "idle"))).capitalize())
		detail.add_child(UiTheme.label("%s · Lv.%d · %s · %s" % [role, unit.char_level(), activity, current], 12, UiTheme.TEXT_DIM))
		row.add_child(detail)
		var add := UiTheme.button(Loc.t("Add"), "ui_people")
		add.custom_minimum_size = Vector2(72, 44)
		var uid := unit.id
		add.pressed.connect(func() -> void:
			var target := g.world.get_squad(target_squad_id)
			var member := g.world.get_unit(uid)
			if target and member and g.world.assign_to_squad(member, target):
				g.world.combat.enlist(member)
				g.select_squad(target.id)
				hud.squad_panel.refresh(true)
				_rebuild())
		row.add_child(add)
		rows.add_child(row)
	if candidates.is_empty():
		rows.add_child(UiTheme.label(Loc.t("No eligible units."), 15, UiTheme.TEXT_DIM))
