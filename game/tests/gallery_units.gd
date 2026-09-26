extends Node3D
## Art-direction gallery: all units share the in-game LookDev camera and a green diorama floor.

var portraits: PortraitRenderer
var portrait_strip: HBoxContainer

func _ready() -> void:
	var gallery_size := 11.0
	for arg: String in OS.get_cmdline_args():
		if arg.begins_with("--gallery_zoom="):
			gallery_size = float(arg.substr(15))
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--gallery_zoom="):
			gallery_size = float(arg.substr(15))
	LookDev.setup_preview(self, Vector3(0, 1.1, 3.5), 18.0)
	_add_ground()
	_add_units()
	_add_portrait_ui()

func _add_ground() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "GalleryGround"
	var kit := MeshKit.new()
	kit.box(Vector3(0, -0.18, 0), Vector3(26, 0.35, 18), Color("#5f8b58"), Color("#75a365"))
	ground.mesh = kit.build()
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(ground)

func _add_units() -> void:
	var rng := RngUtil.make(["gallery", 20260926])
	var roles: Array[String] = ["settler", "guard", "archer", "engineer", "farmer", "merchant", "bandit", "bandit_archer", "scholar", "hunter"]
	for i in roles.size():
		var style := "bandit" if roles[i].begins_with("bandit") else ("merchant" if roles[i] == "merchant" else "frontier")
		var race := AppearanceGen.RACES[i % AppearanceGen.RACES.size()]
		var dna := AppearanceGen.character(rng, race, roles[i], style, Color("#3a5da8") if style == "frontier" else Color.TRANSPARENT)
		var visual := UnitVisualFactory.create(dna)
		visual.position = Vector3(-7.8 + float(i % 5) * 3.6, 0, -3.7 + float(i / 5) * 2.7)
		if i % 4 == 1: visual.set_anim(UnitVisual.Anim.WALK)
		elif i % 4 == 2: visual.set_anim(UnitVisual.Anim.WORK)
		add_child(visual)
	var robots: Array[String] = ["work_bot", "hauler", "walker", "sentry", "turret"]
	for i in robots.size():
		var visual := UnitVisualFactory.create(AppearanceGen.robot(rng, robots[i], "frontier" if i < 3 else "ancient", Color("#3a5da8")))
		visual.position = Vector3(-6.2 + float(i) * 3.1, 0, 1.2)
		if i == 2: visual.set_anim(UnitVisual.Anim.WALK)
		add_child(visual)
	var drones: Array[String] = ["scout_drone", "repair_drone", "war_drone"]
	for i in drones.size():
		var visual := UnitVisualFactory.create(AppearanceGen.drone(rng, drones[i], "frontier" if i != 2 else "ancient", Color("#3a5da8")))
		visual.position = Vector3(-5.4 + float(i) * 3.0, 3.15, 4.0)
		add_child(visual)
	var ships: Array[String] = ["cargo_airship", "trader_airship", "raider_airship", "explorer_airship"]
	for i in ships.size():
		var visual := UnitVisualFactory.create(AppearanceGen.airship(rng, ships[i], "frontier" if i < 2 else ("bandit" if i == 2 else "merchant"), Color("#3a5da8")))
		visual.position = Vector3(-5.0 + float(i) * 3.6, 6.1, 5.7)
		visual.scale = Vector3.ONE * 0.72
		add_child(visual)

func _add_portrait_ui() -> void:
	var hide_ui := false
	var portrait_only := true
	for arg: String in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if arg == "--hide_ui": hide_ui = true
		elif arg == "--portrait_only": portrait_only = true
	
	portraits = PortraitRenderer.new()
	portraits.name = "PortraitRenderer"
	add_child(portraits)
	
	if hide_ui: return
	
	var layer := CanvasLayer.new()
	layer.name = "PortraitStrip"
	add_child(layer)
	var panel := ColorRect.new()
	panel.color = Color(0.06, 0.08, 0.12, 0.88)
	layer.add_child(panel)
	portrait_strip = HBoxContainer.new()
	portrait_strip.add_theme_constant_override("separation", 8)
	layer.add_child(portrait_strip)
	
	var count := 12 if portrait_only else 8
	var p_size := 128 if portrait_only else 80
	
	panel.position = Vector2(24, 790) if not portrait_only else Vector2(24, 600)
	panel.size = Vector2(850, 96) if not portrait_only else Vector2(1600, 140)
	portrait_strip.position = Vector2(32, 798) if not portrait_only else Vector2(32, 606)
	portrait_strip.size = Vector2(830, 80) if not portrait_only else Vector2(1580, 128)
	
	var rng := RngUtil.make(["portrait_gallery", 7])
	for i in count:
		var dna: Dictionary
		if i < 8:
			var race := AppearanceGen.RACES[i % 4]
			dna = AppearanceGen.character(rng, race, "guard" if i % 3 == 0 else "explorer", "frontier", Color("#3a5da8"))
		else:
			dna = AppearanceGen.robot(rng, AppearanceGen.ROBOT_ARCHETYPES[i % 5], "ancient", Color("#a07a4a"))
		var tex := portraits.get_portrait("gallery_%d" % i, dna, p_size)
		var image := TextureRect.new()
		image.custom_minimum_size = Vector2(p_size, p_size)
		image.texture = tex
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait_strip.add_child(image)
