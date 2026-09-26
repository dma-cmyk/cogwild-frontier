class_name ColonyAI
extends RefCounted
## Autonomous work for settlers and work bots. The player designates zones (logging, mining,
## forage, farm), places construction sites and sets priorities; idle workers pick the best job by
## priority, skill and distance, reserve it, and carry it out (gather → haul → deliver, till →
## plant → harvest, fetch → deliver → build, operate furnaces and workshops, rest at night).

const PRI_WEIGHT := [0.0, 0.5, 1.0, 2.0]
const REACH := 1.65

var w: World
var reserved: Dictionary = {}  # target key -> unit id
var _blacklist: Dictionary = {}  # target key -> tick until which it is skipped


func _init(world: World) -> void:
	w = world


func is_worker(u: Unit) -> bool:
	return u.alive and u.is_player() and u.labor == "worker" and u.squad_id < 0 and u.order.is_empty() \
		and u.state != Unit.State.DOWNED and u.kind != "airship"


## Drops the unit's job and reservations (carried goods stay with the unit).
func release(u: Unit) -> void:
	for k: Variant in reserved.keys():
		if reserved[k] == u.id:
			reserved.erase(k)
	for b: Building in w.buildings.values():
		b.workers.erase(u.id)
	if u.job.get("type", "") == "rest":
		u.hidden = false
	u.job = {}
	u.held = ""
	if u.state == Unit.State.WORK or u.state == Unit.State.REST:
		u.state = Unit.State.IDLE


func _finish(u: Unit) -> void:
	release(u)
	u.ai_cd = 0.3


# --- assignment ----------------------------------------------------------------------------

func tick() -> void:
	var assign := w.tick_count % 10 == 3
	var cands: Array = []
	var cands_built := false
	for u: Unit in w.unit_list:
		if not is_worker(u):
			continue
		_energy(u)
		if not u.job.is_empty():
			_run(u)
			continue
		if not assign:
			continue
		u.ai_cd -= 1.0
		if u.ai_cd > 0.0:
			continue
		if not cands_built:
			cands = _collect()
			cands_built = true
		_assign(u, cands)


func _energy(u: Unit) -> void:
	if not u.is_person():
		return
	var rate := 5.0
	match u.job.get("type", ""):
		"rest":
			rate = 30.0 * float(u.stats.get("energy_regen", 1.0))
		"gather", "build", "haul", "farm", "operate":
			rate = -3.0 if u.state == Unit.State.WORK else -1.5
	if w.hungry and rate > 0.0:
		rate *= 0.5
	u.energy = clampf(u.energy + rate * World.TICK / 60.0, 0.0, float(u.stats.get("energy_max", 100.0)))


func _flee_needed(u: Unit) -> bool:
	for e: Unit in w.units_near(u.pos, 9.0):
		if w.hostile(u.faction, e.faction) and e.is_armed():
			return true
	return false


func _assign(u: Unit, cands: Array) -> void:
	if _flee_needed(u):
		u.job = {"type": "flee"}
		w.move_unit(u, w.home_pos())
		return
	if u.carry_amount > 0:
		_start_deliver(u)
		return
	if u.is_person() and (w.is_night() or u.energy < 15.0):
		_start_rest(u)
		return
	var best: Dictionary = {}
	var best_score := 0.0
	for c: Dictionary in cands:
		if u.kind == "robot" and c["type"] in ["operate"]:
			continue
		var key: Variant = c["key"]
		var cap := int(c.get("cap", 1))
		if _taken(key) >= cap or int(_blacklist.get(_bkey(key, u), 0)) > w.tick_count:
			continue
		var d := u.pos.distance_to(c["pos"])
		var sk := 0.6 + u.skill(str(c.get("skill", ""))) / 100.0
		var score: float = float(c["base"]) * sk / (1.0 + d / 18.0)
		if score > best_score:
			best_score = score
			best = c
	if best.is_empty():
		_start_idle(u)
		return
	_reserve(best["key"], u)
	u.job = best.duplicate()
	u.job["phase"] = "go"
	u.job["fails"] = 0
	_go_to_job(u)


## Direct order: gather this node now (then continue with normal work).
func force_gather(u: Unit, t: Vector2i) -> void:
	var r := w.res_at(t)
	var info := Tiles.res_info(r)
	if r == Tiles.Res.NONE or str(info.get("job", "")) == "":
		return
	release(u)
	if reserved.has(t):
		var other := w.get_unit(int(reserved[t]))
		if other:
			release(other)
	reserved[t] = u.id
	u.job = {"type": "gather", "key": t, "tile": t, "pos": Vector2(t) + Vector2(0.5, 0.5), "base": 1.0,
		"skill": str(info["skill"]), "phase": "go", "fails": 0}
	_go_to_job(u)


func _bkey(key: Variant, u: Unit) -> String:
	return "%s|%d" % [str(key), u.id]


func _taken(key: Variant) -> int:
	if key is String:
		var n := 0
		for k: Variant in reserved:
			if k is Array and (k as Array)[0] == key:
				n += 1
		return n
	return 1 if reserved.has(key) else 0


func _reserve(key: Variant, u: Unit) -> void:
	if key is String and (key as String).begins_with("b"):
		reserved[[key, u.id]] = u.id
		var b: Building = w.buildings.get(int((key as String).split(":")[0].substr(1)))
		if b and not b.workers.has(u.id):
			b.workers.append(u.id)
	else:
		reserved[key] = u.id


func _collect() -> Array:
	var out: Array = []
	var pri := w.priorities
	# construction
	for b: Building in w.buildings.values():
		if b.faction != "player" or b.is_built():
			continue
		var p := b.center()
		if not b.needs.is_empty():
			if PRI_WEIGHT[int(pri.get("haul", 2))] > 0.0:
				out.append({"type": "haul", "key": "b%d:haul" % b.id, "cap": 2, "pos": p, "base": 1.25 * PRI_WEIGHT[int(pri.get("haul", 2))], "building": b.id, "skill": "construction"})
		elif PRI_WEIGHT[int(pri.get("build", 2))] > 0.0:
			out.append({"type": "build", "key": "b%d:build" % b.id, "cap": 3, "pos": p, "base": 1.35 * PRI_WEIGHT[int(pri.get("build", 2))], "building": b.id, "skill": "construction"})
	# production
	if PRI_WEIGHT[int(pri.get("operate", 2))] > 0.0:
		for b: Building in w.buildings.values():
			if b.faction != "player" or not b.is_built():
				continue
			if b.type == "smelter" and int(w.res.get("ore", 0)) >= 2:
				out.append({"type": "operate", "key": "b%d:op" % b.id, "cap": 1, "pos": b.center(), "base": 1.1 * PRI_WEIGHT[int(pri.get("operate", 2))], "building": b.id, "skill": "engineering"})
			elif b.type == "workshop" and not b.queue.is_empty():
				out.append({"type": "operate", "key": "b%d:op" % b.id, "cap": 1, "pos": b.center(), "base": 1.3 * PRI_WEIGHT[int(pri.get("operate", 2))], "building": b.id, "skill": "engineering"})
	# farming
	var fw: float = PRI_WEIGHT[int(pri.get("farm", 2))]
	if fw > 0.0:
		for t: Vector2i in w.farm:
			var f: Dictionary = w.farm[t]
			var st := int(f["stage"])
			if st == 2 or reserved.has(t):
				continue
			var action: String = ["till", "plant", "", "harvest"][st]
			out.append({"type": "farm", "key": t, "tile": t, "pos": Vector2(t) + Vector2(0.5, 0.5), "base": (1.3 if st == 3 else 1.0) * fw, "action": action, "skill": "farming"})
	# gathering in zones
	var gw: float = PRI_WEIGHT[int(pri.get("gather", 2))]
	if gw > 0.0:
		for z: Dictionary in w.zones:
			var zt: String = z["type"]
			if zt == "farm":
				continue
			var rect: Rect2i = z["rect"]
			for x in range(rect.position.x, rect.end.x):
				for zz in range(rect.position.y, rect.end.y):
					var t := Vector2i(x, zz)
					var r := w.res_at(t)
					if r == Tiles.Res.NONE or Tiles.zone_for(r) != zt or reserved.has(t) or w.res_amount_at(t) <= 0:
						continue
					var info := Tiles.res_info(r)
					out.append({"type": "gather", "key": t, "tile": t, "pos": Vector2(t) + Vector2(0.5, 0.5), "base": gw, "skill": str(info["skill"])})
	return out


# --- running jobs --------------------------------------------------------------------------

func _go_to_job(u: Unit) -> void:
	var dest := _job_dest(u)
	if dest.x < -9000.0 or not w.move_unit(u, dest):
		if u.pos.distance_to(dest) > REACH:
			_fail(u)


func _fail(u: Unit) -> void:
	_blacklist[_bkey(u.job.get("key", ""), u)] = w.tick_count + 300
	_finish(u)
	u.ai_cd = 1.0


## Walkable spot to stand for the current phase of the job.
func _job_dest(u: Unit) -> Vector2:
	var j := u.job
	match str(j.get("type", "")):
		"gather", "farm":
			var t: Vector2i = j["tile"]
			if w.is_walkable(t):
				return Vector2(t) + Vector2(0.5, 0.5)
			return _adjacent_spot(Rect2i(t, Vector2i.ONE), u.pos)
		"build", "operate":
			var b: Building = w.buildings.get(int(j["building"]))
			if b == null:
				return Vector2(-9999, -9999)
			if j["type"] == "operate":
				var door := b.door_tile()
				if w.is_walkable(door):
					return Vector2(door) + Vector2(0.5, 0.5)
			return _adjacent_spot(b.rect(), u.pos)
		"haul":
			var b: Building = w.buildings.get(int(j["building"]))
			if b == null:
				return Vector2(-9999, -9999)
			if j["phase"] == "go":
				return _storage_spot(u)
			return _adjacent_spot(b.rect(), u.pos)
	return u.pos


func _adjacent_spot(rect: Rect2i, from: Vector2) -> Vector2:
	var best := Vector2(-9999, -9999)
	var best_d := INF
	for x in range(rect.position.x - 1, rect.end.x + 1):
		for z in range(rect.position.y - 1, rect.end.y + 1):
			if rect.has_point(Vector2i(x, z)):
				continue
			var t := Vector2i(x, z)
			if not w.is_walkable(t):
				continue
			var c := Vector2(t) + Vector2(0.5, 0.5)
			var d := c.distance_squared_to(from)
			if d < best_d:
				best_d = d
				best = c
	return best


func _storage_spot(u: Unit) -> Vector2:
	var s := w.nearest_storage(u.pos)
	if s == null:
		return w.home_pos()
	var door := s.door_tile()
	if w.is_walkable(door):
		return Vector2(door) + Vector2(0.5, 0.5)
	return _adjacent_spot(s.rect(), u.pos)


func _near(u: Unit, p: Vector2, tol: float = REACH) -> bool:
	return not u.moving and u.pos.distance_to(p) <= tol


func _work_factor(u: Unit, skill_id: String, bonus_key: String) -> float:
	var f := (0.5 + u.skill(skill_id) / 60.0) * float(u.stats.get("work", 1.0)) * (1.0 + float(u.stats.get(bonus_key, 0.0)))
	if w.hungry:
		f *= 0.7
	if u.is_person() and u.energy < 10.0:
		f *= 0.7
	return maxf(0.15, f)


func _run(u: Unit) -> void:
	var j := u.job
	match str(j.get("type", "")):
		"gather":
			_run_gather(u)
		"farm":
			_run_farm(u)
		"haul":
			_run_haul(u)
		"build":
			_run_build(u)
		"operate":
			_run_operate(u)
		"deliver":
			if not u.moving:
				var s := w.nearest_storage(u.pos)
				if s and s.distance_to(u.pos) <= 2.2:
					_deposit(u)
					_finish(u)
				elif int(j.get("tries", 0)) < 3:
					j["tries"] = int(j.get("tries", 0)) + 1
					w.move_unit(u, _storage_spot(u))
				else:
					_deposit(u)
					_finish(u)
		"rest":
			_run_rest(u)
		"idle":
			j["t"] = float(j.get("t", 0.0)) - World.TICK
			if float(j["t"]) <= 0.0:
				_finish(u)
		"flee":
			if not u.moving:
				_finish(u)
				u.ai_cd = 2.0
		_:
			_finish(u)


func _run_gather(u: Unit) -> void:
	var j := u.job
	var t: Vector2i = j["tile"]
	var r := w.res_at(t)
	if r == Tiles.Res.NONE or w.res_amount_at(t) <= 0:
		_finish(u)
		return
	var info := Tiles.res_info(r)
	var centre := Vector2(t) + Vector2(0.5, 0.5)
	match str(j["phase"]):
		"go":
			if u.moving:
				return
			if u.pos.distance_to(centre) <= REACH:
				j["phase"] = "work"
				var dur := float(info["work"]) / _work_factor(u, str(info["skill"]), "gather")
				j["t"] = dur
				j["dur"] = dur
				u.state = Unit.State.WORK
				u.held = {"chop": "axe", "mine": "pickaxe", "forage": ""}.get(str(info["job"]), "")
				var d := centre - u.pos
				if d.length() > 0.01:
					u.facing = d.normalized()
			else:
				j["fails"] = int(j["fails"]) + 1
				if int(j["fails"]) > 2:
					_fail(u)
				else:
					_go_to_job(u)
		"work":
			j["t"] = float(j["t"]) - World.TICK
			var beat := int(float(j["t"]) / 1.1)
			if beat != int(j.get("beat", -1)):
				j["beat"] = beat
				var act: StringName = {"chop": &"work_chop", "mine": &"work_mine", "forage": &"work_farm"}.get(str(info["job"]), &"work_build")
				u.push_fx(act)
				w.emit_fx(&"chop_chips" if info["job"] == "chop" else (&"rock_chips" if info["job"] == "mine" else &"dust_puff"), centre, 0.8)
			if float(j["t"]) <= 0.0:
				var amount := w.res_amount_at(t)
				var take := mini(amount, maxi(1, int(u.stats.get("carry", 20.0))))
				var left := amount - take
				if Tiles.is_tree(r) and left <= 0:
					var ch := w.chunk_at_tile(t)
					ch.decor.append(["stump", t.x - ch.cx * World.S + 0.5, t.y - ch.cz * World.S + 0.5, w.rng.randf() * TAU, 1.0])
				if r == Tiles.Res.BERRY_BUSH and left <= 0:
					var ch := w.chunk_at_tile(t)
					ch.regrow[w._li(t)] = [r, w.day + int(info.get("regrow", 2))]
				w.set_res(t, r if left > 0 else Tiles.Res.NONE, left)
				u.carry_res = str(info["yield"])
				u.carry_amount = take
				var key: String = {"chop": "chopped", "mine": "mined", "forage": "harvested"}.get(str(info["job"]), "gathered")
				u.counter_add(key, take)
				gain_xp(u, str(info["skill"]), 22.0)
				u.state = Unit.State.MOVE
				u.held = ""
				release_key_only(u)
				_start_deliver(u)


## Clears reservations but keeps the current job dictionary (used when switching to delivery).
func release_key_only(u: Unit) -> void:
	for k: Variant in reserved.keys():
		if reserved[k] == u.id:
			reserved.erase(k)


func _start_deliver(u: Unit) -> void:
	u.job = {"type": "deliver", "tries": 0}
	w.move_unit(u, _storage_spot(u))


func _deposit(u: Unit) -> void:
	if u.carry_amount > 0 and u.carry_res != "":
		w.economy.add(u.carry_res, u.carry_amount)
		w.counters[u.carry_res + "_gathered"] = int(w.counters.get(u.carry_res + "_gathered", 0)) + u.carry_amount
	u.carry_amount = 0
	u.carry_res = ""


func _run_farm(u: Unit) -> void:
	var j := u.job
	var t: Vector2i = j["tile"]
	if not w.farm.has(t):
		_finish(u)
		return
	var f: Dictionary = w.farm[t]
	var centre := Vector2(t) + Vector2(0.5, 0.5)
	var action := str(j["action"])
	match str(j["phase"]):
		"go":
			if u.moving:
				return
			if u.pos.distance_to(centre) <= REACH:
				var base := {"till": 3.5, "plant": 2.5, "harvest": 3.0}.get(action, 3.0) as float
				j["t"] = base / _work_factor(u, "farming", "farm")
				j["phase"] = "work"
				u.state = Unit.State.WORK
				u.held = "hoe" if action != "harvest" else ""
			else:
				j["fails"] = int(j["fails"]) + 1
				if int(j["fails"]) > 2:
					_fail(u)
				else:
					_go_to_job(u)
		"work":
			j["t"] = float(j["t"]) - World.TICK
			var beat := int(float(j["t"]) / 1.0)
			if beat != int(j.get("beat", -1)):
				j["beat"] = beat
				u.push_fx(&"work_farm")
				w.emit_fx(&"dust_puff", centre, 0.2)
			if float(j["t"]) > 0.0:
				return
			match action:
				"till":
					f["stage"] = 1
					if w.terrain_at(t) != Tiles.FARMLAND:
						w.set_terrain(t, Tiles.FARMLAND)
				"plant":
					f["stage"] = 2
					f["growth"] = 0.0
				"harvest":
					f["stage"] = 1
					f["growth"] = 0.0
					var amount := 4 if str(f.get("crop", "wheat")) == "veg" else 3
					amount += int(u.skill("farming") / 40.0)
					u.carry_res = "food"
					u.carry_amount = amount
					u.counter_add("harvested", amount)
			w.farm_changed.emit(t)
			gain_xp(u, "farming", 14.0)
			u.state = Unit.State.IDLE
			u.held = ""
			if u.carry_amount > 0:
				release_key_only(u)
				_start_deliver(u)
			else:
				_finish(u)


func _run_haul(u: Unit) -> void:
	var j := u.job
	var b: Building = w.buildings.get(int(j["building"]))
	if b == null or b.is_built():
		_finish(u)
		return
	match str(j["phase"]):
		"go":
			if u.moving:
				return
			var s := w.nearest_storage(u.pos)
			if s == null or s.distance_to(u.pos) > 2.4:
				j["fails"] = int(j["fails"]) + 1
				if int(j["fails"]) > 2:
					_fail(u)
				else:
					w.move_unit(u, _storage_spot(u))
				return
			if b.needs.is_empty():
				_finish(u)
				return
			var rk: String = b.needs.keys()[0]
			var cap := maxi(4, int(u.stats.get("carry", 20.0)))
			var take := mini(int(b.needs[rk]), cap)
			b.needs[rk] = int(b.needs[rk]) - take
			if int(b.needs[rk]) <= 0:
				b.needs.erase(rk)
			u.carry_res = rk
			u.carry_amount = take
			j["phase"] = "deliver"
			j["res"] = rk
			var dest := _adjacent_spot(b.rect(), u.pos)
			if not w.move_unit(u, dest) and u.pos.distance_to(dest) > REACH:
				_return_goods(u, b)
				_fail(u)
		"deliver":
			if u.moving:
				return
			if b.distance_to(u.pos) <= 2.0:
				b.delivered[u.carry_res] = int(b.delivered.get(u.carry_res, 0)) + u.carry_amount
				u.carry_amount = 0
				u.carry_res = ""
				gain_xp(u, "construction", 6.0)
				w.building_changed.emit(b)
				_finish(u)
			else:
				j["fails"] = int(j["fails"]) + 1
				if int(j["fails"]) > 2:
					_return_goods(u, b)
					_fail(u)
				else:
					w.move_unit(u, _adjacent_spot(b.rect(), u.pos))


func _return_goods(u: Unit, b: Building) -> void:
	if u.carry_amount > 0:
		b.needs[u.carry_res] = int(b.needs.get(u.carry_res, 0)) + u.carry_amount
		u.carry_amount = 0
		u.carry_res = ""


func _run_build(u: Unit) -> void:
	var j := u.job
	var b: Building = w.buildings.get(int(j["building"]))
	if b == null or b.is_built() or not b.needs.is_empty():
		_finish(u)
		return
	match str(j["phase"]):
		"go":
			if u.moving:
				return
			if b.distance_to(u.pos) <= 2.0:
				j["phase"] = "work"
				u.state = Unit.State.WORK
				u.held = "hammer"
				var d := b.center() - u.pos
				if d.length() > 0.01:
					u.facing = d.normalized()
			else:
				j["fails"] = int(j["fails"]) + 1
				if int(j["fails"]) > 2:
					_fail(u)
				else:
					_go_to_job(u)
		"work":
			var work := float(b.def().get("work", 60.0))
			b.progress = minf(1.0, b.progress + World.TICK * _work_factor(u, "construction", "build") / work)
			b.active_t = 0.5
			var beat := int(w.tick_count / 11)
			if beat != int(j.get("beat", -1)):
				j["beat"] = beat
				u.push_fx(&"work_build")
				if w.rng.randf() < 0.4:
					w.emit_fx(&"build_dust", b.center(), 0.4)
				gain_xp(u, "construction", 4.0)
			if int(w.tick_count) % 10 == 0:
				w.building_changed.emit(b)
			if b.is_built():
				_complete(b, u)
				_finish(u)


func _complete(b: Building, by: Unit) -> void:
	b.progress = 1.0
	b.hp = b.max_hp()
	b.needs.clear()
	b.delivered.clear()
	w.counters["built"] = int(w.counters.get("built", 0)) + 1
	for wid: int in b.workers:
		var wu := w.get_unit(wid)
		if wu:
			wu.counter_add("built")
			wu.push_fx(&"cheer")
	b.workers.clear()
	w.building_changed.emit(b)
	w.emit_fx(&"build_dust", b.center(), 0.3)
	w.notify("%s completed." % b.display_name(), "good", b.center(), {"building": b.id})
	_check_titles(by)


func _run_operate(u: Unit) -> void:
	var j := u.job
	var b: Building = w.buildings.get(int(j["building"]))
	if b == null:
		_finish(u)
		return
	match str(j["phase"]):
		"go":
			if u.moving:
				return
			if b.distance_to(u.pos) <= 2.2:
				j["phase"] = "work"
				u.state = Unit.State.WORK
				u.held = "hammer" if b.type == "smelter" else "wrench"
			else:
				j["fails"] = int(j["fails"]) + 1
				if int(j["fails"]) > 2:
					_fail(u)
				else:
					_go_to_job(u)
		"work":
			if w.is_night() and u.is_person():
				_finish(u)
				return
			var f := _work_factor(u, "engineering", "work")
			if b.type == "smelter":
				var recipe: Dictionary = b.def().get("recipe", {})
				if int(w.res.get("ore", 0)) < 2:
					b.active = false
					_finish(u)
					return
				b.active = true
				b.active_t = 1.0
				b.recipe_t += World.TICK * f
				if int(w.tick_count) % 12 == 0:
					u.push_fx(&"work_build")
				if b.recipe_t >= float(recipe.get("time", 8.0)):
					b.recipe_t = 0.0
					for k: String in recipe.get("in", {}):
						w.res[k] = int(w.res.get(k, 0)) - int(recipe["in"][k])
					for k: String in recipe.get("out", {}):
						w.economy.add(k, int(recipe["out"][k]))
					w.emit_fx(&"smoke_puff", b.center(), 3.5)
					gain_xp(u, "engineering", 10.0)
			elif b.type == "workshop":
				if b.queue.is_empty():
					b.active = false
					_finish(u)
					return
				b.active = true
				b.active_t = 1.0
				var arch := str(b.queue[0])
				var ad := _archetype(arch)
				b.prod_t += World.TICK * f
				if int(w.tick_count) % 12 == 0:
					u.push_fx(&"work_build")
				if b.prod_t >= float(ad.get("build_time", 60.0)):
					b.prod_t = 0.0
					b.queue.pop_front()
					var door := Vector2(b.door_tile()) + Vector2(0.5, 0.5)
					var m := CharacterFactory.make_machine(w, arch, "player", door)
					w.emit_fx(&"level_up", door, 0.5, Color("#8fd8ff"))
					w.notify("%s rolled out of the workshop: %s." % [str(ad.get("name", arch)), m.name], "good", door, {"unit": m.id})
					gain_xp(u, "engineering", 30.0)
					w.building_changed.emit(b)
					w.squad_ai.on_machine_built(m)
			else:
				_finish(u)


func _archetype(id: String) -> Dictionary:
	for table: String in ["robots", "airships", "units"]:
		if DB.has_def(table, id):
			return DB.get_def(table, id)
	return {}


func _start_rest(u: Unit) -> void:
	var bed: Building = null
	var best_d := INF
	for b: Building in w.buildings.values():
		if b.faction != "player" or not b.is_built() or int(b.def().get("housing", 0)) <= 0:
			continue
		var used := 0
		for o: Unit in w.unit_list:
			if o.job.get("type", "") == "rest" and int(o.job.get("bed", -1)) == b.id:
				used += 1
		if used >= int(b.def().get("housing", 0)):
			continue
		var d := b.distance_to(u.pos)
		if d < best_d:
			best_d = d
			bed = b
	u.job = {"type": "rest", "phase": "go", "bed": bed.id if bed else -1}
	if bed:
		w.move_unit(u, _adjacent_spot(bed.rect(), u.pos))
	else:
		var ang := float(u.id % 12) / 12.0 * TAU
		w.move_unit(u, w.home_pos() + Vector2(cos(ang), sin(ang)) * 3.0)


func _run_rest(u: Unit) -> void:
	var j := u.job
	if str(j["phase"]) == "go":
		if u.moving:
			return
		j["phase"] = "sleep"
		u.state = Unit.State.REST
		var b: Building = w.buildings.get(int(j.get("bed", -1)))
		if b and b.distance_to(u.pos) < 2.5:
			u.hidden = true
		return
	if not w.is_night() and u.energy >= 70.0:
		u.hidden = false
		_finish(u)


func _start_idle(u: Unit) -> void:
	u.job = {"type": "idle", "t": 4.0 + float(u.id % 5)}
	var home := w.home_pos()
	if u.pos.distance_to(home) > 16.0:
		w.move_unit(u, home + Vector2(w.rng.randf_range(-5, 5), w.rng.randf_range(-3, 5)))
	elif w.rng.randf() < 0.5:
		var p := u.pos + Vector2(w.rng.randf_range(-3, 3), w.rng.randf_range(-3, 3))
		var t := Vector2i(int(floor(p.x)), int(floor(p.y)))
		if w.is_walkable(t):
			w.move_unit(u, p)


# --- growth --------------------------------------------------------------------------------

## Adds experience to a skill (people only). Levels skills and the character; awards titles.
func gain_xp(u: Unit, skill_id: String, amount: float) -> void:
	if not u.is_person() or skill_id == "":
		return
	var c := u.character
	var apt := float((c.get("aptitude", {}) as Dictionary).get(skill_id, 1.0))
	var gain := amount * apt * float(u.stats.get("xp_rate", 1.0))
	var prog: Dictionary = c.get_or_add("skill_xp", {})
	var skills: Dictionary = c.get_or_add("skills", {})
	prog[skill_id] = float(prog.get(skill_id, 0.0)) + gain
	var cur := int(skills.get(skill_id, 0))
	var cost := 60.0 + cur * 2.5
	while float(prog[skill_id]) >= cost and cur < 100:
		prog[skill_id] = float(prog[skill_id]) - cost
		cur += 1
		skills[skill_id] = cur
		cost = 60.0 + cur * 2.5
		if skill_id == "scouting":
			u.recompute_stats()
		if cur % 10 == 0 and cur >= 30:
			var sname := str(DB.get_def("skills", skill_id).get("name", skill_id.capitalize()))
			w.notify("%s's %s reached %d." % [u.name, sname, cur], "info", u.pos, {"unit": u.id})
	c["xp"] = float(c.get("xp", 0.0)) + gain
	var new_level := 1 + int(sqrt(float(c["xp"]) / 80.0))
	if new_level > int(c.get("level", 1)):
		c["level"] = new_level
		u.recompute_stats()
		u.hp = float(u.stats["max_hp"])
		u.push_fx(&"levelup")
		w.emit_fx(&"level_up", u.pos, 0.2, Color("#ffd86b"))
		w.notify("%s reached level %d!" % [u.name, new_level], "levelup", u.pos, {"unit": u.id})
	_check_titles(u)


func _check_titles(u: Unit) -> void:
	if u == null or not u.is_person():
		return
	var doc: Variant = DB.raw("generation/titles")
	if not (doc is Dictionary):
		return
	var titles: Array = u.character.get_or_add("titles", [])
	for t: Dictionary in doc.get("titles", []):
		var name_: String = str(t.get("name", ""))
		if name_ == "" or titles.has(name_):
			continue
		if float(u.counters.get(str(t.get("stat", "")), 0.0)) >= float(t.get("min", 1)):
			titles.append(name_)
			w.notify("%s earned the title \"%s\"." % [u.name, name_], "levelup", u.pos, {"unit": u.id})


func check_titles(u: Unit) -> void:
	_check_titles(u)


func on_new_day() -> void:
	# berry bushes regrow
	for key: Vector2i in w.chunks:
		var ch: ChunkData = w.chunks[key]
		if ch.regrow.is_empty():
			continue
		for i: int in ch.regrow.keys():
			var v: Array = ch.regrow[i]
			if w.day >= int(v[1]):
				ch.regrow.erase(i)
				var t := ch.origin() + Vector2i(i % World.S, i / World.S)
				var am: Array = Tiles.res_info(int(v[0])).get("amount", [4, 4])
				w.set_res(t, int(v[0]), int(am[1]))
	var expired: Array = []
	for k: Variant in _blacklist:
		if int(_blacklist[k]) < w.tick_count:
			expired.append(k)
	for k: Variant in expired:
		_blacklist.erase(k)
