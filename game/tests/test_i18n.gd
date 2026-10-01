extends TestCase
## Localization contracts: catalog placeholders, playable definitions and generated item names.

const TABLES := ["races", "roles", "traits", "skills", "items", "items/materials", "items/qualities", "items/affixes", "buildings", "robots", "airships", "units"]

func before_all() -> void:
	DB.reload()
	Loc.set_language("en", false)

func after_all() -> void:
	Loc.set_language("en", false)

func _catalog(file: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/i18n/" + file))
	return value if value is Dictionary else {}

## Every catalog Loc loads for a language: "<lang>.json" plus "<topic>-<lang>.json".
func _catalogs(lang: String) -> Dictionary:
	var merged := {}
	for file: String in DirAccess.get_files_at("res://data/i18n/"):
		if file == lang + ".json" or file.ends_with("-%s.json" % lang):
			merged.merge(_catalog(file), true)
	return merged

func _placeholders(text: String) -> PackedStringArray:
	var found := PackedStringArray()
	var regex := RegEx.new()
	regex.compile("%(?:\\+?\\d*\\.?\\d*)?[sdif]|\\{[A-Za-z0-9_]+\\}")
	for hit: RegExMatch in regex.search_all(text):
		found.append(hit.get_string())
	found.sort()
	return found

func test_catalog_placeholders_match() -> void:
	var en := _catalogs("en")
	var ja := _catalogs("ja")
	for key: String in en:
		assert_true(ja.has(key), "Japanese catalog missing " + key)
		if ja.has(key):
			assert_eq(_placeholders(str(ja[key])), _placeholders(str(en[key])), "placeholder mismatch " + key)

func test_playable_definitions_have_japanese_names() -> void:
	Loc.set_language("ja", false)
	for table: String in TABLES:
		for id: String in DB.ids(table):
			var english := str(DB.get_def(table, id).get("name", id))
			var japanese := Loc.def_name(table, id)
			assert_true(japanese != "" and japanese != english, "%s/%s lacks Japanese name" % [table, id])

func test_item_name_for_every_quality() -> void:
	Loc.set_language("ja", false)
	for quality: String in DB.ids("items/qualities"):
		var item := ItemGen.generate(_rng(7000 + quality.hash()), {"base": "spear", "level": 3, "quality": quality})
		var localized := Loc.item_name(item)
		assert_true(localized != "" and localized != str(item.get("name", "")), "quality %s item name not localized" % quality)

func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng
