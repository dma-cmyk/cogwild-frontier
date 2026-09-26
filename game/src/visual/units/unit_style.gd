class_name UnitStyle
extends RefCounted
## Shared colour vocabulary for unit art: safe hex parsing, faction materials and deterministic
## per-DNA jitter. Builders take colours from the DNA first and fall back to these tables so a
## bandit's leather is always bandit leather and a frontier soldier always gets steel + gold trim.

const ACCENTS := {
	"frontier": "#d9b04c", "bandit": "#8c4a2a", "ancient": "#ff6a2a",
	"merchant": "#d9b04c", "neutral": "#3f8f8a",
}
const LEATHERS := {
	"frontier": "#8a5a34", "bandit": "#4a3426", "ancient": "#3b3f48",
	"merchant": "#8a6a4a", "neutral": "#6b5138",
}
const METALS := {
	"frontier": "#c2ccd8", "bandit": "#9a8b7a", "ancient": "#a07a4a",
	"merchant": "#c8c0ad", "neutral": "#b0b3ab",
}
const DARK_METALS := {
	"frontier": "#5e6b80", "bandit": "#4a4038", "ancient": "#5b6470",
	"merchant": "#6a6a5c", "neutral": "#5a5d57",
}
const WOODS := {
	"frontier": "#8a5a34", "bandit": "#6a4a32", "ancient": "#4a4a4a",
	"merchant": "#96683d", "neutral": "#7a5a3c",
}
const GLOWS := {
	"frontier": "#5bc8ff", "bandit": "#ff754a", "ancient": "#ff6a2a",
	"merchant": "#ffd66b", "neutral": "#8ce0d5",
}
const CLOTHS := {
	"frontier": "#e9dcc0", "bandit": "#7a6a55", "ancient": "#8d8f86",
	"merchant": "#efe3c2", "neutral": "#b9ab90",
}

const EYE_DARK := Color(0.128, 0.105, 0.131)
const MOUTH := Color(0.40, 0.20, 0.19)
const HIGHLIGHT := Color(0.98, 0.97, 0.94)
const STRAW := Color(0.85, 0.71, 0.36)
const GOLD := Color(0.85, 0.69, 0.30)


static func col(value: Variant, fallback: String) -> Color:
	var s := str(value).strip_edges()
	if s.is_empty():
		s = fallback
	if not s.begins_with("#"):
		s = "#" + s
	if not Color.html_is_valid(s):
		s = fallback
	return Color(s)


static func _table(table: Dictionary, style: String) -> Color:
	return Color(str(table.get(style, table["neutral"])))


static func accent(style: String) -> Color:
	return _table(ACCENTS, style)


static func leather(style: String) -> Color:
	return _table(LEATHERS, style)


static func metal(style: String) -> Color:
	return _table(METALS, style)


static func dark_metal(style: String) -> Color:
	return _table(DARK_METALS, style)


static func wood(style: String) -> Color:
	return _table(WOODS, style)


static func glow_color(style: String) -> Color:
	return _table(GLOWS, style)


static func cloth(style: String) -> Color:
	return _table(CLOTHS, style)


## Deterministic 0..1 value from a DNA seed and a salt (no global RNG).
static func rand01(seed_value: int, salt: int) -> float:
	return float(RngUtil.hash_parts([seed_value, salt]) & 0xFFFFFF) / 16777216.0


static func rand_range(seed_value: int, salt: int, from: float, to: float) -> float:
	return from + (to - from) * rand01(seed_value, salt)


static func pick_index(seed_value: int, salt: int, count: int) -> int:
	if count <= 1:
		return 0
	return int(rand01(seed_value, salt) * float(count)) % count


## Slightly shifted tone so neighbouring parts of the same material read apart.
static func shade(base: Color, amount: float) -> Color:
	if amount >= 0.0:
		return base.lightened(amount)
	return base.darkened(-amount)
