extends TestCase
## Dungeons: deterministic connected floors, the reserved zone, entrances appearing over time,
## moving between levels, depth and difficulty scaling, and the save round trip.

const SEED := 4242

var _worlds: Array = []


func after_all() -> void:
	for w: World in _worlds:
		w.dispose()
	_worlds.clear()


func _new(seed_value: int = SEED) -> World:
	var w := NewGame.create(seed_value)
	_worlds.append(w)
	return w


func _spawn(w: World, difficulty: int, floors: int, theme: String = "brigands") -> int:
	var rng := RngUtil.make([w.seed, "test_spawn", difficulty, floors])
	return w.dungeons.spawn_entrance(rng, {"difficulty": difficulty, "floors": floors, "theme": theme, "discovered": true})


func _reachable(tiles: PackedByteArray, from: Vector2i) -> PackedInt32Array:
	return DungeonZone._bfs(tiles, from)


func test_floors_are_deterministic_and_connected() -> void:
	for floors in [2, 4, 9]:
		for index in floors:
			var a := DungeonZone.generate_floor(SEED, 2000000, index, 3, floors)
			var b := DungeonZone.generate_floor(SEED, 2000000, index, 3, floors)
			assert_eq(a["tiles"], b["tiles"], "floor %d/%d is deterministic" % [index, floors])
			var tiles: PackedByteArray = a["tiles"]
			var dist := _reachable(tiles, a["up"])
			for room: Rect2i in a["rooms"]:
				var c := room.position + room.size / 2
				assert_true(dist[c.y * DungeonZone.FLOOR_SIZE + c.x] >= 0, "every room is reachable (%d/%d)" % [index, floors])
			if not bool(a["last"]):
				var d: Vector2i = a["down"]
				assert_true(dist[d.y * DungeonZone.FLOOR_SIZE + d.x] >= 0, "the down stairs are reachable")
			else:
				assert_eq(a["down"], Vector2i(-1, -1), "the last floor has no way down")
				assert_true(int(a["boss_room"]) >= 0, "the last floor has a boss room")


func test_walls_are_never_one_tile_thin() -> void:
	for index in 6:
		var lay := DungeonZone.generate_floor(SEED, 2000016, index, 2, 6)
		var tiles: PackedByteArray = lay["tiles"]
		for z in range(1, DungeonZone.FLOOR_SIZE - 1):
			for x in range(1, DungeonZone.FLOOR_SIZE - 1):
				var i := z * DungeonZone.FLOOR_SIZE + x
				if tiles[i] != DungeonZone.Kind.WALL:
					continue
				var horizontal := tiles[i - 1] != DungeonZone.Kind.WALL and tiles[i + 1] != DungeonZone.Kind.WALL
				var vertical := tiles[i - DungeonZone.FLOOR_SIZE] != DungeonZone.Kind.WALL and tiles[i + DungeonZone.FLOOR_SIZE] != DungeonZone.Kind.WALL
				assert_false(horizontal or vertical, "wall (%d,%d) on floor %d has floor on both sides" % [x, z, index])


func test_new_worlds_reserve_a_zone_far_from_the_start() -> void:
	var w := _new()
	var zone := w.gen.dungeon_zone
	assert_true(zone.size != Vector2i.ZERO, "a new world has a dungeon zone")
	assert_false(zone.has_point(w.gen.start_tile), "the start is outside the zone")
	for gs: Dictionary in w.gen.sites.values():
		assert_false(zone.has_point(gs["center"]), "site %s is outside the zone" % str(gs["id"]))
	var old := World.new()
	old.setup(SEED)
	_worlds.append(old)
	assert_eq(old.gen.dungeon_zone.size, Vector2i.ZERO, "worlds made without the flag keep their whole map")


func test_zone_rock_is_solid_and_floors_are_walkable() -> void:
	var w := _new()
	var eid := _spawn(w, 2, 3)
	assert_true(eid >= 0, "an entrance was made")
	w.dungeons.ensure_floor(eid, 0)
	var lay := w.dungeons.layout(eid, 0)
	var origin := w.dungeons.floor_origin(eid, 0)
	assert_true(w.is_walkable(origin + lay["up"]), "the up stairs stand on walkable ground")
	var wall := origin + Vector2i(0, 0)
	assert_false(w.is_walkable(wall), "the floor's outer ring is rock")
	var before := w.find_path(w.dungeons.to_world(eid, 0, lay["up"]), w.dungeons.to_world(eid, 0, lay["down"]))
	assert_true(before.size() > 1, "a route runs from the up stairs to the down stairs")
	assert_eq(w.can_place("house", origin + lay["up"], false), "Cannot build inside a dungeon", "no building in dungeons")


func test_entrances_appear_over_time_up_to_the_cap() -> void:
	var w := _new()
	assert_true(w.dungeons.entrances().is_empty(), "no dungeon at the start")
	for i in 60:
		w.day += 1
		w.dungeons.on_new_day()
	var open := 0
	for st: Dictionary in w.dungeons.entrances():
		if str(st["state"]) == "open":
			open += 1
		assert_true(int(st["difficulty"]) >= 1 and int(st["difficulty"]) <= 5, "difficulty in range")
		var lo: int = {1: 2, 2: 3, 3: 4, 4: 6, 5: 8}[int(st["difficulty"])]
		var hi: int = {1: 3, 2: 4, 3: 6, 4: 8, 5: 10}[int(st["difficulty"])]
		assert_true(int(st["floors"]) >= lo and int(st["floors"]) <= hi, "floors follow difficulty")
		assert_false(w.gen.dungeon_zone.has_point(st["center"]), "entrances stand on the surface")
		assert_true(w.is_walkable(Vector2i(st["center"]) + Vector2i(0, 2)), "the gate can be reached")
	assert_true(open >= 1 and open <= DungeonZone.COLS, "some dungeons exist but never more than the slots (%d)" % open)


func test_entering_and_using_stairs_moves_the_units() -> void:
	var w := _new()
	var eid := _spawn(w, 2, 3)
	var squad := w.squads[0]
	var units := w.squad_ai.members(squad)
	assert_true(w.dungeons.enter(units, eid), "the squad enters")
	var loc := w.dungeons.locate(units[0].pos)
	assert_eq(loc, {"eid": eid, "floor": 0}, "the squad stands on the first floor")
	assert_true(w.is_walkable(Vector2i(int(units[0].pos.x), int(units[0].pos.y))), "arrival is on walkable ground")
	assert_true(w.dungeons.use_stairs(units, eid, 0, "down"), "going down works")
	assert_eq(int(w.dungeons.locate(units[0].pos)["floor"]), 1, "now on the second floor")
	assert_true(w.dungeons.use_stairs(units, eid, 1, "up"), "and back up")
	assert_eq(int(w.dungeons.locate(units[0].pos)["floor"]), 0, "first floor again")
	assert_true(w.dungeons.use_stairs(units, eid, 0, "up"), "out through the exit")
	assert_true(w.dungeons.locate(units[0].pos).is_empty(), "back on the surface")
	assert_false(w.dungeons.use_stairs(units, eid, 2, "down"), "the last floor has no way down")


func _average_hp(w: World, fid: int) -> float:
	var total := 0.0
	var n := 0
	for u: Unit in w.factions.site_units(fid):
		if u.named.is_empty():
			total += float(u.stats["max_hp"])
			n += 1
	return total / maxf(1.0, float(n))


func test_deeper_floors_and_harder_dungeons_are_stronger() -> void:
	var w := _new()
	var easy := _spawn(w, 1, 4, "goblins")
	var hard := _spawn(w, 4, 4, "goblins")
	var easy_hp := []
	var hard_hp := []
	for f in 4:
		easy_hp.append(_average_hp(w, w.dungeons.ensure_floor(easy, f)))
		hard_hp.append(_average_hp(w, w.dungeons.ensure_floor(hard, f)))
	for f in range(1, 4):
		assert_true(float(easy_hp[f]) > float(easy_hp[f - 1]), "floor %d enemies are tougher (easy)" % f)
		assert_true(float(hard_hp[f]) > float(hard_hp[f - 1]), "floor %d enemies are tougher (hard)" % f)
	assert_true(float(hard_hp[0]) > float(easy_hp[0]), "the hard dungeon starts tougher than the easy one")
	var boss: Unit = w.get_unit(int(w.dungeons.floor_site(hard, 3)["boss_id"]))
	var easy_boss: Unit = w.get_unit(int(w.dungeons.floor_site(easy, 3)["boss_id"]))
	assert_true(boss != null and easy_boss != null, "the last floor has a boss")
	assert_true(float(boss.stats["max_hp"]) > float(easy_boss.stats["max_hp"]) * 2.0, "the hard boss is far tougher")


func test_harder_dungeons_drop_better_loot() -> void:
	var w := _new()
	var easy := _spawn(w, 1, 3)
	var hard := _spawn(w, 5, 3)
	var tiers := {}
	for eid: int in [easy, hard]:
		var total := 0.0
		var count := 0
		var before := w.loot_bags.keys()
		for f in 3:
			w.dungeons.ensure_floor(eid, f)
		for id: int in w.loot_bags:
			if before.has(id):
				continue
			var bag: Dictionary = w.loot_bags[id]
			if w.dungeons.locate(bag["pos"]).get("eid", -1) != eid:
				continue
			for item: Dictionary in bag["items"]:
				total += float(DB.get_def("items/qualities", str(item["quality"])).get("tier", 2)) + float(item["level"]) * 0.2
				count += 1
		tiers[eid] = total / maxf(1.0, float(count))
	assert_true(float(tiers[hard]) > float(tiers[easy]), "hard dungeons pay better (%.2f vs %.2f)" % [tiers[hard], tiers[easy]])


func test_killing_the_boss_clears_the_dungeon_and_pays() -> void:
	var w := _new()
	var eid := _spawn(w, 3, 2)
	var units := w.squad_ai.members(w.squads[0])
	w.dungeons.enter(units, eid)
	w.dungeons.use_stairs(units, eid, 0, "down")
	var fst := w.dungeons.floor_site(eid, 1)
	var boss: Unit = w.get_unit(int(fst["boss_id"]))
	w.combat.apply_damage(boss, 1.0e9, units[0])
	assert_eq(str((w.sites[eid] as Dictionary)["state"]), "cleared", "the dungeon is cleared")
	var relics := 0
	var cores := 0
	for bag: Dictionary in w.loot_bags.values():
		for item: Dictionary in bag["items"]:
			if str(item.get("relic_theme", "")) == "brigands":
				relics += 1
				assert_true(int(DB.get_def("items/qualities", str(item["quality"]))["tier"]) >= 5, "difficulty three guarantees an epic relic")
			if str(item.get("base", "")) == "master_core":
				cores += 1
	assert_true(relics >= 1, "the master guarantees a theme relic")
	assert_eq(cores, 1, "the master pays one forging core")
	assert_eq(int(w.counters.get("dungeons_cleared", 0)), 1, "it is counted")


func test_dungeons_survive_a_save_and_load() -> void:
	var w := _new()
	var eid := _spawn(w, 3, 4, "reptiles")
	var units := w.squad_ai.members(w.squads[0])
	w.dungeons.enter(units, eid)
	w.dungeons.use_stairs(units, eid, 0, "down")
	var units_before: int = w.factions.site_units(int(w.dungeons.floor_site(eid, 1)["id"])).size()
	var text := JSON.stringify(SaveGame.to_dict(w))
	var loaded_result := SaveGame.parse(text)
	assert_true(loaded_result.has("world"), "parsed: %s" % str(loaded_result.get("error", "")))
	if not loaded_result.has("world"):
		return
	var back: World = loaded_result["world"]
	_worlds.append(back)
	assert_true(back.dungeons.enabled(), "the zone is restored")
	var st: Dictionary = back.sites[eid]
	assert_eq(int(st["difficulty"]), 3, "difficulty kept")
	assert_eq(int(st["floors"]), 4, "floor count kept")
	assert_eq(str(st["theme"]), "reptiles", "theme kept")
	assert_eq(back.dungeons.layout(eid, 1)["tiles"], w.dungeons.layout(eid, 1)["tiles"], "floors regenerate identically")
	assert_eq(back.factions.site_units(int(back.dungeons.floor_site(eid, 1)["id"])).size(), units_before, "monsters kept")
	var unit_back := back.get_unit(units[0].id)
	assert_eq(back.dungeons.locate(unit_back.pos), {"eid": eid, "floor": 1}, "the squad is still on floor 2")
	assert_true(back.is_walkable(Vector2i(int(unit_back.pos.x), int(unit_back.pos.y))), "and standing on floor")
	back.dungeons.on_new_day()  # the restored system keeps working


func test_dungeons_close_after_a_while() -> void:
	var w := _new()
	var eid := _spawn(w, 1, 2)
	var st: Dictionary = w.sites[eid]
	st["spawn_day"] = w.day - Dungeons.UNVISITED_DAYS - 1
	w.dungeons.on_new_day()
	assert_false(w.sites.has(eid), "an entrance nobody visited collapses")
	assert_true(w.dungeons.entrances().size() <= 1, "its slot is free again")


func test_an_auto_squad_delves_to_the_bottom_clears_it_and_comes_home() -> void:
	var w := _new()
	var eid := _spawn(w, 1, 2, "goblins")
	var squad := w.squads[0]
	# The delve begins at its entrance; a random surface location may be on another river bank.
	var gate := w.dungeons.gate_pos(w.sites[eid])
	w.dungeons._place_units(w.squad_ai.members(squad), gate + Vector2(0, 5))
	for id: int in squad.members:
		var u := w.get_unit(id)
		u.named["stat_mult"] = {"max_hp": 30.0, "damage": 12.0}
		u.recompute_stats()
		u.hp = float(u.stats["max_hp"])
	w.squad_ai.order_squad(squad, {"type": "enter", "site": eid, "pos": w.dungeons.gate_pos(w.sites[eid])})
	var deepest := -1
	var cleared_at := -1
	var out_at := -1
	for tick in 9000:
		w.tick()
		var loc := w.dungeons.squad_location(squad)
		if not loc.is_empty():
			deepest = maxi(deepest, int(loc["floor"]))
			if deepest == 0 and str(squad.order.get("type", "")) == "idle":
				# arrived on the first floor with nothing to do: send the delve off
				w.squad_ai.order_squad(squad, {"type": "auto"})
		elif deepest >= 0 and out_at < 0:
			out_at = tick
		if cleared_at < 0 and str((w.sites[eid] as Dictionary)["state"]) == "cleared":
			cleared_at = tick
		if out_at >= 0 and cleared_at >= 0:
			break
	assert_eq(deepest, 1, "the squad reached the last floor")
	assert_true(cleared_at >= 0, "the master fell and the dungeon was cleared")
	assert_true(out_at >= 0, "the squad climbed back out onto the surface")

func test_map_identity_separates_floors_not_tiles() -> void:
	var w := _new()
	var eid := _spawn(w, 1, 2)
	w.dungeons.ensure_floor(eid, 0)
	w.dungeons.ensure_floor(eid, 1)
	var first := Vector2(w.dungeons.floor_origin(eid, 0)) + Vector2(8.5, 8.5)
	var second := Vector2(w.dungeons.floor_origin(eid, 1)) + Vector2(8.5, 8.5)
	assert_true(w.dungeons.same_map(first, first + Vector2(3, 2)), "different tiles on one floor can interact")
	assert_false(w.dungeons.same_map(first, second), "adjacent floors cannot interact")
	assert_false(w.dungeons.same_map(first, w.home_pos()), "floor and surface remain isolated")
	assert_true(w.dungeons.same_map(w.home_pos(), w.home_pos() + Vector2(5, 0)), "surface positions share a map")

func test_surface_flight_cannot_enter_or_cross_dungeon_floors() -> void:
	var w := _new()
	var z := w.gen.dungeon_zone
	var left_side := z.position.x == w.gen.min_tile
	var start := Vector2(z.end.x + 10, z.position.y + 10) if left_side else Vector2(z.position.x - 10, z.position.y + 10)
	var destination := Vector2(z.position.x + 10, z.end.y + 10) if left_side else Vector2(z.end.x - 10, z.end.y + 10)
	var drone := CharacterFactory.make_machine(w, "scout_drone", "player", start)
	drone.stats["move_speed"] = 100.0
	assert_true(w.move_unit(drone, destination), "surface flight can reach the other side")
	for step in 200:
		w._move(drone)
		assert_false(w.gen.in_zone_tile(drone.tile()), "flight never visits a hidden dungeon floor")
		if not drone.moving:
			break
	assert_true(drone.pos.distance_to(destination) < 0.1, "detour reaches the surface destination")
	var eid := _spawn(w, 1, 2)
	w.dungeons.ensure_floor(eid, 0)
	var interior := Vector2(w.dungeons.floor_origin(eid, 0)) + Vector2(8.5, 8.5)
	assert_false(w.move_unit(drone, interior), "ordinary flight cannot replace entering through the gate")
