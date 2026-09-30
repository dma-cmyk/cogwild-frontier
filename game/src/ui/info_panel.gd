class_name InfoPanel
extends PanelContainer
## Right-hand details panel. Characters: portrait, name, role, level, health/energy and tabs for
## Equipment (equip from the armory), Traits, Skills and Bio. Machines, buildings (construction,
## upgrades, workshop queue) and discovered sites have their own views.

const TABS := ["Equipment", "Traits", "Skills", "Bio"]

var g: Game
var hud: Hud
var _body: VBoxContainer
var _tab := "Equipment"
var _town_tab := "store"
var _key := ""
var _hp: ProgressBar
var _hp_l: Label
var _en: ProgressBar
var _en_l: Label
var _dyn: Label
var _armory_slot := ""
var mobile_collapsed := false


func setup(game: Game, h: Hud) -> void:
	g = game
	hud = h
	name = "InfoPanel"
	add_theme_stylebox_override("panel", UiTheme.panel_box())
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -352
	offset_right = -10
	offset_top = -660
	offset_bottom = -10
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_body = UiTheme.vbox(6)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	visible = false
	mobile_collapsed = App.is_touch() or App.is_mobile_web()
func toggle_drawer() -> void:
	mobile_collapsed = not mobile_collapsed
	visible = not mobile_collapsed and _key != ""


func open_drawer() -> void:
	mobile_collapsed = false
	visible = _key != ""




func refresh(force: bool) -> void:
	var key := ""
	var u := g.focus_unit()
	if u:
		key = "u%d:%s:%s:%s:%s" % [u.id, _tab, _armory_slot, str(u.equipment().hash()),
			_resident_key(u)]
	elif g.sel_building >= 0 and g.world.buildings.has(g.sel_building):
		var b: Building = g.world.buildings[g.sel_building]
		key = "b%d:%d:%d:%s:%d" % [b.id, b.level, int(b.is_built()), str(b.queue), b.needs.hash()]
	elif g.sel_site >= 0:
		var st: Dictionary = g.world.sites.get(g.sel_site, {})
		var town_key := TownPanel.signature(g.world, g.sel_site, _town_tab) if str(st.get("kind", "")) == "town" else ""
		key = "s%d:%s:%s:%s%s" % [g.sel_site, str(st.get("cleared", false)), str(st.get("looted", false)),
			_community_key(st) if g.world.diplomacy.is_community(st) else "", town_key]
	elif g.sel_loot >= 0 and g.world.loot_bags.has(g.sel_loot):
		var bag: Dictionary = g.world.loot_bags[g.sel_loot]
		key = "l%d:%d:%d:%d" % [g.sel_loot, (bag.get("items", []) as Array).size(), int(bag.get("gold", 0)), int(bag.get("metal", 0))]
	visible = key != "" and not mobile_collapsed
	if key != _key or force:
		_key = key
		_rebuild(u)
	_update_dynamic(u)


func _clear() -> void:
	for c in _body.get_children():
		c.queue_free()
	_hp = null
	_en = null
	_dyn = null


func _rebuild(u: Unit) -> void:
	_clear()
	if u:
		_build_unit(u)
	elif g.sel_building >= 0 and g.world.buildings.has(g.sel_building):
		_build_building(g.world.buildings[g.sel_building])
	elif g.sel_site >= 0 and g.world.sites.has(g.sel_site):
		_build_site(g.world.sites[g.sel_site])
	elif g.sel_loot >= 0 and g.world.loot_bags.has(g.sel_loot):
		_build_loot(g.world.loot_bags[g.sel_loot])


func _update_dynamic(u: Unit) -> void:
	if u and _hp:
		_hp.value = u.hp_ratio()
		_hp_l.text = "%d/%d" % [ceili(u.hp), ceili(float(u.stats.get("max_hp", 100)))]
		if _en:
			var mx := float(u.stats.get("energy_max", 100.0))
			_en.value = clampf(u.energy / maxf(1.0, mx), 0.0, 1.0)
			_en_l.text = "%d/%d" % [int(u.energy), int(mx)]
	if _dyn:
		_dyn.text = _dynamic_text(u)


func _dynamic_text(u: Unit) -> String:
	if u:
		return Loc.t("Now: ") + _activity(u)
	if g.sel_building >= 0 and g.world.buildings.has(g.sel_building):
		var b: Building = g.world.buildings[g.sel_building]
		if not b.is_built():
			var needs := []
			for k: String in b.needs:
				needs.append("%d %s" % [int(b.needs[k]), Loc.t(k)])
			return Loc.t("Construction %d%%%s") % [int(b.progress * 100), (Loc.t("  · waiting for ") + ", ".join(needs)) if not needs.is_empty() else ""]
		if b.type == "workshop" and not b.queue.is_empty():
			var ad := g.world.colony._archetype(str(b.queue[0]))
			return Loc.t("Building %s: %d%%") % [Loc.t(str(ad.get("name", b.queue[0]))), int(b.prod_t / maxf(1.0, float(ad.get("build_time", 60))) * 100)]
		if b.type == "smelter":
			return Loc.t("Smelting (ore %d)") % int(g.world.res.get("ore", 0)) if b.active else Loc.t("Idle — needs ore and a worker")
	return ""


func _activity(u: Unit) -> String:
	if not u.alive:
		return Loc.t("fallen")
	if u.state == Unit.State.DOWNED:
		return Loc.t("down! (recovering)")
	if u.squad_id >= 0:
		var s := g.world.get_squad(u.squad_id)
		return "%s — %s" % [s.name, Loc.message(s.state_message) if not s.state_message.is_empty() else Loc.t(s.state)] if s else Loc.t("in squad")
	if not u.order.is_empty():
		var o := str(u.order.get("type", ""))
		if o == "auto" and u.kind == "airship":
			return Loc.t("auto (%s)") % Loc.t(str(u.order.get("sub", "idle")))
		return Loc.t(o)
	var j := str(u.job.get("type", ""))
	match j:
		"gather":
			var t: Vector2i = u.job.get("tile", Vector2i.ZERO)
			return "%s %s" % [Loc.t(str({"chop": "chopping", "mine": "mining", "forage": "foraging"}.get(str(Tiles.res_info(g.world.res_at(t)).get("job", "")), "gathering"))), Loc.t(str(Tiles.res_info(g.world.res_at(t)).get("id", "")).replace("_", " "))]
		"farm":
			return Loc.t("%s a field") % Loc.t(str({"till": "tilling", "plant": "planting", "harvest": "harvesting"}.get(str(u.job.get("action", "")), "tending")))
		"haul":
			return Loc.t("hauling building materials")
		"build":
			return Loc.t("building")
		"operate":
			return Loc.t("working the %s") % Loc.def_name("buildings", str(g.world.buildings.get(int(u.job.get("building", -1)), Building.new()).type))
		"deliver":
			return Loc.t("carrying %d %s home") % [u.carry_amount, Loc.t(u.carry_res)]
		"rest":
			return Loc.t("resting")
		"flee":
			return Loc.t("fleeing!")
		"idle":
			return Loc.t("idle")
	return Loc.t("idle")


# --- characters & machines -----------------------------------------------------------------

func _build_unit(u: Unit) -> void:
	var head := UiTheme.hbox(10)
	_body.add_child(head)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UiTheme.flat(Color(0.1, 0.14, 0.2, 1.0), 8, UiTheme.BORDER, 2))
	var pic := TextureRect.new()
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = Vector2(104, 104)
	pic.texture = hud.portraits.get_portrait("u%d" % u.id, u.dna, 128)
	frame.add_child(pic)
	head.add_child(frame)
	var hv := UiTheme.vbox(3)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	var nm := UiTheme.title(u.name, 22 if u.name.length() < 18 else 17)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.custom_minimum_size = Vector2(180, 0)
	hv.add_child(nm)
	var role := UiTheme.hbox(4)
	role.add_child(UiTheme.icon(u.class_icon(), 20))
	var rank := str(u.character.get("rank", "")) if u.is_person() else ""
	role.add_child(UiTheme.label("%s%s" % [Loc.t(u.display_role()), (" · " + Loc.t(rank)) if rank != "" else ""], 16, UiTheme.TEXT))
	hv.add_child(role)
	var lv_line := "Lv. %d" % u.char_level()
	if u.is_person():
		lv_line += "  ·  %s, %d" % [Loc.def_name("races", str(u.character.get("race", ""))), int(u.character.get("age", 0))]
	hv.add_child(UiTheme.label(lv_line, 15, UiTheme.TEXT_DIM))
	if not u.is_player():
		var allegiance := Loc.t(str({"bandits": "Hostile — bandits", "machines": "Hostile — rogue machines", "merchants": "Merchant League", "wanderers": "Wanderer"}.get(u.faction, u.faction)))
		var home_sid := VillagePanel.resident_site(g.world, u)
		if home_sid >= 0:
			allegiance = str((g.world.sites[home_sid] as Dictionary).get("name", ""))
		hv.add_child(UiTheme.label(allegiance, 15, UiTheme.BAD if g.world.hostile("player", u.faction) else UiTheme.GOLD))
	var hp_row := UiTheme.hbox(6)
	hp_row.add_child(UiTheme.icon("ui_heart", 18))
	_hp = UiTheme.bar(Color("#e0493b"), 12)
	_hp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_row.add_child(_hp)
	_hp_l = UiTheme.label("", 14)
	_hp_l.custom_minimum_size = Vector2(70, 0)
	hp_row.add_child(_hp_l)
	_body.add_child(hp_row)
	if u.is_person():
		var en_row := UiTheme.hbox(6)
		en_row.add_child(UiTheme.icon("ui_bolt", 18))
		_en = UiTheme.bar(Color("#4f9dff"), 12)
		_en.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_en.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		en_row.add_child(_en)
		_en_l = UiTheme.label("", 14)
		_en_l.custom_minimum_size = Vector2(70, 0)
		en_row.add_child(_en_l)
		_body.add_child(en_row)
	_dyn = UiTheme.label("", 14, UiTheme.ACCENT)
	_dyn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_dyn)
	if u.is_player():
		_unit_actions(u)
	else:
		var resident_sid := VillagePanel.resident_site(g.world, u)
		if resident_sid >= 0:
			_body.add_child(VillagePanel.resident_row(g, hud, resident_sid, u))
	if u.is_person():
		var tabs := UiTheme.hbox(4)
		_body.add_child(tabs)
		for t: String in TABS:
			var b := UiTheme.button(Loc.t(t))
			b.custom_minimum_size = Vector2(0, 30)
			b.add_theme_font_size_override("font_size", 14)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if t == _tab:
				b.add_theme_stylebox_override("normal", UiTheme.button_box("pressed"))
			var tt := t
			b.pressed.connect(func() -> void:
				_tab = tt
				_armory_slot = ""
				refresh(true))
			tabs.add_child(b)
		match _tab:
			"Equipment":
				_equipment(u)
			"Traits":
				_traits(u)
			"Skills":
				_skills(u)
			"Bio":
				_bio(u)
	else:
		_machine_info(u)


## Part of the panel key for a community: its own state, the quest board, and what gates the
## buttons (someone standing there, the purse, a free bed at home).
func _community_key(st: Dictionary) -> String:
	var w := g.world
	return "%s%s:%d:%d:%d" % [VillagePanel.signature(st), QuestBoard.signature(w, int(st["id"])),
		int(w.diplomacy.is_near_community(int(st["id"]))), int(w.res.get("gold", 0)),
		int(w.population() < w.housing())]


## Part of the panel key: a villager's Talk/Invite buttons follow the relation and the purse.
func _resident_key(u: Unit) -> String:
	var sid := VillagePanel.resident_site(g.world, u)
	if sid < 0:
		return ""
	return "r%d:%d:%s" % [sid, int((g.world.sites[sid] as Dictionary).get("relation", 0)),
		g.world.diplomacy.recruit_blocker(sid, u.id)]


func _unit_actions(u: Unit) -> void:
	var row := UiTheme.hbox(4)
	_body.add_child(row)
	if u.kind == "airship":
		for a: Array in [["Explore", "cmd_explore", {"type": "explore", "pos": g.world.home_pos(), "radius": 140.0}], ["Trade run", "cmd_trade", {"type": "trade", "phase": "out"}],
				["Auto", "cmd_auto", {"type": "auto"}], ["Dock", "ui_home", {"type": "dock"}]]:
			var b := UiTheme.button(Loc.t(str(a[0])), str(a[1]))
			b.add_theme_font_size_override("font_size", 13)
			var o: Dictionary = a[2]
			b.pressed.connect(func() -> void:
				g.world.squad_ai.order_unit(u, o.duplicate(true))
				Sfx.play(&"ui_confirm"))
			row.add_child(b)
	elif u.kind == "drone" and u.squad_id < 0:
		var b := UiTheme.button(Loc.t("Auto-scout"), "cmd_auto", Loc.t("Explore the frontier on its own and report discoveries."))
		b.pressed.connect(func() -> void:
			g.world.squad_ai.order_unit(u, {"type": "auto"})
			Sfx.play(&"ui_confirm"))
		row.add_child(b)
	var f := UiTheme.button("", "ui_target", Loc.t("Centre the camera"))
	f.pressed.connect(func() -> void: g.focus_pos(u.pos))
	row.add_child(f)


func _first_open_squad() -> Squad:
	for s: Squad in g.world.squads:
		if s.members.size() < 6:
			return s
	return null


func _item_row(it: Dictionary, slot: String, u: Unit) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.flat(Color(0.09, 0.12, 0.18, 0.95), 6, UiTheme.BORDER_DIM, 1))
	var h := UiTheme.hbox(8)
	p.add_child(h)
	var ic := TextureRect.new()
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.custom_minimum_size = Vector2(52, 52)
	ic.texture = Icons.item_icon(it, 64)
	h.add_child(ic)
	var v := UiTheme.vbox(1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var q := str(it.get("quality", "common"))
	var nm := UiTheme.label(Loc.item_name(it), 16, Icons.quality_color(q), UiTheme.bold_font)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.custom_minimum_size = Vector2(170, 0)
	v.add_child(nm)
	var lines := ItemGen.describe(it)
	for i in mini(lines.size(), 3):
		var l := UiTheme.label(lines[i], 13, UiTheme.TEXT_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(170, 0)
		v.add_child(l)
	p.tooltip_text = "\n".join(lines)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	return p


func _equipment(u: Unit) -> void:
	var eq := u.equipment()
	for slot: String in ["weapon", "armor", "gadget"]:
		var row := UiTheme.hbox(6)
		row.add_child(UiTheme.label(Loc.t(slot.capitalize()), 14, UiTheme.GOLD))
		var change := UiTheme.button(Loc.t("Change" if _armory_slot != slot else "Close"), "ui_chest")
		change.add_theme_font_size_override("font_size", 12)
		change.custom_minimum_size = Vector2(0, 24)
		var sl := slot
		change.pressed.connect(func() -> void:
			_armory_slot = "" if _armory_slot == sl else sl
			refresh(true))
		row.add_child(change)
		_body.add_child(row)
		if eq.get(slot) is Dictionary:
			_body.add_child(_item_row(eq[slot], slot, u))
		else:
			_body.add_child(UiTheme.label(Loc.t("  — empty —"), 14, UiTheme.TEXT_DIM))
		if _armory_slot == slot:
			_armory_list(u, slot)


func _armory_list(u: Unit, slot: String) -> void:
	var items: Array = []
	for it: Dictionary in g.world.armory:
		if _slot_of(it) == slot:
			items.append(it)
	if u.equipment().get(slot) is Dictionary:
		var un := UiTheme.button(Loc.t("Unequip (to armory)"), "ui_close")
		un.pressed.connect(func() -> void:
			g.world.armory.append(u.equipment()[slot])
			u.equipment()[slot] = null
			_after_equip(u))
		_body.add_child(un)
	if items.is_empty():
		_body.add_child(UiTheme.label(Loc.t("The armory has no %s. Explore ruins and camps for loot.") % Loc.t(slot), 13, UiTheme.TEXT_DIM))
		return
	for it: Dictionary in items:
		var r := _item_row(it, slot, u)
		var eb := UiTheme.button(Loc.t("Equip"))
		eb.custom_minimum_size = Vector2(60, 28)
		eb.add_theme_font_size_override("font_size", 12)
		eb.pressed.connect(func() -> void:
			var old: Variant = u.equipment().get(slot)
			g.world.armory.erase(it)
			if old is Dictionary:
				g.world.armory.append(old)
			u.equipment()[slot] = it
			_after_equip(u))
		(r.get_child(0) as HBoxContainer).add_child(eb)
		_body.add_child(r)


func _after_equip(u: Unit) -> void:
	CharacterFactory.sync_dna(u)
	u.recompute_stats()
	g.world.unit_changed.emit(u)
	hud.portraits.invalidate("u%d" % u.id)
	_armory_slot = ""
	Sfx.play(&"ui_confirm")
	refresh(true)


static func _slot_of(it: Dictionary) -> String:
	var cat := str(it.get("category", ""))
	var slot := str(it.get("slot", ""))
	if cat == "weapon" or slot == "weapon":
		return "weapon"
	if cat == "armor" or slot == "armor":
		return "armor"
	if cat in ["gadget", "tool", "artifact"] or slot == "gadget":
		return "gadget"
	return slot


func _traits(u: Unit) -> void:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	_body.add_child(flow)
	for tid: String in u.character.get("traits", []):
		var d := DB.get_def("traits", tid)
		var pol := str(d.get("polarity", "flavor"))
		var col: Color = {"good": UiTheme.GOOD, "bad": UiTheme.BAD, "mixed": UiTheme.GOLD}.get(pol, UiTheme.ACCENT)
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UiTheme.flat(Color(0.1, 0.13, 0.2, 1.0), 10, col * Color(1, 1, 1, 0.8), 1))
		chip.tooltip_text = Loc.def_text("traits", tid, "description")
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		chip.add_child(UiTheme.label(Loc.def_name("traits", tid), 14, col))
		flow.add_child(chip)
	_body.add_child(UiTheme.label(Loc.t("Quirk"), 14, UiTheme.GOLD))
	var q := UiTheme.label(Loc.generated(u.character, "quirk"), 14)
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(q)
	var titles: Array = u.character.get("titles", [])
	if not titles.is_empty():
		_body.add_child(UiTheme.label(Loc.t("Titles"), 14, UiTheme.GOLD))
		var t := UiTheme.label(", ".join(PackedStringArray(titles.map(func(value: String) -> String: return Loc.t(value)))), 14)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(t)
	_body.add_child(UiTheme.label(Loc.t("Talent: %s") % Loc.t(str(u.character.get("talent", "")).capitalize()), 13, UiTheme.TEXT_DIM))


func _skills(u: Unit) -> void:
	var skills: Dictionary = u.character.get("skills", {})
	var ids: Array = skills.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(skills[a]) > int(skills[b]))
	for sid: String in ids:
		var row := UiTheme.hbox(6)
		var nm := UiTheme.label(Loc.def_name("skills", sid), 14)
		nm.custom_minimum_size = Vector2(110, 0)
		row.add_child(nm)
		var b := UiTheme.bar(UiTheme.GOLD if int(skills[sid]) >= 60 else Color("#8fb8d8"), 10)
		b.value = float(skills[sid]) / 100.0
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(b)
		row.add_child(UiTheme.label(str(int(skills[sid])), 14))
		var apt := float((u.character.get("aptitude", {}) as Dictionary).get(sid, 1.0))
		row.tooltip_text = Loc.t("Learning speed x%.2f") % apt
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		_body.add_child(row)


func _bio(u: Unit) -> void:
	var quote := UiTheme.label("\u201c%s\u201d" % Loc.generated(u.character, "bio"), 16, UiTheme.TEXT, UiTheme.title_font)
	quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(quote)
	var back := UiTheme.label(Loc.generated(u.character, "backstory"), 14, UiTheme.TEXT_DIM)
	back.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(back)
	var c := u.counters
	var facts := []
	for k: Array in [["kills", "foes defeated"], ["tiles_explored", "tiles explored"], ["built", "buildings raised"], ["chopped", "wood felled"],
			["mined", "stone & ore mined"], ["harvested", "food harvested"], ["loot_found", "finds"], ["days_survived", "days on the frontier"]]:
		if float(c.get(k[0], 0.0)) > 0.0:
			facts.append("%d %s" % [int(c[k[0]]), Loc.t(str(k[1]))])
	if not facts.is_empty():
		_body.add_child(UiTheme.label(Loc.t("Record"), 14, UiTheme.GOLD))
		var l := UiTheme.label(" · ".join(PackedStringArray(facts)), 14)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(l)


func _machine_info(u: Unit) -> void:
	var d := u.DB_archetype()
	var desc := UiTheme.label(Loc.def_text("units", str(d.get("id", u.kind)), "description"), 14, UiTheme.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(desc)
	var w: Dictionary = u.stats.get("weapon", {})
	if u.is_armed():
		_body.add_child(UiTheme.label(Loc.t("Weapon: %d dmg / %.1fs, range %.0f m") % [int(float(w.get("damage", 0)) * float(u.stats.get("damage_mult", 1.0))), float(w.get("cooldown", 1)), float(w.get("range", 1))], 14))
	_body.add_child(UiTheme.label(Loc.t("Armor %d · Vision %d m · Speed %.1f m/s") % [int(u.stats.get("armor", 0)), int(u.stats.get("vision", 0)), float(u.stats.get("move_speed", 0))], 14))
	if u.kind == "airship":
		_body.add_child(UiTheme.label(Loc.t("Cargo %d · flies over everything") % int(u.stats.get("cargo", 0)), 14))
	if not u.named.is_empty():
		var ab := []
		for aid: String in u.named.get("abilities", []):
			ab.append(Loc.def_name("generation/abilities", aid))
		_body.add_child(UiTheme.label(Loc.t("Abilities: ") + ", ".join(PackedStringArray(ab)), 14, UiTheme.GOLD))
		var bio := UiTheme.label(Loc.generated(u.named, "bio"), 13, UiTheme.TEXT_DIM)
		bio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(bio)


# --- buildings -------------------------------------------------------------------------------

func _build_building(b: Building) -> void:
	var d := b.def()
	var head := UiTheme.hbox(8)
	head.add_child(UiTheme.icon("bld_" + b.type, 48))
	var hv := UiTheme.vbox(2)
	hv.add_child(UiTheme.title(Loc.def_name("buildings", b.type), 22))
	hv.add_child(UiTheme.label(Loc.t("Level %d") % b.level if b.is_built() else Loc.t("Under construction"), 15, UiTheme.TEXT_DIM))
	head.add_child(hv)
	_body.add_child(head)
	var desc := UiTheme.label(Loc.def_text("buildings", b.type, "description"), 14, UiTheme.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(desc)
	_dyn = UiTheme.label("", 15, UiTheme.ACCENT)
	_dyn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_dyn)
	if not b.is_built():
		var cancel := UiTheme.button(Loc.t("Cancel construction (refund)"), "ui_close")
		cancel.pressed.connect(func() -> void:
			g.world.cancel_building(b)
			g.clear_selection())
		_body.add_child(cancel)
		return
	match b.type:
		"hearth":
			for lv: Dictionary in d.get("levels", []):
				if int(lv["level"]) == b.level + 1:
					var cost: Dictionary = lv.get("cost", {})
					var need := int(lv.get("requires_pop", 0))
					var up := UiTheme.button(Loc.t("Upgrade to %s (%s)") % [Loc.t(str(lv.get("name", ""))), _cost_text(cost)], "ui_star")
					up.disabled = g.world.population() < need or not g.world.economy.can_afford(cost)
					up.tooltip_text = Loc.t("Needs %d population. More housing and a larger building area.") % need
					up.pressed.connect(func() -> void:
						if g.world.economy.pay(cost):
							b.level += 1
							g.world.building_changed.emit(b)
							g.world.notify_key("sim.building.settlement_grows", {"building": {"table": "buildings", "id": b.type, "en": b.display_name()}}, "levelup", b.center())
							refresh(true))
					_body.add_child(up)
			_body.add_child(UiTheme.label(Loc.t("Population %d / housing %d") % [g.world.population(), g.world.housing()], 14))
		"workshop":
			_body.add_child(UiTheme.label(Loc.t("Queue machines (paid now, built by a worker):"), 14, UiTheme.GOLD))
			for arch: String in d.get("produces", []):
				var ad := g.world.colony._archetype(arch)
				var cost: Dictionary = ad.get("cost", {})
				var btn := UiTheme.button("%s  (%s)" % [Loc.def_name("robots" if str(ad.get("kind", "")) == "robot" else "units", arch), _cost_text(cost)], str(ad.get("class_icon", "")), Loc.t(str(ad.get("description", ""))))
				btn.disabled = not g.world.economy.can_afford(cost) or b.queue.size() >= 5
				var a := arch
				btn.pressed.connect(func() -> void:
					if g.world.economy.pay(cost):
						b.queue.append(a)
						Sfx.play(&"ui_confirm")
						refresh(true))
				_body.add_child(btn)
			if not b.queue.is_empty():
				_body.add_child(UiTheme.label(Loc.t("Queue: ") + ", ".join(PackedStringArray(b.queue.map(func(x: String) -> String: return Loc.t(str(g.world.colony._archetype(x).get("name", x)))))), 14))
		"sky_dock":
			_body.add_child(UiTheme.label(Loc.t("Merchant airships visit docks every few days."), 14, UiTheme.TEXT_DIM))


func _cost_text(cost: Dictionary) -> String:
	var parts := []
	for k: String in cost:
		parts.append("%d %s" % [int(cost[k]), Loc.t(k)])
	return ", ".join(PackedStringArray(parts))


# --- sites ---------------------------------------------------------------------------------

func _set_town_tab(tab: String) -> void:
	if tab == _town_tab:
		return
	_town_tab = tab
	refresh(true)
func _build_site(st: Dictionary) -> void:
	if str(st.get("kind", "")) == "town":
		TownPanel.build(_body, g, hud, st, _town_tab, Callable(self, "_set_town_tab"))
		return
	if str(st.get("kind", "")) == "village":
		VillagePanel.build(_body, g, hud, st)
		return
	var head := UiTheme.hbox(8)
	head.add_child(UiTheme.icon(str(st.get("icon", "poi_ruins")), 44))
	var hv := UiTheme.vbox(2)
	var nm := UiTheme.title(str(st["name"]), 21)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.custom_minimum_size = Vector2(230, 0)
	hv.add_child(nm)
	hv.add_child(UiTheme.label(Loc.t("%s · danger level %d") % [Loc.t(str(FactionAI.KIND_LABEL.get(st["kind"], st["kind"]))), int(st.get("level", 1))], 15, UiTheme.TEXT_DIM))
	head.add_child(hv)
	_body.add_child(head)
	var status := ""
	if bool(st.get("hostile", false)):
		if bool(st.get("cleared", false)):
			status = Loc.t("Cleared. Keep an outpost nearby or it may be reoccupied.")
		else:
			status = Loc.t("Hostile. Estimated strength %d (your selected squad: %d).") % [int(g.world.factions.site_strength(int(st["id"]))), int(_my_strength())]
	elif str(st["kind"]) == "trade_post":
		status = Loc.t("Merchants trade here. Send your airship on a trade run (select it, right-click this post).")
	elif str(st["kind"]) == "wanderer_camp":
		status = Loc.t("Travellers camp here. Walk someone over — they may join you.")
	if not (st.get("cache", []) as Array).is_empty() and not bool(st.get("looted", false)):
		status += Loc.t("\nSomething valuable is stashed here.")
	var l := UiTheme.label(status, 14, UiTheme.BAD if (st.get("hostile", false) and not st.get("cleared", false)) else UiTheme.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(l)
	var sq := g.world.get_squad(0) if not g.world.squads.is_empty() else null
	if bool(st.get("hostile", false)) and not bool(st.get("cleared", false)) and sq:
		for s: Squad in g.world.squads:
			var b := UiTheme.button(Loc.t("Send %s to attack") % s.name, "cmd_attack")
			var sid := s.id
			b.pressed.connect(func() -> void:
				g.world.squad_ai.order_squad(g.world.get_squad(sid), {"type": "attack", "site": int(st["id"]), "pos": Vector2(st["center"])})
				Sfx.play(&"ui_confirm"))
			_body.add_child(b)
	for s: Squad in g.world.squads:
		var b := UiTheme.button(Loc.t("Send %s to explore here") % s.name, "cmd_explore")
		var sid := s.id
		b.pressed.connect(func() -> void:
			g.world.squad_ai.order_squad(g.world.get_squad(sid), {"type": "explore", "pos": Vector2(st["center"]), "radius": 40.0})
			Sfx.play(&"ui_confirm"))
		_body.add_child(b)
	var f := UiTheme.button(Loc.t("Centre camera"), "ui_target")
	f.pressed.connect(func() -> void: g.focus_pos(Vector2(st["center"])))
	_body.add_child(f)


func _build_loot(bag: Dictionary) -> void:
	_body.add_child(UiTheme.title(Loc.t("Loot bag"), 22))
	_body.add_child(UiTheme.label(Loc.t("Recovered automatically by nearby members."), 14, UiTheme.TEXT_DIM))
	var gold := int(bag.get("gold", 0))
	var metal := int(bag.get("metal", 0))
	if gold > 0:
		_body.add_child(UiTheme.label(Loc.t("%d gold") % gold, 16, UiTheme.GOLD))
	if metal > 0:
		_body.add_child(UiTheme.label(Loc.t("%d metal") % metal, 16, UiTheme.TEXT))
	var items: Array = bag.get("items", [])
	for item: Dictionary in items:
		_body.add_child(_item_row(item, "loot", null))


func _my_strength() -> float:
	if g.sel_squad >= 0:
		return g.world.squad_ai.strength(g.world.get_squad(g.sel_squad))
	if not g.world.squads.is_empty():
		return g.world.squad_ai.strength(g.world.get_squad(0))
	return 0.0
