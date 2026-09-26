class_name NewGame
extends RefCounted
## Builds a fresh world: generates the start region, founds the settlement (hearth, houses,
## storehouse, sky dock, a planted field, logging and mining zones), and creates the company:
## the player's character leading Alpha Squad, generated settlers, a work bot, a scout drone and
## the founding cargo airship.

const START_RES := {"wood": 120, "stone": 60, "ore": 10, "metal": 30, "food": 80, "gold": 60, "energy": 60}
const SETTLER_ROLES := ["farmer", "woodcutter", "builder", "miner", "engineer"]


## player: character record from the creation screen (NpcGen format + "appearance" DNA), may be {}.
static func create(seed: int, player: Dictionary = {}, company: String = "", color: Color = Color("#3a5da8")) -> World:
	var w := World.new()
	w.setup(seed)
	w.faction_color = color
	w.company_name = company if company != "" else "Frontier Company"
	var sc := w.chunk_key(w.gen.start_tile)
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			w.ensure_chunk(sc + Vector2i(dx, dz))
	var start := Vector2(w.gen.start_tile) + Vector2(0.5, 0.5)
	w.reveal(start, float(DB.raw("generation/world").get("start_explore_radius", 24)))
	for r: String in START_RES:
		w.res[r] = START_RES[r]
	_found_settlement(w)
	_create_company(w, player)
	w.refresh_fog_image()
	w.notify_key("sim.new_game.landed", {"company_name": w.company_name}, "good", w.home_pos())
	return w


static func _place_near(w: World, type: String, around: Vector2i, min_r: int, max_r: int) -> Building:
	var d := DB.get_def("buildings", type)
	var size := Vector2i(int(d["size"][0]), int(d["size"][1]))
	var best := Vector2i(-99999, 0)
	var best_d := INF
	for r in range(min_r, max_r + 1):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if absi(dx) != r and absi(dz) != r:
					continue
				var o := around + Vector2i(dx, dz) - size / 2
				if w.can_place(type, o, false) != "" or not _clearance(w, o, size):
					continue
				var dd := Vector2(dx, dz).length()
				if dd < best_d:
					best_d = dd
					best = o
		if best.x != -99999:
			return w.place_building(type, best, true)
	return null


## Keeps a one-tile walkway around buildings so the settlement stays walkable.
static func _clearance(w: World, o: Vector2i, size: Vector2i) -> bool:
	for x in range(o.x - 1, o.x + size.x + 1):
		for z in range(o.y - 1, o.y + size.y + 1):
			if x >= o.x and x < o.x + size.x and z >= o.y and z < o.y + size.y:
				continue
			var t := Vector2i(x, z)
			if w.building_at(t) != null:
				return false
	return true


static func _found_settlement(w: World) -> void:
	var st := w.gen.start_tile
	var hearth := w.place_building("hearth", st - Vector2i(2, 2), true)
	w.hearth_id = hearth.id
	_place_near(w, "house", st + Vector2i(-6, -2), 0, 6)
	_place_near(w, "house", st + Vector2i(-2, -7), 0, 6)
	_place_near(w, "storehouse", st + Vector2i(6, -1), 0, 6)
	_place_near(w, "sky_dock", st + Vector2i(3, -8), 0, 8)
	# a planted field south of the hearth
	var field_o := _find_field(w, st + Vector2i(-2, 6), Vector2i(6, 4))
	if field_o.x != -99999:
		w.add_zone("farm", Rect2i(field_o, Vector2i(6, 4)))
		var i := 0
		for t: Vector2i in w.farm:
			var f: Dictionary = w.farm[t]
			f["stage"] = 2
			f["growth"] = 0.25 + float(i % 5) * 0.12
			i += 1
			w.set_terrain(t, Tiles.FARMLAND)
	# logging near the closest forest, mining at the ore field
	var forest := _densest(w, Vector2(st), 34.0, func(r: int) -> bool: return Tiles.is_tree(r))
	if forest.x != -99999:
		w.add_zone("logging", Rect2i(forest - Vector2i(6, 6), Vector2i(12, 12)))
	for g: Dictionary in w.gen.sites.values():
		if g["kind"] == "ore_field" and Vector2(g["center"]).distance_to(Vector2(st)) < 40.0:
			var c: Vector2i = g["center"]
			w.add_zone("mining", Rect2i(c - Vector2i(7, 7), Vector2i(14, 14)))
			break


static func _find_field(w: World, around: Vector2i, size: Vector2i) -> Vector2i:
	for r in range(0, 8):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if absi(dx) != r and absi(dz) != r:
					continue
				var o := around + Vector2i(dx, dz)
				var ok := true
				for x in range(o.x - 1, o.x + size.x + 1):
					for z in range(o.y - 1, o.y + size.y + 1):
						var t := Vector2i(x, z)
						var tt := w.terrain_at(t)
						if w.blocked_at(t) or not (tt in [Tiles.GRASS, Tiles.MEADOW, Tiles.DIRT, Tiles.FOREST]) or w.res_at(t) != Tiles.Res.NONE:
							ok = false
							break
					if not ok:
						break
				if ok:
					return o
	return Vector2i(-99999, 0)


static func _densest(w: World, around: Vector2, radius: float, pred: Callable) -> Vector2i:
	var best := Vector2i(-99999, 0)
	var best_n := 0
	var r := int(radius)
	for dz in range(-r, r + 1, 4):
		for dx in range(-r, r + 1, 4):
			var c := Vector2i(int(around.x) + dx, int(around.y) + dz)
			if Vector2(c).distance_to(around) < 14.0:
				continue
			var n := 0
			for oz in range(-5, 6):
				for ox in range(-5, 6):
					if pred.call(w.res_at(c + Vector2i(ox, oz))):
						n += 1
			if n > best_n and _reachable(w, around, Vector2(c)):
				best_n = n
				best = c
	return best


static func _reachable(w: World, a: Vector2, b: Vector2) -> bool:
	var path := w.find_path(a, b)
	return not path.is_empty() and path[path.size() - 1].distance_to(b) < 3.0


static func _spot(w: World, around: Vector2, i: int) -> Vector2:
	var a := float(i) * 2.399
	var r := 2.5 + sqrt(float(i)) * 1.6
	var p := around + Vector2(cos(a), sin(a)) * r
	var t := w.nearest_walkable(Vector2i(int(floor(p.x)), int(floor(p.y))), 5)
	return Vector2(t) + Vector2(0.5, 0.5) if t.x != -99999 else around


static func _create_company(w: World, player: Dictionary) -> void:
	var home := w.home_pos()
	var alpha := w.create_squad()
	# the player's character
	var pu: Unit
	if player.is_empty():
		pu = CharacterFactory.make_colonist(w, {"role": "commander", "talent": "skilled"}, _spot(w, home, 0))
	else:
		pu = Unit.new()
		pu.id = w.new_id()
		pu.kind = "character"
		pu.archetype = "colonist"
		pu.faction = "player"
		pu.character = player.duplicate(true)
		pu.character.erase("appearance")
		pu.character["xp"] = float(pu.character.get("xp", 0))
		pu.name = str(player.get("name", "Founder"))
		pu.dna = (player.get("appearance", {}) as Dictionary).duplicate(true)
		for slot: String in pu.equipment():
			if pu.equipment()[slot] is Dictionary:
				pu.equipment()[slot]["uid"] = w.new_id()
		CharacterFactory.sync_dna(pu)
		pu.pos = _spot(w, home, 0)
		pu.recompute_stats()
		pu.hp = float(pu.stats["max_hp"])
		pu.energy = float(pu.stats["energy_max"])
		w.add_unit(pu)
	pu.character["titles"] = ["Founder"]
	w.player_unit_id = pu.id
	w.assign_to_squad(pu, alpha)
	w.combat.enlist(pu)
	var guard := CharacterFactory.make_colonist(w, {"role": "guard", "talent": "skilled", "level": 2}, _spot(w, home, 1))
	w.assign_to_squad(guard, alpha)
	w.combat.enlist(guard)
	var archer := CharacterFactory.make_colonist(w, {"role": "archer", "talent": "skilled", "level": 2}, _spot(w, home, 2))
	w.assign_to_squad(archer, alpha)
	w.combat.enlist(archer)
	var walker := CharacterFactory.make_machine(w, "walker", "player", _spot(w, home, 3))
	w.assign_to_squad(walker, alpha)
	w.squad_ai.order_squad(alpha, {"type": "idle"})
	var hearth: Building = w.buildings[w.hearth_id]
	var post := w.nearest_walkable(Vector2i(hearth.center() + Vector2(5.5, -1.0)), 6)
	alpha.mem["hold"] = Vector2(post) + Vector2(0.5, 0.5) if post.x != -99999 else home
	# settlers
	for i in SETTLER_ROLES.size():
		CharacterFactory.make_colonist(w, {"role": SETTLER_ROLES[i]}, _spot(w, home, 4 + i))
	CharacterFactory.make_machine(w, "work_bot", "player", _spot(w, home, 10))
	var drone := CharacterFactory.make_machine(w, "scout_drone", "player", _spot(w, home, 11))
	drone.order = {"type": "auto"}
	var dock := w.squad_ai.dock_pos()
	var ship := CharacterFactory.make_machine(w, "cargo_airship", "player", dock)
	ship.order = {"type": "dock"}
	# a couple of odd finds in the armory to try on
	var rng := RngUtil.make([w.seed, "armory"])
	for i in 2:
		var it := ItemGen.generate(rng, {"level": 1, "luck": 0.2, "source": "loot"})
		it["uid"] = w.new_id()
		w.armory.append(it)
