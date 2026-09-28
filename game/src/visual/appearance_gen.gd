class_name AppearanceGen
extends RefCounted
## Deterministic, JSON-safe appearance DNA. All variation comes from the caller's RNG.

## Playable race ids from data/races/races.json.
static func race_ids() -> Array[String]:
	var result: Array[String] = []
	for race: Dictionary in DB.entries("races"):
		if bool(race.get("playable", true)):
			result.append(str(race.get("id", "")))
	return result

const GENDERS: Array[String] = ["female", "male", "nonbinary"]
const BODY_TYPES: Array[String] = ["slim", "average", "stocky", "tall"]
const FACES: Array[String] = ["round", "long", "square"]
const HAIR: Array[String] = ["short", "long", "ponytail", "bun", "mohawk", "bald", "braids", "wild"]
const FACIAL_HAIR: Array[String] = ["none", "beard", "mustache"]
const OUTFITS: Array[String] = ["tunic", "robe", "coat", "overalls", "leathers", "dress", "rags"]
const ARMOR: Array[String] = ["none", "leather", "chain", "plate", "coat"]
const HEADGEAR: Array[String] = ["none", "hood", "cap", "helmet", "goggles", "wide_hat", "bandana", "circlet"]
const WEAPONS: Array[String] = ["none", "sword", "axe", "spear", "bow", "crossbow", "hammer", "mace", "dagger", "staff", "rifle", "pistol", "wrench", "pickaxe", "hoe", "torch"]
const OFFHANDS: Array[String] = ["none", "shield", "lantern", "book", "buckler"]
const ACCESSORIES: Array[String] = ["none", "scarf", "backpack", "cape", "satchel", "pauldron"]
const SCARS: Array[String] = ["none", "cheek", "eye"]
const STYLES: Array[String] = ["frontier", "bandit", "ancient", "merchant", "neutral"]
const ROBOT_ARCHETYPES: Array[String] = ["work_bot", "walker", "sentry", "turret", "hauler"]
const DRONE_ARCHETYPES: Array[String] = ["scout_drone", "repair_drone", "war_drone"]
const AIRSHIP_ARCHETYPES: Array[String] = ["cargo_airship", "trader_airship", "raider_airship", "explorer_airship"]

static func _doc() -> Dictionary:
	if DB != null:
		var value: Variant = DB.raw("generation/appearance")
		if value is Dictionary:
			return value
	return {}

static func _palette(style: String, faction_color: Color) -> Dictionary:
	var doc := _doc()
	var palettes: Dictionary = doc.get("palettes", {})
	var p: Dictionary = palettes.get(style, palettes.get("neutral", {}))
	var primary := faction_color if faction_color != Color.TRANSPARENT and faction_color != Color.WHITE else Color(str(p.get("primary", "#8a6a4a")))
	return {"primary": ("#" + primary.to_html(false)).to_lower(), "secondary": str(p.get("secondary", "#8d8f86")), "accent": str(p.get("accent", "#3f8f8a")), "wood": str(p.get("wood", "#6b5138")), "glow": str(p.get("glow", "#8ce0d5"))}

static func _pick(rng: RandomNumberGenerator, values: Array, fallback: String) -> String:
	return str(values[rng.randi_range(0, values.size() - 1)]) if not values.is_empty() else fallback

static func _color_pick(rng: RandomNumberGenerator, values: Array, fallback: String) -> String:
	if values.is_empty():
		return fallback
	return str(values[rng.randi_range(0, values.size() - 1)])

static func character(rng: RandomNumberGenerator, race: String, role: String, faction_style: String, faction_color: Color, gender: String = "") -> Dictionary:
	var r := race if DB.has_def("races", race) else "human"
	var style := faction_style if STYLES.has(faction_style) else "neutral"
	var doc := _doc()
	var roles: Dictionary = doc.get("roles", {})
	var role_data: Dictionary = roles.get(role, {})
	var races: Dictionary = doc.get("races", {})
	var race_data: Dictionary = races.get(r, {})
	var palette := _palette(style, faction_color)
	var g := gender if GENDERS.has(gender) else _pick(rng, GENDERS, "nonbinary")
	var bt := _pick(rng, BODY_TYPES, "average")
	if r in ["stoutkin", "minotaur", "oni", "goblin", "gnome", "halfling"]:
		bt = "stocky" if rng.randf() < 0.72 else "average"
	elif r in ["sylvan", "lizardfolk"]:
		bt = "tall" if rng.randf() < 0.58 else "slim"
	elif r in ["centaur", "orc"]:
		bt = "tall" if rng.randf() < 0.78 else "average"
	elif r in ["harpy", "tengu", "kobold"]:
		bt = "slim" if rng.randf() < 0.68 else "average"
	var outfit := str(role_data.get("outfit", "tunic"))
	if not OUTFITS.has(outfit): outfit = "tunic"
	var headgear := str(role_data.get("headgear", "none"))
	if not HEADGEAR.has(headgear): headgear = "none"
	var accessory := str(role_data.get("accessory", "none"))
	if not ACCESSORIES.has(accessory): accessory = "none"
	var weapon := str(role_data.get("weapon", "none"))
	if not WEAPONS.has(weapon): weapon = "none"
	var offhand := str(role_data.get("offhand", "none"))
	if not OFFHANDS.has(offhand): offhand = "none"
	var skin := _color_pick(rng, race_data.get("skins", []), "#d09a78")
	var hair_color := _color_pick(rng, race_data.get("hair", []), "#3c2922")
	var hair := _pick(rng, HAIR, "short")
	if r == "stoutkin" and rng.randf() < 0.7: hair = "short"
	var facial := "beard" if r in ["stoutkin"] and g != "female" and rng.randf() < 0.65 else "none"
	if g == "male" and rng.randf() < 0.18: facial = "mustache"
	return {"kind":"character", "seed":rng.randi(), "race":r, "gender":g, "body_type":bt,
		"height":rng.randf_range(0.9, 1.1), "skin":skin, "face":_pick(rng, FACES, "round"),
		"eye_color":_color_pick(rng, ["#2c4b62", "#4d7d52", "#7a4c36", "#40305f"], "#2c4b62"),
		"hair":hair, "hair_color":hair_color, "facial_hair":facial, "outfit":outfit,
		"outfit_color":palette.primary, "outfit_accent":palette.secondary, "armor":_armor_for_role(role),
		"headgear":headgear, "weapon":weapon, "offhand":offhand, "accessory":accessory,
		"scar":_pick(rng, SCARS if rng.randf() < 0.18 else ["none"], "none"),
		"faction_style":style, "faction_color":palette.primary}

static func _armor_for_role(role: String) -> String:
	if role in ["guard", "mercenary", "commander", "bandit_captain"]: return "plate" if role == "commander" else "leather"
	if role in ["bandit", "bandit_archer"]: return "leather"
	return "none"

static func robot(rng: RandomNumberGenerator, archetype: String, faction_style: String, faction_color: Color) -> Dictionary:
	var a := archetype if ROBOT_ARCHETYPES.has(archetype) else "work_bot"
	var style := faction_style if STYLES.has(faction_style) else "neutral"
	var p := _palette(style, faction_color)
	var eye: String = "#57caff" if style == "frontier" else ("#ff6a2a" if style == "ancient" else str(p.get("glow", "#8ce0d5")))
	var chassis := "tall" if a == "walker" else ("barrel" if a == "sentry" else "boxy")
	var legs := "biped" if a == "walker" else ("treads" if a == "hauler" else "none" if a == "turret" else "wheels")
	var sensor := "visor" if a == "walker" else ("dome" if a == "turret" else "mono_eye")
	var weapon := "cannon" if a == "sentry" else ("gatling" if a == "walker" else ("claw" if a == "work_bot" else "none"))
	return {"kind":"robot", "seed":rng.randi(), "archetype":a, "chassis":chassis, "legs":legs,
		"armor":"heavy" if a == "walker" else ("medium" if a in ["sentry", "hauler"] else "light"),
		"sensor":sensor, "weapon":weapon, "utility_module":"crane_arm" if a == "hauler" else ("tool_arm" if a == "work_bot" else "antenna"),
		"paint":p.primary, "paint_secondary":p.secondary, "eye_color":eye, "wear":rng.randf_range(0.05, 0.35),
		"scale":rng.randf_range(0.96, 1.04), "faction_style":style, "faction_color":p.primary}

static func drone(rng: RandomNumberGenerator, archetype: String, faction_style: String, faction_color: Color) -> Dictionary:
	var a := archetype if DRONE_ARCHETYPES.has(archetype) else "scout_drone"
	var style := faction_style if STYLES.has(faction_style) else "neutral"
	var p := _palette(style, faction_color)
	return {"kind":"drone", "seed":rng.randi(), "archetype":a, "frame":"quad" if a == "scout_drone" else ("orb" if a == "repair_drone" else "disc"),
		"rotors":4 if a != "war_drone" else 2, "sensor":"twin_lens" if a == "scout_drone" else "mono_eye",
		"weapon":"repair_beam" if a == "repair_drone" else ("blaster" if a == "war_drone" else "none"),
		"paint":p.primary, "eye_color":"#59d8ff" if style == "frontier" else p.glow,
		"wear":rng.randf_range(0.0, 0.28), "faction_style":style, "faction_color":p.primary}

static func airship(rng: RandomNumberGenerator, archetype: String, faction_style: String, faction_color: Color) -> Dictionary:
	var a := archetype if AIRSHIP_ARCHETYPES.has(archetype) else "cargo_airship"
	var style := faction_style if STYLES.has(faction_style) else "neutral"
	var p := _palette(style, faction_color)
	return {"kind":"airship", "seed":rng.randi(), "archetype":a, "hull":"barge" if a == "cargo_airship" else ("clipper" if a == "raider_airship" else "skiff"),
		"balloon":"cigar" if a != "explorer_airship" else "segmented", "balloon_pattern":"stripes" if a != "explorer_airship" else "panels",
		"engine":"prop_pair" if a != "explorer_airship" else "turbine", "wing":"fins" if a != "trader_airship" else "sails",
		"gondola":"open_deck" if a == "cargo_airship" else ("tower" if a == "raider_airship" else "cabin"),
		"weapon":"cannons" if a == "raider_airship" else "none", "cargo_module":"crates" if a == "cargo_airship" else "none",
		"paint":p.primary, "balloon_color":p.secondary, "balloon_color2":p.primary, "banner":p.accent,
		"wear":rng.randf_range(0.02, 0.25), "scale":rng.randf_range(0.95, 1.05), "faction_style":style, "faction_color":p.primary}
