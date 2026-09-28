class_name VillagePanel
extends RefCounted
## The village view of the right-hand info panel: name, race, population, relation bar and tier,
## specialties, the quest board, the residents (Talk / Invite) and the Trade / Gift / Peace /
## Attack actions. Built into the InfoPanel body so the panel keeps one layout and one refresh path.

const TIER_COLOR := {
	"Hostile": UiTheme.BAD, "Wary": Color("#e0a04a"), "Neutral": UiTheme.TEXT,
	"Friendly": UiTheme.GOOD, "Allied": UiTheme.GOLD,
}
const GIFT_RESOURCES := ["food", "wood", "stone", "metal"]
const GIFT_AMOUNT := 10
const MAX_RESIDENT_ROWS := 10
## Resident job (`Diplomacy.resident_job`) -> i18n key of its label.
const JOB_KEY := {"farmer": "village.job.farmer", "crafter": "village.job.crafter",
	"trader": "village.job.trader", "guard": "village.job.guard", "elder": "village.job.elder"}


static func tier_color(tier: String) -> Color:
	return TIER_COLOR.get(tier, UiTheme.TEXT)


## A key that changes whenever anything shown here changes, so the panel only rebuilds then.
static func signature(st: Dictionary) -> String:
	return "v%d:%d:%d:%d:%d" % [int(st.get("id", -1)), int(st.get("relation", 0)),
		int(st.get("population", 0)), int(bool(st.get("ruined", false))),
		(st.get("units", []) as Array).size()]


## True when `u` is a living resident of a discovered community (world clicks offer Talk/Invite).
static func resident_site(w: World, u: Unit) -> int:
	if u == null or not u.is_person() or u.is_player() or u.home_site < 0:
		return -1
	var st: Dictionary = w.sites.get(u.home_site, {})
	if not w.diplomacy.is_community(st) or not bool(st.get("discovered", false)):
		return -1
	return int(st["id"])


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

	var near := dip.is_near_community(sid)
	if not near:
		var hint := UiTheme.label(Loc.t("Send someone to the village to trade."), 13, UiTheme.TEXT_DIM)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(hint)

	if not bool(st.get("ruined", false)) and value > Diplomacy.HOSTILE_AT:
		QuestBoard.build(body, g, hud, sid)
		_residents(body, g, hud, sid)

	var blocker := dip.trade_blocker(sid)
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


# --- residents -----------------------------------------------------------------------------

static func _residents(body: VBoxContainer, g: Game, hud: Hud, sid: int) -> void:
	var people: Array = g.world.diplomacy.residents(sid)
	if people.is_empty():
		return
	body.add_child(UiTheme.label(Loc.t("Residents"), 15, UiTheme.GOLD))
	var shown := 0
	for u: Unit in people:
		if shown >= MAX_RESIDENT_ROWS:
			break
		body.add_child(resident_row(g, hud, sid, u))
		shown += 1


## One resident: portrait, name, job and level, with Talk and Invite. Also used for the card the
## world click on a villager opens.
static func resident_row(g: Game, hud: Hud, sid: int, u: Unit) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.flat(Color(0.09, 0.12, 0.18, 0.95), 6, UiTheme.BORDER_DIM, 1))
	var v := UiTheme.vbox(3)
	p.add_child(v)
	var head := UiTheme.hbox(6)
	v.add_child(head)
	var pic := TextureRect.new()
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = Vector2(44, 44)
	pic.texture = hud.portraits.get_portrait("u%d" % u.id, u.dna, 64)
	head.add_child(pic)
	var text := UiTheme.vbox(1)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(text)
	var nm := UiTheme.label(u.name, 14, UiTheme.TEXT, UiTheme.bold_font)
	nm.clip_text = true
	nm.custom_minimum_size = Vector2(150, 0)
	text.add_child(nm)
	text.add_child(UiTheme.label(Loc.t("%s · Lv. %d")
		% [Loc.t(str(JOB_KEY.get(Diplomacy.resident_job(u), "village.job.farmer"))), u.char_level()],
		13, UiTheme.TEXT_DIM))
	var row := UiTheme.hbox(4)
	v.add_child(row)
	var talk := UiTheme.button(Loc.t("Talk"), "ui_scroll")
	talk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	talk.disabled = not g.world.diplomacy.is_near_community(sid)
	var uid := u.id
	talk.pressed.connect(func() -> void: speak(g, hud, sid, uid))
	row.add_child(talk)
	var cost := g.world.diplomacy.recruit_cost(sid, u.id)
	var blocker := g.world.diplomacy.recruit_blocker(sid, u.id)
	var invite := UiTheme.button(Loc.t("Invite (%d gold)") % cost, "cmd_move",
		Loc.t(blocker) if blocker != "" else "")
	invite.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	invite.disabled = blocker != ""
	invite.pressed.connect(func() -> void: _run(hud, g.world.diplomacy.recruit(sid, uid)))
	row.add_child(invite)
	return p


## Talks to a resident: the line appears over their head and, with their name, in the feed.
static func speak(g: Game, hud: Hud, sid: int, unit_id: int) -> void:
	var line := g.world.diplomacy.talk(sid, unit_id)
	var u := g.world.get_unit(unit_id)
	if u == null:
		return
	var text := Loc.t(str(line["text_key"]), line["params"])
	hud.speech.say(u, text)
	g.world.notify_key("sim.village.said", {"unit_name": u.name, "line": text}, "info", u.pos,
		{"unit": unit_id, "site": sid})
	Sfx.play(&"ui_confirm")
	hud.info_panel.refresh(true)


static func _run(hud: Hud, error: String) -> void:
	if error == "":
		Sfx.play(&"ui_confirm")
	else:
		hud.add_note({"text": Loc.t(error), "kind": "bad"}, 3.0)
	hud.info_panel.refresh(true)
