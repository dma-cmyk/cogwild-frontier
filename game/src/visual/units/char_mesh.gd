class_name CharMesh
extends RefCounted
## Chibi villager builder. A character is split into four cached meshes so the rig can animate it
## with four MeshInstance3D at most:
##   body(d)          torso, head + face, hair, headgear, accessories, left arm and offhand
##                    (authored around the hip joint, so the rig can lean/bob the whole upper body)
##   leg(d, side)     one leg authored around its hip joint
##   gear(d, w, c)    right arm + held weapon/tool + carried load, authored around the shoulder
## Proportions follow contracts §1: ~1.1-1.3 m tall, head ≈ 35 % of the height, front = +Z.

const FACE_OUT := 0.004


# --- metrics ----------------------------------------------------------------------------------

## Rig measurements derived from the DNA (identical input => identical numbers).
static func metrics(d: Dictionary) -> Dictionary:
	var race := str(d.get("race", "human"))
	var body_type := str(d.get("body_type", "average"))
	var outfit := str(d.get("outfit", "tunic"))
	var h := 1.18 * clampf(float(d.get("height", 1.0)), 0.85, 1.15)
	match race:
		"stoutkin": h *= 0.93
		"sylvan": h *= 1.06
		"minotaur": h *= 1.10
		"centaur": h *= 1.08
		"harpy": h *= 1.02
		"lamia": h *= 1.04
		"oni": h *= 1.08
		"tengu": h *= 1.04
	var bw := 0.300
	match body_type:
		"slim": bw = 0.262
		"stocky": bw = 0.344
		"tall": bw = 0.284
		_: bw = 0.300
	if race == "stoutkin":
		bw += 0.036
	elif race == "minotaur":
		bw += 0.055
	elif race == "oni":
		bw += 0.035
	elif race == "sylvan":
		bw -= 0.020
	bw *= h / 1.18
	var leg_f := 0.300
	if race == "stoutkin":
		leg_f = 0.256
	elif race == "sylvan":
		leg_f = 0.322
	if body_type == "tall":
		leg_f += 0.018
	elif body_type == "stocky":
		leg_f -= 0.014
	var head_ry := h * 0.175
	var head_rx := head_ry * 0.92
	var head_rz := head_ry * 0.88
	match str(d.get("face", "round")):
		"long":
			head_ry *= 1.07
			head_rx *= 0.93
		"square":
			head_rx *= 1.04
			head_rz *= 1.02
	if race == "stoutkin":
		head_rx *= 1.05
	var skirt := outfit == "robe" or outfit == "dress"
	var hem := 0.0
	if outfit == "robe":
		hem = h * 0.085
	elif outfit == "dress":
		hem = h * 0.185
	return {
		"h": h,
		"bw": bw,
		"bd": bw * 0.70,
		"hip_y": h * leg_f,
		"hip_x": bw * 0.235,
		"torso_top": h * 0.655,
		"shoulder_y": h * 0.600,
		"arm_x": bw * 0.52,
		"head_y": h - head_ry,
		"head_rx": head_rx,
		"head_ry": head_ry,
		"head_rz": head_rz,
		"skirt": skirt,
		"hem_y": hem,
		"boot_h": h * 0.10,
	}


static func colors(d: Dictionary) -> Dictionary:
	var style := str(d.get("faction_style", "neutral"))
	var skin := UnitStyle.col(d.get("skin"), "#d09a78")
	var hair := UnitStyle.col(d.get("hair_color"), "#3c2922")
	var cloth := UnitStyle.col(d.get("outfit_color"), "#8a6a4a")
	var trim := UnitStyle.col(d.get("outfit_accent"), "#e9dcc0")
	return {
		"style": style,
		"skin": skin,
		"skin_dark": skin.darkened(0.14),
		"hair": hair,
		"hair_dark": hair.darkened(0.22),
		"cloth": cloth,
		"cloth_dark": cloth.darkened(0.20),
		"trim": trim,
		"accent": UnitStyle.accent(style),
		"leather": UnitStyle.leather(style),
		"metal": UnitStyle.metal(style),
		"dark_metal": UnitStyle.dark_metal(style),
		"wood": UnitStyle.wood(style),
		"eye": UnitStyle.col(d.get("eye_color"), "#2c4b62"),
		"glow": UnitStyle.glow_color(style),
	}


# --- generic shell helper ----------------------------------------------------------------------

## Partial ellipsoid surface: `p0`/`p1` are 0 (bottom pole) .. 1 (top pole), `az0`/`az1` degrees
## with 0 = +Z and 90 = +X. Used for hair caps, hoods, helmets and machine hulls.
static func shell(kit: MeshKit, center: Vector3, radii: Vector3, c: Color, seg: int, rings: int,
		p0: float, p1: float, az0: float = 0.0, az1: float = 360.0) -> void:
	for r in rings:
		var t0 := PI * lerpf(p0, p1, float(r) / float(rings)) - PI * 0.5
		var t1 := PI * lerpf(p0, p1, float(r + 1) / float(rings)) - PI * 0.5
		for s in seg:
			var a0 := deg_to_rad(lerpf(az0, az1, float(s) / float(seg)))
			var a1 := deg_to_rad(lerpf(az0, az1, float(s + 1) / float(seg)))
			kit.quad_out(_sph(center, radii, t0, a0), _sph(center, radii, t0, a1),
				_sph(center, radii, t1, a1), _sph(center, radii, t1, a0), center, c)


static func _sph(center: Vector3, radii: Vector3, t: float, a: float) -> Vector3:
	return center + Vector3(cos(t) * sin(a) * radii.x, sin(t) * radii.y, cos(t) * cos(a) * radii.z)


## Point on the face surface (relative to the head centre), pushed `out` metres forward.
static func _face_pt(m: Dictionary, x: float, y: float, out: float) -> Vector3:
	var u := clampf(x / float(m.head_rx), -0.97, 0.97)
	var v := clampf(y / float(m.head_ry), -0.97, 0.97)
	var k := sqrt(maxf(0.04, 1.0 - u * u - v * v))
	return Vector3(x, y, float(m.head_rz) * k + out)


# --- body --------------------------------------------------------------------------------------

## Torso, head, hair, headgear, accessories, left arm and offhand; origin = hip joint height.
static func body(d: Dictionary) -> ArrayMesh:
	var kit := MeshKit.new()
	var m := metrics(d)
	var c := colors(d)
	var seed_value := int(d.get("seed", 0))
	kit.push_trs(Vector3(0.0, -float(m.hip_y), 0.0))
	_torso(kit, m, c, d)
	_armor(kit, m, c, d)
	_accessory(kit, m, c, d, seed_value)
	_arm(kit, m, c, d, -1, _left_arm_pose(d))
	_offhand(kit, m, c, d)
	_head(kit, m, c, d, seed_value)
	_hair(kit, m, c, d)
	_headgear(kit, m, c, d)
	_race_features(kit, m, c, d)
	kit.pop()
	return kit.build()


static func _torso(kit: MeshKit, m: Dictionary, c: Dictionary, d: Dictionary) -> void:
	var outfit := str(d.get("outfit", "tunic"))
	var bw: float = m.bw
	var squash := Vector3(1.0, 1.0, float(m.bd) / bw)
	var hip: float = m.hip_y
	var top: float = m.torso_top
	var waist := lerpf(hip, top, 0.38)
	var cloth: Color = c.cloth
	var cloth_dark: Color = c.cloth_dark
	var trim: Color = c.trim
	# --- core body ---
	kit.push_trs(Vector3.ZERO, Vector3.ZERO, squash)
	kit.frustum(Vector3(0, hip - 0.035, 0), waist - hip + 0.035, bw * 0.47, bw * 0.43, cloth, 8)
	kit.frustum(Vector3(0, waist, 0), top - waist, bw * 0.43, bw * 0.53, cloth, 8)
	kit.frustum(Vector3(0, top - 0.005, 0), 0.02, bw * 0.53, bw * 0.46, cloth, 8)
	kit.pop()
	# shoulders
	for side in [-1.0, 1.0]:
		kit.ellipsoid(Vector3(side * float(m.arm_x) * 0.86, float(m.shoulder_y), 0.0),
			Vector3(bw * 0.20, bw * 0.19, bw * 0.17), cloth, 6, 4)
	# neck
	kit.cylinder(Vector3(0, top - 0.01, 0.005), float(m.head_ry) * 0.55, bw * 0.19, c.skin_dark, 7)
	# --- outfit specific silhouette ---
	match outfit:
		"robe":
			kit.push_trs(Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 0.86))
			kit.frustum(Vector3(0, float(m.hem_y), 0), waist - float(m.hem_y), bw * 0.82, bw * 0.45, cloth, 10)
			kit.pop()
			kit.torus(Vector3(0, waist + 0.01, 0), bw * 0.42, bw * 0.055, trim, 10, 4)
			_v_collar(kit, m, trim)
		"dress":
			kit.push_trs(Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 0.88))
			kit.frustum(Vector3(0, float(m.hem_y), 0), waist - float(m.hem_y) + 0.01, bw * 0.78, bw * 0.42, cloth, 10)
			kit.pop()
			kit.torus(Vector3(0, waist + 0.02, 0), bw * 0.42, bw * 0.05, trim, 10, 4)
			_v_collar(kit, m, trim)
		"coat":
			kit.push_trs(Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 0.80))
			kit.frustum(Vector3(0, hip - 0.10, 0), top - hip + 0.10, bw * 0.62, bw * 0.56, cloth_dark, 10)
			kit.pop()
			# open front panel showing a cream shirt
			kit.push_trs(Vector3(0, 0, float(m.bd) * 0.44), Vector3.ZERO, Vector3.ONE)
			kit.box(Vector3(0, lerpf(hip, top, 0.55), 0.0), Vector3(bw * 0.30, (top - hip) * 0.80, 0.03), trim)
			kit.pop()
			_lapels(kit, m, cloth)
			_belt(kit, m, c, waist + 0.012)
		"overalls":
			# shirt sleeves colour above, denim bib + straps in the outfit colour
			kit.push_trs(Vector3.ZERO, Vector3.ZERO, squash)
			kit.frustum(Vector3(0, lerpf(hip, top, 0.62), 0), top - lerpf(hip, top, 0.62), bw * 0.49, bw * 0.54, trim, 8)
			kit.pop()
			kit.push_trs(Vector3(0, 0, float(m.bd) * 0.40), Vector3.ZERO, Vector3.ONE)
			kit.box(Vector3(0, lerpf(hip, top, 0.62), 0.0), Vector3(bw * 0.58, (top - hip) * 0.55, 0.045), cloth)
			for side in [-1.0, 1.0]:
				kit.box(Vector3(side * bw * 0.24, lerpf(hip, top, 0.92), -0.005),
					Vector3(bw * 0.16, (top - hip) * 0.40, 0.04), cloth)
			kit.sphere(Vector3(-bw * 0.22, lerpf(hip, top, 0.78), 0.03), bw * 0.045, c.metal, 5, 3)
			kit.sphere(Vector3(bw * 0.22, lerpf(hip, top, 0.78), 0.03), bw * 0.045, c.metal, 5, 3)
			kit.pop()
		"leathers":
			kit.push_trs(Vector3.ZERO, Vector3.ZERO, squash)
			kit.frustum(Vector3(0, waist - 0.02, 0), top - waist + 0.03, bw * 0.46, bw * 0.56, c.leather, 8)
			kit.pop()
			_belt(kit, m, c, waist)
			kit.push_trs(Vector3(0, 0, float(m.bd) * 0.42), Vector3(0, 0, 24.0), Vector3.ONE)
			kit.box(Vector3(0, lerpf(hip, top, 0.72), 0.0), Vector3(bw * 0.13, (top - hip) * 0.85, 0.035), c.leather.darkened(0.18))
			kit.pop()
		"rags":
			_ragged_hem(kit, m, cloth_dark, hip + 0.01)
			kit.push_trs(Vector3(0, 0, float(m.bd) * 0.42), Vector3(0, 0, -18.0), Vector3.ONE)
			kit.box(Vector3(0, lerpf(hip, top, 0.62), 0.0), Vector3(bw * 0.14, (top - hip) * 0.7, 0.03), trim.darkened(0.25))
			kit.pop()
			_belt(kit, m, c, waist)
		_:
			# tunic
			kit.push_trs(Vector3.ZERO, Vector3.ZERO, squash)
			kit.frustum(Vector3(0, hip - 0.03, 0), (top - hip) * 0.52, bw * 0.56, bw * 0.46, cloth, 8)
			kit.pop()
			_belt(kit, m, c, waist + 0.005)
			_v_collar(kit, m, trim)


static func _belt(kit: MeshKit, m: Dictionary, c: Dictionary, y: float) -> void:
	var bw: float = m.bw
	kit.push_trs(Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, float(m.bd) / bw))
	kit.frustum(Vector3(0, y - bw * 0.06, 0), bw * 0.12, bw * 0.46, bw * 0.46, c.leather.darkened(0.15), 8)
	kit.pop()
	kit.box(Vector3(0, y, float(m.bd) * 0.47), Vector3(bw * 0.17, bw * 0.15, 0.03), c.accent)


static func _v_collar(kit: MeshKit, m: Dictionary, trim: Color) -> void:
	var bw: float = m.bw
	var top: float = m.torso_top
	for side in [-1.0, 1.0]:
		kit.push_trs(Vector3(side * bw * 0.13, top - 0.045, float(m.bd) * 0.40), Vector3(0, 0, side * 26.0))
		kit.box(Vector3.ZERO, Vector3(bw * 0.11, bw * 0.30, 0.03), trim)
		kit.pop()


static func _lapels(kit: MeshKit, m: Dictionary, cloth: Color) -> void:
	var bw: float = m.bw
	var top: float = m.torso_top
	for side in [-1.0, 1.0]:
		kit.push_trs(Vector3(side * bw * 0.18, top - 0.05, float(m.bd) * 0.44), Vector3(0, 0, side * 20.0))
		kit.box(Vector3.ZERO, Vector3(bw * 0.15, bw * 0.34, 0.035), cloth.lightened(0.10))
		kit.pop()


static func _ragged_hem(kit: MeshKit, m: Dictionary, col: Color, y: float) -> void:
	var bw: float = m.bw
	var pts := PackedVector2Array()
	var teeth := 9
	for i in teeth:
		var a := TAU * float(i) / float(teeth)
		pts.push_back(Vector2(cos(a) * bw * 0.52, sin(a) * bw * 0.40))
	kit.prism_xz(pts, y, y + (float(m.torso_top) - y) * 0.55, col)
	for i in teeth:
		var a2 := TAU * (float(i) + 0.5) / float(teeth)
		kit.push_trs(Vector3(cos(a2) * bw * 0.46, y, sin(a2) * bw * 0.35))
		kit.cone(Vector3(0, -bw * 0.16, 0), bw * 0.20, bw * 0.10, col.darkened(0.08), 4)
		kit.pop()


# --- head & face --------------------------------------------------------------------------------

static func _head(kit: MeshKit, m: Dictionary, c: Dictionary, d: Dictionary, seed_value: int) -> void:
	var hy: float = m.head_y
	var rx: float = m.head_rx
	var ry: float = m.head_ry
	var rz: float = m.head_rz
	var skin: Color = c.skin
	kit.push_trs(Vector3(0, hy, 0))
	kit.ellipsoid(Vector3.ZERO, Vector3(rx, ry, rz), skin, 8, 5)
	if str(d.get("face", "round")) == "square":
		kit.box(Vector3(0, -ry * 0.55, rz * 0.12), Vector3(rx * 1.55, ry * 0.52, rz * 1.5), skin)
	# --- eyes ---
	var eye_x := rx * 0.40
	var eye_y := ry * 0.02
	var eye_col: Color = c.eye
	for side in [-1.0, 1.0]:
		var p := _face_pt(m, side * eye_x, eye_y, FACE_OUT)
		kit.ellipsoid(p, Vector3(rx * 0.195, ry * 0.215, rz * 0.10), UnitStyle.EYE_DARK, 6, 3)
		kit.ellipsoid(p + Vector3(0, -ry * 0.015, 0.012), Vector3(rx * 0.125, ry * 0.135, rz * 0.055), eye_col, 5, 2)
		kit.ellipsoid(p + Vector3(side * rx * 0.055, ry * 0.075, 0.020),
			Vector3(rx * 0.055, ry * 0.055, rz * 0.03), UnitStyle.HIGHLIGHT, 5, 3)
	# --- brows ---
	var brow_col: Color = c.hair_dark if str(d.get("hair", "short")) != "bald" else c.skin_dark
	var brow_tilt := 7.0 if str(d.get("gender", "")) == "male" else 3.0
	for side in [-1.0, 1.0]:
		var bp := _face_pt(m, side * eye_x, ry * 0.255, FACE_OUT + 0.004)
		kit.push_trs(bp, Vector3(0, side * -12.0, side * brow_tilt))
		kit.box(Vector3.ZERO, Vector3(rx * 0.44, ry * 0.075, rz * 0.10), brow_col)
		kit.pop()
	# --- nose ---
	var np := _face_pt(m, 0.0, -ry * 0.175, 0.0)
	kit.push_trs(np + Vector3(0, 0, rz * 0.035), Vector3(14.0, 0, 0))
	kit.ellipsoid(Vector3.ZERO, Vector3(rx * 0.085, ry * 0.07, rz * 0.10), c.skin_dark, 5, 3)
	kit.pop()
	# --- mouth ---
	_mouth(kit, m, seed_value)
	# --- blush ---
	if UnitStyle.rand01(seed_value, 31) < 0.55:
		var blush := Color(0.93, 0.55, 0.50).lerp(c.skin, 0.35)
		for side in [-1.0, 1.0]:
			var cp := _face_pt(m, side * rx * 0.68, -ry * 0.14, FACE_OUT * 0.5)
			kit.ellipsoid(cp, Vector3(rx * 0.15, ry * 0.085, rz * 0.045), blush, 5, 3)
	# --- scar ---
	var scar := str(d.get("scar", "none"))
	if scar != "none":
		var sy := ry * 0.12 if scar == "eye" else -ry * 0.20
		var sp := _face_pt(m, rx * 0.52, sy, FACE_OUT + 0.002)
		kit.push_trs(sp, Vector3(0, -18.0, 16.0))
		kit.box(Vector3.ZERO, Vector3(rx * 0.045, ry * (0.42 if scar == "eye" else 0.22), rz * 0.05),
			c.skin.darkened(0.30))
		kit.pop()
	# --- ears (human / stoutkin) ---
	var race := str(d.get("race", "human"))
	if race == "human" or race == "stoutkin":
		var ear_r := rx * (0.26 if race == "human" else 0.30)
		for side in [-1.0, 1.0]:
			kit.ellipsoid(Vector3(side * rx * 0.94, -ry * 0.02, -rz * 0.06),
				Vector3(ear_r * 0.45, ear_r, ear_r * 0.75), c.skin, 4, 2)
	_facial_hair(kit, m, c, d)
	kit.pop()


static func _mouth(kit: MeshKit, m: Dictionary, seed_value: int) -> void:
	var rx: float = m.head_rx
	var ry: float = m.head_ry
	var smile := UnitStyle.rand01(seed_value, 57) < 0.7
	var y := -ry * 0.36
	var w := rx * 0.11
	for i in 3:
		var fx := (float(i) - 1.0) * rx * 0.115
		var lift := (0.0 if i == 1 else ry * 0.045) if smile else 0.0
		var p := _face_pt(m, fx, y + lift, FACE_OUT + 0.002)
		kit.push_trs(p, Vector3(0, 0, -signf(fx) * (18.0 if smile else 0.0)))
		kit.box(Vector3.ZERO, Vector3(w, ry * 0.048, rx * 0.06), UnitStyle.MOUTH)
		kit.pop()


static func _facial_hair(kit: MeshKit, m: Dictionary, c: Dictionary, d: Dictionary) -> void:
	var fh := str(d.get("facial_hair", "none"))
	if fh == "none":
		return
	var rx: float = m.head_rx
	var ry: float = m.head_ry
	var rz: float = m.head_rz
	var hair: Color = c.hair
	if fh == "mustache":
		for side in [-1.0, 1.0]:
			var p := _face_pt(m, side * rx * 0.20, -ry * 0.25, FACE_OUT + 0.004)
			kit.push_trs(p, Vector3(0, side * -14.0, side * -10.0))
			kit.box(Vector3.ZERO, Vector3(rx * 0.30, ry * 0.085, rz * 0.10), hair)
			kit.pop()
		return
	# beard: a rounded mass under the jaw plus a moustache
	shell(kit, Vector3(0, -ry * 0.26, rz * 0.06), Vector3(rx * 1.02, ry * 0.86, rz * 1.02),
		hair, 8, 3, 0.02, 0.44, -95.0, 95.0)
	kit.ellipsoid(Vector3(0, -ry * 0.92, rz * 0.34), Vector3(rx * 0.44, ry * 0.30, rz * 0.34), hair, 6, 3)
	for side in [-1.0, 1.0]:
		var p2 := _face_pt(m, side * rx * 0.20, -ry * 0.26, FACE_OUT + 0.004)
		kit.push_trs(p2, Vector3(0, side * -14.0, side * -8.0))
		kit.box(Vector3.ZERO, Vector3(rx * 0.32, ry * 0.09, rz * 0.10), hair)
		kit.pop()


static func _race_features(kit: MeshKit, m: Dictionary, c: Dictionary, d: Dictionary) -> void:
	var race := str(d.get("race", "human"))
	var rx: float = m.head_rx
	var ry: float = m.head_ry
	var rz: float = m.head_rz
	var hy: float = m.head_y
	if race == "sylvan":
		for side in [-1.0, 1.0]:
			kit.push_trs(Vector3(side * rx * 0.88, hy + ry * 0.05, -rz * 0.10), Vector3(0, 0, side * -52.0))
			kit.push_trs(Vector3.ZERO, Vector3(0, 0, 0), Vector3(1.0, 1.0, 0.45))
			kit.cone(Vector3.ZERO, ry * 0.92, rx * 0.26, c.skin, 5)
			kit.pop()
			kit.pop()
	elif race == "vulpin":
		var fur: Color = c.hair
		var fur_tip := fur.lightened(0.35)
		for side in [-1.0, 1.0]:
			kit.push_trs(Vector3(side * rx * 0.52, hy + ry * 0.72, -rz * 0.14), Vector3(0, 0, side * -18.0))
			kit.push_trs(Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.0, 0.42))
			kit.cone(Vector3.ZERO, ry * 0.86, rx * 0.40, fur, 5)
			kit.cone(Vector3(0, ry * 0.30, 0.0), ry * 0.32, rx * 0.20, fur_tip, 5)
			kit.pop()
			kit.pop()
		var bw: float = m.bw
		var base := Vector3(0, float(m.hip_y) + bw * 0.28, -float(m.bd) * 0.46)
		kit.push_trs(base, Vector3(-38.0, 0, 0))
		kit.ellipsoid(Vector3(0, bw * 0.28, 0), Vector3(bw * 0.30, bw * 0.52, bw * 0.30), fur, 6, 3)
		kit.ellipsoid(Vector3(0, bw * 0.72, 0), Vector3(bw * 0.24, bw * 0.30, bw * 0.24), fur_tip, 5, 2)
		kit.pop()
	elif race in ["minotaur", "oni"]:
		_horn_pair(kit, m, race)
	elif race == "centaur":
		_centaur_lower_body(kit, m, c)
	elif race == "harpy":
		_feather_wings(kit, m, Color("#694b38"), 0.68)
	elif race == "lamia":
		_lamia_lower_body(kit, m, c)
	elif race == "tengu":
		_beak(kit, m)
		_feather_wings(kit, m, Color("#443a32"), 0.52)


static func _horn_pair(kit: MeshKit, m: Dictionary, race: String) -> void:
	var rx: float = m.head_rx
	var ry: float = m.head_ry
	var rz: float = m.head_rz
	var hy: float = m.head_y
	var horn: Color = Color("#e3d1a3") if race == "minotaur" else Color("#d4b76f")
	for side in [-1.0, 1.0]:
		var base := Vector3(side * rx * 0.68, hy + ry * 0.60, -rz * 0.04)
		var tip := Vector3(side * rx * (1.34 if race == "minotaur" else 0.95),
			hy + ry * (1.12 if race == "minotaur" else 1.48), -rz * 0.18)
		kit.tube(base, tip, ry * 0.16, horn, 4)


static func _centaur_lower_body(kit: MeshKit, m: Dictionary, c: Dictionary) -> void:
	var bw: float = m.bw
	var hip_y: float = m.hip_y
	var coat: Color = c.hair
	var coat_light := coat.lightened(0.12)
	var coat_dark := coat.darkened(0.18)
	kit.ellipsoid(Vector3(0, hip_y * 0.73, -0.14), Vector3(bw * 1.42, hip_y * 0.78, 0.53), coat, 6, 2)
	kit.ellipsoid(Vector3(0, hip_y * 0.78, 0.22), Vector3(bw * 1.14, hip_y * 0.72, 0.34), coat_light, 5, 2)
	for z: float in [0.31, -0.48]:
		for side: float in [-1.0, 1.0]:
			var x := side * bw * 0.88
			var shoulder := Vector3(x, hip_y * 0.62, z)
			var knee := Vector3(x * 1.04, hip_y * 0.30, z + (0.035 if z > 0.0 else -0.045))
			var hoof := Vector3(x * 1.08, 0.035, knee.z + (0.04 if z > 0.0 else -0.035))
			kit.tube(shoulder, knee, 0.075, coat_light if z > 0.0 else coat, 4)
			kit.sphere(knee, 0.078, coat_dark, 4, 2)
			kit.tube(knee, hoof, 0.052, coat_dark, 4)
			kit.frustum(Vector3(hoof.x, 0.012, hoof.z), 0.095, 0.078, 0.092, Color("#342820"), 4)
	kit.tube(Vector3(0, hip_y * 0.82, -0.56), Vector3(0.04, hip_y * 0.46, -0.77), 0.055, coat_dark, 5)
	kit.tube(Vector3(0.04, hip_y * 0.46, -0.77), Vector3(0.11, hip_y * 0.40, -0.92), 0.04, coat_dark, 5)


static func _lamia_lower_body(kit: MeshKit, m: Dictionary, c: Dictionary) -> void:
	var hip_y: float = m.hip_y
	var scale_color: Color = c.skin.darkened(0.08)
	kit.tube(Vector3(0, hip_y * 0.96, 0.0), Vector3(0.04, hip_y * 0.64, -0.14), 0.15, scale_color, 5)
	var segments := 8
	for i in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var p0 := Vector3(cos(a0) * 0.23, 0.14, sin(a0) * 0.17 - 0.06)
		var p1 := Vector3(cos(a1) * 0.23, 0.14, sin(a1) * 0.17 - 0.06)
		kit.tube(p0, p1, 0.105, scale_color, 4)
	kit.tube(Vector3(0.23, 0.14, -0.06), Vector3(0.18, 0.23, -0.30), 0.095, scale_color, 4)
	kit.tube(Vector3(0.18, 0.23, -0.30), Vector3(0.02, 0.35, -0.42), 0.065, scale_color.lightened(0.06), 4)


static func _feather_wings(kit: MeshKit, m: Dictionary, feather: Color, span: float) -> void:
	var bw: float = m.bw
	var top: float = m.torso_top
	var bd: float = m.bd
	for side in [-1.0, 1.0]:
		kit.push_trs(Vector3(side * bw * 0.42, top * 0.80, -bd * 0.74))
		var outline := PackedVector2Array([
			Vector2(0, -0.13), Vector2(side * span * 0.38, 0.06), Vector2(side * span * 0.76, 0.30),
			Vector2(side * span * 0.58, 0.08), Vector2(side * span, 0.15), Vector2(side * span * 0.54, -0.02),
			Vector2(side * span * 0.73, -0.25), Vector2(side * span * 0.22, -0.32)
		])
		kit.plate(outline, 0.035, feather, feather.lightened(0.12))
		for i in 2:
			var start := Vector3(side * span * (0.24 + float(i) * 0.14), -0.04, -0.045)
			var finish := Vector3(side * span * (0.47 + float(i) * 0.16), 0.19 - float(i) * 0.16, -0.045)
			kit.tube(start, finish, 0.032, feather.lightened(0.22), 3)
		kit.pop()


static func _beak(kit: MeshKit, m: Dictionary) -> void:
	var ry: float = m.head_ry
	var rz: float = m.head_rz
	kit.push_trs(Vector3(0, float(m.head_y) - ry * 0.14, rz * 0.80), Vector3(90.0, 0.0, 0.0))
	kit.cone(Vector3.ZERO, ry * 0.72, ry * 0.20, Color("#b85e2c"), 5)
	kit.pop()

# --- hair ----------------------------------------------------------------------------------------

static func _hair(kit: MeshKit, m: Dictionary, c: Dictionary, d: Dictionary) -> void:
	var style := str(d.get("hair", "short"))
	if style == "bald":
		return
	var rx: float = m.head_rx
	var ry: float = m.head_ry
	var rz: float = m.head_rz
	var hy: float = m.head_y
	var hair: Color = c.hair
	var hair_lit := hair.lightened(0.10)
	var r := Vector3(rx * 1.055, ry * 1.045, rz * 1.06)
	kit.push_trs(Vector3(0, hy, 0))
	if style == "mohawk":
		shell(kit, Vector3.ZERO, r, hair, 10, 2, 0.60, 0.80, 95.0, 265.0)
		kit.push_trs(Vector3(0, 0, 0), Vector3(0, 90.0, 0))
		var pts := PackedVector2Array()
		pts.push_back(Vector2(-rz * 1.0, ry * 0.30))
		for i in 5:
			var t := float(i) / 4.0
			pts.push_back(Vector2(lerpf(-rz * 0.85, rz * 0.85, t), ry * (1.30 + 0.20 * sin(t * PI))))
			pts.push_back(Vector2(lerpf(-rz * 0.72, rz * 0.98, t + 0.06), ry * 1.05))
		pts.push_back(Vector2(rz * 0.95, ry * 0.25))
		kit.plate(pts, rx * 0.30, hair, hair_lit)
		kit.pop()
	else:
		# cap over the crown + mass down the back, leaving the face free
		shell(kit, Vector3.ZERO, r, hair, 10, 3, 0.615, 1.0)
		shell(kit, Vector3.ZERO, r, hair, 10, 3, 0.16, 0.63, 74.0, 286.0)
		# fringe locks over the forehead
		var locks := 4
		for i in locks:
			var fx := lerpf(-rx * 0.72, rx * 0.72, float(i) / float(locks - 1))
			var drop := ry * (0.30 if i % 2 == 0 else 0.20)
			kit.push_trs(_face_pt(m, fx, ry * 0.52, 0.008), Vector3(6.0, 0, fx * 40.0))
			kit.box(Vector3(0, -drop * 0.35, 0), Vector3(rx * 0.40, drop, rz * 0.13), hair_lit)
			kit.pop()
	match style:
		"long":
			shell(kit, Vector3(0, -ry * 0.55, -rz * 0.10), Vector3(rx * 1.02, ry * 1.62, rz * 1.02),
				hair, 10, 4, 0.06, 0.50, 80.0, 280.0)
			for side in [-1.0, 1.0]:
				kit.push_trs(Vector3(side * rx * 0.88, -ry * 0.10, rz * 0.12), Vector3(0, 0, side * 6.0))
				kit.box(Vector3(0, -ry * 0.48, 0), Vector3(rx * 0.30, ry * 1.05, rz * 0.42), hair)
				kit.pop()
		"ponytail":
			kit.push_trs(Vector3(0, ry * 0.42, -rz * 0.92), Vector3(36.0, 0, 0))
			kit.torus(Vector3.ZERO, ry * 0.16, ry * 0.06, c.accent, 8, 4)
			kit.ellipsoid(Vector3(0, -ry * 0.55, 0), Vector3(rx * 0.30, ry * 0.62, rz * 0.30), hair, 7, 4)
			kit.ellipsoid(Vector3(0, -ry * 1.05, 0), Vector3(rx * 0.17, ry * 0.30, rz * 0.17), hair_lit, 6, 3)
			kit.pop()
		"bun":
			kit.ellipsoid(Vector3(0, ry * 0.92, -rz * 0.42), Vector3(rx * 0.46, ry * 0.42, rz * 0.44), hair, 8, 4)
			kit.torus(Vector3(0, ry * 0.72, -rz * 0.42), ry * 0.42, ry * 0.055, c.accent, 8, 4)
		"braids":
			for side in [-1.0, 1.0]:
				for i in 3:
					var yb := -ry * (0.30 + 0.42 * float(i))
					kit.ellipsoid(Vector3(side * rx * 0.92, yb, rz * 0.05),
						Vector3(rx * 0.24, ry * 0.24, rz * 0.24), hair if i % 2 == 0 else hair_lit, 6, 3)
				kit.ellipsoid(Vector3(side * rx * 0.92, -ry * 1.42, rz * 0.05),
					Vector3(rx * 0.12, ry * 0.14, rz * 0.12), c.accent, 5, 3)
		"wild":
			for i in 7:
				var a := TAU * float(i) / 7.0
				kit.push_trs(Vector3(sin(a) * rx * 0.72, ry * 0.68, cos(a) * rz * 0.60),
					Vector3(-34.0, rad_to_deg(a), 0))
				kit.cone(Vector3.ZERO, ry * (0.52 + 0.16 * float(i % 3)), rx * 0.22, hair, 4)
				kit.pop()
		"short":
			for side in [-1.0, 1.0]:
				kit.box(Vector3(side * rx * 0.86, -ry * 0.18, -rz * 0.16),
					Vector3(rx * 0.22, ry * 0.42, rz * 0.55), hair)
	kit.pop()


# --- headgear -------------------------------------------------------------------------------------

static func _headgear(kit: MeshKit, m: Dictionary, c: Dictionary, d: Dictionary) -> void:
	var gear := str(d.get("headgear", "none"))
	if gear == "none":
		return
	var rx: float = m.head_rx
	var ry: float = m.head_ry
	var rz: float = m.head_rz
	var hy: float = m.head_y
	var style := str(c.style)
	kit.push_trs(Vector3(0, hy, 0))
	match gear:
		"hood":
			var hood_col: Color = c.cloth if style != "bandit" else UnitStyle.col("#b33a2e", "#b33a2e")
			if str(d.get("outfit", "")) == "leathers":
				hood_col = c.leather.lightened(0.12)
			var hr := Vector3(rx * 1.26, ry * 1.20, rz * 1.30)
			shell(kit, Vector3(0, ry * 0.03, -rz * 0.08), hr, hood_col, 12, 3, 0.68, 1.0)
			shell(kit, Vector3(0, ry * 0.03, -rz * 0.08), hr, hood_col, 12, 4, 0.10, 0.70, 46.0, 314.0)
			# opening rim
			for i in 9:
				var a := deg_to_rad(lerpf(46.0, -46.0, float(i) / 8.0))
				var t := lerpf(-0.55, 0.62, sin(PI * float(i) / 8.0))
				kit.ellipsoid(_sph(Vector3(0, ry * 0.03, -rz * 0.08), hr * 1.0, t, a),
					Vector3(rx * 0.14, ry * 0.14, rz * 0.14), hood_col.darkened(0.18), 5, 3)
			# mantle over the shoulders
			kit.push_trs(Vector3(0, -ry * 1.55, 0), Vector3.ZERO, Vector3(1, 1, 0.82))
			kit.frustum(Vector3.ZERO, ry * 0.42, float(m.bw) * 0.74, rx * 1.06, hood_col.darkened(0.10), 10)
			kit.pop()
		"helmet":
			var mt: Color = c.metal
			shell(kit, Vector3(0, ry * 0.06, 0), Vector3(rx * 1.14, ry * 1.16, rz * 1.16), mt, 12, 3, 0.56, 1.0)
			shell(kit, Vector3(0, ry * 0.06, 0), Vector3(rx * 1.14, ry * 1.16, rz * 1.16), mt, 12, 2, 0.30, 0.58, 58.0, 302.0)
			kit.torus(Vector3(0, ry * 0.38, 0), rx * 1.12, ry * 0.085, mt.darkened(0.22), 12, 4)
			# nose guard
			kit.push_trs(_face_pt(m, 0.0, ry * 0.30, 0.012))
			kit.box(Vector3(0, -ry * 0.22, 0), Vector3(rx * 0.16, ry * 0.52, rz * 0.10), mt.darkened(0.10))
			kit.pop()
			# crest
			kit.push_trs(Vector3(0, ry * 1.02, 0), Vector3(0, 90.0, 0))
			kit.plate(PackedVector2Array([Vector2(-rz * 0.78, 0), Vector2(rz * 0.62, 0),
				Vector2(rz * 0.30, ry * 0.46), Vector2(-rz * 0.46, ry * 0.40)]), rx * 0.13, c.accent)
			kit.pop()
		"cap":
			var cap_col: Color = c.cloth if style != "bandit" else c.leather
			shell(kit, Vector3(0, ry * 0.04, 0), Vector3(rx * 1.10, ry * 1.08, rz * 1.10), cap_col, 10, 3, 0.58, 1.0)
			kit.torus(Vector3(0, ry * 0.36, 0), rx * 1.08, ry * 0.07, c.accent, 10, 4)
			kit.push_trs(Vector3(0, ry * 0.42, rz * 0.86), Vector3(-8.0, 0, 0))
			kit.push_trs(Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.16, 1.0))
			kit.frustum(Vector3(0, -rx * 0.20, 0), rx * 0.40, rx * 0.86, rx * 0.72, cap_col.darkened(0.20), 8)
			kit.pop()
			kit.pop()
		"wide_hat":
			var straw := UnitStyle.STRAW
			kit.push_trs(Vector3(0, ry * 0.34, 0), Vector3.ZERO, Vector3(1.0, 0.24, 1.0))
			kit.frustum(Vector3(0, -rx * 0.28, 0), rx * 0.56, rx * 2.15, rx * 1.05, straw, 12, true, straw.lightened(0.10))
			kit.pop()
			kit.frustum(Vector3(0, ry * 0.34, 0), ry * 0.72, rx * 1.04, rx * 0.34, straw.lightened(0.07), 10, true)
			kit.torus(Vector3(0, ry * 0.46, 0), rx * 0.98, ry * 0.075, c.accent.darkened(0.08), 10, 4)
		"bandana":
			var band: Color = UnitStyle.col("#b33a2e", "#b33a2e") if style == "bandit" else c.accent
			shell(kit, Vector3(0, ry * 0.02, 0), Vector3(rx * 1.08, ry * 1.06, rz * 1.08), band, 12, 2, 0.62, 1.0)
			kit.torus(Vector3(0, ry * 0.38, 0), rx * 1.07, ry * 0.085, band.darkened(0.12), 12, 4)
			kit.ellipsoid(Vector3(-rx * 0.62, ry * 0.30, -rz * 0.86), Vector3(rx * 0.22, ry * 0.18, rz * 0.20), band, 5, 3)
			kit.push_trs(Vector3(-rx * 0.80, ry * 0.18, -rz * 0.95), Vector3(0, 30.0, 24.0))
			kit.plate(PackedVector2Array([Vector2(-rx * 0.10, 0), Vector2(rx * 0.10, 0),
				Vector2(rx * 0.22, -ry * 0.85), Vector2(-rx * 0.05, -ry * 0.72)]), 0.012, band.darkened(0.06))
			kit.pop()
		"goggles":
			var frame: Color = c.metal.darkened(0.08)
			kit.torus(Vector3(0, ry * 0.46, 0), rx * 1.06, ry * 0.075, c.leather.darkened(0.12), 12, 4)
			for side in [-1.0, 1.0]:
				var gp := _face_pt(m, side * rx * 0.40, ry * 0.46, 0.006)
				kit.push_trs(gp, Vector3(-16.0, 0, 0))
				kit.torus(Vector3.ZERO, rx * 0.30, rx * 0.085, frame, 9, 4)
				kit.push_trs(Vector3.ZERO, Vector3(90.0, 0, 0))
				kit.cylinder(Vector3(0, -rx * 0.03, 0), rx * 0.06, rx * 0.26,
					MeshKit.glow(UnitStyle.col("#8fd9ff", "#8fd9ff"), 0.35), 9)
				kit.pop()
				kit.pop()
		"circlet":
			kit.torus(Vector3(0, ry * 0.44, 0), rx * 1.06, ry * 0.055, UnitStyle.GOLD, 12, 4)
			kit.push_trs(_face_pt(m, 0.0, ry * 0.50, 0.006))
			kit.ellipsoid(Vector3.ZERO, Vector3(rx * 0.14, ry * 0.16, rz * 0.10),
				MeshKit.glow(c.glow, 0.5), 6, 3)
			kit.pop()
	kit.pop()


# --- armour, accessories --------------------------------------------------------------------------

static func _armor(kit: MeshKit, m: Dictionary, c: Dictionary, d: Dictionary) -> void:
	var armor := str(d.get("armor", "none"))
	if armor == "none":
		return
	var bw: float = m.bw
	var top: float = m.torso_top
	var hip: float = m.hip_y
	var waist := lerpf(hip, top, 0.38)
	var squash := Vector3(1.0, 1.0, float(m.bd) / bw)
	match armor:
		"leather":
			kit.push_trs(Vector3.ZERO, Vector3.ZERO, squash)
			kit.frustum(Vector3(0, waist - 0.01, 0), top - waist + 0.01, bw * 0.48, bw * 0.575, c.leather, 8)
			kit.pop()
			kit.push_trs(Vector3(0, 0, float(m.bd) * 0.46), Vector3(0, 0, 30.0))
			kit.box(Vector3(0, lerpf(hip, top, 0.75), 0), Vector3(bw * 0.12, (top - hip) * 0.8, 0.025), c.leather.darkened(0.22))
			kit.pop()
			for side in [-1.0, 1.0]:
				shell(kit, Vector3(side * float(m.arm_x) * 0.88, float(m.shoulder_y), 0),
					Vector3(bw * 0.24, bw * 0.22, bw * 0.21), c.leather.lightened(0.08), 7, 3, 0.45, 1.0)
		"chain":
			kit.push_trs(Vector3.ZERO, Vector3.ZERO, squash)
			kit.frustum(Vector3(0, hip - 0.02, 0), top - hip + 0.02, bw * 0.52, bw * 0.575, c.dark_metal.lightened(0.10), 10)
			kit.pop()
			kit.torus(Vector3(0, top - 0.02, 0), bw * 0.44, bw * 0.06, c.metal.darkened(0.15), 10, 4)
			_belt(kit, m, c, waist)
		"plate":
			kit.push_trs(Vector3.ZERO, Vector3.ZERO, squash)
			kit.frustum(Vector3(0, waist - 0.02, 0), (top - waist) * 0.75, bw * 0.50, bw * 0.60, c.metal, 8)
			kit.frustum(Vector3(0, waist + (top - waist) * 0.72, 0), (top - waist) * 0.30, bw * 0.60, bw * 0.50, c.metal.lightened(0.06), 8)
			kit.frustum(Vector3(0, hip + 0.01, 0), (waist - hip) * 0.75, bw * 0.54, bw * 0.50, c.metal.darkened(0.08), 8)
			kit.pop()
			kit.push_trs(Vector3(0, 0, float(m.bd) * 0.48))
			kit.box(Vector3(0, lerpf(hip, top, 0.72), 0), Vector3(bw * 0.30, (top - hip) * 0.30, 0.03), c.cloth)
			kit.ellipsoid(Vector3(0, lerpf(hip, top, 0.72), 0.02), Vector3(bw * 0.12, bw * 0.13, 0.03), c.accent, 6, 3)
			kit.pop()
			for side in [-1.0, 1.0]:
				shell(kit, Vector3(side * float(m.arm_x) * 0.92, float(m.shoulder_y) + bw * 0.02, 0),
					Vector3(bw * 0.30, bw * 0.28, bw * 0.26), c.metal.lightened(0.05), 8, 3, 0.36, 1.0)
				kit.torus(Vector3(side * float(m.arm_x) * 0.92, float(m.shoulder_y) - bw * 0.05, 0),
					bw * 0.26, bw * 0.035, c.accent, 8, 4)
		"coat":
			kit.push_trs(Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 0.80))
			kit.frustum(Vector3(0, hip - 0.13, 0), top - hip + 0.13, bw * 0.66, bw * 0.58, c.cloth.darkened(0.18), 10)
			kit.pop()
			_lapels(kit, m, c.cloth.lightened(0.08))
			_belt(kit, m, c, waist + 0.01)


static func _accessory(kit: MeshKit, m: Dictionary, c: Dictionary, d: Dictionary, seed_value: int) -> void:
	var acc := str(d.get("accessory", "none"))
	var bw: float = m.bw
	var bd: float = m.bd
	var top: float = m.torso_top
	var hip: float = m.hip_y
	match acc:
		"backpack":
			var pack: Color = c.leather
			kit.push_trs(Vector3(0, lerpf(hip, top, 0.62), -bd * 0.62), Vector3(-6.0, 0, 0))
			kit.box(Vector3.ZERO, Vector3(bw * 0.72, (top - hip) * 0.68, bw * 0.34), pack, pack.lightened(0.10))
			kit.box(Vector3(0, (top - hip) * 0.38, 0.01), Vector3(bw * 0.74, (top - hip) * 0.14, bw * 0.36), pack.darkened(0.18))
			kit.cylinder(Vector3(-bw * 0.42, -(top - hip) * 0.18, 0), (top - hip) * 0.36, bw * 0.10, c.cloth.darkened(0.12), 6)
			kit.pop()
			for side in [-1.0, 1.0]:
				kit.push_trs(Vector3(side * bw * 0.30, lerpf(hip, top, 0.80), bd * 0.30), Vector3(10.0, 0, 0))
				kit.box(Vector3.ZERO, Vector3(bw * 0.13, (top - hip) * 0.52, bw * 0.10), pack.darkened(0.10))
				kit.pop()
		"cape":
			var cape: Color = c.cloth.darkened(0.12) if str(c.style) != "bandit" else UnitStyle.col("#8c2f26", "#8c2f26")
			kit.push_trs(Vector3(0, top + 0.01, -bd * 0.34), Vector3(6.0, 0, 0))
			kit.push_trs(Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 0.55))
			kit.frustum(Vector3(0, -(top - hip) * 1.12, 0), (top - hip) * 1.14, bw * 0.92, bw * 0.46, cape, 10, false)
			kit.pop()
			kit.pop()
			kit.torus(Vector3(0, top - 0.005, 0), bw * 0.42, bw * 0.05, c.accent, 10, 4)
		"pauldron":
			shell(kit, Vector3(float(m.arm_x) * 0.94, float(m.shoulder_y) + bw * 0.03, 0),
				Vector3(bw * 0.32, bw * 0.30, bw * 0.28), c.metal, 8, 3, 0.34, 1.0)
			kit.torus(Vector3(float(m.arm_x) * 0.94, float(m.shoulder_y) - bw * 0.05, 0), bw * 0.28, bw * 0.035, c.accent, 8, 4)
		"scarf":
			var sc: Color = c.accent if str(c.style) != "bandit" else UnitStyle.col("#b33a2e", "#b33a2e")
			kit.torus(Vector3(0, top + 0.015, 0), bw * 0.34, bw * 0.12, sc, 10, 5)
			kit.push_trs(Vector3(bw * 0.20, top - 0.02, bd * 0.34), Vector3(12.0, 0, -12.0))
			kit.box(Vector3(0, -(top - hip) * 0.30, 0), Vector3(bw * 0.22, (top - hip) * 0.62, bw * 0.07), sc.darkened(0.08))
			kit.pop()
		"satchel":
			kit.push_trs(Vector3(-bw * 0.62, lerpf(hip, top, 0.28), bd * 0.10), Vector3(0, -14.0, 0))
			kit.box(Vector3.ZERO, Vector3(bw * 0.40, bw * 0.46, bw * 0.24), c.leather, c.leather.lightened(0.10))
			kit.box(Vector3(0, bw * 0.18, bw * 0.13), Vector3(bw * 0.40, bw * 0.18, bw * 0.05), c.leather.darkened(0.20))
			kit.pop()
			kit.push_trs(Vector3(0, lerpf(hip, top, 0.72), 0), Vector3(0, 0, 36.0))
			kit.push_trs(Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, float(bd) / bw))
			kit.torus(Vector3.ZERO, bw * 0.56, bw * 0.045, c.leather.darkened(0.12), 10, 4)
			kit.pop()
			kit.pop()
	if UnitStyle.rand01(seed_value, 97) < 0.30 and acc != "backpack" and acc != "cape":
		# small hip pouch for variety
		kit.box(Vector3(bw * 0.52, lerpf(hip, top, 0.24), bd * 0.20), Vector3(bw * 0.20, bw * 0.22, bw * 0.16), c.leather)


# --- arms & hands -----------------------------------------------------------------------------------

static func _left_arm_pose(d: Dictionary) -> Vector3:
	var offhand := str(d.get("offhand", "none"))
	if offhand == "shield" or offhand == "buckler":
		return Vector3(-24.0, 0.0, -14.0)
	if offhand == "lantern" or offhand == "book":
		return Vector3(-38.0, 0.0, -10.0)
	return Vector3(6.0, 0.0, -7.0)


## Arm hanging from the shoulder. `side` -1 = left, +1 = right. `pose` = shoulder rotation (deg).
## Authored in the parent frame when `at_origin` is false (body mesh), around the shoulder joint
## when true (gear mesh).
static func _arm(kit: MeshKit, m: Dictionary, c: Dictionary, d: Dictionary, side: float,
		pose: Vector3, at_origin: bool = false) -> void:
	var bw: float = m.bw
	var upper := float(m.h) * 0.115
	var fore := float(m.h) * 0.105
	var rad := bw * 0.135
	var outfit := str(d.get("outfit", "tunic"))
	var sleeve: Color = c.cloth
	if outfit == "overalls":
		sleeve = c.trim
	elif outfit == "leathers" or outfit == "rags":
		sleeve = c.cloth if outfit == "rags" else c.leather.lightened(0.10)
	var armor := str(d.get("armor", "none"))
	var bracer: Color = c.leather if armor == "leather" or armor == "none" else c.metal
	var long_sleeve := outfit == "robe" or outfit == "coat" or armor == "coat"
	var origin := Vector3.ZERO if at_origin else Vector3(side * float(m.arm_x), float(m.shoulder_y), 0.0)
	kit.push_trs(origin, Vector3(pose.x, pose.y, pose.z + side * 8.0))
	kit.ellipsoid(Vector3.ZERO, Vector3(rad * 1.25, rad * 1.2, rad * 1.2), sleeve, 6, 4)
	kit.cylinder(Vector3(0, -upper, 0), upper, rad, sleeve, 6)
	if long_sleeve:
		kit.frustum(Vector3(0, -upper - fore * 0.62, 0), fore * 0.62, rad * 1.22, rad * 1.02, sleeve.darkened(0.06), 6)
	kit.ellipsoid(Vector3(0, -upper, 0), Vector3(rad * 1.1, rad * 1.05, rad * 1.05), sleeve.darkened(0.07), 6, 3)
	kit.push_trs(Vector3(0, -upper, 0), Vector3(-16.0, 0, 0))
	if long_sleeve:
		kit.cylinder(Vector3(0, -fore, 0), fore, rad * 0.95, sleeve, 6)
	else:
		kit.cylinder(Vector3(0, -fore, 0), fore, rad * 0.92, c.skin, 6)
		kit.frustum(Vector3(0, -fore * 0.30, 0), fore * 0.34, rad * 1.12, rad * 1.0, bracer, 6)
	kit.ellipsoid(Vector3(0, -fore - rad * 0.55, 0), Vector3(rad * 1.12, rad * 1.22, rad * 1.02), c.skin, 6, 4)
	kit.pop()
	kit.pop()


## World-space position of the hand for a given arm pose (used to hang the offhand item).
static func hand_point(m: Dictionary, side: float, pose: Vector3) -> Transform3D:
	var upper := float(m.h) * 0.115
	var fore := float(m.h) * 0.105
	var rad := float(m.bw) * 0.135
	var shoulder := Transform3D(Basis.from_euler(
		Vector3(deg_to_rad(pose.x), deg_to_rad(pose.y), deg_to_rad(pose.z + side * 8.0)), EULER_ORDER_YXZ),
		Vector3(side * float(m.arm_x), float(m.shoulder_y), 0.0))
	var elbow := Transform3D(Basis.from_euler(Vector3(deg_to_rad(-16.0), 0, 0), EULER_ORDER_YXZ),
		Vector3(0, -upper, 0))
	return shoulder * elbow * Transform3D(Basis.IDENTITY, Vector3(0, -fore - rad * 0.55, 0))


static func _offhand(kit: MeshKit, m: Dictionary, c: Dictionary, d: Dictionary) -> void:
	var offhand := str(d.get("offhand", "none"))
	if offhand == "none":
		return
	var xf := hand_point(m, -1.0, _left_arm_pose(d))
	kit.push(xf)
	match offhand:
		"shield", "buckler":
			var r := float(m.h) * (0.175 if offhand == "shield" else 0.125)
			kit.push_trs(Vector3(-r * 0.12, r * 0.42, float(m.bw) * 0.10), Vector3(78.0, 0, 14.0))
			kit.cylinder(Vector3(0, -0.018, 0), 0.036, r, c.wood, 12, c.wood.lightened(0.10))
			kit.cylinder(Vector3(0, 0.018, 0), 0.020, r * 0.86, c.cloth, 12, c.cloth)
			kit.torus(Vector3(0, 0.020, 0), r * 0.94, 0.028, c.metal, 12, 4)
			kit.ellipsoid(Vector3(0, 0.032, 0), Vector3(r * 0.22, 0.05, r * 0.22), c.metal.lightened(0.10), 7, 3)
			# faction emblem: four spokes + centre ring
			for i in 4:
				var a := TAU * float(i) / 4.0 + PI * 0.25
				kit.push_trs(Vector3(cos(a) * r * 0.48, 0.040, sin(a) * r * 0.48), Vector3(0, -rad_to_deg(a), 0))
				kit.box(Vector3.ZERO, Vector3(r * 0.46, 0.014, r * 0.13), c.accent)
				kit.pop()
			kit.pop()
		"lantern":
			kit.push_trs(Vector3(0, -0.02, 0.02))
			kit.tube(Vector3(0, 0, 0), Vector3(0, -float(m.h) * 0.06, 0), 0.010, c.metal.darkened(0.2), 4)
			kit.box(Vector3(0, -float(m.h) * 0.115, 0), Vector3(0.10, 0.11, 0.10),
				MeshKit.glow(UnitStyle.col("#ffcf72", "#ffcf72"), 0.85))
			kit.box(Vector3(0, -float(m.h) * 0.175, 0), Vector3(0.115, 0.03, 0.115), c.metal.darkened(0.12))
			kit.box(Vector3(0, -float(m.h) * 0.055, 0), Vector3(0.10, 0.03, 0.10), c.metal.darkened(0.12))
			kit.pop()
		"book":
			kit.push_trs(Vector3(0.0, -0.01, 0.06), Vector3(-62.0, 0, 8.0))
			kit.box(Vector3.ZERO, Vector3(0.20, 0.045, 0.16), c.cloth.darkened(0.22))
			kit.box(Vector3(0, 0.028, 0.0), Vector3(0.185, 0.02, 0.15), UnitStyle.col("#efe3c2", "#efe3c2"))
			kit.box(Vector3(0, 0.040, 0.0), Vector3(0.05, 0.008, 0.05), c.accent)
			kit.pop()
	kit.pop()


# --- legs -------------------------------------------------------------------------------------------

## One leg, authored around its hip joint (side -1 = left, +1 = right).
static func leg(d: Dictionary, side: int) -> ArrayMesh:
	var kit := MeshKit.new()
	if str(d.get("race", "human")) in ["centaur", "lamia"]:
		return kit.build()
	var m := metrics(d)
	var c := colors(d)
	var hip: float = m.hip_y
	var bw: float = m.bw
	var outfit := str(d.get("outfit", "tunic"))
	var trouser: Color = c.cloth.darkened(0.28)
	match outfit:
		"overalls": trouser = c.cloth.darkened(0.10)
		"leathers": trouser = c.leather.darkened(0.10)
		"rags": trouser = c.cloth.darkened(0.35)
		"robe", "dress": trouser = c.cloth.darkened(0.22)
	var boot: Color = c.leather.darkened(0.12)
	var boot_h: float = m.boot_h
	var thigh := bw * 0.19
	var visible_top := hip
	if bool(m.skirt):
		visible_top = minf(hip, float(m.hem_y) + 0.02)
	var leg_bottom := boot_h * 0.55
	kit.push_trs(Vector3(0, 0, 0))
	if visible_top > leg_bottom:
		kit.frustum(Vector3(0, leg_bottom - hip, 0), visible_top - leg_bottom, thigh * 0.82, thigh, trouser, 7)
	# boot
	kit.frustum(Vector3(0, boot_h * 0.10 - hip, 0), boot_h * 0.62, thigh * 0.88, thigh * 0.92, boot, 7)
	kit.box(Vector3(0, boot_h * 0.30 - hip, thigh * 0.28), Vector3(thigh * 1.7, boot_h * 0.60, thigh * 1.5), boot)
	kit.box(Vector3(0, boot_h * 0.09 - hip, thigh * 0.44), Vector3(thigh * 1.78, boot_h * 0.22, thigh * 1.95), boot.darkened(0.22))
	if str(d.get("armor", "none")) == "plate":
		kit.push_trs(Vector3(0, -hip, 0))
		kit.frustum(Vector3(0, boot_h * 0.55, 0), (visible_top - boot_h) * 0.55, thigh * 0.98, thigh * 0.92, c.metal, 7)
		kit.pop()
	if side < 0:
		pass
	kit.pop()
	return kit.build()


# --- gear (right arm + held item + carried load) -------------------------------------------------------

static func gear(d: Dictionary, weapon: String, carry: String) -> ArrayMesh:
	var kit := MeshKit.new()
	var m := metrics(d)
	var c := colors(d)
	var pose := GearMesh.arm_pose(weapon, carry)
	_arm(kit, m, c, d, 1.0, pose, true)
	var upper := float(m.h) * 0.115
	var fore := float(m.h) * 0.105
	var rad := float(m.bw) * 0.135
	var hand := Transform3D(Basis.from_euler(Vector3(deg_to_rad(pose.x), deg_to_rad(pose.y),
		deg_to_rad(pose.z + 8.0)), EULER_ORDER_YXZ), Vector3.ZERO) \
		* Transform3D(Basis.from_euler(Vector3(deg_to_rad(-16.0), 0, 0), EULER_ORDER_YXZ), Vector3(0, -upper, 0)) \
		* Transform3D(Basis.IDENTITY, Vector3(0, -fore - rad * 0.55, 0))
	kit.push(hand)
	GearMesh.held(kit, d, c, weapon, float(m.h))
	kit.pop()
	if not carry.is_empty():
		kit.push_trs(Vector3(-float(m.arm_x) * 0.95, -float(m.h) * 0.14, float(m.bd) * 0.85))
		GearMesh.carry_load(kit, d, c, carry, float(m.h))
		kit.pop()
	return kit.build()
