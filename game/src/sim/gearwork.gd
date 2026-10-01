class_name Gearwork
extends RefCounted
## Forge trophies, salvage surplus, maintain and improve owned equipment. No random upgrades:
## payment and consumption happen only after all prerequisites pass; item uid stays stable.
const MAX_UPGRADE := 3
var w: World

func _init(world: World) -> void:
	w = world


func available(sid: int = -1) -> bool:
	if sid >= 0:
		return w.town.service_blocker(sid) == ""
	for b: Building in w.buildings.values():
		if b.type == "workshop" and b.faction == "player" and b.is_built():
			return true
	return false


func owned(uid: int) -> Dictionary:
	for item: Dictionary in w.armory:
		if int(item.get("uid", 0)) == uid:
			return item
	for u: Unit in w.unit_list:
		if not u.alive or not u.is_player():
			continue
		for it: Variant in u.equipment().values():
			if it is Dictionary and int(it.get("uid", 0)) == uid:
				return it
	return {}


func cost(item: Dictionary, action: String) -> Dictionary:
	var level := maxi(1, int(item.get("level", 1)))
	var upgrades := int(item.get("upgrade", 0))
	if action == "repair":
		var wear := 100.0 - float(item.get("condition", 100.0))
		return {"metal": maxi(1, ceili(wear / 20.0)), "gold": ceili(wear * level * 0.08)}
	return {"metal": (4 + level) * (upgrades + 1), "gold": (10 + level * 3) * (upgrades + 1)}


func act(uid: int, action: String, sid: int = -1) -> String:
	if not available(sid):
		return "gear.error.workshop"
	var item := owned(uid)
	if item.is_empty():
		return "gear.error.item"
	if action == "dismantle":
		# Equipped gear is never destroyed by a stale armory button.
		if not w.armory.has(item):
			return "gear.error.equipped"
		w.armory.erase(item)
		w.economy.add("metal", maxi(1, int(item.get("level", 1)) + int(DB.get_def("items/qualities", str(item.get("quality", "common"))).get("tier", 2))))
	elif action in ["repair", "upgrade"]:
		if str(item.get("category", "")) not in ["weapon", "armor", "gadget", "artifact", "robot_part", "airship_part", "tool"]:
			return "gear.error.item"
		if action == "repair" and float(item.get("condition", 100.0)) >= 100.0:
			return "gear.error.pristine"
		if action == "upgrade" and int(item.get("upgrade", 0)) >= MAX_UPGRADE:
			return "gear.error.max"
		var payment := cost(item, action)
		if not w.economy.pay(payment):
			return "gear.error.resources"
		if action == "repair":
			item["condition"] = 100.0
		else:
			item["upgrade"] = int(item.get("upgrade", 0)) + 1
			var stats: Dictionary = item.get("stats", {})
			for key: String in ["damage", "armor", "max_hp", "carry", "power"]:
				if stats.has(key):
					stats[key] = snappedf(float(stats[key]) * 1.1, 0.01)
			var mods: Dictionary = item.get("mods", {})
			for key: String in mods:
				mods[key] = snappedf(float(mods[key]) * 1.1, 0.001)
			item["value"] = int(ceil(float(item.get("value", 1)) * 1.1))
		_refresh_wearer(uid)
	else:
		return "gear.error.item"
	w.notify_key("gear.done." + action, {"item": item}, "loot")
	return ""


func forge(theme: String, sid: int = -1) -> String:
	if not available(sid):
		return "gear.error.workshop"
	if theme not in Dungeons.THEMES and theme != "wilds":
		return "gear.error.item"
	var component := "colossus_antler" if theme == "wilds" else "master_core"
	var trophy: Dictionary = {}
	for it: Dictionary in w.armory:
		if str(it.get("base", "")) == component:
			trophy = it
			break
	if trophy.is_empty():
		return "gear.error.trophy"
	if not w.economy.pay({"metal": 18, "gold": 45}):
		return "gear.error.resources"
	w.armory.erase(trophy)
	var rng := RngUtil.make([w.seed, "forge", int(trophy["uid"]), theme])
	var item := ItemGen.relic(rng, theme, int(trophy["level"]), 2)
	item["uid"] = w.new_id()
	w.armory.append(item)
	w.notify_key("gear.done.forge", {"item": item}, "loot")
	return ""


func _refresh_wearer(uid: int) -> void:
	for u: Unit in w.unit_list:
		if not u.alive or not u.is_player():
			continue
		for it: Variant in u.equipment().values():
			if it is Dictionary and int(it.get("uid", 0)) == uid:
				u.recompute_stats()
				w.unit_changed.emit(u)
