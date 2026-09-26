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
	"cam_rotate_left": [KEY_Q],
	"cam_rotate_right": [KEY_E],
	"cam_zoom_in": [KEY_EQUAL, KEY_KP_ADD, KEY_PAGEUP],
	"cam_zoom_out": [KEY_MINUS, KEY_KP_SUBTRACT, KEY_PAGEDOWN],
	"toggle_pause": [KEY_SPACE],
	"speed_up": [KEY_BRACKETRIGHT, KEY_PERIOD],
	"speed_down": [KEY_BRACKETLEFT, KEY_COMMA],
	"squad_1": [KEY_1],
	"squad_2": [KEY_2],
	"squad_3": [KEY_3],
	"squad_4": [KEY_4],
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
	"focus_home": [KEY_HOME],
	"quicksave": [KEY_F5],
	"quickload": [KEY_F9],
	"toggle_help": [KEY_F1],
	"cancel": [KEY_ESCAPE],
}


func _enter_tree() -> void:
	_register_actions()


func _register_actions() -> void:
	for action: String in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
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
