extends Node
## App-wide state (autoload "App"): input actions, the pending new-game / load request handed from
## the title screen to the game scene, and user settings.

const GAME_SCENE := "res://scenes/game.tscn"
const TITLE_SCENE := "res://scenes/main.tscn"

## Set by the title screen before switching to the game scene.
## {"mode": "new", "seed": int, "player": Dictionary(character)} or {"mode": "load", "slot": int}
var pending: Dictionary = {}

## Keyboard actions registered at startup so they live in one place (see docs/controls in README).
const ACTIONS := {
	"cam_left": [KEY_A, KEY_LEFT],
	"cam_right": [KEY_D, KEY_RIGHT],
	"cam_up": [KEY_W, KEY_UP],
	"cam_down": [KEY_S, KEY_DOWN],
	"cam_zoom_in": [KEY_EQUAL, KEY_KP_ADD, KEY_PAGEUP],
	"cam_zoom_out": [KEY_MINUS, KEY_KP_SUBTRACT, KEY_PAGEDOWN],
	"toggle_pause": [KEY_SPACE],
	"speed_up": [KEY_BRACKETRIGHT, KEY_PERIOD],
	"speed_down": [KEY_BRACKETLEFT, KEY_COMMA],
	"squad_1": [KEY_1],
	"squad_2": [KEY_2],
	"squad_3": [KEY_3],
	"squad_4": [KEY_4],
	"squad_5": [KEY_5],
	"squad_6": [KEY_6],
	"squad_7": [KEY_7],
	"squad_8": [KEY_8],
	"squad_9": [KEY_9],
	"squad_cycle": [KEY_TAB],
	"cmd_move": [KEY_M],
	"cmd_attack": [KEY_F],
	"cmd_defend": [KEY_H],
	"cmd_explore": [KEY_X],
	"cmd_build": [KEY_B],
	"cmd_gather": [KEY_G],
	"cmd_patrol": [KEY_P],
	"cmd_auto": [KEY_U],
	"cmd_retreat": [KEY_R],
	"cmd_escort": [KEY_Y],
	"cmd_stop": [KEY_L],
	"ability_1": [KEY_Z],
	"ability_2": [KEY_C],
	"ability_3": [KEY_V],
	"ability_4": [KEY_T],
	"ability_5": [KEY_N],
	"ability_6": [KEY_J],
	"ability_7": [KEY_K],
	"ability_8": [KEY_O],
	"ability_9": [KEY_I],
	"focus_home": [KEY_HOME],
	"quicksave": [KEY_F5],
	"quickload": [KEY_F9],
	"toggle_help": [KEY_F1],
	"cancel": [KEY_ESCAPE],
}


func _enter_tree() -> void:
	_register_actions()

func _ready() -> void:
	get_tree().root.size_changed.connect(_apply_ui_scale)
	Settings.changed.connect(func(key: String, _value: Variant) -> void:
		if key == "interface/ui_scale":
			_apply_ui_scale())
	_apply_ui_scale()


## UI scale (root content_scale_factor on top of the 1920x1080 canvas_items stretch). "auto" and
## "normal" aim at ~0.75 CSS px per UI pixel (16 px text ≈ 12 CSS px, so phones get a readable,
## touch-sized UI) while keeping at least 540 UI pixels on the short side so every layout fits;
## never below 1.0 (desktop windows keep the designed size). "small" / "large" scale that by 0.85 / 1.2.
func _apply_ui_scale() -> void:
	var win := Vector2(DisplayServer.window_get_size())
	if win.x < 1.0 or win.y < 1.0:
		return
	var base := Vector2(float(ProjectSettings.get_setting("display/window/size/viewport_width")), float(ProjectSettings.get_setting("display/window/size/viewport_height")))
	var stretch := minf(win.x / base.x, win.y / base.y)
	var css_per_px := maxf(1.0, DisplayServer.screen_get_scale()) / stretch
	var short_side := minf(win.x, win.y) / stretch
	var scale := maxf(1.0, minf(0.75 * css_per_px, short_side / 540.0))
	match str(Settings.get_value("interface/ui_scale")):
		"small":
			scale *= 0.85
		"large":
			scale = minf(scale * 1.2, maxf(1.2, short_side / 440.0))
	get_tree().root.content_scale_factor = scale


func is_touch() -> bool:
	return DisplayServer.is_touchscreen_available()


func is_mobile_web() -> bool:
	return OS.has_feature("web_android") or OS.has_feature("web_ios")


## Size of the UI canvas in UI pixels (after the stretch and the UI scale).
func screen_size() -> Vector2:
	return get_tree().root.get_visible_rect().size


func _register_actions() -> void:
	for action: String in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		if OS.has_feature("web") and action in ["quicksave", "quickload"]:
			var ev := InputEventKey.new()
			ev.physical_keycode = KEY_S if action == "quicksave" else KEY_L
			ev.ctrl_pressed = true
			InputMap.action_add_event(action, ev)
		else:
			for key: int in ACTIONS[action]:
				var ev := InputEventKey.new()
				ev.physical_keycode = key as Key
				InputMap.action_add_event(action, ev)


## Releases static mesh/material/texture caches so nothing outlives the scene tree at exit.
func _exit_tree() -> void:
	Caches.clear_all()


func start_new_game(seed: int, player: Dictionary, company: String = "", color: Color = Color("#3a5da8")) -> void:
	pending = {"mode": "new", "seed": seed, "player": player, "company": company, "color": color}
	get_tree().change_scene_to_file(GAME_SCENE)


func load_game(slot: int) -> void:
	pending = {"mode": "load", "slot": slot}
	get_tree().change_scene_to_file(GAME_SCENE)


func to_title() -> void:
	pending = {}
	get_tree().change_scene_to_file(TITLE_SCENE)
