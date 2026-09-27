class_name SquadMarkers
extends Node3D
## Camera-facing squad stance emblems, allocated once and repositioned as squads move.

const STANCE_ICONS := {
	"aggressive": "res://assets/icons/stance_aggressive.svg",
	"balanced": "res://assets/icons/stance_balanced.svg",
	"cautious": "res://assets/icons/stance_cautious.svg",
	"hold": "res://assets/icons/stance_hold.svg",
}

var _sprites: Dictionary = {}
var _last_stance: Dictionary = {}
var _hold_rings: Dictionary = {}


func setup(world: World) -> void:
	name = "SquadMarkers"
	refresh(world)


func refresh(world: World) -> void:
	for squad: Squad in world.squads:
		var sprite := _ensure_sprite(squad)
		var hold_ring := _ensure_hold_ring(squad)
		var count := 0
		var center := Vector2.ZERO
		for id: int in squad.members:
			var unit := world.get_unit(id)
			if unit and unit.alive and unit.state != Unit.State.DOWNED:
				center += unit.pos
				count += 1
		if count == 0:
			sprite.visible = false
			hold_ring.visible = false
			continue
		center /= float(count)
		sprite.visible = true
		var stance: String = squad.stance
		sprite.position = Vector3(center.x, world.ground_y(center) + 3.0, center.y)
		hold_ring.visible = stance == "hold"
		if hold_ring.visible:
			var hold_point: Vector2 = squad.mem.get("hold", squad.order.get("pos", center))
			hold_ring.position = Vector3(hold_point.x, world.ground_y(hold_point) + 0.3, hold_point.y)
		if _last_stance.get(squad.id) != stance:
			var icon_path := str(STANCE_ICONS.get(stance, STANCE_ICONS["balanced"]))
			sprite.texture = load(icon_path) as Texture2D
			_last_stance[squad.id] = stance

func _ensure_hold_ring(squad: Squad) -> MeshInstance3D:
	if _hold_rings.has(squad.id):
		return _hold_rings[squad.id] as MeshInstance3D
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#ffd36ae6")
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.render_priority = 4
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, material)
	for index: int in 65:
		var angle := TAU * float(index) / 64.0
		mesh.surface_add_vertex(Vector3(cos(angle) * 6.0, 0.0, sin(angle) * 6.0))
		mesh.surface_add_vertex(Vector3(cos(angle) * 5.7, 0.0, sin(angle) * 5.7))
	mesh.surface_end()
	var ring := MeshInstance3D.new()
	ring.name = "SquadHoldRadius%d" % squad.id
	ring.mesh = mesh
	ring.visible = false
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	_hold_rings[squad.id] = ring
	return ring

func _ensure_sprite(squad: Squad) -> Sprite3D:
	if _sprites.has(squad.id):
		return _sprites[squad.id] as Sprite3D
	var sprite := Sprite3D.new()
	sprite.name = "SquadStance%d" % squad.id
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.no_depth_test = true
	sprite.centered = true
	sprite.pixel_size = 0.015
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sprite)
	_sprites[squad.id] = sprite
	return sprite

