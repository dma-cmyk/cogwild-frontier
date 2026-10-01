class_name SquadAI
extends RefCounted
## Carries out squad orders and delegated behaviour: direct orders (move, attack) and delegated
## ones (defend an area, explore a region and report back, patrol, escort, auto), with a
## retreat threshold. Also runs orders of individual units outside squads: drones exploring on
## their own, the airship's trade runs, villagers sent somewhere by hand.

const EXPLORE_RADIUS := 48.0
const AUTO_RADIUS := 80.0
const SLOT := 1.7

var w: World


func _init(world: World) -> void:
	w = world

func _set_state(s: Squad, state: String, params: Dictionary = {}) -> void:
	s.state = state
	s.state_message = {"key": "sim.squad.state." + state.replace(": ", ".").replace(" ", "_"), "params": params}


func members(s: Squad) -> Array:
	var out: Array = []
	for id: int in s.members:
		var u := w.get_unit(id)
		if u and u.alive and u.state != Unit.State.DOWNED:
			out.append(u)
	return out


func center(s: Squad) -> Vector2:
	var ms := members(s)
	if ms.is_empty():
		return w.home_pos()
	var c := Vector2.ZERO
	for u: Unit in ms:
		c += u.pos
	return c / ms.size()


func hp_ratio(s: Squad) -> float:
	var hp := 0.0
	var mx := 0.0
	for id: int in s.members:
		var u := w.get_unit(id)
		if u and u.alive:
			hp += u.hp if u.state != Unit.State.DOWNED else 0.0
			mx += float(u.stats.get("max_hp", 100.0))
	return hp / mx if mx > 0.0 else 0.0


## Rough fighting strength (hp × damage per second) used to judge fights.
static func unit_strength(u: Unit) -> float:
	if not u.alive or u.state == Unit.State.DOWNED or not u.is_armed():
		return 0.0
	var wpn: Dictionary = u.stats.get("weapon", Unit.FISTS)
	var dps := float(wpn.get("damage", 3.0)) * float(u.stats.get("damage_mult", 1.0)) / maxf(0.3, float(wpn.get("cooldown", 1.0)))
	return sqrt(maxf(1.0, u.hp) * dps)


func strength(s: Squad) -> float:
	var total := 0.0
	for u: Unit in members(s):
		total += unit_strength(u)
	return total


func _slot(i: int, s: Squad, u: Unit, threat: Vector2) -> Vector2:
	var forward := threat - center(s)
	if forward.length_squared() < 0.01:
		forward = Vector2(0, 1)
	forward = forward.normalized()
	var side := Vector2(forward.y, -forward.x)
	var weapon: Dictionary = u.stats.get("weapon", Unit.FISTS)
	var ranged := str(weapon.get("kind", "melee")) == "ranged"
	var role := str(u.character.get("role", "")) if u.is_person() else ""
	var row: int = 1 if ranged or role in ["medic", "scholar", "engineer"] else 0
	var col: int = i % 3 - 1
	match s.formation:
		"wedge":
			col = 0 if i == 0 else int((i + 1) / 2) * (1 if i % 2 == 1 else -1)
		"loose":
			row = maxi(row, int(i / 3))
			col = i % 3 - 1
	var depth := 1.7 * float(row)
	return side * float(col) * SLOT - forward * depth

# --- orders --------------------------------------------------------------------------------

func order_squad(s: Squad, order: Dictionary) -> void:
	s.order = order
	# scratch data of the order that just ended: a fresh order must not inherit its route, its
	# progress counters or the "we are stuck" tally of the march it replaces
	for key: String in ["corridor", "target", "patrol_i", "loot_site", "returning", "sub", "stuck", "last_c", "moving_to"]:
		s.mem.erase(key)
	if order.get("type", "") not in ["stairs", "retreat"]:
		s.mem.erase("delve_exit")
		s.mem.erase("delve_resume")
	if order.get("type", "") == "enter":
		_queue_corridor(center(s), order["pos"])
	if order.get("type", "") in ["explore", "auto"]:
		s.report.clear()
		s.mem["mapped0"] = _mapped(s)
	for u: Unit in members(s):
		w.combat.cancel_manual_ability(u)
		if order.get("type", "") != "attack":
			u.target_id = -1
		# Drop the route of the previous order. Delegated orders (defend, patrol, escort, ...)
		# only re-path once everybody stands still, so a stale walk made the command bar look
		# dead for as long as the old march lasted; the orders below re-path immediately.
		if u.moving:
			w.stop_unit(u)
	match str(order.get("type", "")):
		"move":
			_set_state(s, "moving")
			_move_all(s, order["pos"])
		"visit", "enter", "stairs":
			_set_state(s, "travelling")
			_move_all(s, order["pos"])
		"retreat":
			_set_state(s, "retreating")
			var loc := w.dungeons.squad_location(s)
			if loc.is_empty():
				_move_all(s, w.home_pos())
			else:
				_move_all(s, w.dungeons.stairs_order(int(loc["eid"]), int(loc["floor"]), "up")["pos"])
		"idle":
			_set_state(s, "holding")
			s.mem["hold"] = center(s)
	w.squads_changed.emit()


func order_unit(u: Unit, order: Dictionary) -> void:
	if u.squad_id >= 0:
		return
	w.colony.release(u)
	w.combat.cancel_manual_ability(u)
	u.order = order
	u.target_id = -1
	if u.moving:
		w.stop_unit(u)
	match str(order.get("type", "")):
		"move":
			w.move_unit(u, order["pos"])
		"attack":
			u.target_id = int(order.get("target", -1))


## Cancels the standing order: the squad holds the ground it stands on and forgets what it was
## told to resume after a retreat.
func cancel_order(s: Squad) -> void:
	if s == null:
		return
	s.mem.erase("resume")
	order_squad(s, {"type": "idle"})


func _move_all(s: Squad, p: Vector2) -> void:
	var ms := members(s)
	var goal_tile := Vector2i(int(floor(p.x)), int(floor(p.y)))
	var goal_crossing := w.crossing_building_at(goal_tile)
	var keep_slots_on_land := goal_crossing != null or _has_nearby_built_bridge(goal_tile)
	for i in ms.size():
		var u: Unit = ms[i]
		var dest := p + _slot(i, s, u, p)
		var t := Vector2i(int(floor(dest.x)), int(floor(dest.y)))
		var invalid_slot := not u.flying and not w.is_walkable(t)
		if not u.flying and keep_slots_on_land and Tiles.is_water(w.terrain_at(t)) \
				and w.gen.is_river_water(float(t.x) + 0.5, float(t.y) + 0.5) \
				and w.crossing_building_at(t) == null:
			invalid_slot = true
		if invalid_slot:
			dest = p
		w.move_unit(u, dest)


func _has_nearby_built_bridge(t: Vector2i) -> bool:
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			var crossing := w.crossing_building_at(t + Vector2i(dx, dz))
			if crossing != null and crossing.type == "bridge_segment" and crossing.is_built():
				return true
	return false

func _all_arrived(s: Squad) -> bool:
	for u: Unit in members(s):
		if u.moving:
			return false
	return true


## Members without a target pick visible enemies within radius of `anchor`. Returns true if fighting.
## A stance shapes what the squad picks up by itself; while an explicit attack order stands the
## leash is set aside, because the player already chose the fight.
func _engage(s: Squad, anchor: Vector2, radius: float) -> bool:
	var commanded := str(s.order.get("type", "")) == "attack"
	var leashed := s.stance == "hold" and not commanded
	var fighting := false
	for u: Unit in members(s):
		if not u.is_armed():
			continue
		if u.target_id >= 0:
			var current := w.get_unit(u.target_id)
			var keep := current != null and current.alive and current.pos.distance_to(anchor) < radius + 12.0
			if keep and leashed and current.pos.distance_to(Vector2(s.mem.get("hold", anchor))) > 6.0:
				keep = false
			if keep:
				fighting = true
				continue
			u.target_id = -1
			if u.moving:
				w.stop_unit(u)
		var enemy := w.combat.acquire(u, float(u.stats.get("vision", 9.0)) + 2.0)
		var engage_radius := radius + 4.0 if s.stance == "aggressive" else radius
		if leashed:
			engage_radius = minf(radius, 6.0)
		# self-defence: a member always answers an enemy that is attacking it or already in its
		# weapon reach, even when a straggler drags the squad anchor far behind the front
		var reach := float((u.stats.get("weapon", Unit.FISTS) as Dictionary).get("range", 1.3)) + 1.0
		var self_defence := enemy != null and (enemy.target_id == u.id or enemy.pos.distance_to(u.pos) <= reach)
		if enemy and (enemy.pos.distance_to(anchor) <= engage_radius or self_defence) \
				and not (s.stance == "cautious" and not commanded and str(enemy.order.get("type", "")) == "retreat"):
			u.target_id = enemy.id
			fighting = true
	return fighting


func _hold(s: Squad, p: Vector2, radius: float) -> bool:
	var fighting := _engage(s, p, radius)
	if fighting:
		return true
	var ms := members(s)
	for i in ms.size():
		var u: Unit = ms[i]
		if u.target_id >= 0 or u.moving:
			continue
		var slot := p + _slot(i, s, u, p)
		if u.pos.distance_to(slot) > 2.5:
			w.move_unit(u, slot)
	return false

func _clear_targets(s: Squad) -> void:
	for u: Unit in members(s):
		u.target_id = -1


# --- tick ----------------------------------------------------------------------------------

func tick() -> void:
	for s: Squad in w.squads:
		if (w.tick_count + s.id) % 5 == 0:
			_think(s)
	for u: Unit in w.unit_list:
		if u.alive and u.is_player() and u.squad_id < 0 and not u.order.is_empty() and (w.tick_count + u.id) % 5 == 0:
			_think_unit(u)


func _think(s: Squad) -> void:
	var ms := members(s)
	if ms.is_empty():
		_set_state(s, "down" if not s.members.is_empty() else "empty")
		return
	var otype := str(s.order.get("type", "idle"))
	var retreat_at := s.retreat_threshold
	match s.stance:
		"aggressive": retreat_at = minf(retreat_at, 0.2)
		"cautious": retreat_at = maxf(retreat_at, 0.45)
	if w.dungeons.enabled():
		var loc := w.dungeons.squad_location(s)
		if not loc.is_empty():
			_think_dungeon(s, loc, otype, retreat_at)
			return
	if otype != "retreat" and hp_ratio(s) < retreat_at:
		s.mem["resume"] = s.order.duplicate()
		order_squad(s, {"type": "retreat"})
		w.notify_key("sim.squad.retreating", {"squad_name": s.name}, "bad", center(s), {"squad": s.id})
		return
	match otype:
		"idle":
			_set_state(s, "fighting" if _hold(s, s.mem.get("hold", w.home_pos()), 14.0) else "holding")
		"move":
			if _all_arrived(s):
				s.mem["hold"] = s.order["pos"]
				s.order = {"type": "idle"}
				_set_state(s, "holding")
			else:
				_set_state(s, "moving")
		"attack":
			_think_attack(s)
		"defend":
			var p: Vector2 = s.order["pos"]
			_set_state(s, "fighting" if _hold(s, p, float(s.order.get("radius", 10.0)) + 6.0) else "defending")
		"explore":
			_think_explore(s, s.order.get("pos", w.home_pos()), float(s.order.get("radius", EXPLORE_RADIUS)))
		"patrol":
			_think_patrol(s)
		"escort":
			_think_escort(s)
		"retreat":
			_clear_targets(s)
			var home := w.home_pos()
			if _all_arrived(s) and center(s).distance_to(home) > 6.0:
				_move_all(s, home)
			_set_state(s, "retreating")
			if center(s).distance_to(home) < 8.0 and hp_ratio(s) >= 0.85:
				var resume: Dictionary = s.mem.get("resume", {"type": "idle"})
				s.mem.erase("resume")
				s.mem["hold"] = home
				order_squad(s, resume if resume.get("type", "") != "retreat" else {"type": "idle"})
		"visit":
			_think_visit(s)
		"enter":
			_think_enter(s)
		"stairs":
			_think_stairs(s)
		"auto":
			_think_auto(s)


## Walk to a community and stand in it. Arriving is what unlocks trading, gifts, quests and
## recruiting (Diplomacy.is_near_community), and it tells the HUD to open the trade window.
func _think_visit(s: Squad) -> void:
	var sid := int(s.order.get("site", -1))
	var st: Dictionary = w.sites.get(sid, {})
	if st.is_empty() or w.hostile("player", str(st.get("faction", ""))):
		order_squad(s, {"type": "idle"})
		return
	var anchor := Vector2(st["center"]) + Vector2(0.5, 0.5)
	if _engage(s, center(s), 8.0):
		_set_state(s, "fighting")
		return
	if center(s).distance_to(anchor) <= Diplomacy.TRADE_RANGE - 2.0:
		s.mem["hold"] = anchor
		s.order = {"type": "idle"}
		_set_state(s, "holding")
		w.notify_key("sim.village.arrived", {"squad_name": s.name, "village_name": str(st.get("name", ""))},
			"info", anchor, {"site": sid, "squad": s.id, "village_arrival": sid})
		return
	if _all_arrived(s) or not s.mem.has("moving_to") or (s.mem["moving_to"] as Vector2).distance_to(anchor) > 1.0:
		_move_all(s, anchor)
		s.mem["moving_to"] = anchor
	_set_state(s, "travelling")


## Walk to a dungeon gate and go down; the first member to arrive is enough (units shuffle in).
func _think_enter(s: Squad) -> void:
	var sid := int(s.order.get("site", -1))
	if not w.sites.has(sid):
		order_squad(s, {"type": "idle"})
		return
	_walk_through(s, s.order["pos"], func() -> void: w.dungeons.transfer_squad(s, sid, -1, "down"))


## Walk to stairs (or the way out) and use them.
func _think_stairs(s: Squad) -> void:
	var o := s.order
	var sid := int(o.get("site", -1))
	if not w.sites.has(sid) or not o.has("pos"):
		order_squad(s, {"type": "idle"})
		return
	_walk_through(s, o["pos"], func() -> void: w.dungeons.transfer_squad(s, sid, int(o["floor"]), str(o["dir"])))


func _walk_through(s: Squad, gate: Vector2, go: Callable) -> void:
	if bool(s.mem.get("delve_exit", false)):
		_clear_targets(s)
	elif _engage(s, center(s), 4.0):
		_set_state(s, "fighting")
		return
	for u: Unit in members(s):
		if u.pos.distance_to(gate) <= 2.4:
			go.call()
			return
	_chase_progress(s, gate)
	if str(s.order.get("type", "")) == "idle":
		return
	if _all_arrived(s) or not s.mem.has("moving_to") or (s.mem["moving_to"] as Vector2).distance_to(gate) > 1.0:
		_move_all(s, gate)
		s.mem["moving_to"] = gate
	_set_state(s, "travelling")


## A squad on a dungeon floor. The surface has nothing for it: retreating means climbing out, and
## explore / auto mean clearing the floor, taking the loot and going deeper.
func _think_dungeon(s: Squad, loc: Dictionary, otype: String, retreat_at: float) -> void:
	var eid := int(loc["eid"])
	var floor_index := int(loc["floor"])
	if otype == "retreat":
		s.mem["delve_exit"] = true
	elif not bool(s.mem.get("delve_exit", false)) and hp_ratio(s) < retreat_at:
		s.mem["delve_exit"] = true
		w.notify_key("sim.squad.retreating", {"squad_name": s.name}, "bad", center(s), {"squad": s.id})
	if bool(s.mem.get("delve_exit", false)):
		if otype != "stairs" or str(s.order.get("dir", "")) != "up":
			order_squad(s, w.dungeons.stairs_order(eid, floor_index, "up"))
		_think_stairs(s)
		return
	match otype:
		"stairs":
			_think_stairs(s)
		"attack":
			_think_attack(s)
		"move":
			if _all_arrived(s):
				s.mem["hold"] = s.order["pos"]
				s.order = {"type": "idle"}
				_set_state(s, "holding")
			else:
				_set_state(s, "moving")
		"explore", "auto":
			_think_delve_auto(s, eid, floor_index)
		"defend":
			var p: Vector2 = s.order["pos"]
			_set_state(s, "fighting" if _hold(s, p, float(s.order.get("radius", 10.0)) + 6.0) else "defending")
		_:
			_set_state(s, "fighting" if _hold(s, s.mem.get("hold", center(s)), 14.0) else "holding")


func _think_delve_auto(s: Squad, eid: int, floor_index: int) -> void:
	var c := center(s)
	if _engage(s, c, 14.0):
		_set_state(s, "fighting")
		return
	if _collect_loot(s, 20.0):
		_set_state(s, "looting")
		return
	var fst := w.dungeons.floor_site(eid, floor_index)
	if not fst.is_empty() and not bool(fst.get("cleared", false)):
		var best: Unit = null
		var best_d := INF
		for u: Unit in w.factions.site_units(int(fst["id"])):
			if not w.hostile("player", u.faction):
				continue
			var d := c.distance_to(u.pos)
			if d < best_d:
				best_d = d
				best = u
		if best != null:
			if _all_arrived(s) or not s.mem.has("moving_to") or (s.mem["moving_to"] as Vector2).distance_to(best.pos) > 6.0:
				_move_all(s, best.pos)
				s.mem["moving_to"] = best.pos
			_set_state(s, "delving")
			return
	var st: Dictionary = w.sites.get(eid, {})
	var last := floor_index >= int(st.get("floors", 1)) - 1
	if last:
		s.mem["delve_exit"] = true
		order_squad(s, w.dungeons.stairs_order(eid, floor_index, "up"))
	else:
		s.mem["delve_resume"] = s.order.duplicate()
		order_squad(s, w.dungeons.stairs_order(eid, floor_index, "down"))


func _think_attack(s: Squad) -> void:
	var o := s.order
	var anchor: Vector2 = o.get("pos", center(s))
	if o.has("target"):
		var t := w.get_unit(int(o["target"]))
		if t and t.alive and t.state != Unit.State.DOWNED:
			anchor = t.pos
			for u: Unit in members(s):
				if u.is_armed():
					if u.target_id < 0:
						u.target_id = t.id
				elif not u.moving and u.pos.distance_to(anchor) > 6.0:
					w.move_unit(u, anchor)  # drones and the airship follow instead of being left
			_set_state(s, "attacking")
			_chase_progress(s, anchor)
			return
		o.erase("target")
		o["pos"] = anchor
	if o.has("site"):
		var st: Dictionary = w.sites.get(int(o["site"]), {})
		if st.is_empty() or bool(st.get("cleared", false)):
			s.mem["hold"] = anchor
			order_squad(s, {"type": "idle"})
			s.mem["hold"] = anchor
			return
		anchor = Vector2(st["center"]) + Vector2(0.5, 0.5)
		# head for the nearest defender rather than the middle of the camp
		var best_d := INF
		for e: Unit in w.factions.site_units(int(o["site"])):
			if w.hostile("player", e.faction) and e.state != Unit.State.DOWNED:
				var d := e.pos.distance_squared_to(center(s))
				if d < best_d:
					best_d = d
					anchor = e.pos
	if _engage(s, center(s), 16.0):
		_set_state(s, "fighting")
		s.mem.erase("stuck")
		return
	if _collect_loot(s, 14.0):
		_set_state(s, "looting")
		return
	var c := center(s)
	if c.distance_to(anchor) > 3.5:
		if _all_arrived(s) or not s.mem.has("moving_to") or (s.mem["moving_to"] as Vector2).distance_to(anchor) > 1.0:
			# no progress over several thinks while standing still = no route to the target
			var last: Variant = s.mem.get("last_c")
			if w.pending_chunks() > 0:
				pass  # land is still being generated: the route may appear
			elif _all_arrived(s) and last is Vector2 and (last as Vector2).distance_to(c) < 1.0:
				s.mem["stuck"] = int(s.mem.get("stuck", 0)) + 1
			else:
				s.mem["stuck"] = 0
			s.mem["last_c"] = c
			if int(s.mem.get("stuck", 0)) >= 6 and not s.mem.has("corridor"):
				# Paths only cross generated land; the way around a river or cliff may lie in land
				# nobody has seen yet. Generate the area between the squad and its target, then retry.
				s.mem["corridor"] = true
				s.mem["stuck"] = 0
				_queue_corridor(c, anchor)
			elif int(s.mem.get("stuck", 0)) >= 6:
				w.notify_key("sim.squad.path_blocked", {"squad_name": s.name}, "info", c, {"squad": s.id})
				s.mem.erase("stuck")
				order_squad(s, {"type": "idle"})
				s.mem["hold"] = c
				return
			_move_all(s, anchor)
			s.mem["moving_to"] = anchor
		_set_state(s, "advancing")
	elif not o.has("site"):
		s.mem["hold"] = anchor
		order_squad(s, {"type": "idle"})
		s.mem["hold"] = anchor


## Hunting a named unit is driven by Combat: every armed member walks to its own target. When the
## terrain has no route there — the far bank of a river, the top of a cliff, land nobody generated
## yet — the whole squad stalls short of it and the order would hang forever with nothing to see.
## So the squad watches whether it is still closing in, and recovers exactly like an attack on a
## place does: generate the land in between once, then give up with a word to the player.
func _chase_progress(s: Squad, anchor: Vector2) -> void:
	var c := center(s)
	var last: Variant = s.mem.get("last_c")
	var moved: bool = not (last is Vector2) or (last as Vector2).distance_to(c) >= 0.5
	s.mem["last_c"] = c
	if c.distance_to(anchor) <= 6.0 or moved or w.pending_chunks() > 0 or _in_contact(s):
		s.mem["stuck"] = 0
		return
	s.mem["stuck"] = int(s.mem.get("stuck", 0)) + 1
	if int(s.mem["stuck"]) >= 8 and not s.mem.has("corridor"):
		s.mem["corridor"] = true
		s.mem["stuck"] = 0
		_queue_corridor(c, anchor)
	elif int(s.mem["stuck"]) >= 8:
		w.notify_key("sim.squad.path_blocked", {"squad_name": s.name}, "info", c, {"squad": s.id})
		s.mem.erase("stuck")
		order_squad(s, {"type": "idle"})
		s.mem["hold"] = c


func _in_contact(s: Squad) -> bool:
	for u: Unit in members(s):
		if u.state == Unit.State.FIGHT:
			return true
	return false


func _think_patrol(s: Squad) -> void:
	var pts: Array = s.order.get("points", [])
	if pts.size() < 2:
		var p: Vector2 = s.order.get("pos", center(s))
		pts = [w.home_pos(), p]
		s.order["points"] = pts
	if _engage(s, center(s), 14.0):
		_set_state(s, "fighting")
		return
	var i := int(s.mem.get("patrol_i", 1)) % pts.size()
	var target: Vector2 = pts[i]
	if center(s).distance_to(target) < 3.0 and _all_arrived(s):
		i = (i + 1) % pts.size()
		s.mem["patrol_i"] = i
		target = pts[i]
		_move_all(s, target)
	elif _all_arrived(s):
		_move_all(s, target)
	_set_state(s, "patrolling")


func _think_escort(s: Squad) -> void:
	var t := w.get_unit(int(s.order.get("target", -1)))
	if t == null or not t.alive:
		order_squad(s, {"type": "idle"})
		return
	if _engage(s, t.pos, 10.0):
		_set_state(s, "fighting")
		return
	if center(s).distance_to(t.pos) > 5.0 and (_all_arrived(s) or w.tick_count % 20 == 0):
		_move_all(s, t.pos + Vector2(1.5, 1.5))
	_set_state(s, "escorting")


func _collect_loot(s: Squad, radius: float) -> bool:
	var c := center(s)
	var bags: Array[Dictionary] = []
	for bag: Dictionary in w.loot_bags.values():
		if c.distance_to(bag["pos"]) < radius and w.dungeons.same_map(c, bag["pos"]):
			bags.append(bag)
	bags.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return c.distance_squared_to(a["pos"]) < c.distance_squared_to(b["pos"]))
	var ms := members(s)
	for bag: Dictionary in bags:
		var pos: Vector2 = bag["pos"]
		ms.sort_custom(func(a: Unit, b: Unit) -> bool:
			return a.pos.distance_squared_to(pos) < b.pos.distance_squared_to(pos))
		for picker: Unit in ms:
			if picker.is_static or picker.kind == "airship":
				continue
			if picker.pos.distance_to(pos) <= 1.6:
				w.pickup_loot(int(bag["id"]), picker)
				return true
			if picker.moving:
				if picker.goal.distance_to(pos) <= 1.6:
					return true
				continue
			if w.move_unit(picker, pos) and picker.goal.distance_to(pos) <= 1.6:
				return true
			w.stop_unit(picker)
	return false


## Explore: walk to the nearest unexplored ground inside the region, fight what is weak, loot
## what is found, avoid strong camps, and come home with a report when the region is known.
func _think_explore(s: Squad, region: Vector2, radius: float) -> void:
	var c := center(s)
	if _engage(s, c, 12.0):
		_set_state(s, "fighting")
		return
	if _collect_loot(s, 14.0):
		_set_state(s, "looting")
		return
	# open caches found on the way
	var cache := _nearest_cache(c, region, radius)
	if not cache.is_empty():
		var sc := Vector2(cache["center"]) + Vector2(0.5, 0.5)
		if c.distance_to(sc) < 3.5:
			w.factions.loot_site(int(cache["id"]), members(s)[0])
			s.report.append({"key": "sim.report.cache_looted", "params": {"site_name": cache.get("name", "")}})
		elif _all_arrived(s):
			_move_all(s, sc)
		_set_state(s, "investigating")
		return
	if s.mem.get("returning", false):
		if c.distance_to(w.home_pos()) < 8.0:
			_finish_expedition(s)
		elif _all_arrived(s):
			_move_all(s, w.home_pos())
		_set_state(s, "returning")
		return
	var target: Variant = s.mem.get("target")
	if target is Vector2i and not w.is_explored(target) and not _all_arrived(s):
		_set_state(s, "exploring")
		return
	var next := _pick_frontier(c, region, radius, strength(s))
	if next.x == -99999:
		s.mem["returning"] = true
		_move_all(s, w.home_pos())
		_set_state(s, "returning")
		return
	s.mem["target"] = next
	_move_all(s, Vector2(next) + Vector2(0.5, 0.5))
	_set_state(s, "exploring")


func _pick_frontier(from: Vector2, region: Vector2, radius: float, power: float) -> Vector2i:
	var search := clampf(from.distance_to(region) + radius, 16.0, radius * 2.0 + 10.0)
	var cands := w.frontier_near(from, search, 12)
	var checks := 0
	for t: Vector2i in cands:
		var tc := Vector2(t) + Vector2(0.5, 0.5)
		if tc.distance_to(region) > radius:
			continue
		if _dangerous(tc, power):
			continue
		if not w.is_walkable(t):
			var nt := w.nearest_walkable(t, 3)
			if nt.x == -99999:
				continue
		checks += 1
		if checks > 5:
			break
		var path := w.find_path(from, tc)
		if path.is_empty() or path[path.size() - 1].distance_to(tc) > 4.0:
			continue
		return t
	return Vector2i(-99999, -99999)


## Near a known hostile site that looks stronger than us?
func _dangerous(p: Vector2, power: float) -> bool:
	for st: Dictionary in w.sites.values():
		if not bool(st.get("hostile", false)) or bool(st.get("cleared", false)) or not bool(st.get("discovered", false)):
			continue
		var sc := Vector2(st["center"])
		if sc.distance_to(p) < 20.0 and w.factions.site_strength(int(st["id"])) > power * 1.1:
			return true
	return false


func _nearest_cache(from: Vector2, region: Vector2, radius: float) -> Dictionary:
	var best := {}
	var best_d := INF
	for st: Dictionary in w.sites.values():
		if not bool(st.get("discovered", false)) or bool(st.get("looted", false)) or (st.get("cache", []) as Array).is_empty():
			continue
		# a community's stash is not free loot: it is taken by subduing the place
		if w.diplomacy.is_community(st):
			continue
		if w.factions.site_guarded(int(st["id"])):
			continue
		var sc := Vector2(st["center"])
		if sc.distance_to(region) > radius + 10.0:
			continue
		var d := sc.distance_to(from)
		if d < best_d and d < 40.0:
			best_d = d
			best = st
	return best


func add_report(s: Squad, message: Variant) -> void:
	if s and not s.report.has(message):
		s.report.append(message)


func _mapped(s: Squad) -> int:
	var n := 0.0
	for id: int in s.members:
		var u := w.get_unit(id)
		if u:
			n += float(u.counters.get("tiles_explored", 0.0))
	return int(n)


func _finish_expedition(s: Squad) -> void:
	var mapped := _mapped(s) - int(s.mem.get("mapped0", _mapped(s)))
	s.mem["mapped0"] = _mapped(s)
	var entries: Array = s.report.slice(0, 6)
	if mapped > 0:
		entries.append({"key": "sim.report.tiles_mapped", "params": {"count": mapped}})
	if entries.is_empty():
		w.notify_key("sim.squad.expedition_empty", {"squad_name": s.name}, "discover", w.home_pos(), {"squad": s.id})
	else:
		w.notify_key("sim.squad.expedition_report", {"squad_name": s.name,
			"reports": {"list": entries, "separator": ", "}}, "discover", w.home_pos(), {"squad": s.id})
	s.report.clear()
	s.mem.erase("returning")
	s.mem.erase("target")
	if str(s.order.get("type", "")) == "explore":
		s.mem["hold"] = w.home_pos()
		order_squad(s, {"type": "idle"})
		s.mem["hold"] = w.home_pos()


func _think_auto(s: Squad) -> void:
	var home := w.home_pos()
	# 1. defend the settlement
	var threat: Unit = null
	for u: Unit in w.units_near(home, 32.0):
		if w.hostile("player", u.faction) and u.visible and u.is_armed():
			threat = u
			break
	if threat:
		s.mem["sub"] = "defend"
		_set_state(s, "auto: defending home")
		if not _engage(s, home, 34.0) and _all_arrived(s):
			_move_all(s, threat.pos)
		return
	# 2. heal up when hurt
	if hp_ratio(s) < 0.55:
		_set_state(s, "auto: resting")
		if center(s).distance_to(home) > 6.0 and _all_arrived(s):
			_move_all(s, home)
		return
	# 3. clear a weak known camp nearby
	var mine := strength(s)
	var sub := str(s.mem.get("sub", ""))
	var target_site := -1
	for st: Dictionary in w.sites.values():
		if bool(st.get("hostile", false)) and bool(st.get("discovered", false)) and not bool(st.get("cleared", false)):
			var sc := Vector2(st["center"])
			if sc.distance_to(home) < 110.0 and w.factions.site_strength(int(st["id"])) < mine * 0.75:
				target_site = int(st["id"])
				break
	if target_site >= 0:
		var st: Dictionary = w.sites[target_site]
		var anchor := Vector2(st["center"]) + Vector2(0.5, 0.5)
		s.mem["sub"] = "attack"
		_set_state(s, "auto: attacking", {"site_name": st.get("name", "")})
		if _engage(s, center(s), 16.0):
			return
		if center(s).distance_to(anchor) > 4.0 and _all_arrived(s):
			_move_all(s, anchor)
		return
	# 4. explore the frontier around home
	if sub != "patrol":
		s.mem["sub"] = "explore"
		_think_explore(s, home, AUTO_RADIUS + w.day * 8.0)
		if s.state == "returning" and s.mem.get("returning", false) and center(s).distance_to(home) < 8.0:
			s.mem["sub"] = "patrol"
		_set_state(s, "auto: " + str(s.state), s.state_message.get("params", {}))
		return
	# 5. patrol around home
	if _engage(s, center(s), 14.0):
		_set_state(s, "auto: fighting")
		return
	var ang := float(int(s.mem.get("patrol_i", 0))) * TAU / 6.0
	var p := home + Vector2(cos(ang), sin(ang)) * 22.0
	if _all_arrived(s):
		if center(s).distance_to(p) < 4.0:
			s.mem["patrol_i"] = int(s.mem.get("patrol_i", 0)) + 1
			if int(s.mem["patrol_i"]) % 6 == 0:
				s.mem["sub"] = "explore"
		else:
			_move_all(s, p)
	_set_state(s, "auto: patrolling")


# --- individual units ----------------------------------------------------------------------

func _think_unit(u: Unit) -> void:
	var o := u.order
	match str(o.get("type", "")):
		"move":
			if not u.moving:
				u.order = {}
		"attack":
			var t := w.get_unit(int(o.get("target", -1)))
			if t == null or not t.alive or t.state == Unit.State.DOWNED:
				u.order = {}
				u.target_id = -1
			else:
				u.target_id = t.id
		"defend", "hold":
			var p: Vector2 = o.get("pos", u.pos)
			if u.target_id < 0 and u.is_armed():
				var e := w.combat.acquire(u, float(u.stats.get("vision", 9.0)))
				if e and e.pos.distance_to(p) < 14.0:
					u.target_id = e.id
			if u.target_id < 0 and not u.moving and u.pos.distance_to(p) > 2.0:
				w.move_unit(u, p)
		"escort":
			var friend := w.get_unit(int(o.get("target", -1)))
			if friend == null or not friend.alive:
				u.order = {}
			elif not u.moving and u.pos.distance_to(friend.pos) > 5.0:
				w.move_unit(u, friend.pos + Vector2(1.5, 1.5))
		"retreat":
			# a lone unit has nothing to rally to but the hearth; once there it goes back to work
			if u.pos.distance_to(w.home_pos()) < 6.0:
				u.order = {}
			elif not u.moving:
				w.move_unit(u, w.home_pos())
		"gather":
			w.colony.force_gather(u, o["tile"])
			u.order = {}
		"explore":
			_unit_explore(u, o.get("pos", w.home_pos()), float(o.get("radius", EXPLORE_RADIUS * 1.5)))
		"patrol":
			var pts: Array = o.get("points", [w.home_pos(), o.get("pos", u.pos)])
			o["points"] = pts
			if u.target_id < 0 and u.is_armed():
				var e := w.combat.acquire(u, float(u.stats.get("vision", 9.0)))
				if e:
					u.target_id = e.id
			if not u.moving and u.target_id < 0:
				var i := (int(o.get("i", 0)) + 1) % pts.size()
				o["i"] = i
				w.move_unit(u, pts[i])
		"auto":
			if u.kind == "airship":
				_airship_auto(u)
			else:
				_unit_explore(u, w.home_pos(), AUTO_RADIUS * 1.6 + w.day * 10.0)
		"trade":
			_airship_trade(u)
		"dock":
			var dock := dock_pos()
			if u.pos.distance_to(dock) > 1.0 and not u.moving:
				w.move_unit(u, dock)
		"return":
			if not u.moving:
				if u.pos.distance_to(w.home_pos()) < 6.0:
					u.order = {"type": "dock"} if u.kind == "airship" else {}
				else:
					w.move_unit(u, dock_pos() if u.kind == "airship" else w.home_pos())


func _unit_explore(u: Unit, region: Vector2, radius: float) -> void:
	var o := u.order
	if bool(o.get("returning", false)):
		if not u.moving:
			if u.pos.distance_to(w.home_pos()) < 8.0 or u.pos.distance_to(dock_pos()) < 3.0:
				o.erase("returning")
				if str(o.get("type", "")) == "explore":
					u.order = {"type": "dock"} if u.kind == "airship" else {}
					w.notify_key("sim.squad.unit_explored", {"unit_name": u.name}, "discover", u.pos, {"unit": u.id})
				else:
					o["rest_until"] = w.tick_count + 600
			else:
				w.move_unit(u, dock_pos() if u.kind == "airship" else w.home_pos())
		return
	if int(o.get("rest_until", 0)) > w.tick_count:
		return
	var target: Variant = o.get("target")
	if target is Vector2i and not w.is_explored(target) and u.moving:
		return
	var next := Vector2i(-99999, -99999)
	var cands := w.frontier_near(u.pos, clampf(u.pos.distance_to(region) + radius, 20.0, radius * 2.0), 10)
	for t: Vector2i in cands:
		var tc := Vector2(t) + Vector2(0.5, 0.5)
		if tc.distance_to(region) > radius:
			continue
		if not u.flying:
			var path := w.find_path(u.pos, tc)
			if path.is_empty() or path[path.size() - 1].distance_to(tc) > 4.0:
				continue
		elif _dangerous(tc, 60.0 if u.kind == "airship" else 5.0):
			continue
		next = t
		break
	if next.x == -99999:
		o["returning"] = true
		w.move_unit(u, dock_pos() if u.kind == "airship" else w.home_pos())
		return
	o["target"] = next
	w.move_unit(u, Vector2(next) + Vector2(0.5, 0.5))


func dock_pos() -> Vector2:
	for b: Building in w.buildings.values():
		if b.type == "sky_dock" and b.is_built() and b.faction == "player":
			return b.center()
	return w.home_pos() + Vector2(6, -6)


func _airship_auto(u: Unit) -> void:
	var o := u.order
	var sub := str(o.get("sub", ""))
	if sub == "trade":
		_airship_trade(u)
		if str(o.get("phase", "")) == "done":
			o.erase("phase")
			o["sub"] = ""
		return
	if sub == "":
		var post := nearest_trade_post(u.pos)
		if post >= 0 and w.day > int(o.get("last_trade_day", 0)) and not w.factions.surplus().is_empty():
			o["sub"] = "trade"
			o["site"] = post
			o["phase"] = "out"
			o["last_trade_day"] = w.day
			return
		o["sub"] = "explore"
	if sub == "explore":
		_unit_explore(u, w.home_pos(), 150.0 + w.day * 10.0)
		if bool(o.get("returning", false)) == false and o.has("rest_until"):
			o["sub"] = ""


func nearest_trade_post(from: Vector2) -> int:
	var best := -1
	var best_d := INF
	for st: Dictionary in w.sites.values():
		if str(st.get("kind", "")) == "trade_post" and bool(st.get("discovered", false)):
			var d := Vector2(st["center"]).distance_to(from)
			if d < best_d:
				best_d = d
				best = int(st["id"])
	return best


## Airship trade run: fly to a trade post, sell surplus and buy food, fly back, report.
func _airship_trade(u: Unit) -> void:
	var o := u.order
	var sid := int(o.get("site", nearest_trade_post(u.pos)))
	if sid < 0 or not w.sites.has(sid):
		w.notify_key("sim.trade.no_post", {}, "info", u.pos)
		u.order = {"type": "dock"}
		return
	o["site"] = sid
	var st: Dictionary = w.sites[sid]
	var post := Vector2(st["center"]) + Vector2(0.5, 0.5)
	match str(o.get("phase", "out")):
		"out":
			o["phase"] = "flying"
			w.move_unit(u, post)
		"flying":
			if not u.moving:
				o["phase"] = "trading"
				o["t"] = 8.0
		"trading":
			o["t"] = float(o["t"]) - 0.5
			if float(o["t"]) <= 0.0:
				o["result"] = w.factions.trade(u)
				o["phase"] = "home"
				w.move_unit(u, dock_pos())
		"home":
			if not u.moving:
				var r: Dictionary = o.get("result", {})
				w.notify_key("sim.trade.run_returned", {"unit_name": u.name, "site_name": st.get("name", ""),
					"resources": r}, "good", u.pos, {"unit": u.id})
				if str(o.get("type", "")) == "trade":
					u.order = {"type": "dock"}
				else:
					o["phase"] = "done"


func on_machine_built(m: Unit) -> void:
	match m.archetype:
		"scout_drone":
			m.order = {"type": "auto"}
		"walker", "repair_drone":
			for s: Squad in w.squads:
				if s.members.size() < 6:
					w.assign_to_squad(m, s)
					return
			var s := w.create_squad()
			w.assign_to_squad(m, s)
			order_squad(s, {"type": "idle"})


## Individual direct orders may target zones for villagers.
func order_gather(u: Unit, tile: Vector2i) -> void:
	w.colony.release(u)
	u.order = {"type": "gather", "tile": tile}


## Queues generation of every chunk in the box spanning a and b (plus a margin of two chunks).
func _queue_corridor(a: Vector2, b: Vector2) -> void:
	var ka := w.chunk_key(Vector2i(a))
	var kb := w.chunk_key(Vector2i(b))
	for z in range(mini(ka.y, kb.y) - 2, maxi(ka.y, kb.y) + 3):
		for x in range(mini(ka.x, kb.x) - 2, maxi(ka.x, kb.x) + 3):
			w.queue_chunk(Vector2i(x, z))
