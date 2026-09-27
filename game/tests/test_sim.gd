extends TestCase
## Simulation behaviour: new game setup, autonomous work, construction, determinism,
## save/load continuation, squad orders and combat.

const SEED := 4242


func _state(w: World) -> String:
	var d := SaveGame.to_dict(w)
	d.erase("saved_at")
	# Floats are rounded to 1e-6: the JSON text round trip changes the last bits of doubles, but
	# missing or wrongly restored state produces real differences in behaviour.
	return JSON.stringify(_round(JSON.parse_string(JSON.stringify(d))))


func _round(v: Variant) -> Variant:
	if v is float:
		return snappedf(v, 0.000001)
	if v is Dictionary:
		var out := {}
		for k: Variant in v:
			out[k] = _round(v[k])
		return out
	if v is Array:
		var out: Array = []
		for e: Variant in v:
			out.append(_round(e))
		return out
	return v


var _worlds: Array = []


func _new(seed: int) -> World:
	var w := NewGame.create(seed)
	_worlds.append(w)
	return w


func after_all() -> void:
	for w: World in _worlds:
		w.dispose()
	_worlds.clear()


func _run(w: World, ticks: int) -> void:
	for i in ticks:
		w.tick()


func test_new_game_founds_a_settlement() -> void:
	var w := _new(SEED)
	assert_true(w.population() >= 8, "population %d" % w.population())
	assert_true(w.buildings.size() >= 5, "buildings %d" % w.buildings.size())
	assert_eq(w.squads.size(), 1, "squads")
	assert_eq(w.squads[0].members.size(), 4, "alpha members")
	assert_true(w.farm.size() >= 12, "farm tiles %d" % w.farm.size())
	var types := {}
	for z: Dictionary in w.zones:
		types[z["type"]] = true
	assert_true(types.has("logging") and types.has("mining") and types.has("farm"), "zones %s" % str(types.keys()))
	var kinds := {}
	for u: Unit in w.unit_list:
		kinds[u.kind] = int(kinds.get(u.kind, 0)) + 1
	assert_true(kinds.has("robot") and kinds.has("drone") and kinds.has("airship"), "unit kinds %s" % str(kinds))
	for u: Unit in w.unit_list:
		if u.is_player() and not u.flying:
			assert_true(w.is_walkable(u.tile()), "%s starts on walkable ground" % u.name)


func test_settlers_work_on_their_own() -> void:
	var w := _new(SEED)
	var wood0 := int(w.res["wood"])
	var h := w.place_building("house", _free_spot(w, "house"), false)
	assert_true(h != null, "house placed")
	_run(w, 3600)  # 6 minutes of game time
	assert_true(int(w.counters.get("wood_gathered", 0)) > 0, "wood gathered %s" % str(w.counters))
	assert_true(int(w.counters.get("stone_gathered", 0)) + int(w.counters.get("ore_gathered", 0)) > 0, "stone/ore gathered %s" % str(w.counters))
	assert_true(h.is_built(), "house built (progress %.2f, needs %s)" % [h.progress, str(h.needs)])
	var harvested := 0.0
	for u: Unit in w.unit_list:
		harvested += float(u.counters.get("harvested", 0.0))
	assert_true(harvested > 0.0, "crops or berries harvested")
	assert_true(int(w.res["wood"]) != wood0, "wood changed")
	for r: String in World.RESOURCES:
		assert_true(int(w.res[r]) >= 0, "%s non-negative" % r)


func _free_spot(w: World, type: String) -> Vector2i:
	var st := w.gen.start_tile
	for r in range(4, 24):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if absi(dx) != r and absi(dz) != r:
					continue
				var o := st + Vector2i(dx, dz)
				if w.can_place(type, o) == "":
					return o
	return st


func test_same_seed_same_world() -> void:
	var a := _new(SEED)
	var b := _new(SEED)
	_run(a, 900)
	_run(b, 900)
	assert_eq(_state(a).md5_text(), _state(b).md5_text(), "state hash after 900 ticks")
	var c := _new(SEED + 1)
	assert_ne(c.gen.start_tile, a.gen.start_tile, "different seed, different start")


func test_save_load_continues_identically() -> void:
	var a := _new(SEED)
	_run(a, 700)
	var text := JSON.stringify(SaveGame.to_dict(a))
	var loaded := SaveGame.parse(text)
	assert_true(loaded.has("world"), "parse ok: %s" % str(loaded.get("error", "")))
	var b: World = loaded["world"]
	_worlds.append(b)
	assert_eq(_state(b).md5_text(), _state(a).md5_text(), "reloaded state equals saved state")
	_run(a, 600)
	_run(b, 600)
	assert_eq(_state(b).md5_text(), _state(a).md5_text(), "state after continuing 600 ticks")
	var bad := SaveGame.parse("{\"version\": 99}")
	assert_true(bad.has("error"), "unsupported version rejected")
	assert_true(SaveGame.parse("not json").has("error"), "damaged file rejected")


func test_multiple_squad_lifecycle_and_save_round_trip() -> void:
	var w := _new(SEED)
	var original := w.squads[0] as Squad
	var available: Array[Unit] = []
	for unit: Unit in w.unit_list:
		if unit.is_player() and unit.kind != "airship" and not original.members.has(unit.id):
			available.append(unit)
	assert_true(available.size() >= 3, "three eligible units for additional squads")
	if available.size() < 3:
		return
	var empty := w.create_squad("Empty Watch")
	var scouts := w.create_squad("North Scouts")
	var reserve := w.create_squad("Reserve")
	assert_eq(w.squads.size(), 4, "four squads including an empty squad")
	assert_true(w.assign_to_squad(available[0], scouts), "first scout assigned")
	assert_true(w.assign_to_squad(available[1], scouts), "second scout assigned")
	assert_true(w.assign_to_squad(available[2], reserve), "reserve assigned")
	assert_true(w.assign_to_squad(available[2], scouts), "member can move between squads")
	assert_true(reserve.members.is_empty(), "source squad remains as a valid empty squad")
	scouts.name = "Trailblazers"
	w.squad_ai.order_squad(scouts, {"type": "auto"})
	_run(w, 300)
	var loaded := SaveGame.parse(JSON.stringify(SaveGame.to_dict(w)))
	assert_true(loaded.has("world"), "multi-squad save parses")
	if not loaded.has("world"):
		return
	var restored: World = loaded["world"]
	_worlds.append(restored)
	assert_eq(restored.squads.size(), 4, "empty and populated squads persist")
	assert_eq(restored.get_squad(scouts.id).name, "Trailblazers", "rename persists")
	assert_eq(restored.get_squad(empty.id).members.size(), 0, "empty squad persists")
	assert_eq(restored.get_unit(available[2].id).squad_id, scouts.id, "moved membership persists")
	assert_true(restored.disband_squad(empty.id), "empty squad disbands")
	assert_true(restored.disband_squad(reserve.id), "second empty squad disbands")
	assert_eq(restored.squads.size(), 2, "disband removes only selected squads")
	while restored.squads.size() < World.MAX_SQUADS:
		assert_true(restored.create_squad("Squad %d" % restored.squads.size()) != null, "squad created below cap")
	assert_true(restored.create_squad("Too many") == null, "ninth hotkey is the hard squad cap")


func test_squad_move_and_explore() -> void:
	var w := _new(SEED)
	var s := w.squads[0]
	var dest := w.home_pos() + Vector2(10, 6)
	var t := w.nearest_walkable(Vector2i(dest), 6)
	w.squad_ai.order_squad(s, {"type": "move", "pos": Vector2(t) + Vector2(0.5, 0.5)})
	_run(w, 300)
	assert_true(w.squad_ai.center(s).distance_to(Vector2(t)) < 4.0, "squad arrived near %s (at %s)" % [t, w.squad_ai.center(s)])
	var explored0 := w.explored_count
	w.squad_ai.order_squad(s, {"type": "explore", "pos": w.home_pos(), "radius": 45.0})
	_run(w, 1800)
	assert_true(w.explored_count > explored0 + 300, "explored %d -> %d" % [explored0, w.explored_count])


func test_combat_kills_and_drops_loot() -> void:
	var w := _new(SEED)
	var s := w.squads[0]
	var p := w.squad_ai.center(s) + Vector2(4, 0)
	var t := w.nearest_walkable(Vector2i(p), 4)
	var bandit := CharacterFactory.make_npc(w, "bandit", "bandits", Vector2(t) + Vector2(0.5, 0.5), 1)
	bandit.visible = true
	w.squad_ai.order_squad(s, {"type": "attack", "target": bandit.id})
	_run(w, 400)
	assert_false(bandit.alive, "bandit defeated (hp %.1f)" % bandit.hp)
	assert_true(int(w.counters.get("kills", 0)) >= 1, "kill counted")
