class_name Vfx
extends RefCounted
## Small one-shot particle effects. No global state or allocations survive the effect lifetime.

static var _mats: Dictionary = {}
static var _mesh: SphereMesh

const KINDS := [&"hit_spark", &"dust_puff", &"chop_chips", &"rock_chips", &"smoke_puff", &"level_up", &"loot_beam", &"heal", &"discover_ping", &"build_dust", &"muzzle_flash", &"explosion_small", &"death_poof"]

static func spawn(parent: Node, kind: StringName, pos: Vector3, color: Color = Color.WHITE, dir: Vector3 = Vector3.ZERO) -> void:
	if parent == null:
		return
	var p := CPUParticles3D.new()
	p.name = "VFX_%s" % String(kind)
	p.position = pos
	p.one_shot = true
	p.explosiveness = 0.86
	p.amount = 14
	p.lifetime = 0.7
	p.randomness = 0.35
	var velocity := dir.normalized() if dir.length_squared() > 0.001 else Vector3.UP
	var key := color.to_html()
	if not _mats.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.emission_enabled = color != Color.BLACK
		mat.emission = color
		mat.emission_energy_multiplier = 1.8
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mats[key] = mat
	if _mesh == null:
		_mesh = SphereMesh.new()
		_mesh.radius = 0.055
		_mesh.height = 0.11
		_mesh.radial_segments = 6
		_mesh.rings = 3
	p.mesh = _mesh
	p.material_override = _mats[key]
	match kind:
		&"hit_spark":
			p.amount = 18; p.lifetime = 0.32; p.spread = 70.0; p.direction = velocity; p.initial_velocity_min = 1.2; p.initial_velocity_max = 2.5; p.scale_amount_min = 0.7; p.scale_amount_max = 1.3
		&"dust_puff", &"build_dust":
			p.amount = 20; p.lifetime = 0.9; p.spread = 55.0; p.direction = Vector3.UP; p.initial_velocity_min = 0.18; p.initial_velocity_max = 0.55; p.scale_amount_min = 1.2; p.scale_amount_max = 2.8
		&"chop_chips", &"rock_chips":
			p.amount = 15; p.lifetime = 0.48; p.spread = 50.0; p.direction = velocity; p.initial_velocity_min = 0.7; p.initial_velocity_max = 1.8
		&"smoke_puff", &"death_poof":
			p.amount = 18; p.lifetime = 1.1; p.spread = 28.0; p.direction = Vector3.UP; p.initial_velocity_min = 0.2; p.initial_velocity_max = 0.7; p.scale_amount_min = 1.3; p.scale_amount_max = 3.0
		&"level_up", &"heal", &"discover_ping":
			p.amount = 24; p.lifetime = 1.2; p.spread = 8.0; p.direction = Vector3.UP; p.initial_velocity_min = 0.5; p.initial_velocity_max = 1.4; p.scale_amount_min = 0.7; p.scale_amount_max = 1.5
		&"loot_beam":
			p.amount = 28; p.lifetime = 4.0; p.explosiveness = 0.15; p.spread = 4.0; p.direction = Vector3.UP; p.initial_velocity_min = 0.05; p.initial_velocity_max = 0.12; p.scale_amount_min = 1.0; p.scale_amount_max = 2.2
		&"muzzle_flash":
			p.amount = 10; p.lifetime = 0.18; p.spread = 18.0; p.direction = velocity; p.initial_velocity_min = 1.8; p.initial_velocity_max = 3.2; p.scale_amount_min = 1.2; p.scale_amount_max = 2.4
		&"explosion_small":
			p.amount = 32; p.lifetime = 0.65; p.spread = 80.0; p.direction = velocity; p.initial_velocity_min = 0.8; p.initial_velocity_max = 2.8; p.scale_amount_min = 0.8; p.scale_amount_max = 2.5
		_:
			p.amount = 12; p.lifetime = 0.55; p.spread = 45.0; p.direction = velocity; p.initial_velocity_min = 0.3; p.initial_velocity_max = 1.0
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.emitting = true
