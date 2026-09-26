class_name BuildMenu
extends PanelContainer
## Popup above the command bar. "build": buildings with costs (click to place). "gather": zone
## tools (logging, mining, forage, farm, clear) and work priorities for the autonomous settlers.

const ZONES := [["logging", "Logging", "zone_logging", "Fell trees for wood."], ["mining", "Mining", "zone_mining", "Quarry rocks, ore and aether crystals."],
	["forage", "Forage", "zone_forage", "Pick berry bushes for food."], ["farm", "Farm", "zone_farm", "Till a field: plant, grow and harvest crops."],
	["clear", "Clear zones", "zone_clear", "Remove zones in a rectangle."]]
const PRIORITIES := [["build", "Build"], ["haul", "Haul materials"], ["farm", "Farm"], ["gather", "Gather"], ["operate", "Operate workshops"]]
const LEVEL_NAMES := ["Off", "Low", "Normal", "High"]

var g: Game
var tab := ""
var _box: VBoxContainer
var _cost_labels: Array = []  # [label, cost]


func setup(game: Game) -> void:
	g = game
	name = "BuildMenu"
	add_theme_stylebox_override("panel", UiTheme.panel_box())
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -420
	offset_right = 380
	offset_bottom = -126
	offset_top = -126
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	_box = UiTheme.vbox(6)
	add_child(_box)
	visible = false


func toggle(t: String) -> void:
	if visible and tab == t:
		visible = false
		return
	tab = t
	_rebuild()
	visible = true


func _rebuild() -> void:
	for c in _box.get_children():
		c.queue_free()
	_cost_labels.clear()
	if tab == "build":
		_box.add_child(UiTheme.title("Build", 22))
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		_box.add_child(grid)
		for d: Dictionary in DB.entries("buildings"):
			if not bool(d.get("buildable", true)):
				continue
			var id := str(d["id"])
			var b := Button.new()
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(250, 64)
			b.tooltip_text = "%s\n%s" % [d.get("name", id), d.get("description", "")]
			var h := UiTheme.hbox(6)
			h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			h.offset_left = 6
			b.add_child(h)
			h.add_child(UiTheme.icon("bld_" + id, 40))
			var v := UiTheme.vbox(0)
			v.add_child(UiTheme.label(str(d.get("name", id)), 15, UiTheme.TEXT, UiTheme.bold_font))
			var cl := UiTheme.label(_cost(d.get("cost", {})), 13, UiTheme.TEXT_DIM)
			v.add_child(cl)
			_cost_labels.append([cl, d.get("cost", {})])
			h.add_child(v)
			b.pressed.connect(func() -> void:
				visible = false
				g.input_ctl.set_mode("build:" + id))
			grid.add_child(b)
		_box.add_child(UiTheme.label("Settlers haul the materials and build on their own. Walls: drag a line.", 13, UiTheme.TEXT_DIM))
	else:
		_box.add_child(UiTheme.title("Gather & work", 22))
		var zones := UiTheme.hbox(6)
		_box.add_child(zones)
		for z: Array in ZONES:
			var b := UiTheme.button(str(z[1]), str(z[2]), str(z[3]))
			b.custom_minimum_size = Vector2(0, 44)
			var zid := str(z[0])
			b.pressed.connect(func() -> void:
				visible = false
				g.input_ctl.set_mode("zone:" + zid))
			zones.add_child(b)
		_box.add_child(UiTheme.label("Work priorities", 16, UiTheme.GOLD))
		for p: Array in PRIORITIES:
			var row := UiTheme.hbox(4)
			var l := UiTheme.label(str(p[1]), 15)
			l.custom_minimum_size = Vector2(170, 0)
			row.add_child(l)
			var key := str(p[0])
			for lv in 4:
				var b := UiTheme.button(LEVEL_NAMES[lv])
				b.custom_minimum_size = Vector2(84, 30)
				b.add_theme_font_size_override("font_size", 13)
				if int(g.world.priorities.get(key, 2)) == lv:
					b.add_theme_stylebox_override("normal", UiTheme.button_box("pressed"))
				var level := lv
				b.pressed.connect(func() -> void:
					g.world.priorities[key] = level
					Sfx.play(&"ui_select")
					_rebuild())
				row.add_child(b)
			_box.add_child(row)


func _cost(cost: Dictionary) -> String:
	var parts := []
	for k: String in cost:
		parts.append("%d %s" % [int(cost[k]), k])
	return ", ".join(PackedStringArray(parts))


func _process(_delta: float) -> void:
	if not visible:
		return
	for pair: Array in _cost_labels:
		(pair[0] as Label).add_theme_color_override("font_color", UiTheme.TEXT_DIM if g.world.economy.can_afford(pair[1]) else UiTheme.BAD)
