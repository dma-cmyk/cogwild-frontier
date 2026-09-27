extends Node
## Player settings (autoload "Settings"), persisted in user://settings.cfg (IndexedDB on the web).
## Keys are "section/name". Consumers read with get_value() and react to `changed`.

signal changed(key: String, value: Variant)

const PATH := "user://settings.cfg"
const DEFAULTS := {
	"general/language": "",  # "" = pick from the OS locale (Loc)
	"audio/master": 1.0,  # linear 0..1
	"audio/music": 0.7,
	"audio/sfx": 0.8,
	"audio/ambience": 0.6,
	"audio/music_track": "auto",  # "auto" (follows the situation), "shuffle", "off" or a track id
	"graphics/quality": "auto",  # "auto", "low", "medium", "high"
	"interface/ui_scale": "auto",  # "auto", "small", "normal", "large"
	"interface/speech": "all",  # speech bubbles: "all", "combat", "off"
}

var _cfg := ConfigFile.new()


func _enter_tree() -> void:
	_cfg.load(PATH)


func get_value(key: String) -> Variant:
	var parts := key.split("/", true, 1)
	return _cfg.get_value(parts[0], parts[1], DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	var parts := key.split("/", true, 1)
	if _cfg.has_section_key(parts[0], parts[1]) and _cfg.get_value(parts[0], parts[1]) == value:
		return
	_cfg.set_value(parts[0], parts[1], value)
	_cfg.save(PATH)
	changed.emit(key, value)
