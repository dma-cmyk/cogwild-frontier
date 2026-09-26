extends Node
## Data registry (autoload "DB"). Loads every JSON file under res://data/<category>/ at startup.
##
## Accepted file shapes:
##   - Array of objects with "id"                      -> merged into table "<category>"
##   - {"table": "<name>", "entries": [{"id": ...}]}   -> merged into table "<category>/<name>"
##   - any other Object                                -> raw document "<category>/<file stem>"
## Files load in sorted order and later entries override earlier ones with the same id, so new
## content packs can be added by dropping JSON files into a folder (no code changes).

const DATA_ROOT := "res://data"

var _tables: Dictionary = {}  # table name -> {id: Dictionary}
var _order: Dictionary = {}  # table name -> Array of ids in load order
var _raw: Dictionary = {}  # "<category>/<stem>" -> Variant
var load_errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	reload()


func reload() -> void:
	_tables.clear()
	_order.clear()
	_raw.clear()
	load_errors.clear()
	var categories := Array(DirAccess.get_directories_at(DATA_ROOT))
	categories.sort()
	for category: String in categories:
		var dir := DATA_ROOT.path_join(category)
		var files := Array(DirAccess.get_files_at(dir))
		files.sort()
		for file_name: String in files:
			if file_name.get_extension() == "json":
				_load_file(category, dir.path_join(file_name))


func _load_file(category: String, path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		var msg := "DB: %s:%d: %s" % [path, json.get_error_line(), json.get_error_message()]
		load_errors.append(msg)
		push_error(msg)
		return
	var doc: Variant = json.data
	if doc is Array:
		_merge(category, doc, path)
	elif doc is Dictionary and doc.has("table") and doc.get("entries") is Array:
		_merge("%s/%s" % [category, doc["table"]], doc["entries"], path)
	else:
		_raw["%s/%s" % [category, path.get_file().get_basename()]] = doc


func _merge(table: String, entries: Array, path: String) -> void:
	var dict: Dictionary = _tables.get_or_add(table, {})
	var order: Array = _order.get_or_add(table, [])
	for entry: Variant in entries:
		if not (entry is Dictionary) or not entry.has("id"):
			var msg := "DB: %s: entry without id in table '%s'" % [path, table]
			load_errors.append(msg)
			push_error(msg)
			continue
		var id := str(entry["id"])
		if not dict.has(id):
			order.append(id)
		dict[id] = entry


## Definition by id, or an empty Dictionary when missing.
func get_def(table: String, id: String) -> Dictionary:
	var dict: Dictionary = _tables.get(table, {})
	return dict.get(id, {})


func has_def(table: String, id: String) -> bool:
	return _tables.has(table) and (_tables[table] as Dictionary).has(id)


## Ids of a table in load order.
func ids(table: String) -> Array:
	return (_order.get(table, []) as Array).duplicate()


## Definitions of a table in load order.
func entries(table: String) -> Array:
	var dict: Dictionary = _tables.get(table, {})
	var out: Array = []
	for id: String in _order.get(table, []):
		out.append(dict[id])
	return out


## Raw JSON document "<category>/<stem>" (for files that are not id tables), or null.
func raw(key: String) -> Variant:
	return _raw.get(key)


func table_names() -> Array:
	return _tables.keys()
