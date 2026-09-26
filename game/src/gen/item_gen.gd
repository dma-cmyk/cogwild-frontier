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
		shifted["weight"] = maxf(0.01, float(row.get("weight", 1.0)) * (1.0 + clamped_luck * tier * 0.22))
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

static func _format_name(rng: RandomNumberGenerator, base: Dictionary, material: Dictionary, quality: Dictionary, affixes: Array, unique: bool) -> String:
	if unique:
		var names: Array[String] = ANOMALOUS_NAMES
		return names[rng.randi_range(0, names.size() - 1)]
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
		return "Worn %s %s" % [material_name, noun]
	if quality_id == "crude":
		return "Rusty %s" % noun
	var result := (prefix + " " if prefix != "" else "") + material_name + " " + noun
	if suffix != "":
		result += " " + suffix
	return result

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
			stats[str(key)] = snappedf(float(value) * scale * variance, 0.01)
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
	var item_name := _format_name(rng, base, material, quality, affixes, unique)
	var appearance := {
		"kind": "item", "seed": rng.randi(), "shape": str(base.get("icon", "gear")),
		"primary": str(material.get("color", "#777b80")), "secondary": str(material.get("secondary", "#3b4148")),
		"accent": str(quality.get("color", "#e9dcc0")), "glow": float(quality.get("glow", 0.0)),
		"variant": rng.randi_range(0, 3), "engraved": tier >= 4 or unique, "worn": rng.randf_range(0.05, 0.55) if tier < 3 else rng.randf_range(0.0, 0.22)
	}
	var value := maxi(1, int(round(float(base.get("value", 1)) * float(material.get("value_mult", 1.0)) * float(quality.get("value_mult", 1.0)) * (1.0 + 0.1 * level))))
	var flavor := _flavor(base, material, quality, unique)
	return {"uid": 0, "base": str(base.get("id", "")), "name": item_name, "category": str(base.get("category", "resource")), "slot": str(base.get("slot", "none")), "quality": quality_id, "level": level, "material": str(material.get("id", "scrap")), "stats": stats, "mods": mods, "value": value, "flavor": flavor, "unique": unique, "visual": str(base.get("visual", "")), "appearance": appearance, "affixes": affixes}

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

static func loot(rng: RandomNumberGenerator, level: int, luck: float, count: int) -> Array:
	var result: Array = []
	for _i in range(maxi(0, count)):
		result.append(generate(rng, {"level": level, "luck": luck, "source": "loot"}))
	return result

static func describe(item: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("%s · Level %d" % [str(item.get("quality", "common")).capitalize(), int(item.get("level", 1))])
	var stats: Dictionary = item.get("stats", {})
	for key: Variant in stats.keys():
		if key in ["kind", "projectile"]:
			continue
		lines.append("%s: %s" % [str(key).replace("_", " ").capitalize(), str(stats[key])])
	var mods: Dictionary = item.get("mods", {})
	for key: Variant in mods.keys():
		var amount := float(mods[key])
		var sign := "+" if amount >= 0.0 else ""
		lines.append("%s%s %s" % [sign, str(snappedf(amount, 0.01)), str(key).replace("_", " ")])
	lines.append(str(item.get("flavor", "")))
	return lines
