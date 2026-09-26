class_name NameGen
extends RefCounted
## Deterministic names for settlers, locations, factions, machines, and airships.

static func _names_doc() -> Dictionary:
	return GenUtil.raw("generation/names", {"sets": {}}) as Dictionary

static func person(rng: RandomNumberGenerator, race: String, gender: String) -> Dictionary:
	var doc := _names_doc()
	var sets: Dictionary = doc.get("sets", {})
	var chosen: Dictionary = sets.get(race, sets.get("human", {}))
	var gender_key := gender if gender in ["female", "male", "neutral"] else "neutral"
	var given_values: Array = chosen.get(gender_key, chosen.get("neutral", ["Ash"]))
	var family_values: Array = chosen.get("family", ["Veyr"])
	var given := str(GenUtil.pick(rng, given_values))
	var family := str(GenUtil.pick(rng, family_values))
	return {"given": given, "family": family, "full": given + " " + family}

static func place(rng: RandomNumberGenerator, kind: String) -> String:
	var doc: Dictionary = GenUtil.raw("generation/places", {}) as Dictionary
	var parts: Dictionary = doc.get(kind, doc.get("region", {}))
	var prefix := str(GenUtil.pick(rng, parts.get("prefix", ["New"])))
	var core := str(GenUtil.pick(rng, parts.get("core", ["Haven"])))
	var suffix := str(GenUtil.pick(rng, parts.get("suffix", ["Reach"])))
	return "%s %s %s" % [prefix, core, suffix]

static func faction(rng: RandomNumberGenerator, type: String) -> String:
	var rows := GenUtil.entries("factions")
	var options: Array = []
	for row: Variant in rows:
		var faction_def: Dictionary = row as Dictionary
		if str(faction_def.get("type", "")) == type:
			options.append_array(faction_def.get("name_patterns", []))
	if options.is_empty():
		options = ["The Open Road"]
	return str(GenUtil.pick(rng, options))

static func squad(index: int) -> String:
	var doc := _names_doc()
	var squads: Array = doc.get("squads", ["Alpha", "Bravo", "Cinder"])
	if squads.is_empty():
		return "Alpha"
	return str(squads[posmod(index, squads.size())])

static func machine(rng: RandomNumberGenerator, archetype: String) -> String:
	var doc := _names_doc()
	var machines: Dictionary = doc.get("machines", {})
	var prefixes: Array = machines.get(archetype, machines.get("work_bot", ["KX"]))
	var prefix := str(GenUtil.pick(rng, prefixes))
	var number := rng.randi_range(1, 99)
	var nickname_values: Array = doc.get("nicknames", ["Rivet"])
	var nickname := str(GenUtil.pick(rng, nickname_values))
	return "%s-%02d \"%s\"" % [prefix, number, nickname]

static func airship(rng: RandomNumberGenerator) -> String:
	var doc := _names_doc()
	var ships: Array = doc.get("airships", ["The Wandering Gull"])
	return str(GenUtil.pick(rng, ships))
