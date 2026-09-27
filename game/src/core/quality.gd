extends Node
## Resolves the saved graphics preset and exposes renderer-safe quality decisions.

signal level_changed(level: String)

var _level := "high"


func _ready() -> void:
	Settings.changed.connect(_on_setting_changed)
	_apply_level(_resolve_level())


func level() -> String:
	return _level


func shadows_enabled() -> bool:
	return _level != "low"


func prop_density() -> float:
	match _level:
		"low":
			return 0.62
		"medium":
			return 0.82
		_:
			return 1.0


func terrain_detail_enabled() -> bool:
	return _level != "low"


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "graphics/quality":
		_apply_level(_resolve_level())


func _resolve_level() -> String:
	var selected := str(Settings.get_value("graphics/quality"))
	if selected != "auto":
		return selected if selected in ["low", "medium", "high"] else "medium"
	# "high" only adds MSAA and longer shadows (about +60 % frame time in Compatibility for a
	# barely visible gain on painted cards), so it is opt-in everywhere.
	if OS.has_feature("web_android") or OS.has_feature("web_ios"):
		return "low"
	return "medium"


func _apply_level(next_level: String) -> void:
	if _level == next_level:
		return
	_level = next_level
	Engine.max_fps = 30 if _level == "low" and OS.has_feature("web") else 0
	var viewport := get_tree().root
	viewport.msaa_3d = Viewport.MSAA_2X if _level == "high" else Viewport.MSAA_DISABLED
	level_changed.emit(_level)
