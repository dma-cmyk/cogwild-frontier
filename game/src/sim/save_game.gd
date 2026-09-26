class_name SaveGame
extends RefCounted
## JSON save/load of the whole simulation. The terrain itself is not stored: chunks are rebuilt
## from the seed and only the player's changes (felled trees, farmland, foundations), the explored
## map and all entities are saved. Versioned; corrupt or unknown files are rejected with a reason.

const DIR := "user://saves"


static func path(slot: int) -> String:
	return "%s/slot_%d.json" % [DIR, slot]


static func _v(x: Variant) -> Variant:
	return Unit._vec_safe(x)


static func _r(x: Variant) -> Variant:
	return Unit._vec_restore(x)


static func to_dict(w: World) -> Dictionary:
	var chunks := {}
	for key: Vector2i in w.chunks:
		var ch: ChunkData = w.chunks[key]
		chunks["%d,%d" % [key.x, key.y]] = {"res": ch.mod_res, "terrain": ch.mod_terrain, "regrow": ch.regrow, "height": ch.mod_height}
	var units: Array = []
	for u: Unit in w.unit_list:
		units.append(u.to_dict())
	var buildings: Array = []
	for b: Building in w.buildings.values():
		buildings.append(b.to_dict())
	var squads: Array = []
	for s: Squad in w.squads:
		squads.append(s.to_dict())
	var zones: Array = []
	for z: Dictionary in w.zones:
		var r: Rect2i = z["rect"]
		zones.append({"id": z["id"], "type": z["type"], "rect": [r.position.x, r.position.y, r.size.x, r.size.y]})
	var farm: Array = []
	for t: Vector2i in w.farm:
		var f: Dictionary = w.farm[t]
		farm.append([t.x, t.y, int(f["stage"]), float(f["growth"]), str(f["crop"])])
	var reserved: Array = []
	for k: Variant in w.colony.reserved:
		reserved.append([_v(k), w.colony.reserved[k]])
	var queue: Array = []
	for k: Vector2i in w._chunk_queue:
		queue.append([k.x, k.y])
	return {
		"version": World.SAVE_VERSION, "saved_at": Time.get_datetime_string_from_system(),
		"seed": w.seed, "tick": w.tick_count, "day": w.day, "rng_state": str(w.rng.state), "next_id": w.next_id,
		"company": w.company_name, "faction_color": w.faction_color.to_html(false),
		"player_unit": w.player_unit_id, "hearth": w.hearth_id,
		"res": w.res, "armory": w.armory, "priorities": w.priorities, "counters": w.counters, "hungry": w.hungry,
		"explored": Marshalls.raw_to_base64(w.explored.compress(FileAccess.COMPRESSION_ZSTD)), "explored_count": w.explored_count,
		"chunks": chunks, "chunk_queue": queue, "units": units, "buildings": buildings, "squads": squads,
		"sites": _v(w.sites), "loot": _v(w.loot_bags), "zones": zones, "farm": farm,
		"notifications": _v(w.notifications.slice(maxi(0, w.notifications.size() - 30))),
		"colony": {"reserved": reserved, "blacklist": w.colony._blacklist},
		"combat": {"projectiles": _v(w.combat.projectiles)},
		"economy": {"snapshots": w.economy._snapshots, "energy_frac": w.economy._energy_frac},
		"factions": {"trader_day": w.factions.trader_day, "trade_offers": w.factions.trade_offers,
			"trader_id": w.factions.trader_id, "raid_announced": w.factions._raid_announced.keys()},
	}


static func from_dict(d: Dictionary) -> World:
	var w := World.new()
	w.setup(int(d["seed"]))
	w.tick_count = int(d["tick"])
	w.day = int(d["day"])
	w.rng.state = int(str(d["rng_state"]))
	w.next_id = int(d["next_id"])
	w.company_name = str(d.get("company", "Frontier Company"))
	w.faction_color = Color(str(d.get("faction_color", "3a5da8")))
	w.player_unit_id = int(d.get("player_unit", -1))
	w.hearth_id = int(d.get("hearth", -1))
	for k: String in d["res"]:
		w.res[k] = int(d["res"][k])
	w.armory = d.get("armory", [])
	for k: String in d.get("priorities", {}):
		w.priorities[k] = int(d["priorities"][k])
	w.counters = d.get("counters", {})
	w.hungry = bool(d.get("hungry", false))
	var raw := Marshalls.base64_to_raw(str(d["explored"]))
	w.explored = raw.decompress(w.W * w.W, FileAccess.COMPRESSION_ZSTD)
	if w.explored.size() != w.W * w.W:
		push_error("SaveGame: explored map has the wrong size")
		w.explored.resize(w.W * w.W)
	w.explored_count = int(d.get("explored_count", 0))
	w.refresh_fog_image()
	w.sites = _r(d.get("sites", {}))
	var fixed_sites := {}
	for k: Variant in w.sites:
		fixed_sites[int(k)] = w.sites[k]
		var st: Dictionary = w.sites[k]
		st["id"] = int(st["id"])
		st["level"] = int(st["level"])
		var ids: Array = []
		for id: Variant in st.get("units", []):
			ids.append(int(id))
		st["units"] = ids
	w.sites = fixed_sites
	for bd: Dictionary in d.get("buildings", []):
		var b := Building.from_dict(bd)
		w.buildings[b.id] = b
	for z: Dictionary in d.get("zones", []):
		var r: Array = z["rect"]
		w.zones.append({"id": int(z["id"]), "type": str(z["type"]), "rect": Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))})
	for f: Array in d.get("farm", []):
		w.farm[Vector2i(int(f[0]), int(f[1]))] = {"stage": int(f[2]), "growth": float(f[3]), "crop": str(f[4])}
	for key_str: String in d.get("chunks", {}):
		var parts := key_str.split(",")
		w._pending_mods[Vector2i(int(parts[0]), int(parts[1]))] = d["chunks"][key_str]
	for key: Vector2i in w._pending_mods.keys():
		w.ensure_chunk(key)
	w.recount_explored()
	for q: Array in d.get("chunk_queue", []):
		w._chunk_queue.append(Vector2i(int(q[0]), int(q[1])))
	for ud: Dictionary in d.get("units", []):
		var u := Unit.from_dict(ud)
		w.units[u.id] = u
		w.unit_list.append(u)
	for sd: Dictionary in d.get("squads", []):
		w.squads.append(Squad.from_dict(sd))
	var bags: Dictionary = _r(d.get("loot", {}))
	for k: Variant in bags:
		var bag: Dictionary = bags[k]
		bag["id"] = int(bag["id"])
		w.loot_bags[int(k)] = bag
	w.notifications = _r(d.get("notifications", []))
	var col: Dictionary = d.get("colony", {})
	for pair: Array in col.get("reserved", []):
		var key: Variant = _r(pair[0])
		if key is Array:
			key = [str(key[0]), int(key[1])]
		w.colony.reserved[key] = int(pair[1])
	for k: String in col.get("blacklist", {}):
		w.colony._blacklist[k] = int(col["blacklist"][k])
	for p: Dictionary in _r(d.get("combat", {}).get("projectiles", [])):
		p["target"] = int(p["target"])
		p["attacker"] = int(p["attacker"])
		w.combat.projectiles.append(p)
	var eco: Dictionary = d.get("economy", {})
	w.economy._snapshots = eco.get("snapshots", [])
	for snap: Dictionary in w.economy._snapshots:
		snap["tick"] = int(snap["tick"])
	w.economy._energy_frac = float(eco.get("energy_frac", 0.0))
	var fac: Dictionary = d.get("factions", {})
	w.factions.trader_day = int(fac.get("trader_day", 3))
	w.factions.trade_offers = fac.get("trade_offers", [])
	w.factions.trader_id = int(fac.get("trader_id", -1))
	for sid: Variant in fac.get("raid_announced", []):
		w.factions._raid_announced[int(sid)] = true
	return w


static func save(w: World, slot: int) -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(path(slot), FileAccess.WRITE)
	if f == null:
		return "Cannot write %s (%s)" % [path(slot), error_string(FileAccess.get_open_error())]
	f.store_string(JSON.stringify(to_dict(w)))
	f.close()
	return ""


## Loads a slot. Returns {"world": World} or {"error": reason}.
static func load_slot(slot: int) -> Dictionary:
	if not FileAccess.file_exists(path(slot)):
		return {"error": "Empty slot"}
	return parse(FileAccess.get_file_as_string(path(slot)))


static func parse(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		return {"error": "Save file is damaged"}
	var d: Dictionary = json.data
	if int(d.get("version", 0)) != World.SAVE_VERSION:
		return {"error": "Unsupported save version %s" % str(d.get("version", "?"))}
	for k: String in ["seed", "tick", "units", "buildings", "explored", "res"]:
		if not d.has(k):
			return {"error": "Save file is incomplete (%s)" % k}
	return {"world": from_dict(d)}


## Slot summary for menus: {"exists", "day", "company", "saved_at", "population"}.
static func info(slot: int) -> Dictionary:
	if not FileAccess.file_exists(path(slot)):
		return {"exists": false}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path(slot))) != OK or not (json.data is Dictionary):
		return {"exists": true, "damaged": true}
	var d: Dictionary = json.data
	var pop := 0
	for u: Dictionary in d.get("units", []):
		if str(u.get("faction", "")) == "player" and str(u.get("kind", "")) == "character" and bool(u.get("alive", true)):
			pop += 1
	return {"exists": true, "day": int(d.get("day", 1)), "company": str(d.get("company", "")), "saved_at": str(d.get("saved_at", "")), "population": pop}
