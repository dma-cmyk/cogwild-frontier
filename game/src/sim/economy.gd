class_name Economy
extends RefCounted
## Colony resources, energy balance, food and population growth, and per-minute rates for the HUD.

const ENERGY_CAP := 600.0

var w: World
var _snapshots: Array = []  # [{tick, res}] every 10 s of game time, last 7 kept (60 s window)
var _energy_frac := 0.0


func _init(world: World) -> void:
	w = world


func add(r: String, amount: int) -> void:
	if amount == 0:
		return
	w.res[r] = maxi(0, int(w.res.get(r, 0)) + amount)
	if r == "energy":
		w.res[r] = mini(int(w.res[r]), int(ENERGY_CAP))


func can_afford(cost: Dictionary) -> bool:
	for k: String in cost:
		if int(w.res.get(k, 0)) < int(cost[k]):
			return false
	return true


func pay(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for k: String in cost:
		w.res[k] = int(w.res.get(k, 0)) - int(cost[k])
	return true


## Net change per minute over the last 60 s of game time.
func rates() -> Dictionary:
	var out := {}
	if _snapshots.is_empty():
		return out
	var first: Dictionary = _snapshots[0]
	var span := float(w.tick_count - int(first["tick"])) * World.TICK
	if span < 5.0:
		return out
	for r: String in World.RESOURCES:
		out[r] = (float(w.res.get(r, 0)) - float(first["res"].get(r, 0))) / span * 60.0
	return out


func tick() -> void:
	if w.tick_count % 10 == 0:
		_energy_step(1.0)
		_grow_farms(1.0)
	if w.tick_count % 100 == 0:
		_snapshots.append({"tick": w.tick_count, "res": w.res.duplicate()})
		while _snapshots.size() > 7:
			_snapshots.pop_front()


func energy_balance_per_min() -> float:
	var prod := 0.0
	for b: Building in w.buildings.values():
		if b.faction == "player" and b.is_built():
			prod += float(b.def().get("energy_per_min", 0.0))
	var use := 0.0
	for u: Unit in w.unit_list:
		if u.alive and u.is_player() and u.is_machine():
			use += float(u.DB_archetype().get("energy_use", 0.0))
	return prod - use


func _energy_step(seconds: float) -> void:
	_energy_frac += energy_balance_per_min() * seconds / 60.0
	var whole := int(_energy_frac) if _energy_frac >= 0.0 else -int(ceil(-_energy_frac))
	if whole != 0:
		_energy_frac -= whole
		add("energy", whole)
	for b: Building in w.buildings.values():
		if b.type == "windmill" and b.is_built():
			b.active = true


func _grow_farms(seconds: float) -> void:
	var grow_days := 1.1
	for t: Vector2i in w.farm:
		var f: Dictionary = w.farm[t]
		if int(f["stage"]) != 2:
			continue
		var before := int(float(f["growth"]) * 3.0)
		f["growth"] = float(f["growth"]) + seconds / (World.DAY_TICKS * World.TICK * grow_days)
		if float(f["growth"]) >= 1.0:
			f["growth"] = 1.0
			f["stage"] = 3
			w.farm_changed.emit(t)
		elif int(float(f["growth"]) * 3.0) != before:
			w.farm_changed.emit(t)


func on_new_day() -> void:
	var people := w.player_people()
	var cook := 0.0
	for u: Unit in people:
		cook = maxf(cook, u.skill("cooking"))
	var need := 0.0
	for u: Unit in people:
		need += float(u.stats.get("food_use", 1.0))
	need *= 1.0 - clampf(cook / 400.0, 0.0, 0.25)
	var food := int(w.res.get("food", 0))
	var eat := int(ceil(need))
	if food >= eat:
		w.res["food"] = food - eat
		if w.hungry:
			w.notify_key("sim.economy.hunger_ended", {}, "good")
		w.hungry = false
	else:
		w.res["food"] = 0
		if not w.hungry:
			w.notify_key("sim.economy.food_ran_out", {}, "bad")
		w.hungry = true
	for u: Unit in people:
		if u.injured_days > 0.0:
			u.injured_days = maxf(0.0, u.injured_days - 1.0)
			if u.injured_days == 0.0:
				u.recompute_stats()
				w.notify_key("sim.economy.injuries_recovered", {"unit_name": u.name}, "good", u.pos)
		u.character["days"] = int(u.character.get("days", 0)) + 1
		u.counters["days_survived"] = float(u.counters.get("days_survived", 0.0)) + 1.0
	_immigration(people.size())


func _immigration(pop: int) -> void:
	var free := w.housing() - pop
	if free <= 0 or w.hungry or int(w.res.get("food", 0)) < pop:
		return
	var arrivals := 1
	if free >= 4 and w.rng.randf() < 0.45:
		arrivals = 2
	if w.rng.randf() > 0.75:
		return
	for i in arrivals:
		var ang := w.rng.randf() * TAU
		var spawn := w.home_pos() + Vector2(cos(ang), sin(ang)) * 22.0
		var tile := w.nearest_walkable(Vector2i(int(spawn.x), int(spawn.y)), 8)
		if tile.x == -99999:
			tile = Vector2i(w.home_pos())
		var u := CharacterFactory.make_colonist(w, {"talent": ""}, Vector2(tile) + Vector2(0.5, 0.5))
		w.move_unit(u, w.home_pos())
		w.notify_key("sim.economy.newcomer", {"unit_name": u.name,
			"race": {"table": "races", "id": str(u.character.get("race", "")), "en": str(DB.get_def("races", str(u.character.get("race", ""))).get("name", ""))}, "role": {"table": "roles", "id": str(u.character.get("role", "")), "en": u.display_role()}}, "good", u.pos, {"unit": u.id})
