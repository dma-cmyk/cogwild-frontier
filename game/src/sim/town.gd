class_name Town
extends RefCounted
## Town-only services and daily life. Persistent town state belongs to its site Dictionary so the
## existing site save path owns smith stock, candidates, residents and their schedules.

const SERVICE_JOBS := [
	{"type": "t_general_store", "job": "storekeeper", "role": "merchant"},
	{"type": "t_smithy", "job": "smith", "role": "tinkerer"},
	{"type": "t_inn", "job": "innkeeper", "role": "cook"},
	{"type": "t_tavern", "job": "barkeep", "role": "merchant"},
	{"type": "t_guild_hall", "job": "guild_clerk", "role": "scholar"},
]
const CITIZEN_ROLES := ["farmer", "merchant", "engineer", "scholar", "cook", "trader"]
const TOWN_RANGE := 22.0
const DEFAULT_REFRESH_DAYS := 3
const SHOP_CATEGORIES := ["weapon", "armor"]

var w: World


func _init(world: World) -> void:
	w = world


func config() -> Dictionary:
	var cfg := DB.get_def("villages/town", "town")
	return cfg if not cfg.is_empty() else DB.get_def("villages", "town")


func initialize(st: Dictionary, rng: RandomNumberGenerator) -> void:
	if str(st.get("kind", "")) != "town":
		return
	var cfg := config()
	var population_range: Array = cfg.get("population", [18, 22])
	var population := rng.randi_range(int(population_range[0]), int(population_range[1]))
	var g: Dictionary = w.gen.sites.get(int(st["id"]), {})
	var points := _layout_points(g)
	st["population"] = population
	st["town_work_points"] = points["work"]
	st["town_home_points"] = points["homes"]
	st["town_plaza"] = points["plaza"]
	st["town_patrol_points"] = points["patrol"]
	st["town_mercenary_ids"] = []
	st["town_smithy_stock"] = []
	st["town_smithy_refresh_day"] = w.day + _refresh_days("smithy")
	st["town_mercenary_refresh_day"] = w.day + _refresh_days("tavern")
	st["town_trade_day"] = w.day
	st["town_trade_gain_today"] = 0
	_spawn_residents(st, population, int(cfg.get("guards", 4)), rng)
	_refresh_smithy(st, rng)
	_refresh_mercenaries(st, rng)


func _layout_points(site: Dictionary) -> Dictionary:
	var work: Dictionary = {}
	var homes: Array[Vector2] = []
	var center := Vector2(site.get("center", Vector2i.ZERO)) + Vector2(0.5, 0.5)
	var plaza := _walkable_near(center, 6)
	for structure: Dictionary in site.get("structures", []):
		var kind := str(structure.get("type", ""))
		var origin := Vector2(structure.get("origin", Vector2i.ZERO))
		var size := Vector2(structure.get("size", Vector2i.ONE))
		if kind.ends_with("_home"):
			homes.append(_walkable_near(origin + Vector2(size.x * 0.5, size.y + 1.6), 6))
		for row: Dictionary in SERVICE_JOBS:
			if kind == str(row["type"]):
				work[str(row["job"])] = _walkable_near(origin + Vector2(size.x * 0.5, size.y + 1.6), 6)
	if homes.is_empty():
		homes.append(plaza)
	var patrol: Array[Vector2] = []
	for i in 5:
		var angle := TAU * float(i) / 5.0
		var point := center + Vector2(cos(angle), sin(angle)) * 17.0
		patrol.append(_walkable_near(point, 6))
	return {"work": work, "homes": homes, "plaza": plaza, "patrol": patrol}


func _walkable_near(pos: Vector2, radius: int) -> Vector2:
	var tile := w.nearest_walkable(Vector2i(int(floor(pos.x)), int(floor(pos.y))), radius)
	return Vector2(tile) + Vector2(0.5, 0.5) if tile.x != -99999 else pos


func _random_walkable(pos: Vector2, radius: float, rng: RandomNumberGenerator) -> Vector2:
	for _attempt in 10:
		var angle := rng.randf() * TAU
		var candidate := pos + Vector2(cos(angle), sin(angle)) * rng.randf_range(0.0, radius)
		var tile := w.nearest_walkable(Vector2i(int(floor(candidate.x)), int(floor(candidate.y))), 4)
		if tile.x != -99999:
			return Vector2(tile) + Vector2(0.5, 0.5)
	return _walkable_near(pos, 8)


func _spawn_residents(st: Dictionary, population: int, guard_count: int, rng: RandomNumberGenerator) -> void:
	var sid := int(st["id"])
	var center := Vector2(st["center"]) + Vector2(0.5, 0.5)
	var homes: Array = st.get("town_home_points", [])
	var home_count := maxi(1, homes.size())
	var guards := clampi(guard_count, 1, maxi(1, population - SERVICE_JOBS.size()))
	for i in population:
		var home: Vector2 = homes[i % home_count] if not homes.is_empty() else center
		var job := "townsfolk"
		var role := str(CITIZEN_ROLES[rng.randi_range(0, CITIZEN_ROLES.size() - 1)])
		var position := _random_walkable(home, 4.0, rng)
		if i < guards:
			job = "watch"
			role = "guard"
			var patrol: Array = st.get("town_patrol_points", [])
			if not patrol.is_empty():
				position = patrol[i % patrol.size()]
		elif i - guards < SERVICE_JOBS.size():
			var service: Dictionary = SERVICE_JOBS[i - guards]
			job = str(service["job"])
			role = str(service["role"])
			position = Vector2((st.get("town_work_points", {}) as Dictionary).get(job, home))
		var u := CharacterFactory.make_person(w, {"role": role, "level": int(st.get("level", 1))},
			position, str(st.get("faction", "townsfolk")), "colonist")
		u.home_site = sid
		u.guard_pos = home
		u.character["town_job"] = job
		u.labor = "soldier" if job == "watch" else "worker"
		if job == "watch" and not (u.equipment().get("weapon") is Dictionary):
			var weapon := ItemGen.generate(rng, {"base": "spear", "level": int(st.get("level", 1)),
				"quality": "common", "source": "start"})
			weapon["uid"] = w.new_id()
			u.equipment()["weapon"] = weapon
			CharacterFactory.sync_dna(u)
			u.recompute_stats()
		(st["units"] as Array).append(u.id)


func service_blocker(sid: int) -> String:
	var st: Dictionary = w.sites.get(sid, {})
	if str(st.get("kind", "")) != "town" or not bool(st.get("discovered", false)):
		return "town.error.not_known"
	if bool(st.get("hostile", false)) or int(st.get("relation", 0)) <= Diplomacy.HOSTILE_AT:
		return "town.error.hostile"
	# the plaza is a fountain and the shops ring it: anywhere inside the town counts
	var center := Vector2(st.get("center", Vector2i.ZERO)) + Vector2(0.5, 0.5)
	for u: Unit in w.unit_list:
		if u.is_player() and u.alive and u.state != Unit.State.DOWNED \
				and u.pos.distance_to(center) <= TOWN_RANGE:
			return ""
	return "town.error.no_unit"


func smithy_stock(sid: int) -> Array:
	var st: Dictionary = _town(sid)
	if st.is_empty():
		return []
	_ensure_current(st)
	return st.get("town_smithy_stock", [])


func smithy_price(sid: int, item: Dictionary) -> int:
	return maxi(1, int(ceil(float(int(item.get("value", 1))) * w.diplomacy.price_factor(sid))))


func sell_price(sid: int, item: Dictionary) -> int:
	var value := int(floor(float(int(item.get("value", 1))) * 0.6 / w.diplomacy.price_factor(sid)))
	return maxi(1, value)


func buy_smithy(sid: int, index: int) -> String:
	var blocker := service_blocker(sid)
	if blocker != "":
		return blocker
	var st: Dictionary = w.sites[sid]
	_ensure_current(st)
	var stock: Array = st.get("town_smithy_stock", [])
	if index < 0 or index >= stock.size():
		return "town.error.stock"
	var item: Dictionary = stock[index].get("item", {})
	if item.is_empty():
		return "town.error.stock"
	var cost := smithy_price(sid, item)
	if int(w.res.get("gold", 0)) < cost:
		return "town.error.no_gold"
	w.res["gold"] = int(w.res["gold"]) - cost
	var owned := item.duplicate(true)
	owned["uid"] = w.new_id()
	w.armory.append(owned)
	stock.remove_at(index)
	st["town_smithy_stock"] = stock
	st["purse"] = int(st.get("purse", 0)) + cost
	_record_trade(st, cost)
	w.notify_key("sim.trade.item_bought", {"item": owned}, "loot", Vector2(st["center"]), {"site": sid})
	w.site_changed.emit(sid)
	return ""


func sell_item(sid: int, uid: int) -> String:
	var blocker := service_blocker(sid)
	if blocker != "":
		return blocker
	var st: Dictionary = w.sites[sid]
	for item: Dictionary in w.armory:
		if int(item.get("uid", 0)) != uid:
			continue
		var payout := sell_price(sid, item)
		if int(st.get("purse", 0)) < payout:
			return "town.error.no_gold"
		w.armory.erase(item)
		st["purse"] = int(st.get("purse", 0)) - payout
		w.economy.add("gold", payout)
		_record_trade(st, payout)
		w.site_changed.emit(sid)
		return ""
	return "town.error.item"


func local_units(sid: int) -> Array[Unit]:
	var result: Array[Unit] = []
	var st: Dictionary = _town(sid)
	if st.is_empty():
		return result
	var center := Vector2(st["center"]) + Vector2(0.5, 0.5)
	for u: Unit in w.player_people():
		if u.pos.distance_to(center) <= TOWN_RANGE:
			result.append(u)
	return result


func inn_price(sid: int, u: Unit) -> int:
	var services: Dictionary = config().get("services", {})
	var inn: Dictionary = services.get("inn", {})
	var missing := maxf(0.0, float(u.stats.get("max_hp", 1.0)) - u.hp)
	var injury_days := minf(float(inn.get("injury_days_removed", 1.0)), u.injured_days)
	var cost := int(inn.get("base_cost", 12)) + int(ceil(missing * float(inn.get("cost_per_missing_hp", 0.18))))
	if injury_days > 0.0:
		cost += int(ceil(float(inn.get("injury_cost", 35)) * injury_days))
	return maxi(0, cost)


func heal(sid: int, unit_id: int) -> String:
	var blocker := service_blocker(sid)
	if blocker != "":
		return blocker
	var u := w.get_unit(unit_id)
	if u == null or not u.alive or not u.is_player() or not u.is_person():
		return "town.error.not_colony_unit"
	var st: Dictionary = w.sites[sid]
	var center := Vector2(st["center"]) + Vector2(0.5, 0.5)
	if u.pos.distance_to(center) > TOWN_RANGE:
		return "town.error.not_colony_unit"
	var price := inn_price(sid, u)
	if price <= 0:
		return "town.error.not_colony_unit"
	if int(w.res.get("gold", 0)) < price:
		return "town.error.no_gold"
	w.res["gold"] = int(w.res["gold"]) - price
	var inn: Dictionary = (config().get("services", {}) as Dictionary).get("inn", {})
	u.injured_days = maxf(0.0, u.injured_days - float(inn.get("injury_days_removed", 1.0)))
	u.recompute_stats()
	u.hp = float(u.stats.get("max_hp", u.hp))
	if u.state == Unit.State.DOWNED:
		u.state = Unit.State.IDLE
		u.downed_t = 0.0
	w.notify_key("town.healed", {"unit_name": u.name, "gold": price}, "good", u.pos, {"site": sid, "unit": u.id})
	w.unit_changed.emit(u)
	w.site_changed.emit(sid)
	return ""


func mercenary_candidates(sid: int) -> Array[Unit]:
	var result: Array[Unit] = []
	var st: Dictionary = _town(sid)
	if st.is_empty():
		return result
	_ensure_current(st)
	for id: Variant in st.get("town_mercenary_ids", []):
		var u := w.get_unit(int(id))
		if u and u.alive:
			result.append(u)
	return result


func mercenary_price(sid: int, u: Unit) -> int:
	var tavern: Dictionary = (config().get("services", {}) as Dictionary).get("tavern", {})
	var base := float(tavern.get("base_hire_cost", 70)) * float(maxi(1, u.char_level()))
	return maxi(1, int(ceil(base * w.diplomacy.price_factor(sid))))


func hire_mercenary(sid: int, unit_id: int) -> String:
	var blocker := service_blocker(sid)
	if blocker != "":
		return blocker
	var st: Dictionary = w.sites[sid]
	_ensure_current(st)
	if not (st.get("town_mercenary_ids", []) as Array).has(unit_id):
		return "town.error.candidate"
	var u := w.get_unit(unit_id)
	if u == null or not u.alive:
		return "town.error.candidate"
	if w.housing() <= w.player_people().size():
		return "town.error.no_room"
	var cost := mercenary_price(sid, u)
	if int(w.res.get("gold", 0)) < cost:
		return "town.error.no_gold"
	w.res["gold"] = int(w.res["gold"]) - cost
	(st["town_mercenary_ids"] as Array).erase(unit_id)
	(st["units"] as Array).erase(unit_id)
	u.faction = "player"
	w.assign_art_variant(u, true)
	u.archetype = "colonist"
	u.labor = "worker"
	u.home_site = -1
	u.order = {}
	u.character.erase("town_job")
	u.character.erase("town_candidate")
	u.visible = true
	w.move_unit(u, w.home_pos())
	w.unit_changed.emit(u)
	w.notify_key("town.hired", {"unit_name": u.name,
		"race": {"table": "races", "id": str(u.character.get("race", "")), "en": str(DB.get_def("races", str(u.character.get("race", ""))).get("name", ""))}},
		"good", u.pos, {"site": sid, "unit": u.id})
	w.site_changed.emit(sid)
	return ""


func rumour_price(sid: int) -> int:
	var tavern: Dictionary = (config().get("services", {}) as Dictionary).get("tavern", {})
	return maxi(1, int(ceil(float(tavern.get("rumour_cost", 30)) * w.diplomacy.price_factor(sid))))
func has_rumour(sid: int) -> bool:
	return _rumour_target(sid) >= 0


func buy_rumour(sid: int) -> String:
	var blocker := service_blocker(sid)
	if blocker != "":
		return blocker
	var target_sid := _rumour_target(sid)
	if target_sid < 0:
		return "town.error.no_rumours"
	var cost := rumour_price(sid)
	if int(w.res.get("gold", 0)) < cost:
		return "town.error.no_gold"
	w.res["gold"] = int(w.res["gold"]) - cost
	if not w.sites.has(target_sid):
		w.factions.instantiate_site(target_sid)
	var target: Dictionary = w.sites.get(target_sid, {})
	if target.is_empty():
		w.res["gold"] = int(w.res["gold"]) + cost
		return "town.error.no_rumours"
	target["discovered"] = true
	var delta := Vector2(target["center"]) - Vector2(w.sites[sid]["center"])
	var direction := "town.direction.north" if absf(delta.y) > absf(delta.x) and delta.y < 0.0 else \
		"town.direction.south" if absf(delta.y) > absf(delta.x) else \
		"town.direction.east" if delta.x > 0.0 else "town.direction.west"
	w.notify_key("town.rumour_bought", {"site_name": str(target.get("name", Loc.t("Town"))),
		"direction": Loc.t(direction)}, "discover", Vector2(target["center"]), {"site": target_sid})
	w.site_changed.emit(target_sid)
	w.site_changed.emit(sid)
	return ""


func _rumour_target(sid: int) -> int:
	var town_center := Vector2(w.sites[sid]["center"])
	var best_sid := -1
	var best_distance := INF
	for key: Variant in w.gen.sites:
		var candidate_sid := int(key)
		if candidate_sid == sid:
			continue
		var existing: Dictionary = w.sites.get(candidate_sid, {})
		if not existing.is_empty() and bool(existing.get("discovered", false)):
			continue
		var generated: Dictionary = w.gen.sites[key]
		var distance := Vector2(generated.get("center", Vector2i.ZERO)).distance_to(town_center)
		if distance < best_distance:
			best_distance = distance
			best_sid = candidate_sid
	return best_sid


func routine(u: Unit, st: Dictionary) -> void:
	if u.target_id >= 0:
		u.target_id = -1
	if bool(u.character.get("town_candidate", false)):
		var work: Vector2 = (st.get("town_work_points", {}) as Dictionary).get("barkeep", u.guard_pos)
		_walk_to(u, work, 1.4)
		return
	if w.is_night():
		_walk_to(u, u.guard_pos, 1.0)
		return
	if u.moving:
		return
	var job := str(u.character.get("town_job", "townsfolk"))
	var work_points: Dictionary = st.get("town_work_points", {})
	if job in ["storekeeper", "smith", "innkeeper", "barkeep", "guild_clerk"]:
		_walk_to(u, Vector2(work_points.get(job, u.guard_pos)), 1.3)
		return
	if job == "watch":
		var patrol: Array = st.get("town_patrol_points", [])
		if patrol.size() >= 3:
			var next_point := int(u.character.get("town_patrol_index", 0)) % patrol.size()
			var target: Vector2 = patrol[next_point]
			if u.pos.distance_to(target) <= 2.0:
				next_point = (next_point + 1) % patrol.size()
				u.character["town_patrol_index"] = next_point
				target = patrol[next_point]
			w.move_unit(u, target)
		return
	u.ai_cd -= 1.0
	if u.ai_cd > 0.0:
		return
	var homes: Array = st.get("town_home_points", [])
	var targets: Array = [Vector2(st.get("town_plaza", u.guard_pos))]
	targets.append_array(work_points.values())
	if not homes.is_empty():
		targets.append(homes[w.rng.randi_range(0, homes.size() - 1)])
	var target: Vector2 = targets[w.rng.randi_range(0, targets.size() - 1)]
	if u.pos.distance_to(target) > 2.0:
		w.move_unit(u, target)
	u.ai_cd = w.rng.randf_range(12.0, 32.0)


func on_new_day() -> void:
	for st: Dictionary in w.sites.values():
		if str(st.get("kind", "")) == "town":
			_ensure_current(st)


func _walk_to(u: Unit, target: Vector2, tolerance: float) -> void:
	if not u.moving and u.pos.distance_to(target) > tolerance:
		w.move_unit(u, target)


func _town(sid: int) -> Dictionary:
	var st: Dictionary = w.sites.get(sid, {})
	return st if str(st.get("kind", "")) == "town" else {}


func _service_config(id: String) -> Dictionary:
	var services: Dictionary = config().get("services", {})
	return services.get(id, {})


func _refresh_days(id: String) -> int:
	return maxi(1, int(_service_config(id).get("refresh_days", DEFAULT_REFRESH_DAYS)))


func _ensure_current(st: Dictionary) -> void:
	var sid := int(st["id"])
	if w.day >= int(st.get("town_smithy_refresh_day", w.day + 1)):
		_refresh_smithy(st, RngUtil.make([w.seed, "town_smithy", sid, w.day]))
		st["town_smithy_refresh_day"] = w.day + _refresh_days("smithy")
	if w.day >= int(st.get("town_mercenary_refresh_day", w.day + 1)):
		_refresh_mercenaries(st, RngUtil.make([w.seed, "town_mercenaries", sid, w.day]))
		st["town_mercenary_refresh_day"] = w.day + _refresh_days("tavern")


func _refresh_smithy(st: Dictionary, rng: RandomNumberGenerator) -> void:
	var sid := int(st["id"])
	var level := maxi(1, int(st.get("level", 1)) + _reputation_bonus(int(st.get("relation", 0))))
	var luck := float(_reputation_bonus(int(st.get("relation", 0)))) * 0.3
	var count := maxi(1, int(_service_config("smithy").get("stock_count", 6)))
	var goods: Array = []
	for i in count:
		var category: String = SHOP_CATEGORIES[i % SHOP_CATEGORIES.size()]
		var item := ItemGen.generate(rng, {"category": category, "level": level, "luck": luck, "source": "shop"})
		if not item.is_empty():
			goods.append({"item": item})
	st["town_smithy_stock"] = goods
	st["town_smithy_stock_day"] = w.day
	st["town_smithy_refresh_day"] = w.day + _refresh_days("smithy")


func _refresh_mercenaries(st: Dictionary, rng: RandomNumberGenerator) -> void:
	var old_ids: Array = st.get("town_mercenary_ids", [])
	for id: Variant in old_ids.duplicate():
		var old := w.get_unit(int(id))
		if old:
			(st["units"] as Array).erase(int(id))
			w.remove_unit(old)
	st["town_mercenary_ids"] = []
	var services: Dictionary = config().get("services", {})
	var tavern: Dictionary = services.get("tavern", {})
	var configured := clampi(int(tavern.get("mercenary_count", 4)), 3, 4)
	var count := configured if _reputation_bonus(int(st.get("relation", 0))) > 0 else maxi(3, configured - 1)
	var level := maxi(1, int(st.get("level", 1)) + _reputation_bonus(int(st.get("relation", 0))))
	var center: Vector2 = (st.get("town_work_points", {}) as Dictionary).get("barkeep", Vector2(st["center"]))
	for _i in count:
		var candidate_level := maxi(1, level + rng.randi_range(-1, 1))
		var pos := _random_walkable(center, 3.5, rng)
		var u := CharacterFactory.make_person(w, {"role": "mercenary", "level": candidate_level},
			pos, str(st.get("faction", "townsfolk")), "colonist")
		u.home_site = int(st["id"])
		u.guard_pos = pos
		u.character["town_job"] = "barkeep"
		u.character["town_candidate"] = true
		# a candidate is a guest, not part of the town watch (hired, the colony sets their labour)
		u.labor = "worker"
		(st["units"] as Array).append(u.id)
		(st["town_mercenary_ids"] as Array).append(u.id)
	st["town_mercenary_stock_day"] = w.day
	st["town_mercenary_refresh_day"] = w.day + _refresh_days("tavern")


func _reputation_bonus(relation: int) -> int:
	if relation >= Diplomacy.ALLIED_AT:
		return 2
	if relation >= Diplomacy.FRIENDLY_AT:
		return 1
	return 0


func _record_trade(st: Dictionary, value: int) -> void:
	if int(st.get("town_trade_day", w.day)) != w.day:
		st["town_trade_day"] = w.day
		st["town_trade_gain_today"] = 0
	var gained := int(st.get("town_trade_gain_today", 0))
	var goodwill := mini(Diplomacy.DAILY_GOODWILL_CAP - gained, maxi(1, value / 20))
	if goodwill > 0:
		st["town_trade_gain_today"] = gained + goodwill
		w.diplomacy.change_relation(int(st["id"]), goodwill, "trade")
