extends TestCase
## Exact work-zone shape, editing, farm-mask and save-migration behavior.

const SEED := 4242

var _worlds: Array[World] = []


func after_all() -> void:
	for world: World in _worlds:
		world.dispose()
	_worlds.clear()


func _world() -> World:
	var world := World.new()
	world.setup(SEED)
	_worlds.append(world)
	return world


func _zone(world: World, type: String) -> Dictionary:
	for zone: Dictionary in world.zones:
		if str(zone["type"]) == type:
			return zone
	return {}


func _prepare_tile(world: World, tile: Vector2i, terrain: int = Tiles.GRASS) -> void:
	var chunk := world.ensure_chunk(world.chunk_key(tile))
	world.set_terrain(tile, terrain)
	world.set_res(tile, Tiles.Res.NONE, 0)
	chunk.blocked[world._li(tile)] = 0
	world.explored[world._fi(tile)] = 1


func test_same_kind_bridging_merges_transitively_and_keeps_oldest_id() -> void:
	var world := _world()
	var left := world.add_zone("logging", Rect2i(0, 0, 1, 1))
	var right := world.add_zone("logging", Rect2i(2, 0, 1, 1))
	assert_eq(world.zones.size(), 2, "a one-tile gap keeps the zones separate")
	var oldest_id := mini(int(left["id"]), int(right["id"]))
	world.add_zone("logging", Rect2i(1, 0, 1, 1))
	assert_eq(world.zones.size(), 1, "the bridging paint merges both neighbors")
	var merged := world.zones[0] as Dictionary
	assert_eq(int(merged["id"]), oldest_id, "the oldest existing id survives the transitive merge")
	assert_eq(merged["tiles"].size(), 3, "the merged shape contains only the painted tiles")
	assert_eq(merged["rect"], Rect2i(0, 0, 3, 1), "the bounding box is derived from the tile set")


func test_l_shape_keeps_holes_out_of_membership_and_worker_jobs() -> void:
	var world := _world()
	var origin := world.gen.start_tile
	var hole := origin + Vector2i(1, 1)
	var zone_tile := origin
	world.ensure_chunk(world.chunk_key(zone_tile))
	world.ensure_chunk(world.chunk_key(hole))
	world.set_res(zone_tile, Tiles.Res.ROCK_SMALL, 2)
	world.set_res(hole, Tiles.Res.ROCK_SMALL, 2)
	world.add_zone("mining", Rect2i(origin, Vector2i(3, 1)))
	world.add_zone("mining", Rect2i(origin + Vector2i(0, 1), Vector2i(1, 2)))
	var zone := _zone(world, "mining")
	assert_eq(zone["tiles"].size(), 5, "the two paints form a five-tile L")
	assert_true(ZoneShape.contains(zone, zone_tile), "painted tiles are members")
	assert_false(ZoneShape.contains(zone, hole), "a bounding-box hole is not a member")
	assert_eq(world.zone_type_at(hole), "", "zone lookup ignores empty cells inside the bounds")
	var jobs := world.colony._collect()
	var found_inside := false
	var found_hole := false
	for job: Dictionary in jobs:
		if str(job.get("type", "")) != "gather":
			continue
		if Vector2i(job["tile"]) == zone_tile:
			found_inside = true
		if Vector2i(job["tile"]) == hole:
			found_hole = true
	assert_true(found_inside, "workers receive a resource job inside the exact shape")
	assert_false(found_hole, "workers never enumerate a resource in the bounding-box hole")


func test_diagonal_tiles_stay_separate_and_different_types_overlap() -> void:
	var world := _world()
	var origin := Vector2i(8, 8)
	world.add_zone("logging", Rect2i(origin, Vector2i.ONE))
	world.add_zone("logging", Rect2i(origin + Vector2i(1, 1), Vector2i.ONE))
	assert_eq(world.zones.size(), 2, "diagonal contact does not connect zones")
	world.add_zone("mining", Rect2i(origin, Vector2i.ONE))
	assert_eq(world.zones.size(), 3, "different work types retain overlapping designations")
	assert_true(world.has_zone_tile("logging", origin), "the original type remains at the overlap")
	assert_true(world.has_zone_tile("mining", origin), "the overlapping type retains its exact tile")
	assert_eq(world.zone_type_at(origin), "logging", "overlap lookup preserves existing array precedence")


func test_partial_erase_counts_unique_tiles_and_splits_with_stable_ids() -> void:
	var world := _world()
	var logging := world.add_zone("logging", Rect2i(0, 0, 5, 3))
	var mining := world.add_zone("mining", Rect2i(0, 0, 5, 3))
	var removed := world.remove_zones_in(Rect2i(2, 0, 1, 3))
	assert_eq(removed, 3, "overlapping types count each erased grid tile once")
	assert_eq(world.zones.size(), 4, "each original shape splits into left and right components")
	assert_true(world.has_zone_tile("logging", Vector2i(0, 1)), "left logging remnant remains")
	assert_true(world.has_zone_tile("logging", Vector2i(4, 1)), "right logging remnant remains")
	assert_false(world.has_zone_tile("logging", Vector2i(2, 1)), "erased cells leave no membership")
	assert_eq(int(_zone_at(world, "logging", Vector2i(0, 1))["id"]), int(logging["id"]),
		"the deterministic first component keeps the old logging id")
	assert_ne(int(_zone_at(world, "logging", Vector2i(4, 1))["id"]), int(logging["id"]),
		"the other logging component receives a fresh id")
	assert_eq(int(_zone_at(world, "mining", Vector2i(0, 1))["id"]), int(mining["id"]),
		"the deterministic first mining component keeps its old id")
	assert_eq(_zone_at(world, "logging", Vector2i(0, 1))["rect"], Rect2i(0, 0, 2, 3),
		"the left remnant has a tight derived bound")


func _zone_at(world: World, type: String, tile: Vector2i) -> Dictionary:
	for zone: Dictionary in world.zones:
		if str(zone["type"]) == type and ZoneShape.contains(zone, tile):
			return zone
	return {}


func test_farm_paint_uses_only_eligible_or_existing_tiles_and_preserves_state() -> void:
	var world := _world()
	world.explored.fill(1)
	var first := world.gen.start_tile
	var second := first + Vector2i(1, 0)
	var invalid := first + Vector2i(2, 0)
	var preview_only := first + Vector2i(3, 0)
	for tile: Vector2i in [first, second, preview_only]:
		_prepare_tile(world, tile)
	_prepare_tile(world, invalid, Tiles.DEEP_WATER)
	assert_true(world.can_farm_at(preview_only), "the preview accepts an eligible new tile")
	var zone := world.add_zone("farm", Rect2i(first, Vector2i(3, 1)))
	assert_eq(zone["tiles"].size(), 2, "the farm mask excludes invalid terrain")
	assert_true(ZoneShape.contains(zone, first) and ZoneShape.contains(zone, second), "eligible tiles join the mask")
	assert_false(ZoneShape.contains(zone, invalid), "ineligible painted cells are not designated")
	assert_false(world.can_farm_at(first), "an existing farm tile is not previewed as new")
	var state := world.farm[first] as Dictionary
	state["stage"] = 2
	state["growth"] = 0.73
	state["crop"] = "veg"
	world.add_zone("farm", Rect2i(first, Vector2i(3, 1)))
	assert_eq(world.zones.size(), 1, "repainting an existing farm does not duplicate the zone")
	assert_eq(world.farm[first], {"stage": 2, "growth": 0.73, "crop": "veg"},
		"duplicate paint preserves the current crop stage and growth")
	assert_true(world.can_farm_at(preview_only), "preview remains valid for an unpainted eligible tile")
	world.add_zone("farm", Rect2i(first, Vector2i(4, 1)))
	assert_eq(world.zones.size(), 2, "disconnected eligible farm islands remain separate connected zones")
	assert_true(world.has_zone_tile("farm", preview_only), "the separate island remains in the painted farm mask")
	for farm_zone: Dictionary in world.zones:
		assert_eq(ZoneShape.connected_components(farm_zone["tiles"]).size(), 1, "every runtime zone is connected")



func test_erasing_designations_cancels_unstarted_jobs_without_losing_cargo() -> void:
	var world := _world()
	var gather_tile := Vector2i(10, 10)
	var farm_tile := Vector2i(11, 10)
	world.add_zone("mining", Rect2i(gather_tile, Vector2i.ONE))
	world.farm[farm_tile] = {"stage": 0, "growth": 0.0, "crop": "wheat"}
	for tile: Vector2i in [gather_tile, farm_tile]:
		var worker := Unit.new()
		worker.id = world.new_id()
		worker.pos = Vector2(tile) + Vector2(0.5, 0.5)
		worker.job = {"type": "gather" if tile == gather_tile else "farm", "tile": tile, "phase": "go",
			"designated": tile == gather_tile, "zone_type": "mining", "key": tile}
		worker.moving = true
		worker.path = PackedVector2Array([worker.pos, worker.pos + Vector2.RIGHT])
		worker.state = Unit.State.MOVE
		worker.carry_res = "wood"
		worker.carry_amount = 5
		world.units[worker.id] = worker
		world.unit_list.append(worker)
	world.remove_zones_in(Rect2i(gather_tile, Vector2i(2, 1)))
	for worker: Unit in world.unit_list:
		assert_true(worker.job.is_empty(), "unstarted work outside the remaining designation is released")
		assert_false(worker.moving, "cancelled workers stop travelling to erased tiles")
		assert_eq(worker.carry_res, "wood", "cancellation preserves carried resource type")
		assert_eq(worker.carry_amount, 5, "cancellation preserves carried cargo")

func test_exact_save_round_trip_and_legacy_farm_rectangle_migration() -> void:
	var world := _world()
	world.add_zone("logging", Rect2i(4, 4, 3, 1))
	world.add_zone("logging", Rect2i(4, 5, 1, 2))
	var saved_farm_tile := Vector2i(30, 31)
	world.farm[saved_farm_tile] = {"stage": 2, "growth": 0.61, "crop": "veg"}
	world.restore_zone(world.new_id(), "farm", {saved_farm_tile: true})
	var exact_data := SaveGame.to_dict(world)
	assert_true(exact_data["zones"][0].has("tiles"), "new saves store exact zone tiles")
	assert_false(exact_data["zones"][0].has("rect"), "new saves do not serialize the derived bounding box")
	var exact_result := SaveGame.parse(JSON.stringify(exact_data))
	assert_true(exact_result.has("world"), "the exact-shape save parses")
	if not exact_result.has("world"):
		return
	var exact_world: World = exact_result["world"]
	_worlds.append(exact_world)
	var exact_mining_zone := _zone(exact_world, "logging")
	assert_eq(exact_mining_zone["tiles"], _zone(world, "logging")["tiles"], "the L membership round-trips exactly")
	assert_false(ZoneShape.contains(exact_mining_zone, Vector2i(5, 5)), "the L hole stays empty after loading")
	assert_eq(exact_world.farm[saved_farm_tile], world.farm[saved_farm_tile], "farm state round-trips unchanged")

	var legacy := _world()
	legacy.explored.fill(1)
	var origin := legacy.gen.start_tile
	for offset in 3:
		_prepare_tile(legacy, origin + Vector2i(offset, 0))
	var old_farm_tile := origin
	legacy.farm[old_farm_tile] = {"stage": 2, "growth": 0.84, "crop": "wheat"}
	var legacy_zone_id := legacy.new_id()
	var legacy_mining_id := legacy.new_id()
	var legacy_data := SaveGame.to_dict(legacy)
	legacy_data["version"] = 1
	legacy_data["zones"] = [
		{"id": legacy_zone_id, "type": "farm", "rect": [origin.x, origin.y, 3, 1]},
		{"id": legacy_mining_id, "type": "mining", "rect": [20, 20, 2, 2]},
	]
	var legacy_result := SaveGame.parse(JSON.stringify(legacy_data))
	assert_true(legacy_result.has("world"), "version-one rectangle saves remain loadable")
	if not legacy_result.has("world"):
		return
	var migrated: World = legacy_result["world"]
	_worlds.append(migrated)
	var migrated_zone := _zone(migrated, "farm")
	assert_eq(migrated_zone["tiles"], {old_farm_tile: true}, "legacy farm rectangles migrate from saved farm tiles only")
	var migrated_mining_zone := _zone(migrated, "mining")
	assert_eq(migrated_mining_zone["tiles"].size(), 4, "legacy non-farm rectangles migrate to their full exact grid area")
	assert_eq(migrated.farm, legacy.farm, "legacy migration does not change farm growth or crop state")
	assert_true(migrated.can_farm_at(origin + Vector2i(1, 0)),
		"eligible tiles omitted from the old farm mask are not silently added during migration")
