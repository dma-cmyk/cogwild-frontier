class_name Building
extends RefCounted
## A placed structure (player buildings and construction sites). Enemy/neutral site structures
## are static generation data (WorldGen sites) and do not use this class.

var id := 0
var type := ""
var faction := "player"
var origin := Vector2i.ZERO
var size := Vector2i.ONE
var rot := 0
var variant := 0
var level := 1
var progress := 1.0  # construction progress 0..1
var hp := 100.0
var needs: Dictionary = {}  # materials still to be hauled to the site
var delivered: Dictionary = {}  # materials on site (for refunds)
var workers: Array = []  # reserved worker ids (builders / operators)
var queue: Array = []  # workshop production queue (archetype ids)
var prod_t := 0.0
var recipe_t := 0.0
var attack_cd := 0.0
var active := false
var active_t := 0.0  # seconds of recent activity (drives visuals)
var name := ""


func def() -> Dictionary:
	return DB.get_def("buildings", type)


func is_built() -> bool:
	return progress >= 1.0


func center() -> Vector2:
	return Vector2(origin) + Vector2(size) * 0.5


func rect() -> Rect2i:
	return Rect2i(origin, size)


func contains_tile(t: Vector2i) -> bool:
	return rect().has_point(t)


func max_hp() -> float:
	return float(def().get("hp", 300)) * (1.0 + 0.25 * (level - 1))


func display_name() -> String:
	var d := def()
	if level > 1:
		for lv: Dictionary in d.get("levels", []):
			if int(lv["level"]) == level:
				return str(lv.get("name", d.get("name", type)))
	return str(d.get("name", type))


## Distance from p to the closest point of the footprint (0 inside).
func distance_to(p: Vector2) -> float:
	var r := Rect2(Vector2(origin), Vector2(size))
	var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
	return q.distance_to(p)


## Walkable tile just in front of the building (south side, +Z), used as work/delivery spot.
func door_tile() -> Vector2i:
	return Vector2i(origin.x + size.x / 2, origin.y + size.y)


func to_dict() -> Dictionary:
	return {"id": id, "type": type, "faction": faction, "origin": [origin.x, origin.y], "size": [size.x, size.y],
		"rot": rot, "variant": variant, "level": level, "progress": progress, "hp": hp, "needs": needs,
		"delivered": delivered, "queue": queue, "prod_t": prod_t, "recipe_t": recipe_t, "name": name,
		"workers": workers, "attack_cd": attack_cd}


static func from_dict(d: Dictionary) -> Building:
	var b := Building.new()
	b.id = int(d["id"])
	b.type = str(d["type"])
	b.faction = str(d.get("faction", "player"))
	b.origin = Vector2i(int(d["origin"][0]), int(d["origin"][1]))
	b.size = Vector2i(int(d["size"][0]), int(d["size"][1]))
	b.rot = int(d.get("rot", 0))
	b.variant = int(d.get("variant", 0))
	b.level = int(d.get("level", 1))
	b.progress = float(d.get("progress", 1.0))
	b.hp = float(d.get("hp", 100.0))
	b.needs = _ints(d.get("needs", {}))
	b.delivered = _ints(d.get("delivered", {}))
	b.queue = d.get("queue", [])
	b.prod_t = float(d.get("prod_t", 0.0))
	b.recipe_t = float(d.get("recipe_t", 0.0))
	b.name = str(d.get("name", ""))
	for wid: Variant in d.get("workers", []):
		b.workers.append(int(wid))
	b.attack_cd = float(d.get("attack_cd", 0.0))
	return b


static func _ints(src: Dictionary) -> Dictionary:
	var out := {}
	for k: String in src:
		out[k] = int(src[k])
	return out
