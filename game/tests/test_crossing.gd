extends TestCase

const CAMP_SEEDS := [3, 7, 11, 21, 42]

var _worlds: Array[World] = []


func after_all() -> void:
	for w: World in _worlds:
		w.dispose()
	_worlds.clear()


func _world(seed: int) -> World:
	var w := World.new()
	w.setup(seed)
	_worlds.append(w)
	return w


func _ensure_corridor(w: World, from: Vector2i, to: Vector2i) -> void:
	var a := w.chunk_key(from)
	var b := w.chunk_key(to)
	for cx in range(mini(a.x, b.x) - 1, maxi(a.x, b.x) + 2):
		for cz in range(mini(a.y, b.y) - 1, maxi(a.y, b.y) + 2):
			w.ensure_chunk(Vector2i(cx, cz))


func test_start_squads_reach_nearest_bandit_camp_on_all_regression_seeds() -> void:
	for seed: int in CAMP_SEEDS:
		var w := _world(seed)
		var camp: Dictionary = {}
		var best_distance := INF
		for site: Dictionary in w.gen.sites.values():
			if str(site.get("kind", "")) != "bandit_camp":
				continue
			var distance := Vector2(w.gen.start_tile).distance_to(Vector2(site["center"]))
			if distance < best_distance:
				best_distance = distance
				camp = site
		assert_false(camp.is_empty(), "seed %d has a generated bandit camp" % seed)
		if camp.is_empty():
			continue
		var start := w.gen.start_tile
		var goal := Vector2i(camp["center"])
		_ensure_corridor(w, start, goal)
		var camp_tile := w.nearest_walkable(goal, 10)
		assert_ne(camp_tile.x, -99999, "seed %d has an adjacent camp approach tile" % seed)
		if camp_tile.x == -99999:
			continue
		var path := w.find_path(Vector2(start) + Vector2(0.5, 0.5), Vector2(camp_tile) + Vector2(0.5, 0.5))
		assert_true(not path.is_empty(), "seed %d path is nonempty" % seed)
		if not path.is_empty():
			assert_true(Vector2i(floori(path[-1].x), floori(path[-1].y)) == camp_tile,
				"seed %d path reaches camp approach" % seed)
		var ground_unit := Unit.new()
		ground_unit.kind = "character"
		ground_unit.pos = Vector2(start) + Vector2(0.5, 0.5)
		ground_unit.stats = {"move_speed": 2.0}
		assert_true(w.move_unit(ground_unit, Vector2(camp_tile) + Vector2(0.5, 0.5)),
			"seed %d ground unit accepts route to camp approach" % seed)



func test_attack_orders_advance_to_the_blocked_seed_camps() -> void:
	for seed: int in [3, 21, 42]:
		var w := NewGame.create(seed)
		_worlds.append(w)
		var camp: Dictionary = {}
		var best_distance := INF
		for site: Dictionary in w.gen.sites.values():
			if str(site.get("kind", "")) != "bandit_camp":
				continue
			var distance := Vector2(w.gen.start_tile).distance_to(Vector2(site["center"]))
			if distance < best_distance:
				best_distance = distance
				camp = site
		assert_false(camp.is_empty(), "seed %d has a bandit camp for attack order" % seed)
		if camp.is_empty():
			continue
		var camp_tile: Vector2i = camp["center"]
		_ensure_corridor(w, w.gen.start_tile, camp_tile)
		var camp_id := int(camp["id"])
		var defender_ids := {}
		for defender: Unit in w.factions.site_units(camp_id):
			defender_ids[defender.id] = true
		assert_true(not defender_ids.is_empty(), "seed %d instantiates camp defenders" % seed)
		var target := Vector2(camp_tile) + Vector2(0.5, 0.5)
		var squad := w.squads[0]
		squad.stance = "aggressive"

		w.squad_ai.order_squad(squad, {"type": "attack", "site": camp_id, "pos": target})
		var closest_distance := INF
		var fought := false
		for tick in 2400:
			w.tick()
			closest_distance = minf(closest_distance, w.squad_ai.center(squad).distance_to(target))
			fought = fought or squad.state == "fighting"
			for id: int in squad.members:
				var member := w.get_unit(id)
				if member != null and defender_ids.has(member.target_id):
					fought = true
			# the defenders sally out and meet the squad on the approach; where exactly depends on
			# the world around the route (villages, forest), so allow a few metres of slack
			if closest_distance <= 45.0 and fought:
				break
		assert_true(closest_distance <= 45.0 and fought,
			"seed %d attack order reaches a camp defender (%.1f m, fought=%s)" % [seed, closest_distance, str(fought)])

func test_built_crossing_reduces_navigation_cost_and_survives_save_load() -> void:
	var w := _world(7)
	var start := w.gen.start_tile
	for cx in range(-10, 11):
		for cz in range(-10, 11):
			w.ensure_chunk(w.chunk_key(start + Vector2i(cx * ChunkData.S, cz * ChunkData.S)))
	w.reveal(Vector2(start) + Vector2(0.5, 0.5), 500.0)
	var bridge_tile := Vector2i(-99999, -99999)
	var cliff_tile := Vector2i(-99999, -99999)
	var lake_tile := Vector2i(-99999, -99999)
	for dx in range(-320, 321):
		for dz in range(-320, 321):
			var t := start + Vector2i(dx, dz)
			if not w.in_bounds(t) or w.chunk_at_tile(t) == null:
				continue
			var terrain := w.terrain_at(t)
			var river := w.gen.is_river_water(float(t.x) + 0.5, float(t.y) + 0.5)
			if Tiles.is_water(terrain) and river and bridge_tile.x == -99999:
				bridge_tile = t
			elif terrain == Tiles.CLIFF and cliff_tile.x == -99999:
				cliff_tile = t
			elif terrain == Tiles.DEEP_WATER and not river and lake_tile.x == -99999:
				lake_tile = t
	if lake_tile.x != -99999:
		assert_false(w.is_walkable(lake_tile), "natural deep water remains impassable")
	assert_ne(bridge_tile.x, -99999, "seed has a generated river tile")
	assert_ne(cliff_tile.x, -99999, "seed has a generated cliff tile")
	if bridge_tile.x == -99999 or cliff_tile.x == -99999:
		return
	var bridge_origin := _near_valid_crossing(w, "bridge_segment", bridge_tile)
	var stairs_origin := _near_valid_crossing(w, "cliff_stairs", cliff_tile)
	assert_ne(bridge_origin.x, -99999, "river bridge tile remains buildable outside the settlement radius")
	assert_ne(stairs_origin.x, -99999, "cliff stair tile remains buildable outside the settlement radius")
	if bridge_origin.x == -99999 or stairs_origin.x == -99999:
		return
	assert_true(Vector2(bridge_origin).distance_to(w.home_pos()) > 30.0,
		"river bridge can be planned outside settlement radius")
	assert_true(Vector2(stairs_origin).distance_to(w.home_pos()) > 30.0,
		"cliff stairs can be planned outside settlement radius")
	var bridge := w.place_building("bridge_segment", bridge_origin, true)
	var stairs := w.place_building("cliff_stairs", stairs_origin, true)
	w._nav_update_tile(bridge_origin)
	var bank_tile := Vector2i(-99999, -99999)
	for direction: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var candidate := bridge_origin + direction
		if w.is_walkable(candidate) and not Tiles.is_water(w.terrain_at(candidate)):
			bank_tile = candidate
			break
	assert_ne(bank_tile.x, -99999, "built bridge has a land approach tile")
	if bank_tile.x != -99999:
		var target := Vector2(bridge_origin) + Vector2(0.5, 0.5)
		var unit := Unit.new()
		unit.id = w.new_id()
		unit.kind = "character"
		unit.faction = "player"
		unit.pos = Vector2(bank_tile) + Vector2(0.5, 0.5)
		unit.stats = {"move_speed": 2.0}
		w.units[unit.id] = unit
		w.unit_list.append(unit)
		assert_true(w.is_walkable(bridge_origin), "built bridge tile is walkable before pathfinding")
		assert_true(w.move_unit(unit, target), "single unit accepts a move order onto a built bridge")
		assert_eq(Vector2i(floori(unit.goal.x), floori(unit.goal.y)), bridge_origin,
			"single-unit move goal remains on the bridge rather than adjacent shallows")
		var squad := Squad.new()
		squad.id = w.new_id()
		for i in 3:
			var member := Unit.new()
			member.id = w.new_id()
			member.kind = "character"
			member.faction = "player"
			member.squad_id = squad.id
			member.pos = Vector2(bank_tile) + Vector2(0.5, 0.5)
			member.stats = {"move_speed": 2.0}
			w.units[member.id] = member
			w.unit_list.append(member)
			squad.members.append(member.id)
		w.squads.append(squad)
		w.squad_ai.order_squad(squad, {"type": "move", "pos": target})
		for member_id: int in squad.members:
			var member := w.get_unit(member_id)
			var goal_tile := Vector2i(floori(member.goal.x), floori(member.goal.y))
			assert_false(Tiles.is_water(w.terrain_at(goal_tile))
					and w.gen.is_river_water(float(goal_tile.x) + 0.5, float(goal_tile.y) + 0.5)
					and w.crossing_building_at(goal_tile) == null,
				"squad formation slots stay on the bridge or land banks")
		w.squad_ai.order_squad(squad,
			{"type": "move", "pos": Vector2(bank_tile) + Vector2(0.5, 0.5)})
		for member_id: int in squad.members:
			var member := w.get_unit(member_id)
			var goal_tile := Vector2i(floori(member.goal.x), floori(member.goal.y))
			assert_false(Tiles.is_water(w.terrain_at(goal_tile))
					and w.gen.is_river_water(float(goal_tile.x) + 0.5, float(goal_tile.y) + 0.5)
					and w.crossing_building_at(goal_tile) == null,
				"squad formations crossing to the bank avoid the shallow water next to the bridge")
	assert_true(w.is_walkable(stairs_origin), "built cliff stair tile is walkable")
	var stair_bank := Vector2i(-99999, -99999)
	for direction: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var candidate := stairs_origin + direction
		if w.is_walkable(candidate):
			stair_bank = candidate
			break
	if stair_bank.x != -99999:
		var stair_unit := Unit.new()
		stair_unit.id = w.new_id()
		stair_unit.kind = "character"
		stair_unit.faction = "player"
		stair_unit.pos = Vector2(stair_bank) + Vector2(0.5, 0.5)
		stair_unit.stats = {"move_speed": 2.0}
		assert_true(w.move_unit(stair_unit, Vector2(stairs_origin) + Vector2(0.5, 0.5)),
			"single unit accepts a move order onto built stairs")
		assert_eq(Vector2i(floori(stair_unit.goal.x), floori(stair_unit.goal.y)), stairs_origin,
			"stair move goal remains on the built stair tile")
	assert_true(w.nav.get_point_weight_scale(bridge_origin) < Tiles.COST[w.terrain_at(bridge_origin)], "bridge uses road-speed path cost")
	assert_true(w.nav.get_point_weight_scale(stairs_origin) < Tiles.COST[Tiles.CLIFF], "stairs use trail-speed path cost")
	var loaded := SaveGame.from_dict(SaveGame.to_dict(w))
	_worlds.append(loaded)
	assert_true(loaded.buildings.has(bridge.id) and loaded.buildings[bridge.id].is_built(), "built bridge saved and loaded")
	assert_true(loaded.buildings.has(stairs.id) and loaded.buildings[stairs.id].is_built(), "built stairs saved and loaded")
	assert_true(loaded.nav.get_point_weight_scale(bridge_origin) < Tiles.COST[loaded.terrain_at(bridge_origin)], "loaded bridge retains road-speed cost")
	assert_true(loaded.nav.get_point_weight_scale(stairs_origin) < Tiles.COST[Tiles.CLIFF], "loaded stairs retain trail-speed cost")




func _near_valid_crossing(w: World, type: String, around: Vector2i) -> Vector2i:
	for radius in range(0, 30):
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dz) != radius:
					continue
				var candidate := around + Vector2i(dx, dz)
				if w.can_place(type, candidate, false) == "":
					return candidate
	return Vector2i(-99999, -99999)
