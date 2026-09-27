class_name BuildingVisual
extends Node3D
## One building instance. The static geometry is a single merged mesh per construction stage
## (built and cached by BuildingVisuals); only genuinely moving or emitting parts get their own
## node: a spinning element (windmill sails), chimney smoke and a working light.
## With painted art (set_sprite) the picture is drawn on a camera-facing card, the stage mesh
## stays as an invisible shadow caster, construction reveals the picture from the bottom behind a
## painted scaffold, and smoke outlets follow the picture's chimneys.

var footprint: Vector2i = Vector2i.ONE
var type_id: String = ""
var style: String = "frontier"
var variant_seed: int = 0
var level: int = 1

var _stage_meshes: Array[ArrayMesh] = []
var _body: MeshInstance3D
var _moving: Node3D
var _moving_axis := Vector3(0, 0, 1)
var _spin_speed := 1.1
var _smokes: Array[CPUParticles3D] = []
var _light: OmniLight3D
var _anchors: Dictionary = {}
var _top_height: float = 1.0
var _active := false
var _construction := 1.0

static var _quad: QuadMesh
var _card: MeshInstance3D
var _scaffold: MeshInstance3D
var _sails: MeshInstance3D
var _sails_offset := Vector2.ZERO
var _sails_angle := 0.0
var _smoke_card: Array[Vector2] = []
var _cam_basis := Basis()


func configure(id: String, faction_style: String, seed: int, building_level: int,
		data: Dictionary) -> void:
	type_id = id
	style = faction_style
	variant_seed = seed
	level = clampi(building_level, 1, 3)
	footprint = data.get("footprint", Vector2i.ONE)
	_top_height = float(data.get("height", 2.0))
	_stage_meshes = data.get("stages", [] as Array[ArrayMesh])
	_anchors = data.get("anchors", {})
	if _body == null:
		_body = MeshInstance3D.new()
		_body.name = "StaticBody"
		add_child(_body)
	while _stage_meshes.size() < 4:
		_stage_meshes.append(_stage_meshes.back() if not _stage_meshes.is_empty() else ArrayMesh.new())
	set_construction(1.0)


## 0 = staked-out foundation, 0.18 = plinth + part walls + scaffold, 0.55 = scaffolded building,
## 0.82+ = finished.
func set_construction(progress: float) -> void:
	_construction = clampf(progress, 0.0, 1.0)
	if _body == null or _stage_meshes.is_empty():
		return
	var idx := 0
	if _construction >= 0.82:
		idx = 3
	elif _construction >= 0.55:
		idx = 2
	elif _construction >= 0.18:
		idx = 1
	_body.mesh = _stage_meshes[idx]
	if _card != null:
		(_card.material_override as ShaderMaterial).set_shader_parameter("reveal", clampf(_construction / 0.82, 0.0, 1.0))
		if _scaffold != null:
			_scaffold.visible = _construction < 0.82
		if _sails != null:
			_sails.visible = idx >= 3
	if _moving != null:
		_moving.visible = idx >= 3
	_apply_active(_active and idx >= 2)


func set_active(active: bool) -> void:
	_active = active
	_apply_active(active and _construction >= 0.55)


func get_top_height() -> float:
	return _top_height


## Local points of interest: &"door", &"banner", &"mooring" (sky_dock / trade_mast).
func get_anchor(name: StringName) -> Vector3:
	return _anchors.get(name, Vector3.ZERO)


## Attaches a node that spins around `axis` while the building is active (windmill sails).
func set_moving(node: Node3D, axis: Vector3) -> void:
	_moving = node
	_moving_axis = axis.normalized() if axis.length_squared() > 0.001 else Vector3(0, 0, 1)
	add_child(node)
	node.visible = _construction >= 0.82


func add_smoke(node: CPUParticles3D) -> void:
	_smokes.append(node)
	add_child(node)


func add_light(node: OmniLight3D) -> void:
	_light = node
	add_child(node)


func _apply_active(on: bool) -> void:
	for s in _smokes:
		s.emitting = on
	if _light != null:
		_light.visible = on
	set_process(on and (_moving != null or _sails != null or not _smoke_card.is_empty()))


func _process(delta: float) -> void:
	if _moving != null:
		_moving.rotate(_moving_axis, delta * _spin_speed)
	if _sails != null:
		_sails_angle -= delta * _spin_speed
		(_sails.material_override as ShaderMaterial).set_shader_parameter("roll", _sails_angle)
	if not _smoke_card.is_empty():
		_place_smoke()


## Draws the building from a painted picture ("art/buildings" entry). `scaffold` is the painted
## construction site shown until the building is finished.
func set_sprite(entry: Dictionary, scaffold: Dictionary, hue_shift: float, sails: Dictionary = {}) -> void:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_card = _make_card("Picture", entry, 0.05)
	(_card.material_override as ShaderMaterial).set_shader_parameter("hue_shift", hue_shift)
	if not scaffold.is_empty():
		_scaffold = _make_card("Scaffold", scaffold, 0.6)
	if _moving != null:
		_moving.queue_free()
		_moving = null
	if not sails.is_empty():
		_add_sails(entry, sails)
	var size := SpriteLibrary.building_card_size(entry, footprint)
	var px: Array = entry.get("size_px", [512, 512])
	var anchor := SpriteLibrary.building_anchor(entry)
	for p: Variant in entry.get("smoke_px", []):
		var a: Array = p
		_smoke_card.append(Vector2(float(a[0]) / float(px[0]) - anchor.x, anchor.y - float(a[1]) / float(px[1])) * size)
	if _smoke_card.size() != _smokes.size():
		for s in _smokes:
			s.queue_free()
		_smokes.clear()
		for i in _smoke_card.size():
			add_smoke(BuildingVisuals.make_smoke(Vector3.ZERO, 1.0))
	if float(entry.get("mooring_h", 0.0)) > 0.0 and _anchors.has(&"mooring"):
		_anchors[&"mooring"] = Vector3(0.0, float(entry["mooring_h"]), 0.0)
	set_construction(_construction)


func _make_card(node_name: String, entry: Dictionary, toward: float) -> MeshInstance3D:
	var card := MeshInstance3D.new()
	card.name = node_name
	card.mesh = _quad
	# a private copy: reveal / hue are per building (plain uniforms, see sprite_building.gdshader)
	var mat := SpriteLibrary.building_material(entry, footprint).duplicate() as ShaderMaterial
	if toward != 0.05:
		mat.set_shader_parameter("depth_toward", toward)
	card.material_override = mat
	var size := SpriteLibrary.building_card_size(entry, footprint)
	card.scale = Vector3(size.x, size.y, 1.0)
	card.custom_aabb = AABB(Vector3(-1.0, -1.0, -1.5), Vector3(2.0, 2.2, 3.0))
	card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(card)
	return card


## Windmill sails: a separate painted card turning around the hub drawn in the tower picture.
func _add_sails(entry: Dictionary, sails: Dictionary) -> void:
	var hub: Array = entry.get("hub_px", [])
	if hub.size() < 2:
		return
	var size := SpriteLibrary.building_card_size(entry, footprint)
	var px: Array = entry.get("size_px", [512, 512])
	var anchor := SpriteLibrary.building_anchor(entry)
	_sails_offset = Vector2(float(hub[0]) / float(px[0]) - anchor.x, anchor.y - float(hub[1]) / float(px[1])) * size
	var d := float(entry.get("sails_m", size.x * 1.1))
	var mat := ShaderMaterial.new()
	mat.shader = load(SpriteLibrary.UNIT_SHADER)
	mat.set_shader_parameter("sheet", SpriteLibrary.texture(str(sails.get("texture", ""))))
	mat.set_shader_parameter("grid", Vector2.ONE)
	mat.set_shader_parameter("anchor", Vector2(0.5, 0.5))
	mat.set_shader_parameter("depth_bias", 1.2)
	mat.set_shader_parameter("mirror_camera_quadrants", true)
	mat.set_shader_parameter("receive_shadow", 0.0)
	_sails = MeshInstance3D.new()
	_sails.name = "Sails"
	_sails.mesh = _quad
	_sails.material_override = mat
	var sp: Array = sails.get("size_px", [512, 512])
	_sails.scale = Vector3(d, d * float(sp[1]) / float(sp[0]), 1.0)
	_sails.custom_aabb = AABB(Vector3(-2.0, -2.0, -2.0), Vector3(4.0, 4.0, 4.0))
	_sails.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mat.set_shader_parameter("offset", _sails_offset)
	mat.set_shader_parameter("frame", Vector2.ZERO)
	add_child(_sails)


## Smoke outlets sit on the picture's chimneys: a point on the card, which depends on the camera.
func _place_smoke() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var b := cam.global_transform.basis
	if b.is_equal_approx(_cam_basis):
		return
	_cam_basis = b
	for i in mini(_smokes.size(), _smoke_card.size()):
		var c: Vector2 = _smoke_card[i]
		_smokes[i].global_position = global_position + b.x * c.x + b.y * c.y + b.z * 0.8
