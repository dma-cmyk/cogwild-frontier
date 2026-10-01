class_name Giants
extends RefCounted
## A master guards its arena; a wild beast has a home territory and cannot enter colony land.
## Persistent intent, phase and casts live on Unit.named, which the existing save path owns.

const COLONY_SAFE := 42.0
const LEASH := 30.0
const PATH_PAD := 10

var w: World
var _nav := AStarGrid2D.new()

func _init(world: World) -> void:
	w = world
	_nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER


func make_master(theme: String, difficulty: int, level: int, pos: Vector2) -> Unit:
	var u := CharacterFactory.make_machine(w, "dungeon_master", "machines" if theme == "machines" else "bandits", pos, level)
	u.name = Loc.t("Vault Master")
	u.dna["art_id"] = "dungeon_master"
	u.dna["scale"] = 1.0 + difficulty * 0.06
	u.named = {"dungeon_boss": true, "giant": true, "phase": 1, "theme": theme,
		"abilities": ["earthshatter", "call_guardians"],
		"stat_mult": {"max_hp": 1.4 + difficulty * 0.45, "damage": 1.0 + difficulty * 0.10}}
	u.guard_pos = pos
	u.recompute_stats()
	u.hp = float(u.stats["max_hp"])
	return u


func spawn_beast(pos: Vector2, level: int = 5) -> Unit:
	var u := CharacterFactory.make_machine(w, "wild_colossus", "beasts", pos, level)
	u.name = Loc.t("Mossback Colossus")
	u.dna["kind"] = "beast"
	u.dna["art_id"] = "wild_colossus"
	u.named = {"giant": true, "roaming": true, "phase": 1, "mood": "wander", "abilities": ["earthshatter"]}
	u.guard_pos = pos
	u.recompute_stats()
	u.hp = float(u.stats["max_hp"])
	return u


func on_new_day() -> void:
	if not w.dungeons.enabled() or w.day < 2 or bool(w.counters.get("beast_spawned", false)):
		return
	var rng := RngUtil.make([w.seed, "wild_colossus"])
	for attempt in 12:
		var tile := w.dungeons._pick_location(rng)
		if tile == Dungeons.NOWHERE:
			continue
		var pos := Vector2(tile) + Vector2(0.5, 0.5)
		if pos.distance_to(w.home_pos()) < 85.0 or not fits(pos, 1.05) or near_colony(pos):
			continue
		spawn_beast(pos)
		w.counters["beast_spawned"] = true
		return


func near_colony(pos: Vector2) -> bool:
	for b: Building in w.buildings.values():
		if b.faction == "player" and pos.distance_to(b.center()) < COLONY_SAFE:
			return true
	return false


func think(u: Unit) -> void:
	if u.named.has("cast"):
		return
	var roaming := bool(u.named.get("roaming", false))
	var target := w.get_unit(u.target_id)
	var returning := str(u.named.get("mood", "")) == "return"
	var leash := LEASH if roaming else 8.0
	if target != null and (not target.alive or target.pos.distance_to(u.guard_pos) > leash
			or target.pos.distance_to(u.pos) > 18.0 or (roaming and near_colony(target.pos))):
		u.target_id = -1
		u.named["mood"] = "return"
		w.stop_unit(u)
		returning = true
	if returning:
		u.target_id = -1
		if u.pos.distance_to(u.guard_pos) < 2.5:
			u.named["mood"] = "wander"
		elif not u.moving:
			w.move_unit(u, u.guard_pos)
		return
	if u.target_id >= 0:
		return
	var enemy := w.combat.acquire(u, 11.0)
	if enemy != null and enemy.pos.distance_to(u.guard_pos) <= leash and (not roaming or not near_colony(enemy.pos)):
		u.named["mood"] = "chase"
		u.target_id = enemy.id
		return
	if not roaming or u.moving or w.tick_count < int(u.named.get("next_wander", 0)):
		return
	u.named["next_wander"] = w.tick_count + 100
	var rng := RngUtil.make([w.seed, u.id, w.tick_count / 100])
	for attempt in 8:
		var a := rng.randf() * TAU
		var dest := u.guard_pos + Vector2(cos(a), sin(a)) * rng.randf_range(4.0, 18.0)
		if not near_colony(dest) and fits(dest, u.body_radius()) and w.move_unit(u, dest):
			return


## Circle-versus-tile footprint: a giant cannot cut through a wall or a one-tile doorway.
func fits(pos: Vector2, radius: float) -> bool:
	var lo := Vector2i(floori(pos.x - radius), floori(pos.y - radius))
	var hi := Vector2i(floori(pos.x + radius), floori(pos.y + radius))
	for z in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var nearest := Vector2(clampf(pos.x, x, x + 1.0), clampf(pos.y, z, z + 1.0))
			if nearest.distance_squared_to(pos) < radius * radius and not w.is_walkable(Vector2i(x, z)):
				return false
	return true


## Bounded local search: giants only walk their territory/arena, not across the whole map.
func path(u: Unit, destination: Vector2) -> PackedVector2Array:
	var start := u.tile()
	var goal := Vector2i(floori(destination.x), floori(destination.y))
	var out := PackedVector2Array()
	if start.distance_to(goal) > LEASH * 2.0:
		return out
	var lo := Vector2i(mini(start.x, goal.x), mini(start.y, goal.y)) - Vector2i.ONE * PATH_PAD
	var hi := Vector2i(maxi(start.x, goal.x), maxi(start.y, goal.y)) + Vector2i.ONE * PATH_PAD
	var region := Rect2i(lo, hi - lo + Vector2i.ONE)
	if _nav.region != region:
		_nav.region = region
		_nav.update()
	var roaming := bool(u.named.get("roaming", false))
	var radius := u.body_radius()
	for z in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var p := Vector2(x + 0.5, z + 0.5)
			_nav.set_point_solid(Vector2i(x, z), not fits(p, radius) or (roaming and near_colony(p)))
	if _nav.is_point_solid(start):
		return out
	for tile: Vector2i in _nav.get_id_path(start, goal, true):
		out.append(Vector2(tile) + Vector2(0.5, 0.5))
	return out
