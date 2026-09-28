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
	var close := UiTheme.button("", "ui_close", Loc.t("Close"))
	close.pressed.connect(close_window)
	head.add_child(close)
	v.add_child(head)
	_subtitle = UiTheme.label("", 14, UiTheme.TEXT_DIM)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_subtitle)
	var amounts := UiTheme.hbox(4)
	amounts.add_child(UiTheme.label(Loc.t("Amount"), 14, UiTheme.GOLD))
	for value: int in AMOUNTS:
		var b := UiTheme.button(str(value))
		b.custom_minimum_size = Vector2(52, 30)
		b.add_theme_font_size_override("font_size", 14)
		var amount := value
		b.pressed.connect(func() -> void:
			_amount = amount
			refresh(true))
		amounts.add_child(b)
		_amount_buttons.append(b)
	v.add_child(amounts)
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
	var w := minf(640.0, screen.x - 24.0)
	var h := minf(460.0, screen.y - 88.0)
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
	var signature := "%d:%d:%d:%s:%d" % [site_id, int(st.get("relation", 0)), _amount, blocker,
		int(world.res.get("gold", 0))]
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
	_subtitle.text = Loc.t(blocker) if blocker != "" else Loc.t("%s prices · their purse %d gold") \
		% [Loc.t(tier), int(st.get("purse", 0))]
	for i in _amount_buttons.size():
		_amount_buttons[i].add_theme_stylebox_override("normal",
			UiTheme.button_box("pressed" if AMOUNTS[i] == _amount else "normal"))
	for c in _list.get_children():
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
	var h := UiTheme.hbox(6)
	h.add_child(UiTheme.icon("res_" + resource, 24))
	var nm := UiTheme.label(Loc.t(resource).capitalize(), 15)
	nm.custom_minimum_size = Vector2(76, 0)
	h.add_child(nm)
	var have := UiTheme.label("%d / %d" % [int(world.res.get(resource, 0)), their_stock], 14, UiTheme.TEXT_DIM)
	have.custom_minimum_size = Vector2(88, 0)
	have.tooltip_text = Loc.t("Yours / theirs")
	have.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(have)
	var buy := UiTheme.button(Loc.t("Buy %d") % dip.buy_price(site_id, resource, _amount), "res_gold")
	buy.custom_minimum_size = Vector2(112, 32)
	buy.add_theme_font_size_override("font_size", 13)
	buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy.disabled = blocker != "" or their_stock < _amount \
		or int(world.res.get("gold", 0)) < dip.buy_price(site_id, resource, _amount)
	buy.pressed.connect(func() -> void: _trade(resource, true))
	h.add_child(buy)
	var sell := UiTheme.button(Loc.t("Sell %d") % dip.sell_price(site_id, resource, _amount), "res_gold")
	sell.custom_minimum_size = Vector2(112, 32)
	sell.add_theme_font_size_override("font_size", 13)
	sell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell.disabled = blocker != "" or int(world.res.get(resource, 0)) < _amount
	sell.pressed.connect(func() -> void: _trade(resource, false))
	h.add_child(sell)
	return h


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
	var buy := UiTheme.button(Loc.t("Buy %d") % price, "res_gold")
	buy.custom_minimum_size = Vector2(112, 32)
	buy.add_theme_font_size_override("font_size", 13)
	buy.disabled = blocker != "" or count <= 0 or int(world.res.get("gold", 0)) < price
	buy.pressed.connect(func() -> void:
		_report(g.world.diplomacy.buy_specialty(site_id, base)))
	h.add_child(buy)
	return h


func _trade(resource: String, buying: bool) -> void:
	_report(g.world.diplomacy.resource_trade(site_id, resource, _amount, buying))


func _report(error: String) -> void:
	if error == "":
		Sfx.play(&"coin")
	else:
		hud.add_note({"text": Loc.t(error), "kind": "bad"}, 3.0)
	refresh(true)
	hud.info_panel.refresh(true)
