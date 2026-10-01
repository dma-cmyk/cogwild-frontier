extends TestCase
## Older-than-toast events remain readable after a real JSON save/load round trip.

var _worlds: Array[World] = []


func _new() -> World:
	var world := NewGame.create(11)
	_worlds.append(world)
	world.notifications.clear()
	return world


func after_all() -> void:
	for world: World in _worlds:
		world.dispose()
	_worlds.clear()


func test_history_preserves_old_events_and_targets_across_save_load() -> void:
	var world := _new()
	for index in 120:
		world.tick_count = index
		if index % 2 == 0:
			world.notify("Record %d" % index, "info", Vector2(index, 3), {"building": world.hearth_id})
		else:
			world.notify_key("sim.trade.resource_sold", {"site_name": "Test market", "resource_id": "wood", "amount": index, "gold": 12}, "good")
	var loaded := SaveGame.from_dict(JSON.parse_string(JSON.stringify(SaveGame.to_dict(world))))
	_worlds.append(loaded)
	assert_eq(loaded.notifications.size(), 120, "history older than the previous 30-event save window remains available")
	assert_eq(str(loaded.notifications[0]["text"]), "Record 0", "oldest retained event is still readable")
	assert_eq(loaded.notifications[0]["pos"], Vector2(0, 3), "historic location remains navigable")
	assert_eq(int(loaded.notifications[0]["building"]), world.hearth_id, "historic facility target survives")
	assert_eq(int(loaded.notifications[119]["params"]["amount"]), 119, "latest transaction data survives")
	assert_eq(int(loaded.notifications[119]["tick"]), 119, "chronological order survives")


func test_history_evicts_only_oldest_events_and_continues_after_loading() -> void:
	var world := _new()
	for index in World.NOTIFICATION_LIMIT + 17:
		world.tick_count = index
		world.notify("Record %d" % index)
	assert_eq(world.notifications.size(), World.NOTIFICATION_LIMIT, "long sessions have bounded history")
	assert_eq(str(world.notifications[0]["text"]), "Record 17", "only oldest records are evicted")
	var loaded := SaveGame.from_dict(JSON.parse_string(JSON.stringify(SaveGame.to_dict(world))))
	_worlds.append(loaded)
	loaded.notify("After loading")
	assert_eq(loaded.notifications.size(), World.NOTIFICATION_LIMIT, "history remains bounded after load")
	assert_eq(str(loaded.notifications[0]["text"]), "Record 18", "next oldest record is evicted on continuation")
	assert_eq(str(loaded.notifications.back()["text"]), "After loading", "new event is appended to restored history")


func test_legacy_airship_trade_history_keeps_readable_signed_changes() -> void:
	var world := _new()
	var data := SaveGame.to_dict(world)
	data["notifications"] = [{
		"key": "sim.trade.run_returned", "kind": "good", "day": 1, "hour": 6.0,
		"params": {"unit_name": "Airship", "site_name": "Market", "resources": {"wood": -10, "gold": 5}},
	}]
	var loaded := SaveGame.from_dict(JSON.parse_string(JSON.stringify(data)))
	_worlds.append(loaded)
	var language: String = Loc.language
	for locale: String in ["en", "ja"]:
		Loc.set_language(locale, false)
		var message: String = Loc.message(loaded.notifications[0])
		assert_true(message.contains("-10") and message.contains("+5"), "historic sale retains signed quantities in " + locale)
		assert_true(message.contains(Loc.t("wood")) and message.contains(Loc.t("gold")), "historic resource types are readable in " + locale)
	Loc.set_language(language, false)
