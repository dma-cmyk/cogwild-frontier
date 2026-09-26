extends Control
## Art review sheet: all SVGs at 48px and 24px, all item shapes at three qualities.
## Run gallery_icons.tscn at 1600x900; -- --machine shows the fitted machine block.

const QUALITIES := ["junk", "crude", "common", "fine", "rare", "epic", "legendary", "anomalous"]

func _ready() -> void:
	get_window().content_scale_size = Vector2i(1600, 900)
	if "--machine" in OS.get_cmdline_user_args():
		_machine_preview()
		return
	var background := ColorRect.new()
	background.color = Color("202735")
	background.size = Vector2(1600, 900)
	add_child(background)
	_label("COGWILD FRONTIER  /  ICON ATLAS", Vector2(20, 8), 24, Color("f1e3bd"))
	_label("84 hand-drawn SVGs  /  48px + 24px  /  transparent glyphs", Vector2(960, 15), 17)
	for i in Icons.REQUIRED_IDS.size():
		var id: String = Icons.REQUIRED_IDS[i]
		var pos := Vector2(20 + (i % 14) * 112, 49 + (i / 14) * 68)
		_texture(Icons.get_icon(id), pos + Vector2(11, 0), 48)
		_texture(Icons.get_icon(id), pos + Vector2(68, 15), 24)
		_label(id, pos + Vector2(0, 48), 12)
	_label("QUALITY", Vector2(20, 463), 15)
	for i in QUALITIES.size():
		var quality: String = QUALITIES[i]
		var pos := Vector2(123 + i * 173, 459)
		_texture(Icons.item_icon(_item("ring", quality, 0.55), 32), pos, 32)
		_label(quality, pos + Vector2(40, 7), 14, Icons.quality_color(quality))
	_label("46 ITEM SHAPES  /  common (no glow), rare, legendary  /  appearance colours + glow halo", Vector2(20, 498), 16)
	for i in Icons.SHAPES.size():
		var shape: String = Icons.SHAPES[i]
		var pos := Vector2(20 + (i % 10) * 157, 530 + (i / 10) * 72)
		var qualities := ["common", "rare", "legendary"]
		for q in qualities.size():
			_texture(Icons.item_icon(_item(shape, qualities[q], 0.0 if q == 0 else 0.8), 40), pos + Vector2(q * 45, 0), 40)
		_label(shape, pos + Vector2(2, 43), 13)

func _item(shape: String, quality: String, glow: float) -> Dictionary:
	return {"quality": quality, "appearance": {"shape": shape, "primary": "#b7c4cb", "secondary": "#b9824e", "accent": "#68d9ed", "glow": glow}}

func _texture(texture: Texture2D, pos: Vector2, side: int) -> void:
	var rect := TextureRect.new()
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.texture = texture
	rect.position = pos
	rect.size = Vector2(side, side)
	add_child(rect)

func _label(text: String, pos: Vector2, font_size: int, color: Color = Color("aab8c7")) -> void:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)

func _machine_preview() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	var world := Node3D.new()
	add_child(world)
	LookDev.setup_preview(world, Vector3(0, 1, 0), 4.5)
	var block := BuildingVisuals.create("machine_block", "ancient", 17)
	world.add_child(block)
	block.set_construction(1.0)
	block.set_active(true)
	var body := block.get_node("StaticBody") as MeshInstance3D
	var mesh := body.mesh as ArrayMesh
	var arrays := mesh.surface_get_arrays(0)
	print("MACHINE_BLOCK aabb=", mesh.get_aabb(), " triangles=", (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3, " surfaces=", mesh.get_surface_count())
	var ground := MeshKit.new()
	ground.box(Vector3(0, -0.07, 0), Vector3(5, 0.1, 5), Color("646b52"))
	for s: float in [-1.0, 1.0]:
		ground.box(Vector3(s, 0, 0), Vector3(0.025, 0.02, 2.0), Color("d9b04c"))
		ground.box(Vector3(0, 0, s), Vector3(2.0, 0.02, 0.025), Color("d9b04c"))
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = ground.build()
	world.add_child(floor_mesh)
	_label("MACHINE BLOCK  /  2 x 2m footprint in gold  /  seed 17", Vector2(30, 24), 24, Color("f1e3bd"))
