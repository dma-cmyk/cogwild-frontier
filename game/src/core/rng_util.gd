class_name RngUtil
extends RefCounted
## Deterministic random helpers. Everything procedural derives its RandomNumberGenerator from the
## world seed plus a salt, so the same seed always rebuilds the same world, NPCs, items and looks.
## Integer math stays below 2^62 so GDScript's 64-bit ints never overflow.

const MASK31 := 0x7FFFFFFF


static func _m(h: int) -> int:
	h = h & MASK31
	h = ((h >> 16) ^ h) * 0x45d9f3b & MASK31
	h = ((h >> 16) ^ h) * 0x45d9f3b & MASK31
	return (h >> 16) ^ h


## Stable 31-bit hash of a list of ints/strings (same result on every run and platform).
static func hash_parts(parts: Array) -> int:
	var h := 0x2545F491
	for p: Variant in parts:
		var v: int = p if p is int else str(p).hash()
		h = _m(h ^ _m(v & MASK31) ^ _m((v >> 31) & MASK31))
	return h


## New generator seeded from the parts, e.g. RngUtil.make([world_seed, "npc", 12]).
static func make(parts: Array) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash_parts(parts)
	return rng


## Deterministic value in [0, 1) for integer coordinates (world generation).
static func hash01(seed: int, x: int, y: int, salt: int = 0) -> float:
	var h := _m((seed & MASK31) ^ _m((x * 374761393 + salt * 668265263) & MASK31))
	h = _m(h ^ ((y * 1274126177) & MASK31))
	return float(h & 0xFFFFFF) / 16777216.0


static func pick(rng: RandomNumberGenerator, arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[rng.randi_range(0, arr.size() - 1)]


## Weighted choice from an Array of Dictionaries holding a numeric weight field.
static func weighted_pick(rng: RandomNumberGenerator, items: Array, weight_key: String = "weight") -> Variant:
	var total := 0.0
	for it: Dictionary in items:
		total += maxf(0.0, float(it.get(weight_key, 1.0)))
	if total <= 0.0:
		return pick(rng, items)
	var r := rng.randf() * total
	for it: Dictionary in items:
		r -= maxf(0.0, float(it.get(weight_key, 1.0)))
		if r < 0.0:
			return it
	return items.back()


## Weighted choice of a key from {key: weight}.
static func weighted_key(rng: RandomNumberGenerator, weights: Dictionary) -> Variant:
	var total := 0.0
	for k: Variant in weights:
		total += maxf(0.0, float(weights[k]))
	if total <= 0.0:
		return pick(rng, weights.keys())
	var r := rng.randf() * total
	for k: Variant in weights:
		r -= maxf(0.0, float(weights[k]))
		if r < 0.0:
			return k
	return weights.keys().back()


static func chance(rng: RandomNumberGenerator, p: float) -> bool:
	return rng.randf() < p


static func shuffle(rng: RandomNumberGenerator, arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = t


## Random colour variation around a base colour (hue/sat/value jitter), used for palettes.
static func vary_color(rng: RandomNumberGenerator, base: Color, h: float = 0.02, s: float = 0.08, v: float = 0.08) -> Color:
	var c := Color.from_hsv(
		fposmod(base.h + rng.randf_range(-h, h), 1.0),
		clampf(base.s + rng.randf_range(-s, s), 0.0, 1.0),
		clampf(base.v + rng.randf_range(-v, v), 0.0, 1.0))
	return c
