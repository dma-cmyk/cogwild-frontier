class_name Diplomacy
extends RefCounted
## Race villages: relations, requests, local trade, plunder and recovery.
##
## Every mutable value lives in the village's site Dictionary, so the existing site save/load path
## persists all of it without a second schema. Relations are deterministic: the initial value comes
## from the race temperament plus the founder's race, and every later change is caused by a player
## action or the daily drift toward the village's baseline.
##
## One faction id is shared by all villages of a race (`folk_<race>`, see docs/contracts.md), so a
## race turns hostile as a whole; attacking one village also drags its kin down through
## `_share_with_kin`.

const HOSTILE_AT := -50
const FRIENDLY_AT := 30
const ALLIED_AT := 70
const TRADE_RANGE := 9.0            ## a colony unit must stand this close to trade / deliver
const RESOURCE_PRICES := {"wood": 2, "stone": 2, "ore": 4, "metal": 8, "food": 2}
const TRADE_RESOURCES := ["wood", "stone", "ore", "metal", "food"]
const TEMPERAMENT_BASE := {"welcoming": 18, "trading": 8, "reserved": -8, "proud": -2, "wary": -18}
const STOCK_LIMIT := 220
const DAILY_GOODWILL_CAP := 6       ## relation a village can gain from trading in one day
const TIERS := ["Hostile", "Wary", "Neutral", "Friendly", "Allied"]

var w: World
## faction id -> true for every `folk_<race>` that currently fights the player. `World.hostile()`
## runs per attack check, so the answer is cached instead of scanning the sites every time.
var hostile_folk: Dictionary = {}


func _init(world: World) -> void:
	w = world


# --- tiers ---------------------------------------------------------------------------------

static func tier_for(relation: int) -> String:
	if relation <= HOSTILE_AT:
		return "Hostile"
	if relation >= ALLIED_AT:
		return "Allied"
	if relation >= FRIENDLY_AT:
		return "Friendly"
	if relation < 0:
		return "Wary"
	return "Neutral"


static func can_trade_tier(relation: int) -> bool:
	return relation >= 0


func race_config(race: String) -> Dictionary:
	return DB.get_def("villages", race)


func is_village(st: Dictionary) -> bool:
	return str(st.get("kind", "")) == "village" and str(st.get("race", "")) != ""


func relation(sid: int) -> int:
	return int(w.sites.get(sid, {}).get("relation", 0))


func tier(sid: int) -> String:
	return tier_for(relation(sid))


func known_villages() -> Array:
	var result: Array = []
	for sid: Variant in w.sites:
		var st: Dictionary = w.sites[sid]
		if is_village(st) and bool(st.get("discovered", false)):
			result.append(st)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	return result


func faction_hostile_to_player(faction: String) -> bool:
	return hostile_folk.has(faction)


## Rebuilt after loading a save and whenever a village's relation crosses the hostile line.
func rebuild_hostile_cache() -> void:
	hostile_folk.clear()
	for st: Dictionary in w.sites.values():
		if is_village(st) and int(st.get("relation", 0)) <= HOSTILE_AT:
			hostile_folk[str(st.get("faction", "folk_" + str(st["race"])))] = true


# --- founding ------------------------------------------------------------------------------

func initialize(st: Dictionary, rng: RandomNumberGenerator) -> void:
	if not is_village(st):
		return
	var race := str(st["race"])
	var cfg := race_config(race)
	var temperament := str(cfg.get("temperament", "reserved"))
	var base := int(cfg.get("starting_relation", TEMPERAMENT_BASE.get(temperament, 0)))
	var founder := w.get_unit(w.player_unit_id)
	if founder and str(founder.character.get("race", "")) == race:
		base += 20
	var value := clampi(base + rng.randi_range(-4, 4), -100, 100)
	st["faction"] = "folk_" + race
	st["relation"] = value
	st["baseline_relation"] = value
	st["hostile"] = value <= HOSTILE_AT
	st["temperament"] = temperament
	st["population"] = rng.randi_range(5, 10)
	st["ruined"] = false
	st["ruined_until"] = 0
	st["subdued"] = false
	st["gift_count"] = 0
	st["gift_decay_day"] = w.day
	st["trade_day"] = w.day
	st["trade_gain_today"] = 0
	st["stock_day"] = w.day - 1
	st["stock"] = {}
	st["purse"] = 40 + int(st.get("level", 1)) * 20
	st["goods"] = []
	st["request_serial"] = 0
	st["request"] = {}
	st["request_day"] = w.day
	st["cache"] = ItemGen.loot(rng, int(st.get("level", 1)), 0.12, 1)
	st["cache_gold"] = rng.randi_range(12, 34)
	_refresh_stock(st, true)
	_roll_request(st, rng)
	if value <= HOSTILE_AT:
		hostile_folk[str(st["faction"])] = true


func populate(st: Dictionary, rng: RandomNumberGenerator) -> void:
	var population := int(st.get("population", 6))
	var centre := Vector2(st["center"]) + Vector2(0.5, 0.5)
	var cfg := race_config(str(st.get("race", "")))
	var guards := clampi(int(cfg.get("guards", 2)), 1, maxi(1, population - 2))
	for i in population:
		var role := "farmer"
		if i < guards:
			role = "archer" if i == guards - 1 and guards >= 2 else "guard"
		elif i == population - 1:
			role = "elder"
		var u := _spawn_villager(st, centre, role, rng)
		(st["units"] as Array).append(u.id)
	st["population"] = population


func _spawn_villager(st: Dictionary, centre: Vector2, role: String, rng: RandomNumberGenerator) -> Unit:
	var race := str(st["race"])
	var level := maxi(1, int(st.get("level", 1)))
	var candidate := centre + Vector2(rng.randf_range(-4.5, 4.5), rng.randf_range(-4.5, 4.5))
	var walkable := w.nearest_walkable(Vector2i(int(floor(candidate.x)), int(floor(candidate.y))), 6)
	var pos := Vector2(walkable) + Vector2(0.5, 0.5) if walkable.x != -99999 else centre
	var armed := role in ["guard", "archer"]
	var npc_role := "scholar" if role == "elder" else role
	var u := CharacterFactory.make_person(w, {"race": race, "role": npc_role, "level": level},
		pos, str(st["faction"]), "colonist")
	u.home_site = int(st["id"])
	u.guard_pos = pos
	u.labor = "soldier" if armed else "worker"
	if role == "elder":
		u.named = {"epithet": "Village Elder"}
		u.name += ", Elder of " + str(st["name"])
	if armed and not (u.equipment().get("weapon") is Dictionary):
		var weapon := ItemGen.generate(rng, {"base": "bow" if role == "archer" else "spear",
			"level": level, "quality": "crude", "source": "start"})
		weapon["uid"] = w.new_id()
		u.equipment()["weapon"] = weapon
		CharacterFactory.sync_dna(u)
		u.recompute_stats()
	return u


# --- relation ------------------------------------------------------------------------------

func change_relation(sid: int, delta: int, reason: String = "") -> void:
	var st: Dictionary = w.sites.get(sid, {})
	if not is_village(st) or delta == 0:
		return
	_change_one(st, delta)
	if reason in ["trade", "gift", "request", "attack", "casualty", "defense"]:
		_share_with_kin(st, delta)


## Kin of the same race hear about it: a third of the change, capped so a single brawl does not
## flip every village of that race at once.
func _share_with_kin(st: Dictionary, delta: int) -> void:
	var shared := clampi(int(delta / 3.0), -12, 12)
	if shared == 0:
		shared = 1 if delta > 0 else -1
	var race := str(st["race"])
	var sid := int(st["id"])
	for other: Dictionary in w.sites.values():
		if int(other.get("id", -1)) != sid and is_village(other) and str(other.get("race", "")) == race:
			_change_one(other, shared)


func _change_one(st: Dictionary, delta: int) -> void:
	var before := int(st.get("relation", 0))
	var after := clampi(before + delta, -100, 100)
	if after == before:
		return
	st["relation"] = after
	st["hostile"] = after <= HOSTILE_AT
	var faction := str(st.get("faction", ""))
	if after <= HOSTILE_AT:
		hostile_folk[faction] = true
	elif hostile_folk.has(faction):
		rebuild_hostile_cache()
	var old_tier := tier_for(before)
	var new_tier := tier_for(after)
	if old_tier != new_tier and bool(st.get("discovered", false)):
		w.notify_key("sim.village.tier_changed", {"village_name": str(st.get("name", "")),
			"tier": {"list": [new_tier]}}, "good" if after > before else "bad",
			Vector2(st["center"]), {"site": int(st["id"])})
	w.site_changed.emit(int(st["id"]))


func mark_discovered(st: Dictionary, _by_name: String = "") -> void:
	if not is_village(st):
		return
	w.notify_key("sim.village.discovered", {"village_name": str(st.get("name", "")),
		"race": {"table": "races", "id": str(st["race"])},
		"tier": {"list": [tier_for(int(st.get("relation", 0)))]}},
		"discover", Vector2(st["center"]), {"site": int(st["id"])})
	var request: Dictionary = st.get("request", {})
	if not request.is_empty():
		_announce_request(st, request)


# --- presence & trade ------------------------------------------------------------------------

## Trading, gifting and deliveries all need a colony unit standing in the village, the same rule
## the wanderer camps use for recruiting: walk someone (or a squad) over.
func is_near_village(sid: int, radius: float = TRADE_RANGE) -> bool:
	var st: Dictionary = w.sites.get(sid, {})
	if not is_village(st):
		return false
	var centre := Vector2(st["center"]) + Vector2(0.5, 0.5)
	# Do not use World's spatial grid here: callers (and save/load) can move a unit
	# between simulation rebuilds, and diplomacy must observe the authoritative position.
	for u: Unit in w.unit_list:
		if u.is_player() and u.alive and u.state != Unit.State.DOWNED and u.pos.distance_to(centre) <= radius:
			return true
	return false


func can_trade(sid: int, require_presence: bool = true) -> bool:
	var st: Dictionary = w.sites.get(sid, {})
	return is_village(st) and bool(st.get("discovered", false)) \
		and not bool(st.get("ruined", false)) and can_trade_tier(int(st.get("relation", 0))) \
		and (not require_presence or is_near_village(sid))


## Why trading is not possible right now ("" = it is). Localized by the caller.
func trade_blocker(sid: int) -> String:
	var st: Dictionary = w.sites.get(sid, {})
	if not is_village(st) or not bool(st.get("discovered", false)):
		return "This village is not known yet."
	if bool(st.get("ruined", false)):
		return "The village is in ruins and trades nothing."
	if not can_trade_tier(int(st.get("relation", 0))):
		return "They will not trade while they distrust you."
	if not is_near_village(sid):
		return "Send someone to the village to trade."
	return ""


func price_factor(sid: int) -> float:
	match tier(sid):
		"Allied": return 0.65
		"Friendly": return 0.82
		"Wary": return 1.45
		_: return 1.0


func buy_price(sid: int, resource: String, amount: int) -> int:
	return maxi(1, int(ceil(float(int(RESOURCE_PRICES.get(resource, 2)) * amount) * price_factor(sid))))


func sell_price(sid: int, resource: String, amount: int) -> int:
	return maxi(1, int(floor(float(int(RESOURCE_PRICES.get(resource, 2)) * amount) * 0.6 / price_factor(sid))))


func stock_of(sid: int) -> Dictionary:
	var st: Dictionary = w.sites.get(sid, {})
	if not is_village(st):
		return {}
	_refresh_stock(st)
	return st.get("stock", {})


func goods_of(sid: int) -> Array:
	var st: Dictionary = w.sites.get(sid, {})
	if not is_village(st):
		return []
	_refresh_stock(st)
	return st.get("goods", [])


func _refresh_stock(st: Dictionary, force: bool = false) -> void:
	if not force and int(st.get("stock_day", -1)) == w.day:
		return
	st["stock_day"] = w.day
	var ruined := bool(st.get("ruined", false))
	var cfg := race_config(str(st.get("race", "")))
	var configured: Dictionary = cfg.get("stock", {})
	var stock: Dictionary = {}
	for resource: String in TRADE_RESOURCES:
		stock[resource] = 0 if ruined else int(configured.get(resource, 18)) + int(st.get("level", 1)) * 3
	st["stock"] = stock
	if ruined:
		st["goods"] = []
		return
	var rng := RngUtil.make([w.seed, "village_stock", int(st.get("id", -1)), w.day])
	var goods: Array = []
	for base: Variant in cfg.get("specialties", []):
		var item_id := str(base)
		if not DB.has_def("items", item_id):
			continue
		var item := ItemGen.generate(rng, {"base": item_id, "level": maxi(1, int(st.get("level", 1))),
			"luck": 0.08, "source": "shop"})
		if item.is_empty():
			continue
		goods.append({"base": item_id, "item": item, "count": rng.randi_range(1, 2)})
	st["goods"] = goods


## Buy (`buying`) or sell a colony resource. Returns "" or an English reason.
func resource_trade(sid: int, resource: String, amount: int, buying: bool) -> String:
	var blocker := trade_blocker(sid)
	if blocker != "":
		return blocker
	if not RESOURCE_PRICES.has(resource) or amount <= 0:
		return "They do not deal in that."
	var st: Dictionary = w.sites[sid]
	_refresh_stock(st)
	var stock: Dictionary = st["stock"]
	if buying:
		if int(stock.get(resource, 0)) < amount:
			return "The village has no more to sell."
		var cost := buy_price(sid, resource, amount)
		if int(w.res.get("gold", 0)) < cost:
			return "Not enough gold."
		w.res["gold"] = int(w.res.get("gold", 0)) - cost
		w.economy.add(resource, amount)
		stock[resource] = int(stock[resource]) - amount
		st["purse"] = int(st.get("purse", 0)) + cost
		_record_trade(st, cost)
	else:
		if int(w.res.get(resource, 0)) < amount:
			return "You do not have that much to sell."
		if int(stock.get(resource, 0)) + amount > STOCK_LIMIT:
			return "Their storehouse is full."
		var payout := sell_price(sid, resource, amount)
		if int(st.get("purse", 0)) < payout:
			return "The village cannot pay for that much."
		w.res[resource] = int(w.res[resource]) - amount
		w.economy.add("gold", payout)
		st["purse"] = int(st["purse"]) - payout
		stock[resource] = int(stock[resource]) + amount
		_record_trade(st, payout)
	w.site_changed.emit(sid)
	return ""


func specialty_price(sid: int, item: Dictionary) -> int:
	return maxi(1, int(ceil(float(int(item.get("value", 10))) * price_factor(sid))))


func buy_specialty(sid: int, base: String) -> String:
	var blocker := trade_blocker(sid)
	if blocker != "":
		return blocker
	var st: Dictionary = w.sites[sid]
	_refresh_stock(st)
	for row: Dictionary in st.get("goods", []):
		if str(row.get("base", "")) != base or int(row.get("count", 0)) <= 0:
			continue
		var item: Dictionary = row.get("item", {})
		var cost := specialty_price(sid, item)
		if int(w.res.get("gold", 0)) < cost:
			return "Not enough gold."
		w.res["gold"] = int(w.res.get("gold", 0)) - cost
		var owned := item.duplicate(true)
		owned["uid"] = w.new_id()
		w.armory.append(owned)
		row["count"] = int(row["count"]) - 1
		st["purse"] = int(st.get("purse", 0)) + cost
		_record_trade(st, cost)
		w.notify_key("sim.trade.item_bought", {"item": owned}, "loot", Vector2(st["center"]), {"site": sid})
		w.site_changed.emit(sid)
		return ""
	return "The village has sold out."


## Goodwill from trading, capped per village per day.
func _record_trade(st: Dictionary, value: int) -> void:
	if int(st.get("trade_day", -1)) != w.day:
		st["trade_day"] = w.day
		st["trade_gain_today"] = 0
	var gained := int(st.get("trade_gain_today", 0))
	var goodwill := mini(DAILY_GOODWILL_CAP - gained, maxi(1, value / 20))
	if goodwill > 0:
		st["trade_gain_today"] = gained + goodwill
		change_relation(int(st["id"]), goodwill, "trade")


# --- gifts & requests --------------------------------------------------------------------------

## Goodwill a gift of `amount` `resource` would earn right now (shown in the UI before paying).
func gift_goodwill(sid: int, resource: String, amount: int) -> int:
	var st: Dictionary = w.sites.get(sid, {})
	var worth := int(RESOURCE_PRICES.get(resource, 2)) * amount
	var base := clampi(int(worth / 5.0), 1, 14)
	return maxi(1, int(round(float(base) / (1.0 + 0.7 * float(int(st.get("gift_count", 0)))))))


func gift(sid: int, resource: String, amount: int) -> String:
	var st: Dictionary = w.sites.get(sid, {})
	if not is_village(st) or not bool(st.get("discovered", false)):
		return "This village is not known yet."
	if not is_near_village(sid):
		return "Send someone to the village to trade."
	if amount <= 0 or not RESOURCE_PRICES.has(resource):
		return "They do not deal in that."
	if int(w.res.get(resource, 0)) < amount:
		return "You do not have that much to sell."
	var goodwill := gift_goodwill(sid, resource, amount)
	w.res[resource] = int(w.res[resource]) - amount
	st["gift_count"] = int(st.get("gift_count", 0)) + 1
	_refresh_stock(st)
	var stock: Dictionary = st["stock"]
	stock[resource] = mini(STOCK_LIMIT, int(stock.get(resource, 0)) + amount)
	change_relation(sid, goodwill, "gift")
	w.notify_key("sim.village.gift", {"village_name": str(st["name"]),
		"resources": {"resources": {resource: amount}}}, "good", Vector2(st["center"]), {"site": sid})
	return ""


func _roll_request(st: Dictionary, rng: RandomNumberGenerator) -> void:
	if bool(st.get("ruined", false)):
		return
	var cfg := race_config(str(st.get("race", "")))
	var wants: Array = cfg.get("wants", ["food", "wood"])
	if wants.is_empty():
		return
	var resource := str(wants[rng.randi_range(0, wants.size() - 1)])
	var amount := rng.randi_range(6, 10) + int(st.get("level", 1)) * 2
	var serial := int(st.get("request_serial", 0)) + 1
	st["request_serial"] = serial
	var request := {"serial": serial, "resource": resource, "amount": amount, "due_day": w.day + 3,
		"reward_gold": 10 + amount * 2, "relation": 14}
	st["request"] = request
	st["request_day"] = w.day
	if bool(st.get("discovered", false)):
		_announce_request(st, request)


func _announce_request(st: Dictionary, request: Dictionary) -> void:
	w.notify_key("sim.village.request", {"village_name": str(st["name"]),
		"resources": {"resources": {str(request.get("resource", "food")): int(request.get("amount", 0))}},
		"due_day": int(request.get("due_day", w.day))}, "info", Vector2(st["center"]), {"site": int(st["id"])})


func fulfil_request(sid: int) -> String:
	var st: Dictionary = w.sites.get(sid, {})
	if not is_village(st) or not bool(st.get("discovered", false)):
		return "This village is not known yet."
	if not is_near_village(sid):
		return "Send someone to the village to trade."
	var request: Dictionary = st.get("request", {})
	if request.is_empty() or w.day > int(request.get("due_day", 0)):
		return "There is nothing they are asking for."
	var resource := str(request.get("resource", "food"))
	var amount := int(request.get("amount", 0))
	if int(w.res.get(resource, 0)) < amount:
		return "You do not have that much to sell."
	w.res[resource] = int(w.res[resource]) - amount
	var reward := int(request.get("reward_gold", 0))
	w.economy.add("gold", reward)
	st["request"] = {}
	st["request_day"] = w.day
	_refresh_stock(st)
	(st["stock"] as Dictionary)[resource] = mini(STOCK_LIMIT, int((st["stock"] as Dictionary).get(resource, 0)) + amount)
	change_relation(sid, int(request.get("relation", 12)), "request")
	w.notify_key("sim.village.request_fulfilled", {"village_name": str(st["name"]), "reward": reward},
		"good", Vector2(st["center"]), {"site": sid})
	return ""


# --- war & peace ---------------------------------------------------------------------------

func tribute_cost(sid: int) -> int:
	return 35 + int(w.sites.get(sid, {}).get("level", 1)) * 18


func make_peace(sid: int) -> String:
	var st: Dictionary = w.sites.get(sid, {})
	if not is_village(st) or int(st.get("relation", 0)) > HOSTILE_AT:
		return "They are not at war with you."
	var tribute := tribute_cost(sid)
	if int(w.res.get("gold", 0)) < tribute:
		return "Not enough gold."
	w.res["gold"] = int(w.res["gold"]) - tribute
	st["baseline_relation"] = 0
	st["subdued"] = false
	st["cleared"] = false
	_change_one(st, -int(st.get("relation", 0)))
	# kin of the same race accept the peace as well, otherwise the faction stays at war
	for other: Dictionary in w.sites.values():
		if is_village(other) and str(other["race"]) == str(st["race"]) and int(other.get("relation", 0)) <= HOSTILE_AT:
			other["baseline_relation"] = maxi(int(other.get("baseline_relation", 0)), HOSTILE_AT + 12)
			_change_one(other, HOSTILE_AT + 12 - int(other.get("relation", 0)))
	rebuild_hostile_cache()
	w.notify_key("sim.village.peace", {"village_name": str(st["name"]), "gold": tribute},
		"good", Vector2(st["center"]), {"site": sid})
	return ""


## The player confirmed an attack on a village that was not hostile yet.
func declare_attack(sid: int) -> void:
	var st: Dictionary = w.sites.get(sid, {})
	if not is_village(st) or int(st.get("relation", 0)) <= HOSTILE_AT:
		return
	st["baseline_relation"] = HOSTILE_AT - 15
	st["subdued"] = false
	st["cleared"] = false
	st["next_raid_day"] = w.day + 2
	change_relation(sid, HOSTILE_AT - 15 - int(st["relation"]), "attack")
	w.notify_key("sim.village.attacked", {"village_name": str(st["name"])}, "bad",
		Vector2(st["center"]), {"site": sid})


func villager_killed(sid: int, victim: Unit, attacker: Unit) -> void:
	var st: Dictionary = w.sites.get(sid, {})
	if not is_village(st):
		return
	st["population"] = maxi(0, int(st.get("population", 0)) - 1)
	(st["units"] as Array).erase(victim.id)
	if attacker and attacker.is_player():
		change_relation(sid, -6 if str(victim.character.get("role", "")) in ["guard", "archer"] else -12, "casualty")


## Every armed defender is down: the village is plundered and left in ruins for a few days.
func subdue(sid: int, attacker: Unit = null) -> void:
	var st: Dictionary = w.sites.get(sid, {})
	if not is_village(st) or bool(st.get("subdued", false)):
		return
	st["subdued"] = true
	st["ruined"] = true
	st["ruined_until"] = w.day + 3 + int(st.get("level", 1))
	st["cleared"] = true
	st["cleared_day"] = w.day
	st["request"] = {}
	var survivors := maxi(2, int(float(int(st.get("population", 5))) * 0.55))
	var items: Array = []
	for row: Dictionary in st.get("goods", []):
		for i in int(row.get("count", 0)):
			var item: Dictionary = (row.get("item", {}) as Dictionary).duplicate(true)
			item["uid"] = 0
			items.append(item)
	items.append_array(st.get("cache", []))
	var stock: Dictionary = st.get("stock", {})
	var resources: Dictionary = {}
	for resource: String in TRADE_RESOURCES:
		var amount := int(float(int(stock.get(resource, 0))) * 0.7)
		if amount > 0:
			resources[resource] = amount
	var gold := int(st.get("purse", 0)) + int(st.get("cache_gold", 0))
	var bag := w.drop_loot(Vector2(st["center"]) + Vector2(0.5, 2.0), items, gold, 0, resources)
	st["stock"] = {}
	st["goods"] = []
	st["cache"] = []
	st["cache_gold"] = 0
	st["purse"] = 0
	st["population"] = survivors
	# the villagers who were still standing abandon the place; a smaller group returns on recovery
	for id: Variant in (st["units"] as Array).duplicate():
		var u := w.get_unit(int(id))
		if u:
			w.remove_unit(u)
	st["units"] = []
	if not bag.is_empty() and attacker and attacker.is_player() and attacker.pos.distance_to(Vector2(bag["pos"])) < 3.0:
		w.pickup_loot(int(bag["id"]), attacker)
	w.counters["villages_subdued"] = int(w.counters.get("villages_subdued", 0)) + 1
	w.notify_key("sim.village.subdued", {"village_name": str(st["name"])}, "loot",
		Vector2(st["center"]), {"site": sid})
	w.site_changed.emit(sid)


## Called when the player's forces kill raiders that came from a village's neighbourhood.
func defended(sid: int) -> void:
	var st: Dictionary = w.sites.get(sid, {})
	if is_village(st) and bool(st.get("discovered", false)) and not bool(st.get("ruined", false)):
		change_relation(sid, 5, "defense")
		w.notify_key("sim.village.defended", {"village_name": str(st["name"])}, "good",
			Vector2(st["center"]), {"site": sid})


## A bandit raid was beaten near a friendly village: nearby villages notice.
func bandit_raid_repelled(pos: Vector2) -> void:
	for st: Dictionary in w.sites.values():
		if is_village(st) and bool(st.get("discovered", false)) \
				and Vector2(st["center"]).distance_to(pos) < 60.0:
			defended(int(st["id"]))


# --- days ----------------------------------------------------------------------------------

func on_new_day() -> void:
	for st: Dictionary in w.sites.values():
		if not is_village(st):
			continue
		var sid := int(st["id"])
		var current := int(st.get("relation", 0))
		var baseline := int(st.get("baseline_relation", current))
		if current != baseline:
			_change_one(st, 1 if current < baseline else -1)
		if w.day - int(st.get("gift_decay_day", w.day)) >= 3:
			st["gift_decay_day"] = w.day
			st["gift_count"] = maxi(0, int(st.get("gift_count", 0)) - 1)
		var request: Dictionary = st.get("request", {})
		if not request.is_empty() and w.day > int(request.get("due_day", 0)):
			st["request"] = {}
			st["request_day"] = w.day
			change_relation(sid, -3, "ignored")
			if bool(st.get("discovered", false)):
				w.notify_key("sim.village.request_expired", {"village_name": str(st["name"])},
					"bad", Vector2(st["center"]), {"site": sid})
		if bool(st.get("ruined", false)) and w.day >= int(st.get("ruined_until", 0)):
			_recover(st)
		_refresh_stock(st)
		st["purse"] = mini(int(st.get("purse", 0)) + 8 + int(st.get("level", 1)) * 4, 320)
		if (st.get("request", {}) as Dictionary).is_empty() and not bool(st.get("ruined", false)) \
				and w.day - int(st.get("request_day", 0)) >= 2:
			_roll_request(st, RngUtil.make([w.seed, "village_request", sid, w.day]))
		if int(st.get("relation", 0)) >= FRIENDLY_AT and not bool(st.get("ruined", false)):
			_daily_friendly(st)


func _daily_friendly(st: Dictionary) -> void:
	var rng := RngUtil.make([w.seed, "village_friendly", int(st["id"]), w.day])
	if int(st.get("relation", 0)) >= ALLIED_AT and rng.randf() < 0.25:
		var gifts := ["food", "wood", "stone"]
		var resource := str(gifts[rng.randi_range(0, gifts.size() - 1)])
		var amount := rng.randi_range(4, 9)
		w.economy.add(resource, amount)
		w.notify_key("sim.village.allied_gift", {"village_name": str(st["name"]),
			"resources": {"resources": {resource: amount}}}, "good",
			Vector2(st["center"]), {"site": int(st["id"])})
		return
	if w.population() < w.housing() and not w.hungry and int(w.res.get("food", 0)) > w.population() + 2 \
			and rng.randf() < 0.18:
		var race := str(st["race"])
		var newcomer := CharacterFactory.make_colonist(w, {"race": race, "level": 1}, w.home_pos())
		w.assign_art_variant(newcomer)
		w.notify_key("sim.village.settler", {"unit_name": newcomer.name, "village_name": str(st["name"]),
			"race": {"table": "races", "id": race}}, "good", newcomer.pos,
			{"unit": newcomer.id, "site": int(st["id"])})
		w.unit_changed.emit(newcomer)


func _recover(st: Dictionary) -> void:
	var sid := int(st["id"])
	var rng := RngUtil.make([w.seed, "village_recovery", sid, w.day])
	st["ruined"] = false
	st["subdued"] = false
	st["cleared"] = false
	st["cleared_day"] = 0
	st["units"] = []
	var population := clampi(int(st.get("population", 3)), 3, 8)
	var centre := Vector2(st["center"]) + Vector2(0.5, 0.5)
	var guards := clampi(population / 3, 1, 3)
	for i in population:
		var role := "farmer"
		if i < guards:
			role = "guard"
		elif i == population - 1:
			role = "elder"
		(st["units"] as Array).append(_spawn_villager(st, centre, role, rng).id)
	st["population"] = population
	st["purse"] = 20 + int(st.get("level", 1)) * 10
	st["next_raid_day"] = w.day + 2 + rng.randi_range(0, 2)
	_refresh_stock(st, true)
	w.notify_key("sim.village.recovered", {"village_name": str(st["name"]), "population": population},
		"info", centre, {"site": sid})
	w.site_changed.emit(sid)
