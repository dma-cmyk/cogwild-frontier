class_name LookDev
extends RefCounted
## Single source of the game's look: camera angle, sun, environment. The game view and every
## gallery / preview scene use these so art is always judged under in-game conditions.

## Isometric-style orthographic camera: looks from +X+Z toward -X-Z, so +X, +Z and +Y faces are
## visible and a model's front (+Z) faces the viewer (down-right on screen).
const CAMERA_PITCH_DEG := -30.0
const CAMERA_YAW_DEG := 45.0
const CAMERA_DISTANCE := 50.0
const ZOOM_DEFAULT := 28.0  # Camera3D.size (visible world height in metres)
const ZOOM_MIN := 12.0
const ZOOM_MAX := 64.0


static func camera_basis(yaw_deg: float = CAMERA_YAW_DEG) -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(CAMERA_PITCH_DEG), deg_to_rad(yaw_deg), 0.0), EULER_ORDER_YXZ)


## Camera transform looking at `target` from the standard angle.
static func camera_transform(target: Vector3, yaw_deg: float = CAMERA_YAW_DEG) -> Transform3D:
	var b := camera_basis(yaw_deg)
	return Transform3D(b, target + b.z * CAMERA_DISTANCE)


static func make_camera(target: Vector3, size: float = ZOOM_DEFAULT) -> Camera3D:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = size
	cam.near = 1.0
	cam.far = 260.0
	cam.transform = camera_transform(target)
	return cam


## Warm late-morning sun from the upper left of the screen.
static func make_sun() -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50.0, -75.0, 0.0)
	sun.light_color = Color("#fff0d4")
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 100.0
	return sun


static func make_environment() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#8ea6bb")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#b4c0d6")
	e.ambient_light_energy = 0.62
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_white = 5.0
	e.glow_enabled = true
	e.glow_intensity = 0.55
	e.glow_bloom = 0.04
	e.glow_hdr_threshold = 1.1
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.12
	e.adjustment_contrast = 1.04
	return e


## Adds sun + WorldEnvironment + camera to `parent` (gallery / preview helper). Returns the camera.
static func setup_preview(parent: Node, target: Vector3 = Vector3.ZERO, size: float = ZOOM_DEFAULT) -> Camera3D:
	parent.add_child(make_sun())
	var env := WorldEnvironment.new()
	env.environment = make_environment()
	parent.add_child(env)
	var cam := make_camera(target, size)
	parent.add_child(cam)
	cam.make_current()
	return cam
