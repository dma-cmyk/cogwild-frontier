extends TestCase
## Tactical orders, modifiers, ability state, and save compatibility.

var _worlds: Array[World] = []

func _new() -> World:
	var w := NewGame.create(511)
	_worlds.append(w)
	return w

func after_all() -> void:
	for w: World in _worlds:
		w.dispose()
	_worlds.clear()

func _enemy(w: World, p: Vector2) -> Unit:
	var tile := w.nearest_walkable(Vector2i(p), 6)
	var enemy := CharacterFactory.make_npc(w, "bandit_archer", "bandits", Vector2(tile) + Vector2(0.5, 0.5), 1)
	enemy.visible = true
	return enemy

func test_hold_does_not_acquire_targets_beyond_six_metres() -> void:
	var w := _new()
	var squad := w.squads[0]
	var anchor := w.squad_ai.center(squad)
	squad.stance = "hold"
	squad.mem["hold"] = anchor
	var enemy := _enemy(w, anchor + Vector2(8, 0))
	assert_false(w.squad_ai._engage(squad, anchor, 18.0), "hold ignores hostile outside its 6 m order radius")
	for id: int in squad.members:
		assert_eq(w.get_unit(id).target_id, -1, "no squad member is assigned a distant target")
	assert_eq(enemy.target_id, -1, "holding squad does not start a fight beyond its radius")

func test_cautious_retreats_at_higher_hp_fraction_than_aggressive() -> void:
	var w := _new()
	var squad := w.squads[0]
	for id: int in squad.members:
		var unit := w.get_unit(id)
		unit.hp = float(unit.stats["max_hp"]) * 0.4
	squad.stance = "cautious"
	w.squad_ai._think(squad)
	assert_eq(str(squad.order.get("type", "")), "retreat", "cautious withdraws at 40% HP")
	squad.order = {"type":"idle"}
	squad.stance = "aggressive"
	w.squad_ai._think(squad)
	assert_eq(str(squad.order.get("type", "")), "idle", "aggressive remains engaged at the same HP fraction")

func test_aimed_shot_cooldown_and_damage_interrupt() -> void:
	var w := _new()
	var shooter := w.get_unit(int(w.squads[0].members[0]))
	shooter.character["role"] = "archer"
	shooter.stats["weapon"] = {"kind":"ranged", "range":10.0, "damage":8.0, "cooldown":1.0, "accuracy":0.8, "projectile":"arrow"}
	var enemy := _enemy(w, shooter.pos + Vector2(3, 0))
	shooter.target_id = enemy.id
	shooter.last_hit_t = 2.0
	w.combat._abilities()
	assert_true(shooter.ability_windup > 0.0, "aimed shot enters windup")
	assert_true(float(shooter.ability_cd.get("aimed_shot", 0.0)) > 0.0, "ability cooldown starts on activation")
	w.combat.apply_damage(shooter, 1.0, enemy)
	assert_eq(shooter.ability_windup, 0.0, "incoming damage interrupts aim")
	assert_true(float(shooter.ability_cd.get("aimed_shot", 0.0)) > 0.0, "interrupted shot retains cooldown")

func test_flank_bonus_uses_facing_and_outnumbering() -> void:
	var w := _new()
	var attacker := w.get_unit(int(w.squads[0].members[0]))
	var target := _enemy(w, attacker.pos + Vector2(4, 0))
	target.facing = Vector2.RIGHT
	attacker.pos = target.pos + Vector2(2, 0)
	assert_false(w.combat._is_flank(attacker, target), "front-facing attacker is not flanking")
	attacker.pos = target.pos + Vector2(-2, 0)
	assert_true(w.combat._is_flank(attacker, target), "attacker outside facing cone receives flank")
	attacker.pos = target.pos + Vector2(2, 0)
	attacker.target_id = target.id
	var second := w.get_unit(int(w.squads[0].members[1]))
	second.target_id = target.id
	assert_true(w.combat._is_flank(attacker, target), "target engaged by two attackers is flanked")

func test_flank_bonus_is_applied_to_damage() -> void:
	var w := _new()
	var attacker := w.get_unit(int(w.squads[0].members[0]))
	var target := _enemy(w, attacker.pos + Vector2(4, 0))
	var weapon: Dictionary = {"kind":"melee", "damage":12.0, "range":1.4, "cooldown":1.0}
	target.facing = Vector2.RIGHT
	attacker.pos = target.pos + Vector2(2, 0)
	target.hp = float(target.stats["max_hp"])
	w.rng.seed = 731
	w.combat.attack(attacker, target, weapon)
	var front_damage := float(target.stats["max_hp"]) - target.hp
	target.hp = float(target.stats["max_hp"])
	attacker.pos = target.pos + Vector2(-2, 0)
	w.rng.seed = 731
	w.combat.attack(attacker, target, weapon)
	var flank_damage := float(target.stats["max_hp"]) - target.hp
	assert_true(flank_damage > front_damage * 1.1, "outside-facing-cone attack receives 15%% damage bonus (%0.1f vs %0.1f)" % [flank_damage, front_damage])
func test_stance_formation_and_cooldowns_round_trip() -> void:
	var w := _new()
	var squad := w.squads[0]
	squad.stance = "cautious"
	squad.formation = "wedge"
	var unit := w.get_unit(int(squad.members[0]))
	squad.auto_abilities = false
	unit.ability_cd["shield_bash"] = 7.5
	var loaded := SaveGame.parse(JSON.stringify(SaveGame.to_dict(w)))
	assert_true(loaded.has("world"), "world save reloads")
	var restored: World = loaded["world"]
	_worlds.append(restored)
	var restored_squad := restored.get_squad(squad.id)
	assert_eq(restored_squad.stance, "cautious", "stance persists")
	assert_eq(restored_squad.formation, "wedge", "formation persists")
	assert_eq(float(restored.get_unit(unit.id).ability_cd["shield_bash"]), 7.5, "ability cooldown persists")
	assert_false(restored_squad.auto_abilities, "auto ability setting persists")
	var legacy := Squad.from_dict({"id":9, "name":"Old squad"})
	assert_eq(legacy.stance, "balanced", "legacy stance defaults balanced")
	assert_eq(legacy.formation, "line", "legacy formation defaults line")
	assert_true(legacy.auto_abilities, "legacy squads default to automatic abilities")

func test_manual_ability_effect_and_cooldown_reason() -> void:
	var w := _new()
	var unit := w.get_unit(int(w.squads[0].members[0]))
	w.squads[0].auto_abilities = false
	unit.character["role"] = "guard"
	var enemy := _enemy(w, unit.pos + Vector2(1, 0))
	assert_true(w.combat.ability_ids(unit).has("shield_bash"), "guard can use Shield Bash")
	assert_eq(w.combat.use_ability(unit, "shield_bash", {"unit":enemy.id}), "", "manual ability activates")
	assert_true(float(enemy.ability_cd.get("stunned", 0.0)) > 0.0, "Shield Bash stuns target")
	assert_true(float(unit.ability_cd.get("shield_bash", 0.0)) > 0.0, "manual ability starts cooldown")
	assert_eq(w.combat.use_ability(unit, "shield_bash", {"unit":enemy.id}), "cooldown", "cooldown refusal reports reason")


func test_manual_field_dressing_revives_downed_ally() -> void:
	var w := _new()
	var squad := w.squads[0]
	var medic := w.get_unit(int(squad.members[0]))
	var ally := w.get_unit(int(squad.members[1]))
	ally.pos = medic.pos + Vector2(1, 0)
	medic.character["role"] = "medic"
	ally.hp = 0.0
	ally.state = Unit.State.DOWNED
	assert_eq(str(w.combat.ability_info(medic, "field_dressing").get("target", "")), "ally", "Field Dressing targets allies")
	assert_eq(w.combat.use_ability(medic, "field_dressing", {"unit":ally.id}), "", "medic uses Field Dressing on downed ally")
	assert_ne(ally.state, Unit.State.DOWNED, "Field Dressing revives the ally")
	assert_true(ally.hp > 0.0, "revived ally receives health")


func test_manual_out_of_range_ability_approaches_and_fires() -> void:
	var w := _new()
	var unit := w.get_unit(int(w.squads[0].members[0]))
	unit.character["role"] = "archer"
	var enemy := _enemy(w, unit.pos + Vector2(18, 0))
	assert_eq(w.combat.use_ability(unit, "aimed_shot", {"unit":enemy.id}), "", "out-of-range ability queues")
	assert_true(unit.moving, "unit approaches the target")
	var reached_range := false
	for tick in 250:
		w.tick()
		if unit.ability_windup > 0.0:
			reached_range = true
			break
	assert_true(reached_range, "queued ability fires after the unit walks into range")
	assert_true(float(unit.ability_cd.get("aimed_shot", 0.0)) > 0.0, "queued ability starts cooldown")


func test_new_order_cancels_pending_manual_ability() -> void:
	var w := _new()
	var squad := w.squads[0]
	var unit := w.get_unit(int(squad.members[0]))
	unit.character["role"] = "archer"
	var enemy := _enemy(w, unit.pos + Vector2(18, 0))
	assert_eq(w.combat.use_ability(unit, "aimed_shot", {"unit":enemy.id}), "", "out-of-range ability queues")
	assert_true(unit.named.has("_pending_ability"), "manual order remains pending while approaching")
	w.squad_ai.order_squad(squad, {"type":"move", "pos":unit.pos + Vector2(2, 0)})
	assert_false(unit.named.has("_pending_ability"), "new squad order cancels the manual ability")


func test_auto_abilities_can_be_disabled() -> void:
	var w := _new()
	var squad := w.squads[0]
	var unit := w.get_unit(int(squad.members[0]))
	unit.character["role"] = "guard"
	var enemy := _enemy(w, unit.pos + Vector2(1, 0))
	unit.target_id = enemy.id
	squad.auto_abilities = false
	w.combat._abilities()
	assert_eq(float(enemy.ability_cd.get("stunned", 0.0)), 0.0, "disabled auto abilities do not stun")
	assert_eq(float(unit.ability_cd.get("shield_bash", 0.0)), 0.0, "disabled auto abilities do not start cooldown")

func _run_ab_fight(stance: String, formation: String, seed: int = 11) -> Dictionary:
	var w := NewGame.create(seed)
	_worlds.append(w)
	var squad := w.squads[0]
	squad.stance = stance
	squad.formation = formation
	var initial_hp := 0.0
	for id: int in squad.members:
		initial_hp += w.get_unit(id).hp
	var center := w.squad_ai.center(squad)
	var enemies: Array[Unit] = []
	for offset: Vector2 in [Vector2(4, 0), Vector2(4, 2), Vector2(5, -2), Vector2(6, 1),
			Vector2(7, 3), Vector2(7, -3), Vector2(8, 0), Vector2(5, 4)]:
		enemies.append(_enemy(w, center + offset))
	if stance == "hold":
		squad.mem["hold"] = enemies[0].pos
	w.squad_ai.order_squad(squad, {"type":"attack", "target":enemies[0].id})
	var duration := 6000
	var distance_total := 0.0
	var distance_samples := 0
	for tick in 6000:
		w.tick()
		var nearest_total := 0.0
		var nearest_count := 0
		for id: int in squad.members:
			var member := w.get_unit(id)
			if not member.alive or member.state == Unit.State.DOWNED:
				continue
			var nearest := INF
			for opponent: Unit in enemies:
				if opponent.alive:
					nearest = minf(nearest, member.pos.distance_to(opponent.pos))
			if nearest < INF:
				nearest_total += nearest
				nearest_count += 1
		if nearest_count > 0:
			distance_total += nearest_total / float(nearest_count)
			distance_samples += 1
		var alive := false
		for enemy: Unit in enemies:
			alive = alive or enemy.alive
		if not alive:
			duration = tick + 1
			break
	var casualties := 0
	var remaining_hp := 0.0
	for id: int in squad.members:
		var unit := w.get_unit(id)
		if not unit.alive or unit.state == Unit.State.DOWNED:
			casualties += 1
		remaining_hp += unit.hp
	var result := {"stance":stance, "formation":formation, "casualties":casualties,
		"duration_seconds":float(duration) * World.TICK, "damage_taken":maxf(0.0, initial_hp - remaining_hp),
		"mean_enemy_distance":distance_total / float(maxi(1, distance_samples))}
	print("TACTICS_AB " + JSON.stringify(result))
	return result


func test_stances_and_formations_change_scripted_fight_metrics() -> void:
	var balanced := _run_ab_fight("balanced", "line")
	var cautious_wedge := _run_ab_fight("cautious", "wedge")
	var cautious := _run_ab_fight("cautious", "line")
	var aggressive := _run_ab_fight("aggressive", "line")
	var hold := _run_ab_fight("hold", "line")
	assert_true(balanced["casualties"] != cautious_wedge["casualties"] or balanced["damage_taken"] != cautious_wedge["damage_taken"],
		"cautious wedge changes outcome compared with balanced line")
	assert_ne(cautious["mean_enemy_distance"], aggressive["mean_enemy_distance"],
		"cautious and aggressive stances produce measurable engagement distances")
	assert_ne(hold["mean_enemy_distance"], aggressive["mean_enemy_distance"],
		"hold and aggressive stances produce measurably different engagement distances")
	# one scripted fight depends on the generated crew; compare the total over several worlds
	var balanced_total := float(balanced["damage_taken"])
	var cautious_total := float(cautious["damage_taken"])
	var aggressive_total := float(aggressive["damage_taken"])
	for seed: int in [3, 7]:
		balanced_total += float(_run_ab_fight("balanced", "line", seed)["damage_taken"])
		cautious_total += float(_run_ab_fight("cautious", "line", seed)["damage_taken"])
		aggressive_total += float(_run_ab_fight("aggressive", "line", seed)["damage_taken"])
	assert_true(cautious_total < balanced_total * 0.9,
		"cautious positioning reduces squad damage taken (%.0f vs %.0f over three worlds)" % [cautious_total, balanced_total])
	assert_true(float(aggressive["duration_seconds"]) < float(balanced["duration_seconds"]),
		"aggressive stance clears the engagement fastest")
	assert_true(aggressive_total >= balanced_total * 0.95,
		"aggressive stance accepts comparable incoming damage while closing (%.0f vs %.0f over three worlds)" % [aggressive_total, balanced_total])
