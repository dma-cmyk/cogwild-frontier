class_name UnitView
extends Node3D
## Presents one simulation unit: interpolated position, facing, animation state, one-shot actions,
## held tools and carried goods (UnitVisual), plus selection ring, health bar and a ground shadow
## for flying units.

const RING_PLAYER := Color("#4fd3ff")
const RING_ENEMY := Color("#ff5a4a")
const RING_NEUTRAL := Color("#ffd25a")

static var _ring_mesh: Mesh
static var _shadow_mesh: Mesh
static var _bar_mesh: QuadMesh
static var _bar_mat: ShaderMaterial
static var _mats: Dictionary = {}

var u: Unit
var w: World
var visual: UnitVisual
var ring: MeshInstance3D
var bar: MeshInstance3D
var shadow: MeshInstance3D
var selected := false
var hovered := false
var squad_color := Color.TRANSPARENT
var _anim := -1
var _held := "~"
var _carry := "~"
var _yaw := 0.0
var _dna_key := ""
var _bar_h := 1.4


static func clear_cache() -> void:
	_ring_mesh = null
	_shadow_mesh = null
	_bar_mesh = null
	_bar_mat = null
	_mats.clear()


static func _unshaded(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = c
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.no_depth_test = false
		_mats[key] = m
	return _mats[key]


static func _meshes() -> void:
	if _ring_mesh != null:
		return
	var tm := TorusMesh.new()
	tm.inner_radius = 0.46
	tm.outer_radius = 0.56
	tm.rings = 24
	tm.ring_segments = 4
	_ring_mesh = tm
	var cm := CylinderMesh.new()
	cm.top_radius = 0.5
	cm.bottom_radius = 0.5
	cm.height = 0.02
	cm.radial_segments = 16
	_shadow_mesh = cm
	_bar_mesh = QuadMesh.new()
	_bar_mesh.size = Vector2(0.9, 0.14)
	_bar_mat = ShaderMaterial.new()
	_bar_mat.shader = load("res://src/visual/shaders/hp_bar.gdshader")
	_bar_mat.render_priority = 10


func setup(world: World, unit: Unit) -> void:
	w = world
	u = unit
	_meshes()
	name = "Unit_%d" % u.id
	ring = MeshInstance3D.new()
	ring.mesh = _ring_mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	add_child(ring)
	bar = MeshInstance3D.new()
	bar.mesh = _bar_mesh
	bar.material_override = _bar_mat
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar.visible = false
	add_child(bar)
	if u.flying:
		shadow = MeshInstance3D.new()
		shadow.mesh = _shadow_mesh
		shadow.material_override = _unshaded(Color(0, 0, 0, 0.28))
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(shadow)
	rebuild_visual()
	_yaw = atan2(u.facing.x, u.facing.y)
	sync(1.0, 0.0)


func rebuild_visual() -> void:
	if visual:
		visual.queue_free()
	visual = UnitVisualFactory.create(u.dna)
	add_child(visual)
	_dna_key = str(u.dna.hash())
	_anim = -1
	_held = "~"
	_carry = "~"
	_bar_h = visual.get_visual_height() + 0.35
	var r := 0.55
	match u.kind:
		"airship":
			r = 3.5
		"robot":
			r = 0.55 if u.archetype == "work_bot" else 1.1
		"drone":
			r = 0.5
	ring.scale = Vector3.ONE * (r / 0.5)
	if shadow:
		shadow.scale = Vector3(r * 1.3, 1.0, r * (2.2 if u.kind == "airship" else 1.3)) / 0.5
	bar.scale = Vector3.ONE * (1.9 if u.kind == "airship" else 1.0)


func _ring_color() -> Color:
	if squad_color.a > 0.0:
		return squad_color
	if u.is_player():
		return RING_PLAYER
	if w.hostile("player", u.faction):
		return RING_ENEMY
	return RING_NEUTRAL


## Called every frame by WorldView. alpha = fraction of the current sim tick.
func sync(alpha: float, delta: float) -> void:
	var show := (u.alive or u.state == Unit.State.DEAD) and not u.hidden and (u.is_player() or u.visible)
	visible = show
	if not show:
		return
	if str(u.dna.hash()) != _dna_key:
		rebuild_visual()
	var p := u.prev_pos.lerp(u.pos, alpha)
	var gy := w.ground_y(p)
	var y := gy
	if u.flying:
		y = maxf(w.height_at(p), 0.0) + u.altitude
	position = Vector3(p.x, y, p.y)
	if shadow:
		shadow.position = Vector3(0, maxf(gy, 0.0) - y + 0.06, 0)
	var goal_yaw := atan2(u.facing.x, u.facing.y)
	_yaw = lerp_angle(_yaw, goal_yaw, 1.0 - exp(-10.0 * delta)) if delta > 0.0 else goal_yaw
	visual.rotation.y = _yaw
	var anim := UnitVisual.Anim.IDLE
	if u.state == Unit.State.DEAD or not u.alive:
		anim = UnitVisual.Anim.DEAD
	elif u.state == Unit.State.DOWNED:
		anim = UnitVisual.Anim.DOWNED
	elif u.moving:
		anim = UnitVisual.Anim.WALK
	elif u.state == Unit.State.WORK:
		anim = UnitVisual.Anim.WORK
	if anim != _anim:
		_anim = anim
		visual.set_anim(anim)
	visual.set_move_speed(float(u.stats.get("move_speed", 2.0)) if u.moving else 0.0)
	while not u.fx_queue.is_empty():
		visual.trigger(u.fx_queue.pop_front())
	if u.held != _held:
		_held = u.held
		visual.set_held(u.held)
	var carry := u.carry_res if u.carry_amount > 0 else ""
	if carry != _carry:
		_carry = carry
		visual.set_carry(carry)
	# ring & bar
	var show_ring := selected or hovered
	ring.visible = show_ring and u.alive
	if ring.visible:
		ring.material_override = _unshaded(_ring_color() if selected else _ring_color().lerp(Color.WHITE, 0.3) * Color(1, 1, 1, 0.6))
		ring.position = Vector3(0, (maxf(gy, 0.0) - y if u.flying else 0.0) + 0.06, 0)
	var ratio := u.hp_ratio()
	bar.visible = u.alive and u.state != Unit.State.DOWNED and (selected or ratio < 0.999 or hovered)
	if bar.visible:
		bar.position = Vector3(0, _bar_h, 0)
		bar.set_instance_shader_parameter("ratio", ratio)
		var col := Color("#58d65a") if u.is_player() else (Color("#e0493b") if w.hostile("player", u.faction) else Color("#e8c14a"))
		bar.set_instance_shader_parameter("fill_color", col)
		var e := -1.0
		if u.is_person() and u.is_player() and selected:
			e = clampf(u.energy / maxf(1.0, float(u.stats.get("energy_max", 100.0))), 0.0, 1.0)
		bar.set_instance_shader_parameter("ratio2", e)
