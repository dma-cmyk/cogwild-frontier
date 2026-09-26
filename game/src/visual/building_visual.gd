class_name BuildingVisual
extends Node3D
## One building instance. The static geometry is a single merged mesh per construction stage
## (built and cached by BuildingVisuals); only genuinely moving or emitting parts get their own
## node: a spinning element (windmill sails), chimney smoke and a working light.

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
	set_process(on and _moving != null)


func _process(delta: float) -> void:
	if _moving != null:
		_moving.rotate(_moving_axis, delta * _spin_speed)
