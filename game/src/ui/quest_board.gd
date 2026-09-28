class_name QuestBoard
extends RefCounted
## The quest board widget shared by every community panel (village panel, town guild hall).
##
## `build` appends the board of one giver to an existing VBox: the jobs on offer with an Accept
## button, then the jobs you already took with their progress and Hand in / Abandon. `signature`
## changes whenever anything shown here changes, so a panel can skip the rebuild.

const PROGRESS_COLOR := {"active": UiTheme.ACCENT, "done": UiTheme.GOOD}


static func signature(w: World, sid: int) -> String:
	var parts := PackedStringArray(["q%d:%d" % [sid, w.day]])
	for q: Dictionary in w.quests.board(sid):
		parts.append("o%d" % int(q["id"]))
	for q: Dictionary in w.quests.accepted_for(sid):
		var p := w.quests.progress(q)
		parts.append("a%d:%s:%d" % [int(q["id"]), str(q["state"]), int(p["have"])])
	return "|".join(parts)


## Appends the board of `sid` to `body`. Returns the number of rows shown.
static func build(body: VBoxContainer, g: Game, hud: Hud, sid: int) -> int:
	var w := g.world
	var offered: Array = w.quests.board(sid)
	var mine: Array = w.quests.accepted_for(sid)
	body.add_child(UiTheme.label(Loc.t("Quest board"), 15, UiTheme.GOLD))
	if offered.is_empty() and mine.is_empty():
		body.add_child(UiTheme.label(Loc.t("Nothing on the board today."), 13, UiTheme.TEXT_DIM))
		return 0
	var rows := 0
	for q: Dictionary in mine:
		body.add_child(_taken_row(g, hud, q))
		rows += 1
	for q: Dictionary in offered:
		body.add_child(_offer_row(g, hud, q))
		rows += 1
	return rows


static func _card() -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.flat(Color(0.09, 0.12, 0.18, 0.95), 6, UiTheme.BORDER_DIM, 1))
	var v := UiTheme.vbox(3)
	p.add_child(v)
	v.set_meta("card", p)
	return v


static func _wrap(text: String, size: int, color: Color) -> Label:
	var l := UiTheme.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(190, 0)
	return l


static func _offer_row(g: Game, hud: Hud, q: Dictionary) -> Control:
	var w := g.world
	var v := _card()
	v.add_child(_wrap(w.quests.describe_text(q), 15, UiTheme.TEXT))
	v.add_child(UiTheme.label(Loc.t("Reward %d gold · by day %d")
		% [int(q["reward_gold"]), int(q["deadline_day"])], 13, UiTheme.TEXT_DIM))
	var blocker := w.quests.accept_blocker(int(q["id"]))
	var accept := UiTheme.button(Loc.t("Accept"), "ui_scroll", Loc.t(blocker) if blocker != "" else "")
	accept.disabled = blocker != ""
	var qid := int(q["id"])
	accept.pressed.connect(func() -> void: _run(hud, w.quests.accept(qid)))
	v.add_child(accept)
	return v.get_meta("card")


static func _taken_row(g: Game, hud: Hud, q: Dictionary) -> Control:
	var w := g.world
	var v := _card()
	var p := w.quests.progress(q)
	var state := str(q["state"])
	v.add_child(_wrap(w.quests.describe_text(q), 15, PROGRESS_COLOR.get(state, UiTheme.TEXT)))
	if state == "done":
		v.add_child(UiTheme.label(Loc.t("Ready to hand in"), 13, UiTheme.GOOD))
	else:
		v.add_child(UiTheme.label(Loc.t("%s (%d/%d)") % [Loc.t("Active jobs"), int(p["have"]), int(p["need"])],
			13, UiTheme.TEXT_DIM))
	if q.has("hint"):
		v.add_child(UiTheme.label(Loc.t("Heading %s, about %d tiles")
			% [Loc.t(str(q["hint"])), int(q.get("hint_distance", 0))], 13, UiTheme.TEXT_DIM))
	var row := UiTheme.hbox(4)
	var qid := int(q["id"])
	var blocker := w.quests.turn_in_blocker(qid)
	var hand_in := UiTheme.button(Loc.t("Hand in"), "cmd_trade", Loc.t(blocker) if blocker != "" else "")
	hand_in.disabled = blocker != ""
	hand_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand_in.pressed.connect(func() -> void: _run(hud, w.quests.turn_in(qid)))
	row.add_child(hand_in)
	var drop := UiTheme.button(Loc.t("Abandon"), "ui_close")
	drop.pressed.connect(func() -> void:
		w.quests.abandon(qid)
		Sfx.play(&"ui_confirm")
		hud.info_panel.refresh(true))
	row.add_child(drop)
	v.add_child(row)
	return v.get_meta("card")


static func _run(hud: Hud, error: String) -> void:
	if error == "":
		Sfx.play(&"ui_confirm")
	else:
		hud.add_note({"text": Loc.t(error), "kind": "bad"}, 3.0)
	hud.info_panel.refresh(true)
