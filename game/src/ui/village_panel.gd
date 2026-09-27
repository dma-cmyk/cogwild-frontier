class_name VillagePanel
extends RefCounted
## The village view of the right-hand info panel: name, race, population, relation bar and tier,
## specialties, the current request and the Trade / Gift / Peace / Attack actions.
## Built into the InfoPanel body so the panel keeps one layout and one refresh path.

const TIER_COLOR := {
	"Hostile": UiTheme.BAD, "Wary": Color("#e0a04a"), "Neutral": UiTheme.TEXT,
	"Friendly": UiTheme.GOOD, "Allied": UiTheme.GOLD,
}
const GIFT_RESOURCES := ["food", "wood", "stone", "metal"]
const GIFT_AMOUNT := 10


static func tier_color(tier: String) -> Color:
	return TIER_COLOR.get(tier, UiTheme.TEXT)


## A key that changes whenever anything shown here changes, so the panel only rebuilds then.
static func signature(st: Dictionary) -> String:
	return "v%d:%d:%d:%d:%d:%d" % [int(st.get("id", -1)), int(st.get("relation", 0)),
		int(st.get("population", 0)), int(bool(st.get("ruined", false))),
		int((st.get("request", {}) as Dictionary).get("serial", 0)),
		int((st.get("request", {}) as Dictionary).is_empty())]


static func build(body: VBoxContainer, g: Game, hud: Hud, st: Dictionary) -> void:
	var world := g.world
	var dip := world.diplomacy
	var sid := int(st["id"])
	var race := str(st.get("race", ""))
	var value := int(st.get("relation", 0))
	var tier := Diplomacy.tier_for(value)

	var head := UiTheme.hbox(8)
	head.add_child(UiTheme.icon(str(st.get("icon", "poi_village")), 44))
	var hv := UiTheme.vbox(2)
	var nm := UiTheme.title(str(st["name"]), 21)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.custom_minimum_size = Vector2(210, 0)
	hv.add_child(nm)
	hv.add_child(UiTheme.label(Loc.t("%s village · %d people") % [Loc.def_name("races", race),
		int(st.get("population", 0))], 15, UiTheme.TEXT_DIM))
	head.add_child(hv)
	body.add_child(head)

	var relation_row := UiTheme.hbox(6)
	relation_row.add_child(UiTheme.label(Loc.t("Relation"), 14, UiTheme.GOLD))
	var bar := UiTheme.bar(tier_color(tier), 12)
	bar.value = clampf((float(value) + 100.0) / 200.0, 0.0, 1.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	relation_row.add_child(bar)
	relation_row.add_child(UiTheme.label("%s %d" % [Loc.t(tier), value], 14, tier_color(tier)))
	body.add_child(relation_row)

	if bool(st.get("ruined", false)):
		var ruin := UiTheme.label(Loc.t("Plundered and empty. Survivors will trickle back in a few days."), 14, UiTheme.BAD)
		ruin.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(ruin)
	elif value <= Diplomacy.HOSTILE_AT:
		var war := UiTheme.label(Loc.t("At war with you. They will raid until a tribute buys peace."), 14, UiTheme.BAD)
		war.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(war)

	var goods: Array = dip.goods_of(sid)
	if not goods.is_empty():
		var names := PackedStringArray()
		for row: Dictionary in goods:
			names.append(Loc.def_name("items", str(row.get("base", ""))))
		var spec := UiTheme.label(Loc.t("Known for: ") + ", ".join(names), 14, UiTheme.TEXT_DIM)
		spec.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(spec)

	var request: Dictionary = st.get("request", {})
	if not request.is_empty() and not bool(st.get("ruined", false)):
		var resource := str(request.get("resource", "food"))
		var amount := int(request.get("amount", 0))
		var ask := UiTheme.label(Loc.t("They ask for %d %s by day %d — reward %d gold.") % [amount,
			Loc.t(resource), int(request.get("due_day", 0)), int(request.get("reward_gold", 0))],
			14, UiTheme.ACCENT)
		ask.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(ask)
		var deliver := UiTheme.button(Loc.t("Deliver the goods"), "cmd_trade")
		deliver.disabled = int(world.res.get(resource, 0)) < amount
		deliver.pressed.connect(func() -> void: _run(hud, world.diplomacy.fulfil_request(sid)))
		body.add_child(deliver)

	var blocker := dip.trade_blocker(sid)
	var near := dip.is_near_village(sid)
	if not near:
		var hint := UiTheme.label(Loc.t("Send someone to the village to trade."), 13, UiTheme.TEXT_DIM)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(hint)

	var trade := UiTheme.button(Loc.t("Trade"), "cmd_trade", Loc.t(blocker) if blocker != "" else "")
	trade.disabled = blocker != ""
	trade.pressed.connect(func() -> void: hud.villages.open_trade(sid))
	body.add_child(trade)

	if value > Diplomacy.HOSTILE_AT:
		var gift_row := UiTheme.hbox(4)
		gift_row.add_child(UiTheme.label(Loc.t("Gift"), 14, UiTheme.GOLD))
		for resource: String in GIFT_RESOURCES:
			var goodwill := dip.gift_goodwill(sid, resource, GIFT_AMOUNT)
			var b := UiTheme.button("%d %s" % [GIFT_AMOUNT, Loc.t(resource)], "res_" + resource,
				Loc.t("Goodwill from this gift: +%d") % goodwill)
			b.add_theme_font_size_override("font_size", 12)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.disabled = not near or int(world.res.get(resource, 0)) < GIFT_AMOUNT
			var r := resource
			b.pressed.connect(func() -> void: _run(hud, world.diplomacy.gift(sid, r, GIFT_AMOUNT)))
			gift_row.add_child(b)
		body.add_child(gift_row)
	else:
		var tribute := dip.tribute_cost(sid)
		var peace := UiTheme.button(Loc.t("Make peace (%d gold)") % tribute, "ui_scroll")
		peace.disabled = int(world.res.get("gold", 0)) < tribute
		peace.pressed.connect(func() -> void: _run(hud, world.diplomacy.make_peace(sid)))
		body.add_child(peace)

	for s: Squad in world.squads:
		if value > Diplomacy.HOSTILE_AT and not bool(st.get("ruined", false)):
			var visit := UiTheme.button(Loc.t("Send %s to visit") % s.name, "cmd_move")
			var visit_id := s.id
			visit.pressed.connect(func() -> void:
				world.squad_ai.order_squad(world.get_squad(visit_id),
					{"type": "visit", "site": sid, "pos": Vector2(st["center"])})
				Sfx.play(&"ui_confirm"))
			body.add_child(visit)
		var attack := UiTheme.button(Loc.t("Send %s to attack") % s.name, "cmd_attack")
		var attack_id := s.id
		attack.pressed.connect(func() -> void: hud.villages.confirm_village_attack(sid, attack_id))
		body.add_child(attack)

	var focus := UiTheme.button(Loc.t("Centre camera"), "ui_target")
	focus.pressed.connect(func() -> void: g.focus_pos(Vector2(st["center"])))
	body.add_child(focus)


static func _run(hud: Hud, error: String) -> void:
	if error == "":
		Sfx.play(&"ui_confirm")
	else:
		hud.add_note({"text": Loc.t(error), "kind": "bad"}, 3.0)
	hud.info_panel.refresh(true)
