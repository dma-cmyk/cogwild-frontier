class_name SpeechBubbles
extends Control
## Lightweight screen-space presentation layer, inserted before HUD panels.

class BubbleCard:
	extends Control
	var text := ""
	var alpha := 0.0
	var tail_offset := 0.0
	var combat := false
	var _style: StyleBoxFlat

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_style = StyleBoxFlat.new()
		_style.bg_color = Color("#f2e5c8")
		_style.border_color = Color("#8d7042")
		_style.set_border_width_all(2)
		_style.set_corner_radius_all(9)
		_style.content_margin_left = 10
		_style.content_margin_right = 10
		_style.content_margin_top = 6
		_style.content_margin_bottom = 6

	func _draw() -> void:
		var panel := Rect2(Vector2.ZERO, size - Vector2(0, 7))
		_style.bg_color = Color("#f2e5c8", alpha)
		_style.border_color = Color("#8d7042", alpha)
		draw_style_box(_style, panel)
		var center := clampf(tail_offset, 12.0, size.x - 12.0)
		var points := PackedVector2Array([Vector2(center - 7, panel.end.y - 1), Vector2(center + 7, panel.end.y - 1), Vector2(center, size.y)])
		draw_colored_polygon(points, Color("#f2e5c8", alpha))
		draw_polyline(PackedVector2Array([points[0], points[2], points[1]]), Color("#8d7042", alpha), 2.0)
		var font := UiTheme.body_font
		var font_size := 16
		var color := Color("#302719", alpha)
		var lines := text.split("\n")
		var y := 21.0
		for line: String in lines:
			draw_string(font, Vector2(10, y), line, HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, font_size, color)
			y += 19.0

var game: Game
var director: Chatter
var _bubbles: Array[Dictionary] = []
var _spacing := 8.0

func setup(g: Game) -> void:
	game = g
	name = "SpeechBubbles"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	director = Chatter.new()
	director.name = "Chatter"
	add_child(director)
	director.setup(game)
	director.spoke.connect(_on_spoke)

func _on_spoke(unit: Unit, text: String, combat: bool) -> void:
	# in a melee several downed or hit fighters often shout the same line at once: one bubble reads
	# better than an identical stack
	for b: Dictionary in _bubbles:
		var other := game.world.get_unit(int(b["unit_id"]))
		if (b["card"] as BubbleCard).text == _wrap_text(text, 220) and other != null and other.pos.distance_to(unit.pos) < 8.0:
			return
	var card := BubbleCard.new()
	card.text = _wrap_text(text, 220)
	card.combat = combat
	card.tail_offset = 42.0
	var lines := card.text.split("\n").size()
	card.custom_minimum_size = Vector2(230, float(lines) * 19.0 + 23.0)
	card.size = card.custom_minimum_size
	add_child(card)
	var duration := clampf(2.8 + float(text.length()) * 0.035, 3.0, 4.5)
	_bubbles.append({"card": card, "unit_id": unit.id, "age": 0.0, "duration": duration, "fade": 0.0})
	while _bubbles.size() > 5:
		var oldest: Dictionary = _bubbles.pop_front()
		(oldest["card"] as Control).queue_free()

func _process(delta: float) -> void:
	if game == null:
		return
	var scale := float(game.speed)
	var screen := get_viewport_rect().size
	var placed: Array[Rect2] = []
	for i in range(_bubbles.size() - 1, -1, -1):
		var entry: Dictionary = _bubbles[i]
		var card := entry["card"] as BubbleCard
		var unit := game.world.get_unit(int(entry["unit_id"]))
		if unit == null or not unit.alive or unit.state == Unit.State.DEAD or unit.hidden or not unit.visible:
			card.queue_free()
			_bubbles.remove_at(i)
			continue
		if scale > 0.0:
			entry["age"] = float(entry["age"]) + delta * scale
		var age := float(entry["age"])
		var fade_in := minf(1.0, age / 0.18)
		var fade_out := clampf((float(entry["duration"]) - age) / 0.45, 0.0, 1.0)
		card.alpha = minf(fade_in, fade_out)
		card.visible = false
		if age >= float(entry["duration"]):
			card.queue_free()
			_bubbles.remove_at(i)
			continue
		var view: UnitView = game.view.unit_views.get(unit.id)
		if view == null or not view.visible:
			continue
		var head := view.global_position + Vector3(0, view._bar_h + 0.18, 0)
		var point := game.rig.world_to_screen(head)
		if not game.rig.cam.is_position_behind(head) and point.x > -20 and point.x < screen.x + 20 and point.y > 72 and point.y < screen.y - 84:
			var pos := Vector2(clampf(point.x - card.size.x * 0.5, 4, screen.x - card.size.x - 4), point.y - card.size.y - 8)
			var rect := Rect2(pos, card.size)
			for prior: Rect2 in placed:
				if rect.intersects(prior):
					pos.y = prior.position.y - card.size.y - _spacing
					rect.position = pos
			if game.hud.info_panel.visible and rect.end.x > screen.x - 310.0:
				card.queue_redraw()
				continue
			card.position = pos
			card.tail_offset = clampf(point.x - pos.x, 12, card.size.x - 12)
			card.visible = true
			placed.append(rect)
		card.queue_redraw()

func _wrap_text(text: String, max_width: float) -> String:
	var font := UiTheme.body_font
	var output := ""
	var line := ""
	if not text.contains(" "):
		for character: String in text.split("", false):
			var candidate := line + character
			if not line.is_empty() and font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x > max_width:
				output += ("\n" if not output.is_empty() else "") + line
				line = character
			else:
				line = candidate
		output += ("\n" if not output.is_empty() else "") + line
		return output
	for word: String in text.split(" "):
		var candidate := word if line.is_empty() else line + " " + word
		if not line.is_empty() and font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x > max_width:
			output += ("\n" if not output.is_empty() else "") + line
			line = word
		else:
			line = candidate
	output += ("\n" if not output.is_empty() else "") + line
	return output
