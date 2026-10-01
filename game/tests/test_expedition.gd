extends TestCase
## Consumer-visible boundaries: avoidable attacks, summon caps, territory safety, loot power,
## transactional crafting and save continuation. Tests do not depend on rendered art or text.
var _worlds: Array[World] = []

func _new() -> World:
	var w := NewGame.create(11)
	_worlds.append(w)
	return w

func after_all() -> void:
	for w: World in _worlds:
		w.dispose()
	_worlds.clear()

func _boss(w: World) -> Unit:
	var eid := w.dungeons.spawn_entrance(RngUtil.make([w.seed, "expedition"]), {"difficulty": 1, "floors": 2, "theme": "machines"})
	w.dungeons.ensure_floor(eid, 1)
	return w.get_unit(int(w.dungeons.floor_site(eid, 1)["boss_id"]))

func _workshop(w: World) -> void:
	var home := Vector2i(w.home_pos())
	for r in range(10, 35):
		for delta: Vector2i in [Vector2i(r, 0), Vector2i(-r, 0), Vector2i(0, r), Vector2i(0, -r)]:
			var b := w.place_building("workshop", home + delta, true)
			if b != null:
				return
	assert_true(false, "test fixture has room for a workshop")

func test_quality_increases_power_without_slowing_weapons() -> void:
	var common := ItemGen.generate(RngUtil.make([81]), {"base": "sword", "level": 5, "quality": "common"})
	var rare := ItemGen.generate(RngUtil.make([81]), {"base": "sword", "level": 5, "quality": "legendary"})
	assert_true(float(rare["stats"]["damage"]) > float(common["stats"]["damage"]), "better quality deals more damage")
	assert_eq(rare["stats"]["cooldown"], common["stats"]["cooldown"], "quality never makes a weapon slower")
	assert_eq(rare["stats"]["range"], common["stats"]["range"], "reach is the weapon's handling, not random quality")
	assert_true(float(rare["stats"]["accuracy"]) <= 1.0, "accuracy remains a probability")

func test_earthshatter_can_be_escaped_and_does_not_fire_after_death() -> void:
	var w := _new()
	var boss := _boss(w)
	var victim := CharacterFactory.make_colonist(w, {}, boss.pos + Vector2(3, 0))
	var evader := CharacterFactory.make_colonist(w, {}, victim.pos + Vector2(0, 1))
	var hp := victim.hp
	var escape_hp := evader.hp
	w.combat._execute_ability(boss, "earthshatter", victim, victim.pos)
	w.combat._casts()
	assert_eq(victim.hp, hp, "warning precedes the hit")
	evader.pos += Vector2(9, 0)
	w._rebuild_grid()
	for tick in 25:
		w.combat._casts()
	assert_true(victim.hp < hp, "remaining in the marked area takes damage")
	assert_eq(evader.hp, escape_hp, "leaving the marked area avoids it")
	w.combat._execute_ability(boss, "earthshatter", evader, evader.pos)
	w.combat.apply_damage(boss, 1.0e9, victim)
	for tick in 25:
		w.combat._casts()
	assert_eq(evader.hp, escape_hp, "dead casters cannot deliver queued hits")

func test_master_summons_are_capped_and_enrage_survives_save() -> void:
	var w := _new()
	var boss := _boss(w)
	for attempt in 4:
		w.combat._execute_ability(boss, "call_guardians", null, boss.pos)
	var count := 0
	for u: Unit in w.unit_list:
		if int(u.named.get("summoner", -1)) == boss.id:
			count += 1
	assert_eq(count, 4, "summons never exceed the living cap")
	var damage := float(boss.stats["damage_mult"])
	boss.hp = float(boss.stats["max_hp"]) * 0.49
	w.combat._abilities()
	assert_true(float(boss.stats["damage_mult"]) > damage, "crossing half health increases damage")
	var parsed := SaveGame.parse(JSON.stringify(SaveGame.to_dict(w)))
	var back: World = parsed["world"]
	_worlds.append(back)
	assert_eq(int(back.get_unit(boss.id).named["phase"]), 2, "phase restored")
	assert_eq(back.get_unit(boss.id).stats["damage_mult"], boss.stats["damage_mult"], "phase power is not lost or applied twice")

func test_saved_warning_resolves_once_after_loading() -> void:
	var w := _new()
	var boss := _boss(w)
	var victim := CharacterFactory.make_colonist(w, {}, boss.pos + Vector2(3, 0))
	w.combat._execute_ability(boss, "earthshatter", victim, victim.pos)
	for tick in 10:
		w.combat._casts()
	var parsed := SaveGame.parse(JSON.stringify(SaveGame.to_dict(w)))
	var back: World = parsed["world"]
	_worlds.append(back)
	var restored := back.get_unit(victim.id)
	var hp := restored.hp
	back._rebuild_grid()
	for tick in 15:
		back.combat._casts()
	assert_true(restored.hp < hp, "saved windup delivers its remaining hit")
	var hit_hp := restored.hp
	for tick in 30:
		back.combat._casts()
	assert_eq(restored.hp, hit_hp, "resolving the warning consumes it")

func test_beast_chases_then_returns_and_refuses_colony_targets() -> void:
	var w := _new()
	var tile := w.dungeons._pick_location(RngUtil.make([11, "beast_test"]))
	var beast := w.giants.spawn_beast(Vector2(tile) + Vector2(0.5, 0.5))
	var u := w.get_unit(w.squads[0].members[0])
	u.pos = beast.pos + Vector2(4, 0)
	w._rebuild_grid()
	w.giants.think(beast)
	assert_eq(beast.target_id, u.id, "nearby intruder starts a chase")
	beast.pos += Vector2(5, 0)
	u.pos = beast.guard_pos + Vector2(45, 0)
	w.giants.think(beast)
	assert_eq(beast.target_id, -1, "a distant intruder is released")
	assert_eq(str(beast.named["mood"]), "return", "beast returns instead of raiding")
	var safe_edge := Vector2.ZERO
	var protected := Vector2.ZERO
	for b: Building in w.buildings.values():
		if b.faction != "player":
			continue
		for step in 24:
			var direction := Vector2.from_angle(step * TAU / 24.0)
			var candidate := b.center() + direction * 44.0
			if not w.giants.near_colony(candidate):
				safe_edge = candidate
				protected = b.center() + direction * 37.0
				break
		if safe_edge != Vector2.ZERO:
			break
	assert_true(safe_edge != Vector2.ZERO, "fixture has a colony boundary")
	beast.named["mood"] = "wander"
	beast.pos = safe_edge
	beast.guard_pos = safe_edge
	u.pos = protected
	w._rebuild_grid()
	w.giants.think(beast)
	assert_eq(beast.target_id, -1, "colony safety beats proximity")
	assert_false(w.giants.near_colony(beast.pos), "beast stays outside colony safety")

func test_forge_upgrade_repair_and_salvage_are_transactional() -> void:
	var w := _new()
	_workshop(w)
	w.res["gold"] = 500
	w.res["metal"] = 300
	var trophy := ItemGen.trophy("master_core", 5)
	trophy["uid"] = w.new_id()
	w.armory.append(trophy)
	assert_eq(w.gearwork.forge("brigands"), "", "trophy can become usable gear")
	assert_false(w.armory.has(trophy), "forge consumes its trophy")
	var item: Dictionary = w.armory[-1]
	var uid := int(item["uid"])
	var u := w.get_unit(w.squads[0].members[0])
	w.armory.erase(item)
	u.equipment()["weapon"] = item
	u.recompute_stats()
	var power := float(u.stats["weapon"]["damage"])
	var metal := int(w.res["metal"])
	assert_eq(w.gearwork.act(uid, "dismantle"), "gear.error.equipped", "stale salvage button cannot destroy equipped gear")
	assert_eq(int(w.res["metal"]), metal, "rejected salvage changes no resources")
	for step in 3:
		assert_eq(w.gearwork.act(uid, "upgrade"), "", "upgrade succeeds")
	assert_true(float(u.stats["weapon"]["damage"]) > power, "upgrade affects the wearer's actual weapon")
	var resources := w.res.duplicate()
	assert_eq(w.gearwork.act(uid, "upgrade"), "gear.error.max", "fourth upgrade rejected")
	assert_eq(w.res, resources, "upgrade cap spends nothing")
	item["condition"] = 10.0
	u.recompute_stats()
	var worn := float(u.stats["weapon"]["damage"])
	assert_eq(w.gearwork.act(uid, "repair"), "", "damaged gear repaired")
	assert_true(float(u.stats["weapon"]["damage"]) > worn, "repair restores effective damage")
	u.equipment()["weapon"] = null
	w.armory.append(item)
	assert_eq(w.gearwork.act(uid, "dismantle"), "", "unequipped gear salvaged")
	assert_true(w.gearwork.owned(uid).is_empty(), "salvage removes ownership")
	resources = w.res.duplicate()
	assert_eq(w.gearwork.act(uid, "dismantle"), "gear.error.item", "same uid cannot be salvaged twice")
	assert_eq(w.res, resources, "repeat salvage pays nothing")

func test_failed_crafting_spends_nothing_and_relics_are_deterministic() -> void:
	var w := _new()
	_workshop(w)
	var item := ItemGen.relic(RngUtil.make([77]), "machines", 4, 3)
	assert_eq(item, ItemGen.relic(RngUtil.make([77]), "machines", 4, 3), "same expedition seed, same relic")
	item["uid"] = w.new_id()
	w.armory.append(item)
	w.res["gold"] = 0
	var before := item.duplicate(true)
	var res_before := w.res.duplicate()
	assert_eq(w.gearwork.act(item["uid"], "upgrade"), "gear.error.resources", "insufficient materials rejected")
	assert_eq(item, before, "failed work preserves the item")
	assert_eq(w.res, res_before, "failed work preserves resources")

func test_relic_retains_generated_affixes_and_adds_its_theme_effect() -> void:
	var rng := RngUtil.make([713])
	var ordinary := ItemGen.generate(rng, {"base": "sensor_array", "level": 7, "quality": "epic"})
	var relic := ItemGen.relic(RngUtil.make([713]), "machines", 7, 3)
	assert_eq(float(relic["mods"].get("vision", 0.0)), float(ordinary["mods"].get("vision", 0.0)), "relic retains the sensor and affix sight bonuses")
	assert_eq(float(relic["mods"]["energy_max"]), float(ordinary["mods"].get("energy_max", 0.0)) + 35.0, "theme effect adds to generated modifiers")

func test_giant_cannot_cross_a_one_tile_door_but_uses_a_wide_one() -> void:
	var w := _new()
	var boss := _boss(w)
	var loc := w.dungeons.locate(boss.pos)
	var origin := w.dungeons.floor_origin(int(loc["eid"]), int(loc["floor"])) + Vector2i(3, 3)
	for y in 18:
		for x in 18:
			var tile := origin + Vector2i(x, y)
			var ch := w.chunk_at_tile(tile)
			var i := w._li(tile)
			ch.res_type[i] = Tiles.Res.NONE
			ch.terrain[i] = Tiles.PAVED
			ch.blocked[i] = 1 if x == 0 or y == 0 or x == 17 or y == 17 or (x == 9 and y != 8) else 0
			w._nav_update_tile(tile)
	boss.pos = Vector2(origin) + Vector2(5.5, 8.5)
	var destination := Vector2(origin) + Vector2(13.5, 8.5)
	var small_path := w.find_path(boss.pos, destination)
	assert_eq(small_path[-1], destination, "ordinary units fit through a single tile")
	var giant_path := w.giants.path(boss, destination)
	assert_true(giant_path.is_empty() or giant_path[-1] != destination, "giant cannot squeeze through")
	for y in [7, 9]:
		var tile := origin + Vector2i(9, y)
		w.chunk_at_tile(tile).blocked[w._li(tile)] = 0
		w._nav_update_tile(tile)
	giant_path = w.giants.path(boss, destination)
	assert_eq(giant_path[-1], destination, "three-tile door admits the giant")

func test_move_order_escapes_warning_without_reentering_melee() -> void:
	var w := _new()
	var boss := _boss(w)
	var squad := w.squads[0]
	var unit := w.get_unit(squad.members[0])
	squad.members = PackedInt32Array([unit.id])
	squad.auto_abilities = false
	var loc := w.dungeons.locate(boss.pos)
	w.dungeons.enter([unit], int(loc["eid"]))
	w.dungeons.use_stairs([unit], int(loc["eid"]), 0, "down")
	for enemy: Unit in w.factions.site_units(boss.home_site):
		if enemy != boss:
			w.remove_unit(enemy)
	unit.pos = boss.pos + Vector2(-2, 0)
	unit.prev_pos = unit.pos
	boss.visible = true
	var warning_pos := unit.pos
	w.combat._execute_ability(boss, "earthshatter", unit, warning_pos)
	w.squad_ai.order_squad(squad, {"type": "move", "pos": boss.pos + Vector2(3.5, 0)})
	w.combat.apply_damage(unit, 1.0, boss)
	var hp := unit.hp
	for step in 25:
		w.tick()
		if not boss.named.has("cast"):
			break
	assert_true(unit.pos.distance_to(warning_pos) > 3.5 + unit.body_radius(), "movement leaves the marked area before impact")
	assert_eq(unit.hp, hp, "AI retaliation does not turn a dodge back into melee")

func _loot_room(w: World) -> Vector2i:
	var boss := _boss(w)
	var loc := w.dungeons.locate(boss.pos)
	var origin := w.dungeons.floor_origin(int(loc["eid"]), int(loc["floor"])) + Vector2i(3, 3)
	for enemy: Unit in w.factions.site_units(boss.home_site):
		w.remove_unit(enemy)
	for y in 18:
		for x in 18:
			var tile := origin + Vector2i(x, y)
			var ch := w.chunk_at_tile(tile)
			var i := w._li(tile)
			ch.res_type[i] = Tiles.Res.NONE
			ch.terrain[i] = Tiles.PAVED
			ch.blocked[i] = 1 if x == 0 or y == 0 or x == 17 or y == 17 or (x >= 7 and x <= 11 and y >= 6 and y <= 10) else 0
			w._nav_update_tile(tile)
	var squad := w.squads[0]
	var unit := w.get_unit(squad.members[0])
	squad.members = PackedInt32Array([unit.id])
	w.squad_ai.order_squad(squad, {"type": "idle"})
	unit.pos = Vector2(origin) + Vector2(4.5, 8.5)
	unit.prev_pos = unit.pos
	return origin

func test_airborne_loot_lands_on_collectible_ground() -> void:
	var w := _new()
	var origin := _loot_room(w)
	var wall := Vector2(origin) + Vector2(9.5, 8.5)
	var item := ItemGen.generate(RngUtil.make([71]), {"base": "sword", "quality": "rare"})
	var bag := w.drop_loot(wall, [item])
	var landing: Vector2 = bag["pos"]
	assert_true(w.is_walkable(Vector2i(floori(landing.x), floori(landing.y))), "loot over a wall lands on ground")
	assert_true(w.dungeons.same_map(wall, landing), "loot remains on its original floor")
	for tick in 100:
		w.squad_ai._collect_loot(w.squads[0], 20.0)
		w.tick()
		if not w.loot_bags.has(bag["id"]):
			break
	assert_true(w.armory.has(item), "ground squad recovers airborne loot")

func test_unreachable_old_loot_does_not_block_other_pickups() -> void:
	var w := _new()
	var origin := _loot_room(w)
	var squad := w.squads[0]
	var unit := w.get_unit(squad.members[0])
	var old_bag := w.drop_loot(unit.pos, [], 9)
	old_bag["pos"] = Vector2(origin) + Vector2(9.5, 8.5)  # a pre-fix bag over solid rock
	var item := ItemGen.generate(RngUtil.make([72]), {"base": "bow", "quality": "rare"})
	w.drop_loot(Vector2(origin) + Vector2(4.5, 15.5), [item])
	for tick in 100:
		w.squad_ai._collect_loot(squad, 20.0)
		w.tick()
		if w.armory.has(item):
			break
	assert_true(w.armory.has(item), "unreachable nearest bag does not stall reachable loot")
	assert_true(w.loot_bags.has(old_bag["id"]), "unreachable loot is not silently deleted")
