class_name CameraRig
extends Node3D
## Orthographic isometric RTS camera: keyboard/edge scrolling and middle-drag panning,
## wheel zoom, smooth focusing, and ray picking against the terrain height field.

signal moved

const EDGE := 6.0

var world: World
var cam: Camera3D
var target := Vector3.ZERO
const yaw := LookDev.CAMERA_YAW_DEG
var zoom := LookDev.ZOOM_DEFAULT
var zoom_goal := LookDev.ZOOM_DEFAULT
var edge_scroll := true
var _mouse_seen := false
var bounds := Rect2(-400, -400, 800, 800)
var _focus_goal: Variant = null
var _dragging := false
var _drag_last := Vector2.ZERO
var _shake_time := 0.0
var _shake_duration := 0.0
var _shake_strength := 0.0


func request_shake(strength: float, duration: float) -> void:
	_shake_strength = maxf(_shake_strength, strength)
	_shake_duration = maxf(_shake_duration, duration)
	_shake_time = _shake_duration




func _ready() -> void:
	cam = LookDev.make_camera(target, zoom)
	add_child(cam)
	cam.make_current()


## Edge scrolling follows a real mouse only: a finger's last position (or the mouse emulated from
## touches) would otherwise scroll the map by itself on touch screens.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		_mouse_seen = true
	elif event is InputEventScreenTouch:
		_mouse_seen = false


func focus(p: Vector3, instant: bool = false) -> void:
	if instant:
		target = Vector3(p.x, target.y, p.z)
		_focus_goal = null
		_apply()
	else:
		_focus_goal = Vector3(p.x, 0.0, p.z)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_goal = clampf(zoom_goal * 0.88, LookDev.ZOOM_MIN, LookDev.ZOOM_MAX)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_goal = clampf(zoom_goal * 1.14, LookDev.ZOOM_MIN, LookDev.ZOOM_MAX)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
			_drag_last = mb.position
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		var d := mm.position - _drag_last
		_drag_last = mm.position
		pan_screen(d)
	elif event.is_action_pressed("cam_zoom_in"):
		zoom_goal = clampf(zoom_goal * 0.85, LookDev.ZOOM_MIN, LookDev.ZOOM_MAX)
	elif event.is_action_pressed("cam_zoom_out"):
		zoom_goal = clampf(zoom_goal * 1.18, LookDev.ZOOM_MIN, LookDev.ZOOM_MAX)


func pan_screen(delta: Vector2) -> void:
	var px := zoom / get_viewport().get_visible_rect().size.y
	_pan(Vector2(-delta.x, -delta.y / sin(deg_to_rad(-LookDev.CAMERA_PITCH_DEG))) * px)


## Zooms about a screen point so the ground beneath it remains anchored.
func zoom_at(screen: Vector2, factor: float) -> void:
	var before: Variant = screen_to_ground(screen)
	zoom_goal = clampf(zoom_goal * factor, LookDev.ZOOM_MIN, LookDev.ZOOM_MAX)
	zoom = zoom_goal
	_apply()
	if before is Vector3:
		var after: Variant = screen_to_ground(screen)
		if after is Vector3:
			target.x += before.x - after.x
			target.z += before.z - after.z
			_apply()


## Pan by a screen-aligned offset in metres (x right, y down).
func _pan(d: Vector2) -> void:
	var b := LookDev.camera_basis(yaw)
	var right := Vector3(b.x.x, 0, b.x.z).normalized()
	var down := Vector3(b.z.x, 0, b.z.z).normalized()
	target += right * d.x + down * d.y
	_focus_goal = null


func _process(delta: float) -> void:
	var dir := Vector2(Input.get_axis("cam_left", "cam_right"), Input.get_axis("cam_up", "cam_down"))
	if edge_scroll and _mouse_seen and DisplayServer.window_is_focused() and not _dragging:
		var vp := get_viewport()
		var mp := vp.get_mouse_position()
		var size := vp.get_visible_rect().size
		if Rect2(Vector2.ZERO, size).has_point(mp):
			if mp.x < EDGE:
				dir.x -= 1.0
			elif mp.x > size.x - EDGE:
				dir.x += 1.0
			if mp.y < EDGE:
				dir.y -= 1.0
			elif mp.y > size.y - EDGE:
				dir.y += 1.0
	if dir != Vector2.ZERO:
		_pan(dir.normalized() * zoom * 1.1 * delta)
	if _focus_goal is Vector3:
		var g: Vector3 = _focus_goal
		var cur := Vector2(target.x, target.z)
		var nxt := cur.lerp(Vector2(g.x, g.z), 1.0 - exp(-8.0 * delta))
		target.x = nxt.x
		target.z = nxt.y
		if nxt.distance_to(Vector2(g.x, g.z)) < 0.05:
			_focus_goal = null
	zoom = lerpf(zoom, zoom_goal, 1.0 - exp(-12.0 * delta))
	_apply(delta)


func _apply(delta: float = 1.0) -> void:
	target.x = clampf(target.x, bounds.position.x, bounds.end.x)
	target.z = clampf(target.z, bounds.position.y, bounds.end.y)
	if world:
		var gy := maxf(world.height_at(Vector2(target.x, target.z)), 0.0)
		target.y = lerpf(target.y, gy, clampf(delta * 4.0, 0.0, 1.0))
	cam.transform = LookDev.camera_transform(target, yaw)
	if _shake_time > 0.0:
		_shake_time = maxf(0.0, _shake_time - delta)
		var fade := _shake_time / maxf(0.001, _shake_duration)
		cam.position += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * _shake_strength * fade
	else:
		_shake_strength = 0.0
	cam.size = zoom
	moved.emit()


## Ground point under a screen position (terrain height field ray march), or null.
func screen_to_ground(sp: Vector2) -> Variant:
	if world == null:
		return null
	var o := cam.project_ray_origin(sp)
	var d := cam.project_ray_normal(sp)
	if d.y > -0.01:
		return null
	var top := 26.0
	var t0 := (o.y - top) / -d.y
	var prev := o + d * t0
	var step := 0.5
	for i in 140:
		var p := prev + d * step
		var h := maxf(world.height_at(Vector2(p.x, p.z)), -0.05)
		if p.y <= h:
			var lo := prev
			var hi := p
			for k in 7:
				var mid := (lo + hi) * 0.5
				if mid.y <= maxf(world.height_at(Vector2(mid.x, mid.z)), -0.05):
					hi = mid
				else:
					lo = mid
			return hi
		prev = p
	return null


func world_to_screen(p: Vector3) -> Vector2:
	return cam.unproject_position(p)
