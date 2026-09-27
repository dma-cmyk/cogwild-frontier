class_name Chatter
extends Node
## Presentation-only speech director. Samples the view-visible world; never mutates simulation.

signal spoke(unit: Unit, text: String, combat: bool)

const WORK_LINES := {
	"gather": ["These trees won't chop themselves.", "One more swing, then a breather.", "Good timber. We'll need every bit."],
	"mine": ["Stone's tougher than it looks.", "There's ore in this seam.", "Dust in my teeth again."],
	"haul": ["Heavy, but manageable.", "Where should I stack this?", "This path could use a cart."],
	"build": ["Measure twice, build once.", "This place is taking shape.", "Pass me another beam."],
	"farm": ["Hope the soil stays kind.", "These rows look healthy.", "Fresh food soon, please."],
	"patrol": ["All quiet on this stretch.", "Keeping an eye on the horizon.", "Nothing sneaks past me."],
	"explore": ["Wonder what's over that ridge.", "New ground, new stories.", "I'll mark the way back."],
	"trade": ["Let's make this a fair deal.", "I wonder what they brought.", "Keep the ledger handy."],
	"repair": ["A little care goes a long way.", "Back in working order soon.", "This should hold now."],
	"rest": ["My feet needed this.", "A quiet night sounds lovely.", "Wake me when the kettle's on."],
	"idle": ["It's peaceful for a change.", "Anyone know a good story?", "Could use a cup of tea."]
}
const COMBAT_LINES := ["Stay together!", "They're not getting through!", "Keep your guard up!", "That one felt close!", "I'm hit—still standing!", "I need a hand!", "They're down!", "Fall back, regroup!", "We held the line!", "You'll regret that!", "Not so brave now, are you?", "Hold fast, help is coming!", "We can do this!"]
const TOPICS := [
	["Sky's lovely today, isn't it?", "It is. Let's enjoy it while it lasts."],
	["Any good food left, {name}?", "Saved you a bite, {name}. Don't tell the cook."],
	["How's your work going?", "Steady. Better with company."],
	["Those robots are growing on me.", "They hum better than they talk."],
	["Heard anything about the old ruins?", "Only that we should bring a map."],
	["Sometimes I miss the old home.", "We can make this one ours."],
	["I know a joke about a stubborn mule.", "Save it for the next long march."]
]

var game: Game
var _scan_time := 0.0
var _global_cd := 0.0
var _cooldowns: Dictionary = {}
var _chat_reply: Dictionary = {}

func setup(g: Game) -> void:
	game = g
	game.world.fx.connect(_on_fx)

func _process(delta: float) -> void:
	if game == null or game.speed <= 0:
		return
	var scale := float(game.speed)
	_global_cd = maxf(0.0, _global_cd - delta * scale)
	for id: int in _cooldowns:
		_cooldowns[id] = maxf(0.0, float(_cooldowns[id]) - delta * scale)
	if not _chat_reply.is_empty():
		var pending: Dictionary = _chat_reply
		pending["wait"] = float(pending["wait"]) - delta * scale
		if float(pending["wait"]) <= 0.0:
			var responder := game.world.get_unit(int(pending["id"]))
			if _eligible(responder) and _emit(responder, str(pending["line"]), false):
				_cooldowns[responder.id] = 30.0
			_chat_reply.clear()
	_scan_time -= delta * scale
	if _scan_time > 0.0:
		return
	_scan_time = 0.5
	var people := game.world.player_people()
	for unit: Unit in people:
		if not _eligible(unit):
			continue
		var retreating := _retreating(unit)
		if retreating or unit.hp_ratio() < 0.25:
			if cooldown_ready(unit.id):
				var line := "Fall back, regroup!" if retreating else "I need a hand!"
				if _emit(unit, line, true):
					_cooldowns[unit.id] = 15.0
			return
	for unit: Unit in people:
		if _eligible(unit) and (unit.target_id >= 0 or unit.state == Unit.State.FIGHT):
			if cooldown_ready(unit.id):
				_emit(unit, _pick(COMBAT_LINES, unit.id + game.world.tick_count), true)
				_cooldowns[unit.id] = 12.0
			return
	for unit: Unit in people:
		if not _eligible(unit) or unit.target_id >= 0 or unit.state == Unit.State.FIGHT:
			continue
		if cooldown_ready(unit.id) and _global_cd <= 0.0:
			var activity := _activity(unit)
			if activity == "idle" and _try_chat(unit, people):
				return
			var lines: Array = WORK_LINES.get(activity, WORK_LINES["idle"])
			if _emit(unit, _pick(lines, unit.id + game.world.tick_count), false):
				_cooldowns[unit.id] = 25.0 + float((unit.id * 7 + game.world.tick_count) % 21)
				_global_cd = 2.0

func _eligible(unit: Unit) -> bool:
	return unit != null and unit.alive and unit.is_player() and unit.is_person() and unit.visible and not unit.hidden and unit.state != Unit.State.DEAD and unit.state != Unit.State.DOWNED

func cooldown_ready(unit_id: int) -> bool:
	return float(_cooldowns.get(unit_id, 0.0)) <= 0.0
func _retreating(unit: Unit) -> bool:
	if str(unit.order.get("type", "")) == "retreat":
		return true
	if unit.squad_id >= 0:
		var squad := game.world.get_squad(unit.squad_id)
		return squad != null and str(squad.order.get("type", "")) == "retreat"
	return false

func _try_chat(unit: Unit, people: Array) -> bool:
	if _chat_reply.size() > 0 or _activity(unit) == "rest":
		return false
	var closest: Unit
	var best := 4.0
	for other: Unit in people:
		if other.id == unit.id or not _eligible(other) or other.target_id >= 0 or other.state == Unit.State.FIGHT or _activity(other) == "rest":
			continue
		var distance := unit.pos.distance_to(other.pos)
		if distance < best:
			best = distance
			closest = other
	if closest == null:
		return false
	var topic_index := (unit.id + closest.id + game.world.day) % TOPICS.size()
	var pair: Array = TOPICS[topic_index]
	if topic_index == 1 and ("glutton" in unit.character.get("traits", []) or "glutton" in closest.character.get("traits", [])):
		topic_index = 1
		pair = TOPICS[topic_index]
	if _emit(unit, str(pair[0]), false):
		_cooldowns[unit.id] = 35.0
		_cooldowns[closest.id] = 28.0
		_chat_reply = {"id": closest.id, "line": str(pair[1]), "wait": 1.5}
		_global_cd = 2.0
		return true
	return false

func _activity(unit: Unit) -> String:
	if unit.carry_amount > 0 or str(unit.job.get("type", "")) in ["haul", "deliver"]:
		return "haul"
	match str(unit.job.get("type", "")):
		"gather":
			var skill := str(unit.job.get("skill", ""))
			return "mine" if skill in ["mining", "engineering"] else "gather"
		"build", "operate": return "build"
		"farm": return "farm"
		"rest": return "rest"
	if str(unit.order.get("type", "")) == "patrol" or unit.squad_id >= 0 and unit.state != Unit.State.FIGHT:
		return "patrol"
	if str(unit.order.get("type", "")) in ["explore", "auto"]:
		return "explore"
	if str(unit.order.get("type", "")) == "trade":
		return "trade"
	if unit.state == Unit.State.WORK:
		return "repair"
	return "idle"

func _on_fx(kind: StringName, pos: Vector3, _color: Color) -> void:
	if game == null or game.speed <= 0:
		return
	var name := str(kind)
	if name not in ["hit_spark", "death_poof"] and not name.begins_with("combat_damage|"):
		return
	var best: Unit
	var distance := 3.0
	for unit: Unit in game.world.player_people():
		if not _eligible(unit):
			continue
		var d := unit.pos.distance_to(Vector2(pos.x, pos.z))
		if d < distance:
			distance = d
			best = unit
	if best == null:
		return
	var bark := "I'm hit—still standing!"
	if name == "death_poof":
		var victim: Unit
		var victim_distance := 2.0
		for candidate: Unit in game.world.unit_list:
			var victim_d := candidate.pos.distance_to(Vector2(pos.x, pos.z))
			if victim_d < victim_distance:
				victim_distance = victim_d
				victim = candidate
		if victim != null and victim.is_player():
			bark = "I need a hand!"
		else:
			var enemy_nearby := false
			for enemy: Unit in game.world.unit_list:
				if enemy.alive and game.world.hostile("player", enemy.faction) and enemy.pos.distance_to(Vector2(pos.x, pos.z)) < 8.0:
					enemy_nearby = true
					break
			bark = "They're down!" if enemy_nearby else "We held the line!"
	if _emit(best, bark, true):
		_cooldowns[best.id] = 12.0

func _emit(unit: Unit, line: String, combat: bool) -> bool:
	var setting := str(Settings.get_value("interface/speech"))
	if setting == "off" or setting == "combat" and not combat or not _eligible(unit):
		return false
	spoke.emit(unit, Loc.t(line, {"name": unit.name}), combat)
	return true

func _pick(lines: Array, seed_value: int) -> String:
	return str(lines[absi(seed_value) % lines.size()])

static func all_lines() -> Array[String]:
	var lines: Array[String] = []
	for activity: String in WORK_LINES:
		for line: String in WORK_LINES[activity]:
			lines.append(line)
	for line: String in COMBAT_LINES:
		lines.append(line)
	for pair: Array in TOPICS:
		lines.append(str(pair[0]))
		lines.append(str(pair[1]))
	return lines
