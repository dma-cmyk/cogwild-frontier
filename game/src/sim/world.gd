class_name World
static var _profile_chunks: bool = OS.get_environment("COGWILD_PROFILE_CHUNKS") == "1"
static func profile_chunks() -> bool:
	return _profile_chunks
## Root of the simulation: map chunks, navigation, fog of war, entities, colony state and the fixed
## tick. Deterministic: the same seed and the same orders give the same results, independent of
## frame rate or time scale (speed = more ticks per frame). The view and HUD only read this state
## and listen to its signals.

signal chunk_ready(key: Vector2i)
signal chunk_changed(key: Vector2i)
signal unit_added(u: Unit)
signal unit_removed(u: Unit)
signal unit_changed(u: Unit)  # look or allegiance changed (equipment, recruitment)
signal building_added(b: Building)
signal building_removed(b: Building)
signal building_changed(b: Building)
signal site_changed(site_id: int)
signal site_removed(site_id: int)
signal notified(n: Dictionary)
signal fx(kind: StringName, pos: Vector3, color: Color)
signal projectile_fired(from: Vector3, to: Vector3, kind: String, flight: float)
signal loot_added(bag: Dictionary)
signal loot_removed(bag_id: int)
signal squads_changed()
signal zones_changed()
signal quests_changed()
signal farm_changed(tile: Vector2i)

const TICK := 0.1
const DAY_TICKS := 2400  # 240 s per day at x1
const S := ChunkData.S
const SAVE_VERSION := 1
const RESOURCES := ["wood", "stone", "ore", "metal", "food", "gold", "energy"]
const MAX_SQUADS := 9


var seed := 0
var gen: WorldGen
var chunks: Dictionary = {}  # Vector2i -> ChunkData
var _chunk_queue: Array[Vector2i] = []
var _pending_mods: Dictionary = {}  # Vector2i -> saved chunk modifications (applied on generation)
var nav := AStarGrid2D.new()
var W := 0  # world width in tiles
var explored := PackedByteArray()
var fog_image: Image
var fog_dirty := true
var explored_count := 0
var chunk_explored: Dictionary = {}  # chunk key -> explored tiles (skips finished chunks in searches)

var units: Dictionary = {}
var unit_list: Array[Unit] = []
var buildings: Dictionary = {}
var squads: Array[Squad] = []
var _crossing_index: Dictionary = {}  # Vector2i tile -> bridge/stairs Building
var sites: Dictionary = {}  # id -> runtime site state
var loot_bags: Dictionary = {}
var zones: Array = []  # {id, type, rect: Rect2i}
var farm: Dictionary = {}  # Vector2i -> {stage, growth, crop}
var res: Dictionary = {}
var armory: Array = []  # unequipped items owned by the colony
var priorities: Dictionary = {"build": 2, "farm": 2, "gather": 2, "haul": 2, "operate": 2}
var company_name := "Frontier Company"
var faction_color := Color("#3a5da8")
var player_unit_id := -1
var hearth_id := -1

var tick_count := 0
var day := 1
var rng := RandomNumberGenerator.new()
var next_id := 1
var notifications: Array = []
var counters: Dictionary = {}  # colony-wide statistics
var hungry := false

var colony: ColonyAI
var combat: Combat
var squad_ai: SquadAI
var factions: FactionAI
var economy: Economy
var diplomacy: Diplomacy
var quests: Quests
var town: Town
var dungeons: Dungeons
var giants: Giants
var gearwork: Gearwork

var _grid: Dictionary = {}  # spatial hash of units: Vector2i cell -> Array[Unit]
const GRID := 8.0


func _init() -> void:
	colony = ColonyAI.new(self)
	combat = Combat.new(self)
	squad_ai = SquadAI.new(self)
	factions = FactionAI.new(self)
	economy = Economy.new(self)
	diplomacy = Diplomacy.new(self)
	quests = Quests.new(self)
	town = Town.new(self)
	dungeons = Dungeons.new(self)
	giants = Giants.new(self)
	gearwork = Gearwork.new(self)
	for r: String in RESOURCES:
		res[r] = 0


## Sets up generation, navigation and fog for a seed (new game or load). Worlds with dungeons
## reserve a block of the grid for the floors (see DungeonZone); old saves keep their whole map.
func setup(p_seed: int, generation_races: Array = [], with_dungeons: bool = false) -> void:
	seed = p_seed
	rng.seed = RngUtil.hash_parts([seed, "sim"])
	gen = WorldGen.new(seed, {}, generation_races, with_dungeons)
	W = gen.max_tile - gen.min_tile
	nav.region = Rect2i(gen.min_tile, gen.min_tile, W, W)
	nav.cell_size = Vector2.ONE
	nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	nav.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	nav.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	nav.update()
	nav.fill_solid_region(nav.region, true)
	explored.resize(W * W)
	explored.fill(0)
	fog_image = Image.create_from_data(W, W, false, Image.FORMAT_L8, explored)


## Breaks the reference cycles between the world and its systems so everything is freed.
func dispose() -> void:
	for sys: Variant in [colony, combat, squad_ai, factions, economy, diplomacy, quests, town, dungeons, giants, gearwork]:
		if sys != null:
			sys.set("w", null)
	colony = null
	combat = null
	squad_ai = null
	factions = null
	economy = null
	diplomacy = null
	quests = null
	town = null
	dungeons = null
	giants = null
	gearwork = null
	units.clear()
	unit_list.clear()
	buildings.clear()
	squads.clear()
	chunks.clear()
	sites.clear()
	loot_bags.clear()
	gen = null


func new_id() -> int:
	next_id += 1
	return next_id - 1


# --- time --------------------------------------------------------------------------------------

func tod() -> float:
	return float(tick_count % DAY_TICKS) / DAY_TICKS


## Clock hour: 0.00-0.75 of the day covers 06:00-20:00, the rest the (shorter) night.
func hour() -> float:
	var t := tod()
	if t < 0.75:
		return 6.0 + t / 0.75 * 14.0
	return fmod(20.0 + (t - 0.75) / 0.25 * 10.0, 24.0)


func night_amount() -> float:
	var h := hour()
	if h >= 12.0:
		return smoothstep(19.0, 21.5, h)
	return 1.0 - smoothstep(4.5, 6.5, h)


func is_night() -> bool:
	return night_amount() > 0.5


# --- chunks & tiles ------------------------------------------------------------------------

func chunk_key(t: Vector2i) -> Vector2i:
	return Vector2i(int(floor(float(t.x) / S)), int(floor(float(t.y) / S)))


func chunk_at_tile(t: Vector2i) -> ChunkData:
	return chunks.get(chunk_key(t))


func ensure_chunk(key: Vector2i) -> ChunkData:
	if chunks.has(key):
		return chunks[key]
	if not gen.chunk_in_bounds(key.x, key.y):
		return null
	var profile := World.profile_chunks()
	var total_start_usec: int = Time.get_ticks_usec() if profile else 0
	var generation_start_usec: int = total_start_usec
	var ch: ChunkData
	if gen.in_zone_chunk(key.x, key.y):
		ch = ChunkData.new(key.x, key.y)
		DungeonZone.fill_chunk(ch, gen.dungeon_zone, dungeons.floor_lookup())
	else:
		ch = gen.generate_chunk(key.x, key.y)
	var generation_usec: int = Time.get_ticks_usec() - generation_start_usec if profile else 0
	if _pending_mods.has(key):
		var m: Dictionary = _pending_mods[key]
		ch.apply_mods(m.get("res", {}), m.get("terrain", {}), m.get("regrow", {}), m.get("height", {}))
		_pending_mods.erase(key)
	chunks[key] = ch
	var setup_start_usec: int = Time.get_ticks_usec() if profile else 0
	# re-apply player building footprints and grown site structures reaching into this chunk
	for b: Building in buildings.values():
		_mark_building_tiles(b, 1, ch)
	for st: Dictionary in sites.values():
		for s: Dictionary in st.get("extra", []):
			_mark_structure(s, ch)
	var setup_usec: int = Time.get_ticks_usec() - setup_start_usec if profile else 0
	var nav_start_usec: int = Time.get_ticks_usec() if profile else 0
	_nav_update_chunk(ch)
	var nav_usec: int = Time.get_ticks_usec() - nav_start_usec if profile else 0
	var sites_start_usec: int = Time.get_ticks_usec() if profile else 0
	for sid: int in ch.site_ids:
		factions.instantiate_site(sid)
	var sites_usec: int = Time.get_ticks_usec() - sites_start_usec if profile else 0
	chunk_ready.emit(key)
	if profile:
		print("PERF_WORLD_CHUNK key=%s gen_ms=%.2f setup_ms=%.2f nav_ms=%.2f sites_ms=%.2f total_ms=%.2f" % [
			key, generation_usec / 1000.0, setup_usec / 1000.0, nav_usec / 1000.0,
			sites_usec / 1000.0, (Time.get_ticks_usec() - total_start_usec) / 1000.0])
	return ch


func queue_chunk(key: Vector2i) -> void:
	if not chunks.has(key) and gen.chunk_in_bounds(key.x, key.y) and not _chunk_queue.has(key):
		_chunk_queue.append(key)


func process_chunk_queue(max_count: int) -> int:
	var n := 0
	while n < max_count and not _chunk_queue.is_empty():
		ensure_chunk(_chunk_queue.pop_front())
		n += 1
	return n


func pending_chunks() -> int:
	return _chunk_queue.size()


func in_bounds(t: Vector2i) -> bool:
	return gen.in_bounds(t)


func _li(t: Vector2i) -> int:
	return (t.y - int(floor(float(t.y) / S)) * S) * S + (t.x - int(floor(float(t.x) / S)) * S)


func terrain_at(t: Vector2i) -> int:
	var ch := chunk_at_tile(t)
	return ch.terrain[_li(t)] if ch else Tiles.DEEP_WATER


func res_at(t: Vector2i) -> int:
	var ch := chunk_at_tile(t)
	return ch.res_type[_li(t)] if ch else Tiles.Res.NONE


func res_amount_at(t: Vector2i) -> int:
	var ch := chunk_at_tile(t)
	return ch.res_amount[_li(t)] if ch else 0


func blocked_at(t: Vector2i) -> bool:
	var ch := chunk_at_tile(t)
	return ch == null or ch.blocked[_li(t)] != 0


func set_res(t: Vector2i, type: int, amount: int) -> void:
	var ch := chunk_at_tile(t)
	if ch == null:
		return
	if amount <= 0:
		type = Tiles.Res.NONE
	ch.set_resource(_li(t), type, amount)
	_nav_update_tile(t)
	chunk_changed.emit(chunk_key(t))


func set_terrain(t: Vector2i, tt: int) -> void:
	var ch := chunk_at_tile(t)
	if ch == null:
		return
	ch.set_terrain(_li(t), tt)
	_nav_update_tile(t)
	chunk_changed.emit(chunk_key(t))


func is_walkable(t: Vector2i) -> bool:
	if not in_bounds(t):
		return false
	var crossing := crossing_building_at(t)
	if crossing != null:
		return crossing.is_built()
	return not nav.is_point_solid(t)


## Terrain height at a world position (bilinear), gen fallback outside generated chunks.
func height_at(p: Vector2) -> float:
	var t := Vector2i(int(floor(p.x)), int(floor(p.y)))
	var ch := chunk_at_tile(t)
	if ch == null:
		return gen.height_at(p.x, p.y)
	return ch.height_local(p.x - ch.cx * S, p.y - ch.cz * S)


## Height a ground unit stands at. Swimmers sink below the surface; built bridge decks are raised.
func ground_y(p: Vector2) -> float:
	var t := Vector2i(int(floor(p.x)), int(floor(p.y)))
	var h := height_at(p)
	var crossing := _crossing_index.get(t) as Building
	if crossing != null and crossing.type == "bridge_segment" and crossing.is_built():
		return maxf(h, float(gen.t["bridge_deck"]))
	if Tiles.is_water(terrain_at(t)) and gen.is_river_water(float(t.x) + 0.5, float(t.y) + 0.5):
		return h - 0.45
	return h


func crossing_building_at(t: Vector2i) -> Building:
	if _crossing_index.is_empty():
		return null
	return _crossing_index.get(t) as Building


func rebuild_crossing_index() -> void:
	_crossing_index.clear()
	for b: Building in buildings.values():
		if b.type in ["bridge_segment", "cliff_stairs"]:
			_crossing_index[b.origin] = b



## Orient each stair tile uphill across its footprint so adjacent segments form a rising run.
func _cliff_stairs_rotation(t: Vector2i) -> int:
	var center := Vector2(t) + Vector2(0.5, 0.5)
	var up_height := height_at(center + Vector2(0.0, -1.0))
	var down_height := height_at(center + Vector2(0.0, 1.0))
	var left_height := height_at(center + Vector2(-1.0, 0.0))
	var right_height := height_at(center + Vector2(1.0, 0.0))
	var best_delta := down_height - up_height
	var rotation := 2 if best_delta > 0.0 else 0
	var x_delta := right_height - left_height
	if absf(x_delta) > absf(best_delta):
		rotation = 3 if x_delta > 0.0 else 1
	return rotation


func world_pos(u: Unit) -> Vector3:
	var y := ground_y(u.pos)
	if u.flying:
		y = maxf(height_at(u.pos), 0.0) + u.altitude
	return Vector3(u.pos.x, y, u.pos.y)


# --- navigation ----------------------------------------------------------------------------

func _tile_cost(ch: ChunkData, i: int) -> float:
	var tt := ch.terrain[i]
	var t := Vector2i(ch.cx * S + i % S, ch.cz * S + i / S)
	if not _crossing_index.is_empty():
		var crossing := _crossing_index.get(t) as Building
		if crossing != null and crossing.is_built():
			return float(Tiles.COST[Tiles.PAVED if crossing.type == "bridge_segment" else Tiles.TRAIL])
	var cost := float(Tiles.COST[tt])
	var r := ch.res_type[i]
	cost += float(Tiles.RES_PATH_COST.get(r, 0.0))
	return cost


func _tile_solid(ch: ChunkData, i: int) -> bool:
	var tt := ch.terrain[i]
	var t := Vector2i(ch.cx * S + i % S, ch.cz * S + i / S)
	if not _crossing_index.is_empty():
		var crossing := _crossing_index.get(t) as Building
		if crossing != null:
			return not crossing.is_built()
	if ch.blocked[i] != 0:
		return true
	if tt == Tiles.CLIFF:
		return false
	if tt == Tiles.SHALLOW_WATER or tt == Tiles.DEEP_WATER:
		return not gen.is_river_water(float(t.x) + 0.5, float(t.y) + 0.5)
	if not Tiles.WALKABLE[tt]:
		return true
	var r := ch.res_type[i]
	return r != Tiles.Res.NONE and bool(Tiles.res_info(r).get("solid", false))


func _nav_update_tile(t: Vector2i) -> void:
	if not in_bounds(t):
		return
	var ch := chunk_at_tile(t)
	if ch == null:
		nav.set_point_solid(t, true)
		return
	var i := _li(t)
	var solid := _tile_solid(ch, i)
	nav.set_point_solid(t, solid)
	if not solid:
		nav.set_point_weight_scale(t, _tile_cost(ch, i))


func _nav_update_chunk(ch: ChunkData) -> void:
	var o := ch.origin()
	for lz in S:
		for lx in S:
			var i := lz * S + lx
			var t := Vector2i(o.x + lx, o.y + lz)
			var solid := _tile_solid(ch, i)
			nav.set_point_solid(t, solid)
			if not solid:
				nav.set_point_weight_scale(t, _tile_cost(ch, i))


## Nearest walkable tile to t within radius (Chebyshev rings), or Vector2i(INT_MIN) if none.
func nearest_walkable(t: Vector2i, radius: int = 4) -> Vector2i:
	if is_walkable(t):
		return t
	for r in range(1, radius + 1):
		var best := Vector2i(-99999, -99999)
		var best_d := INF
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if absi(dx) != r and absi(dz) != r:
					continue
				var q := t + Vector2i(dx, dz)
				if is_walkable(q):
					var d := Vector2(dx, dz).length()
					if d < best_d:
						best_d = d
						best = q
		if best_d < INF:
			return best
	return Vector2i(-99999, -99999)


## Path of tile centres from a to b (partial path to the closest reachable tile if blocked).
func find_path(a: Vector2, b: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for t: Vector2i in _crossing_index:
		_nav_update_tile(t)
	var ta := nearest_walkable(Vector2i(int(floor(a.x)), int(floor(a.y))), 3)
	var tb := nearest_walkable(Vector2i(int(floor(b.x)), int(floor(b.y))), 4)
	if ta.x == -99999 or tb.x == -99999:
		return out
	var path_start_usec := Time.get_ticks_usec()
	var ids: Array[Vector2i] = nav.get_id_path(ta, tb, true)
	if World.profile_chunks() and Time.get_ticks_usec() - path_start_usec > 15000:
		print("PERF_PATH ms=%.2f from=%s to=%s" % [(Time.get_ticks_usec() - path_start_usec) / 1000.0, ta, tb])
	for id: Vector2i in ids:
		out.append(Vector2(id.x + 0.5, id.y + 0.5))
	return out


## Orders a unit to walk (or fly) to p. Returns false if no route exists.
func move_unit(u: Unit, p: Vector2) -> bool:
	if u.is_static or not dungeons.same_map(u.pos, p):
		return false
	if u.flying:
		u.path = PackedVector2Array()
		# Surface flight goes around the reserved floor block, never through an interior.
		var z := gen.dungeon_zone
		if z.size != Vector2i.ZERO and not gen.in_zone_tile(u.tile()):
			var left_side := z.position.x == gen.min_tile
			var beside_start := u.pos.x >= z.end.x if left_side else u.pos.x < z.position.x
			var beside_goal := p.x >= z.end.x if left_side else p.x < z.position.x
			if not (beside_start and beside_goal) and not (u.pos.y >= z.end.y and p.y >= z.end.y):
				var x := z.end.x + 0.5 if left_side else z.position.x - 0.5
				u.path.append(Vector2(x, z.end.y + 0.5))
		u.path.append(p)
		u.path_i = 0
		u.moving = true
		u.goal = p
		return true
	var path := giants.path(u, p) if u.body_radius() > 0.6 else find_path(u.pos, p)
	if path.is_empty():
		u.moving = false
		return false
	var tp := Vector2i(int(floor(p.x)), int(floor(p.y)))
	var last := path[path.size() - 1]
	if Vector2i(int(floor(last.x)), int(floor(last.y))) == tp and is_walkable(tp):
		path[path.size() - 1] = p
	for step_pos: Vector2 in path:
		if not unit_can_use_terrain(u, Vector2i(int(floor(step_pos.x)), int(floor(step_pos.y)))):
			u.moving = false
			return false
	if path.size() > 1 and u.pos.distance_to(path[0]) < 0.75:
		path.remove_at(0)
	u.path = path
	u.path_i = 0
	u.moving = true
	u.goal = path[path.size() - 1]
	u.stuck_t = 0.0
	return true

func unit_can_use_terrain(u: Unit, t: Vector2i) -> bool:
	if u.flying or not u.is_machine():
		return true
	var terrain := terrain_at(t)
	var crossing := crossing_building_at(t)
	if crossing != null and crossing.is_built():
		return true
	if terrain != Tiles.CLIFF and not Tiles.is_water(terrain):
		return true
	var legs := str(u.dna.get("legs", ""))
	var heavy := u.archetype in ["walker", "hauler", "machine_warden"]
	return not heavy and legs not in ["wheels", "treads"]


func stop_unit(u: Unit) -> void:
	u.moving = false
	u.path = PackedVector2Array()
	u.path_i = 0


func arrived(u: Unit, p: Vector2, tol: float = 0.6) -> bool:
	return not u.moving and u.pos.distance_to(p) <= tol


# --- fog of war & exploration --------------------------------------------------------------

func _fi(t: Vector2i) -> int:
	return (t.y - gen.min_tile) * W + (t.x - gen.min_tile)


func is_explored(t: Vector2i) -> bool:
	return in_bounds(t) and explored[_fi(t)] != 0


## Marks tiles within radius as explored; queues chunks around new ground. Returns new tiles.
func reveal(center: Vector2, radius: float) -> int:
	var n := 0
	var r := int(ceil(radius))
	var cx := int(floor(center.x))
	var cz := int(floor(center.y))
	var r2 := radius * radius
	var touched := {}
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dz * dz > r2:
				continue
			var t := Vector2i(cx + dx, cz + dz)
			if not in_bounds(t):
				continue
			var fi := _fi(t)
			if explored[fi] == 0:
				explored[fi] = 255
				n += 1
				var ck := chunk_key(t)
				touched[ck] = true
				chunk_explored[ck] = int(chunk_explored.get(ck, 0)) + 1
	if n > 0:
		explored_count += n
		fog_dirty = true
		for key: Vector2i in touched:
			for oz in range(-1, 2):
				for ox in range(-1, 2):
					queue_chunk(key + Vector2i(ox, oz))
	return n


## Refreshes the fog image from the explored grid (the view uploads it to the GPU).
func refresh_fog_image() -> void:
	fog_image.set_data(W, W, false, Image.FORMAT_L8, explored)
	fog_dirty = false


## Unexplored tiles near p (generated and in bounds), sorted by distance — explore targets.
## Searches chunk rings outward and skips fully explored chunks, so the cost stays small even
## when most of the world is known.
func frontier_near(p: Vector2, radius: float, max_results: int = 8) -> Array:
	var out: Array = []
	var center := chunk_key(Vector2i(int(floor(p.x)), int(floor(p.y))))
	var rings := int(ceil(radius / S)) + 1
	var r2 := radius * radius
	for ring in rings + 1:
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if absi(dx) != ring and absi(dz) != ring:
					continue
				var key := center + Vector2i(dx, dz)
				var ch: ChunkData = chunks.get(key)
				if ch == null or int(chunk_explored.get(key, 0)) >= S * S:
					continue
				var o := ch.origin()
				for lz in range(1, S, 3):
					for lx in range(1, S, 3):
						var t := Vector2i(o.x + lx, o.y + lz)
						if explored[_fi(t)] == 0 and Vector2(t).distance_squared_to(p) <= r2:
							out.append(t)
		if out.size() >= max_results and ring >= 1:
			break
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Vector2(a).distance_squared_to(p) < Vector2(b).distance_squared_to(p))
	if out.size() > max_results:
		out.resize(max_results)
	return out


## Rebuilds per-chunk explored counts from the explored grid (after loading).
func recount_explored() -> void:
	chunk_explored.clear()
	for key: Vector2i in chunks:
		var o: Vector2i = (chunks[key] as ChunkData).origin()
		var n := 0
		for lz in S:
			var row := _fi(Vector2i(o.x, o.y + lz))
			for lx in S:
				if explored[row + lx] != 0:
					n += 1
		chunk_explored[key] = n


# --- units ---------------------------------------------------------------------------------

func add_unit(u: Unit) -> Unit:
	if u.faction == "player" and u.is_person() and not u.dna.has("art_variant"):
		assign_art_variant(u)
	if u.id == 0:
		u.id = new_id()
	u.prev_pos = u.pos
	units[u.id] = u
	unit_list.append(u)
	if u.stats.is_empty():
		u.recompute_stats()
	unit_added.emit(u)
	return u


func assign_art_variant(u: Unit, force: bool = false) -> void:
	if u.faction != "player" or not u.is_person() or (u.dna.has("art_variant") and not force):
		return
	var count := SpriteLibrary.variant_count(u.dna)
	if count <= 1:
		u.dna["art_variant"] = 0
		return
	var combo := SpriteLibrary.chip_id(u.dna)
	var used := PackedInt32Array()
	used.resize(count)
	for resident: Unit in player_people():
		if resident == u or SpriteLibrary.chip_id(resident.dna) != combo:
			continue
		var variant := SpriteLibrary.art_variant(resident.dna)
		used[variant] += 1
	var identity := "%s|%s|%s|%s|%s" % [str(u.dna.get("seed", 0)), str(u.dna.get("hair", "")),
		str(u.dna.get("hair_color", "")), str(u.dna.get("skin", "")), combo]
	var start := posmod(hash(identity), count)
	var chosen := start
	for offset in range(1, count):
		var candidate := (start + offset) % count
		if used[candidate] < used[chosen]:
			chosen = candidate
	u.dna["art_variant"] = chosen


func remove_unit(u: Unit) -> void:
	if not units.has(u.id):
		return
	units.erase(u.id)
	unit_list.erase(u)
	for s: Squad in squads:
		s.members.erase(u.id)
	colony.release(u)
	unit_removed.emit(u)


func get_unit(id: int) -> Unit:
	return units.get(id)


func _rebuild_grid() -> void:
	_grid.clear()
	for u: Unit in unit_list:
		if not u.alive:
			continue
		var c := Vector2i(int(floor(u.pos.x / GRID)), int(floor(u.pos.y / GRID)))
		if not _grid.has(c):
			_grid[c] = []
		(_grid[c] as Array).append(u)


## Living units within radius of p (optionally filtered).
func units_near(p: Vector2, radius: float, filter: Callable = Callable()) -> Array:
	var out: Array = []
	var c0 := Vector2i(int(floor((p.x - radius) / GRID)), int(floor((p.y - radius) / GRID)))
	var c1 := Vector2i(int(floor((p.x + radius) / GRID)), int(floor((p.y + radius) / GRID)))
	var r2 := radius * radius
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var cell: Variant = _grid.get(Vector2i(cx, cz))
			if cell == null:
				continue
			for u: Unit in cell:
				if u.alive and u.pos.distance_squared_to(p) <= r2 and (not filter.is_valid() or filter.call(u)):
					out.append(u)
	return out


func hostile(a: String, b: String) -> bool:
	if a == b:
		return false
	var hostile_factions := ["bandits", "machines", "beasts"]
	if a == "player":
		return b in hostile_factions or diplomacy.faction_hostile_to_player(b)
	if b == "player":
		return a in hostile_factions or diplomacy.faction_hostile_to_player(a)
	return (a in hostile_factions) != (b in hostile_factions) and (a == "merchants" or b == "merchants")


func player_units() -> Array:
	return unit_list.filter(func(u: Unit) -> bool: return u.faction == "player" and u.alive)


func player_people() -> Array:
	return unit_list.filter(func(u: Unit) -> bool: return u.faction == "player" and u.alive and u.is_person())


func population() -> int:
	return player_people().size()


# --- buildings -----------------------------------------------------------------------------

func add_building(b: Building) -> Building:
	if b.id == 0:
		b.id = new_id()
	if b.type in ["bridge_segment", "cliff_stairs"]:
		_crossing_index[b.origin] = b
	buildings[b.id] = b
	if b.name == "":
		b.name = b.display_name()
	_mark_building_tiles(b, 1)
	building_added.emit(b)
	return b


func remove_building(b: Building) -> void:
	if not buildings.has(b.id):
		return
	buildings.erase(b.id)
	if _crossing_index.get(b.origin) == b:
		_crossing_index.erase(b.origin)
	_mark_building_tiles(b, 0)
	for wid: int in b.workers:
		var w := get_unit(wid)
		if w:
			colony.release(w)
	building_removed.emit(b)


func _mark_building_tiles(b: Building, value: int, only: ChunkData = null) -> void:
	for x in range(b.origin.x, b.origin.x + b.size.x):
		for z in range(b.origin.y, b.origin.y + b.size.y):
			var t := Vector2i(x, z)
			var ch := chunk_at_tile(t)
			if ch == null or (only != null and ch != only):
				continue
			ch.blocked[_li(t)] = value
			_nav_update_tile(t)


## Adds a structure to a site at runtime (camps grow). Returns false if the ground is not free.
func add_site_structure(sid: int, type: String, origin: Vector2i, size: Vector2i) -> bool:
	for x in range(origin.x, origin.x + size.x):
		for z in range(origin.y, origin.y + size.y):
			var t := Vector2i(x, z)
			if chunk_at_tile(t) == null or blocked_at(t) or not is_walkable(t) or farm.has(t):
				return false
	var st: Dictionary = sites[sid]
	var s := {"type": type, "origin": origin, "size": size, "rot": 0}
	(st["extra"] as Array).append(s)
	_mark_structure(s)
	site_changed.emit(sid)
	return true


func _mark_structure(s: Dictionary, only: ChunkData = null) -> void:
	var o: Vector2i = s["origin"]
	var sz: Vector2i = s["size"]
	for x in range(o.x, o.x + sz.x):
		for z in range(o.y, o.y + sz.y):
			var t := Vector2i(x, z)
			var ch := chunk_at_tile(t)
			if ch == null or (only != null and ch != only):
				continue
			ch.blocked[_li(t)] = 1
			if ch.res_type[_li(t)] != Tiles.Res.NONE:
				ch.set_resource(_li(t), Tiles.Res.NONE, 0)
			_nav_update_tile(t)


func building_at(t: Vector2i) -> Building:
	for b: Building in buildings.values():
		if b.contains_tile(t):
			return b
	return null


func buildings_of(type: String, built_only: bool = true) -> Array:
	return buildings.values().filter(func(b: Building) -> bool:
		return b.type == type and b.faction == "player" and (b.is_built() or not built_only))


## Built player buildings that accept deliveries.
func storages() -> Array:
	return buildings.values().filter(func(b: Building) -> bool:
		return b.faction == "player" and b.is_built() and bool(b.def().get("storage", false)))


func nearest_storage(p: Vector2) -> Building:
	var best: Building = null
	var best_d := INF
	for b: Building in storages():
		var d := b.distance_to(p)
		if d < best_d:
			best_d = d
			best = b
	return best


func housing() -> int:
	var total := 0
	for b: Building in buildings.values():
		if b.faction == "player" and b.is_built():
			var d := b.def()
			var h := int(d.get("housing", 0))
			for lv: Dictionary in d.get("levels", []):
				if int(lv["level"]) <= b.level:
					h = int(lv.get("housing", h))
			total += h
	return total


func build_radius_ok(rect: Rect2i) -> bool:
	var c := Vector2(rect.position) + Vector2(rect.size) * 0.5
	for b: Building in buildings.values():
		if b.faction != "player" or not b.is_built():
			continue
		var d := b.def()
		var r := float(d.get("build_radius", 0.0))
		for lv: Dictionary in d.get("levels", []):
			if int(lv["level"]) <= b.level:
				r = float(lv.get("build_radius", r))
		if r > 0.0 and b.center().distance_to(c) <= r:
			return true
	return false


## "" if the building can be placed with its top-left tile at origin, else a reason for the player.
func can_place(type: String, origin: Vector2i, check_cost: bool = true) -> String:
	var d := DB.get_def("buildings", type)
	if d.is_empty():
		return "Unknown building"
	var size := Vector2i(int(d["size"][0]), int(d["size"][1]))
	if gen.in_zone_tile(origin) or gen.in_zone_tile(origin + size):
		return "Cannot build inside a dungeon"
	if type in ["bridge_segment", "cliff_stairs"]:
		var t := origin
		if not in_bounds(t) or chunk_at_tile(t) == null:
			return "Outside the known world"
		if not is_explored(t):
			return "Unexplored ground"
		if blocked_at(t) or crossing_building_at(t) != null:
			return "Blocked"
		if farm.has(t):
			return "Farmland"
		var tt := terrain_at(t)
		if type == "bridge_segment":
			if not Tiles.is_water(tt) or not gen.is_river_water(float(t.x) + 0.5, float(t.y) + 0.5):
				return "Bridge segments need river water"
		elif tt != Tiles.CLIFF:
			return "Stairs need cliff ground"
		if check_cost and not economy.can_afford(d.get("cost", {})):
			return "Not enough resources"
		return ""
	var hmin := INF
	var hmax := -INF
	for x in range(origin.x, origin.x + size.x):
		for z in range(origin.y, origin.y + size.y):
			var t := Vector2i(x, z)
			if not in_bounds(t) or chunk_at_tile(t) == null:
				return "Outside the known world"
			if not is_explored(t):
				return "Unexplored ground"
			var tt := terrain_at(t)
			if Tiles.is_water(tt):
				return "Water"
			if not Tiles.BUILDABLE[tt]:
				return "Cannot build on %s" % Tiles.NAMES[tt]
			if blocked_at(t):
				return "Blocked"
			if farm.has(t):
				return "Farmland"
			for c: Vector2i in [t, t + Vector2i(1, 0), t + Vector2i(0, 1), t + Vector2i(1, 1)]:
				var h := height_at(Vector2(c))
				hmin = minf(hmin, h)
				hmax = maxf(hmax, h)
	if hmax - hmin > 1.4:
		return "Too steep"
	if not build_radius_ok(Rect2i(origin, size)):
		return "Too far from your settlement"
	if check_cost and not economy.can_afford(d.get("cost", {})):
		return "Not enough resources"
	return ""


## Places a construction site (or a finished building when instant). Pays the cost up front.
func place_building(type: String, origin: Vector2i, instant: bool = false, faction: String = "player") -> Building:
	var d := DB.get_def("buildings", type)
	var b := Building.new()
	b.type = type
	b.faction = faction
	b.origin = origin
	b.size = Vector2i(int(d["size"][0]), int(d["size"][1]))
	if type == "cliff_stairs":
		b.rot = _cliff_stairs_rotation(origin)
	b.variant = rng.randi_range(0, 9999)
	b.progress = 1.0 if instant else 0.0
	b.hp = b.max_hp()
	if not instant:
		var cost: Dictionary = d.get("cost", {})
		economy.pay(cost)
		for k: String in cost:
			b.needs[k] = int(cost[k])
	if type not in ["bridge_segment", "cliff_stairs"]:
		_flatten_footprint(b)
	# gather what grows or lies on the footprint (felled as part of clearing)
	for x in range(origin.x, origin.x + b.size.x):
		for z in range(origin.y, origin.y + b.size.y):
			var t := Vector2i(x, z)
			var r := res_at(t)
			if r != Tiles.Res.NONE:
				var info := Tiles.res_info(r)
				if instant and str(info.get("yield", "")) != "":
					economy.add(str(info["yield"]), res_amount_at(t))
				set_res(t, Tiles.Res.NONE, 0)
	add_building(b)
	return b


func _flatten_footprint(b: Building) -> void:
	var total := 0.0
	var n := 0
	for x in range(b.origin.x, b.origin.x + b.size.x + 1):
		for z in range(b.origin.y, b.origin.y + b.size.y + 1):
			total += height_at(Vector2(x, z))
			n += 1
	var h := total / maxf(1.0, n)
	var changed := {}
	for x in range(b.origin.x, b.origin.x + b.size.x + 1):
		for z in range(b.origin.y, b.origin.y + b.size.y + 1):
			# a corner can belong to up to four chunks
			for ox in [0, -1]:
				for oz in [0, -1]:
					var key := chunk_key(Vector2i(x + ox, z + oz))
					var ch: ChunkData = chunks.get(key)
					if ch == null:
						continue
					var lx := x - ch.cx * S
					var lz := z - ch.cz * S
					if lx < 0 or lz < 0 or lx > S or lz > S:
						continue
					ch.set_corner_height(lz * (S + 1) + lx, h)
					changed[key] = true
	for key: Vector2i in changed:
		chunk_changed.emit(key)


func cancel_building(b: Building) -> void:
	if b.is_built():
		return
	var refund := {}
	for k: String in b.needs:
		refund[k] = int(refund.get(k, 0)) + int(b.needs[k])
	for k: String in b.delivered:
		refund[k] = int(refund.get(k, 0)) + int(b.delivered[k])
	for k: String in refund:
		economy.add(k, refund[k])
	remove_building(b)


# --- zones & farms -------------------------------------------------------------------------

func add_zone(type: String, rect: Rect2i) -> Dictionary:
	var z := {"id": new_id(), "type": type, "rect": rect}
	if type == "farm":
		var count := 0
		for x in range(rect.position.x, rect.end.x):
			for zz in range(rect.position.y, rect.end.y):
				var t := Vector2i(x, zz)
				if farm.has(t) or not is_explored(t) or blocked_at(t):
					continue
				var tt := terrain_at(t)
				if not (tt in [Tiles.GRASS, Tiles.MEADOW, Tiles.DIRT, Tiles.FOREST, Tiles.FARMLAND]):
					continue
				var r := res_at(t)
				if r != Tiles.Res.NONE and Tiles.res_info(r).get("solid", false):
					continue
				farm[t] = {"stage": 1 if tt == Tiles.FARMLAND else 0, "growth": 0.0, "crop": "wheat" if (x + zz) % 7 != 0 else "veg"}
				count += 1
		if count == 0:
			return {}
	zones.append(z)
	zones_changed.emit()
	return z


func remove_zones_in(rect: Rect2i) -> int:
	var removed := 0
	for z: Dictionary in zones.duplicate():
		var zr: Rect2i = z["rect"]
		if zr.intersects(rect):
			zones.erase(z)
			removed += 1
	for t: Vector2i in farm.keys():
		if rect.has_point(t):
			farm.erase(t)
			farm_changed.emit(t)
	if removed > 0:
		zones_changed.emit()
	return removed


func zone_type_at(t: Vector2i) -> String:
	for z: Dictionary in zones:
		if (z["rect"] as Rect2i).has_point(t):
			return z["type"]
	return ""


# --- squads --------------------------------------------------------------------------------

func create_squad(name_: String = "") -> Squad:
	if squads.size() >= MAX_SQUADS:
		return null
	var s := Squad.new()
	s.id = squads.size()
	for existing: Squad in squads:
		s.id = maxi(s.id, existing.id + 1)
	s.name = name_ if name_ != "" else "%s Squad" % NameGen.squad(s.id)
	s.mem["home"] = home_pos()
	squads.append(s)
	squads_changed.emit()
	return s


func disband_squad(squad_id: int) -> bool:
	var squad := get_squad(squad_id)
	if squad == null:
		return false
	for member_id: int in squad.members.duplicate():
		var member := get_unit(member_id)
		if member:
			_unassign_from_squad(member)
	squads.erase(squad)
	squads_changed.emit()
	return true


func get_squad(id: int) -> Squad:
	for s: Squad in squads:
		if s.id == id:
			return s
	return null


func assign_to_squad(u: Unit, s: Squad) -> bool:
	if s == null or not squads.has(s) or not u.is_player() or u.kind == "airship" or s.members.size() >= 6:
		return false
	if u.squad_id >= 0:
		unassign_from_squad(u)
	colony.release(u)
	s.members.append(u.id)
	u.squad_id = s.id
	u.labor = "soldier"
	u.order = {}
	stop_unit(u)
	squads_changed.emit()
	return true


func unassign_from_squad(u: Unit) -> void:
	_unassign_from_squad(u)
	squads_changed.emit()


func _unassign_from_squad(u: Unit) -> void:
	var squad := get_squad(u.squad_id)
	if squad:
		squad.members.erase(u.id)
	u.squad_id = -1
	u.target_id = -1
	var arch := u.DB_archetype()
	u.labor = str(arch.get("labor", "worker")) if u.is_machine() else "worker"
	stop_unit(u)



func home_pos() -> Vector2:
	var h: Building = buildings.get(hearth_id)
	if h:
		return Vector2(h.door_tile()) + Vector2(0.5, 1.5)
	return Vector2(gen.start_tile) + Vector2(0.5, 0.5)


# --- loot ----------------------------------------------------------------------------------

func drop_loot(p: Vector2, items: Array, gold: int = 0, metal: int = 0, resources: Dictionary = {}) -> Dictionary:
	var has_resources := false
	for amount: Variant in resources.values():
		if int(amount) > 0:
			has_resources = true
			break
	if items.is_empty() and gold <= 0 and metal <= 0 and not has_resources:
		return {}
	# Flying enemies can die over walls or water. Their loot lands on nearby ground.
	var tile := Vector2i(floori(p.x), floori(p.y))
	if not is_walkable(tile):
		var ground := nearest_walkable(tile, 8)
		var landing := Vector2(ground) + Vector2(0.5, 0.5)
		if ground.x != -99999 and dungeons.same_map(p, landing):
			p = landing
	var best := -1
	for it: Dictionary in items:
		best = maxi(best, int(DB.get_def("items/qualities", str(it.get("quality", "common"))).get("tier", 2)))
	var bag := {"id": new_id(), "pos": p, "items": items, "gold": gold, "metal": metal,
		"resources": resources.duplicate(true), "tier": best, "age": 0.0}
	loot_bags[bag["id"]] = bag
	loot_added.emit(bag)
	return bag


## Moves a bag's contents to the colony. Returns the items picked up.
func pickup_loot(bag_id: int, by: Unit) -> Array:
	var bag: Dictionary = loot_bags.get(bag_id, {})
	if bag.is_empty():
		return []
	loot_bags.erase(bag_id)
	for it: Dictionary in bag["items"]:
		if int(it.get("uid", 0)) == 0:
			it["uid"] = new_id()
		armory.append(it)
		counters["loot_found"] = int(counters.get("loot_found", 0)) + 1
		if by:
			by.counter_add("loot_found")
		var q := DB.get_def("items/qualities", str(it.get("quality", "common")))
		if int(q.get("tier", 0)) >= 4:
			var loot_key := "sim.loot.rare_item" if by else "sim.loot.rare_item.people"
			notify_key(loot_key, {"unit_name": by.name if by else "", "item": it, "quality": {"table": "items/qualities", "id": str(it.get("quality", "common"))}},
				"loot", bag["pos"], {"item_uid": it["uid"], "tier": q.get("tier", 0)})
	if int(bag["gold"]) > 0:
		economy.add("gold", int(bag["gold"]))
	if int(bag["metal"]) > 0:
		economy.add("metal", int(bag["metal"]))
	for resource: String in bag.get("resources", {}):
		economy.add(resource, int(bag["resources"][resource]))
	loot_removed.emit(bag_id)
	return bag["items"]


# --- notifications -------------------------------------------------------------------------

func notify_key(key: String, params: Dictionary = {}, kind: String = "info", pos: Variant = null, extra: Dictionary = {}) -> void:
	var n := {"key": key, "params": params, "kind": kind, "day": day, "hour": hour(), "tick": tick_count}
	if pos is Vector2:
		n["pos"] = pos
	for k: String in extra:
		n[k] = extra[k]
	notifications.append(n)
	if notifications.size() > 80:
		notifications.pop_front()
	notified.emit(n)


func notify(text: String, kind: String = "info", pos: Variant = null, extra: Dictionary = {}) -> void:
	var n := {"text": text, "kind": kind, "day": day, "hour": hour(), "tick": tick_count}
	if pos is Vector2:
		n["pos"] = pos
	for k: String in extra:
		n[k] = extra[k]
	notifications.append(n)
	if notifications.size() > 80:
		notifications.pop_front()
	notified.emit(n)


func emit_fx(kind: StringName, p: Vector2, y_off: float = 0.6, color: Color = Color.WHITE) -> void:
	fx.emit(kind, Vector3(p.x, ground_y(p) + y_off, p.y), color)


# --- tick ----------------------------------------------------------------------------------

func tick() -> void:
	tick_count += 1
	# one chunk per tick: generating a chunk costs ~25-30 ms in GDScript, two in one tick made
	# 60+ ms hitches while exploring; 10 chunks/s at x1 still stays ahead of every explorer
	process_chunk_queue(1)
	_rebuild_grid()
	for u: Unit in unit_list:
		u.prev_pos = u.pos
	economy.tick()
	colony.tick()
	squad_ai.tick()
	factions.tick()
	for u: Unit in unit_list:
		_update_unit(u)
	combat.tick()
	if tick_count % 5 == 0:
		_update_vision()
	# quest goals are world state (resources, cleared camps, discovered sites): poll them rarely
	if tick_count % 20 == 0:
		quests.refresh_states()
	if tick_count % DAY_TICKS == 0:
		day += 1
		economy.on_new_day()
		factions.on_new_day()
		quests.on_new_day()
		colony.on_new_day()
		dungeons.on_new_day()
		giants.on_new_day()
	_cleanup()

func _update_unit(u: Unit) -> void:
	if not u.alive:
		return
	u.last_hit_t += TICK
	if u.attack_cd > 0.0:
		u.attack_cd -= TICK
	for b: Dictionary in u.buffs.duplicate():
		b["t"] = float(b["t"]) - TICK
		if float(b["t"]) <= 0.0:
			u.buffs.erase(b)
			u.recompute_stats()
	if u.state == Unit.State.DOWNED:
		combat.update_downed(u)
		return
	# regeneration: out of combat, faster near home
	if u.last_hit_t > 6.0 and u.hp < float(u.stats["max_hp"]):
		var rate := 0.35 * float(u.stats.get("hp_regen", 1.0))
		if u.is_player() and u.pos.distance_to(home_pos()) < 14.0:
			rate *= 4.0
		if u.is_machine() and u.is_player():
			rate *= 0.6 if res.get("energy", 0) > 0 else 0.0
		u.hp = minf(float(u.stats["max_hp"]), u.hp + rate * TICK)
	_move(u)


func _move(u: Unit) -> void:
	if not u.moving or u.path.is_empty():
		u.moving = false
		return
	var target := u.path[u.path_i]
	var speed := float(u.stats.get("move_speed", 2.0))
	if not u.flying:
		var current_tile := u.tile()
		var crossing := crossing_building_at(current_tile)
		var move_cost := float(Tiles.COST[terrain_at(current_tile)])
		if crossing != null and crossing.is_built():
			move_cost = float(Tiles.COST[Tiles.PAVED if crossing.type == "bridge_segment" else Tiles.TRAIL])
		speed /= move_cost
		speed = maxf(speed, 0.5)
	if u.is_machine() and u.is_player() and int(res.get("energy", 0)) <= 0:
		speed *= 0.5
	var step := speed * TICK
	var d := target - u.pos
	var dist := d.length()
	if dist > 0.001:
		u.facing = d / dist
	if dist <= step:
		u.pos = target
		u.path_i += 1
		if u.path_i >= u.path.size():
			u.moving = false
			u.path = PackedVector2Array()
			u.path_i = 0
	else:
		u.pos += d / dist * step


var _last_reveal: Dictionary = {}  # seer key -> Vector3(x, z, radius) of its last reveal


func _update_vision() -> void:
	# exploration by player units and buildings; visibility of others
	var seers: Array = []
	var reveal_changed := false
	for u: Unit in unit_list:
		if u.alive and u.is_player() and not u.hidden:
			var v := float(u.stats.get("vision", 9.0))
			if is_night():
				v = maxf(v * 0.7, v * 0.7 + float(u.stats.get("night_vision", 0.0)))
			seers.append([u.pos, v, u])
	for b: Building in buildings.values():
		if b.faction == "player" and b.is_built():
			seers.append([b.center(), float(b.def().get("vision", 8.0)), null])
	for s: Array in seers:
		# Reveal from the tile centre, and only when the tile or the view radius changed: a pure
		# function of (tile, radius), so it does not matter when the last reveal happened.
		var key: Variant = (s[2] as Unit).id if s[2] != null else s[0]
		var tile := Vector2i(int(floor((s[0] as Vector2).x)), int(floor((s[0] as Vector2).y)))
		var anchor := Vector3(tile.x, tile.y, snappedf(float(s[1]), 0.01))
		if _last_reveal.get(key) == anchor:
			continue
		_last_reveal[key] = anchor
		var n := reveal(Vector2(tile) + Vector2(0.5, 0.5), anchor.z)
		reveal_changed = true
		if n > 0 and s[2] != null:
			(s[2] as Unit).counter_add("tiles_explored", n)
	for u: Unit in unit_list:
		if u.faction == "player":
			u.visible = true
			continue
		var seen := false
		for s: Array in seers:
			if (s[0] as Vector2).distance_squared_to(u.pos) <= float(s[1]) * float(s[1]):
				seen = true
				break
		if seen and not u.visible:
			factions.on_unit_spotted(u)
		u.visible = seen
	if reveal_changed:
		factions.check_site_discovery(seers)


func _cleanup() -> void:
	for u: Unit in unit_list.duplicate():
		if not u.alive and u.state == Unit.State.DEAD:
			u.downed_t += TICK
			if u.downed_t > 6.0:
				remove_unit(u)
	for id: int in loot_bags.keys():
		var bag: Dictionary = loot_bags[id]
		bag["age"] = float(bag["age"]) + TICK
