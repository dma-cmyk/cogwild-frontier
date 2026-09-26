class_name GenUtil
extends RefCounted
## Shared deterministic helpers for Lorewright generators.

const STAT_KEYS: Array[String] = [
	"max_hp", "max_hp_pct", "armor", "move_speed_pct", "work_speed_pct", "gather_speed_pct",
	"build_speed_pct", "farm_speed_pct", "carry", "melee_damage_pct", "ranged_damage_pct",
	"attack_speed_pct", "accuracy", "crit_chance", "vision", "night_vision", "retreat_bias",
	"loot_luck", "energy_max", "energy_regen_pct", "hp_regen_pct", "xp_rate_pct", "trade_pct",
	"food_use_pct"
]

static func pick(rng: RandomNumberGenerator, values: Array) -> Variant:
	if values.is_empty():
		return ""
	return values[rng.randi_range(0, values.size() - 1)]

static func weighted(rng: RandomNumberGenerator, values: Array, key: String = "weight") -> Dictionary:
	var total := 0.0
	for value: Variant in values:
		if value is Dictionary:
			total += maxf(0.0, float((value as Dictionary).get(key, 1.0)))
	if total <= 0.0:
		return values[0] as Dictionary if not values.is_empty() else {}
	var needle := rng.randf() * total
	for value: Variant in values:
		var row: Dictionary = value as Dictionary
		needle -= maxf(0.0, float(row.get(key, 1.0)))
		if needle < 0.0:
			return row
	return values.back() as Dictionary

static func raw(key: String, fallback: Variant) -> Variant:
	if DB == null:
		return fallback
	var value: Variant = DB.raw(key)
	return fallback if value == null else value

static func entries(table: String) -> Array:
	if DB == null:
		return []
	return DB.entries(table)

static func safe_def(table: String, id: String) -> Dictionary:
	if DB == null:
		return {}
	return DB.get_def(table, id)

static func valid_mods(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in source.keys():
		if STAT_KEYS.has(str(key)):
			result[str(key)] = source[key]
	return result

static func merge_mods(target: Dictionary, source: Dictionary) -> void:
	for key: Variant in source.keys():
		var name := str(key)
		if not STAT_KEYS.has(name):
			continue
		target[name] = float(target.get(name, 0.0)) + float(source[key])

static func fill_template(template: String, values: Dictionary) -> String:
	var output := template
	for key: Variant in values.keys():
		output = output.replace("{" + str(key) + "}", str(values[key]))
	return output

static func clamp_int(value: int, low: int, high: int) -> int:
	return maxi(low, mini(high, value))
static func shuffle(rng: RandomNumberGenerator, values: Array) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var temporary: Variant = values[index]
		values[index] = values[swap_index]
		values[swap_index] = temporary
