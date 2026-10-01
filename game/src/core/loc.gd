extends Node
## Presentation-only localization. Simulation records retain English text and stable ids.
signal language_changed

const ROOT := "res://data/i18n/"
var language := "en"
var japanese: Dictionary = {}
var english: Dictionary = {}
var definitions: Dictionary = {}

func _ready() -> void:
	# "ja.json" / "en.json" plus any "<topic>-ja.json" / "<topic>-en.json" catalog.
	var files := Array(DirAccess.get_files_at(ROOT))
	files.sort()
	for file: String in files:
		if file == "ja.json" or file.ends_with("-ja.json"):
			japanese.merge(_json(ROOT + file), true)
		elif file == "en.json" or file.ends_with("-en.json"):
			english.merge(_json(ROOT + file), true)
	_load_definitions(ROOT + "ja", "")
	var ja := Translation.new()
	ja.locale = "ja"
	for key: String in japanese:
		ja.add_message(key, str(japanese[key]))
	var en := Translation.new()
	en.locale = "en"
	for key: String in english:
		en.add_message(key, str(english[key]))
	TranslationServer.add_translation(ja)
	TranslationServer.add_translation(en)
	var chosen: String = str(Settings.get_value("general/language"))
	if not chosen in ["en", "ja"]:
		chosen = "ja" if OS.get_locale_language() == "ja" else "en"
	var override := OS.get_environment("COGWILD_LANG")
	if override in ["en", "ja"]:
		chosen = override
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--lang=") and arg.substr(7) in ["en", "ja"]:
			chosen = arg.substr(7)
	set_language(chosen, false)

func _json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

func _load_definitions(path: String, prefix: String) -> void:
	for file: String in DirAccess.get_files_at(path):
		if file.ends_with(".json"):
			var table := prefix + file.get_basename()
			var data := _json(path.path_join(file))
			definitions[table] = data
			# Static Controls can translate unformatted definition text too.
			for id: String in data:
				if data[id] is Dictionary:
					var original := DB.get_def(table, id)
					for field: String in data[id]:
						if original.get(field) is String and data[id][field] is String:
							japanese[str(original[field])] = data[id][field]
	for dir: String in DirAccess.get_directories_at(path):
		_load_definitions(path.path_join(dir), prefix + dir + "/")

func set_language(value: String, persist: bool = true) -> void:
	language = value if value in ["en", "ja"] else "en"
	TranslationServer.set_locale(language)
	if persist:
		Settings.set_value("general/language", language)
	language_changed.emit()

func t(key_or_english: String, params: Dictionary = {}) -> String:
	var text := str(TranslationServer.translate(key_or_english))
	if params.is_empty():
		return text
	var rendered: Dictionary = {}
	for key: String in params:
		var value: Variant = params[key]
		if value is Dictionary:
			value = _parameter(value)
		elif key == "resource_id" or key == "rank":
			value = t(str(value))
		elif key == "site_kind_id":
			value = t("site_kind." + str(value))
		elif key == "rank_id":
			value = t(str(value).capitalize())
		elif value is float and absf(value) < 1.0e9 and is_equal_approx(value, roundf(value)):
			# counts and levels that went through JSON or float math: "2", not "2.0"
			value = int(roundf(value))
		rendered[key] = value
	return text.format(rendered)

func message(payload: Variant) -> String:
	if payload is Dictionary:
		return t(str(payload.get("key", payload.get("text", ""))), payload.get("params", {}))
	return t(str(payload))

func _parameter(value: Dictionary) -> String:
	if language == "en" and value.has("en"):
		return str(value["en"])
	if value.has("table"):
		return def_text(str(value["table"]), str(value.get("id", "")), str(value.get("field", "name")))
	if value.has("item"):
		return item_name(value["item"])
	if value.has("base") and value.has("name"):
		return item_name(value)
	if value.has("resources"):
		var resources: Dictionary = value["resources"]
		if resources.is_empty():
			return t("resources.no_change")
		var signed := false
		for amount: Variant in resources.values():
			if int(amount) < 0:
				signed = true
		var parts := PackedStringArray()
		for resource: String in resources:
			parts.append(("%+d %s" if signed else "%d %s") % [int(resources[resource]), t(resource)])
		return ("、" if language == "ja" else ", ").join(parts)
	if value.has("list"):
		var parts := PackedStringArray()
		for entry: Variant in value["list"]:
			parts.append(_parameter(entry) if entry is Dictionary else t(str(entry)))
		return ("、" if language == "ja" else str(value.get("separator", ", "))).join(parts)
	return message(value)

func def_name(table: String, id: String) -> String:
	return def_text(table, id, "name")

func def_text(table: String, id: String, field: String) -> String:
	var original := DB.get_def(table, id)
	if language == "ja":
		var translated: Dictionary = (definitions.get(table, {}) as Dictionary).get(id, {})
		if translated.get(field) is String:
			return str(translated[field])
	return str(original.get(field, id if field == "name" else ""))

func item_name(item: Dictionary) -> String:
	if language != "ja":
		return str(item.get("name", "?"))
	if bool(item.get("unique", false)):
		return t(str(item.get("name", "?")))
	var base: Dictionary = (definitions.get("items", {}) as Dictionary).get(str(item.get("base", "")), {})
	var nouns: Array = base.get("name_nouns", [def_name("items", str(item.get("base", "")))])
	var noun := str(nouns[0])
	var material := def_name("items/materials", str(item.get("material", "scrap")))
	var quality := str(item.get("quality", "common"))
	if quality == "junk":
		return "使い古した" + material + "の" + noun
	if quality == "crude":
		return "錆びた" + noun
	var prefix := ""
	var suffix := ""
	for affix: Dictionary in item.get("affixes", []):
		var modifier := def_name("items/affixes", str(affix.get("id", "")))
		if str(affix.get("kind", "prefix")) == "prefix" and prefix == "":
			prefix = modifier
		elif str(affix.get("kind", "prefix")) == "suffix" and suffix == "":
			suffix = modifier
	return prefix + suffix + material + "の" + noun

func generated(record: Dictionary, field: String) -> String:
	if language == "en" or (bool(record.get("ai_enriched", false)) and field in ["bio", "backstory", "flavor"]):
		return str(record.get(field, ""))
	if record.has(field + "_message"):
		return message(record[field + "_message"])
	return str(record.get(field, ""))

func language_selector() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = "Language / 言語"
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	row.add_child(label)
	var option := OptionButton.new()
	option.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	option.add_item("English")
	option.add_item("日本語")
	option.select(1 if language == "ja" else 0)
	option.custom_minimum_size = Vector2(140, 36)
	option.item_selected.connect(_on_language_option_selected)
	var sync_language: Callable = _sync_language_option.bind(option)
	if not language_changed.is_connected(sync_language):
		language_changed.connect(sync_language)
	row.tree_exiting.connect(_disconnect_language_selector.bind(sync_language))
	row.add_child(option)
	return row

func _on_language_option_selected(index: int) -> void:
	set_language("ja" if index == 1 else "en")


func _sync_language_option(option: OptionButton) -> void:
	if is_instance_valid(option):
		option.select(1 if language == "ja" else 0)


func _disconnect_language_selector(sync_language: Callable) -> void:
	if language_changed.is_connected(sync_language):
		language_changed.disconnect(sync_language)
