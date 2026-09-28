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

func test_placement_is_deterministic_and_reaches_four_races() -> void:
	for seed: int in [11, 4242, 90210, 777]:
		var a := WorldGen.new(seed)
		var b := WorldGen.new(seed)
		var va := _guaranteed_villages(a)
		var vb := _guaranteed_villages(b)
		assert_eq(va.size(), 4, "seed %d guaranteed villages" % seed)
		var races := {}
		for i in va.size():
			assert_eq(Vector2i(vb[i]["center"]), Vector2i(va[i]["center"]), "seed %d village %d position" % [seed, i])
			assert_eq(str(vb[i]["race"]), str(va[i]["race"]), "seed %d village %d race" % [seed, i])
			assert_eq(str(va[i]["faction"]), "folk_" + str(va[i]["race"]), "faction id")
			var d := Vector2(va[i]["center"]).distance_to(Vector2(a.start_tile))
			assert_true(d <= 160.0, "seed %d village %d is %.0f tiles away" % [seed, i, d])
			races[str(va[i]["race"])] = true
		assert_eq(races.size(), 4, "seed %d reaches %d races" % [seed, races.size()])


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


func test_village_layout_has_a_hall_homes_stalls_and_fields() -> void:
	var gen := WorldGen.new(SEED)
	for st: Dictionary in _guaranteed_villages(gen):
		var race := str(st["race"])
		var halls := 0
		var homes := 0
		var stalls := 0
		for s: Dictionary in st["structures"]:
			if str(s["type"]) == "v_%s_hall" % race:
				halls += 1
				assert_eq(Vector2i(s["size"]), Vector2i(5, 5), "hall footprint")
			elif str(s["type"]) == "v_%s_home" % race:
				homes += 1
			elif str(s["type"]) == "trade_stall":
				stalls += 1
		var fields := 0
		for d: Array in st["decor"]:
			if str(d[0]) == "tilled_soil":
				fields += 1
		assert_eq(halls, 1, "%s hall count" % race)
		assert_between(float(homes), 4.0, 10.0, "%s homes" % race)
		assert_between(float(stalls), 2.0, 3.0, "%s stalls" % race)
		assert_true(fields >= 18, "%s tilled tiles: %d" % [race, fields])
		assert_true((st["decor"] as Array).size() >= 40, "%s decor" % race)


func test_village_is_populated_with_guards_an_elder_and_workers() -> void:
	var pair := _village_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	var units: Array = w.factions.site_units(int(st["id"]))
	var range_: Array = w.diplomacy.population_range(st)
	assert_between(float(units.size()), float(range_[0]), float(range_[1]), "villagers")
	var armed := 0
	var elders := 0
	var jobs := {}
	for u: Unit in units:
		assert_eq(str(u.character.get("race", "")), str(st["race"]), "villager race")
		if u.is_armed():
			armed += 1
		if not u.named.is_empty():
			elders += 1
		jobs[Diplomacy.resident_job(u)] = true
	assert_true(armed >= 1, "armed guards %d" % armed)
	assert_eq(elders, 1, "named elder")
	for job: String in ["farmer", "trader", "crafter", "guard", "elder"]:
		assert_true(jobs.has(job), "somebody works as %s" % job)


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


# --- quests -------------------------------------------------------------------------------

## The offered quest of a kind, or {} when no board of the next two weeks has one. The board is
## re-rolled per day, so this steps the calendar until the kind turns up.
func _offer(w: World, sid: int, kind: String) -> Dictionary:
	for i in 14:
		for q: Dictionary in w.quests.board(sid):
			if str(q["kind"]) == kind:
				return q
		w.day += 1
	return {}


func test_board_offers_jobs_and_scales_with_the_relation_tier() -> void:
	var pair := _village_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	var sid := int(st["id"])
	st["relation"] = 0
	var neutral: Array = w.quests.board(sid)
	assert_true(neutral.size() >= 1, "a neutral village offers %d jobs" % neutral.size())
	for q: Dictionary in neutral:
		assert_true(str(q["kind"]) in Quests.KINDS, "known kind %s" % str(q["kind"]))
		assert_eq(str(q["state"]), "offered", "offered state")
		assert_true(int(q["deadline_day"]) > w.day, "deadline in the future")
	st["relation"] = 80
	w.day += 1
	var allied: Array = w.quests.board(sid)
	assert_true(allied.size() > neutral.size(), "allied %d > neutral %d" % [allied.size(), neutral.size()])
	st["relation"] = -80
	w.day += 1
	assert_eq(w.quests.board(sid).size(), 0, "a village at war offers nothing")


func test_deliver_quest_runs_from_offer_to_turn_in() -> void:
	var pair := _village_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	var sid := int(st["id"])
	var q := _offer(w, sid, "deliver")
	assert_false(q.is_empty(), "a deliver job is on the board")
	var qid := int(q["id"])
	var resource := str(q["resource"])
	var amount := int(q["amount"])
	assert_eq(w.quests.accept(qid), "", "accepted")
	assert_eq(w.quests.active().size(), 1, "one active job")
	w.res[resource] = amount - 1
	w.res["gold"] = 0
	assert_false(bool(w.quests.progress(q)["done"]), "not enough goods yet")
	assert_ne(w.quests.turn_in(qid), "", "cannot hand in an unfinished job")
	w.res[resource] = amount
	w.quests.refresh_states()
	assert_eq(str(q["state"]), "done", "goods gathered")
	var relation_before := int(st["relation"])
	assert_eq(w.quests.turn_in(qid), "", "handed in")
	assert_eq(int(w.res[resource]), 0, "goods handed over")
	assert_eq(int(w.res["gold"]), int(q["reward_gold"]), "reward paid")
	assert_true(int(st["relation"]) > relation_before, "relation rose")
	assert_eq(w.quests.active().size(), 0, "the job is off the list")


func test_bounty_quest_completes_when_the_camp_is_cleared() -> void:
	var pair := _village_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	var sid := int(st["id"])
	st["relation"] = 60
	w.day += 1
	var q := _offer(w, sid, "bounty")
	if q.is_empty():
		fail("no bounty on the board within two weeks")
		return
	var target := int(q["target_sid"])
	assert_eq(w.quests.accept(int(q["id"])), "", "accepted the bounty")
	assert_false(bool(w.quests.progress(q)["done"]), "camp still standing")
	w.factions.instantiate_site(target)
	(w.sites[target] as Dictionary)["cleared"] = true
	assert_true(bool(w.quests.progress(q)["done"]), "camp cleared")
	w.res["gold"] = 0
	assert_eq(w.quests.turn_in(int(q["id"])), "", "reported back")
	assert_eq(int(w.res["gold"]), int(q["reward_gold"]), "bounty paid")


func test_scout_quest_points_a_direction_and_completes_on_discovery() -> void:
	var pair := _village_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	var sid := int(st["id"])
	st["relation"] = 60
	w.day += 2
	var q := _offer(w, sid, "scout")
	if q.is_empty():
		fail("no scouting job on the board within two weeks")
		return
	assert_eq(w.quests.accept(int(q["id"])), "", "accepted the scouting job")
	assert_true(str(q.get("hint", "")) != "", "the giver points a direction")
	assert_false(bool(w.quests.progress(q)["done"]), "target still unknown")
	var target := int(q["target_sid"])
	w.factions.instantiate_site(target)
	(w.sites[target] as Dictionary)["discovered"] = true
	assert_true(bool(w.quests.progress(q)["done"]), "target found")
	assert_eq(w.quests.turn_in(int(q["id"])), "", "reported back")


func test_missed_deadline_fails_the_quest_and_costs_goodwill() -> void:
	var pair := _village_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	var sid := int(st["id"])
	var q := _offer(w, sid, "deliver")
	assert_false(q.is_empty(), "a deliver job is on the board")
	assert_eq(w.quests.accept(int(q["id"])), "", "accepted")
	var relation_before := int(st["relation"])
	w.day = int(q["deadline_day"]) + 1
	w.quests.on_new_day()
	assert_eq(str(q["state"]), "failed", "the job failed")
	assert_eq(w.quests.active().size(), 0, "dropped from the active list")
	assert_true(int(st["relation"]) < relation_before, "relation fell")


func test_accepting_needs_presence_and_abandoning_costs_goodwill() -> void:
	var pair := _village_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	var sid := int(st["id"])
	var q := _offer(w, sid, "deliver")
	assert_false(q.is_empty(), "a deliver job is on the board")
	var visitor := w.get_unit(w.player_unit_id)
	visitor.pos = Vector2(st["center"]) + Vector2(400, 400)
	assert_eq(w.quests.accept(int(q["id"])), "quest.blocked.presence", "nobody there to take the job")
	visitor.pos = Vector2(st["center"]) + Vector2(0.5, 0.5)
	assert_eq(w.quests.accept(int(q["id"])), "", "accepted in person")
	var relation_before := int(st["relation"])
	w.quests.abandon(int(q["id"]))
	assert_eq(w.quests.active().size(), 0, "dropped")
	assert_true(int(st["relation"]) < relation_before, "relation fell")


func test_old_saves_migrate_their_village_request_into_a_quest() -> void:
	var pair := _village_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	st["request"] = {"serial": 1, "resource": "food", "amount": 9, "due_day": w.day + 3,
		"reward_gold": 28, "relation": 14}
	st["request_day"] = w.day
	st["request_serial"] = 1
	var loaded_result := SaveGame.parse(JSON.stringify(SaveGame.to_dict(w)))
	assert_true(loaded_result.has("world"), "save parsed: %s" % str(loaded_result.get("error", "")))
	if not loaded_result.has("world"):
		return
	var loaded: World = loaded_result["world"]
	_worlds.append(loaded)
	assert_false((loaded.sites[int(st["id"])] as Dictionary).has("request"), "the old field is gone")
	var migrated: Array = loaded.quests.active()
	assert_eq(migrated.size(), 1, "the promise became a quest")
	if migrated.is_empty():
		return
	var q: Dictionary = migrated[0]
	assert_eq(str(q["kind"]), "deliver", "as a delivery")
	assert_eq(str(q["resource"]), "food", "same resource")
	assert_eq(int(q["amount"]), 9, "same amount")
	assert_eq(int(q["reward_gold"]), 28, "same reward")


func test_accepted_quests_survive_a_save_and_load() -> void:
	var pair := _village_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	var sid := int(st["id"])
	var q := _offer(w, sid, "deliver")
	assert_false(q.is_empty(), "a deliver job is on the board")
	assert_eq(w.quests.accept(int(q["id"])), "", "accepted")
	var loaded_result := SaveGame.parse(JSON.stringify(SaveGame.to_dict(w)))
	assert_true(loaded_result.has("world"), "save parsed: %s" % str(loaded_result.get("error", "")))
	if not loaded_result.has("world"):
		return
	var loaded: World = loaded_result["world"]
	_worlds.append(loaded)
	var back: Array = loaded.quests.active()
	assert_eq(back.size(), 1, "the job came back")
	if back.is_empty():
		return
	assert_eq(int((back[0] as Dictionary)["id"]), int(q["id"]), "same id")
	assert_eq(int((back[0] as Dictionary)["amount"]), int(q["amount"]), "amount restored as an int")
	assert_eq(str((back[0] as Dictionary)["kind"]), "deliver", "kind restored")


# --- recruiting and talking -------------------------------------------------------------------

## A resident who is not the elder, plus a colony with a free bed and gold.
func _recruitable(w: World, st: Dictionary) -> Unit:
	for u: Unit in w.diplomacy.residents(int(st["id"])):
		if u.named.is_empty():
			return u
	return null


func test_recruiting_needs_a_friendly_village_a_bed_and_gold() -> void:
	var pair := _village_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	var sid := int(st["id"])
	var recruit := _recruitable(w, st)
	assert_true(recruit != null, "a resident to invite")
	if recruit == null:
		return
	st["relation"] = 10
	w.res["gold"] = 9999
	assert_eq(w.diplomacy.recruit_blocker(sid, recruit.id), "village.recruit.relation", "neutral is not enough")
	st["relation"] = 40
	var elder: Unit = null
	for u: Unit in w.diplomacy.residents(sid):
		if not u.named.is_empty():
			elder = u
	assert_true(elder != null, "the village has an elder")
	if elder:
		assert_eq(w.diplomacy.recruit_blocker(sid, elder.id), "village.recruit.elder", "the elder stays")
	var population := int(st["population"])
	st["population"] = w.diplomacy.min_population(st)
	assert_eq(w.diplomacy.recruit_blocker(sid, recruit.id), "village.recruit.population", "too few people left")
	st["population"] = population
	st["recruit_day"] = w.day
	assert_eq(w.diplomacy.recruit_blocker(sid, recruit.id), "village.recruit.cooldown", "one at a time")
	st["recruit_day"] = w.day - Diplomacy.RECRUIT_COOLDOWN_DAYS
	var colonists := w.population()
	while w.population() < w.housing():
		CharacterFactory.make_colonist(w, {"race": "human", "level": 1}, w.home_pos())
	assert_eq(w.diplomacy.recruit_blocker(sid, recruit.id), "village.recruit.beds", "no free bed at home")
	for u: Unit in w.player_people().slice(colonists):
		w.remove_unit(u)
	assert_eq(w.diplomacy.recruit_blocker(sid, recruit.id), "", "a free bed again")
	w.res["gold"] = 0
	assert_eq(w.diplomacy.recruit_blocker(sid, recruit.id), "village.recruit.gold", "the gift costs gold")


func test_recruiting_moves_the_resident_into_the_colony() -> void:
	var pair := _village_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	var sid := int(st["id"])
	var recruit := _recruitable(w, st)
	if recruit == null:
		fail("no resident to invite")
		return
	st["relation"] = 40
	st["recruit_day"] = w.day - Diplomacy.RECRUIT_COOLDOWN_DAYS
	var cost := w.diplomacy.recruit_cost(sid, recruit.id)
	w.res["gold"] = cost
	var population_before := int(st["population"])
	var colony_before := w.population()
	assert_eq(w.diplomacy.recruit_blocker(sid, recruit.id), "", "everything is in order")
	assert_eq(w.diplomacy.recruit(sid, recruit.id), "", "invited")
	assert_eq(recruit.faction, "player", "joined the colony")
	assert_eq(recruit.home_site, -1, "no longer a villager")
	assert_eq(w.population(), colony_before + 1, "colony grew")
	assert_eq(int(st["population"]), population_before - 1, "village shrank")
	assert_eq(int(w.res["gold"]), 0, "paid for the parting gift")
	assert_false((st["units"] as Array).has(recruit.id), "off the village roster")
	assert_true(recruit.dna.has("art_variant"), "given a colony art variant")
	# the cooldown blocks the next invite
	var second := _recruitable(w, st)
	if second:
		w.res["gold"] = 9999
		assert_eq(w.diplomacy.recruit_blocker(sid, second.id), "village.recruit.cooldown", "one per cooldown")


func test_talking_returns_a_line_and_can_reveal_a_site() -> void:
	var pair := _village_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	var sid := int(st["id"])
	st["relation"] = 80
	var speaker := _recruitable(w, st)
	if speaker == null:
		fail("no resident to talk to")
		return
	var revealed := -1
	for i in 40:
		var line := w.diplomacy.talk(sid, speaker.id)
		var key := str(line["text_key"])
		assert_true(key.begins_with("village.talk."), "dialogue key %s" % key)
		assert_ne(Loc.t(key, line["params"]), key, "the line is localized")
		if int(line["rumor_sid"]) >= 0:
			revealed = int(line["rumor_sid"])
			assert_true(bool((w.sites[revealed] as Dictionary)["discovered"]), "the rumour put it on the map")
			break
		w.day += 1
	assert_true(revealed >= 0, "a rumour turned up within 40 chats")


func test_talking_is_worth_a_little_goodwill_but_is_capped() -> void:
	var pair := _village_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	var sid := int(st["id"])
	st["relation"] = 10
	st["baseline_relation"] = 10
	var speaker := _recruitable(w, st)
	if speaker == null:
		fail("no resident to talk to")
		return
	for i in 8:
		w.diplomacy.talk(sid, speaker.id)
	assert_eq(int(st["relation"]), 10 + Diplomacy.TALK_GAIN_CAP, "capped per day")


func test_a_peaceful_village_regrows_towards_its_range() -> void:
	var pair := _village_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	var top := int(w.diplomacy.population_range(st)[1])
	st["population"] = 4
	st["grow_day"] = w.day - 3
	var units_before := w.factions.site_units(int(st["id"])).size()
	w.diplomacy.on_new_day()
	assert_eq(int(st["population"]), 5, "one newcomer")
	assert_eq(w.factions.site_units(int(st["id"])).size(), units_before + 1, "and they are really there")
	st["population"] = top
	st["grow_day"] = w.day - 3
	w.diplomacy.on_new_day()
	assert_eq(int(st["population"]), top, "a full village does not grow")


# --- the town as a community ------------------------------------------------------------------

## A bare `kind == "town"` site next to the start with the founder standing in it. The Town slice
## lays the real one out; diplomacy and quests only need the site dictionary.
func _town_world() -> Array:
	var w := _new(SEED)
	var sid := 900001
	var home := w.home_pos()
	var centre := Vector2i(int(home.x) + 24, int(home.y))
	var st := {"id": sid, "kind": "town", "center": centre, "name": "Testburg", "faction": "",
		"level": 2, "hostile": false, "discovered": true, "cleared": false, "looted": false,
		"units": [], "cache": [], "cache_gold": 0, "extra": [], "next_raid_day": 99, "cleared_day": 0}
	w.sites[sid] = st
	w.diplomacy.initialize(st, RngUtil.make([SEED, "test_town"]))
	w.get_unit(w.player_unit_id).pos = Vector2(centre) + Vector2(0.5, 0.5)
	return [w, st]


func test_the_town_trades_befriends_fights_and_recovers_like_a_village() -> void:
	var pair := _town_world()
	var w: World = pair[0]
	var st: Dictionary = pair[1]
	var sid := int(st["id"])
	assert_true(w.diplomacy.is_community(st), "the town is a community")
	assert_false(w.diplomacy.is_village(st), "but not a race village")
	assert_eq(str(st["faction"]), "townsfolk", "its own faction")
	st["relation"] = 10
	w.res["gold"] = 500
	assert_eq(w.diplomacy.resource_trade(sid, "wood", 5, true), "", "the town trades")
	var villages := _guaranteed_villages(w.gen)
	var kin_sid := int(villages[0]["id"])
	w.factions.instantiate_site(kin_sid)
	var village_relation := int((w.sites[kin_sid] as Dictionary)["relation"])
	w.res["food"] = 50
	var before := int(st["relation"])
	assert_eq(w.diplomacy.gift(sid, "food", 20), "", "the town takes gifts")
	assert_true(int(st["relation"]) > before, "and likes them")
	assert_eq(int((w.sites[kin_sid] as Dictionary)["relation"]), village_relation, "no kin shares the town's mood")
	assert_false(w.quests.board(sid).is_empty(), "the town has a quest board")
	w.diplomacy.declare_attack(sid)
	assert_true(w.hostile("player", "townsfolk"), "attacking turns the townsfolk hostile")
	assert_eq(w.quests.board(sid).size(), 0, "no jobs while at war")
	w.diplomacy.subdue(sid, w.get_unit(w.player_unit_id))
	assert_true(bool(st["ruined"]), "subdued and plundered")
	w.day = int(st["ruined_until"])
	w.diplomacy.on_new_day()
	assert_false(bool(st["ruined"]), "the town recovers")
	w.res["gold"] = 1000
	assert_eq(w.diplomacy.make_peace(sid), "", "tribute buys peace")
	assert_false(w.hostile("player", "townsfolk"), "at peace again")



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
	st["recruit_day"] = 7
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
	assert_eq(int(back["recruit_day"]), 7, "recruit cooldown restored as an int")
	assert_eq(loaded.diplomacy.tier(sid), w.diplomacy.tier(sid), "tier restored")
	# a hostile village must still be hostile after loading
	back["relation"] = -80
	loaded.diplomacy.rebuild_hostile_cache()
	assert_true(loaded.hostile("player", str(back["faction"])), "hostile cache rebuilt")
