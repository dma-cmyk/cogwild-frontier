class_name Diplomacy
extends RefCounted
## Communities (race villages and the mixed-race town): relations, quests, local trade, plunder,
## recovery, recruiting residents and small talk.
##
## Every mutable value lives in the community's site Dictionary, so the existing site save/load path
## persists all of it without a second schema. Relations are deterministic: the initial value comes
## from the community's temperament plus the founder's race, and every later change is caused by a
## player action or the daily drift toward the baseline.
##
## One faction id is shared by all villages of a race (`folk_<race>`, see docs/contracts.md), so a
## race turns hostile as a whole; attacking one village also drags its kin down through
## `_share_with_kin`. The town has no kin: its faction is `townsfolk` and it stands alone.

const HOSTILE_AT := -50
const FRIENDLY_AT := 30
const ALLIED_AT := 70
const TRADE_RANGE := 9.0            ## a colony unit must stand this close to trade / deliver
const RESOURCE_PRICES := {"wood": 2, "stone": 2, "ore": 4, "metal": 8, "food": 2}
const TRADE_RESOURCES := ["wood", "stone", "ore", "metal", "food"]
const TEMPERAMENT_BASE := {"welcoming": 18, "trading": 8, "reserved": -8, "proud": -2, "wary": -18}
const STOCK_LIMIT := 220
const DAILY_GOODWILL_CAP := 6       ## relation a community can gain from trading in one day
const TIERS := ["Hostile", "Wary", "Neutral", "Friendly", "Allied"]
const COMMUNITY_KINDS := ["village", "town"]
const POPULATION_RANGE := [8, 14]   ## village head count unless the race config says otherwise
const MIN_POPULATION := 6           ## a community never lets recruiting take it below this
const RECRUIT_COOLDOWN_DAYS := 2
const RECRUIT_BASE_COST := 40
const TALK_GAIN_CAP := 2            ## relation a community can gain from small talk in one day

var w: World
## faction id -> true for every `folk_<race>` that currently fights the player. `World.hostile()`
## runs per attack check, so the answer is cached instead of scanning the sites every time.
var hostile_folk: Dictionary = {}
## site id -> routine spots derived from the generated layout (see `village_spots`).
var _spot_cache: Dictionary = {}


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


## Race villages only (kin sharing, villager spawning, village-flavoured text).
func is_village(st: Dictionary) -> bool:
	return str(st.get("kind", "")) == "village" and str(st.get("race", "")) != ""


## Any settled community the player can have a relation with: race villages and the town.
func is_community(st: Dictionary) -> bool:
	var kind := str(st.get("kind", ""))
	if kind == "village":
		return str(st.get("race", "")) != ""
	return kind in COMMUNITY_KINDS


## Data row driving a community: the race row for villages, `data/villages/town.json` for the town.
## The town file may be an id table (`{"table": "town", "entries": [{"id": "town", ...}]}`) or a
## plain object document; both resolve here.
func community_config(st: Dictionary) -> Dictionary:
	var kind := str(st.get("kind", ""))
	if kind == "village":
		return race_config(str(st.get("race", "")))
	var id := str(st.get("config_id", kind))
	var cfg := DB.get_def("villages/" + kind, id)
	if cfg.is_empty():
		var doc: Variant = DB.raw("villages/" + kind)
		if doc is Dictionary:
			cfg = doc
	return cfg


## [min, max] head count of a community.
func population_range(st: Dictionary) -> Array:
	var configured: Array = community_config(st).get("population", POPULATION_RANGE)
	if configured.size() < 2:
		return POPULATION_RANGE
	return [int(configured[0]), int(configured[1])]


func min_population(st: Dictionary) -> int:
	return int(community_config(st).get("min_population",
		mini(MIN_POPULATION, int(population_range(st)[0]))))


func relation(sid: int) -> int:
	return int(w.sites.get(sid, {}).get("relation", 0))


func tier(sid: int) -> String:
	return tier_for(relation(sid))


## Discovered communities (villages and the town), by site id.
func known_communities() -> Array:
	var result: Array = []
	for sid: Variant in w.sites:
		var st: Dictionary = w.sites[sid]
		if is_community(st) and bool(st.get("discovered", false)):
			result.append(st)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	return result


func faction_hostile_to_player(faction: String) -> bool:
	return hostile_folk.has(faction)


## Rebuilt after loading a save and whenever a community's relation crosses the hostile line.
func rebuild_hostile_cache() -> void:
	hostile_folk.clear()
	for st: Dictionary in w.sites.values():
		if is_community(st) and int(st.get("relation", 0)) <= HOSTILE_AT:
			hostile_folk[str(st.get("faction", "folk_" + str(st.get("race", "?"))))] = true


# --- founding ------------------------------------------------------------------------------

func initialize(st: Dictionary, rng: RandomNumberGenerator) -> void:
	if not is_community(st):
		return
	var village := is_village(st)
	var race := str(st.get("race", ""))
	var cfg := community_config(st)
	var temperament := str(cfg.get("temperament", "reserved"))
	var base := int(cfg.get("starting_relation", TEMPERAMENT_BASE.get(temperament, 0)))
	var founder := w.get_unit(w.player_unit_id)
	if founder and village and str(founder.character.get("race", "")) == race:
		base += 20
	var value := clampi(base + rng.randi_range(-4, 4), -100, 100)
	var own_faction := str(st.get("faction", ""))
	st["faction"] = ("folk_" + race) if village else (own_faction if own_faction != "" else "townsfolk")
	st["relation"] = value
	st["baseline_relation"] = value
	st["hostile"] = value <= HOSTILE_AT
	st["temperament"] = temperament
	var range_ := population_range(st)
	st["population"] = rng.randi_range(int(range_[0]), int(range_[1]))
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
	st["grow_day"] = w.day
	st["recruit_day"] = -99
	st["cache"] = ItemGen.loot(rng, int(st.get("level", 1)), 0.12, 1)
	st["cache_gold"] = rng.randi_range(12, 34)
	_refresh_stock(st, true)
	if value <= HOSTILE_AT:
		hostile_folk[str(st["faction"])] = true


## Village jobs in spawn order: guards first (they anchor the ring), then the elder, the stall
## traders and the crafters, and everyone else works the fields.
const CRAFTER_ROLES := ["builder", "tinkerer", "cook", "woodcutter", "miner"]


func populate(st: Dictionary, rng: RandomNumberGenerator) -> void:
	var population := int(st.get("population", 6))
	var centre := Vector2(st["center"]) + Vector2(0.5, 0.5)
	for role: String in village_roles(st, population):
		var u := _spawn_villager(st, centre, role, rng)
		(st["units"] as Array).append(u.id)
	st["population"] = population


## The role of every resident of a village of `population` people, in spawn order.
func village_roles(st: Dictionary, population: int) -> Array:
	var cfg := community_config(st)
	var roles: Array = []
	# the watch stays the race's configured size: a bigger village has more workers, not a
	# stronger garrison (plundering one stays a fight a starting squad can win)
	var guards := clampi(int(cfg.get("guards", 2)), 1, maxi(1, population - 4))
	for i in guards:
		roles.append("archer" if i == guards - 1 and guards >= 2 else "guard")
	roles.append("elder")
	var traders := clampi(population / 6, 1, 2)
	for i in traders:
		if roles.size() < population:
			roles.append("trader")
	var crafters := clampi(population / 5, 1, 3)
	for i in crafters:
		if roles.size() < population:
			roles.append(str(CRAFTER_ROLES[i % CRAFTER_ROLES.size()]))
	while roles.size() < population:
		roles.append("farmer")
	roles.resize(population)
	return roles


## The daily routine a resident follows, derived from its role (no extra saved state).
static func resident_job(u: Unit) -> String:
	if not u.named.is_empty():
		return "elder"
	match str(u.character.get("role", "")):
		"guard", "archer", "mercenary":
			return "guard"
		"trader", "merchant":
			return "trader"
		"scholar", "researcher", "medic":
			return "elder"
		"farmer", "hunter":
			return "farmer"
		"builder", "tinkerer", "cook", "woodcutter", "miner", "engineer":
			return "crafter"
	return "farmer"


func _spawn_villager(st: Dictionary, centre: Vector2, role: String, rng: RandomNumberGenerator) -> Unit:
	var race := str(st["race"])
	var level := maxi(1, int(st.get("level", 1)))
	var candidate := centre + Vector2(rng.randf_range(-7.0, 7.0), rng.randf_range(-7.0, 7.0))
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


## Living residents of a community, in a stable order (the UI list and recruiting read this).
func residents(sid: int) -> Array:
	var out: Array = []
	for id: Variant in (w.sites.get(sid, {}) as Dictionary).get("units", []):
		var u := w.get_unit(int(id))
		if u and u.alive and u.is_person():
			out.append(u)
	return out


## Where the daily routines happen, derived once per village from its generated layout and then
## cached: fields to till, stalls to mind, piles to work, homes to sleep in and a guard ring.
## Returns {"hall": Vector2, "homes": Array, "stalls": Array, "fields": Array, "craft": Array,
## "ring": Array} — all positions are world centres.
func village_spots(sid: int) -> Dictionary:
	if _spot_cache.has(sid):
		return _spot_cache[sid]
	var layout: Dictionary = w.gen.sites.get(sid, {})
	var centre := Vector2(w.sites.get(sid, layout).get("center", Vector2i.ZERO)) + Vector2(0.5, 0.5)
	var spots := {"hall": centre, "homes": [], "stalls": [], "fields": [], "craft": [], "ring": []}
	for s: Dictionary in layout.get("structures", []):
		var size := Vector2(s["size"])
		var middle := Vector2(s["origin"]) + size * 0.5
		var front := middle + Vector2(0.0, size.y * 0.5 + 0.9)
		var type := str(s["type"])
		if type.ends_with("_hall"):
			spots["hall"] = front
		elif type.ends_with("_home"):
			(spots["homes"] as Array).append(front)
		elif type == "trade_stall":
			(spots["stalls"] as Array).append(front)
	for d: Array in layout.get("decor", []):
		var prop := str(d[0])
		var at := Vector2(float(d[1]), float(d[2]))
		if prop == "tilled_soil" and (spots["fields"] as Array).size() < 12:
			if ((spots["fields"] as Array).is_empty()
					or (spots["fields"] as Array).back().distance_to(at) > 2.0):
				(spots["fields"] as Array).append(at + Vector2(0.0, 1.0))
		elif prop in ["log_pile", "stone_pile", "crate", "barrel"]:
			(spots["craft"] as Array).append(at + Vector2(0.9, 0.9))
	for i in 8:
		var a := TAU * float(i) / 8.0
		(spots["ring"] as Array).append(centre + Vector2(cos(a), sin(a)) * 11.0)
	if (spots["homes"] as Array).is_empty():
		(spots["homes"] as Array).append(centre)
	if (spots["fields"] as Array).is_empty():
		(spots["fields"] as Array).append(centre + Vector2(4.0, 4.0))
	if (spots["craft"] as Array).is_empty():
		(spots["craft"] as Array).append(centre + Vector2(-3.0, 2.0))
	if (spots["stalls"] as Array).is_empty():
		spots["stalls"] = [spots["hall"]]
	_spot_cache[sid] = spots
	return spots


# --- relation ------------------------------------------------------------------------------

func change_relation(sid: int, delta: int, reason: String = "") -> void:
	var st: Dictionary = w.sites.get(sid, {})
	if not is_community(st) or delta == 0:
		return
	_change_one(st, delta)
	if is_village(st) and reason in ["trade", "gift", "request", "attack", "casualty", "defense"]:
		_share_with_kin(st, delta)


## Kin of the same race hear about it: a third of the change, capped so a single brawl does not
## flip every village of that race at once. The town has no kin.
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
	if not is_community(st):
		return
	if is_village(st):
		w.notify_key("sim.village.discovered", {"village_name": str(st.get("name", "")),
			"race": {"table": "races", "id": str(st["race"])},
			"tier": {"list": [tier_for(int(st.get("relation", 0)))]}},
			"discover", Vector2(st["center"]), {"site": int(st["id"])})
	else:
		w.notify_key("sim.town.discovered", {"town_name": str(st.get("name", "")),
			"tier": {"list": [tier_for(int(st.get("relation", 0)))]}},
			"discover", Vector2(st["center"]), {"site": int(st["id"])})
	w.quests.board(int(st["id"]))


# --- presence & trade ------------------------------------------------------------------------

## Trading, gifting, quests, talking and recruiting all need a colony unit standing in the
## community, the same rule the wanderer camps use for recruiting: walk someone (or a squad) over.
func is_near_community(sid: int, radius: float = -1.0) -> bool:
	var st: Dictionary = w.sites.get(sid, {})
	if not is_community(st):
		return false
	if radius < 0.0:
		# the town spreads its shops around a wide plaza; a village is walked in a few steps
		radius = Town.TOWN_RANGE if str(st["kind"]) == "town" else TRADE_RANGE
	var centre := Vector2(st["center"]) + Vector2(0.5, 0.5)
	# Do not use World's spatial grid here: callers (and save/load) can move a unit
	# between simulation rebuilds, and diplomacy must observe the authoritative position.
	for u: Unit in w.unit_list:
		if u.is_player() and u.alive and u.state != Unit.State.DOWNED and u.pos.distance_to(centre) <= radius:
			return true
	return false


func can_trade(sid: int, require_presence: bool = true) -> bool:
	var st: Dictionary = w.sites.get(sid, {})
	return is_community(st) and bool(st.get("discovered", false)) \
		and not bool(st.get("ruined", false)) and can_trade_tier(int(st.get("relation", 0))) \
		and (not require_presence or is_near_community(sid))


## Why trading is not possible right now ("" = it is). Localized by the caller.
func trade_blocker(sid: int) -> String:
	var st: Dictionary = w.sites.get(sid, {})
	if not is_community(st) or not bool(st.get("discovered", false)):
		return "This village is not known yet."
	if bool(st.get("ruined", false)):
		return "The village is in ruins and trades nothing."
	if not can_trade_tier(int(st.get("relation", 0))):
		return "They will not trade while they distrust you."
	if not is_near_community(sid):
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
	if not is_community(st):
		return {}
	_refresh_stock(st)
	return st.get("stock", {})


func goods_of(sid: int) -> Array:
	var st: Dictionary = w.sites.get(sid, {})
	if not is_community(st):
		return []
	_refresh_stock(st)
	return st.get("goods", [])


func _refresh_stock(st: Dictionary, force: bool = false) -> void:
	if not force and int(st.get("stock_day", -1)) == w.day:
		return
	st["stock_day"] = w.day
	var ruined := bool(st.get("ruined", false))
	var cfg := community_config(st)
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
	var gold_before := int(w.res.get("gold", 0))
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
	w.notify_key("sim.trade.resource_bought" if buying else "sim.trade.resource_sold",
		{"site_name": st["name"], "resource_id": resource, "amount": amount,
			"gold": absi(int(w.res.get("gold", 0)) - gold_before)},
		"good", Vector2(st["center"]), {"site": sid})
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


# --- gifts ---------------------------------------------------------------------------------

## Goodwill a gift of `amount` `resource` would earn right now (shown in the UI before paying).
func gift_goodwill(sid: int, resource: String, amount: int) -> int:
	var st: Dictionary = w.sites.get(sid, {})
	var worth := int(RESOURCE_PRICES.get(resource, 2)) * amount
	var base := clampi(int(worth / 5.0), 1, 14)
	return maxi(1, int(round(float(base) / (1.0 + 0.7 * float(int(st.get("gift_count", 0)))))))


func gift(sid: int, resource: String, amount: int) -> String:
	var st: Dictionary = w.sites.get(sid, {})
	if not is_community(st) or not bool(st.get("discovered", false)):
		return "This village is not known yet."
	if not is_near_community(sid):
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


# --- recruiting ----------------------------------------------------------------------------

## Gold a community asks for one of its people. Friendly neighbours charge less than wary ones.
func recruit_cost(sid: int, unit_id: int) -> int:
	var u := w.get_unit(unit_id)
	if u == null:
		return 0
	var level := maxi(1, u.char_level())
	return maxi(10, int(round(float(RECRUIT_BASE_COST + level * 25) * price_factor(sid))))


## "" when `unit_id` can be invited into the colony, else an i18n key explaining why not.
func recruit_blocker(sid: int, unit_id: int) -> String:
	var st: Dictionary = w.sites.get(sid, {})
	if not is_community(st) or not bool(st.get("discovered", false)):
		return "village.recruit.unknown"
	if bool(st.get("ruined", false)):
		return "village.recruit.ruined"
	var u := w.get_unit(unit_id)
	if u == null or not u.alive or not u.is_person() or u.home_site != sid \
			or not (st["units"] as Array).has(unit_id):
		return "village.recruit.not_resident"
	if int(st.get("relation", 0)) < FRIENDLY_AT:
		return "village.recruit.relation"
	if not u.named.is_empty():
		return "village.recruit.elder"
	if int(st.get("population", 0)) <= min_population(st):
		return "village.recruit.population"
	if w.day - int(st.get("recruit_day", -99)) < RECRUIT_COOLDOWN_DAYS:
		return "village.recruit.cooldown"
	if w.population() >= w.housing():
		return "village.recruit.beds"
	if not is_near_community(sid):
		return "village.recruit.presence"
	if int(w.res.get("gold", 0)) < recruit_cost(sid, unit_id):
		return "village.recruit.gold"
	return ""


## Invites a resident into the colony. Returns "" or an i18n key reason.
func recruit(sid: int, unit_id: int) -> String:
	var blocker := recruit_blocker(sid, unit_id)
	if blocker != "":
		return blocker
	var st: Dictionary = w.sites[sid]
	var u := w.get_unit(unit_id)
	var cost := recruit_cost(sid, unit_id)
	w.res["gold"] = int(w.res.get("gold", 0)) - cost
	(st["units"] as Array).erase(unit_id)
	st["population"] = maxi(0, int(st.get("population", 1)) - 1)
	st["recruit_day"] = w.day
	u.faction = "player"
	w.assign_art_variant(u, true)
	u.archetype = "colonist"
	u.labor = "worker"
	u.home_site = -1
	u.order = {}
	u.job = {}
	u.visible = true
	u.hidden = false
	u.state = Unit.State.IDLE
	u.guard_pos = w.home_pos()
	CharacterFactory.sync_dna(u)
	u.recompute_stats()
	w.move_unit(u, w.home_pos())
	w.counters["residents_recruited"] = int(w.counters.get("residents_recruited", 0)) + 1
	w.notify_key("sim.village.recruited", {"unit_name": u.name, "village_name": str(st["name"]),
		"race": {"table": "races", "id": str(u.character.get("race", ""))},
		"role": {"table": "roles", "id": str(u.character.get("role", "")), "en": u.display_role()},
		"gold": cost}, "good", u.pos, {"unit": u.id, "site": sid})
	w.unit_changed.emit(u)
	w.site_changed.emit(sid)
	return ""


# --- talking -------------------------------------------------------------------------------

## A line from a resident: {text_key, params, rumor_sid}. Race-, job- and tier-flavoured, and
## every so often a rumour that puts an unknown place on your map.
func talk(sid: int, unit_id: int) -> Dictionary:
	var st: Dictionary = w.sites.get(sid, {})
	var u := w.get_unit(unit_id)
	if not is_community(st) or u == null or not u.is_person():
		return {"text_key": "village.talk.generic.1", "params": {}, "rumor_sid": -1}
	var talks := int(st.get("talk_count", 0)) + 1
	st["talk_count"] = talks
	var rng := RngUtil.make([w.seed, "talk", sid, unit_id, w.day, talks])
	var tier_name := tier_for(int(st.get("relation", 0)))
	var params := {"unit_name": u.name, "village_name": str(st.get("name", "")),
		"race": {"table": "races", "id": str(u.character.get("race", ""))}}
	var rumor_sid := -1
	var buckets: Array = []
	if tier_name != "Hostile":
		buckets.append("job_" + resident_job(u))
		buckets.append("race_" + str(u.character.get("race", "")))
	buckets.append("tier_" + tier_name.to_lower())
	buckets.append("generic")
	var text_key := ""
	# a rumour needs trust: neutral and better, and something left to find
	if tier_name in ["Neutral", "Friendly", "Allied"] and rng.randf() < (0.4 if tier_name == "Allied" else 0.25):
		rumor_sid = _rumor_site(st, rng)
		if rumor_sid >= 0:
			var target: Dictionary = w.sites[rumor_sid]
			params["site_name"] = str(target.get("name", ""))
			params["site_kind_id"] = str(target.get("kind", ""))
			params["direction"] = Loc.t(Quests.direction_between(Vector2(st["center"]), Vector2(target["center"])))
			text_key = _line(rng, "rumor_site")
	if text_key == "":
		var wants: Array = community_config(st).get("wants", [])
		if not wants.is_empty() and rng.randf() < 0.2:
			params["resource"] = Loc.t(str(wants[rng.randi_range(0, wants.size() - 1)]))
			text_key = _line(rng, "rumor_want")
	if text_key == "":
		# Starting with the job every time made race, tier and generic lines unreachable.
		var start := rng.randi_range(0, buckets.size() - 1)
		for offset in buckets.size():
			text_key = _line(rng, buckets[(start + offset) % buckets.size()])
			if text_key != "":
				break
	if text_key == "":
		text_key = "village.talk.generic.1"
	_talk_goodwill(st)
	return {"text_key": text_key, "params": params, "rumor_sid": rumor_sid}


func _line(rng: RandomNumberGenerator, bucket: String) -> String:
	var lines: Array = DB.get_def("villages/dialogue", bucket).get("lines", [])
	if lines.is_empty():
		return ""
	return str(lines[rng.randi_range(0, lines.size() - 1)])


## Marks an undiscovered site near the community as known and notes it.
func _rumor_site(st: Dictionary, rng: RandomNumberGenerator) -> int:
	var centre := Vector2(st["center"])
	var candidates: Array = []
	for gs: Dictionary in w.gen.sites.values():
		var target_sid := int(gs["id"])
		if bool((w.sites.get(target_sid, {}) as Dictionary).get("discovered", false)):
			continue
		if Vector2(gs["center"]).distance_to(centre) > 180.0:
			continue
		candidates.append(target_sid)
	if candidates.is_empty():
		return -1
	var chosen := int(candidates[rng.randi_range(0, candidates.size() - 1)])
	for offset_z in range(-1, 2):
		for offset_x in range(-1, 2):
			w.ensure_chunk(w.chunk_key(Vector2i(w.gen.sites[chosen]["center"])) + Vector2i(offset_x, offset_z))
	var target: Dictionary = w.sites.get(chosen, {})
	if target.is_empty():
		return -1
	target["discovered"] = true
	w.notify_key("sim.village.rumor", {"village_name": str(st.get("name", "")),
		"site_name": str(target.get("name", "")), "site_kind_id": str(target.get("kind", ""))},
		"discover", Vector2(target["center"]), {"site": chosen})
	w.site_changed.emit(chosen)
	return chosen


## Chatting is worth a little goodwill, capped per community per day.
func _talk_goodwill(st: Dictionary) -> void:
	if int(st.get("talk_day", -1)) != w.day:
		st["talk_day"] = w.day
		st["talk_gain_today"] = 0
	if int(st.get("talk_gain_today", 0)) >= TALK_GAIN_CAP or int(st.get("relation", 0)) <= HOSTILE_AT:
		return
	st["talk_gain_today"] = int(st.get("talk_gain_today", 0)) + 1
	change_relation(int(st["id"]), 1, "talk")


# --- war & peace ---------------------------------------------------------------------------

func tribute_cost(sid: int) -> int:
	return 35 + int(w.sites.get(sid, {}).get("level", 1)) * 18


func make_peace(sid: int) -> String:
	var st: Dictionary = w.sites.get(sid, {})
	if not is_community(st) or int(st.get("relation", 0)) > HOSTILE_AT:
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
	if is_village(st):
		for other: Dictionary in w.sites.values():
			if is_village(other) and str(other["race"]) == str(st["race"]) and int(other.get("relation", 0)) <= HOSTILE_AT:
				other["baseline_relation"] = maxi(int(other.get("baseline_relation", 0)), HOSTILE_AT + 12)
				_change_one(other, HOSTILE_AT + 12 - int(other.get("relation", 0)))
	rebuild_hostile_cache()
	w.notify_key("sim.village.peace", {"village_name": str(st["name"]), "gold": tribute},
		"good", Vector2(st["center"]), {"site": sid})
	return ""


## The player confirmed an attack on a community that was not hostile yet.
func declare_attack(sid: int) -> void:
	var st: Dictionary = w.sites.get(sid, {})
	if not is_community(st) or int(st.get("relation", 0)) <= HOSTILE_AT:
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
	if not is_community(st):
		return
	st["population"] = maxi(0, int(st.get("population", 0)) - 1)
	(st["units"] as Array).erase(victim.id)
	if attacker and attacker.is_player():
		change_relation(sid, -6 if str(victim.character.get("role", "")) in ["guard", "archer"] else -12, "casualty")


## Every armed defender is down: the community is plundered and left in ruins for a few days.
func subdue(sid: int, attacker: Unit = null) -> void:
	var st: Dictionary = w.sites.get(sid, {})
	if not is_community(st) or bool(st.get("subdued", false)):
		return
	st["subdued"] = true
	st["ruined"] = true
	st["ruined_until"] = w.day + 3 + int(st.get("level", 1))
	st["cleared"] = true
	st["cleared_day"] = w.day
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


## Called when the player's forces kill raiders that came from a community's neighbourhood.
func defended(sid: int) -> void:
	var st: Dictionary = w.sites.get(sid, {})
	if is_community(st) and bool(st.get("discovered", false)) and not bool(st.get("ruined", false)):
		change_relation(sid, 5, "defense")
		w.notify_key("sim.village.defended", {"village_name": str(st["name"])}, "good",
			Vector2(st["center"]), {"site": sid})


## A bandit raid was beaten near a friendly community: neighbours notice.
func bandit_raid_repelled(pos: Vector2) -> void:
	for st: Dictionary in w.sites.values():
		if is_community(st) and bool(st.get("discovered", false)) \
				and Vector2(st["center"]).distance_to(pos) < 60.0:
			defended(int(st["id"]))


# --- days ----------------------------------------------------------------------------------

func on_new_day() -> void:
	for st: Dictionary in w.sites.values():
		if not is_community(st):
			continue
		var sid := int(st["id"])
		var current := int(st.get("relation", 0))
		var baseline := int(st.get("baseline_relation", current))
		if current != baseline:
			_change_one(st, 1 if current < baseline else -1)
		if w.day - int(st.get("gift_decay_day", w.day)) >= 3:
			st["gift_decay_day"] = w.day
			st["gift_count"] = maxi(0, int(st.get("gift_count", 0)) - 1)
		if bool(st.get("ruined", false)) and w.day >= int(st.get("ruined_until", 0)):
			_recover(st)
		_refresh_stock(st)
		st["purse"] = mini(int(st.get("purse", 0)) + 8 + int(st.get("level", 1)) * 4, 320)
		_regrow(st)
		if int(st.get("relation", 0)) >= FRIENDLY_AT and not bool(st.get("ruined", false)):
			_daily_friendly(st)


## Peaceful communities slowly fill up again to their configured head count.
func _regrow(st: Dictionary) -> void:
	if bool(st.get("ruined", false)) or int(st.get("relation", 0)) <= HOSTILE_AT:
		return
	var top := int(population_range(st)[1])
	if int(st.get("population", 0)) >= top or w.day - int(st.get("grow_day", 0)) < 3:
		return
	st["grow_day"] = w.day
	st["population"] = int(st.get("population", 0)) + 1
	# only instantiated communities have live units; the rest just count heads
	if is_village(st) and not (st["units"] as Array).is_empty():
		var rng := RngUtil.make([w.seed, "village_growth", int(st["id"]), w.day])
		var centre := Vector2(st["center"]) + Vector2(0.5, 0.5)
		(st["units"] as Array).append(_spawn_villager(st, centre, "farmer", rng).id)
	w.site_changed.emit(int(st["id"]))


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
		var race := str(st.get("race", ""))
		if race == "":
			var locals := residents(int(st["id"]))
			if locals.is_empty():
				return
			race = str((locals[rng.randi_range(0, locals.size() - 1)] as Unit).character.get("race", ""))
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
	var population := clampi(int(st.get("population", 3)), 3, int(population_range(st)[0]))
	st["population"] = population
	st["purse"] = 20 + int(st.get("level", 1)) * 10
	st["next_raid_day"] = w.day + 2 + rng.randi_range(0, 2)
	if is_village(st):
		var centre := Vector2(st["center"]) + Vector2(0.5, 0.5)
		for role: String in village_roles(st, population):
			(st["units"] as Array).append(_spawn_villager(st, centre, role, rng).id)
	else:
		# the town rebuilds its own mixed-race crowd
		var town: Variant = w.get("town")
		if town != null and (town as Object).has_method("repopulate"):
			(town as Object).call("repopulate", st, rng)
	_refresh_stock(st, true)
	w.notify_key("sim.village.recovered", {"village_name": str(st["name"]), "population": population},
		"info", Vector2(st["center"]) + Vector2(0.5, 0.5), {"site": sid})
	w.site_changed.emit(sid)
