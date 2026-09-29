class_name SquadMarkers
extends Node3D
## Camera-facing squad stance emblems, allocated once and repositioned as squads move.

const STANCE_ICONS := {
	"aggressive": "res://assets/icons/stance_aggressive.svg",
	"balanced": "res://assets/icons/stance_balanced.svg",
	"cautious": "res://assets/icons/stance_cautious.svg",
	"hold": "res://assets/icons/stance_hold.svg",
}
const HOLD_RADIUS := 6.0  # matches the leash in SquadAI._engage / Combat._engage

var _sprites: Dictionary = {}
var _last_stance: Dictionary = {}
var _hold_rings: Dictionary = {}


func setup(world: World) -> void:
	name = "SquadMarkers"
	refresh(world)


func refresh(world: World) -> void:
	var live_ids: Dictionary = {}
	var centers: Dictionary = {}
	for squad: Squad in world.squads:
		live_ids[squad.id] = true
		var count := 0
		var center := Vector2.ZERO
		for id: int in squad.members:
			var unit := world.get_unit(id)
			if unit and unit.alive and unit.state != Unit.State.DOWNED:
				center += unit.pos
				count += 1
		if count > 0:
			centers[squad.id] = center / float(count)
	_cleanup_missing(live_ids)
	for squad: Squad in world.squads:
		var sprite := _ensure_sprite(squad)
		var hold_ring := _ensure_hold_ring(squad)
		if not centers.has(squad.id):
			sprite.visible = false
			hold_ring.visible = false
			continue
		var center: Vector2 = centers[squad.id]
		var overlap_rank := 0
		for prior: Squad in world.squads:
			if prior.id == squad.id:
				break
			if centers.has(prior.id) and center.distance_to(centers[prior.id]) < 2.4:
				overlap_rank += 1
		sprite.visible = true
		sprite.position = Vector3(center.x + float(overlap_rank % 2) * 0.45, world.ground_y(center) + 3.0 + float(overlap_rank) * 0.42, center.y)
		sprite.modulate = Color(1.0, 1.0, 1.0, maxf(0.42, 1.0 - float(overlap_rank) * 0.2))
		var stance: String = squad.stance
		hold_ring.visible = stance == "hold"
		if hold_ring.visible:
			var hold_point: Vector2 = squad.mem.get("hold", squad.order.get("pos", center))
			_draw_hold_ring(hold_ring, world, hold_point)
		if _last_stance.get(squad.id) != stance:
			var icon_path := str(STANCE_ICONS.get(stance, STANCE_ICONS["balanced"]))
			sprite.texture = load(icon_path) as Texture2D
			_last_stance[squad.id] = stance


func _cleanup_missing(live_ids: Dictionary) -> void:
	for id: Variant in _sprites.keys():
		if live_ids.has(id):
			continue
		var sprite := _sprites[id] as Sprite3D
		if is_instance_valid(sprite):
			sprite.queue_free()
		_sprites.erase(id)
		_last_stance.erase(id)
	for id: Variant in _hold_rings.keys():
		if live_ids.has(id):
			continue
		var ring := _hold_rings[id] as MeshInstance3D
		if is_instance_valid(ring):
			ring.queue_free()
		_hold_rings.erase(id)

## The ring that shows how far a squad set to hold will step from its ground. Rebuilt whenever the
## point moves so it follows the terrain instead of floating over it as a flat disc.
func _ensure_hold_ring(squad: Squad) -> MeshInstance3D:
	if _hold_rings.has(squad.id):
		return _hold_rings[squad.id] as MeshInstance3D
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	material.render_priority = 4
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ring := MeshInstance3D.new()
	ring.name = "SquadHoldRadius%d" % squad.id
	ring.material_override = material
	ring.visible = false
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	_hold_rings[squad.id] = ring
	return ring


func _draw_hold_ring(ring: MeshInstance3D, world: World, at: Vector2) -> void:
	var key := "%.0f,%.0f" % [at.x, at.y]
	if ring.get_meta("at", "") == key:
		return
	ring.set_meta("at", key)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var color := Color("#ffd36a")
	var steps := 64
	var before := Vector2.RIGHT
	for index in range(1, steps + 1):
		var angle := TAU * float(index) / float(steps)
		var after := Vector2(cos(angle), sin(angle))
		OrderMarkers.ribbon(mesh, world, at + before * HOLD_RADIUS, at + after * HOLD_RADIUS, color)
		before = after
	mesh.surface_end()
	ring.mesh = mesh
	ring.position = Vector3.ZERO

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

