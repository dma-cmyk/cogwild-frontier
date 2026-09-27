extends TestCase
## Race villages: deterministic placement in the terrain each race prefers, relation tiers,
## trading, gifts, requests, plunder and recovery, and the save/load round trip.

const SEED := 4242

var _worlds: Array = []


func after_all() -> void:
	for w: World in _worlds:
		w.dispose()
	_worlds.clear()


func _new(seed: int) -> World:
	var w := NewGame.create(seed)
	_worlds.append(w)
	return w


## Guaranteed villages of a generator, in id order.
func _guaranteed_villages(gen: WorldGen) -> Array:
	var out: Array = []
	for sid: Variant in gen.sites:
		var st: Dictionary = gen.sites[sid]
		if str(st["kind"]) == "village":
			out.append(st)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	return out


## The first village instantiated in a world, with the player standing in it.
func _village_world(seed: int = SEED) -> Array:
	var w := _new(seed)
	var villages := _guaranteed_villages(w.gen)
	if villages.is_empty():
		fail("seed %d generated no village" % seed)
		return [w, {}]
	var sid := int(villages[0]["id"])
	w.factions.instantiate_site(sid)
	var st: Dictionary = w.sites[sid]
	st["discovered"] = true
	var visitor := w.get_unit(w.player_unit_id)
	visitor.pos = Vector2(st["center"]) + Vector2(0.5, 0.5)
	return [w, st]


# --- world generation ------------------------------------------------------------------------

func test_placement_is_deterministic_and_reaches_three_races() -> void:
	for seed: int in [11, 4242, 90210, 777]:
		var a := WorldGen.new(seed)
		var b := WorldGen.new(seed)
		var va := _guaranteed_villages(a)
		var vb := _guaranteed_villages(b)
		assert_eq(va.size(), 3, "seed %d guaranteed villages" % seed)
		var races := {}
		for i in va.size():
			assert_eq(Vector2i(vb[i]["center"]), Vector2i(va[i]["center"]), "seed %d village %d position" % [seed, i])
			assert_eq(str(vb[i]["race"]), str(va[i]["race"]), "seed %d village %d race" % [seed, i])
			assert_eq(str(va[i]["faction"]), "folk_" + str(va[i]["race"]), "faction id")
			var d := Vector2(va[i]["center"]).distance_to(Vector2(a.start_tile))
			assert_true(d <= 160.0, "seed %d village %d is %.0f tiles away" % [seed, i, d])
			races[str(va[i]["race"])] = true
		assert_true(races.size() >= 3, "seed %d reaches %d races" % [seed, races.size()])


func test_each_race_sits_in_the_terrain_it_prefers() -> void:
	# A village must score at least as well as the average random spot in its band for its race.
	for seed: int in [11, 4242, 90210]:
		var gen := WorldGen.new(seed)
		for st: Dictionary in _guaranteed_villages(gen):
			var race := str(st["race"])
			var centre := Vector2(st["center"])
			var score := gen.village_preference_score(race, centre)
			var rng := RngUtil.make([seed, "prefs", st["id"]])
			var total := 0.0
			var d := centre.distance_to(Vector2(gen.start_tile))
			for i in 24:
				var a := rng.randf() * TAU
				total += gen.village_preference_score(race, Vector2(gen.start_tile) + Vector2(cos(a), sin(a)) * d)
			assert_true(score >= total / 24.0, "seed %d %s scored %.2f vs average %.2f"
				% [seed, race, score, total / 24.0])


func test_village_layout_has_a_hall_homes_and_fields() -> void:
	var gen := WorldGen.new(SEED)
	for st: Dictionary in _guaranteed_villages(gen):
		var race := str(st["race"])
		var halls := 0
		var homes := 0
		for s: Dictionary in st["structures"]:
			if str(s["type"]) == "v_%s_hall" % race:
				halls += 1
				assert_eq(Vector2i(s["size"]), Vector2i(5, 5), "hall footprint")
			elif str(s["type"]) == "v_%s_home" % race:
				homes += 1
		assert_eq(halls, 1, "%s hall count" % race)
		assert_between(float(homes), 3.0, 6.0, "%s homes" % race)
		assert_true((st["decor"] as Array).size() >= 8, "%s decor" % race)


func test_village_is_populated_with_guards_and_an_elder() -> void:
	var pair := _village_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	var units: Array = w.factions.site_units(int(st["id"]))
	assert_between(float(units.size()), 5.0, 10.0, "villagers")
	var armed := 0
	var elders := 0
	for u: Unit in units:
		assert_eq(str(u.character.get("race", "")), str(st["race"]), "villager race")
		if u.is_armed():
			armed += 1
		if not u.named.is_empty():
			elders += 1
	assert_true(armed >= 1, "armed guards %d" % armed)
	assert_eq(elders, 1, "named elder")


# --- relations --------------------------------------------------------------------------------

func test_tier_thresholds() -> void:
	assert_eq(Diplomacy.tier_for(-100), "Hostile", "hostile floor")
	assert_eq(Diplomacy.tier_for(-50), "Hostile", "hostile edge")
	assert_eq(Diplomacy.tier_for(-49), "Wary", "wary")
	assert_eq(Diplomacy.tier_for(0), "Neutral", "neutral")
	assert_eq(Diplomacy.tier_for(29), "Neutral", "below friendly")
	assert_eq(Diplomacy.tier_for(30), "Friendly", "friendly edge")
	assert_eq(Diplomacy.tier_for(70), "Allied", "allied edge")


func test_relation_changes_move_between_tiers_and_share_with_kin() -> void:
	var pair := _village_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	var sid := int(st["id"])
	st["relation"] = 0
	st["hostile"] = false
	w.diplomacy.rebuild_hostile_cache()
	# a same-race neighbour to check the shared reaction
	var kin: Dictionary = {"id": 9001, "kind": "village", "race": str(st["race"]), "name": "Kin",
		"faction": str(st["faction"]), "center": Vector2i(st["center"]) + Vector2i(40, 0),
		"relation": 0, "baseline_relation": 0, "level": 1, "discovered": true, "units": []}
	w.sites[9001] = kin
	w.diplomacy.change_relation(sid, 36, "gift")
	assert_eq(w.diplomacy.tier(sid), "Friendly", "friendly after a big gift")
	assert_true(int(kin["relation"]) > 0, "kin heard about it: %d" % int(kin["relation"]))
	w.diplomacy.change_relation(sid, -100, "attack")
	assert_eq(w.diplomacy.tier(sid), "Hostile", "hostile after an attack")
	assert_true(w.hostile("player", str(st["faction"])), "the race fights the player")
	w.res["gold"] = 9999
	assert_eq(w.diplomacy.make_peace(sid), "", "peace accepted")
	assert_false(w.hostile("player", str(st["faction"])), "peace ends the war")
	assert_eq(w.diplomacy.tier(sid), "Neutral", "peace resets to neutral")


func test_hostile_village_raids_and_tribute_buys_peace() -> void:
	var pair := _village_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	var sid := int(st["id"])
	w.diplomacy.declare_attack(sid)
	assert_true(bool(st["hostile"]), "declared war")
	assert_true(int(st["relation"]) <= Diplomacy.HOSTILE_AT, "relation %d" % int(st["relation"]))
	var cost := w.diplomacy.tribute_cost(sid)
	w.res["gold"] = cost - 1
	assert_ne(w.diplomacy.make_peace(sid), "", "cannot pay the tribute")
	w.res["gold"] = cost
	assert_eq(w.diplomacy.make_peace(sid), "", "tribute accepted")
	assert_eq(int(w.res["gold"]), 0, "tribute paid")


# --- trade --------------------------------------------------------------------------------

func test_trade_moves_resources_and_gold_both_ways() -> void:
	var pair := _village_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	var sid := int(st["id"])
	st["relation"] = 10
	var stock: Dictionary = w.diplomacy.stock_of(sid)
	assert_true(int(stock.get("wood", 0)) > 0, "daily stock")
	w.res["gold"] = 500
	w.res["wood"] = 0
	var price := w.diplomacy.buy_price(sid, "wood", 10)
	var their_wood := int(stock["wood"])
	assert_eq(w.diplomacy.resource_trade(sid, "wood", 10, true), "", "buy wood")
	assert_eq(int(w.res["wood"]), 10, "wood received")
	assert_eq(int(w.res["gold"]), 500 - price, "gold paid")
	assert_eq(int((st["stock"] as Dictionary)["wood"]), their_wood - 10, "their stock fell")
	var payout := w.diplomacy.sell_price(sid, "wood", 10)
	var gold_before := int(w.res["gold"])
	assert_eq(w.diplomacy.resource_trade(sid, "wood", 10, false), "", "sell wood back")
	assert_eq(int(w.res["wood"]), 0, "wood handed over")
	assert_eq(int(w.res["gold"]), gold_before + payout, "gold received")
	assert_true(payout < price, "they buy lower than they sell")


func test_prices_follow_the_relation_tier() -> void:
	var pair := _village_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	var sid := int(st["id"])
	st["relation"] = 0
	var neutral := w.diplomacy.buy_price(sid, "metal", 10)
	st["relation"] = 80
	var allied := w.diplomacy.buy_price(sid, "metal", 10)
	st["relation"] = -20
	var wary := w.diplomacy.buy_price(sid, "metal", 10)
	assert_true(allied < neutral, "allied %d < neutral %d" % [allied, neutral])
	assert_true(wary > neutral, "wary %d > neutral %d" % [wary, neutral])


func test_trade_needs_presence_and_a_willing_village() -> void:
	var pair := _village_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	var sid := int(st["id"])
	st["relation"] = 10
	w.res["gold"] = 500
	assert_eq(w.diplomacy.trade_blocker(sid), "", "trading with someone in the village")
	var visitor := w.get_unit(w.player_unit_id)
	visitor.pos = Vector2(st["center"]) + Vector2(400, 400)
	assert_ne(w.diplomacy.trade_blocker(sid), "", "nobody there")
	assert_ne(w.diplomacy.resource_trade(sid, "wood", 10, true), "", "trade refused")
	visitor.pos = Vector2(st["center"]) + Vector2(0.5, 0.5)
	st["relation"] = -30
	assert_ne(w.diplomacy.trade_blocker(sid), "", "wary villages do not trade")


func test_specialty_goods_are_bought_into_the_armory() -> void:
	var pair := _village_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	var sid := int(st["id"])
	st["relation"] = 10
	var goods: Array = w.diplomacy.goods_of(sid)
	assert_true(goods.size() >= 2, "specialties on offer: %d" % goods.size())
	var row: Dictionary = goods[0]
	var price := w.diplomacy.specialty_price(sid, row["item"])
	w.res["gold"] = price
	var armory_before := w.armory.size()
	assert_eq(w.diplomacy.buy_specialty(sid, str(row["base"])), "", "bought the specialty")
	assert_eq(w.armory.size(), armory_before + 1, "item in the armory")
	assert_eq(int(w.res["gold"]), 0, "paid for it")


# --- gifts and requests -------------------------------------------------------------------------

func test_gifts_give_less_each_time() -> void:
	var pair := _village_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	var sid := int(st["id"])
	st["relation"] = 0
	st["gift_count"] = 0
	w.res["food"] = 200
	var first := w.diplomacy.gift_goodwill(sid, "food", 20)
	assert_eq(w.diplomacy.gift(sid, "food", 20), "", "first gift")
	assert_eq(int(st["relation"]), first, "relation rose by the promised amount")
	var second := w.diplomacy.gift_goodwill(sid, "food", 20)
	assert_true(second < first, "second gift %d < first %d" % [second, first])
	assert_eq(w.diplomacy.gift(sid, "food", 20), "", "second gift")
	var third := w.diplomacy.gift_goodwill(sid, "food", 20)
	assert_true(third <= second, "third gift %d <= second %d" % [third, second])
	assert_eq(int(w.res["food"]), 160, "food handed over")


func test_request_is_fulfilled_for_gold_and_goodwill() -> void:
	var pair := _village_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	var sid := int(st["id"])
	var request: Dictionary = st["request"]
	assert_false(request.is_empty(), "a village asks for something")
	var resource := str(request["resource"])
	var amount := int(request["amount"])
	var reward := int(request["reward_gold"])
	w.res[resource] = amount - 1
	w.res["gold"] = 0
	assert_ne(w.diplomacy.fulfil_request(sid), "", "not enough to deliver")
	w.res[resource] = amount
	var relation_before := int(st["relation"])
	assert_eq(w.diplomacy.fulfil_request(sid), "", "delivered")
	assert_eq(int(w.res[resource]), 0, "goods handed over")
	assert_eq(int(w.res["gold"]), reward, "reward paid")
	assert_true(int(st["relation"]) > relation_before, "relation rose")
	assert_true((st["request"] as Dictionary).is_empty(), "request cleared")


func test_ignored_request_costs_goodwill() -> void:
	var pair := _village_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	var request: Dictionary = st["request"]
	assert_false(request.is_empty(), "a village asks for something")
	var relation_before := int(st["relation"])
	w.day = int(request["due_day"]) + 1
	w.diplomacy.on_new_day()
	assert_true((st["request"] as Dictionary).is_empty() or int((st["request"] as Dictionary)["serial"]) != int(request["serial"]),
		"the old request is gone")
	assert_true(int(st["relation"]) < relation_before, "relation fell")


# --- plunder and recovery --------------------------------------------------------------------

func test_attack_subdues_the_village_and_drops_its_stores() -> void:
	var pair := _village_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	var sid := int(st["id"])
	st["relation"] = 20
	w.diplomacy._refresh_stock(st, true)
	assert_true(int((st["stock"] as Dictionary).get("food", 0)) > 0, "they have stores")
	w.diplomacy.declare_attack(sid)
	assert_true(w.hostile("player", str(st["faction"])), "war declared")
	var attacker := w.get_unit(w.player_unit_id)
	var bags_before := w.loot_bags.size()
	for u: Unit in w.factions.site_units(sid):
		u.hp = 0.0
		u.alive = false
		u.state = Unit.State.DEAD
		w.factions.on_unit_killed(u, attacker)
	assert_true(bool(st["subdued"]), "subdued")
	assert_true(bool(st["ruined"]), "ruined")
	assert_true(bool(st["cleared"]), "squads stop attacking it")
	assert_eq(w.factions.site_units(sid).size(), 0, "nobody left")
	assert_true(w.loot_bags.size() > bags_before or w.armory.size() > 0, "plunder dropped or picked up")
	var plunder: Dictionary = {}
	for bag: Dictionary in w.loot_bags.values():
		if Vector2(bag["pos"]).distance_to(Vector2(st["center"])) < 6.0:
			plunder = bag
	if not plunder.is_empty():
		var resources: Dictionary = plunder.get("resources", {})
		var total := 0
		for amount: Variant in resources.values():
			total += int(amount)
		assert_true(total > 0, "resources in the plunder")
		var gold_before := int(w.res.get("gold", 0))
		w.pickup_loot(int(plunder["id"]), attacker)
		assert_true(int(w.res.get("gold", 0)) >= gold_before, "gold collected")
	assert_true(w.diplomacy.can_trade(sid, false) == false, "a ruin does not trade")
	# recovery brings a smaller village back
	w.day = int(st["ruined_until"])
	w.diplomacy.on_new_day()
	assert_false(bool(st["ruined"]), "rebuilt")
	assert_true(w.factions.site_units(sid).size() >= 3, "people came back")
	assert_true(int(st["relation"]) <= Diplomacy.HOSTILE_AT, "still at war until a tribute")


func test_killing_a_villager_of_a_peaceful_village_costs_goodwill() -> void:
	var pair := _village_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	st["relation"] = 20
	st["hostile"] = false
	w.diplomacy.rebuild_hostile_cache()
	var victim: Unit = w.factions.site_units(int(st["id"]))[0]
	var attacker := w.get_unit(w.player_unit_id)
	var population_before := int(st["population"])
	victim.alive = false
	victim.state = Unit.State.DEAD
	w.factions.on_unit_killed(victim, attacker)
	assert_true(int(st["relation"]) < 20, "relation fell to %d" % int(st["relation"]))
	assert_eq(int(st["population"]), population_before - 1, "population fell")
	assert_false(bool(st.get("subdued", false)), "a peaceful village is not subdued by one death")


# --- persistence ---------------------------------------------------------------------------

func test_village_state_survives_a_save_and_load() -> void:
	var pair := _village_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	var sid := int(st["id"])
	st["relation"] = 44
	st["gift_count"] = 2
	w.diplomacy._refresh_stock(st, true)
	w.diplomacy.rebuild_hostile_cache()
	var stock_food := int((st["stock"] as Dictionary)["food"])
	var request: Dictionary = st["request"]
	var loaded_result := SaveGame.parse(JSON.stringify(SaveGame.to_dict(w)))
	assert_true(loaded_result.has("world"), "save parsed: %s" % str(loaded_result.get("error", "")))
	if not loaded_result.has("world"):
		return
	var loaded: World = loaded_result["world"]
	_worlds.append(loaded)
	var back: Dictionary = loaded.sites.get(sid, {})
	assert_false(back.is_empty(), "village restored")
	assert_eq(int(back["relation"]), 44, "relation restored")
	assert_eq(int(back["gift_count"]), 2, "gift count restored")
	assert_eq(str(back["race"]), str(st["race"]), "race restored")
	assert_eq(int((back["stock"] as Dictionary)["food"]), stock_food, "stock restored")
	assert_eq(int((back["request"] as Dictionary).get("serial", -1)), int(request.get("serial", -2)), "request restored")
	assert_eq(loaded.diplomacy.tier(sid), w.diplomacy.tier(sid), "tier restored")
	# a hostile village must still be hostile after loading
	back["relation"] = -80
	loaded.diplomacy.rebuild_hostile_cache()
	assert_true(loaded.hostile("player", str(back["faction"])), "hostile cache rebuilt")
