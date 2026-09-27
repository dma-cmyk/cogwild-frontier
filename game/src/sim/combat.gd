class_name Combat
extends RefCounted
## Real-time combat: chasing and attacking targets, projectiles, damage/armour/crits, downed and
## death states, loot drops, experience, military ranks, watchtower fire and leader abilities.

const PROJECTILE_SPEED := {"arrow": 20.0, "bolt": 22.0, "bullet": 30.0, "cannon_shell": 13.0, "blaster_bolt": 18.0}
## Military ranks: [name, kills needed, level needed].
const RANKS := [["Recruit", 0, 1], ["Soldier", 2, 2], ["Veteran", 6, 4], ["Squad Leader", 14, 6], ["Captain", 26, 8], ["General", 45, 10]]
const DOWNED_RECOVER := 25.0
const DOWNED_BLEED_OUT := 70.0

var w: World
var projectiles: Array = []


func _init(world: World) -> void:
	w = world


func tick() -> void:
	for p: Dictionary in projectiles.duplicate():
		p["t"] = float(p["t"]) - World.TICK
		if float(p["t"]) <= 0.0:
			projectiles.erase(p)
			_resolve(p)
	for u: Unit in w.unit_list:
		if u.alive and u.state != Unit.State.DOWNED and u.target_id >= 0:
			_engage(u)
	if w.tick_count % 2 == 0:
		_towers()
	if w.tick_count % 10 == 5:
		_heal_drones()
		_abilities()
	if w.tick_count % 3 == 0:
		_pickup_loot()


## Nearest visible hostile within radius (player units see through the fog of war only).
func acquire(u: Unit, radius: float) -> Unit:
	var best: Unit = null
	var best_d := INF
	for o: Unit in w.units_near(u.pos, radius):
		if o == u or not o.alive or o.state == Unit.State.DOWNED or o.hidden:
			continue
		if not w.hostile(u.faction, o.faction):
			continue
		if u.is_player() and not o.visible:
			continue
		var d := u.pos.distance_squared_to(o.pos)
		if o.kind == "airship" and not u.is_machine():
			d += 40.0  # prefer ground targets
		if d < best_d:
			best_d = d
			best = o
	return best


func _engage(u: Unit) -> void:
	var t := w.get_unit(u.target_id)
	if t == null or not t.alive or t.state == Unit.State.DOWNED or t.hidden or not w.hostile(u.faction, t.faction):
		u.target_id = -1
		if u.state == Unit.State.FIGHT:
			u.state = Unit.State.IDLE
		return
	var wpn: Dictionary = u.stats.get("weapon", Unit.FISTS)
	var reach := float(wpn.get("range", 1.3)) + (0.6 if t.kind == "airship" or t.kind == "robot" else 0.2)
	var d := u.pos.distance_to(t.pos)
	if d > reach:
		if u.is_static:
			u.target_id = -1
			return
		if not u.moving or u.goal.distance_to(t.pos) > 1.8:
			var dest := t.pos - (t.pos - u.pos).normalized() * minf(reach * 0.8, d)
			if not w.move_unit(u, dest):
				u.target_id = -1
		u.state = Unit.State.MOVE
		return
	if u.moving:
		w.stop_unit(u)
	var dir := t.pos - u.pos
	if dir.length() > 0.01:
		u.facing = dir.normalized()
	u.state = Unit.State.FIGHT
	if u.attack_cd <= 0.0:
		u.attack_cd = float(wpn.get("cooldown", 1.0)) / maxf(0.2, float(u.stats.get("attack_speed", 1.0)))
		attack(u, t, wpn)


func attack(u: Unit, t: Unit, wpn: Dictionary) -> void:
	var ranged := str(wpn.get("kind", "melee")) == "ranged"
	var skill := u.skill("archery" if ranged else "melee")
	var dmg := float(wpn.get("damage", 3.0)) * (0.75 + skill / 160.0)
	dmg *= 1.0 + float(u.stats.get("ranged_pct" if ranged else "melee_pct", 0.0))
	dmg *= float(u.stats.get("damage_mult", 1.0))
	dmg *= w.rng.randf_range(0.85, 1.15)
	var crit := w.rng.randf() < float(u.stats.get("crit", 0.05))
	if crit:
		dmg *= 1.6
	u.push_fx(&"attack_ranged" if ranged else &"attack_melee")
	if not ranged:
		w.fx.emit(&"slash_arc", w.world_pos(u) + Vector3(0, 0.9, 0), Color("#ffe1a0"))
	if ranged:
		var hit_chance := clampf(float(wpn.get("accuracy", 0.75)) + skill / 300.0 + float(u.stats.get("accuracy", 0.0)) - (0.1 if t.moving else 0.0), 0.2, 0.97)
		var hit := w.rng.randf() < hit_chance
		var kind := str(wpn.get("projectile", "arrow"))
		var from := w.world_pos(u) + Vector3(0, 0.8 if not u.flying else 0.0, 0)
		var to := w.world_pos(t) + Vector3(0, 0.6, 0)
		if not hit:
			to += Vector3(w.rng.randf_range(-1.2, 1.2), -0.4, w.rng.randf_range(-1.2, 1.2))
		var flight := from.distance_to(to) / float(PROJECTILE_SPEED.get(kind, 18.0))
		projectiles.append({"t": flight, "target": t.id, "attacker": u.id, "damage": dmg, "hit": hit, "crit": crit,
			"splash": float(wpn.get("splash", 0.0)), "pos": Vector2(to.x, to.z), "kind": kind})
		w.projectile_fired.emit(from, to, kind, flight)
		if kind == "cannon_shell" or kind == "bullet":
			w.fx.emit(&"muzzle_flash", from, Color("#ffd27a"))
	else:
		apply_damage(t, dmg, u, crit)


func _resolve(p: Dictionary) -> void:
	var attacker := w.get_unit(int(p["attacker"]))
	var splash := float(p["splash"])
	if splash > 0.0:
		var pos: Vector2 = p["pos"]
		w.emit_fx(&"explosion_small", pos, 0.4)
		for o: Unit in w.units_near(pos, splash):
			if attacker and w.hostile(attacker.faction, o.faction):
				apply_damage(o, float(p["damage"]) * (1.0 if o.id == int(p["target"]) else 0.6), attacker, bool(p["crit"]))
		return
	if not bool(p["hit"]):
		var miss_pos: Vector2 = p["pos"]
		w.fx.emit(&"combat_miss", Vector3(miss_pos.x, w.height_at(miss_pos) + 1.0, miss_pos.y), Color("#aeb7c5"))
		return
	var t := w.get_unit(int(p["target"]))
	if t and t.alive and t.state != Unit.State.DOWNED:
		apply_damage(t, float(p["damage"]), attacker, bool(p["crit"]))


func apply_damage(t: Unit, amount: float, attacker: Unit, crit: bool = false) -> void:
	if not t.alive or t.state == Unit.State.DOWNED:
		return
	var dmg := maxf(1.0, amount - float(t.stats.get("armor", 0.0)) * 0.6)
	t.hp -= dmg
	t.last_hit_t = 0.0
	t.push_fx(&"hit")
	var impact := w.world_pos(t) + Vector3(0, 0.7, 0)
	w.fx.emit(&"hit_spark", impact, Color("#ffe08a") if crit else Color.WHITE)
	w.fx.emit(StringName("combat_damage|%d|%d" % [roundi(dmg), 1 if crit else 0]), impact + Vector3(0, 0.45, 0), Color.WHITE)
	if attacker and t.target_id < 0 and t.is_armed() and w.hostile(t.faction, attacker.faction):
		if not (t.is_player() and t.squad_id >= 0 and str(w.get_squad(t.squad_id).order.get("type", "")) == "retreat"):
			t.target_id = attacker.id
	if t.hp <= 0.0:
		_fall(t, attacker)


func _fall(t: Unit, attacker: Unit) -> void:
	t.hp = 0.0
	w.stop_unit(t)
	t.target_id = -1
	if t.is_player() and t.is_person():
		t.state = Unit.State.DOWNED
		t.downed_t = 0.0
		w.colony.release(t)
		w.notify_key("sim.combat.unit_down", {"unit_name": t.name}, "bad", t.pos, {"unit": t.id})
	else:
		t.alive = false
		t.state = Unit.State.DEAD
		t.downed_t = 0.0
		w.fx.emit(&"death_poof", w.world_pos(t), Color.WHITE)
		if t.is_player():
			w.notify_key("sim.combat.unit_destroyed", {"unit_name": t.name}, "bad", t.pos)
			w.colony.release(t)
		else:
			_drop_loot(t, attacker)
			w.factions.on_unit_killed(t, attacker)
	if attacker and attacker.alive:
		attacker.target_id = -1
		if not t.is_player():
			_reward_kill(attacker, t)


func _reward_kill(a: Unit, victim: Unit) -> void:
	a.counter_add("kills")
	w.counters["kills"] = int(w.counters.get("kills", 0)) + 1
	if not a.is_person():
		return
	var ranged := str((a.stats.get("weapon", {}) as Dictionary).get("kind", "melee")) == "ranged"
	var xp := 30.0 + victim.char_level() * 8.0 + (60.0 if not victim.named.is_empty() else 0.0)
	w.colony.gain_xp(a, "archery" if ranged else "melee", xp)
	if a.squad_id >= 0:
		_update_rank(a)


func _update_rank(a: Unit) -> void:
	var kills := int(a.counters.get("kills", 0.0))
	var lv := a.char_level()
	var rank := ""
	for r: Array in RANKS:
		if kills >= int(r[1]) and lv >= int(r[2]):
			rank = str(r[0])
	var old := str(a.character.get("rank", ""))
	if rank != "" and rank != old:
		var idx_old := -1
		var idx_new := -1
		for i in RANKS.size():
			if RANKS[i][0] == old:
				idx_old = i
			if RANKS[i][0] == rank:
				idx_new = i
		if idx_new > idx_old:
			a.character["rank"] = rank
			if idx_new > 0:
				w.notify_key("sim.combat.promoted", {"unit_name": a.name, "rank": rank}, "levelup", a.pos, {"unit": a.id})


## Rank on joining a squad.
func enlist(a: Unit) -> void:
	if a.is_person() and str(a.character.get("rank", "")) == "":
		a.character["rank"] = "Recruit"
		_update_rank(a)


func _drop_loot(t: Unit, attacker: Unit) -> void:
	var items: Array = []
	var luck := float(attacker.stats.get("loot_luck", 0.0)) if attacker else 0.0
	var level := t.char_level()
	if t.is_person():
		for slot: String in t.equipment():
			var it: Variant = t.equipment()[slot]
			if it is Dictionary and w.rng.randf() < 0.35:
				items.append((it as Dictionary).duplicate(true))
		if w.rng.randf() < 0.25:
			items.append(ItemGen.generate(w.rng, {"level": level, "luck": luck, "source": "loot"}))
	elif w.rng.randf() < 0.3:
		items.append(ItemGen.generate(w.rng, {"level": level, "luck": luck, "category": "robot_part", "source": "loot"}))
	if not t.named.is_empty():
		for it: Variant in t.named.get("loot", []):
			if it is Dictionary:
				items.append((it as Dictionary).duplicate(true))
	var gold := w.rng.randi_range(2, 8) * (3 if not t.named.is_empty() else 1) if t.is_person() else 0
	var metal := 0
	var drops: Dictionary = t.DB_archetype().get("drops", {})
	if drops.has("metal"):
		metal = w.rng.randi_range(int(drops["metal"][0]), int(drops["metal"][1]))
	for it: Dictionary in items:
		it["uid"] = 0
	var bag := w.drop_loot(t.pos, items, gold, metal)
	if not bag.is_empty() and int(bag["tier"]) >= 4:
		w.emit_fx(&"loot_beam", t.pos, 0.0, Icons.quality_color(quality_for_tier(int(bag["tier"]))))


static func quality_for_tier(tier: int) -> String:
	for q: Dictionary in DB.entries("items/qualities"):
		if int(q.get("tier", -1)) == tier:
			return str(q["id"])
	return "common"


func update_downed(u: Unit) -> void:
	u.downed_t += World.TICK
	var threat := false
	for o: Unit in w.units_near(u.pos, 7.0):
		if w.hostile(u.faction, o.faction) and o.is_armed():
			threat = true
			break
	if not threat and u.downed_t >= DOWNED_RECOVER:
		u.state = Unit.State.IDLE
		u.hp = float(u.stats["max_hp"]) * 0.25
		u.injured_days = 2.0
		u.recompute_stats()
		u.counter_add("downed_survived")
		w.colony.check_titles(u)
		w.notify_key("sim.combat.recovered_injured", {"unit_name": u.name}, "info", u.pos, {"unit": u.id})
	elif threat and u.downed_t >= DOWNED_BLEED_OUT:
		u.alive = false
		u.state = Unit.State.DEAD
		u.downed_t = 0.0
		w.fx.emit(&"death_poof", w.world_pos(u), Color.WHITE)
		w.notify_key("sim.combat.unit_died", {"unit_name": u.name}, "bad", u.pos)


func _towers() -> void:
	for b: Building in w.buildings.values():
		if b.faction != "player" or not b.is_built():
			continue
		var d: Dictionary = b.def().get("defense", {})
		if d.is_empty():
			continue
		b.attack_cd -= World.TICK * 2.0
		if b.attack_cd > 0.0:
			continue
		var best: Unit = null
		var best_d := INF
		for o: Unit in w.units_near(b.center(), float(d.get("range", 10.0))):
			if w.hostile("player", o.faction) and o.visible and o.state != Unit.State.DOWNED:
				var dd := o.pos.distance_squared_to(b.center())
				if dd < best_d:
					best_d = dd
					best = o
		if best == null:
			continue
		b.attack_cd = float(d.get("cooldown", 1.6))
		var from := Vector3(b.center().x, w.height_at(b.center()) + 5.2, b.center().y)
		var to := w.world_pos(best) + Vector3(0, 0.6, 0)
		var kind := str(d.get("projectile", "arrow"))
		var flight := from.distance_to(to) / float(PROJECTILE_SPEED.get(kind, 18.0))
		var hit := w.rng.randf() < float(d.get("accuracy", 0.75))
		projectiles.append({"t": flight, "target": best.id, "attacker": -1, "damage": float(d.get("damage", 7.0)), "hit": hit,
			"crit": false, "splash": 0.0, "pos": best.pos, "kind": kind})
		w.projectile_fired.emit(from, to, kind, flight)


func _heal_drones() -> void:
	for u: Unit in w.unit_list:
		var heal: Dictionary = u.DB_archetype().get("heal", {}) if u.kind == "drone" else {}
		if heal.is_empty() or not u.alive:
			continue
		var best: Unit = null
		var worst := 0.98
		for o: Unit in w.units_near(u.pos, float(heal.get("range", 5.0))):
			if o.faction == u.faction and o.alive and o.state != Unit.State.DOWNED and o.hp_ratio() < worst:
				worst = o.hp_ratio()
				best = o
		if best:
			var previous_hp := best.hp
			best.hp = minf(float(best.stats["max_hp"]), best.hp + float(heal.get("amount", 5.0)))
			var healed := best.hp - previous_hp
			var heal_pos := w.world_pos(best) + Vector3(0, 0.8, 0)
			w.fx.emit(&"heal", heal_pos, Color("#7dff9a"))
			w.fx.emit(StringName("combat_heal|%d" % roundi(healed)), heal_pos + Vector3(0, 0.45, 0), Color("#73ff9b"))


## Named leaders use their abilities while fighting.
func _abilities() -> void:
	for u: Unit in w.unit_list:
		if u.named.is_empty() or not u.alive or u.target_id < 0:
			continue
		for aid: String in u.named.get("abilities", []):
			var a := DB.get_def("generation/abilities", aid)
			if a.is_empty():
				continue
			var cd := float(u.ability_cd.get(aid, 0.0)) - 1.0
			u.ability_cd[aid] = cd
			if cd > 0.0:
				continue
			var used := false
			match str(a.get("kind", "")):
				"buff_allies":
					for o: Unit in w.units_near(u.pos, float(a.get("radius", 6.0))):
						if o.faction == u.faction:
							o.buffs.append({"mods": a.get("mods", {}), "t": float(a.get("duration", 8.0))})
							o.recompute_stats()
					used = true
				"buff_self":
					u.buffs.append({"mods": a.get("mods", {}), "t": float(a.get("duration", 6.0))})
					u.recompute_stats()
					used = true
				"heal_self":
					if u.hp_ratio() < float(a.get("trigger_hp", 0.5)):
						var previous_hp := u.hp
						u.hp = minf(float(u.stats["max_hp"]), u.hp + float(u.stats["max_hp"]) * float(a.get("amount_pct", 0.25)))
						var healed := u.hp - previous_hp
						var heal_pos := w.world_pos(u) + Vector3(0, 1.0, 0)
						w.fx.emit(&"heal", heal_pos, Color("#ffb070"))
						w.fx.emit(StringName("combat_heal|%d" % roundi(healed)), heal_pos + Vector3(0, 0.45, 0), Color("#73ff9b"))
						used = true
				"multi_shot":
					var t := w.get_unit(u.target_id)
					if t:
						for i in int(a.get("shots", 3)):
							attack(u, t, u.stats.get("weapon", Unit.FISTS))
						used = true
			if used:
				u.ability_cd[aid] = float(a.get("cooldown", 15.0))
				if u.visible and not u.is_player():
					w.notify_key("sim.combat.ability_used", {"unit_name": u.name, "ability": {"table": "generation/abilities", "id": aid, "en": str(a.get("name", aid))}}, "bad", u.pos)


func _pickup_loot() -> void:
	for id: int in w.loot_bags.keys():
		var bag: Dictionary = w.loot_bags.get(id, {})
		if bag.is_empty():
			continue
		for o: Unit in w.units_near(bag["pos"], 1.6):
			if o.is_player() and o.alive and o.state != Unit.State.DOWNED and o.kind != "airship":
				w.pickup_loot(id, o)
				break
