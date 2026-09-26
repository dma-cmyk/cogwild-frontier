class_name SpriteUnitVisual
extends UnitVisual
## A unit drawn from a painted chip sheet (SpriteLibrary): one camera-facing card whose frame is
## picked from the facing relative to the camera (rows down / left / right / up) and a walk cycle
## (columns: step, stand, step). Actions are small card motions: lunge, recoil, knock-back flash,
## hop, squash on work strokes, lying down when downed. Carried goods show as a resource icon.

const WALK_SEQ := [0, 1, 2, 1]
const WALK_RATE := 2.4  # frames per metre travelled
const ROW_DOWN := 0
const ROW_LEFT := 1
const ROW_RIGHT := 2
const ROW_UP := 3
const CARRY_ICONS := {"wood": "res_wood", "stone": "res_stone", "ore": "res_ore", "food": "res_food",
	"metal": "res_metal", "gold": "res_gold", "crystal": "res_energy"}

static var _quad: QuadMesh

var entry: Dictionary = {}
var card: MeshInstance3D
var _size := Vector2.ONE
var _row := ROW_DOWN
var _screen_dir := Vector2(0.0, -1.0)
var _walk := 0.0
var _hover := false
var _static := false
var _carry_icon: Sprite3D
var _dead_t := 0.0
var _sent_frame := Vector2(-1.0, -1.0)
var _sent_offset := Vector2(INF, INF)
var _sent_roll := INF
var _sent_flash := Color(0, 0, 0, -1)


func setup_sprite(p_dna: Dictionary, p_entry: Dictionary, hints: Dictionary) -> void:
	dna = p_dna.duplicate(true)
	kind = str(dna.get("kind", "character"))
	entry = p_entry
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
	_size = SpriteLibrary.chip_cell_size(entry, dna, hints)
	_hover = str(entry.get("anchor_mode", "")) == "center"
	_static = str(entry.get("id", "")) == "turret"
	card = MeshInstance3D.new()
	card.name = "Card"
	card.mesh = _quad
	card.material_override = SpriteLibrary.unit_material(entry)
	card.scale = Vector3(_size.x, _size.y, 1.0)
	card.custom_aabb = AABB(Vector3(-1.2, -1.0, -1.5), Vector3(2.4, 2.4, 3.0))
	card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	card.set_instance_shader_parameter("hue_shift", SpriteLibrary.hue_shift_for(dna))
	add_child(card)
	var cell: Array = entry.get("cell", [128, 128])
	_height = _size.y * float(entry.get("height_px", cell[1])) / float(cell[1])
	if _hover:
		_height *= 0.6
	held_name = str(dna.get("weapon", ""))
	_base_position = position


func _process(delta: float) -> void:
	if not is_instance_valid(card):
		return
	anim_time += delta
	action_time = maxf(0.0, action_time - delta)
	_update_direction()
	var frame := 1
	var offset := Vector2.ZERO
	var roll := 0.0
	var flash := Color(1, 1, 1, 0)
	match anim:
		Anim.WALK:
			_walk += delta * maxf(0.2, move_speed) * WALK_RATE
			frame = WALK_SEQ[int(_walk) % 4]
		Anim.WORK:
			frame = 1
		Anim.DOWNED:
			roll = -PI * 0.5 if _row != ROW_LEFT else PI * 0.5
			offset.y = -_size.y * 0.02
		Anim.DEAD:
			_dead_t += delta
			roll = (-PI * 0.5 if _row != ROW_LEFT else PI * 0.5) * clampf(_dead_t * 2.5, 0.0, 1.0)
			flash = Color(0.1, 0.08, 0.08, clampf(_dead_t * 0.5, 0.0, 0.45))
	if _hover:
		offset.y += sin(anim_time * (2.2 if kind == "drone" else 0.8)) * (0.06 if kind == "drone" else 0.18)
		if kind == "drone":
			frame = int(anim_time * 9.0) % 3
	if _static:
		frame = 1
	if action_time > 0.0 and anim != Anim.DEAD:
		var k := 1.0 - action_time / 0.45
		var pulse := sin(k * PI)
		match action:
			&"attack_melee":
				offset += _screen_dir * 0.22 * pulse
				frame = 2 if k < 0.5 else 0
			&"attack_ranged":
				offset -= _screen_dir * 0.08 * pulse
				if _static:
					frame = 2 if k < 0.35 else 0
			&"hit":
				offset -= _screen_dir * 0.12 * pulse
				flash = Color(1.0, 0.92, 0.85, 0.75 * (1.0 - k))
			&"cheer", &"levelup":
				offset.y += 0.28 * pulse
			_:
				if action.begins_with("work_"):
					offset += _screen_dir * 0.07 * pulse
					offset.y -= 0.04 * pulse
					frame = 0 if k < 0.5 else 2
	# instance parameters cost a render-server call each: only send what changed
	var fr := Vector2(float(frame), float(_row))
	if fr != _sent_frame:
		_sent_frame = fr
		card.set_instance_shader_parameter("frame", fr)
	if offset != _sent_offset:
		_sent_offset = offset
		card.set_instance_shader_parameter("offset", offset)
	if roll != _sent_roll:
		_sent_roll = roll
		card.set_instance_shader_parameter("roll", roll)
	if flash != _sent_flash:
		_sent_flash = flash
		card.set_instance_shader_parameter("flash", flash)
	if is_instance_valid(_carry_icon):
		_carry_icon.position = Vector3(0.0, _height * 0.95 + maxf(0.0, offset.y), 0.0)


## Picks the chip row from the unit's facing as seen on screen, with hysteresis.
func _update_direction() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var fwd := global_transform.basis.z
	var cb := cam.global_transform.basis
	var right := Vector3(cb.x.x, 0.0, cb.x.z).normalized()
	var away := -Vector3(cb.z.x, 0.0, cb.z.z).normalized()
	var sx := fwd.dot(right)
	var sy := fwd.dot(away)
	if absf(sx) + absf(sy) < 0.01:
		return
	_screen_dir = Vector2(sx, sy).normalized()
	var ang := rad_to_deg(atan2(sy, sx))
	var keep := 10.0
	var rows := {ROW_RIGHT: [-60.0, 60.0], ROW_UP: [60.0, 120.0], ROW_DOWN: [-120.0, -60.0]}
	if _row in rows:
		var r: Array = rows[_row]
		if ang >= float(r[0]) - keep and ang <= float(r[1]) + keep:
			return
	elif absf(ang) >= 120.0 - keep:
		return
	if ang > -60.0 and ang < 60.0:
		_row = ROW_RIGHT
	elif ang >= 60.0 and ang <= 120.0:
		_row = ROW_UP
	elif ang <= -60.0 and ang >= -120.0:
		_row = ROW_DOWN
	else:
		_row = ROW_LEFT


func set_anim(next_anim: int) -> void:
	if next_anim == Anim.DEAD and anim != Anim.DEAD:
		_dead_t = 0.0
	anim = next_anim
	anim_time = 0.0 if next_anim != Anim.WALK else anim_time


func trigger(trigger_action: StringName) -> void:
	action = trigger_action
	action_time = 0.45


func set_held(item_visual: String) -> void:
	held_name = item_visual


func set_carry(resource: String) -> void:
	carry_name = resource
	var icon_id := str(CARRY_ICONS.get(resource, ""))
	if icon_id.is_empty():
		if is_instance_valid(_carry_icon):
			_carry_icon.visible = false
		return
	if not is_instance_valid(_carry_icon):
		_carry_icon = Sprite3D.new()
		_carry_icon.name = "Carry"
		_carry_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_carry_icon.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		_carry_icon.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_carry_icon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_carry_icon)
	var tex := SpriteLibrary.icon_texture(icon_id)
	if tex == null:
		tex = Icons.get_icon(icon_id)
	_carry_icon.texture = tex
	_carry_icon.pixel_size = 0.5 / maxf(1.0, float(tex.get_width()))
	_carry_icon.visible = true


## Title / portrait previews render outside the map: a private material without fog of war.
func use_preview_material() -> void:
	var mat := (card.material_override as ShaderMaterial).duplicate() as ShaderMaterial
	mat.set_shader_parameter("no_fog", true)
	card.material_override = mat
	card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func get_head_position() -> Vector3:
	return Vector3(0.0, _height * (0.5 if _hover else 0.82), 0.0)


func get_muzzle_position() -> Vector3:
	return Vector3(0.0, _height * (0.4 if _hover else 0.6), 0.25)
