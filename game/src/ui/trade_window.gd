class_name TradeWindow
extends PanelContainer
## Village market: buy and sell colony resources and the race's specialty goods.
## Prices follow the relation tier and the stock refreshes every morning.

const AMOUNTS := [1, 10, 50]

var g: Game
var hud: Hud
var site_id := -1
var _amount := 10
var _list: VBoxContainer
var _title: Label
var _subtitle: Label
var _gold: Label
var _amount_buttons: Array[Button] = []
var _signature := ""
var _amount_label: Label
var _outcome: Label
var _last_outcome: Dictionary = {}
var _last_failed := false
var _close: Button


func setup(game: Game, h: Hud) -> void:
	g = game
	hud = h
	name = "TradeWindow"
	add_theme_stylebox_override("panel", UiTheme.panel_box())
	var v := UiTheme.vbox(6)
	add_child(v)
	var head := UiTheme.hbox(8)
	_title = UiTheme.title(Loc.t("Trade"), 22)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	head.add_child(_title)
	_gold = UiTheme.label("", 16, UiTheme.GOLD, UiTheme.bold_font)
	head.add_child(UiTheme.icon("res_gold", 24))
	head.add_child(_gold)
	_close = UiTheme.button("", "ui_close", Loc.t("Close"))
	_close.name = "CloseTradeWindow"
	_close.pressed.connect(close_window)
	head.add_child(_close)
	v.add_child(head)
	_subtitle = UiTheme.label("", 14, UiTheme.TEXT_DIM)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_subtitle)
	var amounts := UiTheme.hbox(4)
	_amount_label = UiTheme.label("", 14, UiTheme.GOLD)
	amounts.add_child(_amount_label)
	for value: int in AMOUNTS:
		var b := UiTheme.button(str(value))
		b.name = "TradeAmount%d" % value
		b.custom_minimum_size = Vector2(52, 30)
		b.add_theme_font_size_override("font_size", 14)
		var amount := value
		b.pressed.connect(func() -> void:
			_amount = amount
			refresh(true))
		amounts.add_child(b)
		_amount_buttons.append(b)
	v.add_child(amounts)
	_outcome = UiTheme.label("", 14)
	_outcome.name = "TradeOutcome"
	_outcome.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_outcome)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	_list = UiTheme.vbox(4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	visible = false
	layout()


func layout() -> void:
	var screen := g.get_viewport().get_visible_rect().size
	var w := minf(800.0, screen.x - 24.0)
	var h := minf(720.0, screen.y - 280.0)
	set_anchors_preset(Control.PRESET_CENTER)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -w * 0.5
	offset_right = w * 0.5
	offset_top = -h * 0.5
	offset_bottom = h * 0.5


func open(sid: int) -> void:
	site_id = sid
	_last_outcome.clear()
	_signature = ""
	layout()
	visible = true
	refresh(true)
	Sfx.play(&"ui_select")


func close_window() -> void:
	visible = false
	site_id = -1


func refresh(force: bool = false) -> void:
	if not visible:
		return
	var world := g.world
	var st: Dictionary = world.sites.get(site_id, {})
	if st.is_empty() or not world.diplomacy.is_community(st):
		close_window()
		return
	var blocker := world.diplomacy.trade_blocker(site_id)
	# Refresh the model's daily stock before reading availability into the signature.
	world.diplomacy.stock_of(site_id)
	var signature := "%d:%d:%d:%s:%d:%d:%d:%s" % [site_id, int(st.get("relation", 0)), _amount, blocker,
		int(world.res.get("gold", 0)), int(st.get("purse", 0)), world.day, Loc.language]
	for resource: String in Diplomacy.TRADE_RESOURCES:
		signature += ":%d/%d" % [int(world.res.get(resource, 0)),
			int((st.get("stock", {}) as Dictionary).get(resource, 0))]
	for row: Dictionary in st.get("goods", []):
		signature += ":%s%d" % [str(row.get("base", "")), int(row.get("count", 0))]
	if signature == _signature and not force:
		return
	_signature = signature
	_rebuild(st, blocker)


func _rebuild(st: Dictionary, blocker: String) -> void:
	var world := g.world
	var dip := world.diplomacy
	var tier := Diplomacy.tier_for(int(st.get("relation", 0)))
	_title.text = str(st["name"])
	_gold.text = str(int(world.res.get("gold", 0)))
	_close.tooltip_text = Loc.t("Close")
	_amount_label.text = Loc.t("trade.ui.amount", {"amount": _amount})
	_subtitle.text = Loc.t("trade.ui.market_status", {"tier": Loc.t(tier),
		"purse": int(st.get("purse", 0)), "day": world.day})
	if blocker != "":
		_subtitle.text += "\n" + Loc.t(blocker)
	_outcome.text = Loc.message(_last_outcome) if not _last_outcome.is_empty() else ""
	_outcome.visible = not _last_outcome.is_empty()
	_outcome.add_theme_color_override("font_color", UiTheme.GOLD if _last_failed else UiTheme.TEXT)
	for i in _amount_buttons.size():
		_amount_buttons[i].add_theme_stylebox_override("normal",
			UiTheme.button_box("pressed" if AMOUNTS[i] == _amount else "normal"))
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var stock: Dictionary = dip.stock_of(site_id)
	_list.add_child(UiTheme.label(Loc.t("Resources"), 15, UiTheme.GOLD))
	for resource: String in Diplomacy.TRADE_RESOURCES:
		_list.add_child(_resource_row(resource, int(stock.get(resource, 0)), blocker))
	var goods: Array = dip.goods_of(site_id)
	if not goods.is_empty():
		_list.add_child(UiTheme.label(Loc.t("Specialties"), 15, UiTheme.GOLD))
		for row: Dictionary in goods:
			_list.add_child(_goods_row(row, blocker))


func _resource_row(resource: String, their_stock: int, blocker: String) -> Control:
	var world := g.world
	var dip := world.diplomacy
	var own := int(world.res.get(resource, 0))
	var gold := int(world.res.get("gold", 0))
	var purse := int(world.sites[site_id].get("purse", 0))
	var cost := dip.buy_price(site_id, resource, _amount)
	var payout := dip.sell_price(site_id, resource, _amount)
	var box := UiTheme.vbox(3)
	box.name = "Resource_" + resource
	box.add_child(UiTheme.label(Loc.t("trade.ui.inventory", {"resource": Loc.t(resource),
		"own": own, "stock": their_stock}), 15, UiTheme.GOLD))
	var row := UiTheme.hbox(8)
	var buy_reason := Loc.t(blocker) if blocker != "" else ""
	if buy_reason == "" and their_stock < _amount:
		buy_reason = Loc.t("trade.ui.stock_short", {"stock": their_stock, "amount": _amount})
	elif buy_reason == "" and gold < cost:
		buy_reason = Loc.t("trade.ui.gold_short", {"gold": gold, "price": cost})
	var sell_reason := Loc.t(blocker) if blocker != "" else ""
	if sell_reason == "" and own < _amount:
		sell_reason = Loc.t("trade.ui.inventory_short", {"own": own, "amount": _amount})
	elif sell_reason == "" and their_stock + _amount > Diplomacy.STOCK_LIMIT:
		sell_reason = Loc.t("trade.ui.capacity_short", {"space": maxi(0, Diplomacy.STOCK_LIMIT - their_stock),
			"amount": _amount, "limit": Diplomacy.STOCK_LIMIT})
	elif sell_reason == "" and purse < payout:
		sell_reason = Loc.t("trade.ui.purse_short", {"purse": purse, "price": payout})
	var params := {"resource": Loc.t(resource), "amount": _amount, "price": cost}
	row.add_child(_action("Buy_" + resource, Loc.t("trade.ui.buy", params), buy_reason,
		func() -> void: _trade(resource, true)))
	params["price"] = payout
	row.add_child(_action("Sell_" + resource, Loc.t("trade.ui.sell", params), sell_reason,
		func() -> void: _trade(resource, false)))
	box.add_child(row)
	return box


func _action(node_name: String, text: String, reason: String, action: Callable) -> Control:
	var box := UiTheme.vbox(2)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var button := UiTheme.button(text)
	button.name = node_name
	button.custom_minimum_size = Vector2(0, 34)
	button.add_theme_font_size_override("font_size", 14)
	button.disabled = reason != ""
	button.pressed.connect(action)
	box.add_child(button)
	var label := UiTheme.label(reason, 13, UiTheme.TEXT_DIM)
	label.name = node_name + "Reason"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.visible = reason != ""
	box.add_child(label)
	return box


func _goods_row(row: Dictionary, blocker: String) -> Control:
	var world := g.world
	var item: Dictionary = row.get("item", {})
	var base := str(row.get("base", ""))
	var count := int(row.get("count", 0))
	var price := world.diplomacy.specialty_price(site_id, item)
	var h := UiTheme.hbox(6)
	var ic := TextureRect.new()
	ic.texture = Icons.item_icon(item, 48)
	ic.custom_minimum_size = Vector2(36, 36)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	h.add_child(ic)
	var nm := UiTheme.label("%s  x%d" % [Loc.item_name(item), count], 15,
		Icons.quality_color(str(item.get("quality", "common"))))
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	nm.tooltip_text = "\n".join(ItemGen.describe(item))
	nm.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(nm)
	var reason := Loc.t(blocker) if blocker != "" else ""
	if reason == "" and count <= 0:
		reason = Loc.t("The village has sold out.")
	elif reason == "" and int(world.res.get("gold", 0)) < price:
		reason = Loc.t("trade.ui.gold_short", {"gold": int(world.res.get("gold", 0)), "price": price})
	var buy := _action("Specialty_" + base,
		Loc.t("trade.ui.buy_item", {"price": price}), reason, func() -> void:
			var actual_price := g.world.diplomacy.specialty_price(site_id, item)
			_report(g.world.diplomacy.buy_specialty(site_id, base),
				{"key": "trade.ui.item_bought", "params": {"item": {"item": item}, "price": actual_price}}))
	h.add_child(buy)
	return h


func _trade(resource: String, buying: bool) -> void:
	var dip := g.world.diplomacy
	var price := dip.buy_price(site_id, resource, _amount) if buying else dip.sell_price(site_id, resource, _amount)
	_report(dip.resource_trade(site_id, resource, _amount, buying),
		{"key": "trade.ui.bought" if buying else "trade.ui.sold", "params": {
			"resource_id": resource, "amount": _amount, "price": price}})


func _report(error: String, success: Dictionary) -> void:
	_last_failed = error != ""
	_last_outcome = {"key": "trade.ui.failed", "params": {"reason": {"key": error}}} if _last_failed else success
	if not _last_failed:
		Sfx.play(&"coin")
	refresh(true)
	hud.info_panel.refresh(true)
