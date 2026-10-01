class_name GearworkPanel
extends RefCounted
## Shared workshop / town-smith controls. Equipped gear can be repaired and upgraded; only
## unequipped items can be dismantled. Each button uses an immutable item uid, never list indices.

static func build(body: VBoxContainer, g: Game, hud: Hud, sid: int = -1) -> void:
	var w := g.world
	var ready := w.gearwork.available(sid)
	body.add_child(UiTheme.label(Loc.t("Expedition gearwork"), 16, UiTheme.GOLD))
	var desc := UiTheme.label(Loc.t("Reforge trophies, upgrade gear up to +3, or salvage unwanted loot. Worn gear loses power; repair it here."), 13, UiTheme.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(desc)
	for theme: String in Dungeons.THEMES + ["wilds"]:
		var button := UiTheme.button(Loc.t("Forge %s · 18 metal, 45 gold + trophy") % Loc.t("relic." + theme), "ui_chest")
		button.add_theme_font_size_override("font_size", 12)
		button.disabled = not ready
		button.pressed.connect(func() -> void: _report(hud, w.gearwork.forge(theme, sid)))
		body.add_child(button)
	var items := w.armory.duplicate()
	for u: Unit in w.player_units():
		for it: Variant in u.equipment().values():
			if it is Dictionary:
				items.append(it)
	for item: Dictionary in items:
		var uid := int(item.get("uid", 0))
		var name_label := UiTheme.label("%s +%d · %d%%" % [Loc.item_name(item), int(item.get("upgrade", 0)), roundi(float(item.get("condition", 100)))], 13, Icons.quality_color(str(item.get("quality", "common"))))
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.tooltip_text = "\n".join(ItemGen.describe(item))
		body.add_child(name_label)
		var row := UiTheme.hbox(3)
		for action: String in ["repair", "upgrade", "dismantle"]:
			if str(item.get("category", "")) == "resource" and action != "dismantle":
				continue
			if action == "dismantle" and not w.armory.has(item):
				continue
			var button := UiTheme.button(Loc.t("gear.action." + action))
			button.add_theme_font_size_override("font_size", 12)
			button.custom_minimum_size = Vector2(0, 30)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.disabled = not ready or (action == "repair" and float(item.get("condition", 100)) >= 100) or (action == "upgrade" and int(item.get("upgrade", 0)) >= Gearwork.MAX_UPGRADE)
			if action != "dismantle":
				button.tooltip_text = Loc.t("gear.cost", {"resources": {"resources": w.gearwork.cost(item, action)}})
			else:
				button.tooltip_text = Loc.t("Destroy this unequipped item for metal.")
			button.pressed.connect(func() -> void: _report(hud, w.gearwork.act(uid, action, sid)))
			row.add_child(button)
		body.add_child(row)


static func _report(hud: Hud, error: String) -> void:
	if error != "":
		hud.g.toast.emit(Loc.t(error), "bad")
		Sfx.play(&"ui_error")
	else:
		Sfx.play(&"ui_confirm")
	hud.info_panel.refresh(true)
