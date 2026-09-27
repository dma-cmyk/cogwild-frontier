class_name VillageHud
extends Control
## Container for the village screens: the trade window, the diplomacy overview and the
## "really attack them?" confirmation. Kept apart from Hud so the HUD only creates it and asks it
## to refresh, relayout and close.

var g: Game
var hud: Hud
var trade_window: TradeWindow
var diplomacy_panel: DiplomacyPanel
var _confirm: PanelContainer
var _confirm_text: Label
var _confirm_action: Callable


func setup(game: Game, h: Hud) -> void:
	g = game
	hud = h
	name = "VillageHud"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	trade_window = TradeWindow.new()
	add_child(trade_window)
	trade_window.setup(g, hud)
	diplomacy_panel = DiplomacyPanel.new()
	add_child(diplomacy_panel)
	diplomacy_panel.setup(g, hud)
	_build_confirm()
	g.world.notified.connect(_on_note)
	get_viewport().size_changed.connect(relayout)


func _build_confirm() -> void:
	_confirm = UiTheme.panel()
	add_child(_confirm)
	_confirm.visible = false
	var v := UiTheme.vbox(10)
	_confirm.add_child(v)
	_confirm_text = UiTheme.label("", 17)
	_confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_text.custom_minimum_size = Vector2(360, 0)
	v.add_child(_confirm_text)
	var row := UiTheme.hbox(8)
	var yes := UiTheme.button(Loc.t("Attack"), "cmd_attack")
	yes.custom_minimum_size = Vector2(150, 44)
	yes.pressed.connect(func() -> void:
		_confirm.visible = false
		if _confirm_action.is_valid():
			_confirm_action.call())
	row.add_child(yes)
	var no := UiTheme.button(Loc.t("Cancel"), "ui_close")
	no.custom_minimum_size = Vector2(150, 44)
	no.pressed.connect(func() -> void: _confirm.visible = false)
	row.add_child(no)
	v.add_child(row)


func relayout() -> void:
	var screen := get_viewport().get_visible_rect().size
	var w := minf(440.0, screen.x - 24.0)
	_confirm.anchor_left = 0.5
	_confirm.anchor_right = 0.5
	_confirm.anchor_top = 0.5
	_confirm.anchor_bottom = 0.5
	_confirm.offset_left = -w * 0.5
	_confirm.offset_right = w * 0.5
	_confirm.offset_top = -90
	_confirm.offset_bottom = 90
	_confirm_text.custom_minimum_size = Vector2(w - 40.0, 0)
	trade_window.layout()
	diplomacy_panel.layout()


func refresh() -> void:
	trade_window.refresh()
	diplomacy_panel.refresh()


## Closes the topmost village window. Returns true when something was closed (for the Esc chain).
func close_top() -> bool:
	if _confirm.visible:
		_confirm.visible = false
		return true
	if trade_window.visible:
		trade_window.close_window()
		return true
	if diplomacy_panel.visible:
		diplomacy_panel.visible = false
		return true
	return false


func open_trade(sid: int) -> void:
	diplomacy_panel.visible = false
	trade_window.open(sid)


## Attacking people who are not at war with you needs a deliberate confirmation.
func confirm_village_attack(sid: int, squad_id: int) -> void:
	var st: Dictionary = g.world.sites.get(sid, {})
	if st.is_empty():
		return
	var attack := func() -> void:
		var squad := g.world.get_squad(squad_id)
		if squad == null:
			return
		g.world.diplomacy.declare_attack(sid)
		g.world.squad_ai.order_squad(squad, {"type": "attack", "site": sid, "pos": Vector2(st["center"])})
		Sfx.play(&"alert")
	if int(st.get("relation", 0)) <= Diplomacy.HOSTILE_AT:
		attack.call()
		return
	_confirm_action = attack
	_confirm_text.text = Loc.t("Attack %s? The %s will turn hostile and their other villages will hear of it.") \
		% [str(st["name"]), Loc.def_text("races", str(st.get("race", "")), "plural")]
	relayout()
	_confirm.visible = true
	trade_window.close_window()


## Auto-opens the market when a squad you sent finishes the walk to a village.
func _on_note(n: Dictionary) -> void:
	if not n.has("village_arrival"):
		return
	var sid := int(n["village_arrival"])
	if g.world.diplomacy.trade_blocker(sid) == "":
		g.select_site(sid)
		open_trade(sid)
