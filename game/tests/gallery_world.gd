extends Node3D

var _elapsed := 0.0
var _vfx_timer := 0.0

func _ready() -> void:
	LookDev.setup_preview(self, Vector3(0, 1.5, 0), 28.0)
	_add_ground()
	_add_buildings()
	_add_props()
	_add_icon_panel()

func _process(delta: float) -> void:
	_elapsed += delta
	_vfx_timer += delta
	if _vfx_timer > 1.2:
		_vfx_timer = 0.0
		Vfx.spawn(self, &"discover_ping", Vector3(sin(_elapsed) * 5.0, 0.3, cos(_elapsed) * 5.0), Color("63d6df"), Vector3.UP)

func _add_ground() -> void:
	var kit := MeshKit.new()
	kit.box(Vector3(0, -0.16, 0), Vector3(26, 0.32, 22), Color("789c68"), Color("91b873"))
	var mi := MeshInstance3D.new(); mi.name = "DioramaGround"; mi.mesh = kit.build(); add_child(mi)
	var water := MeshInstance3D.new()
	var wk := MeshKit.new(); wk.box(Vector3(5, 0.015, -7), Vector3(10, 0.04, 2.1), Color("4c9bb1"))
	water.mesh = wk.build(); add_child(water)

func _add_buildings() -> void:
	var ids := ["hearth", "house", "storehouse", "workshop", "smelter", "windmill", "sky_dock", "watchtower", "bandit_tent", "bandit_hut", "machine_spire", "machine_foundry", "trade_hall", "trade_stall", "ruin_arch", "ruin_vault", "wreck_airship"]
	for i in ids.size():
		var id: String = ids[i]
		var b := BuildingVisuals.create(id, "frontier" if i < 8 else ("bandit" if i < 10 else ("ancient" if i < 12 else ("merchant" if i < 14 else "neutral"))), i * 11, 3 if id == "hearth" else 1)
		b.position = Vector3(-10.0 + float(i % 6) * 4.0, 0, -7.5 + float(i / 6) * 5.5)
		add_child(b)
		b.set_construction(0.4 if i == 5 else 1.0)
		b.set_active(true)

func _add_props() -> void:
	var props := ["tree_pine", "tree_oak", "tree_birch", "tree_dead", "ore_iron", "ore_crystal", "rock_large", "berry_bush", "crop_wheat_0", "crop_wheat_3", "crop_veg_0", "crop_veg_3", "bridge_plank", "fence", "crate", "barrel", "lantern_post"]
	for i in props.size():
		var mi := MeshInstance3D.new(); mi.name = "Prop_%s" % props[i]; mi.mesh = PropMeshes.get_mesh(props[i], i % max(PropMeshes.variant_count(props[i]), 1))
		mi.position = Vector3(-10.0 + float(i % 9) * 2.4, 0, 7.0 + float(i / 9) * 2.0)
		add_child(mi)

func _add_icon_panel() -> void:
	var layer := CanvasLayer.new(); layer.name = "IconGallery"; add_child(layer)
	var panel := ColorRect.new(); panel.position = Vector2(1180, 24); panel.size = Vector2(390, 820); panel.color = Color(0.06, 0.08, 0.12, 0.88); layer.add_child(panel)
	var title := Label.new(); title.text = "WORLD ICONS  •  ITEMS"; title.position = Vector2(20, 14); title.add_theme_color_override("font_color", Color("f1e3bd")); panel.add_child(title)
	var grid := GridContainer.new(); grid.columns = 8; grid.position = Vector2(16, 48); grid.size = Vector2(360, 740); grid.add_theme_constant_override("h_separation", 4); grid.add_theme_constant_override("v_separation", 4); panel.add_child(grid)
	for i in mini(48, Icons.REQUIRED_IDS.size()):
		var icon := TextureRect.new(); icon.texture = Icons.get_icon(Icons.REQUIRED_IDS[i]); icon.custom_minimum_size = Vector2(38, 38); icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; grid.add_child(icon)
	for shape: String in ["sword", "gear", "core", "ration", "relic", "amulet", "map", "orb"]:
		for quality: String in ["common", "rare"]:
			var item := TextureRect.new(); item.texture = Icons.item_icon({"uid": shape + quality, "quality": quality, "appearance": {"shape": shape, "primary": "#4f8a4b", "secondary": "#8a5a34", "accent": "#d9b04c", "glow": 0.3}}, 48); item.custom_minimum_size = Vector2(42, 42); item.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; item.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; grid.add_child(item)
