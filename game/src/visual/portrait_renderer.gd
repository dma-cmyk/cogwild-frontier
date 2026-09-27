class_name PortraitRenderer
extends Node
## Portraits for the UI. Painted art first (SpriteLibrary: generated busts for people, the chip's
## front frame for machines; follows the unit's current look, so re-equipping updates it). Units
## without painted art get a render of the procedural model: one tiny private viewport/world is
## shared by a queued render and the returned texture is updated in place after the next frame.

var _viewport: SubViewport
var _world: World3D
var _queue: Array[Dictionary] = []
var _cached: Dictionary = {}
var _busy_key := ""
var _busy_visual: UnitVisual
var _busy_camera: Camera3D
var _busy_size := 128

func _ready() -> void:
	add_to_group("web_extra_art_refresh")
	_viewport = SubViewport.new()
	_viewport.name = "PortraitViewport"
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.size = Vector2i(128, 128)
	_world = World3D.new()
	_viewport.world_3d = _world
	add_child(_viewport)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0, 0, 0, 0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#d9e4ef")
	environment.ambient_light_energy = 1.15
	env.environment = environment
	_viewport.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 45, 0)
	sun.light_color = Color("#fff0d4")
	sun.light_energy = 1.4
	_viewport.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 225, 0)
	rim.light_color = Color("#b3d4ff")
	rim.light_energy = 0.8
	_viewport.add_child(rim)

func get_portrait(key: String, dna: Dictionary, size: int = 128) -> Texture2D:
	var painted := SpriteLibrary.portrait(dna)
	if painted != null:
		return painted
	if _cached.has(key):
		return (_cached[key] as Dictionary)["texture"] as Texture2D
	var blank := Image.create(size, size, false, Image.FORMAT_RGBA8)
	blank.fill(Color(0, 0, 0, 0))
	var texture := ImageTexture.create_from_image(blank)
	_cached[key] = {"texture":texture, "dna":dna.duplicate(true), "size":size}
	_queue.push_back({"key":key, "dna":dna.duplicate(true), "size":size})
	return texture

func invalidate(key: String) -> void:
	_cached.erase(key)
	for i in range(_queue.size() - 1, -1, -1):
		if str(_queue[i].get("key", "")) == key: _queue.remove_at(i)

## Replace procedural portraits already displayed in the HUD when optional painted art arrives.
## Update the existing ImageTexture in place so every TextureRect showing it refreshes immediately.
func refresh_after_web_extra_art() -> void:
	if not _busy_key.is_empty() and _cached.has(_busy_key):
		var busy_entry: Dictionary = _cached[_busy_key] as Dictionary
		if SpriteLibrary.portrait(busy_entry.get("dna", {}) as Dictionary) != null:
			_cancel_busy_render()
	for i in range(_queue.size() - 1, -1, -1):
		var queued: Dictionary = _queue[i]
		if SpriteLibrary.portrait(queued.get("dna", {}) as Dictionary) != null:
			_queue.remove_at(i)
	for key: Variant in _cached.keys():
		var cached: Dictionary = _cached[key] as Dictionary
		var painted := SpriteLibrary.portrait(cached.get("dna", {}) as Dictionary)
		if painted == null:
			continue
		var image := painted.get_image()
		if image == null or image.is_empty():
			continue
		if image.is_compressed():
			image.decompress()
		image.convert(Image.FORMAT_RGBA8)
		var size := int(cached.get("size", 128))
		if image.get_size() != Vector2i(size, size):
			image.resize(size, size, Image.INTERPOLATE_LANCZOS)
		var texture := cached.get("texture") as ImageTexture
		if texture != null:
			texture.update(image)


func _cancel_busy_render() -> void:
	if is_instance_valid(_busy_visual):
		_busy_visual.queue_free()
	if is_instance_valid(_busy_camera):
		_busy_camera.queue_free()
	_busy_visual = null
	_busy_camera = null
	_busy_key = ""

func _process(_delta: float) -> void:
	if _viewport == null: return
	if not _busy_key.is_empty():
		_capture_busy()
		return
	if _queue.is_empty(): return
	_start_render(_queue.pop_front() as Dictionary)

func _start_render(entry: Dictionary) -> void:
	_busy_key = str(entry["key"])
	_busy_size = int(entry["size"])
	_viewport.size = Vector2i(_busy_size, _busy_size)
	_busy_visual = UnitVisualFactory.create_mesh(entry["dna"] as Dictionary)
	_viewport.add_child(_busy_visual)
	MeshKit.apply_preview_material(_busy_visual)
	var kind := str(entry["dna"].get("kind", "character"))
	var h := _busy_visual.get_visual_height()
	var target := _busy_visual.get_head_position()
	_busy_camera = Camera3D.new()
	_busy_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	if kind == "character":
		_busy_camera.size = 0.78
		target.y -= 0.14
	else:
		_busy_camera.size = h * 0.95
		if kind != "robot": target = Vector3(0, h * 0.5, 0)
	_busy_camera.near = 0.05
	_busy_camera.far = 30.0
	_busy_camera.position = target + Vector3(1.5, 0.4, 2.0)
	_viewport.add_child(_busy_camera)
	_busy_camera.look_at(target, Vector3.UP)
	_busy_camera.make_current()

func _capture_busy() -> void:
	var image := _viewport.get_texture().get_image()
	if image == null or image.is_empty(): return
	image.convert(Image.FORMAT_RGBA8)
	var entry: Dictionary = _cached.get(_busy_key, {})
	var texture: ImageTexture = entry.get("texture") as ImageTexture
	if texture != null: texture.update(image)
	if is_instance_valid(_busy_visual): _busy_visual.queue_free()
	if is_instance_valid(_busy_camera): _busy_camera.queue_free()
	_busy_visual = null
	_busy_camera = null
	_busy_key = ""
