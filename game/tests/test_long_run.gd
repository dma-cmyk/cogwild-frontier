extends TestCase
## Long unattended run (10 in-game days at full delegation): the world keeps working on its own,
## with no invalid numbers, runaway entity counts or stalls. Slow (~2 min): run with
## --filter=long_run.

const DAYS := 10


func test_ten_days_unattended() -> void:
	var w := NewGame.create(2026)
	w.squad_ai.order_squad(w.squads[0], {"type": "auto"})
	for u: Unit in w.unit_list:
		if u.kind == "airship":
			u.order = {"type": "auto"}
	var t0 := Time.get_ticks_msec()
	var peak_units := 0
	var days_log: PackedStringArray = []
	for d in DAYS:
		for i in World.DAY_TICKS:
			w.tick()
		peak_units = maxi(peak_units, w.unit_list.size())
		for r: String in World.RESOURCES:
			assert_true(int(w.res[r]) >= 0, "day %d: %s negative" % [w.day, r])
		for u: Unit in w.unit_list:
			if is_nan(u.pos.x) or is_nan(u.pos.y) or is_nan(u.hp) or is_inf(u.hp):
				fail("day %d: invalid numbers on %s" % [w.day, u.name])
				break
			if u.alive and not u.flying and u.is_player() and not w.in_bounds(u.tile()):
				fail("day %d: %s left the world bounds" % [w.day, u.name])
		days_log.append("day %d: pop %d/%d, units %d, explored %d, sites %d, kills %d, wood %d food %d gold %d" % [
			w.day, w.population(), w.housing(), w.unit_list.size(), w.explored_count, w.sites.size(),
			int(w.counters.get("kills", 0)), int(w.res["wood"]), int(w.res["food"]), int(w.res["gold"])])
	var ms := Time.get_ticks_msec() - t0
	for line in days_log:
		print("  ", line)
	print("  %d ticks in %d ms (%.2f ms/tick), peak units %d" % [DAYS * World.DAY_TICKS, ms, float(ms) / (DAYS * World.DAY_TICKS), peak_units])
	assert_true(w.population() >= 8, "colony survived (%d people)" % w.population())
	assert_true(peak_units < 400, "entity count bounded (%d)" % peak_units)
	assert_true(w.explored_count > 20000, "the world kept being explored (%d)" % w.explored_count)
	assert_true(int(w.counters.get("wood_gathered", 0)) > 200, "settlers kept working")
	var discovered := 0
	for st: Dictionary in w.sites.values():
		if bool(st.get("discovered", false)):
			discovered += 1
	assert_true(discovered >= 5, "sites discovered (%d)" % discovered)
	w.dispose()
