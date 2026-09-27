class_name FactionAI
extends RefCounted
## The rest of the world: points of interest come alive when their chunk is generated (guards,
## caches, merchants, wanderers), hostile camps guard, patrol, raid the settlement and grow over
## time, cleared camps may be reoccupied, merchant airships visit your dock. Sites far from the
## player are simulated abstractly (daily growth only) to keep the CPU cost low.

const ACTIVE_RANGE := 72.0
const LEASH := 24.0
const PLACE_KIND := {"ruins": "ruins", "bandit_camp": "bandit_camp", "machine_outpost": "machine_outpost",
	"trade_post": "trade_post", "wanderer_camp": "wanderer_camp", "wreck": "wreck", "crystal_grove": "crystal",
	"ore_field": "ore_field", "village": "settlement"}
const KIND_LABEL := {"ruins": "Ruins", "bandit_camp": "Bandit camp", "machine_outpost": "Machine outpost",
	"trade_post": "Trade post", "wanderer_camp": "Wanderer camp", "wreck": "Airship wreck", "crystal_grove": "Aether crystals",
	"ore_field": "Ore field", "village": "Village"}
const RESERVE := {"wood": 220, "stone": 160, "ore": 60, "metal": 80}
const PRICE := {"wood": 0.5, "stone": 0.5, "ore": 1.0, "metal": 2.5}

var w: World
var trader_day := 3
var trade_offers: Array = []  # items offered by a docked trader: {item, price}
var trader_id := -1
var _raid_announced: Dictionary = {}


func _init(world: World) -> void:
	w = world


# --- sites ---------------------------------------------------------------------------------

func instantiate_site(sid: int) -> void:
	if w.sites.has(sid) or not w.gen.sites.has(sid):
		return
	var g: Dictionary = w.gen.sites[sid]
	var rng := RngUtil.make([w.seed, "site", sid])
	var kind := str(g["kind"])
	var faction := str(g.get("faction", ""))
	var st := {
		"id": sid, "kind": kind, "center": g["center"], "name": NameGen.place(rng, PLACE_KIND.get(kind, "region")),
		"faction": faction, "hostile": faction in ["bandits", "machines"], "level": int(g["level"]),
		"discovered": false, "cleared": false, "looted": false, "units": [], "cache": [], "cache_gold": 0,
		"extra": [], "next_patrol": w.tick_count + rng.randi_range(600, 1500), "next_raid_day": 2 + rng.randi_range(0, 2),
		"cleared_day": 0, "icon": str(g.get("icon", "")),
	}
	if kind == "village":
		st["race"] = str(g.get("race", ""))
	w.sites[sid] = st
	if kind == "village":
		w.diplomacy.initialize(st, rng)
		w.diplomacy.populate(st, rng)
	var lv := int(g["level"])
	var c := Vector2(g["center"]) + Vector2(0.5, 0.5)
	match kind:
		"bandit_camp":
			for i in 2 + lv / 2:
				_spawn_guard(st, "bandit", c, rng)
			for i in 1 + lv / 3:
				_spawn_guard(st, "bandit_archer", c, rng)
			_spawn_guard(st, "bandit_captain", c, rng)
			st["cache"] = ItemGen.loot(rng, lv, 0.25, 2)
			st["cache_gold"] = rng.randi_range(20, 60)
		"machine_outpost":
			for i in 2 + lv / 2:
				_spawn_guard(st, "sentry", c, rng)
			for s: Dictionary in g.get("structures", []):
				if s["type"] == "machine_spire":
					var sp := Vector2(s["origin"]) + Vector2(s["size"]) * 0.5 + Vector2(0, 1.6)
					_spawn_guard(st, "turret", sp, rng, true)
			_spawn_guard(st, "war_drone", c, rng)
			_spawn_guard(st, "machine_warden", c, rng)
			st["cache"] = [ItemGen.generate(rng, {"level": lv, "luck": 0.4, "category": "robot_part", "source": "boss"}),
				ItemGen.generate(rng, {"level": lv, "luck": 0.4, "source": "boss"})]
			st["cache_gold"] = rng.randi_range(10, 40)
		"ruins":
			if lv >= 3:
				for i in 2:
					_spawn_guard(st, "sentry", c, rng)
			st["cache"] = ItemGen.loot(rng, lv, 0.35, rng.randi_range(2, 4))
			st["cache_gold"] = rng.randi_range(10, 45)
		"wreck":
			if lv >= 3:
				_spawn_guard(st, "war_drone", c, rng)
			var items: Array = [ItemGen.generate(rng, {"level": lv, "category": "airship_part", "luck": 0.2, "source": "loot"})]
			if rng.randf() < 0.6:
				items.append(ItemGen.generate(rng, {"level": lv, "category": "robot_part", "source": "loot"}))
			st["cache"] = items
			st["cache_gold"] = rng.randi_range(5, 25)
		"crystal_grove":
			if lv >= 2:
				for i in rng.randi_range(1, 2):
					_spawn_guard(st, "war_drone", c, rng)
		"trade_post":
			for i in 2:
				var u := CharacterFactory.make_npc(w, "merchant", "merchants", _spot_near(c, 4.0, rng), lv)
				u.home_site = sid
				u.guard_pos = u.pos
				(st["units"] as Array).append(u.id)
		"wanderer_camp":
			for i in rng.randi_range(1, 2):
				var u := CharacterFactory.make_npc(w, "wanderer", "wanderers", _spot_near(c, 3.0, rng), 1 + lv / 2)
				u.home_site = sid
				u.guard_pos = u.pos
				(st["units"] as Array).append(u.id)
	if (st["units"] as Array).is_empty() and st["hostile"]:
		st["cleared"] = true
	w.site_changed.emit(sid)


func _spot_near(c: Vector2, r: float, rng: RandomNumberGenerator) -> Vector2:
	for attempt in 12:
		var a := rng.randf() * TAU
		var p := c + Vector2(cos(a), sin(a)) * rng.randf_range(1.0, r)
		if w.is_walkable(Vector2i(int(floor(p.x)), int(floor(p.y)))):
			return p
	var t := w.nearest_walkable(Vector2i(int(floor(c.x)), int(floor(c.y))), 6)
	return Vector2(t) + Vector2(0.5, 0.5) if t.x != -99999 else c


func _spawn_guard(st: Dictionary, archetype: String, c: Vector2, rng: RandomNumberGenerator, exact: bool = false) -> Unit:
	var lv := int(st["level"])
	var faction := str(st["faction"])
	var p := c if exact else _spot_near(c, 5.5, rng)
	var u: Unit
	if DB.has_def("units", archetype):
		u = CharacterFactory.make_npc(w, archetype, faction, p, lv)
	else:
		u = CharacterFactory.make_machine(w, archetype, faction, p, lv)
		var d := u.DB_archetype()
		if d.has("named"):
			CharacterFactory.make_named(w, u, str(d["named"]), lv)
	u.home_site = int(st["id"])
	u.guard_pos = p
	u.visible = false
	(st["units"] as Array).append(u.id)
	return u


func site_units(sid: int) -> Array:
	var out: Array = []
	var st: Dictionary = w.sites.get(sid, {})
	for id: Variant in st.get("units", []):
		var u := w.get_unit(int(id))
		if u and u.alive:
			out.append(u)
	return out


func site_strength(sid: int) -> float:
	var total := 0.0
	for u: Unit in site_units(sid):
		if w.hostile("player", u.faction):
			total += SquadAI.unit_strength(u)
	return total


func site_guarded(sid: int) -> bool:
	var st: Dictionary = w.sites.get(sid, {})
	var c := Vector2(st.get("center", Vector2i.ZERO))
	for u: Unit in site_units(sid):
		if w.hostile("player", u.faction) and u.pos.distance_to(c) < 16.0:
			return true
	return false


func loot_site(sid: int, by: Unit) -> void:
	var st: Dictionary = w.sites.get(sid, {})
	if st.is_empty() or bool(st.get("looted", false)):
		return
	st["looted"] = true
	var c := Vector2(st["center"]) + Vector2(0.5, 0.5)
	var items: Array = st.get("cache", [])
	var bag := w.drop_loot(c + Vector2(0.3, 1.8), items, int(st.get("cache_gold", 0)))
	st["cache"] = []
	w.notify_key("sim.site.cache_opened", {"unit_name": by.name if by else "", "site_name": st["name"]}, "loot", c, {"site": sid})
	if not bag.is_empty() and by:
		w.pickup_loot(int(bag["id"]), by)
	w.site_changed.emit(sid)


func check_site_discovery(seers: Array) -> void:
	for st: Dictionary in w.sites.values():
		if bool(st["discovered"]):
			continue
		var c := Vector2(st["center"]) + Vector2(0.5, 0.5)
		for s: Array in seers:
			if (s[0] as Vector2).distance_to(c) <= float(s[1]) + 4.0:
				_discover(st, s[2])
				break


func _discover(st: Dictionary, by: Variant) -> void:
	st["discovered"] = true
	var who := ""
	if by is Unit:
		who = (by as Unit).name
		(by as Unit).counter_add("sites_found")
		if (by as Unit).squad_id >= 0:
			w.squad_ai.add_report(w.get_squad((by as Unit).squad_id), {"key": "sim.report.site_found", "params": {"site_name": st["name"]}})
	if str(st["kind"]) == "village":
		w.diplomacy.mark_discovered(st, who)
		w.site_changed.emit(int(st["id"]))
		return
	var params := {"site_kind_id": str(st["kind"]), "site_name": st["name"], "unit_name": who,
		"strength": int(site_strength(int(st["id"])))}
	var key := "sim.site.discovered"
	if bool(st["hostile"]) and not bool(st["cleared"]):
		key += ".hostile"
	if who != "":
		key += ".by_unit"
	w.notify_key(key, params, "discover", Vector2(st["center"]), {"site": st["id"]})
	w.site_changed.emit(int(st["id"]))


func on_unit_spotted(u: Unit) -> void:
	if str(u.order.get("type", "")) == "raid" and not _raid_announced.has(u.home_site):
		_raid_announced[u.home_site] = true
		w.notify_key("sim.raid.spotted", {}, "bad", u.pos)


func on_unit_killed(t: Unit, attacker: Unit) -> void:
	if t.home_site < 0 or not w.sites.has(t.home_site):
		return
	var st: Dictionary = w.sites[t.home_site]
	if str(st["kind"]) == "village":
		w.diplomacy.villager_killed(t.home_site, t, attacker)
		if not bool(st.get("hostile", false)) or bool(st.get("subdued", false)):
			w.site_changed.emit(t.home_site)
			return
		for u: Unit in site_units(t.home_site):
			if u.is_armed():
				w.site_changed.emit(t.home_site)
				return
		w.diplomacy.subdue(t.home_site, attacker)
		return
	if str(st["kind"]) == "bandit_camp" and str(t.order.get("type", "")) == "raid" \
			and attacker != null and attacker.is_player():
		w.diplomacy.bandit_raid_repelled(t.pos)
	if not bool(st["hostile"]) or bool(st["cleared"]):
		return
	for u: Unit in site_units(t.home_site):
		if w.hostile("player", u.faction):
			return
	st["cleared"] = true
	st["cleared_day"] = w.day
	w.counters["camps_cleared"] = int(w.counters.get("camps_cleared", 0)) + 1
	w.notify_key("sim.site.cleared", {"site_name": st["name"]}, "good", Vector2(st["center"]), {"site": st["id"]})
	if not bool(st["looted"]) and not (st["cache"] as Array).is_empty():
		var near: Unit = null
		for u: Unit in w.units_near(Vector2(st["center"]), 30.0):
			if u.is_player():
				near = u
				break
		if near:
			loot_site(int(st["id"]), near)
	w.site_changed.emit(int(st["id"]))

## A cleared camp is still a place: build nearby to keep it (reoccupation checks look for you).
func _player_presence(c: Vector2, r: float) -> bool:
	for u: Unit in w.units_near(c, r):
		if u.is_player():
			return true
	for b: Building in w.buildings.values():
		if b.faction == "player" and b.center().distance_to(c) < r:
			return true
	return false


# --- tick ----------------------------------------------------------------------------------

func tick() -> void:
	if w.tick_count % 5 != 1:
		return
	var active := {}
	var anchors: Array = []
	for u: Unit in w.unit_list:
		if u.is_player() and u.alive:
			anchors.append(u.pos)
	for b: Building in w.buildings.values():
		if b.faction == "player":
			anchors.append(b.center())
	var r2 := ACTIVE_RANGE * ACTIVE_RANGE
	for st: Dictionary in w.sites.values():
		var c := Vector2(st["center"])
		var on := false
		for a: Vector2 in anchors:
			if a.distance_squared_to(c) < r2:
				on = true
				break
		active[st["id"]] = on
	for u: Unit in w.unit_list:
		if not u.alive or u.is_player() or u.state == Unit.State.DOWNED:
			continue
		var o := str(u.order.get("type", ""))
		if o == "raid":
			_raider(u)
		elif o == "trader":
			_trader(u)
		elif u.home_site >= 0:
			if not bool(active.get(u.home_site, false)):
				u.lod = 2
				continue
			u.lod = 0
			var st: Dictionary = w.sites.get(u.home_site, {})
			if str(st.get("kind", "")) == "village":
				if bool(st.get("ruined", false)):
					continue
				if w.hostile("player", u.faction):
					if u.is_armed():
						_guard(u)
					else:
						_flee_villager(u)
				else:
					_village_routine(u, st)
			elif w.hostile("player", u.faction):
				_guard(u)
			elif u.faction == "wanderers":
				_wanderer(u)
	_patrols(active)


func _village_routine(u: Unit, st: Dictionary) -> void:
	if u.target_id >= 0:
		u.target_id = -1
	if w.is_night():
		if not u.moving and u.pos.distance_to(u.guard_pos) > 1.0:
			w.move_unit(u, u.guard_pos)
		return
	if u.moving or u.pos.distance_to(u.guard_pos) > 2.5:
		return
	if w.rng.randf() < 0.35:
		return
	var c := Vector2(st["center"]) + Vector2(0.5, 0.5)
	var angle := w.rng.randf() * TAU
	var target := c + Vector2(cos(angle), sin(angle)) * w.rng.randf_range(1.0, 4.0)
	var tile := w.nearest_walkable(Vector2i(int(floor(target.x)), int(floor(target.y))), 4)
	if tile.x != -99999:
		w.move_unit(u, Vector2(tile) + Vector2(0.5, 0.5))


func _flee_villager(u: Unit) -> void:
	if u.moving:
		return
	var nearest: Unit = null
	var nearest_distance := 13.0
	for other: Unit in w.units_near(u.pos, nearest_distance):
		if not other.is_player():
			continue
		var d := u.pos.distance_to(other.pos)
		if d < nearest_distance:
			nearest_distance = d
			nearest = other
	if nearest == null:
		return
	var direction := (u.pos - nearest.pos).normalized()
	if direction.length_squared() < 0.01:
		direction = Vector2.RIGHT
	w.move_unit(u, u.pos + direction * 8.0)


func _guard(u: Unit) -> void:
	if u.target_id >= 0:
		if u.pos.distance_to(u.guard_pos) > LEASH and not u.is_static:
			u.target_id = -1
			w.move_unit(u, u.guard_pos)
		return
	var e := w.combat.acquire(u, float(u.stats.get("vision", 9.0)))
	if e and e.pos.distance_to(u.guard_pos) < LEASH:
		u.target_id = e.id
		for o: Unit in w.units_near(u.pos, 12.0):
			if o.home_site == u.home_site and o.target_id < 0 and o.is_armed():
				o.target_id = e.id
		return
	if not u.moving and not u.is_static and u.pos.distance_to(u.guard_pos) > 2.5 and str(u.order.get("type", "")) != "patrol":
		w.move_unit(u, u.guard_pos)
	if str(u.order.get("type", "")) == "patrol" and not u.moving:
		var pts: Array = u.order.get("points", [])
		var i := int(u.order.get("i", 0)) + 1
		if i >= pts.size():
			u.order = {}
			w.move_unit(u, u.guard_pos)
		else:
			u.order["i"] = i
			w.move_unit(u, pts[i])


func _patrols(active: Dictionary) -> void:
	for st: Dictionary in w.sites.values():
		if not bool(st["hostile"]) or bool(st["cleared"]) or not bool(active.get(st["id"], false)):
			continue
		if w.tick_count < int(st["next_patrol"]):
			continue
		st["next_patrol"] = w.tick_count + 900 + w.rng.randi_range(0, 900)
		var c := Vector2(st["center"]) + Vector2(0.5, 0.5)
		var pts: Array = []
		var a0 := w.rng.randf() * TAU
		for k in 5:
			var a := a0 + k * TAU / 5.0
			var p := c + Vector2(cos(a), sin(a)) * 15.0
			var t := w.nearest_walkable(Vector2i(int(floor(p.x)), int(floor(p.y))), 4)
			if t.x != -99999:
				pts.append(Vector2(t) + Vector2(0.5, 0.5))
		if pts.size() < 3:
			continue
		var n := 0
		for u: Unit in site_units(int(st["id"])):
			if n >= 2 or u.is_static or not u.named.is_empty() or u.target_id >= 0:
				continue
			u.order = {"type": "patrol", "points": pts, "i": 0}
			w.move_unit(u, pts[0])
			n += 1


func _raider(u: Unit) -> void:
	var home := w.home_pos()
	var phase := str(u.order.get("phase", "march"))
	if u.target_id >= 0:
		return
	var e := w.combat.acquire(u, float(u.stats.get("vision", 9.0)) + 2.0)
	if e and phase != "flee":
		u.target_id = e.id
		return
	match phase:
		"march":
			if u.pos.distance_to(home) < 9.0:
				u.order["phase"] = "plunder"
				u.order["t"] = 6.0
			elif not u.moving:
				w.move_unit(u, home + Vector2(w.rng.randf_range(-4, 4), w.rng.randf_range(-4, 4)))
		"plunder":
			u.order["t"] = float(u.order["t"]) - 0.5
			if float(u.order["t"]) <= 0.0:
				var took := {}
				for r: String in ["food", "gold", "wood"]:
					var amount := mini(int(w.res.get(r, 0)), 6 + w.day * 2)
					if amount > 0:
						w.res[r] = int(w.res[r]) - amount
						took[r] = amount
				if not took.is_empty():
					w.notify_key("sim.raid.plundered", {"unit_name": u.name, "resources": took}, "bad", u.pos)
				u.order["phase"] = "flee"
				w.move_unit(u, u.guard_pos)
		"flee":
			if not u.moving:
				u.order = {}


func _trader(u: Unit) -> void:
	var o := u.order
	match str(o.get("phase", "arrive")):
		"arrive":
			if not u.moving:
				o["phase"] = "docked"
				o["t"] = 90.0
				_open_trade(u)
		"docked":
			o["t"] = float(o["t"]) - 0.5
			if float(o["t"]) <= 0.0:
				o["phase"] = "leave"
				trade_offers.clear()
				trader_id = -1
				w.notify_key("sim.trade.merchant_departed", {"unit_name": u.name}, "info", u.pos)
				w.move_unit(u, o["exit"])
		"leave":
			if not u.moving:
				u.alive = false
				u.state = Unit.State.DEAD
				u.downed_t = 5.9


func _wanderer(u: Unit) -> void:
	var st: Dictionary = w.sites.get(u.home_site, {})
	if st.is_empty() or not bool(st.get("discovered", false)):
		return
	for o: Unit in w.units_near(u.pos, 5.0):
		if o.is_player() and o.is_person():
			_recruit(u, st)
			return


func _recruit(u: Unit, st: Dictionary) -> void:
	(st["units"] as Array).erase(u.id)
	u.faction = "player"
	w.assign_art_variant(u, true)
	u.archetype = "colonist"
	u.labor = "worker"
	u.home_site = -1
	u.order = {}
	u.visible = true
	w.move_unit(u, w.home_pos())
	w.notify_key("sim.site.wanderer_joined", {"unit_name": u.name,
		"race": {"table": "races", "id": str(u.character.get("race", "")), "en": str(DB.get_def("races", str(u.character.get("race", ""))).get("name", ""))},
		"role": {"table": "roles", "id": str(u.character.get("role", "")), "en": u.display_role()}, "site_name": st["name"]}, "good", u.pos, {"unit": u.id})
	w.unit_changed.emit(u)


# --- days ----------------------------------------------------------------------------------

func on_new_day() -> void:
	w.diplomacy.on_new_day()
	var home := w.home_pos()
	for st: Dictionary in w.sites.values():
		var c := Vector2(st["center"]) + Vector2(0.5, 0.5)
		var kind := str(st["kind"])
		if kind == "village":
			if bool(st.get("hostile", false)) and not bool(st.get("subdued", false)) \
					and c.distance_to(home) < 170.0 and w.day >= int(st.get("next_raid_day", w.day + 1)):
				_launch_raid(st)
			continue
		if kind == "bandit_camp":
			if bool(st["cleared"]):
				if w.day - int(st["cleared_day"]) >= 6 and not _player_presence(c, 30.0):
					_reoccupy(st)
				continue
			if (w.day - 1) % 3 == 0 and w.day > 1:
				_grow_camp(st)
			if c.distance_to(home) < 170.0 and w.day >= int(st["next_raid_day"]):
				_launch_raid(st)
		elif kind == "machine_outpost" and not bool(st["cleared"]):
			var sentries := 0
			for u: Unit in site_units(int(st["id"])):
				if u.archetype == "sentry":
					sentries += 1
			if sentries < 3 + int(st["level"]) / 2:
				_spawn_guard(st, "sentry", c, w.rng)
				if bool(st["discovered"]):
					w.notify_key("sim.site.sentry_rebuilt", {"site_name": st["name"]}, "info", c, {"site": st["id"]})
	if w.day >= trader_day:
		trader_day = w.day + 2 + w.rng.randi_range(0, 1)
		_send_trader()


func _grow_camp(st: Dictionary) -> void:
	st["level"] = int(st["level"]) + 1
	var c := Vector2(st["center"]) + Vector2(0.5, 0.5)
	_spawn_guard(st, "bandit" if w.rng.randf() < 0.6 else "bandit_archer", c, w.rng)
	var a := w.rng.randf() * TAU
	var p := c + Vector2(cos(a), sin(a)) * 7.0
	var origin := Vector2i(int(floor(p.x)) - 1, int(floor(p.y)) - 1)
	if w.add_site_structure(int(st["id"]), "bandit_tent", origin, Vector2i(2, 2)):
		if bool(st["discovered"]):
			w.notify_key("sim.site.bandit_camp_grew", {"site_name": st["name"]}, "bad", c, {"site": st["id"]})


func _reoccupy(st: Dictionary) -> void:
	st["cleared"] = false
	st["looted"] = false
	var c := Vector2(st["center"]) + Vector2(0.5, 0.5)
	for i in 2 + int(st["level"]) / 2:
		_spawn_guard(st, "bandit", c, w.rng)
	_spawn_guard(st, "bandit_captain", c, w.rng)
	st["cache"] = ItemGen.loot(w.rng, int(st["level"]), 0.25, 2)
	st["cache_gold"] = w.rng.randi_range(20, 60)
	if bool(st["discovered"]):
		w.notify_key("sim.site.bandits_reoccupied", {"site_name": st["name"]}, "bad", c, {"site": st["id"]})
	w.site_changed.emit(int(st["id"]))


func _launch_raid(st: Dictionary) -> void:
	st["next_raid_day"] = w.day + 2 + w.rng.randi_range(0, 2)
	var avail: Array = []
	for u: Unit in site_units(int(st["id"])):
		if not u.is_static and u.named.is_empty() and u.target_id < 0 and u.is_armed():
			avail.append(u)
	var n := mini(avail.size() - 1, 1 + w.day / 3)
	if n <= 0:
		return
	_raid_announced.erase(int(st["id"]))
	for i in n:
		var u: Unit = avail[i]
		u.order = {"type": "raid", "phase": "march"}
		w.move_unit(u, w.home_pos())
	if bool(st["discovered"]):
		w.notify_key("sim.raid.launched", {"site_name": st["name"]}, "bad", Vector2(st["center"]), {"site": st["id"]})


func _send_trader() -> void:
	var dock: Building = null
	for b: Building in w.buildings.values():
		if b.type == "sky_dock" and b.is_built() and b.faction == "player":
			dock = b
	if dock == null or trader_id >= 0:
		return
	var from := Vector2.ZERO
	var best := INF
	for st: Dictionary in w.sites.values():
		if st["kind"] == "trade_post":
			var d := Vector2(st["center"]).distance_to(dock.center())
			if d < best:
				best = d
				from = Vector2(st["center"])
	if best == INF:
		var a := w.rng.randf() * TAU
		from = dock.center() + Vector2(cos(a), sin(a)) * 140.0
	var u := CharacterFactory.make_machine(w, "trader_airship", "merchants", from)
	u.order = {"type": "trader", "phase": "arrive", "exit": from}
	trader_id = u.id
	w.move_unit(u, dock.center() + Vector2(4.5, -4.5))
	w.notify_key("sim.trade.merchant_arriving", {"unit_name": u.name}, "info", from)


func _open_trade(u: Unit) -> void:
	trade_offers.clear()
	var rng := RngUtil.make([w.seed, "offers", w.day])
	for i in 4:
		var it := ItemGen.generate(rng, {"level": 1 + w.day / 3, "luck": 0.35, "source": "shop"})
		it["uid"] = w.new_id()
		trade_offers.append({"item": it, "price": maxi(5, int(float(it.get("value", 10)) * 1.25))})
	var result := trade(u)
	w.notify_key("sim.trade.merchant_docked", {"unit_name": u.name, "resources": result}, "good", u.pos, {"trader": u.id})


## Buys an offered item with gold. Returns "" or a reason.
func buy_offer(index: int) -> String:
	if index < 0 or index >= trade_offers.size():
		return "Gone"
	var o: Dictionary = trade_offers[index]
	if int(w.res.get("gold", 0)) < int(o["price"]):
		return "Not enough gold"
	w.res["gold"] = int(w.res["gold"]) - int(o["price"])
	w.armory.append(o["item"])
	trade_offers.remove_at(index)
	w.notify_key("sim.trade.item_bought", {"item": o["item"]}, "loot")
	return ""


func surplus() -> Dictionary:
	var out := {}
	for r: String in RESERVE:
		var extra := int(w.res.get(r, 0)) - int(RESERVE[r])
		if extra > 0:
			out[r] = extra
	return out


## Sells surplus goods (up to the ship's cargo) and buys food when stocks are low.
func trade(ship: Unit) -> Dictionary:
	var result := {}
	var cap := int(ship.stats.get("cargo", 80.0))
	var best_trader := 0.0
	for u: Unit in w.player_people():
		best_trader = maxf(best_trader, u.skill("trade"))
	var bonus := 1.0 + best_trader / 200.0
	var sur := surplus()
	var gold := 0.0
	for r: String in ["metal", "ore", "wood", "stone"]:
		if cap <= 0 or not sur.has(r):
			continue
		var n := mini(int(sur[r]) / 2, cap)
		cap -= n
		w.res[r] = int(w.res[r]) - n
		result[r] = -n
		gold += n * float(PRICE[r]) * bonus
	if gold > 0.0:
		w.economy.add("gold", int(gold))
		result["gold"] = int(gold)
	var pop := w.population()
	if int(w.res.get("food", 0)) < pop * 6:
		var want := mini(40, pop * 6 - int(w.res.get("food", 0)))
		var afford := int(float(w.res.get("gold", 0)) / 1.5)
		var n := mini(want, afford)
		if n > 0:
			w.res["gold"] = int(w.res["gold"]) - int(ceil(n * 1.5))
			w.economy.add("food", n)
			result["food"] = n
			result["gold"] = int(result.get("gold", 0)) - int(ceil(n * 1.5))
	return result
