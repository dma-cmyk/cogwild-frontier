class_name WorldGen
extends RefCounted
## Deterministic, rule-based world generation. Every value is a pure function of the seed and the
## world position, so chunks can be generated in any order (as the player explores) and are rebuilt
## identically after loading a save. Rules make the world playable rather than noisy: a flat, safe
## start valley near water and forest, rivers with fords and trail bridges, terraced highlands with
## cliffs, resources by biome, and points of interest whose danger grows with distance.

const S := ChunkData.S
const SITE_OUTER := 7.0  # flatten blend distance beyond a site's flat radius

var seed: int
var p: Dictionary
var t: Dictionary
var veg: Dictionary
var site_cfg: Dictionary
var radius_chunks: int
var min_tile: int
var max_tile: int

var start_tile: Vector2i
var start_height: float
## All sites known so far (guaranteed + generated cells): id -> site Dictionary.
var sites: Dictionary = {}
var _guaranteed: Array = []
var _cell_cache: Dictionary = {}

var _n_cont := FastNoiseLite.new()
var _n_detail := FastNoiseLite.new()
var _n_mount := FastNoiseLite.new()
var _n_river := FastNoiseLite.new()
var _n_warp_x := FastNoiseLite.new()
var _n_warp_z := FastNoiseLite.new()
var _n_ford := FastNoiseLite.new()
var _n_trail := FastNoiseLite.new()
var _n_moist := FastNoiseLite.new()
var _n_ore := FastNoiseLite.new()
var _n_crystal := FastNoiseLite.new()


func _init(p_seed: int, params: Dictionary = {}) -> void:
	seed = p_seed
	p = params if not params.is_empty() else (DB.raw("generation/world") as Dictionary)
	t = p["terrain"]
	veg = p["vegetation"]
	site_cfg = p["sites"]
	radius_chunks = int(p.get("world_radius_chunks", 10))
	min_tile = -radius_chunks * S
	max_tile = radius_chunks * S
	_setup_noise()
	_compute_start()
	_place_guaranteed_sites()


func _setup_noise() -> void:
	_cfg(_n_cont, "cont", float(t["continent_freq"]), 4, FastNoiseLite.FRACTAL_FBM)
	_cfg(_n_detail, "detail", float(t["detail_freq"]), 2, FastNoiseLite.FRACTAL_FBM)
	_cfg(_n_mount, "mount", float(t["mountain_freq"]), 4, FastNoiseLite.FRACTAL_RIDGED)
	_cfg(_n_river, "river", float(t["river_freq"]), 2, FastNoiseLite.FRACTAL_FBM)
	_cfg(_n_warp_x, "warpx", float(t["river_freq"]) * 3.0, 2, FastNoiseLite.FRACTAL_FBM)
	_cfg(_n_warp_z, "warpz", float(t["river_freq"]) * 3.0, 2, FastNoiseLite.FRACTAL_FBM)
	_cfg(_n_ford, "ford", float(t["ford_freq"]), 1, FastNoiseLite.FRACTAL_NONE)
	_cfg(_n_trail, "trail", float(t["trail_freq"]), 2, FastNoiseLite.FRACTAL_FBM)
	_cfg(_n_moist, "moist", float(t["moisture_freq"]), 3, FastNoiseLite.FRACTAL_FBM)
	_cfg(_n_ore, "ore", 0.05, 2, FastNoiseLite.FRACTAL_FBM)
	_cfg(_n_crystal, "crystal", 0.035, 2, FastNoiseLite.FRACTAL_FBM)


func _cfg(n: FastNoiseLite, salt: String, freq: float, octaves: int, fractal: int) -> void:
	n.seed = RngUtil.hash_parts([seed, salt])
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = fractal as FastNoiseLite.FractalType
	n.fractal_octaves = octaves


# --- height field ------------------------------------------------------------------------------

func river_value(x: float, z: float) -> float:
	var w := float(t["river_warp"])
	var wx := x + _n_warp_x.get_noise_2d(x, z) * w
	var wz := z + _n_warp_z.get_noise_2d(x, z) * w
	return absf(_n_river.get_noise_2d(wx, wz))

## Natural lake basins have negative uncarved land height, unlike carved river channels.
func is_river_water(x: float, z: float) -> bool:
	return land_height(x, z) > 0.0 and river_value(x, z) < float(t["river_bank"])


func moisture(x: float, z: float) -> float:
	return _n_moist.get_noise_2d(x, z)


func _terrace(h: float) -> float:
	var step := float(t["terrace_step"])
	var sharp := float(t["terrace_sharpness"])
	var k := h / step
	var f := floorf(k)
	var fr := k - f
	return (f + smoothstep(sharp, 1.0 - sharp, fr)) * step


## Land height before rivers carve their beds (natural lakes are still below zero here).
func land_height(x: float, z: float) -> float:
	var c := _n_cont.get_noise_2d(x, z)
	var d := _n_detail.get_noise_2d(x, z)
	var m := _n_mount.get_noise_2d(x, z)
	var h := float(t["base_height"]) + c * float(t["continent_amp"]) * 2.0
	var mt := clampf((m - float(t["mountain_threshold"])) / float(t["mountain_span"]), 0.0, 1.0)
	h += mt * mt * float(t["mountain_amp"])
	return _terrace(h) + d * float(t["detail_amp"])


## Distance in metres to the nearest trail centre line (isoline of the trail noise).
func trail_distance(x: float, z: float) -> float:
	var n := _n_trail.get_noise_2d(x, z)
	if absf(n) > float(t["trail_width"]) * 4.0:
		return INF
	var gx := _n_trail.get_noise_2d(x + 0.5, z) - _n_trail.get_noise_2d(x - 0.5, z)
	var gz := _n_trail.get_noise_2d(x, z + 0.5) - _n_trail.get_noise_2d(x, z - 0.5)
	return absf(n) / maxf(sqrt(gx * gx + gz * gz), 0.00001)


## Height before start/site flattening.
func raw_height(x: float, z: float) -> float:
	var h := land_height(x, z)
	var rv := river_value(x, z)
	var bank := float(t["river_bank"])
	if rv < bank:
		var k := 1.0 - smoothstep(float(t["river_core"]), bank, rv)
		var bed := float(t["river_depth"])
		if _n_ford.get_noise_2d(x, z) > float(t["ford_threshold"]):
			bed = float(t["ford_depth"])
		h = lerpf(h, minf(h, bed), k)
	return h


## Final height including flattened start valley and site plateaus.
## local_sites: precomputed list of sites that can affect the point (pass [] to search).
func height_at(x: float, z: float, local_sites: Variant = null) -> float:
	var h := raw_height(x, z)
	var ds := Vector2(x, z).distance_to(Vector2(start_tile) + Vector2(0.5, 0.5))
	var inner := float(p["start_flat_inner"])
	var outer := float(p["start_flat_outer"])
	if ds < outer:
		h = lerpf(start_height, h, smoothstep(inner, outer, ds))
	var list: Array = local_sites if local_sites is Array else sites_affecting(Rect2(x - 1.0, z - 1.0, 2.0, 2.0))
	for s: Dictionary in list:
		var r := float(s["flat_radius"])
		if r <= 0.0:
			continue
		var d := Vector2(x, z).distance_to(Vector2(s["center"]) + Vector2(0.5, 0.5))
		if d < r + SITE_OUTER:
			h = lerpf(float(s["height"]), h, smoothstep(r, r + SITE_OUTER, d))
	return h


# --- start ---------------------------------------------------------------------------------

func _compute_start() -> void:
	var rng := RngUtil.make([seed, "start"])
	var best := Vector2.ZERO
	var best_score := -INF
	for i in 220:
		var ang := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 120.0
		var cand := Vector2(cos(ang), sin(ang)) * r
		var s := _start_score(cand)
		if s > best_score:
			best_score = s
			best = cand
	start_tile = Vector2i(int(floor(best.x)), int(floor(best.y)))
	start_height = maxf(raw_height(best.x, best.y), 1.3)


func _start_score(c: Vector2) -> float:
	var h := raw_height(c.x, c.y)
	if h < 1.0:
		return -INF
	var max_dev := 0.0
	for k in 12:
		var a := TAU * k / 12.0
		for rad: float in [7.0, 13.0]:
			var q := c + Vector2(cos(a), sin(a)) * rad
			max_dev = maxf(max_dev, absf(raw_height(q.x, q.y) - h))
			if river_value(q.x, q.y) < float(t["river_bank"]) * 1.3:
				return -INF
	var score := -max_dev * 3.0 - c.length() * 0.012
	# water within reach (river band 20-45 m away) is nice, trees nearby are needed
	var near_river := false
	var wet := 0.0
	for k in 16:
		var a := TAU * k / 16.0
		for rad: float in [24.0, 34.0, 44.0]:
			var q := c + Vector2(cos(a), sin(a)) * rad
			if river_value(q.x, q.y) < float(t["river_core"]) * 1.5:
				near_river = true
			wet += moisture(q.x, q.y)
	if near_river:
		score += 4.0
	score += clampf(wet / 48.0, -0.3, 0.4) * 10.0
	if h > 7.0:
		score -= (h - 7.0) * 0.8
	return score


# --- sites ---------------------------------------------------------------------------------

func _site_ok(pos: Vector2, radius: float) -> bool:
	var margin := radius + 12.0
	if pos.x < min_tile + margin or pos.y < min_tile + margin or pos.x > max_tile - margin or pos.y > max_tile - margin:
		return false
	var h := raw_height(pos.x, pos.y)
	if h < 0.7:
		return false
	for k in 8:
		var a := TAU * k / 8.0
		var q := pos + Vector2(cos(a), sin(a)) * maxf(radius, 4.0)
		if river_value(q.x, q.y) < float(t["river_bank"]) * 1.2:
			return false
		if raw_height(q.x, q.y) < 0.2:
			return false
	return river_value(pos.x, pos.y) > float(t["river_bank"]) * 1.4


func _kind_radius(kind: String) -> float:
	return float((site_cfg["kinds"] as Dictionary).get(kind, {}).get("flat_radius", 6))


func _village_races() -> Array[String]:
	var result: Array[String] = []
	for race: String in DB.ids("races"):
		if DB.has_def("villages", race):
			result.append(race)
	return result


## 0..1 suitability used to choose a race's preferred site terrain.
func village_preference_score(race: String, pos: Vector2) -> float:
	var cfg := DB.get_def("villages", race)
	var h := raw_height(pos.x, pos.y)
	var wet := moisture(pos.x, pos.y)
	var river := 1.0
	for i in 12:
		var a := TAU * float(i) / 12.0
		river = minf(river, river_value(pos.x + cos(a) * 18.0, pos.y + sin(a) * 18.0))
	var height_low := clampf(1.0 - absf(h - 4.0) / 8.0, 0.0, 1.0)
	var hill := clampf((h - 2.0) / 8.0, 0.0, 1.0)
	var forest := clampf((wet + 0.2) / 0.7, 0.0, 1.0)
	var riverbank := clampf(1.0 - river / 0.28, 0.0, 1.0)
	match str(cfg.get("biome_preference", "plains")):
		"forest":
			return forest
		"hills":
			return hill * 0.75 + (1.0 - forest) * 0.25
		"rocky_hills":
			return hill * 0.7 + (1.0 - forest) * 0.3
		"highlands":
			return clampf((h - 4.0) / 8.0, 0.0, 1.0)
		"mountain_forest":
			return clampf((clampf((h - 3.0) / 8.0, 0.0, 1.0) + forest) * 0.5, 0.0, 1.0)
		"river":
			return riverbank
		_:
			return height_low * 0.75 + clampf(1.0 - absf(wet) / 0.8, 0.0, 1.0) * 0.25


func _make_site(id: int, kind: String, pos: Vector2, race: String = "") -> Dictionary:
	var center := Vector2i(int(floor(pos.x)), int(floor(pos.y)))
	var dist := Vector2(center).distance_to(Vector2(start_tile))
	var kcfg: Dictionary = (site_cfg["kinds"] as Dictionary).get(kind, {})
	var site := {
		"id": id, "kind": kind, "center": center, "flat_radius": int(kcfg.get("flat_radius", 6)),
		"height": maxf(raw_height(center.x + 0.5, center.y + 0.5), 0.8),
		"faction": str(kcfg.get("faction", "")), "icon": str(kcfg.get("icon", "")),
		"distance": dist, "level": 1 + int(maxf(0.0, dist - 60.0) / 70.0),
		"structures": [], "decor": [], "resources": [], "clear_radius": int(kcfg.get("flat_radius", 6)),
	}
	if kind == "village":
		if race == "" or not DB.has_def("races", race) or not DB.has_def("villages", race):
			return {}
		site["race"] = race
		site["faction"] = "folk_" + race
		site["preference_score"] = village_preference_score(race, pos)
		# the outer ring of homes and the fields sit past the flattened plateau: clear further out
		site["clear_radius"] = int(kcfg.get("flat_radius", 6)) + 5
	_layout_site(site)
	sites[id] = site
	return site


## Guaranteed sites are laid out in the order of `generation/world.json`. Villages come last and
## take the best-scoring spot for their race inside their distance band, so each race sits in the
## terrain it likes without displacing the older landmarks.
func _place_guaranteed_sites() -> void:
	var rng := RngUtil.make([seed, "guaranteed"])
	var village_races := _village_races()
	var race_rng := RngUtil.make([seed, "village_races"])
	for i in range(village_races.size() - 1, 0, -1):
		var j := race_rng.randi_range(0, i)
		var swap := village_races[i]
		village_races[i] = village_races[j]
		village_races[j] = swap
	var used_angles: Array = []
	var village_index := 0
	var gid := 1
	for g: Dictionary in site_cfg["guaranteed"]:
		var kind: String = g["kind"]
		var dmin := float(g["dist"][0])
		var dmax := float(g["dist"][1])
		var radius := _kind_radius(kind)
		var is_village := kind == "village"
		var race := ""
		if is_village:
			if village_races.is_empty():
				gid += 1
				continue
			race = village_races[village_index % village_races.size()]
			village_index += 1
		var placed := false
		var best_score := -1.0
		var best_pos := Vector2.ZERO
		var best_angle := 0.0
		# Villages search much harder: they are placed last, they must land in terrain their race
		# likes, and unlike the landmarks they may share a bearing with a site at another distance.
		for attempt in (240 if is_village else 60):
			var ang := rng.randf() * TAU
			var spread := rng.randf()
			var too_close := false
			if not is_village:
				for ua: float in used_angles:
					if absf(angle_difference(ang, ua)) < 0.5 and attempt < 40:
						too_close = true
			if too_close:
				continue
			var d := lerpf(dmin, dmax, spread) + (0.0 if is_village else attempt * 0.8)
			var pos := Vector2(start_tile) + Vector2(cos(ang), sin(ang)) * d
			if not _site_ok(pos, radius):
				continue
			if not is_village and dmax <= 140.0 and absf(raw_height(pos.x, pos.y) - start_height) > 3.2 and attempt < 50:
				continue
			var clash := false
			for other: Dictionary in _guaranteed:
				if Vector2(other["center"]).distance_to(pos) < radius + _kind_radius(str(other["kind"])) + 14.0:
					clash = true
			if clash:
				continue
			if not is_village:
				_guaranteed.append(_make_site(gid, kind, pos))
				used_angles.append(ang)
				placed = true
				break
			var score := village_preference_score(race, pos)
			if score > best_score:
				best_score = score
				best_pos = pos
				best_angle = ang
		if is_village and best_score >= 0.0:
			var village := _make_site(gid, kind, best_pos, race)
			if not village.is_empty():
				_guaranteed.append(village)
				used_angles.append(best_angle)
				placed = true
		if not placed:
			push_warning("WorldGen: could not place guaranteed site %s (seed %d)" % [kind, seed])
		gid += 1


## Site id for a 64 m cell, generating it on first request (-1 = none).
func cell_site(cell: Vector2i) -> int:
	if _cell_cache.has(cell):
		return _cell_cache[cell]
	var id := -1
	var cs := float(site_cfg["cell_size"])
	var rng := RngUtil.make([seed, "cell", cell.x, cell.y])
	if rng.randf() < float(site_cfg["cell_chance"]):
		for attempt in 4:
			var pos := Vector2(cell.x * cs + rng.randf_range(14.0, cs - 14.0), cell.y * cs + rng.randf_range(14.0, cs - 14.0))
			var dist := pos.distance_to(Vector2(start_tile))
			if dist < float(site_cfg["min_start_distance"]):
				break
			var far := dist > float(site_cfg["far_distance"])
			var weights: Dictionary = site_cfg["weights_far"] if far else site_cfg["weights_near"]
			var kind: String = RngUtil.weighted_key(rng, weights)
			var race := ""
			if kind == "village":
				var races := _village_races()
				if races.is_empty():
					continue
				race = races[rng.randi_range(0, races.size() - 1)]
			var radius := _kind_radius(kind)
			var clash := false
			for g: Dictionary in _guaranteed:
				if Vector2(g["center"]).distance_to(pos) < 46.0:
					clash = true
			if clash or not _site_ok(pos, radius):
				continue
			id = 1000 + (cell.x + 512) * 1024 + (cell.y + 512)
			var generated := _make_site(id, kind, pos, race)
			if generated.is_empty():
				id = -1
			break
	_cell_cache[cell] = id
	return id


## Sites whose influence (flat radius + blend + structures) can touch the rect.
func sites_affecting(rect: Rect2) -> Array:
	var out: Array = []
	var cs := float(site_cfg["cell_size"])
	var grown := rect.grow(24.0)
	var c0 := Vector2i(int(floor(grown.position.x / cs)), int(floor(grown.position.y / cs)))
	var c1 := Vector2i(int(floor(grown.end.x / cs)), int(floor(grown.end.y / cs)))
	for g: Dictionary in _guaranteed:
		if grown.has_point(Vector2(g["center"])):
			out.append(g)
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var id := cell_site(Vector2i(cx, cz))
			if id >= 0 and grown.has_point(Vector2(sites[id]["center"])):
				out.append(sites[id])
	return out


func _layout_site(site: Dictionary) -> void:
	var rng := RngUtil.make([seed, "layout", site["id"]])
	var c: Vector2i = site["center"]
	var occupied := {}
	var a0 := rng.randf() * TAU
	match site["kind"]:
		"village":
			_village_layout(site, occupied, rng, a0)
		"bandit_camp":
			_add_structure(site, occupied, "campfire", c, 0)
			for k in 3:
				_ring_structure(site, occupied, "bandit_tent", c, a0 + k * TAU / 3.0, 5.0, rng)
			_ring_structure(site, occupied, "bandit_hut", c, a0 + TAU / 6.0, 6.8, rng)
			_ring_structure(site, occupied, "bandit_tower", c, a0 + PI + 0.5, 7.5, rng)
			var n := 34
			for k in n:
				var a := a0 + 0.35 + (TAU - 0.9) * k / float(n)
				var q := Vector2(c) + Vector2(cos(a), sin(a)) * 10.0
				_add_structure(site, occupied, "palisade", Vector2i(int(floor(q.x)), int(floor(q.y))), 0)
			_add_decor(site, "banner_pole", Vector2(c) + Vector2(cos(a0 + PI), sin(a0 + PI)) * 3.0 + Vector2(0.5, 0.5), rng)
			_add_decor(site, "crate", Vector2(c) + Vector2(2.5, -1.5), rng)
			_add_decor(site, "barrel", Vector2(c) + Vector2(-2.0, 2.4), rng)
		"machine_outpost":
			_add_structure(site, occupied, "machine_foundry", c, 0)
			_ring_structure(site, occupied, "machine_spire", c, a0, 7.5, rng)
			_ring_structure(site, occupied, "machine_spire", c, a0 + PI, 7.5, rng)
			for k in 3:
				_ring_structure(site, occupied, "machine_block", c, a0 + PI * 0.5 + k * 0.9, 7.0, rng)
		"ruins":
			_add_structure(site, occupied, "ruin_vault" if rng.randf() < 0.6 else "ruin_statue", c, 0)
			for k in 4:
				_ring_structure(site, occupied, "ruin_pillar", c, a0 + k * TAU / 4.0 + 0.4, 4.5, rng)
			_ring_structure(site, occupied, "ruin_wall", c, a0 + 0.1, 6.0, rng)
			_ring_structure(site, occupied, "ruin_wall", c, a0 + PI + 0.3, 6.0, rng)
			_ring_structure(site, occupied, "ruin_arch", c, a0 + PI * 0.5, 6.0, rng)
		"trade_post":
			_add_structure(site, occupied, "trade_hall", c, 0)
			_ring_structure(site, occupied, "trade_stall", c, a0, 5.8, rng)
			_ring_structure(site, occupied, "trade_stall", c, a0 + 1.2, 5.8, rng)
			_ring_structure(site, occupied, "trade_mast", c, a0 + PI, 7.0, rng)
			for k in 4:
				var q := Vector2(c) + Vector2(cos(a0 + 2.2 + k * 0.6), sin(a0 + 2.2 + k * 0.6)) * 4.2 + Vector2(0.5, 0.5)
				_add_decor(site, ["crate", "barrel", "lantern_post", "crate"][k], q, rng)
		"wanderer_camp":
			_add_structure(site, occupied, "wanderer_tent", c, 0)
			_ring_structure(site, occupied, "campfire", c, a0, 2.8, rng)
			_add_decor(site, "log_pile", Vector2(c) + Vector2(cos(a0 + 2.0), sin(a0 + 2.0)) * 3.0, rng)
		"wreck":
			_add_structure(site, occupied, "wreck_airship", c, rng.randi_range(0, 1))
			for k in 3:
				var q := Vector2(c) + Vector2(cos(a0 + k * 2.1), sin(a0 + k * 2.1)) * 5.5
				_add_decor(site, ["crate", "barrel", "stone_pile"][k], q, rng)
		"crystal_grove":
			for k in 9:
				var a := rng.randf() * TAU
				var r := rng.randf_range(0.0, 4.5)
				_add_resource(site, Vector2(c) + Vector2(cos(a), sin(a)) * r, Tiles.Res.ORE_CRYSTAL)
			for k in 4:
				var a := rng.randf() * TAU
				_add_resource(site, Vector2(c) + Vector2(cos(a), sin(a)) * rng.randf_range(4.0, 6.5), Tiles.Res.ROCK_LARGE)
		"ore_field":
			for k in 10:
				var a := rng.randf() * TAU
				var r := rng.randf_range(0.0, 5.0)
				_add_resource(site, Vector2(c) + Vector2(cos(a), sin(a)) * r, Tiles.Res.ORE_IRON)
			for k in 8:
				var a := rng.randf() * TAU
				var r := rng.randf_range(2.0, 7.0)
				_add_resource(site, Vector2(c) + Vector2(cos(a), sin(a)) * r, Tiles.Res.ROCK_LARGE if k % 2 == 0 else Tiles.Res.ROCK_SMALL)


## A lived-in village: a hall on the square, homes on two rings, a market row of stalls, fenced
## fields, work piles, lantern posts and small dressing. The counts follow the race's head count
## (`Diplomacy.population_range`), so a bigger village really is a bigger place.
func _village_layout(site: Dictionary, occupied: Dictionary, rng: RandomNumberGenerator, a0: float) -> void:
	var c: Vector2i = site["center"]
	var race := str(site["race"])
	var cfg := DB.get_def("villages", race)
	var people: Array = cfg.get("population", Diplomacy.POPULATION_RANGE)
	var top := int(people[people.size() - 1])
	var home_count := clampi(int(ceil(float(top) * 0.6)), 4, 10)
	var stall_count := rng.randi_range(2, 3)
	var field_count := rng.randi_range(3, 5)
	_add_structure(site, occupied, "v_%s_hall" % race, c, 0)
	# homes alternate between an inner and an outer ring so the village has streets, not a circle
	for i in home_count:
		var radius := 8.4 if i % 2 == 0 else 12.4
		_ring_structure(site, occupied, "v_%s_home" % race, c,
			a0 + float(i) * TAU / float(home_count) + (0.0 if i % 2 == 0 else 0.22), radius, rng)
	for i in stall_count:
		_ring_structure(site, occupied, "trade_stall", c, a0 + 0.55 + float(i) * 0.5, 5.6, rng)
	for i in field_count:
		var angle := a0 + PI * 0.5 + float(i) * 0.8
		var origin := Vector2(c) + Vector2(cos(angle), sin(angle)) * 15.5 + Vector2(0.5, 0.5)
		for row in 3:
			for col in 3:
				var tile := origin + Vector2(float(col) - 1.0, float(row) - 1.0)
				_add_decor(site, "tilled_soil", tile, rng)
				_add_decor(site, "crop_wheat_3" if (col + row + i) % 2 == 0 else "crop_veg_3", tile, rng)
		for col in 4:
			_add_decor(site, "fence", origin + Vector2(float(col) - 1.5, -1.6), rng)
	for i in 5:
		var lamp := a0 + 0.9 + float(i) * TAU / 5.0
		_add_decor(site, "lantern_post", Vector2(c) + Vector2(cos(lamp), sin(lamp)) * 6.2 + Vector2(0.5, 0.5), rng)
	_add_decor(site, "banner_pole", Vector2(c) + Vector2(cos(a0 + PI), sin(a0 + PI)) * 4.0 + Vector2(0.5, 0.5), rng)
	_add_decor(site, "sign_post", Vector2(c) + Vector2(cos(a0), sin(a0)) * 13.5 + Vector2(0.5, 0.5), rng)
	# work corners: the crafters' wood and stone, the traders' crates
	_add_decor(site, "crate", Vector2(c) + Vector2(4.0, -1.5), rng)
	_add_decor(site, "crate", Vector2(c) + Vector2(4.8, -2.4), rng)
	_add_decor(site, "barrel", Vector2(c) + Vector2(-4.0, 2.4), rng)
	_add_decor(site, "barrel", Vector2(c) + Vector2(-4.7, 3.1), rng)
	_add_decor(site, "log_pile", Vector2(c) + Vector2(-2.4, -4.2), rng)
	_add_decor(site, "log_pile", Vector2(c) + Vector2(-3.3, -4.9), rng)
	_add_decor(site, "stone_pile", Vector2(c) + Vector2(3.2, 3.6), rng)
	_add_decor(site, "ore_pile", Vector2(c) + Vector2(2.3, 4.4), rng)
	for i in 6:
		var a := a0 + 0.3 + float(i) * TAU / 6.0
		var r := rng.randf_range(7.0, 10.5)
		_add_decor(site, "flowers" if i % 2 == 0 else "grass_tuft",
			Vector2(c) + Vector2(cos(a), sin(a)) * r + Vector2(0.5, 0.5), rng)


## Building tables whose entries carry a `size` footprint.
const FOOTPRINT_TABLES: Array[String] = ["buildings", "buildings/villages", "buildings/town"]
## Fallback footprints for ids that are not in a buildings table.
const STRUCT_SIZE := {
	"campfire": Vector2i(1, 1), "bandit_tent": Vector2i(2, 2), "bandit_hut": Vector2i(3, 3), "bandit_tower": Vector2i(2, 2),
	"palisade": Vector2i(1, 1), "machine_foundry": Vector2i(4, 4), "machine_spire": Vector2i(2, 2), "machine_block": Vector2i(2, 2),
	"ruin_vault": Vector2i(3, 3), "ruin_statue": Vector2i(2, 2), "ruin_pillar": Vector2i(1, 1), "ruin_wall": Vector2i(3, 1),
	"ruin_arch": Vector2i(3, 1), "trade_hall": Vector2i(4, 4), "trade_stall": Vector2i(2, 2), "trade_mast": Vector2i(2, 2),
	"wanderer_tent": Vector2i(2, 2), "wreck_airship": Vector2i(6, 3),
}

## Footprint in tiles: the `size` of the building definition (player or village/town tables), else STRUCT_SIZE.
static func struct_size(type: String) -> Vector2i:
	for table: String in FOOTPRINT_TABLES:
		var def := DB.get_def(table, type)
		if def.has("size"):
			var s: Array = def["size"]
			return Vector2i(int(s[0]), int(s[1]))
	return STRUCT_SIZE.get(type, Vector2i(2, 2))


func _ring_structure(site: Dictionary, occupied: Dictionary, type: String, c: Vector2i, angle: float, radius: float, rng: RandomNumberGenerator) -> void:
	var q := Vector2(c) + Vector2(cos(angle), sin(angle)) * radius
	var rot := rng.randi_range(0, 3) if type in ["ruin_wall", "ruin_arch"] else 0
	_add_structure(site, occupied, type, Vector2i(int(round(q.x)), int(round(q.y))), rot)


## Adds a structure centred near `center` unless it overlaps an existing one.
func _add_structure(site: Dictionary, occupied: Dictionary, type: String, center: Vector2i, rot: int) -> void:
	var size: Vector2i = struct_size(type)
	if rot % 2 == 1:
		size = Vector2i(size.y, size.x)
	var origin := center - Vector2i(size.x / 2, size.y / 2)
	for x in range(origin.x, origin.x + size.x):
		for z in range(origin.y, origin.y + size.y):
			if occupied.has(Vector2i(x, z)):
				return
	for x in range(origin.x - 1, origin.x + size.x + 1):
		for z in range(origin.y - 1, origin.y + size.y + 1):
			if x >= origin.x and x < origin.x + size.x and z >= origin.y and z < origin.y + size.y:
				occupied[Vector2i(x, z)] = true
	(site["structures"] as Array).append({"type": type, "origin": origin, "size": size, "rot": rot})


func _add_decor(site: Dictionary, prop: String, pos: Vector2, rng: RandomNumberGenerator) -> void:
	(site["decor"] as Array).append([prop, pos.x, pos.y, rng.randf() * TAU, rng.randf_range(0.9, 1.1)])


func _add_resource(site: Dictionary, pos: Vector2, res: int) -> void:
	(site["resources"] as Array).append([int(floor(pos.x)), int(floor(pos.y)), res])


# --- chunks --------------------------------------------------------------------------------

func chunk_in_bounds(cx: int, cz: int) -> bool:
	return cx >= -radius_chunks and cz >= -radius_chunks and cx < radius_chunks and cz < radius_chunks


func generate_chunk(cx: int, cz: int) -> ChunkData:
	var profile := World.profile_chunks()
	var ch := ChunkData.new(cx, cz)
	var ox := cx * S
	var oz := cz * S
	var rect := Rect2(ox, oz, S, S)
	var site_lookup_start_usec: int = Time.get_ticks_usec() if profile else 0
	var local_sites := sites_affecting(rect)
	var site_lookup_usec: int = Time.get_ticks_usec() - site_lookup_start_usec if profile else 0
	var height_start_usec: int = Time.get_ticks_usec() if profile else 0
	# corner heights
	for lz in S + 1:
		for lx in S + 1:
			ch.heights[lz * (S + 1) + lx] = height_at(ox + lx, oz + lz, local_sites)
	var height_usec: int = Time.get_ticks_usec() - height_start_usec if profile else 0
	var tiles_start_usec: int = Time.get_ticks_usec() if profile else 0
	var cliff := float(t["cliff_slope"])
	var core := float(t["river_core"])
	var bank := float(t["river_bank"])
	var start_c := Vector2(start_tile) + Vector2(0.5, 0.5)
	var start_inner := float(p["start_flat_inner"])
	for lz in S:
		for lx in S:
			var i := lz * S + lx
			var wx := ox + lx
			var wz := oz + lz
			var cx_ := wx + 0.5
			var cz_ := wz + 0.5
			var h00 := ch.corner(lx, lz)
			var h10 := ch.corner(lx + 1, lz)
			var h01 := ch.corner(lx, lz + 1)
			var h11 := ch.corner(lx + 1, lz + 1)
			var hc := (h00 + h10 + h01 + h11) * 0.25
			var slope := maxf(maxf(h00, h10), maxf(h01, h11)) - minf(minf(h00, h10), minf(h01, h11))
			var rv := river_value(cx_, cz_)
			var trail := trail_distance(cx_, cz_) < 0.85
			var m := moisture(cx_, cz_)
			var tt := Tiles.GRASS
			if hc < -0.55:
				tt = Tiles.DEEP_WATER
			elif hc < -0.05:
				tt = Tiles.SHALLOW_WATER
			elif slope > cliff:
				tt = Tiles.CLIFF
			elif trail and hc < 9.0:
				tt = Tiles.TRAIL
			elif hc < 0.45 and (rv < bank * 1.5 or hc < 0.3):
				tt = Tiles.SAND
			elif hc > 9.5 or (slope > cliff * 0.7 and hc > 5.0):
				tt = Tiles.ROCK
			elif m > 0.22:
				tt = Tiles.FOREST
			elif m < -0.42:
				tt = Tiles.DIRT
			elif m < -0.08:
				tt = Tiles.MEADOW
			# bridges only span river channels, never natural lakes
			if trail and Tiles.is_water(tt) and rv < core * 1.8 and land_height(cx_, cz_) > 0.4:
				tt = Tiles.BRIDGE
			ch.terrain[i] = tt
			# resources
			var near_start := Vector2(cx_, cz_).distance_to(start_c) < start_inner + 2.0
			if near_start or not Tiles.WALKABLE[tt] or tt == Tiles.TRAIL or tt == Tiles.BRIDGE or tt == Tiles.SAND or Tiles.is_water(tt):
				_decor_for(ch, tt, lx, lz, wx, wz, rv, near_start)
				continue
			var r1 := RngUtil.hash01(seed, wx, wz, 11)
			var r2 := RngUtil.hash01(seed, wx, wz, 12)
			var res := Tiles.Res.NONE
			var forest := smoothstep(0.02, 0.42, m)
			var ore_n := _n_ore.get_noise_2d(cx_, cz_)
			var cry_n := _n_crystal.get_noise_2d(cx_, cz_)
			var highland := hc > 5.5 or tt == Tiles.ROCK
			if ore_n > float(veg["ore_threshold"]) and (highland or hc > 3.0) and r1 < 0.45:
				res = Tiles.Res.ORE_IRON
			elif cry_n > float(veg["crystal_threshold"]) and r1 < 0.3:
				res = Tiles.Res.ORE_CRYSTAL
			elif r1 < float(veg["forest_density"]) * forest + float(veg["meadow_tree_density"]):
				if m < -0.25 and r2 < 0.35:
					res = Tiles.Res.TREE_DEAD
				elif hc > 5.0 or r2 < 0.45:
					res = Tiles.Res.TREE_PINE
				elif r2 < 0.82:
					res = Tiles.Res.TREE_OAK
				else:
					res = Tiles.Res.TREE_BIRCH
			elif r1 < float(veg["forest_density"]) * forest + float(veg["meadow_tree_density"]) + float(veg["rock_density"]) + (float(veg["highland_rock_density"]) if highland else 0.0):
				res = Tiles.Res.ROCK_LARGE if r2 < 0.3 else Tiles.Res.ROCK_SMALL
			elif r2 < float(veg["berry_density"]) and tt != Tiles.DIRT:
				res = Tiles.Res.BERRY_BUSH
			elif r2 > 0.975:
				res = Tiles.Res.BUSH
			if res != Tiles.Res.NONE:
				_set_res(ch, i, res, wx, wz)
			else:
				_decor_for(ch, tt, lx, lz, wx, wz, rv, false)
	var tiles_usec: int = Time.get_ticks_usec() - tiles_start_usec if profile else 0
	var site_apply_start_usec: int = Time.get_ticks_usec() if profile else 0
	_apply_sites(ch, local_sites)
	var site_apply_usec: int = Time.get_ticks_usec() - site_apply_start_usec if profile else 0
	for s: Dictionary in local_sites:
		var sc: Vector2i = s["center"]
		if sc.x >= ox and sc.x < ox + S and sc.y >= oz and sc.y < oz + S:
			ch.site_ids.append(s["id"])
	if profile:
		print("PERF_WORLDGEN key=(%d,%d) site_lookup_ms=%.2f heights_ms=%.2f tiles_noise_veg_ms=%.2f site_apply_ms=%.2f" % [
			cx, cz, site_lookup_usec / 1000.0, height_usec / 1000.0, tiles_usec / 1000.0, site_apply_usec / 1000.0])
	return ch


func _set_res(ch: ChunkData, i: int, res: int, wx: int, wz: int) -> void:
	var info := Tiles.res_info(res)
	var am: Array = info.get("amount", [1, 1])
	var r3 := RngUtil.hash01(seed, wx, wz, 13)
	ch.res_type[i] = res
	ch.res_amount[i] = int(lerpf(float(am[0]), float(am[1]) + 0.99, r3))
	ch.res_var[i] = int(RngUtil.hash01(seed, wx, wz, 14) * 255.0)


func _decor_for(ch: ChunkData, tt: int, lx: int, lz: int, wx: int, wz: int, rv: float, near_start: bool) -> void:
	var r := RngUtil.hash01(seed, wx, wz, 21)
	var prop := ""
	match tt:
		Tiles.GRASS, Tiles.FOREST:
			if r < float(veg["grass_decor"]) * (0.5 if near_start else 1.0):
				prop = "grass_tuft"
		Tiles.MEADOW:
			if r < float(veg["flower_decor"]):
				prop = "flowers"
			elif r < float(veg["flower_decor"]) + float(veg["grass_decor"]):
				prop = "grass_tuft"
		Tiles.SAND, Tiles.SHALLOW_WATER:
			if rv < float(t["river_bank"]) * 1.6 and r < float(veg["reed_decor"]):
				prop = "reeds"
		Tiles.CLIFF, Tiles.ROCK:
			if r < 0.22:
				prop = "rock_small" if r < 0.16 else "rock_large"
	if prop != "":
		var jx := RngUtil.hash01(seed, wx, wz, 22)
		var jz := RngUtil.hash01(seed, wx, wz, 23)
		var rot := RngUtil.hash01(seed, wx, wz, 24) * TAU
		ch.decor.append([prop, lx + 0.15 + jx * 0.7, lz + 0.15 + jz * 0.7, rot, 0.8 + r * 0.5])


func _apply_sites(ch: ChunkData, local_sites: Array) -> void:
	var ox := ch.cx * S
	var oz := ch.cz * S
	for s: Dictionary in local_sites:
		var c := Vector2(s["center"]) + Vector2(0.5, 0.5)
		var clear := float(s["clear_radius"])
		if clear > 0.0:
			for lz in S:
				for lx in S:
					if Vector2(ox + lx + 0.5, oz + lz + 0.5).distance_to(c) < clear:
						var i := lz * S + lx
						if ch.res_type[i] != Tiles.Res.NONE:
							ch.res_type[i] = Tiles.Res.NONE
							ch.res_amount[i] = 0
		for r: Array in s["resources"]:
			var lx := int(r[0]) - ox
			var lz := int(r[1]) - oz
			if lx >= 0 and lz >= 0 and lx < S and lz < S:
				var i := lz * S + lx
				if Tiles.WALKABLE[ch.terrain[i]] and not Tiles.is_water(ch.terrain[i]):
					_set_res(ch, i, int(r[2]), int(r[0]), int(r[1]))
		for st: Dictionary in s["structures"]:
			var o: Vector2i = st["origin"]
			var sz: Vector2i = st["size"]
			for x in range(o.x, o.x + sz.x):
				for z in range(o.y, o.y + sz.y):
					var lx := x - ox
					var lz := z - oz
					if lx >= 0 and lz >= 0 and lx < S and lz < S:
						var i := lz * S + lx
						ch.blocked[i] = 1
						ch.res_type[i] = Tiles.Res.NONE
						ch.res_amount[i] = 0
		for d: Array in s["decor"]:
			var lx := float(d[1]) - ox
			var lz := float(d[2]) - oz
			if lx >= 0.0 and lz >= 0.0 and lx < S and lz < S:
				ch.decor.append([d[0], lx, lz, d[3], d[4]])


## Tile centre inside the world bounds?
func in_bounds(tile: Vector2i) -> bool:
	return tile.x >= min_tile and tile.y >= min_tile and tile.x < max_tile and tile.y < max_tile


static func chunk_of(tile: Vector2i) -> Vector2i:
	return Vector2i(int(floor(float(tile.x) / S)), int(floor(float(tile.y) / S)))
