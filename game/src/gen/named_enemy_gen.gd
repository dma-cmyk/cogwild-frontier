class_name NamedEnemyGen
extends RefCounted
## Deterministic hand-authored elite enemies and their loot.

static func _faction_for(base: String, requested: String) -> String:
	if requested != "":
		return requested
	if base.begins_with("machine") or base in ["sentinel", "machine_warden", "rust_colossus"]:
		return "machine"
	return "bandit"

static func _parts(rng: RandomNumberGenerator, faction: String) -> Dictionary:
	var doc: Dictionary = GenUtil.raw("generation/named", {}) as Dictionary
	return doc.get(faction, doc.get("bandit", {})) as Dictionary

static func _trait_ids(rng: RandomNumberGenerator, tier: int) -> Array:
	var candidates: Array = []
	for value: Variant in GenUtil.entries("traits"):
		var trait_def: Dictionary = value as Dictionary
		if str(trait_def.get("polarity", "")) != "bad":
			candidates.append(str(trait_def.get("id", "")))
	var selected: Array = []
	var target := mini(2 + tier, candidates.size())
	for _i in range(target):
		if candidates.is_empty():
			break
		var index := rng.randi_range(0, candidates.size() - 1)
		selected.append(candidates[index])
		candidates.remove_at(index)
	return selected

static func _abilities(rng: RandomNumberGenerator, tier: int) -> Array:
	var rows := GenUtil.entries("generation/abilities")
	var ids: Array = []
	for value: Variant in rows:
		ids.append(str((value as Dictionary).get("id", "")))
	GenUtil.shuffle(rng, ids)
	return ids.slice(0, mini(tier + 1, ids.size()))

static func _equipment(rng: RandomNumberGenerator, base: String, level: int, tier: int) -> Dictionary:
	var slots: Dictionary = {"weapon": null, "armor": null, "gadget": null}
	var weapon := "steel_sword"
	if base.begins_with("machine") or base in ["sentinel", "machine_warden", "rust_colossus"]:
		weapon = "rifle" if rng.randf() < 0.5 else "hammer"
	elif base in ["bandit_archer", "sharpshooter"]:
		weapon = "crossbow"
	elif base in ["bandit_captain", "warlord"]:
		weapon = "steel_sword"
	else:
		weapon = "axe" if rng.randf() < 0.3 else "sword"
	var quality := "rare" if tier >= 3 else ("fine" if tier == 2 else "common")
	slots["weapon"] = ItemGen.generate(rng, {"base": weapon, "level": level, "quality": quality, "luck": float(tier)})
	var armor := "plate_armor" if tier >= 3 else ("chain_mail" if tier == 2 else "leather_vest")
	slots["armor"] = ItemGen.generate(rng, {"base": armor, "level": level, "quality": quality})
	var gadget := "sensor_array" if base.begins_with("machine") else ("scope" if rng.randf() < 0.5 else "lantern")
	slots["gadget"] = ItemGen.generate(rng, {"base": gadget, "level": level, "quality": "fine" if tier >= 2 else "common"})
	return slots

static func generate(rng: RandomNumberGenerator, opts: Dictionary) -> Dictionary:
	var base := str(opts.get("base", "bandit_captain"))
	var faction := _faction_for(base, str(opts.get("faction_type", "")))
	var level := maxi(1, int(opts.get("level", 5)))
	var tier := GenUtil.clamp_int(int(opts.get("tier", 1)), 1, 3)
	var parts := _parts(rng, faction)
	var first := str(GenUtil.pick(rng, parts.get("first", ["Red"])))
	var last := str(GenUtil.pick(rng, parts.get("last", ["Rook"])))
	var epithet_values: Array = parts.get("epithets", ["the Unquiet"])
	var epithet_i := rng.randi_range(0, epithet_values.size() - 1)
	var epithet := str(epithet_values[epithet_i])
	var full_name := first + " " + last
	var stat_mult := {"max_hp": snappedf(1.0 + 0.45 * tier, 0.01), "damage": snappedf(1.0 + 0.3 * tier, 0.01)}
	var loot_count := 2 + tier
	var loot := ItemGen.loot(rng, level, 0.3 * tier, loot_count)
	var bio := "%s is %s, a tier-%d threat whose trophies still smell of the road." % [full_name, epithet, tier]
	return {"name": first, "epithet": epithet, "epithet_i": epithet_i, "epithet_message": {"key": "gen.enemy.epithet.%s.%d" % [faction, epithet_i]}, "full_name": full_name, "base": base, "level": level, "tier": tier, "traits": _trait_ids(rng, tier), "abilities": _abilities(rng, tier), "equipment": _equipment(rng, base, level, tier), "loot": loot, "stat_mult": stat_mult, "bio": bio, "bio_message": {"key": "gen.enemy.bio", "params": {"name": full_name, "epithet": {"key": "gen.enemy.epithet.%s.%d" % [faction, epithet_i]}, "tier": tier}}}
