class_name NpcGen
extends RefCounted
## Deterministic settler/NPC generation. Appearance DNA is intentionally owned by VisualUnits.

const SKILLS: Array[String] = ["melee", "archery", "scouting", "woodcutting", "mining", "farming", "construction", "engineering", "medicine", "trade", "cooking"]
const WORK_SKILLS: Array[String] = ["woodcutting", "mining", "farming", "construction", "engineering", "medicine", "trade", "cooking"]

static func _role(rng: RandomNumberGenerator, requested: String) -> Dictionary:
	if requested != "" and DB.has_def("roles", requested):
		return DB.get_def("roles", requested)
	var rows := GenUtil.entries("roles")
	return GenUtil.pick(rng, rows) as Dictionary

static func _race(rng: RandomNumberGenerator, requested: String) -> Dictionary:
	if requested != "" and DB.has_def("races", requested):
		return DB.get_def("races", requested)
	return GenUtil.pick(rng, GenUtil.entries("races")) as Dictionary

static func _talent(rng: RandomNumberGenerator, requested: String) -> String:
	if requested in ["prodigy", "skilled", "average", "mediocre", "poor"]:
		return requested
	var roll := rng.randf()
	if roll < 0.035:
		return "prodigy"
	if roll < 0.17:
		return "skilled"
	if roll < 0.78:
		return "average"
	if roll < 0.96:
		return "mediocre"
	return "poor"

static func _skill_value(rng: RandomNumberGenerator, talent: String) -> int:
	match talent:
		"prodigy": return rng.randi_range(12, 34)
		"skilled": return rng.randi_range(30, 62)
		"average": return rng.randi_range(8, 40)
		"mediocre": return rng.randi_range(3, 27)
		_: return rng.randi_range(0, 17)

static func _traits(rng: RandomNumberGenerator, race: Dictionary) -> Array:
	var rows := GenUtil.entries("traits")
	var race_weights: Dictionary = race.get("trait_weights", {})
	var selected: Array = []
	var blocked: Dictionary = {}
	var count := rng.randi_range(2, 4)
	for _i in range(count):
		var options: Array = []
		for value: Variant in rows:
			var trait_def: Dictionary = value as Dictionary
			var id := str(trait_def.get("id", ""))
			if selected.has(id) or blocked.has(id):
				continue
			var weight := float(trait_def.get("weight", 1.0)) * float(race_weights.get(id, 1.0))
			if weight <= 0.0:
				continue
			var weighted_trait := trait_def.duplicate()
			weighted_trait["_selection_weight"] = weight
			options.append(weighted_trait)
		if options.is_empty():
			break
		var chosen := GenUtil.weighted(rng, options, "_selection_weight")
		var chosen_id := str(chosen.get("id", ""))
		selected.append(chosen_id)
		blocked[chosen_id] = true
		for conflict: Variant in chosen.get("conflicts", []):
			blocked[str(conflict)] = true
	return selected

static func _quip(rng: RandomNumberGenerator) -> String:
	var doc: Dictionary = GenUtil.raw("generation/quirks", {"quirks": ["Keeps a careful watch."]}) as Dictionary
	return str(GenUtil.pick(rng, doc.get("quirks", [])))

static func _bio(rng: RandomNumberGenerator, name: String, race: String, role: String, skill: String) -> Array[String]:
	var doc: Dictionary = GenUtil.raw("generation/bios", {}) as Dictionary
	var quote := str(GenUtil.pick(rng, doc.get("quotes", ["The road goes on."])))
	var backstory_template := str(GenUtil.pick(rng, doc.get("backstories", ["{name} found a home on the frontier."])))
	var backstory := GenUtil.fill_template(backstory_template, {"name": name, "race": race, "role": role, "skill": skill})
	return [quote, backstory]

static func _equipment(rng: RandomNumberGenerator, role: Dictionary, level: int) -> Dictionary:
	var result: Dictionary = {"weapon": null, "armor": null, "gadget": null}
	for value: Variant in role.get("starting_items", []):
		var base_id := str(value)
		var base := DB.get_def("items", base_id)
		if base.is_empty():
			continue
		var category := str(base.get("category", ""))
		var slot := str(base.get("slot", "none"))
		var equip_slot := slot
		if category == "weapon":
			equip_slot = "weapon"
		elif category in ["armor"]:
			equip_slot = "armor"
		elif category in ["gadget", "tool", "artifact"]:
			equip_slot = "gadget"
		if equip_slot not in result:
			continue
		var quality := "common" if rng.randf() < 0.28 else "crude"
		result[equip_slot] = ItemGen.generate(rng, {"base": base_id, "level": level, "quality": quality, "source": "start"})
	return result

static func generate(rng: RandomNumberGenerator, opts: Dictionary) -> Dictionary:
	var level := maxi(1, int(opts.get("level", 1)))
	var race := _race(rng, str(opts.get("race", "")))
	var role := _role(rng, str(opts.get("role", "")))
	var race_id := str(race.get("id", "human"))
	var role_id := str(role.get("id", "settler"))
	var gender := str(opts.get("gender", ""))
	if gender not in ["female", "male", "nonbinary"]:
		gender = ["female", "male", "nonbinary"][rng.randi_range(0, 2)]
	var person := NameGen.person(rng, race_id, gender if gender != "nonbinary" else "neutral")
	var talent := _talent(rng, str(opts.get("talent", "")))
	var skills: Dictionary = {}
	var aptitude: Dictionary = {}
	var race_bias: Dictionary = race.get("skill_bias", {})
	var role_bonus: Dictionary = role.get("skill_bonus", {})
	var focus := str(GenUtil.pick(rng, SKILLS))
	if str(role.get("combat_role", "none")) == "melee":
		focus = "melee"
	elif str(role.get("combat_role", "none")) == "ranged":
		focus = "archery"
	for skill: String in SKILLS:
		var value := _skill_value(rng, talent)
		value += int(race_bias.get(skill, 0)) + int(role_bonus.get(skill, 0))
		value += (level - 1) * 2
		if talent == "prodigy" and skill == focus:
			value = rng.randi_range(70, 95)
		elif talent == "prodigy":
			value = mini(value, 58)
		skills[skill] = GenUtil.clamp_int(value, 0, 100)
		var apt_base := 0.55 if talent == "poor" else (0.8 if talent == "mediocre" else (1.0 if talent == "average" else (1.35 if talent == "skilled" else 1.55)))
		aptitude[skill] = snappedf(clampf(apt_base + rng.randf_range(-0.15, 0.15), 0.5, 2.0), 0.01)
	if str(role.get("combat_role", "none")) != "none" and rng.randf() < 0.42:
		for skill: String in WORK_SKILLS:
			skills[skill] = mini(int(skills[skill]), rng.randi_range(4, 20))
	var trait_ids := _traits(rng, race)
	var quirk := _quip(rng)
	var best_skill := "melee"
	for skill: String in SKILLS:
		if int(skills[skill]) > int(skills[best_skill]):
			best_skill = skill
	var bio := _bio(rng, str(person["full"]), race_id, role_id, best_skill)
	var age_range: Array = race.get("age_range", [18, 70])
	var age := rng.randi_range(int(age_range[0]), int(age_range[1]))
	var xp := maxi(0, (level - 1) * 100 + rng.randi_range(0, 80))
	return {"name": person["full"], "given": person["given"], "family": person["family"], "nickname": "" if rng.randf() > 0.18 else str(GenUtil.pick(rng, (GenUtil.raw("generation/names", {}) as Dictionary).get("nicknames", []))), "race": race_id, "role": role_id, "gender": gender, "age": age, "level": level, "xp": xp, "skills": skills, "aptitude": aptitude, "traits": trait_ids, "quirk": quirk, "bio": bio[0], "backstory": bio[1], "equipment": _equipment(rng, role, level), "titles": [], "rank": "", "talent": talent}
