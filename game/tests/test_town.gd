extends TestCase
## The mixed-race town: one per world in its distance band, service buildings and a mixed crowd,
## the smithy / inn / tavern rules, hiring into the colony, and the save/load round trip.

const SEEDS := [11, 4242, 90210, 777]

var _worlds: Array = []


func after_all() -> void:
	for w: World in _worlds:
		w.dispose()
	_worlds.clear()


func _towns(gen: WorldGen) -> Array:
	var out: Array = []
	for sid: Variant in gen.sites:
		var st: Dictionary = gen.sites[sid]
		if str(st["kind"]) == "town":
			out.append(st)
	return out


## A world with its town instantiated and discovered, the founder standing on the plaza.
func _town_world(seed: int = 4242) -> Array:
	var w := NewGame.create(seed)
	_worlds.append(w)
	var towns := _towns(w.gen)
	if towns.is_empty():
		fail("seed %d generated no town" % seed)
		return [w, {}]
	var sid := int(towns[0]["id"])
	w.factions.instantiate_site(sid)
	var st: Dictionary = w.sites[sid]
	st["discovered"] = true
	var visitor := w.get_unit(w.player_unit_id)
	visitor.pos = Vector2(st["center"]) + Vector2(0.5, 0.5)
	return [w, st]


func test_exactly_one_town_in_its_band_with_every_service() -> void:
	for seed: int in SEEDS:
		var gen := WorldGen.new(seed)
		var towns := _towns(gen)
		assert_eq(towns.size(), 1, "seed %d towns" % seed)
		if towns.is_empty():
			continue
		var st: Dictionary = towns[0]
		var d := Vector2(st["center"]).distance_to(Vector2(gen.start_tile))
		assert_between(d, 70.0, 150.0, "seed %d town distance" % seed)
		var types := {}
		var home_races := {}
		for s: Dictionary in st["structures"]:
			types[str(s["type"])] = true
			var t := str(s["type"])
			if t.begins_with("v_") and t.ends_with("_home"):
				home_races[t] = true
		for t: String in ["t_fountain", "t_guild_hall", "t_tavern", "t_general_store", "t_smithy", "t_inn"]:
			assert_true(types.has(t), "seed %d town has %s" % [seed, t])
		assert_true(home_races.size() >= 3, "seed %d homes of several races: %d" % [seed, home_races.size()])


func test_town_residents_are_a_mixed_crowd_with_shopkeepers_and_a_watch() -> void:
	var pair := _town_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	var races := {}
	var jobs := {}
	for id: Variant in st["units"]:
		var u := w.get_unit(int(id))
		if u == null:
			continue
		races[str(u.character.get("race", ""))] = true
		jobs[str(u.character.get("town_job", ""))] = true
		assert_false(u.is_player(), "residents are not colonists")
	assert_true(races.size() >= 3, "races in town: %s" % str(races.keys()))
	for job: String in ["watch", "storekeeper", "smith", "innkeeper", "barkeep", "guild_clerk"]:
		assert_true(jobs.has(job), "job %s present" % job)
	assert_true(w.town.mercenary_candidates(int(st["id"])).size() >= 3, "mercenaries at the tavern")


func test_services_need_a_colonist_in_town_and_peace() -> void:
	var pair := _town_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	var sid := int(st["id"])
	assert_eq(w.town.service_blocker(sid), "", "open with the founder on the plaza")
	for u: Unit in w.player_people():
		u.pos = Vector2(st["center"]) + Vector2(400, 400)
	assert_eq(w.town.service_blocker(sid), "town.error.no_unit", "nobody in town")
	w.get_unit(w.player_unit_id).pos = Vector2(st["center"]) + Vector2(0.5, 0.5)
	st["relation"] = -80
	assert_eq(w.town.service_blocker(sid), "town.error.hostile", "closed while hostile")


func test_smithy_sells_for_gold_and_buys_from_the_armory() -> void:
	var pair := _town_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	var sid := int(st["id"])
	var stock := w.town.smithy_stock(sid)
	var stock_size := stock.size()
	assert_true(stock_size >= 4, "smithy stock: %d" % stock_size)
	var item: Dictionary = stock[0]["item"]
	var price := w.town.smithy_price(sid, item)
	w.res["gold"] = price - 1
	assert_eq(w.town.buy_smithy(sid, 0), "town.error.no_gold", "too poor")
	w.res["gold"] = price
	var armory_before := w.armory.size()
	assert_eq(w.town.buy_smithy(sid, 0), "", "bought")
	assert_eq(int(w.res["gold"]), 0, "paid the price")
	assert_eq(w.armory.size(), armory_before + 1, "item in the armory")
	assert_eq(w.town.smithy_stock(sid).size(), stock_size - 1, "stock shrank by one")
	var owned: Dictionary = w.armory[w.armory.size() - 1]
	var payout := w.town.sell_price(sid, owned)
	assert_true(payout < price, "sells back below the buying price")
	assert_eq(w.town.sell_item(sid, int(owned["uid"])), "", "sold back")
	assert_eq(int(w.res["gold"]), payout, "got the payout")
	assert_eq(w.armory.size(), armory_before, "item left the armory")


func test_inn_heals_wounds_and_injuries_for_gold() -> void:
	var pair := _town_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	var sid := int(st["id"])
	var u := w.get_unit(w.player_unit_id)
	u.hp = 10.0
	u.injured_days = 3.0
	var price := w.town.inn_price(sid, u)
	assert_true(price > 0, "healing costs gold")
	w.res["gold"] = price
	assert_eq(w.town.heal(sid, u.id), "", "healed")
	assert_eq(u.hp, float(u.stats.get("max_hp", u.hp)), "full health")
	assert_true(u.injured_days < 3.0, "injuries shortened")
	assert_eq(int(w.res["gold"]), 0, "paid")
	u.pos = Vector2(st["center"]) + Vector2(60, 60)
	u.hp = 10.0
	w.res["gold"] = 999
	assert_ne(w.town.heal(sid, u.id), "", "only units in town")


func test_hired_mercenary_joins_the_colony() -> void:
	var pair := _town_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	var sid := int(st["id"])
	var candidates := w.town.mercenary_candidates(sid)
	var merc: Unit = candidates[0]
	var cost := w.town.mercenary_price(sid, merc)
	w.res["gold"] = cost - 1
	assert_eq(w.town.hire_mercenary(sid, merc.id), "town.error.no_gold", "too poor")
	w.res["gold"] = cost
	var people := w.player_people().size()
	if w.housing() <= people:
		assert_eq(w.town.hire_mercenary(sid, merc.id), "town.error.no_room", "needs a bed")
		return
	assert_eq(w.town.hire_mercenary(sid, merc.id), "", "hired")
	assert_true(merc.is_player(), "now a colonist")
	assert_eq(merc.home_site, -1, "left the town")
	assert_eq(w.player_people().size(), people + 1, "colony grew")
	assert_false(w.town.mercenary_candidates(sid).has(merc), "no longer on offer")
	assert_eq(w.town.hire_mercenary(sid, merc.id), "town.error.candidate", "cannot hire twice")


func test_rumour_reveals_an_unknown_site() -> void:
	var pair := _town_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	var sid := int(st["id"])
	assert_true(w.town.has_rumour(sid), "something to hear about")
	var target := w.town._rumour_target(sid)
	w.res["gold"] = w.town.rumour_price(sid)
	assert_eq(w.town.buy_rumour(sid), "", "rumour bought")
	assert_true(bool((w.sites.get(target, {}) as Dictionary).get("discovered", false)), "site discovered")
	assert_eq(int(w.res["gold"]), 0, "paid")


func test_guild_board_offers_quests() -> void:
	var pair := _town_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	assert_true(w.quests.board(int(st["id"])).size() >= 2, "guild quests on the board")


func test_town_survives_a_save_and_load() -> void:
	var pair := _town_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	var sid := int(st["id"])
	st["relation"] = 35
	var stock_names: Array = []
	for row: Dictionary in w.town.smithy_stock(sid):
		stock_names.append(str((row["item"] as Dictionary).get("name", "")))
	var merc_ids: Array = st["town_mercenary_ids"].duplicate()
	var loaded_result := SaveGame.parse(JSON.stringify(SaveGame.to_dict(w)))
	assert_true(loaded_result.has("world"), "save parsed: %s" % str(loaded_result.get("error", "")))
	if not loaded_result.has("world"):
		return
	var loaded: World = loaded_result["world"]
	_worlds.append(loaded)
	var back: Dictionary = loaded.sites.get(sid, {})
	assert_eq(str(back.get("kind", "")), "town", "town restored")
	assert_eq(int(back["relation"]), 35, "reputation restored")
	var back_names: Array = []
	for row: Dictionary in loaded.town.smithy_stock(sid):
		back_names.append(str((row["item"] as Dictionary).get("name", "")))
	assert_eq(back_names, stock_names, "smithy stock restored")
	assert_eq(loaded.town.mercenary_candidates(sid).size(), merc_ids.size(), "mercenaries restored")
	assert_eq(loaded.town.service_blocker(sid), "", "services open after loading")
