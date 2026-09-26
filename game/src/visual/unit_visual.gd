class_name UnitVisual
extends Node3D
## Cached low-poly unit mesh plus a tiny procedural animation rig.

enum Anim { IDLE, WALK, WORK, DOWNED, DEAD }

var kind: String = "character"
var dna: Dictionary = {}
var body_mesh: MeshInstance3D
var moving_mesh: MeshInstance3D
var leg_l_mesh: MeshInstance3D
var leg_r_mesh: MeshInstance3D
var rotor_mesh: MeshInstance3D
var anim: int = Anim.IDLE
var move_speed: float = 1.0
var anim_time: float = 0.0
var action: StringName = &""
var action_time: float = 0.0
var held_name: String = ""
var carry_name: String = ""
var _base_position := Vector3.ZERO
var _height := 1.2
var _leg_base_l := Vector3.ZERO
var _leg_base_r := Vector3.ZERO
var _rotor_base := Vector3.ZERO
var _spin := 0.0

static func build_meshes(p_dna: Dictionary) -> Array:
	var k := str(p_dna.get("kind", "character"))
	if k == "character":
		return [CharMesh.body(p_dna), CharMesh.leg(p_dna, -1), CharMesh.leg(p_dna, 1), CharMesh.gear(p_dna, str(p_dna.get("weapon", "none")), "")]
	if k == "robot":
		if str(p_dna.get("archetype", "")) == "walker":
			return [MachineMesh.robot(p_dna), MachineMesh.walker_leg(p_dna, -1), MachineMesh.walker_leg(p_dna, 1)]
		return [MachineMesh.robot(p_dna), null]
	if k == "drone":
		return [MachineMesh.drone(p_dna), MachineMesh.drone_rotors(p_dna)]
	if k == "airship":
		return [MachineMesh.airship(p_dna), MachineMesh.airship_props(p_dna)]
	return [CharMesh.body({}), null]

func configure(p_dna: Dictionary, meshes: Array) -> void:
	dna = p_dna.duplicate(true)
	kind = str(dna.get("kind", "character"))
	body_mesh = MeshInstance3D.new()
	body_mesh.name = "Body"
	body_mesh.mesh = meshes[0] as ArrayMesh
	body_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(body_mesh)
	if meshes.size() > 1 and meshes[1] is ArrayMesh and kind != "character":
		moving_mesh = MeshInstance3D.new()
		moving_mesh.name = "HeldOrProps"
		moving_mesh.mesh = meshes[1] as ArrayMesh
		moving_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(moving_mesh)
	if kind == "character" and meshes.size() == 4:
		leg_l_mesh = MeshInstance3D.new()
		leg_l_mesh.name = "LegL"
		leg_l_mesh.mesh = meshes[1] as ArrayMesh
		leg_l_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(leg_l_mesh)
		leg_r_mesh = MeshInstance3D.new()
		leg_r_mesh.name = "LegR"
		leg_r_mesh.mesh = meshes[2] as ArrayMesh
		leg_r_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(leg_r_mesh)
		moving_mesh = MeshInstance3D.new()
		moving_mesh.name = "Gear"
		moving_mesh.mesh = meshes[3] as ArrayMesh
		moving_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(moving_mesh)
	if kind == "robot" and meshes.size() == 3:
		leg_l_mesh = MeshInstance3D.new()
		leg_l_mesh.name = "LegL"
		leg_l_mesh.mesh = meshes[1] as ArrayMesh
		leg_l_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(leg_l_mesh)
		leg_r_mesh = MeshInstance3D.new()
		leg_r_mesh.name = "LegR"
		leg_r_mesh.mesh = meshes[2] as ArrayMesh
		leg_r_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(leg_r_mesh)
	if kind == "drone" or kind == "airship":
		rotor_mesh = moving_mesh
	var sc := float(dna.get("scale", 1.0))
	if kind == "robot" and meshes.size() == 3:
		_leg_base_l = Vector3(-MachineMesh.WALKER_HIP.x, MachineMesh.WALKER_HIP.y, MachineMesh.WALKER_HIP.z) * sc
		_leg_base_r = MachineMesh.WALKER_HIP * sc
	if kind == "airship":
		_rotor_base = MachineMesh.AIRSHIP_PROP_HUB * sc
	held_name = str(dna.get("weapon", ""))
	if kind == "character":
		_height = _character_height(dna)
	elif kind == "robot":
		_height = _robot_height(dna)
	elif kind == "drone":
		_height = 0.55
	else:
		_height = 3.9 * sc
	_base_position = position

func _process(delta: float) -> void:
	anim_time += delta * maxf(0.1, move_speed)
	action_time = maxf(0.0, action_time - delta)
	if not is_instance_valid(body_mesh): return
	body_mesh.position = Vector3.ZERO
	body_mesh.rotation = Vector3.ZERO
	if is_instance_valid(moving_mesh):
		moving_mesh.position = _rotor_base
		moving_mesh.rotation = Vector3.ZERO
	if is_instance_valid(leg_l_mesh):
		leg_l_mesh.position = _leg_base_l
		leg_l_mesh.rotation = Vector3.ZERO
	if is_instance_valid(leg_r_mesh):
		leg_r_mesh.position = _leg_base_r
		leg_r_mesh.rotation = Vector3.ZERO
	if kind == "drone" or kind == "airship":
		_spin += delta * (14.0 if kind == "drone" else 7.0)
		var hover := sin(_spin * (0.2 if kind == "drone" else 0.12)) * (0.05 if kind == "drone" else 0.12)
		position.y = _base_position.y + hover
		if kind == "airship":
			body_mesh.rotation.z = sin(_spin * 0.05) * 0.015
		if is_instance_valid(rotor_mesh):
			if kind == "airship":
				rotor_mesh.rotation.z = _spin
			else:
				rotor_mesh.rotation.y = _spin
		return
	position.y = _base_position.y
	if anim == Anim.WALK:
		var stride := sin(anim_time * 8.0) * 0.16
		body_mesh.position.y = absf(stride) * 0.12
		body_mesh.rotation.z = sin(anim_time * 4.0) * 0.025
		if is_instance_valid(moving_mesh): 
			moving_mesh.position.y = body_mesh.position.y
			moving_mesh.rotation.x = -sin(anim_time * 8.0) * 0.2
		if is_instance_valid(leg_l_mesh):
			leg_l_mesh.rotation.x = sin(anim_time * 8.0) * 0.4
		if is_instance_valid(leg_r_mesh):
			leg_r_mesh.rotation.x = -sin(anim_time * 8.0) * 0.4
	elif anim == Anim.WORK:
		var swing := sin(anim_time * 10.0) * 0.24
		if is_instance_valid(moving_mesh): moving_mesh.rotation.x = swing
	elif anim == Anim.DOWNED:
		body_mesh.rotation.x = -deg_to_rad(78.0)
		body_mesh.position = Vector3(0.0, 0.1, 0.0)
		if is_instance_valid(moving_mesh): moving_mesh.rotation.x = -deg_to_rad(78.0)
		if is_instance_valid(leg_l_mesh): leg_l_mesh.rotation.x = -deg_to_rad(78.0)
		if is_instance_valid(leg_r_mesh): leg_r_mesh.rotation.x = -deg_to_rad(78.0)
	elif anim == Anim.DEAD:
		var fall := clampf(1.0 - anim_time * 0.35, 0.0, 1.0)
		body_mesh.rotation.x = -deg_to_rad(90.0) * (1.0 - fall)
		body_mesh.position.y = -0.32 * (1.0 - fall)
		if is_instance_valid(leg_l_mesh): leg_l_mesh.rotation.x = body_mesh.rotation.x
		if is_instance_valid(leg_r_mesh): leg_r_mesh.rotation.x = body_mesh.rotation.x
		if is_instance_valid(moving_mesh):
			moving_mesh.rotation.x = body_mesh.rotation.x
			moving_mesh.position.y = body_mesh.position.y
	if action_time > 0.0:
		var pulse := sin((0.45 - action_time) * 20.0)
		if action in [&"attack_melee", &"work_chop", &"work_mine", &"work_build", &"work_farm"] and is_instance_valid(moving_mesh):
			moving_mesh.rotation.x = -0.55 * maxf(0.0, pulse)
		elif action == &"attack_ranged" and is_instance_valid(moving_mesh):
			moving_mesh.position.z = -0.07 * maxf(0.0, pulse)
		elif action == &"hit":
			body_mesh.position.z = -0.15 * maxf(0.0, pulse)
			if is_instance_valid(moving_mesh): moving_mesh.position.z = body_mesh.position.z
			if is_instance_valid(leg_l_mesh): leg_l_mesh.position.z = body_mesh.position.z
			if is_instance_valid(leg_r_mesh): leg_r_mesh.position.z = body_mesh.position.z
		elif action == &"cheer" or action == &"levelup":
			var hop := sin(minf(1.0, (0.45 - action_time) * 3.0) * PI) * 0.2
			body_mesh.position.y += hop
			if is_instance_valid(moving_mesh): moving_mesh.position.y += hop
			if is_instance_valid(leg_l_mesh): leg_l_mesh.position.y += hop
			if is_instance_valid(leg_r_mesh): leg_r_mesh.position.y += hop

func set_anim(next_anim: int) -> void:
	anim = next_anim
	anim_time = 0.0

func set_move_speed(speed: float) -> void:
	move_speed = maxf(0.05, speed)

func trigger(trigger_action: StringName) -> void:
	action = trigger_action
	action_time = 0.45
	if trigger_action.begins_with("work_"): anim = Anim.WORK
	elif trigger_action == &"hit": anim_time = 0.0
	elif trigger_action == &"cheer" or trigger_action == &"levelup": anim_time = 0.0

func set_held(item_visual: String) -> void:
	if kind != "character": return
	held_name = str(dna.get("weapon", "none")) if item_visual.is_empty() else item_visual
	if is_instance_valid(moving_mesh):
		moving_mesh.mesh = CharMesh.gear(dna, held_name, carry_name)
		moving_mesh.visible = true

func set_carry(resource: String) -> void:
	if kind != "character": return
	carry_name = resource
	if is_instance_valid(moving_mesh):
		moving_mesh.mesh = CharMesh.gear(dna, held_name if not held_name.is_empty() else "none", carry_name)
		moving_mesh.visible = not resource.is_empty() or held_name != "none"

func get_visual_height() -> float:
	return _height

func get_head_position() -> Vector3:
	if kind == "character": return Vector3(0.0, _character_height(dna) * 0.82, 0.05)
	if kind == "robot": return Vector3(0.0, _height * 0.78, 0.04)
	return Vector3(0.0, _height * 0.55, 0.0)

func get_muzzle_position() -> Vector3:
	if kind == "character": return Vector3(0.27, _character_height(dna) * 0.56, 0.34)
	if kind == "robot": return Vector3(0.0, _height * 0.62, 0.45)
	return Vector3(0.0, 0.0, 0.42)

static func _col(value: Variant, fallback: String) -> Color:
	var s := str(value)
	if s.is_empty(): s = fallback
	if not s.begins_with("#"): s = "#" + s
	return Color(s)

static func _character_height(d: Dictionary) -> float:
	return float(CharMesh.metrics(d).h)

static func _robot_height(d: Dictionary) -> float:
	var a := str(d.get("archetype", "work_bot"))
	if a == "walker": return 2.25 * float(d.get("scale", 1.0))
	if a == "hauler": return 1.25 * float(d.get("scale", 1.0))
	if a == "sentry": return 1.42 * float(d.get("scale", 1.0))
	if a == "turret": return 1.6 * float(d.get("scale", 1.0))
	return 1.0 * float(d.get("scale", 1.0))
