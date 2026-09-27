class_name Vfx
extends RefCounted
## One-shot combat and world effects: particles, floating combat numbers and melee slash arcs.
## Every node frees itself when its effect ends; only shared meshes/materials are cached.

static var _mats: Dictionary = {}
static var _mesh: SphereMesh
static var _slash_mesh: ArrayMesh

const KINDS := [&"hit_spark", &"dust_puff", &"chop_chips", &"rock_chips", &"smoke_puff", &"level_up", &"loot_beam", &"heal", &"discover_ping", &"build_dust", &"muzzle_flash", &"explosion_small", &"death_poof", &"slash_arc"]


static func _quality_scale(parent: Node) -> float:
	var quality: Node = parent.get_node_or_null("/root/Quality")
	return 0.55 if quality != null and quality.call("level") == "low" else 1.0


static func _make_text(parent: Node) -> Label3D:
	var created := Label3D.new()
	created.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	created.no_depth_test = true
	created.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	created.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	created.pixel_size = 0.009
	created.outline_size = 5
	created.font = ThemeDB.fallback_font
	created.font_size = 44
	created.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(created)
	return created


## Floating combat values are world-space labels, pooled separately from particle effects.
static func spawn_combat_text(parent: Node, kind: StringName, pos: Vector3, _color: Color = Color.WHITE) -> void:
	if parent == null:
		return
	var label := _make_text(parent)
	var text := Loc.t("Miss")
	var color := Color("#aeb7c5")
	var size := 34
	var rise := 1.05
	var kind_text := String(kind)
	if kind_text.begins_with("combat_damage|"):
		var damage_fields := kind_text.split("|")
		var amount := int(damage_fields[1]) if damage_fields.size() > 1 else 0
		var crit := damage_fields.size() > 2 and damage_fields[2] == "1"
		text = "-%d" % amount
		color = Color("#ffd05c") if crit else Color("#fff1dc")
		size = 56 if crit else 44
		rise = 1.35 if crit else 1.0
	elif kind_text.begins_with("combat_heal|"):
		var heal_fields := kind_text.split("|")
		text = "+%d" % (int(heal_fields[1]) if heal_fields.size() > 1 else 0)
		color = Color("#73ff9b")
		size = 40
		rise = 0.9
	label.text = text
	label.font_size = size
	label.modulate = color
	label.outline_modulate = Color("#19202a", 0.95)
	label.position = pos + Vector3(0, 0.28, 0)
	label.scale = Vector3.ONE
	var tween := parent.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position", label.position + Vector3(0.0, rise, 0.0), 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.38)
	tween.tween_callback(label.queue_free).set_delay(0.95)


static func _make_slash_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 12:
		var a0 := PI - PI * float(i) / 12.0
		var a1 := PI - PI * float(i + 1) / 12.0
		var outer0 := Vector3(cos(a0) * 0.62, sin(a0) * 0.62, 0.0)
		var inner0 := Vector3(cos(a0) * 0.49, sin(a0) * 0.49, 0.0)
		var outer1 := Vector3(cos(a1) * 0.62, sin(a1) * 0.62, 0.0)
		var inner1 := Vector3(cos(a1) * 0.49, sin(a1) * 0.49, 0.0)
		tool.add_vertex(outer0)
		tool.add_vertex(inner0)
		tool.add_vertex(outer1)
		tool.add_vertex(inner0)
		tool.add_vertex(inner1)
		tool.add_vertex(outer1)
	return tool.commit()


static func _make_slash(parent: Node, pos: Vector3, color: Color) -> MeshInstance3D:
	if _slash_mesh == null:
		_slash_mesh = _make_slash_mesh()
	var slash := MeshInstance3D.new()
	slash.name = "CombatSlash"
	slash.mesh = _slash_mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.no_depth_test = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	slash.material_override = material
	slash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	slash.position = pos
	parent.add_child(slash)
	return slash


static func _spawn_slash(parent: Node, pos: Vector3, color: Color) -> void:
	var slash := _make_slash(parent, pos, color)
	var material := slash.material_override as StandardMaterial3D
	var tween := parent.create_tween()
	tween.set_parallel(true)
	tween.tween_property(slash, "scale", Vector3(1.5, 1.5, 1.0), 0.22)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.22)
	tween.tween_callback(slash.queue_free).set_delay(0.24)


static func spawn(parent: Node, kind: StringName, pos: Vector3, color: Color = Color.WHITE, dir: Vector3 = Vector3.ZERO) -> void:
	if parent == null:
		return
	if kind == &"slash_arc":
		_spawn_slash(parent, pos, color)
		return
	var p := CPUParticles3D.new()
	p.name = "VFX_%s" % String(kind)
	p.position = pos
	p.one_shot = true
	p.explosiveness = 0.86
	p.amount = 14
	p.lifetime = 0.7
	p.randomness = 0.35
	p.spread = 45.0
	p.direction = Vector3.UP
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 1.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.5
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
	p.amount = maxi(1, roundi(float(p.amount) * _quality_scale(parent)))
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.emitting = true
