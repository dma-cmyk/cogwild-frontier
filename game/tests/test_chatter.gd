extends TestCase
## Chatter presentation contract: bilingual pools and safe/cooldown-gated speakers.

func test_every_pool_line_has_japanese_and_matching_params() -> void:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/i18n/chatter-ja.json"))
	assert_true(value is Dictionary, "Japanese chatter catalog parses")
	if not value is Dictionary:
		return
	var ja: Dictionary = value
	for line: String in Chatter.all_lines():
		assert_true(ja.has(line), "missing Japanese chatter: " + line)
		if ja.has(line):
			assert_eq(_params(line), _params(str(ja[line])), "placeholder mismatch: " + line)

func test_person_pool_excludes_dead_hostile_and_robot_speakers() -> void:
	var director := Chatter.new()
	var person := Unit.new()
	person.faction = "player"
	person.kind = "character"
	person.alive = true
	person.visible = true
	assert_true(director._eligible(person), "visible player person can speak")
	person.alive = false
	assert_false(director._eligible(person), "dead person cannot speak")
	person.alive = true
	person.faction = "bandits"
	assert_false(director._eligible(person), "hostile cannot speak from player pools")
	person.faction = "player"
	person.kind = "robot"
	assert_false(director._eligible(person), "robot excluded from person pools")
	director.free()

func test_per_unit_cooldown_blocks_repeat_barks() -> void:
	var director := Chatter.new()
	assert_true(director.cooldown_ready(42), "new speaker starts ready")
	director._cooldowns[42] = 25.0
	assert_false(director.cooldown_ready(42), "speaker remains gated during cooldown")
	director._cooldowns[42] = 0.0
	assert_true(director.cooldown_ready(42), "speaker is ready after cooldown")
	director.free()

func _params(text: String) -> PackedStringArray:
	var found := PackedStringArray()
	var regex := RegEx.new()
	regex.compile("\\{[A-Za-z0-9_]+\\}")
	for hit: RegExMatch in regex.search_all(text):
		found.append(hit.get_string())
	found.sort()
	return found
