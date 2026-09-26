class_name Unit
extends RefCounted
## Simulation state of one unit (person, robot, drone or airship). Pure data + small helpers;
## behaviour lives in the systems (ColonyAI, SquadAI, Combat, FactionAI). The view reads it.

enum State { IDLE, MOVE, WORK, FIGHT, DOWNED, DEAD, REST }
const SKILLS := ["melee", "archery", "scouting", "woodcutting", "mining", "farming", "construction", "engineering", "medicine", "trade", "cooking"]
const FISTS := {"damage": 3.0, "cooldown": 1.0, "range": 1.3, "kind": "melee", "projectile": "none", "accuracy": 0.9}

var id := 0
var kind := "character"  # character | robot | drone | airship
var archetype := "colonist"
var faction := "player"
var name := ""
var character: Dictionary = {}  # NpcGen record for people (skills, traits, equipment, bio, ...)
var dna: Dictionary = {}
var gear: Dictionary = {}  # equipment of machines: slot -> item
var level := 1
var flying := false
var altitude := 0.0
var is_static := false

var pos := Vector2.ZERO  # metres in world x/z
var prev_pos := Vector2.ZERO
var facing := Vector2(0, 1)
var hp := 100.0
var energy := 100.0
var stats: Dictionary = {}

var state := State.IDLE
var alive := true
var hidden := false  # inside a building (resting)
var held := ""
var carry_res := ""
var carry_amount := 0
var fx_queue: Array[StringName] = []

# movement
var path := PackedVector2Array()
var path_i := 0
var moving := false
var goal := Vector2.ZERO
var stuck_t := 0.0

# control
var labor := "worker"  # worker | soldier | none
var squad_id := -1
var order: Dictionary = {}  # direct order (units outside squads, machines): {type, ...}
var job: Dictionary = {}  # colony job
var ai_cd := 0.0
var target_id := -1
var attack_cd := 0.0
var ability_cd: Dictionary = {}
var buffs: Array = []  # [{"mods": {}, "t": seconds}]
var home_site := -1
var guard_pos := Vector2.ZERO
var downed_t := 0.0
var injured_days := 0.0
var named: Dictionary = {}
var counters: Dictionary = {}
var cargo: Dictionary = {}
var visible := true  # seen by the player this tick
var lod := 0
var last_hit_t := 99.0  # seconds since last damaged
var xp_hint := 0.0


func is_person() -> bool:
	return kind == "character"


func is_machine() -> bool:
	return kind != "character"


func is_player() -> bool:
	return faction == "player"


func tile() -> Vector2i:
	return Vector2i(int(floor(pos.x)), int(floor(pos.y)))


func equipment() -> Dictionary:
	if is_person():
		if not character.has("equipment"):
			character["equipment"] = {}
		return character["equipment"]
	return gear


func skill(id_: String) -> float:
	if is_person():
		return float((character.get("skills", {}) as Dictionary).get(id_, 0))
	return float((DB_archetype().get("skills", {}) as Dictionary).get(id_, 0))


func DB_archetype() -> Dictionary:
	for table: String in ["units", "robots", "airships"]:
		if DB.has_def(table, archetype):
			return DB.get_def(table, archetype)
	return {}


func char_level() -> int:
	return int(character.get("level", 1)) if is_person() else level


## Sum of stat modifiers from traits, equipment and active buffs.
func mods() -> Dictionary:
	var out := {}
	if is_person():
		for tid: String in character.get("traits", []):
			_add_mods(out, DB.get_def("traits", tid).get("mods", {}))
	for slot: String in equipment():
		var it: Variant = equipment()[slot]
		if it is Dictionary:
			_add_mods(out, (it as Dictionary).get("mods", {}))
	for b: Dictionary in buffs:
		_add_mods(out, b.get("mods", {}))
	if injured_days > 0.0:
		_add_mods(out, {"move_speed_pct": -0.2, "work_speed_pct": -0.25, "melee_damage_pct": -0.2, "ranged_damage_pct": -0.2})
	return out


static func _add_mods(out: Dictionary, m: Dictionary) -> void:
	for k: String in m:
		out[k] = float(out.get(k, 0.0)) + float(m[k])


## Recomputes effective stats. Call after equipment, traits, level or buffs change.
func recompute_stats() -> void:
	var arch := DB_archetype()
	var base: Dictionary = {"max_hp": 90.0, "armor": 0.0, "move_speed": 2.2, "vision": 9.0, "carry": 20.0, "energy": 100.0, "cargo": 0.0}
	if is_person():
		var race := DB.get_def("races", str(character.get("race", "human")))
		for k: String in race.get("base", {}):
			base[k] = float(race["base"][k])
	for k: String in arch.get("base", {}):
		base[k] = float(arch["base"][k])
	var m := mods()
	var lv := char_level()
	var eq := equipment()
	var armor_item: Dictionary = eq.get("armor") if eq.get("armor") is Dictionary else {}
	var armor_stats: Dictionary = armor_item.get("stats", {})
	var hp_per_level := float(arch.get("level_hp", 6.0))
	var max_hp := (float(base["max_hp"]) + (lv - 1) * hp_per_level + float(m.get("max_hp", 0.0)) + float(armor_stats.get("max_hp", 0.0))) * (1.0 + float(m.get("max_hp_pct", 0.0)))
	var s := {
		"max_hp": maxf(10.0, max_hp),
		"armor": float(base["armor"]) + float(m.get("armor", 0.0)) + float(armor_stats.get("armor", 0.0)),
		"move_speed": float(base["move_speed"]) * maxf(0.3, 1.0 + float(m.get("move_speed_pct", 0.0))),
		"vision": float(base["vision"]) + float(m.get("vision", 0.0)) + skill("scouting") * 0.03,
		"night_vision": float(m.get("night_vision", 0.0)),
		"carry": maxf(0.0, float(base["carry"]) + float(m.get("carry", 0.0))),
		"cargo": float(base.get("cargo", 0.0)),
		"energy_max": float(base["energy"]) + float(m.get("energy_max", 0.0)),
		"work": 1.0 + float(m.get("work_speed_pct", 0.0)),
		"gather": float(m.get("gather_speed_pct", 0.0)),
		"build": float(m.get("build_speed_pct", 0.0)),
		"farm": float(m.get("farm_speed_pct", 0.0)),
		"melee_pct": float(m.get("melee_damage_pct", 0.0)),
		"ranged_pct": float(m.get("ranged_damage_pct", 0.0)),
		"attack_speed": 1.0 + float(m.get("attack_speed_pct", 0.0)),
		"accuracy": float(m.get("accuracy", 0.0)),
		"crit": 0.05 + float(m.get("crit_chance", 0.0)),
		"retreat_bias": float(m.get("retreat_bias", 0.0)),
		"loot_luck": float(m.get("loot_luck", 0.0)),
		"hp_regen": 1.0 + float(m.get("hp_regen_pct", 0.0)),
		"energy_regen": 1.0 + float(m.get("energy_regen_pct", 0.0)),
		"xp_rate": 1.0 + float(m.get("xp_rate_pct", 0.0)),
		"trade": float(m.get("trade_pct", 0.0)),
		"food_use": maxf(0.2, 1.0 + float(m.get("food_use_pct", 0.0))),
	}
	s["weapon"] = weapon()
	s["damage_mult"] = 1.0 + (lv - 1) * (0.04 if is_person() else 0.08)
	if not named.is_empty():
		var sm: Dictionary = named.get("stat_mult", {})
		s["max_hp"] = float(s["max_hp"]) * float(sm.get("max_hp", 1.0))
		s["damage_mult"] = float(s["damage_mult"]) * float(sm.get("damage", 1.0))
	var was_max := float(stats.get("max_hp", s["max_hp"]))
	stats = s
	if was_max > 0.0 and absf(was_max - float(s["max_hp"])) > 0.01:
		hp = clampf(hp * float(s["max_hp"]) / was_max, 1.0 if alive else 0.0, float(s["max_hp"]))
	hp = minf(hp, float(s["max_hp"]))


## Weapon stats: equipped weapon item, else archetype weapon, else fists.
func weapon() -> Dictionary:
	var eq := equipment()
	if eq.get("weapon") is Dictionary:
		var w: Dictionary = eq["weapon"]
		var st: Dictionary = w.get("stats", {})
		if st.has("damage"):
			var out := FISTS.duplicate()
			for k: String in st:
				out[k] = st[k]
			return out
	var arch := DB_archetype()
	if arch.get("weapon") is Dictionary:
		return arch["weapon"]
	return FISTS


func is_armed() -> bool:
	if kind == "airship" or archetype in ["scout_drone", "repair_drone"]:
		return false
	return is_person() or DB_archetype().get("weapon") is Dictionary


func hp_ratio() -> float:
	return clampf(hp / maxf(1.0, float(stats.get("max_hp", 100.0))), 0.0, 1.0)


func push_fx(action: StringName) -> void:
	if fx_queue.size() < 6:
		fx_queue.append(action)


func counter_add(key: String, amount: float = 1.0) -> void:
	counters[key] = float(counters.get(key, 0.0)) + amount


func display_role() -> String:
	if is_person():
		var r := DB.get_def("roles", str(character.get("role", "")))
		return str(r.get("name", str(character.get("role", "")).capitalize()))
	return str(DB_archetype().get("name", archetype.capitalize()))


## Icon id describing the unit's combat/work class for the HUD.
func class_icon() -> String:
	if kind == "airship":
		return "class_airship"
	if kind == "drone":
		return "class_drone"
	if kind == "robot":
		return "class_robot"
	var w := str(((equipment().get("weapon") as Dictionary) if equipment().get("weapon") is Dictionary else {}).get("visual", ""))
	var off: Variant = equipment().get("offhand")
	var role := DB.get_def("roles", str(character.get("role", "")))
	if labor == "soldier" or squad_id >= 0:
		if w in ["bow", "crossbow", "rifle", "pistol"]:
			return "class_archer"
		if w == "spear":
			return "class_spear"
		if str(dna.get("offhand", "")) in ["shield", "buckler"] or off != null:
			return "class_shield"
	return str(role.get("class_icon", "class_worker"))


func to_dict() -> Dictionary:
	return {
		"id": id, "kind": kind, "archetype": archetype, "faction": faction, "name": name,
		"character": character, "dna": dna, "gear": gear, "level": level, "flying": flying, "altitude": altitude,
		"static": is_static, "pos": [pos.x, pos.y], "facing": [facing.x, facing.y], "hp": hp, "energy": energy,
		"state": state, "alive": alive, "hidden": hidden, "carry_res": carry_res, "carry_amount": carry_amount,
		"path": _pack_path(), "path_i": path_i, "moving": moving, "goal": [goal.x, goal.y],
		"labor": labor, "squad_id": squad_id, "order": _vec_safe(order), "job": _vec_safe(job), "ai_cd": ai_cd,
		"target_id": target_id, "attack_cd": attack_cd, "ability_cd": ability_cd, "buffs": buffs,
		"home_site": home_site, "guard_pos": [guard_pos.x, guard_pos.y], "downed_t": downed_t,
		"injured_days": injured_days, "named": named, "counters": counters, "cargo": cargo, "held": held,
		"visible": visible, "last_hit_t": last_hit_t,
	}


func _pack_path() -> Array:
	var out: Array = []
	for v in path:
		out.append([v.x, v.y])
	return out


## Converts Vector2 / Vector2i values in (nested) dictionaries to tagged arrays for JSON.
static func _vec_safe(v: Variant) -> Variant:
	if v is Vector2:
		return {"__v2": [v.x, v.y]}
	if v is Vector2i:
		return {"__v2i": [v.x, v.y]}
	if v is Dictionary:
		var out := {}
		for k: Variant in v:
			out[k] = _vec_safe(v[k])
		return out
	if v is Array:
		var out: Array = []
		for e: Variant in v:
			out.append(_vec_safe(e))
		return out
	if v is PackedVector2Array:
		var out: Array = []
		for e in v:
			out.append({"__v2": [e.x, e.y]})
		return {"__pv2": out}
	return v


static func _vec_restore(v: Variant) -> Variant:
	if v is Dictionary:
		if v.has("__v2"):
			return Vector2(float(v["__v2"][0]), float(v["__v2"][1]))
		if v.has("__v2i"):
			return Vector2i(int(v["__v2i"][0]), int(v["__v2i"][1]))
		if v.has("__pv2"):
			var pv := PackedVector2Array()
			for e: Variant in v["__pv2"]:
				pv.append(_vec_restore(e))
			return pv
		var out := {}
		for k: Variant in v:
			out[k] = _vec_restore(v[k])
		return out
	if v is Array:
		var out: Array = []
		for e: Variant in v:
			out.append(_vec_restore(e))
		return out
	return v


static func from_dict(d: Dictionary) -> Unit:
	var u := Unit.new()
	u.id = int(d["id"])
	u.kind = str(d["kind"])
	u.archetype = str(d["archetype"])
	u.faction = str(d["faction"])
	u.name = str(d["name"])
	u.character = d.get("character", {})
	_int_fields(u.character)
	u.dna = d.get("dna", {})
	u.gear = d.get("gear", {})
	u.level = int(d.get("level", 1))
	u.flying = bool(d.get("flying", false))
	u.altitude = float(d.get("altitude", 0.0))
	u.is_static = bool(d.get("static", false))
	u.pos = Vector2(float(d["pos"][0]), float(d["pos"][1]))
	u.prev_pos = u.pos
	u.facing = Vector2(float(d["facing"][0]), float(d["facing"][1]))
	u.hp = float(d["hp"])
	u.energy = float(d.get("energy", 100.0))
	u.state = int(d.get("state", 0))
	u.alive = bool(d.get("alive", true))
	u.hidden = bool(d.get("hidden", false))
	u.carry_res = str(d.get("carry_res", ""))
	u.carry_amount = int(d.get("carry_amount", 0))
	for e: Array in d.get("path", []):
		u.path.append(Vector2(float(e[0]), float(e[1])))
	u.path_i = int(d.get("path_i", 0))
	u.moving = bool(d.get("moving", false))
	u.goal = Vector2(float(d["goal"][0]), float(d["goal"][1]))
	u.labor = str(d.get("labor", "worker"))
	u.squad_id = int(d.get("squad_id", -1))
	u.order = _vec_restore(d.get("order", {}))
	u.job = _vec_restore(d.get("job", {}))
	u.ai_cd = float(d.get("ai_cd", 0.0))
	u.target_id = int(d.get("target_id", -1))
	u.attack_cd = float(d.get("attack_cd", 0.0))
	u.ability_cd = d.get("ability_cd", {})
	u.buffs = d.get("buffs", [])
	u.home_site = int(d.get("home_site", -1))
	u.guard_pos = Vector2(float(d["guard_pos"][0]), float(d["guard_pos"][1]))
	u.downed_t = float(d.get("downed_t", 0.0))
	u.injured_days = float(d.get("injured_days", 0.0))
	u.named = d.get("named", {})
	u.counters = d.get("counters", {})
	u.cargo = d.get("cargo", {})
	u.held = str(d.get("held", ""))
	u.visible = bool(d.get("visible", true))
	u.last_hit_t = float(d.get("last_hit_t", 99.0))
	u.recompute_stats()
	u.hp = float(d["hp"])
	return u


## JSON turns ints into floats; restore the integer fields of a character record.
static func _int_fields(c: Dictionary) -> void:
	for k: String in ["level", "age"]:
		if c.has(k):
			c[k] = int(c[k])
	if c.get("skills") is Dictionary:
		var sk: Dictionary = c["skills"]
		for k: String in sk:
			sk[k] = int(sk[k])
