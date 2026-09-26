extends TestCase
## Lorewright contract tests and deterministic sample-dump generator.

const STAT_KEYS: Array[String] = ["max_hp", "max_hp_pct", "armor", "move_speed_pct", "work_speed_pct", "gather_speed_pct", "build_speed_pct", "farm_speed_pct", "carry", "melee_damage_pct", "ranged_damage_pct", "attack_speed_pct", "accuracy", "crit_chance", "vision", "night_vision", "retreat_bias", "loot_luck", "energy_max", "energy_regen_pct", "hp_regen_pct", "xp_rate_pct", "trade_pct", "food_use_pct"]
const SKILL_IDS: Array[String] = ["melee", "archery", "scouting", "woodcutting", "mining", "farming", "construction", "engineering", "medicine", "trade", "cooking"]
const QUALITY_TARGETS: Dictionary = {"junk": 0.28, "crude": 0.26, "common": 0.25, "fine": 0.12}

func before_all() -> void:
	DB.reload()

func _json_safe(value: Variant) -> bool:
	var encoded := JSON.stringify(value)
	return encoded != "" and encoded != "null" if value != null else true

func test_determinism() -> void:
	var a := NpcGen.generate(_rng(7001), {"race": "sylvan", "role": "explorer", "level": 4, "talent": "skilled"})
	var b := NpcGen.generate(_rng(7001), {"race": "sylvan", "role": "explorer", "level": 4, "talent": "skilled"})
	assert_eq(a, b, "NPC same seed")
	var ia := ItemGen.generate(_rng(7002), {"base": "scope", "level": 3, "quality": "rare", "luck": 1.0})
	var ib := ItemGen.generate(_rng(7002), {"base": "scope", "level": 3, "quality": "rare", "luck": 1.0})
	assert_eq(ia, ib, "item same seed")
	var ea := NamedEnemyGen.generate(_rng(7003), {"base": "machine_warden", "level": 7, "tier": 3})
	var eb := NamedEnemyGen.generate(_rng(7003), {"base": "machine_warden", "level": 7, "tier": 3})
	assert_eq(ea, eb, "enemy same seed")
	assert_eq(NameGen.person(_rng(8), "vulpin", "female"), NameGen.person(_rng(8), "vulpin", "female"), "name same seed")
	assert_eq(NameGen.place(_rng(9), "ruins"), NameGen.place(_rng(9), "ruins"), "place same seed")

func test_schema_and_cross_references() -> void:
	assert_true(DB.load_errors.is_empty(), "DB reports no load errors")
	for skill: String in SKILL_IDS:
		assert_true(DB.has_def("skills", skill), "missing skill " + skill)
	for race: Dictionary in DB.entries("races"):
		for skill: Variant in (race.get("skill_bias", {}) as Dictionary).keys():
			assert_true(SKILL_IDS.has(str(skill)), "race skill id")
		for trait_key: Variant in (race.get("trait_weights", {}) as Dictionary).keys():
			assert_true(DB.has_def("traits", str(trait_key)), "race trait ref")
	for role: Dictionary in DB.entries("roles"):
		for skill: Variant in (role.get("skill_bonus", {}) as Dictionary).keys():
			assert_true(SKILL_IDS.has(str(skill)), "role skill id")
		for base_id: Variant in role.get("starting_items", []):
			assert_true(DB.has_def("items", str(base_id)), "role item ref")
	for trait_def: Dictionary in DB.entries("traits"):
		for key: Variant in (trait_def.get("mods", {}) as Dictionary).keys():
			assert_true(STAT_KEYS.has(str(key)), "trait stat key")
		for conflict: Variant in trait_def.get("conflicts", []):
			assert_true(DB.has_def("traits", str(conflict)), "trait conflict ref")
	for base: Dictionary in DB.entries("items"):
		for key: Variant in (base.get("mods", {}) as Dictionary).keys():
			assert_true(STAT_KEYS.has(str(key)), "item mod stat key")
		for material: Variant in base.get("materials", []):
			assert_true(DB.has_def("items/materials", str(material)), "material ref")
	for affix: Dictionary in DB.entries("items/affixes"):
		for key: Variant in (affix.get("mods", {}) as Dictionary).keys():
			assert_true(STAT_KEYS.has(str(key)), "affix stat key")

func test_output_schemas() -> void:
	var npc := NpcGen.generate(_rng(1), {"race": "human", "role": "farmer", "level": 2})
	for key: String in ["name", "given", "family", "race", "role", "gender", "age", "level", "xp", "skills", "aptitude", "traits", "quirk", "bio", "backstory", "equipment", "titles", "rank", "talent"]:
		assert_true(npc.has(key), "NPC key " + key)
	for skill: String in SKILL_IDS:
		assert_true((npc["skills"] as Dictionary).has(skill), "NPC skill " + skill)
	for trait_id: Variant in npc["traits"]:
		assert_true(DB.has_def("traits", str(trait_id)), "NPC trait exists")
	assert_false(npc.has("appearance"), "NPC does not create appearance")
	assert_true(_json_safe(npc), "NPC JSON-safe")
	var quirk_doc: Dictionary = DB.raw("generation/quirks") as Dictionary
	var bio_doc: Dictionary = DB.raw("generation/bios") as Dictionary
	assert_eq(npc["quirk"], (quirk_doc["quirks"] as Array)[int(npc["quirk_i"])], "NPC quirk index reproduces English")
	assert_eq(npc["bio"], (bio_doc["quotes"] as Array)[int(npc["bio_i"])], "NPC bio index reproduces English")
	assert_eq(npc["backstory"], GenUtil.fill_template(str((bio_doc["backstories"] as Array)[int(npc["backstory_i"])]), npc["backstory_params"]), "NPC backstory metadata reproduces English")
	var item := ItemGen.generate(_rng(2), {"base": "spear", "level": 3, "quality": "fine"})
	for key: String in ["uid", "base", "name", "category", "slot", "quality", "level", "material", "stats", "mods", "value", "flavor", "unique", "visual", "appearance"]:
		assert_true(item.has(key), "item key " + key)
	assert_true(_mods_use_stat_keys(item["mods"] as Dictionary), "item mods use stat keys")
	assert_true(_json_safe(item), "item JSON-safe")
	var generated_affix_ids: Array[String] = []
	for affix: Dictionary in item["affixes"]:
		generated_affix_ids.append(str(affix.get("id", "")))
	assert_eq(item["affix_ids"], generated_affix_ids, "item affix ids match selected affixes")
	var enemy := NamedEnemyGen.generate(_rng(3), {"base": "bandit_captain", "level": 5, "tier": 2})
	for key: String in ["name", "epithet", "full_name", "base", "level", "tier", "traits", "abilities", "equipment", "loot", "stat_mult", "bio"]:
		assert_true(enemy.has(key), "enemy key " + key)
	for trait_id: Variant in enemy["traits"]:
		assert_true(DB.has_def("traits", str(trait_id)), "enemy trait exists")
	for ability: Variant in enemy["abilities"]:
		assert_true(DB.has_def("generation/abilities", str(ability)), "enemy ability exists")
	assert_true(_json_safe(enemy), "enemy JSON-safe")
	var named_doc: Dictionary = DB.raw("generation/named") as Dictionary
	var enemy_parts: Dictionary = named_doc["bandit"] as Dictionary
	assert_eq(enemy["epithet"], (enemy_parts["epithets"] as Array)[int(enemy["epithet_i"])], "enemy epithet index reproduces English")

func test_quality_distribution() -> void:
	var rng := _rng(991)
	var counts: Dictionary = {}
	for quality: Dictionary in DB.entries("items/qualities"):
		counts[quality["id"]] = 0
	for _i in range(20000):
		var quality := ItemGen.roll_quality(rng, 0.0)
		counts[quality] = int(counts.get(quality, 0)) + 1
	for key: String in QUALITY_TARGETS:
		var observed := float(counts[key]) / 20000.0
		assert_between(observed, QUALITY_TARGETS[key] * 0.8, QUALITY_TARGETS[key] * 1.2, "quality " + key)
	var top := (int(counts.get("legendary", 0)) + int(counts.get("anomalous", 0))) / 200.0
	assert_true(top < 1.5, "legendary+anomalous under 1.5 percent")
	print("QUALITY_DISTRIBUTION ", counts)

func test_talent_spread_and_names() -> void:
	var rng := _rng(1777)
	var max_seen := 0
	var low_count := 0
	var fighter_with_poor_work := 0
	var names: Dictionary = {}
	for _i in range(500):
		var npc := NpcGen.generate(rng, {"level": 1})
		for value: Variant in (npc["skills"] as Dictionary).values():
			max_seen = maxi(max_seen, int(value))
		var local_max := 0
		for value: Variant in (npc["skills"] as Dictionary).values():
			local_max = maxi(local_max, int(value))
		if local_max <= 45:
			low_count += 1
		if str(npc["role"]) in ["guard", "archer", "hunter", "mercenary", "bandit", "bandit_archer", "bandit_captain"]:
			var work_max := 0
			for skill: String in NpcGen.WORK_SKILLS:
				work_max = maxi(work_max, int((npc["skills"] as Dictionary)[skill]))
			if work_max <= 20:
				fighter_with_poor_work += 1
		names[npc["name"]] = true
	assert_true(max_seen >= 70, "prodigy max skill >=70")
	assert_true(low_count >= 100, "many ordinary/poor NPCs")
	assert_true(fighter_with_poor_work > 0, "fighter with poor work skills")
	assert_true(float(names.size()) / 500.0 >= 0.8, "NPC names at least 80 percent unique")
	print("TALENT_SPREAD max=", max_seen, " low=", low_count, " poor_fighters=", fighter_with_poor_work, " unique=", names.size())

func test_write_samples() -> void:
	var sample_dir := "res://../docs/samples"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(sample_dir))
	var rng := _rng(42042)
	var npc_lines := PackedStringArray(["# Frontier Settlers", "", "Generated by `test_generators.gd` with seed 42042.", ""])
	for index in range(12):
		var npc := NpcGen.generate(rng, {"level": (index % 5) + 1})
		npc_lines.append("## %s" % npc["name"])
		npc_lines.append("- **Race / role:** %s %s  " % [npc["race"], npc["role"]])
		npc_lines.append("- **Age / talent:** %d / %s  " % [npc["age"], npc["talent"]])
		npc_lines.append("- **Traits:** %s  " % ", ".join(npc["traits"]))
		npc_lines.append("- **Top skills:** %s  " % _top_skills(npc["skills"]))
		npc_lines.append("- **Quirk:** %s  " % npc["quirk"])
		npc_lines.append("- **Bio:** \"%s\"  " % npc["bio"])
		npc_lines.append("- **Backstory:** %s  " % npc["backstory"])
		npc_lines.append("- **Equipment:** %s" % _equipment_summary(npc["equipment"]))
		npc_lines.append("")
	_write_sample("res://../docs/samples/npcs.md", npc_lines)
	var item_lines := PackedStringArray(["# Frontier Loot", "", "Generated by `test_generators.gd` with seed 42042.", ""])
	for index in range(60):
		var item := ItemGen.generate(rng, {"level": (index % 5) + 1, "luck": 0.1})
		item_lines.append("## %s" % item["name"])
		item_lines.append("- **Quality / level / material:** %s / %d / %s  " % [item["quality"], item["level"], item["material"]])
		item_lines.append("- **Stats:** %s  " % str(item["stats"]))
		item_lines.append("- **Mods:** %s  " % str(item["mods"]))
		item_lines.append("- **Flavor:** %s" % item["flavor"])
		item_lines.append("")
	for tier in range(1, 4):
		var enemy := NamedEnemyGen.generate(rng, {"base": "machine_warden" if tier > 1 else "bandit_captain", "level": tier + 4, "tier": tier})
		item_lines.append("## Named enemy: %s %s" % [enemy["full_name"], enemy["epithet"]])
		item_lines.append("- **Base / tier:** %s / %d  " % [enemy["base"], enemy["tier"]])
		item_lines.append("- **Abilities:** %s  " % ", ".join(enemy["abilities"]))
		item_lines.append("- **Loot:** %d items" % enemy["loot"].size())
		item_lines.append("")
	_write_sample("res://../docs/samples/items.md", item_lines)

func _rng(seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return rng

func _top_skills(skills: Dictionary) -> String:
	var pairs: Array = []
	for key: Variant in skills.keys():
		pairs.append({"id": str(key), "value": int(skills[key])})
	pairs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["value"] > b["value"])
	var out: Array[String] = []
	for pair: Dictionary in pairs.slice(0, mini(3, pairs.size())):
		out.append("%s %d" % [pair["id"], pair["value"]])
	return ", ".join(out)

func _equipment_summary(equipment: Dictionary) -> String:
	var out: Array[String] = []
	for slot: String in ["weapon", "armor", "gadget"]:
		var item: Variant = equipment.get(slot)
		if item is Dictionary:
			out.append("%s: %s" % [slot, (item as Dictionary).get("name", "none")])
	return ", ".join(out) if not out.is_empty() else "none"

func _write_sample(path: String, lines: PackedStringArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(lines) + "\n")
func _mods_use_stat_keys(mods: Dictionary) -> bool:
	for key: Variant in mods.keys():
		if not STAT_KEYS.has(str(key)):
			return false
	return true
