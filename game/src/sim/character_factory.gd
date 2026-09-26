class_name CharacterFactory
extends RefCounted
## Creates units: procedural people (NpcGen + AppearanceGen + equipment visuals), machines,
## drones and airships, and named leaders (NamedEnemyGen). Deterministic per world seed and id.

const WEAPON_VISUALS := ["sword", "axe", "spear", "bow", "crossbow", "hammer", "mace", "dagger", "staff", "rifle", "pistol", "wrench", "pickaxe", "hoe", "torch"]
const ARMOR_VISUALS := ["leather", "chain", "plate", "coat"]
const OFFHAND_VISUALS := ["shield", "lantern", "book", "buckler"]


static func style_for(faction: String) -> String:
	match faction:
		"player":
			return "frontier"
		"bandits":
			return "bandit"
		"machines":
			return "ancient"
		"merchants":
			return "merchant"
	return "neutral"


static func faction_color(w: World, faction: String) -> Color:
	match faction:
		"player":
			return w.faction_color
		"bandits":
			return Color("#b33a2e")
		"machines":
			return Color("#ff6a2a")
		"merchants":
			return Color("#4f8a4b")
	return Color("#8a6a4a")


## Copies the look of equipped items into the appearance DNA (held weapon, armour, offhand).
static func sync_dna(u: Unit) -> void:
	if not u.is_person():
		return
	var eq := u.equipment()
	var wpn: Dictionary = eq.get("weapon") if eq.get("weapon") is Dictionary else {}
	var arm: Dictionary = eq.get("armor") if eq.get("armor") is Dictionary else {}
	var gad: Dictionary = eq.get("gadget") if eq.get("gadget") is Dictionary else {}
	if not u.dna.has("_default_weapon"):
		u.dna["_default_weapon"] = u.dna.get("weapon", "none")
		u.dna["_default_armor"] = u.dna.get("armor", "none")
		u.dna["_default_offhand"] = u.dna.get("offhand", "none")
	var wv := str(wpn.get("visual", ""))
	u.dna["weapon"] = wv if wv in WEAPON_VISUALS else ("none" if wpn.is_empty() else str(u.dna["_default_weapon"]))
	if wpn.is_empty() and u.labor == "worker":
		u.dna["weapon"] = str(u.dna["_default_weapon"])
	var av := str(arm.get("visual", ""))
	u.dna["armor"] = av if av in ARMOR_VISUALS else str(u.dna["_default_armor"])
	var gv := str(gad.get("visual", ""))
	u.dna["offhand"] = gv if gv in OFFHAND_VISUALS else str(u.dna["_default_offhand"])
	if str(u.dna["weapon"]) in ["bow", "crossbow", "spear", "staff", "rifle"] and str(u.dna["offhand"]) in ["shield", "buckler"]:
		u.dna["offhand"] = "none"


static func _assign_uids(w: World, eq: Dictionary) -> void:
	for slot: String in eq:
		if eq[slot] is Dictionary and int((eq[slot] as Dictionary).get("uid", 0)) == 0:
			eq[slot]["uid"] = w.new_id()


static func make_person(w: World, opts: Dictionary, pos: Vector2, faction: String = "player", archetype: String = "colonist") -> Unit:
	var u := Unit.new()
	u.id = w.new_id()
	var rng := RngUtil.make([w.seed, "person", u.id])
	var c := NpcGen.generate(rng, opts)
	c["xp"] = float(c.get("xp", 0))
	u.kind = "character"
	u.archetype = archetype
	u.faction = faction
	u.character = c
	var nick := str(c.get("nickname", ""))
	u.name = str(c["name"]) if nick == "" else "%s \"%s\" %s" % [c.get("given", ""), nick, c.get("family", "")]
	u.name = u.name.strip_edges()
	u.dna = AppearanceGen.character(rng, str(c["race"]), str(c["role"]), style_for(faction), faction_color(w, faction), str(c.get("gender", "")))
	var arch := u.DB_archetype()
	u.labor = str(arch.get("labor", "worker"))
	_assign_uids(w, u.equipment())
	sync_dna(u)
	u.pos = pos
	u.recompute_stats()
	u.hp = float(u.stats["max_hp"])
	u.energy = float(u.stats["energy_max"])
	w.add_unit(u)
	return u


static func make_colonist(w: World, opts: Dictionary, pos: Vector2) -> Unit:
	return make_person(w, opts, pos, "player", "colonist")


static func _machine_dna(rng: RandomNumberGenerator, kind: String, archetype: String, style: String, color: Color) -> Dictionary:
	match kind:
		"drone":
			return AppearanceGen.drone(rng, archetype, style, color)
		"airship":
			return AppearanceGen.airship(rng, archetype, style, color)
	var visual_arch := archetype if archetype in ["work_bot", "walker", "sentry", "turret", "hauler"] else "sentry"
	return AppearanceGen.robot(rng, visual_arch, style, color)


static func make_machine(w: World, archetype: String, faction: String, pos: Vector2, level: int = 1) -> Unit:
	var u := Unit.new()
	u.id = w.new_id()
	u.archetype = archetype
	var d := u.DB_archetype()
	var rng := RngUtil.make([w.seed, "machine", u.id])
	u.kind = str(d.get("kind", "robot"))
	u.faction = faction
	u.flying = bool(d.get("flying", false))
	u.altitude = float(d.get("altitude", 0.0))
	u.is_static = bool(d.get("static", false))
	u.level = level
	u.labor = str(d.get("labor", "none"))
	u.name = NameGen.airship(rng) if u.kind == "airship" else NameGen.machine(rng, archetype)
	u.dna = _machine_dna(rng, u.kind, archetype, style_for(faction), faction_color(w, faction))
	u.pos = pos
	u.recompute_stats()
	u.hp = float(u.stats["max_hp"])
	w.add_unit(u)
	return u


## Hostile or neutral person for a site (bandits, merchants, wanderers).
static func make_npc(w: World, archetype: String, faction: String, pos: Vector2, level: int) -> Unit:
	var d := DB.get_def("units", archetype)
	var opts := {"level": level, "role": str(d.get("role", ""))}
	var u := make_person(w, opts, pos, faction, archetype)
	if d.has("named"):
		make_named(w, u, str(d["named"]), level)
	return u


## Turns a unit into a named leader: unique name, epithet, abilities, gear and loot.
static func make_named(w: World, u: Unit, base: String, level: int) -> void:
	var rng := RngUtil.make([w.seed, "named", u.id])
	var tier := clampi(1 + level / 3, 1, 3)
	var n := NamedEnemyGen.generate(rng, {"base": base, "faction_type": "machine" if u.faction == "machines" else "bandit", "level": level, "tier": tier})
	u.named = n
	u.name = "%s, %s" % [n.get("full_name", u.name), n.get("epithet", "")]
	if u.is_person():
		var eq := u.equipment()
		for slot: String in n.get("equipment", {}):
			if n["equipment"][slot] is Dictionary:
				eq[slot] = n["equipment"][slot]
		_assign_uids(w, eq)
		for t: String in n.get("traits", []):
			if not (u.character["traits"] as Array).has(t):
				(u.character["traits"] as Array).append(t)
		sync_dna(u)
	u.recompute_stats()
	u.hp = float(u.stats["max_hp"])
