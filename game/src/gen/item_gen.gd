class_name ItemGen
extends RefCounted
## Deterministic loot and equipment generation.

const ANOMALOUS_NAMES: Array[String] = [
	"The Clockwork That Remembers", "A Lantern for the Unborn", "Hush of the Deep Engine",
	"The Skyhook at Midnight", "A Small and Patient Thunder", "The Unlost Compass"
]

static func _quality_rows() -> Array:
	return GenUtil.entries("items/qualities")

static func roll_quality(rng: RandomNumberGenerator, luck: float) -> String:
	var rows := _quality_rows()
	if rows.is_empty():
		return "common"
	var weighted_rows: Array = []
	var clamped_luck := clampf(luck, -0.8, 4.0)
	for value: Variant in rows:
		var row: Dictionary = value as Dictionary
		var tier := float(row.get("tier", 0))
		var shifted := row.duplicate()
		var shift := pow(1.0 + clamped_luck * 0.25, tier) if clamped_luck >= 0.0 else maxf(0.05, 1.0 + clamped_luck * tier * 0.22)
		shifted["weight"] = maxf(0.001, float(row.get("weight", 1.0)) * shift)
		weighted_rows.append(shifted)
	return str(GenUtil.weighted(rng, weighted_rows).get("id", "common"))

static func _choose_base(rng: RandomNumberGenerator, opts: Dictionary, level: int) -> Dictionary:
	var requested := str(opts.get("base", ""))
	if requested != "" and DB.has_def("items", requested):
		return DB.get_def("items", requested)
	var category := str(opts.get("category", ""))
	var candidates: Array = []
	for row: Variant in GenUtil.entries("items"):
		var base: Dictionary = row as Dictionary
		if category != "" and str(base.get("category", "")) != category:
			continue
		if int(base.get("level_min", 1)) <= level:
			candidates.append(base)
	if candidates.is_empty():
		candidates = GenUtil.entries("items")
	return GenUtil.pick(rng, candidates) as Dictionary

static func _choose_material(rng: RandomNumberGenerator, base: Dictionary, level: int) -> Dictionary:
	var options: Array = []
	var wanted: Array = base.get("materials", [])
	for value: Variant in wanted:
		var material := GenUtil.safe_def("items/materials", str(value))
		if not material.is_empty() and int(material.get("level_min", 1)) <= level:
			options.append(material)
	if options.is_empty():
		options.append(GenUtil.safe_def("items/materials", "scrap"))
	return GenUtil.pick(rng, options) as Dictionary

static func _choose_affixes(rng: RandomNumberGenerator, category: String, count: int, level: int) -> Array:
	var choices: Array = []
	for value: Variant in GenUtil.entries("items/affixes"):
		var affix: Dictionary = value as Dictionary
		if int(affix.get("level_min", 1)) <= level and category in (affix.get("categories", []) as Array):
			choices.append(affix)
	var selected: Array = []
	var pool := choices.duplicate()
	for _i in range(count):
		if pool.is_empty():
			break
		var affix := GenUtil.weighted(rng, pool)
		selected.append(affix)
		pool.erase(affix)
	return selected

static func _quality(level: String) -> Dictionary:
	var row := GenUtil.safe_def("items/qualities", level)
	return row if not row.is_empty() else GenUtil.safe_def("items/qualities", "common")

static func _format_name(rng: RandomNumberGenerator, base: Dictionary, material: Dictionary, quality: Dictionary, affixes: Array, unique: bool) -> Dictionary:
	if unique:
		var names: Array[String] = ANOMALOUS_NAMES
		var unique_i := rng.randi_range(0, names.size() - 1)
		return {"text": names[unique_i], "unique_i": unique_i}
	var prefix := ""
	var suffix := ""
	for value: Variant in affixes:
		var affix: Dictionary = value as Dictionary
		if str(affix.get("kind", "prefix")) == "prefix" and prefix == "":
			prefix = str(affix.get("name", ""))
		elif str(affix.get("kind", "suffix")) == "suffix" and suffix == "":
			suffix = str(affix.get("name", ""))
	var noun := str((base.get("name_nouns", [base.get("name", "Item")]) as Array)[0])
	var material_name := str(material.get("name", "Scrap"))
	var quality_id := str(quality.get("id", "common"))
	if quality_id == "junk":
		return {"text": "Worn %s %s" % [material_name, noun], "template": "gen.item.name.junk"}
	if quality_id == "crude":
		return {"text": "Rusty %s" % noun, "template": "gen.item.name.crude"}
	var result := (prefix + " " if prefix != "" else "") + material_name + " " + noun
	if suffix != "":
		result += " " + suffix
	return {"text": result, "template": "gen.item.name.standard"}

static func generate(rng: RandomNumberGenerator, opts: Dictionary) -> Dictionary:
	var level := maxi(1, int(opts.get("level", 1)))
	var base := _choose_base(rng, opts, level)
	if base.is_empty():
		return {}
	var quality_id := str(opts.get("quality", ""))
	if quality_id == "":
		quality_id = roll_quality(rng, float(opts.get("luck", 0.0)))
	var quality := _quality(quality_id)
	var material := _choose_material(rng, base, level)
	var tier := int(quality.get("tier", 2))
	var affix_range: Array = quality.get("affix_count", [0, 0])
	var affix_count := rng.randi_range(int(affix_range[0]), int(affix_range[1])) if affix_range.size() >= 2 else 0
	var affixes := _choose_affixes(rng, str(base.get("category", "resource")), affix_count, level)
	var scale := float(material.get("stat_mult", 1.0)) * float(quality.get("stat_mult", 1.0)) * (1.0 + 0.08 * float(level - 1))
	var variance := rng.randf_range(0.94, 1.06)
	var stats: Dictionary = {}
	for key: Variant in (base.get("base_stats", {}) as Dictionary).keys():
		var value: Variant = (base.get("base_stats", {}) as Dictionary)[key]
		if value is float or value is int:
			# Power scales; handling does not. Scaling cooldown made rare weapons slower.
			var scaled := float(value) * scale * variance if str(key) in ["damage", "armor", "max_hp", "carry", "power"] else float(value)
			stats[str(key)] = snappedf(scaled, 0.01)
		else:
			stats[str(key)] = value
	var mods := GenUtil.valid_mods(base.get("mods", {}) as Dictionary)
	for value: Variant in affixes:
		GenUtil.merge_mods(mods, (value as Dictionary).get("mods", {}) as Dictionary)
	if quality_id == "anomalous":
		mods["loot_luck"] = float(mods.get("loot_luck", 0.0)) + 0.3
		mods["energy_max"] = float(mods.get("energy_max", 0.0)) + 25.0
		if rng.randf() < 0.35:
			mods["food_use_pct"] = float(mods.get("food_use_pct", 0.0)) + 0.18
	for key: Variant in mods.keys():
		mods[key] = snappedf(float(mods[key]) * (0.92 + 0.08 * scale), 0.001)
	var unique := quality_id == "anomalous"
	var item_name_data := _format_name(rng, base, material, quality, affixes, unique)
	var appearance := {
		"kind": "item", "seed": rng.randi(), "shape": str(base.get("icon", "gear")),
		"primary": str(material.get("color", "#777b80")), "secondary": str(material.get("secondary", "#3b4148")),
		"accent": str(quality.get("color", "#e9dcc0")), "glow": float(quality.get("glow", 0.0)),
		"variant": rng.randi_range(0, 3), "engraved": tier >= 4 or unique, "worn": rng.randf_range(0.05, 0.55) if tier < 3 else rng.randf_range(0.0, 0.22)
	}
	var value := maxi(1, int(round(float(base.get("value", 1)) * float(material.get("value_mult", 1.0)) * float(quality.get("value_mult", 1.0)) * (1.0 + 0.1 * level))))
	var flavor := _flavor(base, material, quality, unique)
	var affix_ids: Array[String] = []
	for affix: Dictionary in affixes:
		affix_ids.append(str(affix.get("id", "")))
	var flavor_message := _flavor_message(base, material, quality, unique)
	return {"uid": 0, "base": str(base.get("id", "")), "name": item_name_data["text"], "name_template": item_name_data.get("template", ""), "unique_i": item_name_data.get("unique_i", -1), "category": str(base.get("category", "resource")), "slot": str(base.get("slot", "none")), "quality": quality_id, "level": level, "material": str(material.get("id", "scrap")), "stats": stats, "mods": mods, "value": value, "flavor": flavor, "flavor_message": flavor_message, "unique": unique, "visual": str(base.get("visual", "")), "appearance": appearance, "affixes": affixes, "affix_ids": affix_ids}

static func _flavor(base: Dictionary, material: Dictionary, quality: Dictionary, unique: bool) -> String:
	if unique:
		return "It hums softly when pointed toward forgotten roads."
	var q := str(quality.get("id", "common"))
	var noun := str(base.get("name", "item")).to_lower()
	var mat := str(material.get("name", "scrap")).to_lower()
	if q == "junk":
		return "A battered %s of %s, but still useful in a pinch." % [noun, mat]
	if q == "crude":
		return "Rough frontier work in %s; honest, noisy, and serviceable." % mat
	if q == "rare" or q == "epic" or q == "legendary":
		return "A carefully made %s that catches the light like a promise." % noun
	return "A dependable %s prepared from warm, practical %s." % [noun, mat]

static func _flavor_message(base: Dictionary, material: Dictionary, quality: Dictionary, unique: bool) -> Dictionary:
	if unique:
		return {"key": "gen.item.flavor.unique"}
	var quality_id := str(quality.get("id", "common"))
	var key := "gen.item.flavor.standard"
	if quality_id == "junk":
		key = "gen.item.flavor.junk"
	elif quality_id == "crude":
		key = "gen.item.flavor.crude"
	elif quality_id in ["rare", "epic", "legendary"]:
		key = "gen.item.flavor.rare"
	return {"key": key, "params": {"noun": {"table": "items", "id": str(base.get("id", "")), "en": str(base.get("name", "item")).to_lower()}, "material": {"table": "items/materials", "id": str(material.get("id", "scrap")), "en": str(material.get("name", "scrap")).to_lower()}}}

static func loot(rng: RandomNumberGenerator, level: int, luck: float, count: int) -> Array:
	var result: Array = []
	for _i in range(maxi(0, count)):
		result.append(generate(rng, {"level": level, "luck": luck, "source": "loot"}))
	return result

## Theme-specific relics have different build-defining effects, not just different names.
static func relic(rng: RandomNumberGenerator, theme: String, level: int, difficulty: int) -> Dictionary:
	var row: Dictionary = {
		"brigands": {"name": "Chainbreaker's Edge", "base": "sword", "mods": {"melee_damage_pct": 0.18, "crit_chance": 0.06}},
		"goblins": {"name": "Warrenrunner's Bow", "base": "bow", "mods": {"ranged_damage_pct": 0.18, "move_speed_pct": 0.08}},
		"reptiles": {"name": "Scale of the Deep", "base": "chain_mail", "mods": {"armor": 6.0, "max_hp": 35.0}},
		"beastfolk": {"name": "Horncaller's Maul", "base": "hammer", "mods": {"melee_damage_pct": 0.22, "max_hp": 25.0}},
		"machines": {"name": "Heart of the Vault", "base": "sensor_array", "mods": {"energy_max": 35.0, "loot_luck": 0.25}},
		"wilds": {"name": "Mossback Mantle", "base": "leather_vest", "mods": {"hp_regen_pct": 0.8, "move_speed_pct": 0.10}},
	}[theme]
	var quality: String = ["rare", "rare", "epic", "legendary", "anomalous"][clampi(difficulty - 1, 0, 4)]
	var item := generate(rng, {"base": row["base"], "level": level, "quality": quality})
	item["name"] = row["name"]
	item["unique"] = true
	item["relic_theme"] = theme
	GenUtil.merge_mods(item["mods"], row["mods"])
	item["flavor"] = "A trophy of a dangerous expedition. Reforge it with a master's core."
	item["flavor_message"] = {"key": "item.relic.flavor"}
	return item


static func trophy(base: String, level: int) -> Dictionary:
	return {"uid": 0, "base": base, "name": "Master's Core" if base == "master_core" else "Colossus Antler",
		"unique": true, "category": "resource", "slot": "none", "quality": "rare", "level": level,
		"value": 60 + 8 * level, "stats": {}, "mods": {}, "material": "ancient_alloy",
		"flavor": "A rare component for forging expedition relics.", "flavor_message": {"key": "item.trophy.flavor"}}


static func describe(item: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append(Loc.t("gen.item.describe.level", {"quality": {"table": "items/qualities", "id": str(item.get("quality", "common")), "en": str(item.get("quality", "common")).capitalize()}, "level": int(item.get("level", 1))}))
	if str(item.get("category", "")) != "resource":
		lines.append(Loc.t("gear.condition") % [roundi(float(item.get("condition", 100))), int(item.get("upgrade", 0))])
	var stats: Dictionary = item.get("stats", {})
	for key: Variant in stats.keys():
		if key in ["kind", "projectile"]:
			continue
		lines.append(Loc.t("%s: %s") % [_label("stat.", str(key), str(key).replace("_", " ").capitalize()), str(stats[key])])
	var mods: Dictionary = item.get("mods", {})
	for key: Variant in mods.keys():
		var amount := float(mods[key])
		var sign := "+" if amount >= 0.0 else ""
		lines.append("%s%s %s" % [sign, str(snappedf(amount, 0.01)), _label("mod.", str(key), str(key).replace("_", " "))])
	lines.append(Loc.generated(item, "flavor"))
	return lines


## Display label for a stat / modifier id: catalog key "<prefix><id>", English fallback.
static func _label(prefix: String, id: String, english: String) -> String:
	var key := prefix + id
	var text := Loc.t(key)
	return english if text == key else text
