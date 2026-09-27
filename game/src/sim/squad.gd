class_name Squad
extends RefCounted
## A small group of units that receives orders together. Orders can be direct (move, attack, ...)
## or delegated (explore, patrol, defend, auto) — the SquadAI carries them out.

const ORDERS := ["idle", "move", "attack", "defend", "explore", "patrol", "escort", "retreat", "auto"]
const COLORS := [Color("#4fd3ff"), Color("#ffd24f"), Color("#b98cff"), Color("#7dff8a")]

var id := 0
var name := ""
var members: Array = []  # unit ids
var order: Dictionary = {"type": "idle"}  # type + pos (Vector2) / target (int) / radius / points
var stance := "balanced"  # aggressive | balanced | cautious | hold
var retreat_threshold := 0.3  # retreat when squad HP ratio drops below this
var state := "idle"  # what the squad is doing right now (for the HUD)
var state_message: Dictionary = {"key": "sim.squad.state.idle", "params": {}}
var mem: Dictionary = {}  # AI scratch data (explore target, patrol index, ...)
var report: Array = []  # discoveries during the current expedition
var auto_abilities := true
var formation := "line"  # line | wedge | loose



func color() -> Color:
	return COLORS[id % COLORS.size()]


func to_dict() -> Dictionary:
	return {"id": id, "name": name, "members": members, "order": Unit._vec_safe(order), "stance": stance,
		"retreat_threshold": retreat_threshold, "state": state, "state_message": state_message, "mem": Unit._vec_safe(mem),
		"report": report, "formation": formation, "auto_abilities": auto_abilities}


static func from_dict(d: Dictionary) -> Squad:
	var s := Squad.new()
	s.id = int(d["id"])
	s.name = str(d["name"])
	for m: Variant in d.get("members", []):
		s.members.append(int(m))
	s.order = Unit._vec_restore(d.get("order", {"type": "idle"}))
	s.stance = str(d.get("stance", "balanced"))
	s.retreat_threshold = float(d.get("retreat_threshold", 0.3))
	s.state = str(d.get("state", "idle"))
	s.state_message = d.get("state_message", {})
	s.mem = Unit._vec_restore(d.get("mem", {}))
	s.report = d.get("report", [])
	s.formation = str(d.get("formation", "line"))
	s.auto_abilities = bool(d.get("auto_abilities", true))
	return s
