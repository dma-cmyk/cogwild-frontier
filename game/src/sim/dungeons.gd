class_name Dungeons
extends RefCounted
## Dungeons appear as days pass: an entrance shows up somewhere on the surface with a difficulty
## and a random number of floors (deeper for harder dungeons). Every floor lives in the reserved
## zone of the world grid (DungeonZone); the surface keeps simulating while a squad is down there.
## Deeper floors and harder dungeons mean stronger enemies and better loot.

signal relocated(pos: Vector2, eid: int, floor_index: int)
signal floor_created(eid: int, floor_index: int)

const ID_BASE := 2000000
const ID_STEP := 16
const SPAWN_CHANCE := 0.5
const FIRST_ENTRANCE_DAY := 2  # a dungeon is always around by the second day
const UNVISITED_DAYS := 30
const ABANDONED_DAYS := 60
const CLEARED_DAYS := 8
const THEMES := ["brigands", "goblins", "reptiles", "beastfolk", "machines"]
const DIFFICULTY_WEIGHTS := {1: 34, 2: 28, 3: 20, 4: 12, 5: 6}
const THEME_RACES := {
	"goblins": ["goblin", "kobold", "orc"],
	"reptiles": ["lizardfolk", "lamia", "kobold"],
	"beastfolk": ["minotaur", "oni", "harpy", "tengu"],
}
const MIN_CHEST_QUALITY := ["common", "fine", "rare", "epic", "legendary"]
const NOWHERE := Vector2i(-99999, -99999)

var w: World
var _layouts: Dictionary = {}  # "eid:floor" -> floor layout (regenerated on demand, never saved)
var _slot_owner: Array = [-1, -1, -1, -1]


func _init(world: World) -> void:
	w = world


# --- basics ------------------------------------------------------------------------------------

func enabled() -> bool:
	return w.gen != null and w.gen.dungeon_zone.size != Vector2i.ZERO


func zone() -> Rect2i:
	return w.gen.dungeon_zone


## Enemy level on a floor: harder dungeons start higher and every floor down adds one.
static func floor_level(difficulty: int, floor_index: int) -> int:
	return maxi(1, 2 * difficulty - 1 + floor_index)


func entrances() -> Array:
	var out: Array = []
	for st: Dictionary in w.sites.values():
		if str(st.get("kind", "")) == "dungeon":
			out.append(st)
	return out


func layout(eid: int, floor_index: int) -> Dictionary:
	var st: Dictionary = w.sites.get(eid, {})
	if st.is_empty() or floor_index < 0 or floor_index >= int(st["floors"]):
		return {}
	var key := "%d:%d" % [eid, floor_index]
	if not _layouts.has(key):
		_layouts[key] = DungeonZone.generate_floor(w.seed, eid, floor_index, int(st["difficulty"]), int(st["floors"]))
	return _layouts[key]


func _layout_for_slot(slot: int, floor_index: int) -> Dictionary:
	var eid: int = _slot_owner[slot]
	return layout(eid, floor_index) if eid >= 0 else {}


func floor_lookup() -> Callable:
	return Callable(self, "_layout_for_slot")


func rebuild_slots() -> void:
	_slot_owner = [-1, -1, -1, -1]
	_layouts.clear()
	for st: Dictionary in entrances():
		_slot_owner[int(st["slot"])] = int(st["id"])


func _free_slot() -> int:
	for i in _slot_owner.size():
		if int(_slot_owner[i]) < 0:
			return i
	return -1


func floor_origin(eid: int, floor_index: int) -> Vector2i:
	return DungeonZone.slot_origin(zone(), int((w.sites[eid] as Dictionary)["slot"]), floor_index)


func to_world(eid: int, floor_index: int, local: Vector2i) -> Vector2:
	return Vector2(floor_origin(eid, floor_index) + local) + Vector2(0.5, 0.5)


## {eid, floor} of the dungeon floor a position is on, or {} on the surface.
func locate(pos: Vector2) -> Dictionary:
	if not enabled():
		return {}
	var loc := DungeonZone.locate(zone(), Vector2i(int(floor(pos.x)), int(floor(pos.y))))
	if loc.is_empty():
		return {}
	var eid: int = _slot_owner[int(loc[0])]
	if eid < 0 or int(loc[1]) >= int((w.sites[eid] as Dictionary)["floors"]):
		return {}
	return {"eid": eid, "floor": int(loc[1])}


func squad_location(s: Squad) -> Dictionary:
	if not enabled():
		return {}
	for id: int in s.members:
		var u := w.get_unit(id)
		if u != null and u.alive:
			return locate(u.pos)
	return {}

func same_map(a: Vector2, b: Vector2) -> bool:
	if not enabled():
		return true
	var first := DungeonZone.locate(zone(), Vector2i(floori(a.x), floori(a.y)))
	var second := DungeonZone.locate(zone(), Vector2i(floori(b.x), floori(b.y)))
	if first.is_empty() or second.is_empty():
		return first.is_empty() and second.is_empty()
	return first[0] == second[0] and first[1] == second[1]



func floor_site(eid: int, floor_index: int) -> Dictionary:
	var st: Dictionary = w.sites.get(eid, {})
	if st.is_empty():
		return {}
	var ids: Array = st.get("floor_sids", [])
	if floor_index < 0 or floor_index >= ids.size() or int(ids[floor_index]) < 0:
		return {}
	return w.sites.get(int(ids[floor_index]), {})


## Stairs and exit of a floor: [{type: "up"|"down"|"exit", pos: Vector2}].
func features(eid: int, floor_index: int) -> Array:
	var lay := layout(eid, floor_index)
	if lay.is_empty():
		return []
	var out: Array = [{"type": "exit" if floor_index == 0 else "up", "pos": to_world(eid, floor_index, lay["up"])}]
	if not bool(lay["last"]):
		out.append({"type": "down", "pos": to_world(eid, floor_index, lay["down"])})
	return out


## The stairs (or exit) within `radius` of a position on the floor it stands on, else {}.
func feature_near(pos: Vector2, radius: float = 2.6) -> Dictionary:
	var loc := locate(pos)
	if loc.is_empty():
		return {}
	for f: Dictionary in features(int(loc["eid"]), int(loc["floor"])):
		if (f["pos"] as Vector2).distance_to(pos) <= radius:
			var out: Dictionary = f.duplicate()
			out["eid"] = int(loc["eid"])
			out["floor"] = int(loc["floor"])
			return out
	return {}


func stairs_order(eid: int, floor_index: int, dir: String) -> Dictionary:
	for f: Dictionary in features(eid, floor_index):
		if (dir == "down" and f["type"] == "down") or (dir == "up" and f["type"] in ["up", "exit"]):
			return {"type": "stairs", "site": eid, "floor": floor_index, "dir": dir, "pos": f["pos"]}
	return {}


func gate_pos(st: Dictionary) -> Vector2:
	return Vector2(st["center"]) + Vector2(0.5, 2.6)


# --- entrances appearing over time -----------------------------------------------------------

func on_new_day() -> void:
	if not enabled():
		return
	for st: Dictionary in entrances():
		_age(st)
	var open := 0
	for st: Dictionary in entrances():
		if str(st.get("state", "open")) == "open":
			open += 1
	if open >= _slot_owner.size():
		return
	var rng := RngUtil.make([w.seed, "dungeon_day", w.day])
	var due := rng.randf() < SPAWN_CHANCE or (w.day >= FIRST_ENTRANCE_DAY and entrances().is_empty())
	if due:
		spawn_entrance(rng)


func _age(st: Dictionary) -> void:
	var eid := int(st["id"])
	var state := str(st.get("state", "open"))
	var visited := false
	for id: Variant in st.get("floor_sids", []):
		if int(id) >= 0:
			visited = true
	var age := w.day - int(st.get("spawn_day", w.day))
	var done := false
	if state == "cleared":
		done = w.day - int(st.get("cleared_day", w.day)) >= CLEARED_DAYS
	elif not visited:
		done = age >= UNVISITED_DAYS
	else:
		done = age >= ABANDONED_DAYS
	if done and not players_inside(eid):
		collapse(eid)


func players_inside(eid: int) -> bool:
	for u: Unit in w.unit_list:
		if u.alive and u.is_player():
			var loc := locate(u.pos)
			if not loc.is_empty() and int(loc["eid"]) == eid:
				return true
	return false


## Makes a new entrance. opts: difficulty, floors, theme, pos (Vector2i tile), discovered. Returns
## the site id or -1 when there is no room (every slot taken, no suitable ground).
func spawn_entrance(rng: RandomNumberGenerator, opts: Dictionary = {}) -> int:
	if not enabled():
		return -1
	var slot := _free_slot()
	if slot < 0:
		return -1
	var difficulty := int(opts.get("difficulty", 0))
	if difficulty <= 0:
		difficulty = int(RngUtil.weighted_key(rng, DIFFICULTY_WEIGHTS))
	var floors := int(opts.get("floors", 0))
	if floors <= 0:
		floors = DungeonZone.floors_for(difficulty, rng)
	var theme := str(opts.get("theme", RngUtil.pick(rng, THEMES)))
	var pos: Vector2i = opts["pos"] if opts.has("pos") else _pick_location(rng)
	if pos == NOWHERE:
		return -1
	var seq := int(w.counters.get("dungeon_seq", 0))
	w.counters["dungeon_seq"] = seq + 1
	var eid := ID_BASE + seq * ID_STEP
	var floor_ids: Array = []
	for i in floors:
		floor_ids.append(-1)
	var st := {
		"id": eid, "kind": "dungeon", "center": pos, "name": NameGen.place(rng, "dungeon"),
		"faction": "", "hostile": false, "level": floor_level(difficulty, 0),
		"discovered": bool(opts.get("discovered", false)), "cleared": false, "looted": false,
		"units": [], "cache": [], "cache_gold": 0, "extra": [], "next_patrol": 0, "next_raid_day": 99999,
		"cleared_day": 0, "icon": "poi_ruins", "difficulty": difficulty, "floors": floors, "slot": slot,
		"theme": theme, "spawn_day": w.day, "state": "open", "floor_sids": floor_ids,
	}
	w.sites[eid] = st
	w.gen.sites[eid] = _gen_record(st)
	_slot_owner[slot] = eid
	if not w.add_site_structure(eid, "ruin_vault", pos - Vector2i(1, 1), Vector2i(3, 3)):
		w.sites.erase(eid)
		w.gen.sites.erase(eid)
		_slot_owner[slot] = -1
		return -1
	refresh_slot(slot)
	w.site_changed.emit(eid)
	var origin := Vector2(pos) + Vector2(0.5, 0.5)
	w.notify_key("sim.dungeon.appeared", {"site_name": st["name"], "direction": {"key": Quests.direction_between(w.home_pos(), origin)},
		"difficulty": difficulty}, "discover", origin, {"site": eid})
	return eid


func _gen_record(st: Dictionary) -> Dictionary:
	return {"id": int(st["id"]), "kind": str(st["kind"]), "center": st["center"], "flat_radius": 0,
		"height": 0.0, "faction": "", "icon": str(st.get("icon", "")), "distance": 0.0,
		"level": int(st["level"]), "structures": [], "decor": [], "resources": [], "clear_radius": 0}


## A random spot on the surface anywhere in the world: open ground, away from the settlement and
## other places. Only a few candidates that pass cheap terrain checks get their chunks generated.
func _pick_location(rng: RandomNumberGenerator) -> Vector2i:
	var g := w.gen
	var home := w.home_pos()
	var bank := float(g.t["river_bank"])
	var generated := 0
	for attempt in 120:
		var x := rng.randi_range(g.min_tile + 20, g.max_tile - 20)
		var z := rng.randi_range(g.min_tile + 20, g.max_tile - 20)
		var tile := Vector2i(x, z)
		if Rect2(g.dungeon_zone).grow(30.0).has_point(Vector2(tile)):
			continue
		var p := Vector2(x + 0.5, z + 0.5)
		if p.distance_to(home) < 30.0:
			continue
		var h := g.raw_height(p.x, p.y)
		if h < 1.0 or h > 8.0 or g.river_value(p.x, p.y) < bank * 1.8:
			continue
		var flat := true
		for k in 8:
			var a := TAU * k / 8.0
			var q := p + Vector2(cos(a), sin(a)) * 3.0
			if absf(g.raw_height(q.x, q.y) - h) > 0.9 or g.river_value(q.x, q.y) < bank * 1.4:
				flat = false
				break
		if not flat:
			continue
		var crowded := false
		for other: Dictionary in w.sites.values():
			if Vector2(other["center"]).distance_to(Vector2(tile)) < 18.0:
				crowded = true
				break
		if crowded:
			continue
		for other: Dictionary in g.sites.values():
			if Vector2(other["center"]).distance_to(Vector2(tile)) < 18.0 + float(other.get("flat_radius", 0)):
				crowded = true
				break
		if crowded:
			continue
		generated += 1
		if generated > 8:
			break
		for oz in range(-2, 3):
			for ox in range(-2, 3):
				w.ensure_chunk(w.chunk_key(tile + Vector2i(ox, oz)))
		var ok := true
		for oz in range(-2, 3):
			for ox in range(-2, 4):
				var t := tile + Vector2i(ox, oz)
				if not w.is_walkable(t) or w.blocked_at(t) or w.farm.has(t):
					ok = false
		if ok:
			return tile
	return NOWHERE


# --- slots --------------------------------------------------------------------------------------

## Re-fills every generated chunk of a dungeon slot after its dungeon appeared or vanished.
func refresh_slot(slot: int) -> void:
	var z := zone()
	var x0 := z.position.x + slot * DungeonZone.PITCH
	for key: Vector2i in w.chunks.keys():
		var o := key * World.S
		if o.x + World.S <= x0 or o.x >= x0 + DungeonZone.PITCH or not w.gen.in_zone_chunk(key.x, key.y):
			continue
		var ch: ChunkData = w.chunks[key]
		DungeonZone.fill_chunk(ch, z, floor_lookup())
		w._nav_update_chunk(ch)
		w.chunk_changed.emit(key)


## Registers the generation record of every saved dungeon (called before chunks are rebuilt).
func after_load() -> void:
	rebuild_slots()
	for st: Dictionary in entrances():
		var ids: Array = []
		for id: Variant in st.get("floor_sids", []):
			ids.append(int(id))
		st["floor_sids"] = ids
		for key: String in ["difficulty", "floors", "slot", "spawn_day", "cleared_day"]:
			st[key] = int(st.get(key, 0))
		w.gen.sites[int(st["id"])] = _gen_record(st)
	for fst: Dictionary in w.sites.values():
		if str(fst.get("kind", "")) == "dungeon_floor":
			for key: String in ["dungeon", "floor", "boss_id", "cleared_day"]:
				fst[key] = int(fst.get(key, -1))


# --- floors -------------------------------------------------------------------------------------

## Creates the floor's site, its enemies and its chests the first time somebody arrives.
func ensure_floor(eid: int, floor_index: int) -> int:
	var st: Dictionary = w.sites[eid]
	var ids: Array = st["floor_sids"]
	if int(ids[floor_index]) >= 0:
		return int(ids[floor_index])
	var lay := layout(eid, floor_index)
	var origin := floor_origin(eid, floor_index)
	var fid := eid + 1 + floor_index
	var theme := str(st["theme"])
	var difficulty := int(st["difficulty"])
	var level := floor_level(difficulty, floor_index)
	var center := origin + DungeonZone.FLOOR_SIZE / 2 * Vector2i.ONE
	var fst := {
		"id": fid, "kind": "dungeon_floor", "center": center, "name": "%s B%dF" % [st["name"], floor_index + 1],
		"faction": "machines" if theme == "machines" else "bandits", "hostile": true, "level": level,
		"discovered": true, "cleared": false, "looted": false, "units": [], "cache": [], "cache_gold": 0,
		"extra": [], "next_patrol": w.tick_count + 600, "next_raid_day": 99999, "cleared_day": 0, "icon": "",
		"dungeon": eid, "floor": floor_index, "boss_id": -1,
	}
	w.sites[fid] = fst
	ids[floor_index] = fid
	# the floor's chunks (36x36 tiles span up to 4 x 4 chunks)
	for oz in range(-1, DungeonZone.FLOOR_SIZE / World.S + 2):
		for ox in range(-1, DungeonZone.FLOOR_SIZE / World.S + 2):
			w.ensure_chunk(w.chunk_key(origin + Vector2i(ox * World.S, oz * World.S)))
	_populate(st, fst, lay, origin, theme, difficulty, floor_index, level)
	floor_created.emit(eid, floor_index)
	w.site_changed.emit(fid)
	return fid


func _cell_in_room(rng: RandomNumberGenerator, origin: Vector2i, room: Rect2i) -> Vector2:
	var x := rng.randi_range(room.position.x + 1, room.end.x - 2)
	var z := rng.randi_range(room.position.y + 1, room.end.y - 2)
	return Vector2(origin + Vector2i(x, z)) + Vector2(0.5, 0.5)


func _populate(st: Dictionary, fst: Dictionary, lay: Dictionary, origin: Vector2i, theme: String,
		difficulty: int, floor_index: int, level: int) -> void:
	var rng := RngUtil.make([w.seed, "dungeon_pop", int(st["id"]), floor_index])
	var last: bool = lay["last"]
	var rooms: Array = lay["rooms"]
	for room_index: int in lay["spawn_rooms"]:
		var room: Rect2i = rooms[room_index]
		var boss_room := last and room_index == int(lay["boss_room"])
		var count := 1 + (1 if room.get_area() >= 40 else 0)
		if difficulty >= 3 and rng.randf() < 0.6:
			count += 1
		if floor_index >= 3 and rng.randf() < 0.4:
			count += 1
		if boss_room:
			count = 2 + difficulty / 2
		for k in count:
			var kind := "ranged" if rng.randf() < 0.3 else "melee"
			_spawn_monster(fst, theme, kind, level + (1 if boss_room else 0), _cell_in_room(rng, origin, room), rng)
	# chests in the side rooms
	var chest_luck := 0.12 * difficulty + 0.06 * floor_index
	for cell: Vector2i in lay["chests"]:
		var items := ItemGen.loot(rng, level, chest_luck, 1 + (1 if difficulty >= 3 else 0))
		if rng.randf() < 0.08 + 0.025 * difficulty:
			items.append(ItemGen.relic(rng, theme, level, difficulty))
		w.drop_loot(Vector2(origin + cell) + Vector2(0.5, 0.5), items, rng.randi_range(6, 14) * (difficulty + floor_index / 2))
	if last:
		var room: Rect2i = rooms[int(lay["boss_room"])]
		var boss_pos := Vector2(origin + room.position + room.size / 2) + Vector2(0.5, 0.5)
		var boss := _spawn_boss(fst, theme, difficulty, level + 2, boss_pos)
		fst["boss_id"] = boss.id


func _tag(u: Unit, fst: Dictionary, pos: Vector2) -> Unit:
	u.home_site = int(fst["id"])
	u.guard_pos = pos
	u.visible = false
	(fst["units"] as Array).append(u.id)
	return u


func _spawn_monster(fst: Dictionary, theme: String, kind: String, level: int, pos: Vector2, rng: RandomNumberGenerator) -> Unit:
	var u: Unit
	match theme:
		"machines":
			u = CharacterFactory.make_machine(w, "war_drone" if kind == "ranged" else "sentry", "machines", pos, level)
		"brigands":
			u = CharacterFactory.make_npc(w, "bandit_archer" if kind == "ranged" else "bandit", "bandits", pos, level)
		_:
			var races: Array = THEME_RACES[theme]
			var race: String = races[rng.randi_range(0, races.size() - 1)]
			u = CharacterFactory.make_person(w, {"level": level, "race": race,
				"role": "archer" if kind == "ranged" else "mercenary"}, pos, "bandits",
				"bandit_archer" if kind == "ranged" else "bandit")
			u.dna["faction_style"] = "neutral"  # painted as their own people, not as bandits
	return _tag(u, fst, pos)


func _spawn_boss(fst: Dictionary, theme: String, difficulty: int, level: int, pos: Vector2) -> Unit:
	return _tag(w.giants.make_master(theme, difficulty, level, pos), fst, pos)


# --- moving between levels ---------------------------------------------------------------------

func _spot_near(eid: int, floor_index: int, anchor: Vector2, index: int) -> Vector2:
	var t := Vector2i(int(floor(anchor.x)), int(floor(anchor.y))) + Vector2i(index % 3 - 1, index / 3)
	var good := w.nearest_walkable(t, 5)
	if good.x == -99999:
		return anchor
	return Vector2(good) + Vector2(0.5, 0.5)


func _place_units(units: Array, anchor: Vector2) -> void:
	var i := 0
	for u: Unit in units:
		var p := _spot_near(0, 0, anchor, i)
		u.pos = p
		u.prev_pos = p
		w.stop_unit(u)
		u.target_id = -1
		if u.state != Unit.State.DOWNED:
			u.state = Unit.State.IDLE
		i += 1
	w.reveal(anchor, 11.0)


## Takes the units into a floor. `from_below` = arriving by the down stairs of the floor above
## means standing at this floor's up stairs; arriving from the floor below puts them at its down stairs.
func _transfer(units: Array, eid: int, floor_index: int, from_below: bool) -> void:
	ensure_floor(eid, floor_index)
	var lay := layout(eid, floor_index)
	var anchor := to_world(eid, floor_index, lay["down"] if from_below else lay["up"])
	anchor += Vector2(0.0, 1.2)
	_place_units(units, anchor)
	relocated.emit(anchor, eid, floor_index)


func enter(units: Array, eid: int) -> bool:
	var st: Dictionary = w.sites.get(eid, {})
	if st.is_empty() or str(st.get("kind", "")) != "dungeon":
		return false
	_transfer(units, eid, 0, false)
	w.notify_key("sim.dungeon.entered", {"site_name": st["name"], "floor": 1, "floors": int(st["floors"])},
		"discover", Vector2(st["center"]) + Vector2(0.5, 0.5), {"site": eid})
	return true


func leave(units: Array, eid: int) -> void:
	var st: Dictionary = w.sites.get(eid, {})
	if st.is_empty():
		return
	var anchor := gate_pos(st) + Vector2(0.0, 0.8)
	_place_units(units, anchor)
	relocated.emit(anchor, eid, -1)


## Stairs: `dir` "down" goes to the next floor, "up" to the previous one (or out at floor 0).
func use_stairs(units: Array, eid: int, floor_index: int, dir: String) -> bool:
	var st: Dictionary = w.sites.get(eid, {})
	if st.is_empty():
		return false
	if dir == "up":
		if floor_index == 0:
			leave(units, eid)
			return true
		_transfer(units, eid, floor_index - 1, true)
		_announce(st, floor_index - 1)
		return true
	if floor_index + 1 >= int(st["floors"]):
		return false
	_transfer(units, eid, floor_index + 1, false)
	_announce(st, floor_index + 1)
	return true


func _announce(st: Dictionary, floor_index: int) -> void:
	w.notify_key("sim.dungeon.floor", {"site_name": st["name"], "floor": floor_index + 1, "floors": int(st["floors"])},
		"info", null, {"site": int(st["id"])})


## A squad (or its delegated behaviour) reached stairs or the gate: move everybody.
func transfer_squad(s: Squad, eid: int, floor_index: int, dir: String) -> void:
	var units: Array = []
	for id: int in s.members:
		var u := w.get_unit(id)
		if u != null and u.alive:
			units.append(u)
	var exiting := dir == "up" and floor_index == 0
	var entering: bool = floor_index < 0
	if entering:
		enter(units, eid)
	else:
		use_stairs(units, eid, floor_index, dir)
	var resume: Dictionary = s.mem.get("delve_resume", {})
	s.mem.erase("delve_resume")
	if exiting:
		var hurt := w.squad_ai.hp_ratio(s) < 0.85 or bool(s.mem.get("delve_exit", false))
		s.mem.erase("delve_exit")
		if hurt:
			w.squad_ai.order_squad(s, {"type": "retreat"})
		else:
			w.squad_ai.order_squad(s, {"type": "idle"})
		return
	if not resume.is_empty() and not bool(s.mem.get("delve_exit", false)):
		w.squad_ai.order_squad(s, resume)
	elif bool(s.mem.get("delve_exit", false)):
		var loc := squad_location(s)
		if not loc.is_empty():
			w.squad_ai.order_squad(s, stairs_order(int(loc["eid"]), int(loc["floor"]), "up"))
	else:
		w.squad_ai.order_squad(s, {"type": "idle"})


# --- fights and rewards -------------------------------------------------------------------------

func on_unit_killed(fst: Dictionary, t: Unit, attacker: Unit) -> void:
	var eid := int(fst["dungeon"])
	var st: Dictionary = w.sites.get(eid, {})
	if st.is_empty():
		return
	if int(fst.get("boss_id", -1)) == t.id and str(st.get("state", "open")) == "open":
		_finish(st, fst, t)
	if bool(fst["cleared"]):
		return
	for u: Unit in w.factions.site_units(int(fst["id"])):
		if w.hostile("player", u.faction):
			return
	fst["cleared"] = true
	fst["cleared_day"] = w.day
	w.notify_key("sim.dungeon.floor_cleared", {"site_name": st["name"], "floor": int(fst["floor"]) + 1},
		"good", t.pos, {"site": int(fst["id"])})
	w.site_changed.emit(int(fst["id"]))


func _roll_min_quality(rng: RandomNumberGenerator, luck: float, minimum: String) -> String:
	var rolled := ItemGen.roll_quality(rng, luck)
	var have := int(DB.get_def("items/qualities", rolled).get("tier", 2))
	var want := int(DB.get_def("items/qualities", minimum).get("tier", 2))
	return rolled if have >= want else minimum


## The dungeon's master fell: the prize chest, the notification, and the dungeon starts to close.
func _finish(st: Dictionary, fst: Dictionary, boss: Unit) -> void:
	var difficulty := int(st["difficulty"])
	var level := floor_level(difficulty, int(st["floors"]) - 1) + 2
	var rng := RngUtil.make([w.seed, "dungeon_prize", int(st["id"])])
	var minimum: String = MIN_CHEST_QUALITY[clampi(difficulty - 1, 0, MIN_CHEST_QUALITY.size() - 1)]
	var items: Array = [ItemGen.relic(rng, str(st["theme"]), level, difficulty), ItemGen.trophy("master_core", level)]
	for i in 2 + difficulty:
		var quality := _roll_min_quality(rng, 0.5 * difficulty, minimum if i == 0 else "common")
		items.append(ItemGen.generate(rng, {"level": level, "luck": 0.5 * difficulty, "quality": quality, "source": "boss"}))
	w.drop_loot(boss.pos + Vector2(0.0, 0.8), items, 40 * difficulty)
	st["state"] = "cleared"
	st["cleared"] = true
	st["cleared_day"] = w.day
	w.counters["dungeons_cleared"] = int(w.counters.get("dungeons_cleared", 0)) + 1
	w.notify_key("sim.dungeon.cleared", {"site_name": st["name"]}, "good", boss.pos, {"site": int(st["id"])})
	w.site_changed.emit(int(st["id"]))


## The dungeon closes: its monsters and loot vanish, the slot frees up and the entrance crumbles.
func collapse(eid: int) -> void:
	var st: Dictionary = w.sites.get(eid, {})
	if st.is_empty():
		return
	for u: Unit in w.unit_list.duplicate():
		var loc := locate(u.pos)
		if loc.is_empty() or int(loc["eid"]) != eid:
			continue
		if u.is_player():
			leave([u], eid)
		else:
			w.remove_unit(u)
	var slot := int(st["slot"])
	var zr := DungeonZone.floor_rect(zone(), slot, 0)
	var column := Rect2i(zr.position, Vector2i(DungeonZone.FLOOR_SIZE, DungeonZone.PITCH * DungeonZone.ROWS))
	for id: int in w.loot_bags.keys():
		if column.has_point(Vector2i(int(floor((w.loot_bags[id]["pos"] as Vector2).x)), int(floor((w.loot_bags[id]["pos"] as Vector2).y)))):
			w.loot_bags.erase(id)
			w.loot_removed.emit(id)
	for id: Variant in st.get("floor_sids", []):
		w.sites.erase(int(id))
	for s: Dictionary in st.get("extra", []):
		var o: Vector2i = s["origin"]
		var sz: Vector2i = s["size"]
		for x in range(o.x, o.x + sz.x):
			for z in range(o.y, o.y + sz.y):
				var t := Vector2i(x, z)
				var ch := w.chunk_at_tile(t)
				if ch != null:
					ch.blocked[w._li(t)] = 0
					w._nav_update_tile(t)
	w.sites.erase(eid)
	w.gen.sites.erase(eid)
	_slot_owner[slot] = -1
	for key: String in _layouts.keys():
		if key.begins_with("%d:" % eid):
			_layouts.erase(key)
	refresh_slot(slot)
	w.site_removed.emit(eid)
	w.notify_key("sim.dungeon.collapsed", {"site_name": st["name"]}, "info", null)
