class_name TownPanel
extends RefCounted
## Town-specific service tabs embedded in the right-hand InfoPanel.

const TABS := ["store", "smithy", "inn", "tavern", "guild"]
const TAB_KEYS := {"store": "town.tab.store", "smithy": "town.tab.smithy", "inn": "town.tab.inn",
	"tavern": "town.tab.tavern", "guild": "town.tab.guild"}
const RESOURCES := ["wood", "stone", "ore", "metal", "food"]


static func signature(w: World, sid: int, active_tab: String) -> String:
	var st: Dictionary = w.sites.get(sid, {})
	if st.is_empty():
		return ""
	var key := "t%d:%d:%d:%d:%d:%s" % [sid, int(st.get("relation", 0)),
		int(st.get("population", 0)), int(bool(st.get("hostile", false))), w.day, active_tab]
	key += ":%d:%d" % [int(w.res.get("gold", 0)), w.town.service_blocker(sid).hash()]
	match active_tab:
		"store":
			var stock := w.diplomacy.stock_of(sid)
			for resource: String in RESOURCES:
				key += ":%s%d/%d" % [resource, int(w.res.get(resource, 0)), int(stock.get(resource, 0))]
			key += ":%s" % w.diplomacy.trade_blocker(sid)
		"smithy":
			for row: Dictionary in w.town.smithy_stock(sid):
				var item: Dictionary = row.get("item", {})
				key += ":%s:%s:%d:%d" % [str(item.get("base", "")), str(item.get("quality", "")),
					int(item.get("value", 0)), int(item.get("level", 1))]
			for item: Dictionary in w.armory:
				key += ":a%d:%d" % [int(item.get("uid", 0)), int(item.get("value", 0))]
		"inn":
			for u: Unit in w.town.local_units(sid):
				key += ":u%d:%d:%.1f" % [u.id, int(ceil(u.hp)), u.injured_days]
		"tavern":
			for u: Unit in w.town.mercenary_candidates(sid):
				key += ":m%d:%d:%d" % [u.id, u.char_level(), int(w.town.mercenary_price(sid, u))]
			key += ":%d" % int(w.housing() - w.player_people().size())
		"guild":
			key += ":%s" % QuestBoard.signature(w, sid)
	return key


static func build(body: VBoxContainer, g: Game, hud: Hud, st: Dictionary, active_tab: String,
		change_tab: Callable) -> void:
	var w := g.world
	var sid := int(st["id"])
	var relation := int(st.get("relation", 0))
	var tier := Diplomacy.tier_for(relation)
	var tint := VillagePanel.tier_color(tier)
	var head := UiTheme.hbox(7)
	head.add_child(UiTheme.icon("poi_town", 40))
	var title := UiTheme.title(str(st.get("name", Loc.t("Town"))), 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	head.add_child(title)
	body.add_child(head)
	var subtitle := UiTheme.label(Loc.t("town.subtitle"), 13, UiTheme.TEXT_DIM)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(subtitle)
	body.add_child(UiTheme.label(Loc.t("town.population") % int(st.get("population", 0)), 14, UiTheme.TEXT))
	var relation_row := UiTheme.hbox(5)
	relation_row.add_child(UiTheme.label(Loc.t("town.reputation"), 13, UiTheme.GOLD))
	var bar := UiTheme.bar(tint, 10)
	bar.value = clampf((float(relation) + 100.0) / 200.0, 0.0, 1.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	relation_row.add_child(bar)
	relation_row.add_child(UiTheme.label("%s %d" % [Loc.t(tier), relation], 13, tint))
	body.add_child(relation_row)

	var blocker := w.town.service_blocker(sid)
	if bool(st.get("hostile", false)) or relation <= Diplomacy.HOSTILE_AT:
		body.add_child(UiTheme.label(Loc.t("town.status.closed"), 13, UiTheme.BAD))
		var peace_cost := w.diplomacy.tribute_cost(sid)
		var peace := UiTheme.button(Loc.t("Make peace (%d gold)") % peace_cost, "ui_scroll")
		peace.disabled = int(w.res.get("gold", 0)) < peace_cost
		peace.pressed.connect(func() -> void: _report(hud, w.diplomacy.make_peace(sid)))
		body.add_child(peace)
	elif blocker != "":
		var message := UiTheme.label(Loc.t(blocker), 13, UiTheme.BAD)
		message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(message)

	var tabs := UiTheme.hbox(2)
	for tab: String in TABS:
		var button := UiTheme.button(Loc.t(str(TAB_KEYS[tab])))
		button.add_theme_font_size_override("font_size", 12)
		button.custom_minimum_size = Vector2(0, 36)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_stylebox_override("normal", UiTheme.button_box("pressed" if tab == active_tab else "normal"))
		button.pressed.connect(func() -> void: change_tab.call(tab))
		tabs.add_child(button)
	body.add_child(tabs)
	match active_tab:
		"store": _store(body, g, hud, sid, blocker)
		"smithy": _smithy(body, g, hud, sid, blocker)
		"inn": _inn(body, g, hud, sid, blocker)
		"tavern": _tavern(body, g, hud, sid, blocker)
		"guild": _guild(body, g, hud, sid)
	_add_town_actions(body, g, hud, st)


static func _store(body: VBoxContainer, g: Game, hud: Hud, sid: int, blocker: String) -> void:
	var w := g.world
	var desc := UiTheme.label(Loc.t("town.store.description"), 13, UiTheme.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(desc)
	var trade_blocker := blocker if blocker != "" else w.diplomacy.trade_blocker(sid)
	if trade_blocker != "":
		var status := UiTheme.label(Loc.t(trade_blocker), 13, UiTheme.BAD)
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(status)
	body.add_child(UiTheme.label(Loc.t("town.store.stock"), 14, UiTheme.GOLD))
	var stock := w.diplomacy.stock_of(sid)
	for resource: String in RESOURCES:
		var row := UiTheme.hbox(4)
		row.add_child(UiTheme.icon("res_" + resource, 22))
		var amount := UiTheme.label("%s  %d" % [Loc.t(resource).capitalize(), int(stock.get(resource, 0))], 13)
		amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(amount)
		body.add_child(row)
	var trade := UiTheme.button(Loc.t("Trade"), "cmd_trade", Loc.t(trade_blocker) if trade_blocker != "" else "")
	trade.disabled = trade_blocker != ""
	trade.pressed.connect(func() -> void: hud.villages.open_trade(sid))
	body.add_child(trade)


static func _smithy(body: VBoxContainer, g: Game, hud: Hud, sid: int, blocker: String) -> void:
	var w := g.world
	var desc := UiTheme.label(Loc.t("town.smithy.description"), 13, UiTheme.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(desc)
	body.add_child(UiTheme.label(Loc.t("town.smithy.stock"), 14, UiTheme.GOLD))
	var stock := w.town.smithy_stock(sid)
	if stock.is_empty():
		body.add_child(UiTheme.label(Loc.t("town.smithy.sold_out"), 13, UiTheme.TEXT_DIM))
	for i in stock.size():
		var item: Dictionary = (stock[i] as Dictionary).get("item", {})
		var price := w.town.smithy_price(sid, item)
		var row := UiTheme.hbox(4)
		var icon := TextureRect.new()
		icon.texture = Icons.item_icon(item, 36)
		icon.custom_minimum_size = Vector2(32, 32)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		row.add_child(icon)
		var label := UiTheme.label("%s · %s · Lv%d" % [Loc.item_name(item), Loc.def_name("items/qualities", str(item.get("quality", "common"))), int(item.get("level", 1))], 12)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		row.add_child(label)
		var buy := UiTheme.button(Loc.t("town.item.buy") % price, "res_gold")
		buy.add_theme_font_size_override("font_size", 11)
		buy.disabled = blocker != "" or int(w.res.get("gold", 0)) < price
		var index := i
		buy.pressed.connect(func() -> void: _report(hud, w.town.buy_smithy(sid, index)))
		row.add_child(buy)
		body.add_child(row)
	body.add_child(UiTheme.label(Loc.t("town.smithy.sell_items"), 14, UiTheme.GOLD))
	if w.armory.is_empty():
		body.add_child(UiTheme.label(Loc.t("town.smithy.no_items"), 13, UiTheme.TEXT_DIM))
	for item: Dictionary in w.armory:
		var price := w.town.sell_price(sid, item)
		var row := UiTheme.hbox(4)
		var icon := TextureRect.new()
		icon.texture = Icons.item_icon(item, 36)
		icon.custom_minimum_size = Vector2(32, 32)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		row.add_child(icon)
		var label := UiTheme.label(Loc.item_name(item), 12)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		row.add_child(label)
		var sell := UiTheme.button(Loc.t("town.item.sell") % price, "res_gold")
		sell.add_theme_font_size_override("font_size", 11)
		sell.disabled = blocker != ""
		var uid := int(item.get("uid", 0))
		sell.pressed.connect(func() -> void: _report(hud, w.town.sell_item(sid, uid)))
		row.add_child(sell)
		body.add_child(row)
	GearworkPanel.build(body, g, hud, sid)


static func _inn(body: VBoxContainer, g: Game, hud: Hud, sid: int, blocker: String) -> void:
	var w := g.world
	var desc := UiTheme.label(Loc.t("town.inn.description"), 13, UiTheme.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(desc)
	var units := w.town.local_units(sid)
	if units.is_empty():
		body.add_child(UiTheme.label(Loc.t("town.inn.no_units"), 13, UiTheme.TEXT_DIM))
	for u: Unit in units:
		var price := w.town.inn_price(sid, u)
		var row := UiTheme.hbox(4)
		var label := UiTheme.label("%s  %d/%d%s" % [u.name, int(ceil(u.hp)), int(u.stats.get("max_hp", 1)),
			(" · %s %.1f" % [Loc.t("Injured"), u.injured_days]) if u.injured_days > 0.0 else ""], 12)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		row.add_child(label)
		var heal := UiTheme.button(Loc.t("town.inn.heal") % price, "ui_heart")
		heal.add_theme_font_size_override("font_size", 11)
		heal.disabled = blocker != "" or price <= 0 or int(w.res.get("gold", 0)) < price
		var id := u.id
		heal.pressed.connect(func() -> void: _report(hud, w.town.heal(sid, id)))
		row.add_child(heal)
		body.add_child(row)


static func _tavern(body: VBoxContainer, g: Game, hud: Hud, sid: int, blocker: String) -> void:
	var w := g.world
	var desc := UiTheme.label(Loc.t("town.tavern.description"), 13, UiTheme.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(desc)
	body.add_child(UiTheme.label(Loc.t("town.tavern.candidates"), 14, UiTheme.GOLD))
	var candidates := w.town.mercenary_candidates(sid)
	if candidates.is_empty():
		body.add_child(UiTheme.label(Loc.t("town.tavern.no_candidates"), 13, UiTheme.TEXT_DIM))
	for u: Unit in candidates:
		var price := w.town.mercenary_price(sid, u)
		var row := UiTheme.hbox(4)
		var info := UiTheme.label("%s  ·  %s Lv%d" % [u.name,
			Loc.def_name("races", str(u.character.get("race", "human"))), u.char_level()], 12)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.clip_text = true
		row.add_child(info)
		var hire := UiTheme.button(Loc.t("town.tavern.hire") % price, "res_gold")
		hire.add_theme_font_size_override("font_size", 11)
		hire.disabled = blocker != "" or w.housing() <= w.player_people().size() or int(w.res.get("gold", 0)) < price
		var id := u.id
		hire.pressed.connect(func() -> void: _report(hud, w.town.hire_mercenary(sid, id)))
		row.add_child(hire)
		body.add_child(row)
	var rumour_price := w.town.rumour_price(sid)
	var rumour := UiTheme.button(Loc.t("town.tavern.rumour") % rumour_price, "poi_ruins")
	rumour.disabled = blocker != "" or not w.town.has_rumour(sid) or int(w.res.get("gold", 0)) < rumour_price
	rumour.pressed.connect(func() -> void: _report(hud, w.town.buy_rumour(sid)))
	body.add_child(rumour)


static func _guild(body: VBoxContainer, g: Game, hud: Hud, sid: int) -> void:
	var desc := UiTheme.label(Loc.t("town.guild.description"), 13, UiTheme.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(desc)
	body.add_child(UiTheme.label(Loc.t("town.guild.board"), 14, UiTheme.GOLD))
	QuestBoard.build(body, g, hud, sid)


static func _add_town_actions(body: VBoxContainer, g: Game, hud: Hud, st: Dictionary) -> void:
	var sid := int(st["id"])
	var focus := UiTheme.button(Loc.t("Centre camera"), "ui_target")
	focus.pressed.connect(func() -> void: g.focus_pos(Vector2(st["center"])))
	body.add_child(focus)
	for squad: Squad in g.world.squads:
		var attack := UiTheme.button(Loc.t("Send %s to attack") % squad.name, "cmd_attack")
		var squad_id := squad.id
		attack.pressed.connect(func() -> void: hud.villages.confirm_village_attack(sid, squad_id))
		body.add_child(attack)


static func _report(hud: Hud, error: String) -> void:
	if error == "":
		Sfx.play(&"coin")
	else:
		hud.add_note({"text": Loc.t(error), "kind": "bad"}, 3.0)
	hud.info_panel.refresh(true)
