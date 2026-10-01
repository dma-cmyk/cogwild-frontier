class_name TradeOverviewPanel
extends PanelContainer
## Presentation only: all transactions and flight orders use the existing simulation APIs.

var g: Game
var hud: Hud
var _title: Label
var _close: Button
var _list: VBoxContainer
var _signature := ""
var _tab := "market"
var _tabs: Dictionary = {}
var _show_rules := false


func setup(game: Game, h: Hud) -> void:
	g = game
	hud = h
	name = "TradeOverviewPanel"
	add_theme_stylebox_override("panel", UiTheme.panel_box())
	var box := UiTheme.vbox(8)
	add_child(box)
	var head := UiTheme.hbox(8)
	_title = UiTheme.title("", 22)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_close = UiTheme.button("", "ui_close", Loc.t("Close"))
	_close.name = "CloseTradeOverview"
	_close.pressed.connect(close_window)
	head.add_child(_close)
	box.add_child(head)
	var tabs := UiTheme.hbox(6)
	for kind: String in ["market", "airship", "merchant"]:
		var button := UiTheme.button(Loc.t("trade.ui.tab." + kind))
		button.name = "TradeTab_" + kind
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void:
			_tab = kind
			refresh(true))
		tabs.add_child(button)
		_tabs[kind] = button
	box.add_child(tabs)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_list = UiTheme.vbox(8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	visible = false
	layout()


func layout() -> void:
	var screen := g.get_viewport().get_visible_rect().size
	var size_ := Vector2(minf(820.0, screen.x - 24.0), minf(760.0, screen.y - 280.0))
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -size_.x * 0.5
	offset_right = size_.x * 0.5
	offset_top = -size_.y * 0.5
	offset_bottom = size_.y * 0.5


func open() -> void:
	visible = true
	layout()
	refresh(true)
	Sfx.play(&"ui_select")


func close_window() -> void:
	visible = false


func _selected_airship() -> Unit:
	# Never substitute another ship for the actual selection.
	var u := g.focus_unit()
	if u and u.is_player() and u.alive and u.kind == "airship":
		return u
	return null


func refresh(force: bool = false) -> void:
	if not visible:
		return
	var w := g.world
	var ship := _selected_airship()
	var communities := w.diplomacy.known_communities()
	var posts: Array[Dictionary] = []
	var signature := Loc.language + _tab + str(_show_rules) + str(w.day) + str(w.res) + str(w.population())
	for st: Dictionary in communities:
		signature += str(st["id"]) + str(st.get("relation", 0)) + w.diplomacy.trade_blocker(int(st["id"]))
	for st: Dictionary in w.sites.values():
		if str(st.get("kind", "")) == "trade_post" and bool(st.get("discovered", false)):
			posts.append(st)
			signature += "post" + str(st["id"])
	for u: Unit in w.unit_list:
		if u.is_player() and u.alive and u.kind == "airship":
			signature += "ship" + str(u.id) + str(u.name)
	if ship:
		signature += str(ship.id) + airship_text(w, ship) + str(ship.squad_id) + str(ship.state) + str(ship.stats.get("cargo", 80.0))
	var merchant := w.get_unit(w.factions.trader_id)
	var docked := merchant != null and merchant.alive and str(merchant.order.get("phase", "")) == "docked"
	signature += str(w.factions.trader_id) + str(docked) + str(w.factions.trade_offers.size())
	if not force and signature == _signature:
		return
	_signature = signature
	_title.text = Loc.t("trade.ui.title")
	_close.tooltip_text = Loc.t("Close")
	for kind: String in _tabs:
		var button: Button = _tabs[kind]
		button.text = Loc.t("trade.ui.tab." + kind)
		button.modulate = UiTheme.GOLD if kind == _tab else Color.WHITE
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	match _tab:
		"market":
			_heading("trade.ui.community_title")
			_text(Loc.t("trade.ui.community_help"))
			if communities.is_empty():
				_text(Loc.t("trade.ui.no_communities"))
			for st: Dictionary in communities:
				_community(st)
		"airship":
			_airship(ship, posts)
		"merchant":
			_heading("trade.ui.merchant_title")
			_text(Loc.t("trade.ui.merchant_help"))
			_text(Loc.t("trade.ui.merchant_docked", {"count": w.factions.trade_offers.size()}) if docked
				else Loc.t("trade.ui.no_merchant"))
			var wares := _button("OpenMerchantWares", Loc.t("trade.ui.open_wares"), func() -> void:
				close_window()
				hud.show_merchant_wares())
			wares.disabled = not docked or w.factions.trade_offers.is_empty()
			_list.add_child(wares)


func _airship(ship: Unit, posts: Array[Dictionary]) -> void:
	var w := g.world
	_heading("trade.ui.airship_title")
	_text(Loc.t("trade.ui.airship_help"))
	for u: Unit in w.unit_list:
		if u.is_player() and u.alive and u.kind == "airship":
			var id := u.id
			_list.add_child(_button("SelectAirship_%d" % id,
				Loc.t("trade.ui.select_ship", {"name": u.name}), func() -> void:
					g.select_units([id])
					refresh(true)))
	_text(Loc.t("trade.ui.selected_ship", {"name": ship.name, "status": airship_text(w, ship)})
		if ship else Loc.t("trade.ui.select_ship_help"))
	if ship:
		_text(Loc.t("trade.ui.cargo", {"cargo": int(ship.stats.get("cargo", 80.0))}))
	var surplus := w.factions.surplus()
	_text(Loc.t("trade.ui.no_surplus") if surplus.is_empty() else Loc.t("trade.ui.surplus", {
		"resources": {"resources": surplus}}))
	if posts.is_empty():
		_text(Loc.t("trade.ui.no_posts"))
	posts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	var reason := _ship_blocker(ship)
	if reason != "":
		_text(reason)
	for st: Dictionary in posts:
		var sid := int(st["id"])
		var row := UiTheme.hbox(6)
		var label := UiTheme.label(str(st.get("name", "")), 15, UiTheme.GOLD)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		row.add_child(label)
		row.add_child(_button("FocusTradePost_%d" % sid, Loc.t("trade.ui.focus"), _focus_site.bind(sid)))
		var send := _button("SendAirship_%d" % sid, Loc.t("trade.ui.send_ship"), _send_ship.bind(sid))
		send.set_meta("site_id", sid)
		send.disabled = reason != ""
		row.add_child(send)
		_list.add_child(row)
	var rules := _button("TradeRules", Loc.t("trade.ui.hide_rules" if _show_rules else "trade.ui.show_rules"),
		func() -> void:
			_show_rules = not _show_rules
			refresh(true))
	_list.add_child(rules)
	if _show_rules:
		_text(Loc.t("trade.ui.reserve_rules"))
		_text(Loc.t("trade.ui.food_rules", {"food": int(w.res.get("food", 0)), "target": w.population() * 6,
			"gold": int(w.res.get("gold", 0))}))
		_text(Loc.t("trade.ui.rounding"))


func _community(st: Dictionary) -> void:
	var sid := int(st["id"])
	var blocker := g.world.diplomacy.trade_blocker(sid)
	_text(Loc.t("trade.ui.community_status", {"name": st.get("name", ""),
		"tier": Loc.t(g.world.diplomacy.tier(sid)), "relation": g.world.diplomacy.relation(sid)}), UiTheme.GOLD)
	_text(Loc.t(blocker) if blocker != "" else Loc.t("trade.ui.ready"))
	var row := UiTheme.hbox(6)
	row.add_child(_button("FocusCommunity_%d" % sid, Loc.t("trade.ui.focus"), _focus_site.bind(sid)))
	# The market remains inspectable when blocked; its transaction controls explain why.
	var market := _button("OpenMarket_%d" % sid, Loc.t("trade.ui.open_market"), func() -> void:
		close_window()
		hud.villages.open_trade(sid))
	market.set_meta("site_id", sid)
	row.add_child(market)
	_list.add_child(row)


func _ship_blocker(ship: Unit) -> String:
	if ship == null:
		return Loc.t("trade.ui.select_ship_help")
	if ship.state == Unit.State.DOWNED:
		return Loc.t("trade.ui.ship_downed")
	if ship.squad_id >= 0:
		return Loc.t("trade.ui.ship_in_squad")
	return ""


func _send_ship(sid: int) -> void:
	var ship := _selected_airship()
	var st: Dictionary = g.world.sites.get(sid, {})
	if _ship_blocker(ship) != "" or str(st.get("kind", "")) != "trade_post" or not bool(st.get("discovered", false)):
		refresh(true)
		return
	g.world.squad_ai.order_unit(ship, {"type": "trade", "site": sid, "phase": "out"})
	Sfx.play(&"ui_select")
	refresh(true)


func _focus_site(sid: int) -> void:
	var st: Dictionary = g.world.sites.get(sid, {})
	if st.is_empty():
		return
	g.select_site(sid)
	g.focus_pos(Vector2(st["center"]))
	close_window()


func _heading(key: String) -> void:
	_list.add_child(UiTheme.title(Loc.t(key), 18))


func _text(text: String, color: Color = UiTheme.TEXT_DIM) -> void:
	var label := UiTheme.label(text, 16, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(label)


func _button(node_name: String, text: String, action: Callable) -> Button:
	var button := UiTheme.button(text)
	button.name = node_name
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(action)
	return button


static func airship_text(w: World, u: Unit) -> String:
	var order := str(u.order.get("type", ""))
	if order == "trade" or (order == "auto" and str(u.order.get("sub", "")) == "trade"):
		var st: Dictionary = w.sites.get(int(u.order.get("site", -1)), {})
		var destination := str(st.get("name", "")) if bool(st.get("discovered", false)) else Loc.t("trade.ui.unknown_destination")
		var phase := str(u.order.get("phase", "out"))
		var phases := {"out": "trade.ui.phase_out", "flying": "trade.ui.phase_flying",
			"trading": "trade.ui.phase_trading", "home": "trade.ui.phase_home", "done": "trade.ui.phase_done"}
		return Loc.t("trade.ui.flight_status", {"destination": destination,
			"phase": Loc.t(str(phases.get(phase, "trade.ui.phase_out")))})
	if order == "auto":
		return Loc.t("trade.ui.auto_status")
	if order == "dock":
		return Loc.t("trade.ui.dock_status")
	if order == "":
		return Loc.t("trade.ui.idle_status")
	return Loc.t("trade.ui.other_order", {"order": Loc.t(order.capitalize())})
