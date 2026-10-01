extends "res://tests/probe/management_ui_observer.gd"
## Uses real flight, resource exchange and merchant purchase APIs after fixture setup.

var flight_note: Dictionary = {}
var flight_phases: Dictionary = {}
var watching_flight := false
var offered_item := -1
var offered_price := 0
var merchant_gold := 0


func setup_flight(game: Game) -> void:
	setup(game)
	for resource: String in ["wood", "stone", "ore", "metal"]:
		g.world.res[resource] = 400
	g.world.res["food"] = 30
	g.world.notified.connect(func(note: Dictionary) -> void:
		if watching_flight and str(note.get("key", "")) == "sim.trade.run_returned" \
				and int(note.get("unit", -1)) == ship_id:
			flight_note = note
			watching_flight = false
			g.set_speed(0))
	watching_flight = true


func _process(_delta: float) -> void:
	if not watching_flight:
		return
	var ship := g.world.get_unit(ship_id)
	if ship and str(ship.order.get("type", "")) == "trade":
		flight_phases[str(ship.order.get("phase", ""))] = true


func flight_is_visible() -> bool:
	var ship := g.world.get_unit(ship_id)
	if ship == null or not ship.moving:
		return false
	for child in g.hud.trade_overview._list.get_children():
		if child is Label and (child as Label).text.contains(ship.name) \
				and (child as Label).text.contains(str(g.world.sites[post_id]["name"])) \
				and (child as Label).text.contains(Loc.t("trade.ui.phase_flying")):
			return true
	return false


func returned_with_readable_receipt() -> bool:
	var ship := g.world.get_unit(ship_id)
	if flight_note.is_empty() or ship == null or not ship.alive or ship.moving \
			or str(ship.order.get("type", "")) != "dock" \
			or ship.pos.distance_to(g.world.squad_ai.dock_pos()) > 2.0:
		return false
	for phase: String in ["flying", "trading", "home"]:
		if not flight_phases.has(phase):
			return false
	var result: Dictionary = flight_note.get("params", {}).get("resources", {}).get("resources", {})
	if int(result.get("metal", 0)) >= 0 or int(result.get("food", 0)) <= 0 or int(result.get("gold", 0)) <= 0:
		return false
	var rendered := Loc.message(flight_note)
	if not rendered.contains(ship.name) or not rendered.contains(str(g.world.sites[post_id]["name"])):
		return false
	for resource: String in result:
		if not rendered.contains(Loc.t(resource)) or not rendered.contains("%+d" % int(result[resource])):
			return false
	return true


func dock_merchant(dismiss: bool = true) -> void:
	# Fixture only: place a normal merchant at a completed dock, then open real stock.
	_complete_facility("sky_dock")
	g.world.factions._send_trader()
	var merchant := g.world.get_unit(g.world.factions.trader_id)
	merchant.pos = g.world.squad_ai.dock_pos()
	merchant.moving = false
	merchant.order["phase"] = "docked"
	g.world.factions._open_trade(merchant)
	g.world.res["gold"] = 500
	if dismiss:
		g.hud._dismiss_trade()
	else:
		g.hud._trade_dismissed = -2


func buy_first_merchant_item() -> void:
	var offer: Dictionary = g.world.factions.trade_offers[0]
	offered_item = int(offer["item"]["uid"])
	offered_price = int(offer["price"])
	merchant_gold = int(g.world.res["gold"])
	var button := g.hud._trade_list.get_child(0).get_child(2) as Button
	g.dbg_click(button.get_global_transform_with_canvas() * (button.size * 0.5))


func merchant_purchase_succeeded() -> bool:
	if int(g.world.res["gold"]) != merchant_gold - offered_price or g.world.factions.trade_offers.size() != 3:
		return false
	for item: Dictionary in g.world.armory:
		if int(item.get("uid", -1)) == offered_item:
			return true
	return false
