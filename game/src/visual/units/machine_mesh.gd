class_name MachineMesh
extends RefCounted
## Builders for ground robots, drones and airships (model front = +Z, origin at the feet for
## ground machines and at the craft centre for flyers). Style follows the reference: brass and
## steel frontier machines with blue faction plates and cyan glowing eyes; bronze/slate ancient
## machines with orange-red glow; striped cigar balloons with a wooden gondola.

const WALKER_HIP := Vector3(0.36, 1.02, -0.02)
const AIRSHIP_PROP_HUB := Vector3(0.0, 1.9, -5.45)


static func colors(d: Dictionary) -> Dictionary:
	var style := str(d.get("faction_style", "frontier"))
	var faction := UnitStyle.col(d.get("faction_color"), "#3a5da8")
	var eye := UnitStyle.col(d.get("eye_color"), "#5bc8ff" if style == "frontier" else "#ff6a2a")
	var c := {"style": style, "faction": faction, "eye": MeshKit.glow(eye, 1.0), "eye_soft": MeshKit.glow(eye, 0.55)}
	match style:
		"ancient":
			c.merge({"body": Color("#a07a4a"), "body_dark": Color("#6e5232"), "plate": Color("#5b6470"), "plate_dark": Color("#3b3f48"), "trim": Color("#c9a063"), "rubber": Color("#2a2c30")})
		"bandit":
			c.merge({"body": Color("#8c4a2a"), "body_dark": Color("#5a2f1c"), "plate": Color("#6b6158"), "plate_dark": Color("#3e3630"), "trim": Color("#b33a2e"), "rubber": Color("#2a2622")})
		"merchant":
			c.merge({"body": Color("#b89a5a"), "body_dark": Color("#7a6232"), "plate": Color("#4f8a4b"), "plate_dark": Color("#355e33"), "trim": Color("#efe3c2"), "rubber": Color("#2d2a26")})
		_:
			c.merge({"body": Color("#c9a052"), "body_dark": Color("#8a6a34"), "plate": faction, "plate_dark": faction.darkened(0.35), "trim": Color("#e9dcc0"), "rubber": Color("#2b2d33")})
	var wear := clampf(float(d.get("wear", 0.2)), 0.0, 1.0)
	c["body"] = (c["body"] as Color).darkened(wear * 0.18)
	c["steel"] = Color("#b7c0cc").darkened(wear * 0.15)
	c["dark"] = Color("#3c4048")
	return c


# --- ground robots ---------------------------------------------------------------------------

static func robot(d: Dictionary) -> ArrayMesh:
	var k := MeshKit.new()
	var c := colors(d)
	var s := float(d.get("scale", 1.0))
	k.push_trs(Vector3.ZERO, Vector3.ZERO, Vector3.ONE * s)
	match str(d.get("archetype", "work_bot")):
		"walker":
			_walker_body(k, c, d)
		"sentry":
			_sentry(k, c, d)
		"turret":
			_turret(k, c, d)
		"hauler":
			_work_bot(k, c, d, 1.25)
		_:
			_work_bot(k, c, d, 1.0)
	k.pop()
	return k.build()


static func _rivets(k: MeshKit, a: Vector3, b: Vector3, n: int, col: Color) -> void:
	for i in n:
		var p := a.lerp(b, (float(i) + 0.5) / n)
		k.box(p, Vector3(0.035, 0.035, 0.03), col)


static func _work_bot(k: MeshKit, c: Dictionary, d: Dictionary, sz: float) -> void:
	k.push_trs(Vector3.ZERO, Vector3.ZERO, Vector3.ONE * sz)
	var legs := str(d.get("legs", "treads"))
	if legs == "wheels":
		for x: float in [-0.3, 0.3]:
			for z: float in [-0.2, 0.2]:
				k.push_trs(Vector3(x, 0.14, z), Vector3(0, 0, 90))
				k.cylinder(Vector3(0, -0.06, 0), 0.12, 0.14, c["rubber"], 10)
				k.cylinder(Vector3(0, -0.065, 0), 0.13, 0.07, c["steel"], 8)
				k.pop()
	else:
		for x: float in [-0.29, 0.29]:
			k.box(Vector3(x, 0.14, 0.0), Vector3(0.17, 0.26, 0.66), c["rubber"])
			k.box(Vector3(x, 0.14, 0.0), Vector3(0.19, 0.12, 0.5), c["dark"])
			for z: float in [-0.22, 0.0, 0.22]:
				k.push_trs(Vector3(x + signf(x) * 0.09, 0.14, z), Vector3(0, 0, 90))
				k.cylinder(Vector3(0, -0.02, 0), 0.04, 0.075, c["steel"], 8)
				k.pop()
	# chassis: rounded brass barrel with a blue front plate
	k.box(Vector3(0, 0.33, 0), Vector3(0.5, 0.1, 0.5), c["body_dark"])
	k.push_trs(Vector3(0, 0.36, 0))
	k.frustum(Vector3.ZERO, 0.42, 0.3, 0.27, c["body"], 10, true, c["body_dark"])
	k.pop()
	k.box(Vector3(0, 0.55, 0.27), Vector3(0.32, 0.22, 0.05), c["plate"])
	k.box(Vector3(0, 0.55, 0.3), Vector3(0.1, 0.1, 0.03), c["trim"])
	_rivets(k, Vector3(-0.28, 0.4, 0.2), Vector3(-0.28, 0.72, 0.2), 3, c["body_dark"])
	_rivets(k, Vector3(0.28, 0.4, 0.2), Vector3(0.28, 0.72, 0.2), 3, c["body_dark"])
	# head: dome with a big glowing eye
	k.box(Vector3(0, 0.8, 0), Vector3(0.14, 0.06, 0.14), c["dark"])
	k.ellipsoid(Vector3(0, 0.92, 0.02), Vector3(0.2, 0.15, 0.18), c["body"], 10, 5)
	k.box(Vector3(0, 0.93, 0.13), Vector3(0.26, 0.09, 0.08), c["dark"])
	k.sphere(Vector3(0, 0.93, 0.18), 0.075, c["eye"], 8, 5)
	k.sphere(Vector3(0.1, 0.95, 0.15), 0.03, c["eye_soft"], 6, 3)
	# smokestack and antenna
	k.cylinder(Vector3(-0.14, 0.72, -0.2), 0.3, 0.05, c["dark"], 8)
	k.cylinder(Vector3(-0.14, 1.0, -0.2), 0.04, 0.07, c["body_dark"], 8)
	k.tube(Vector3(0.12, 1.02, -0.02), Vector3(0.16, 1.24, -0.06), 0.012, c["steel"], 4)
	k.sphere(Vector3(0.16, 1.26, -0.06), 0.03, c["eye_soft"], 6, 3)
	match str(d.get("utility_module", "tool_arm")):
		"crane_arm":
			k.tube(Vector3(0.3, 0.6, 0.0), Vector3(0.5, 0.95, 0.25), 0.04, c["plate"], 6)
			k.tube(Vector3(0.5, 0.95, 0.25), Vector3(0.52, 0.7, 0.42), 0.012, c["dark"], 4)
			k.box(Vector3(0.52, 0.66, 0.42), Vector3(0.08, 0.06, 0.08), c["steel"])
		"cargo_rack":
			k.box(Vector3(0, 0.62, -0.33), Vector3(0.46, 0.04, 0.2), c["body_dark"])
			k.box(Vector3(-0.1, 0.72, -0.35), Vector3(0.18, 0.16, 0.16), Color("#9a6a3a"))
			k.box(Vector3(0.12, 0.7, -0.34), Vector3(0.14, 0.12, 0.14), Color("#b07a44"))
		_:
			k.tube(Vector3(0.3, 0.6, 0.05), Vector3(0.42, 0.45, 0.22), 0.035, c["steel"], 6)
			k.box(Vector3(0.44, 0.42, 0.27), Vector3(0.08, 0.1, 0.1), c["plate"])
	k.tube(Vector3(-0.3, 0.6, 0.05), Vector3(-0.38, 0.42, 0.18), 0.035, c["steel"], 6)
	k.box(Vector3(-0.39, 0.39, 0.21), Vector3(0.07, 0.09, 0.08), c["dark"])
	k.pop()


static func _walker_body(k: MeshKit, c: Dictionary, d: Dictionary) -> void:
	# pelvis
	k.box(Vector3(0, 1.05, -0.02), Vector3(0.62, 0.22, 0.44), c["dark"])
	k.box(Vector3(0, 1.1, -0.02), Vector3(0.5, 0.16, 0.5), c["body_dark"])
	# hull: rounded brass cockpit
	k.ellipsoid(Vector3(0, 1.58, 0.0), Vector3(0.62, 0.48, 0.58), c["body"], 14, 7)
	k.ellipsoid(Vector3(0, 1.3, -0.02), Vector3(0.52, 0.2, 0.5), c["body_dark"], 12, 4)
	# faction armour plates and chest emblem
	k.push_trs(Vector3(0, 1.52, 0.47), Vector3(-12, 0, 0))
	k.box(Vector3.ZERO, Vector3(0.62, 0.34, 0.1), c["plate"])
	k.box(Vector3(0, 0.0, 0.055), Vector3(0.16, 0.16, 0.03), c["trim"])
	k.pop()
	# visor with glowing eye
	k.push_trs(Vector3(0, 1.84, 0.34), Vector3(-18, 0, 0))
	k.box(Vector3.ZERO, Vector3(0.52, 0.16, 0.14), c["dark"])
	k.box(Vector3(0, 0.0, 0.07), Vector3(0.44, 0.07, 0.02), c["eye_soft"])
	k.sphere(Vector3(0.0, 0.0, 0.09), 0.08, c["eye"], 8, 5)
	k.pop()
	# top hatch and exhaust pipes
	k.cylinder(Vector3(0, 2.02, -0.05), 0.08, 0.2, c["body_dark"], 10, c["steel"])
	for x: float in [-0.22, 0.22]:
		k.cylinder(Vector3(x, 1.7, -0.5), 0.42, 0.06, c["dark"], 8)
		k.cylinder(Vector3(x, 2.1, -0.5), 0.05, 0.085, c["body_dark"], 8)
	_rivets(k, Vector3(-0.5, 1.45, 0.3), Vector3(-0.5, 1.8, 0.1), 4, c["body_dark"])
	_rivets(k, Vector3(0.5, 1.45, 0.3), Vector3(0.5, 1.8, 0.1), 4, c["body_dark"])
	# shoulders
	for side: float in [-1.0, 1.0]:
		k.sphere(Vector3(side * 0.66, 1.66, 0.0), 0.2, c["plate"], 8, 5)
		k.box(Vector3(side * 0.7, 1.8, 0.0), Vector3(0.3, 0.1, 0.36), c["plate_dark"])
	var weapon := str(d.get("weapon", "cannon"))
	# right arm: cannon / gatling
	k.tube(Vector3(0.7, 1.6, 0.0), Vector3(0.78, 1.28, 0.1), 0.08, c["steel"], 8)
	k.push_trs(Vector3(0.8, 1.26, 0.25), Vector3(90, 0, 0))
	if weapon == "gatling":
		for a in 6:
			var ang := TAU * a / 6.0
			k.cylinder(Vector3(cos(ang) * 0.06, -0.3, sin(ang) * 0.06), 0.7, 0.025, c["dark"], 5)
		k.cylinder(Vector3(0, -0.3, 0), 0.2, 0.12, c["body_dark"], 8)
	else:
		k.cylinder(Vector3(0, -0.25, 0), 0.75, 0.085, c["dark"], 10)
		k.cylinder(Vector3(0, 0.38, 0), 0.1, 0.11, c["body"], 10)
		k.cylinder(Vector3(0, -0.3, 0), 0.22, 0.13, c["body_dark"], 10)
	k.pop()
	# left arm: claw
	k.tube(Vector3(-0.7, 1.6, 0.0), Vector3(-0.8, 1.2, 0.12), 0.08, c["steel"], 8)
	k.box(Vector3(-0.82, 1.12, 0.18), Vector3(0.18, 0.18, 0.22), c["body_dark"])
	for off: float in [-0.05, 0.05]:
		k.tube(Vector3(-0.82 + off, 1.05, 0.25), Vector3(-0.82 + off * 1.6, 0.9, 0.36), 0.025, c["steel"], 4)
	# small blue banner pennant on the back
	k.tube(Vector3(-0.3, 1.8, -0.45), Vector3(-0.3, 2.55, -0.5), 0.015, c["dark"], 4)
	k.push_trs(Vector3(-0.3, 2.35, -0.5), Vector3(0, 90, 0))
	k.plate(PackedVector2Array([Vector2(0, 0.18), Vector2(0.34, 0.1), Vector2(0.26, 0.0), Vector2(0.34, -0.1), Vector2(0, -0.18)]), 0.02, c["plate"], c["plate"])
	k.pop()


## One walker leg authored with the hip joint at the origin (the rig places it at WALKER_HIP).
static func walker_leg(d: Dictionary, side: int) -> ArrayMesh:
	var k := MeshKit.new()
	var c := colors(d)
	var s := float(d.get("scale", 1.0))
	k.push_trs(Vector3.ZERO, Vector3.ZERO, Vector3.ONE * s)
	var sx := float(side) * 0.04
	k.sphere(Vector3(sx, 0, 0), 0.13, c["dark"], 8, 5)
	k.tube(Vector3(sx, 0, 0), Vector3(sx, -0.48, 0.2), 0.1, c["body"], 8)
	k.box(Vector3(sx + float(side) * 0.03, -0.22, 0.12), Vector3(0.1, 0.3, 0.22), c["plate"])
	k.sphere(Vector3(sx, -0.5, 0.2), 0.1, c["dark"], 8, 5)
	k.tube(Vector3(sx, -0.5, 0.2), Vector3(sx, -0.9, -0.06), 0.075, c["steel"], 8)
	k.tube(Vector3(sx + 0.05, -0.48, 0.16), Vector3(sx + 0.05, -0.84, -0.04), 0.02, c["dark"], 4)
	k.box(Vector3(sx, -0.96, 0.04), Vector3(0.26, 0.1, 0.44), c["body_dark"])
	k.box(Vector3(sx, -0.93, 0.2), Vector3(0.22, 0.08, 0.14), c["body"])
	k.pop()
	return k.build()


static func _sentry(k: MeshKit, c: Dictionary, d: Dictionary) -> void:
	for ix in [-1, 1]:
		for iz in [-1, 1]:
			var hip := Vector3(ix * 0.26, 0.72, iz * 0.2)
			var knee := Vector3(ix * 0.5, 0.82, iz * 0.4)
			var foot := Vector3(ix * 0.58, 0.02, iz * 0.5)
			k.tube(hip, knee, 0.06, c["plate"], 6)
			k.tube(knee, foot, 0.045, c["body_dark"], 6)
			k.cone(foot - Vector3(0, 0.02, 0), 0.08, 0.06, c["dark"], 6)
	# angular body
	k.push_trs(Vector3(0, 0.95, 0), Vector3(0, 45, 0))
	k.pyramid(Vector3(0, -0.28, 0), Vector2(0.62, 0.62), -0.001, c["plate_dark"])
	k.box(Vector3(0, -0.1, 0), Vector3(0.6, 0.3, 0.6), c["plate"])
	k.pyramid(Vector3(0, 0.05, 0), Vector2(0.6, 0.6), 0.38, c["body"])
	k.pop()
	k.box(Vector3(0, 0.98, 0.3), Vector3(0.36, 0.1, 0.1), c["dark"])
	k.box(Vector3(0, 0.98, 0.35), Vector3(0.28, 0.035, 0.02), c["eye"])
	# glow seams
	for a: float in [0.0, 90.0, 180.0, 270.0]:
		k.push_trs(Vector3(0, 0.95, 0), Vector3(0, a + 45.0, 0))
		k.box(Vector3(0, -0.1, 0.43), Vector3(0.05, 0.22, 0.01), c["eye_soft"])
		k.pop()
	# blaster under the chin
	k.push_trs(Vector3(0, 0.78, 0.2), Vector3(90, 0, 0))
	k.cylinder(Vector3(0, -0.05, 0), 0.4, 0.05, c["dark"], 6)
	k.pop()
	k.sphere(Vector3(0, 1.36, 0), 0.07, c["eye_soft"], 6, 4)


static func _turret(k: MeshKit, c: Dictionary, d: Dictionary) -> void:
	k.frustum(Vector3.ZERO, 0.5, 0.62, 0.46, c["plate_dark"], 8, true, c["plate"])
	k.frustum(Vector3(0, 0.5, 0), 0.35, 0.34, 0.3, c["plate"], 8, true, c["body"])
	for a in 4:
		var ang := TAU * a / 4.0 + PI * 0.25
		k.box(Vector3(cos(ang) * 0.48, 0.25, sin(ang) * 0.48), Vector3(0.12, 0.4, 0.12), c["body_dark"])
		k.box(Vector3(cos(ang) * 0.55, 0.25, sin(ang) * 0.55), Vector3(0.03, 0.26, 0.03), c["eye_soft"])
	# head
	k.ellipsoid(Vector3(0, 1.08, 0), Vector3(0.36, 0.26, 0.36), c["body"], 10, 5)
	k.box(Vector3(0, 1.08, 0.25), Vector3(0.3, 0.14, 0.14), c["dark"])
	k.sphere(Vector3(0, 1.1, 0.33), 0.07, c["eye"], 8, 4)
	for x: float in [-0.12, 0.12]:
		k.push_trs(Vector3(x, 1.0, 0.3), Vector3(90, 0, 0))
		k.cylinder(Vector3(0, -0.1, 0), 0.62, 0.05, c["dark"], 6)
		k.pop()
	k.cone(Vector3(0, 1.3, 0), 0.24, 0.12, c["plate"], 6)


# --- drones --------------------------------------------------------------------------------

const ROTOR_ARMS := [Vector3(0.3, 0.02, 0.3), Vector3(-0.3, 0.02, 0.3), Vector3(0.3, 0.02, -0.3), Vector3(-0.3, 0.02, -0.3)]


static func drone(d: Dictionary) -> ArrayMesh:
	var k := MeshKit.new()
	var c := colors(d)
	var arch := str(d.get("archetype", "scout_drone"))
	var body: Color = c["body"]
	var lens: Color = c["eye"]
	if arch == "repair_drone":
		body = Color("#e9e2cc")
		lens = MeshKit.glow(Color("#7dff9a"), 1.0)
	k.ellipsoid(Vector3(0, 0, 0), Vector3(0.24, 0.15, 0.24), body, 12, 6)
	k.ellipsoid(Vector3(0, -0.07, 0), Vector3(0.2, 0.07, 0.2), c["plate"], 10, 3)
	k.box(Vector3(0, 0.12, -0.04), Vector3(0.14, 0.06, 0.18), c["plate_dark"])
	# big lens facing forward
	k.cylinder(Vector3(0, -0.01, 0.2), 0.02, 0.1, c["dark"], 10)
	k.push_trs(Vector3(0, 0.0, 0.2), Vector3(90, 0, 0))
	k.cylinder(Vector3(0, -0.05, 0), 0.07, 0.1, c["dark"], 10)
	k.pop()
	k.sphere(Vector3(0, 0.0, 0.25), 0.07, lens, 8, 5)
	for a: Vector3 in ROTOR_ARMS:
		k.tube(Vector3(a.x * 0.35, 0.03, a.z * 0.35), a + Vector3(0, 0.02, 0), 0.025, c["dark"], 5)
		k.cylinder(a, 0.07, 0.045, c["plate"], 8)
	if arch == "repair_drone":
		k.box(Vector3(0, 0.1, 0.0), Vector3(0.12, 0.03, 0.04), Color("#c0392b"))
		k.box(Vector3(0, 0.1, 0.0), Vector3(0.04, 0.03, 0.12), Color("#c0392b"))
	elif str(d.get("weapon", "none")) == "blaster" or arch == "war_drone":
		k.push_trs(Vector3(0, -0.12, 0.12), Vector3(90, 0, 0))
		k.cylinder(Vector3(0, -0.05, 0), 0.2, 0.03, c["dark"], 6)
		k.pop()
	# small tail fin
	k.push_trs(Vector3(0, 0.1, -0.22), Vector3(0, 90, 0))
	k.plate(PackedVector2Array([Vector2(0, 0), Vector2(0.14, 0.0), Vector2(0.02, 0.12)]), 0.02, c["plate"])
	k.pop()
	return k.build()


## Rotor discs (spun around the drone's vertical axis; the discs read as blurred rotors).
static func drone_rotors(d: Dictionary) -> ArrayMesh:
	var k := MeshKit.new()
	var c := colors(d)
	for a: Vector3 in ROTOR_ARMS:
		k.cylinder(a + Vector3(0, 0.07, 0), 0.012, 0.17, Color(0.85, 0.88, 0.92), 14)
		for i in 2:
			k.push_trs(a + Vector3(0, 0.085, 0), Vector3(0, i * 90.0 + 20.0, 0))
			k.box(Vector3.ZERO, Vector3(0.34, 0.01, 0.035), c["dark"])
			k.pop()
	return k.build()


# --- airships ------------------------------------------------------------------------------

## Lathe-built balloon along Z with longitudinal gore stripes and ring bands.
static func _balloon(k: MeshKit, center: Vector3, radius: float, half_len: float, col_a: Color, col_b: Color, band: Color, segs: int, rings: int, bands: Array) -> void:
	for r in rings:
		var t0 := float(r) / rings
		var t1 := float(r + 1) / rings
		var z0 := lerpf(-half_len, half_len, t0)
		var z1 := lerpf(-half_len, half_len, t1)
		var r0 := radius * sqrt(maxf(0.0, 1.0 - pow(z0 / half_len, 2.0)))
		var r1 := radius * sqrt(maxf(0.0, 1.0 - pow(z1 / half_len, 2.0)))
		# slightly pointed tail, fuller nose
		r0 *= 1.0 - 0.18 * maxf(0.0, -z0 / half_len)
		r1 *= 1.0 - 0.18 * maxf(0.0, -z1 / half_len)
		var ring_band := false
		for bz: float in bands:
			if absf((z0 + z1) * 0.5 - bz * half_len) < half_len / rings * 0.6:
				ring_band = true
		for s in segs:
			var a0 := TAU * s / segs
			var a1 := TAU * (s + 1) / segs
			var col: Color = band if ring_band else (col_a if s % 2 == 0 else col_b)
			var p00 := center + Vector3(cos(a0) * r0, sin(a0) * r0 * 0.92, z0)
			var p01 := center + Vector3(cos(a1) * r0, sin(a1) * r0 * 0.92, z0)
			var p10 := center + Vector3(cos(a0) * r1, sin(a0) * r1 * 0.92, z1)
			var p11 := center + Vector3(cos(a1) * r1, sin(a1) * r1 * 0.92, z1)
			var mid := center + Vector3(0, 0, (z0 + z1) * 0.5)
			k.quad_out(p00, p01, p11, p10, mid, col)


static func airship(d: Dictionary) -> ArrayMesh:
	var k := MeshKit.new()
	var c := colors(d)
	var s := float(d.get("scale", 1.0))
	var style := str(c["style"])
	var bal_a := UnitStyle.col(d.get("balloon_color"), "#e9dcc0")
	var bal_b := UnitStyle.col(d.get("balloon_color2"), "#3a5da8")
	var band := Color("#d9b04c")
	var wood := Color("#8a5a34")
	var wood_dark := Color("#5e3c22")
	if style == "frontier":
		bal_a = Color("#ece2c6")
		bal_b = c["faction"]
	elif style == "merchant":
		bal_a = Color("#efe3c2")
		bal_b = Color("#4f8a4b")
	elif style == "bandit":
		bal_a = Color("#6e2a24")
		bal_b = Color("#3e2a22")
		band = Color("#8c4a2a")
	k.push_trs(Vector3.ZERO, Vector3.ZERO, Vector3.ONE * s)
	var pattern := str(d.get("balloon_pattern", "stripes"))
	var shape := str(d.get("balloon", "cigar"))
	var bands: Array = [-0.62, 0.0, 0.62] if pattern in ["stripes", "rings"] else [0.0]
	if shape == "twin":
		for x: float in [-1.05, 1.05]:
			_balloon(k, Vector3(x, 1.9, 0), 1.15, 4.6, bal_a, bal_b if pattern != "plain" else bal_a, band, 12, 12, bands)
	else:
		var rad := 1.75 if shape != "round" else 2.1
		var hl := 5.2 if shape != "round" else 3.6
		_balloon(k, Vector3(0, 1.9, 0), rad, hl, bal_a, bal_b if pattern != "plain" else bal_a, band, 16, 14, bands)
		# nose cap
		k.push_trs(Vector3(0, 1.9, hl - 0.05), Vector3(90, 0, 0))
		k.cone(Vector3.ZERO, 0.5, 0.35, band, 10)
		k.pop()
	# tail fins
	for a: float in [0.0, 90.0, 180.0, 270.0]:
		k.push_trs(Vector3(0, 1.9, -4.3), Vector3(0, 0, a))
		k.push_trs(Vector3(0, 0, 0), Vector3(0, 90, 0))
		k.plate(PackedVector2Array([Vector2(-0.9, 1.2), Vector2(0.6, 1.25), Vector2(1.0, 2.35), Vector2(-0.6, 2.2)]), 0.06, bal_b.darkened(0.1), bal_b.darkened(0.1))
		k.pop()
		k.pop()
	# rigging lines
	for x: float in [-0.7, 0.7]:
		for z: float in [-1.5, 1.5]:
			k.tube(Vector3(x * 1.2, -1.35, z), Vector3(x * 2.0, 0.55, z * 1.5), 0.02, Color("#4a3a2a"), 4)
	# gondola hangs well below the envelope so it reads from the game camera
	k.push_trs(Vector3(0, -1.35, 0.35))
	k.box(Vector3(0, -0.55, 0), Vector3(1.9, 0.8, 3.8), wood)
	k.box(Vector3(0, -0.98, 0), Vector3(1.7, 0.12, 3.4), wood_dark)
	k.box(Vector3(0, -0.1, 0.1), Vector3(1.6, 0.1, 3.0), Color("#b07a44"))
	k.gable(Vector3(0, -0.07, -0.45), Vector3(1.1, 0.5, 1.7), c["plate"], wood, 0.08)
	for z: float in [-1.3, -0.65, 0.0, 0.65, 1.3]:
		for x: float in [-0.96, 0.96]:
			k.box(Vector3(x, -0.5, z), Vector3(0.03, 0.24, 0.32), MeshKit.glow(Color("#ffcf7a"), 0.55))
	for z in 8:
		for x: float in [-0.85, 0.85]:
			k.box(Vector3(x, 0.03, -1.7 + z * 0.48), Vector3(0.05, 0.22, 0.05), wood_dark)
	k.push_trs(Vector3(0, -0.55, 1.9), Vector3(0, 45, 0))
	k.box(Vector3.ZERO, Vector3(1.05, 0.7, 1.05), wood)
	k.pop()
	k.box(Vector3(0, -0.4, -1.95), Vector3(1.4, 0.55, 0.3), wood_dark)
	k.pop()
	# side engine pods
	for x: float in [-1.55, 1.55]:
		k.tube(Vector3(signf(x) * 0.8, -1.1, -0.3), Vector3(x, -0.9, -0.3), 0.05, c["dark"], 5)
		k.push_trs(Vector3(x, -0.9, -0.3), Vector3(90, 0, 0))
		k.cylinder(Vector3(0, -0.5, 0), 1.0, 0.2, c["body"], 10)
		k.cone(Vector3(0, 0.5, 0), 0.25, 0.2, c["body_dark"], 10)
		k.pop()
		k.push_trs(Vector3(x, -0.9, -0.82), Vector3(90, 0, 0))
		k.cylinder(Vector3.ZERO, 0.02, 0.3, Color(0.85, 0.87, 0.9), 12)
		k.pop()
	# rear engine housing (the spinning propeller is a separate node)
	k.push_trs(Vector3(0, 1.9, -5.0), Vector3(90, 0, 0))
	k.cylinder(Vector3(0, -0.45, 0), 0.5, 0.22, c["body"], 10)
	k.pop()
	# banner with crest
	k.tube(Vector3(0.75, -1.45, 1.9), Vector3(0.75, -0.3, 2.0), 0.025, wood_dark, 4)
	k.push_trs(Vector3(0.75, -0.5, 2.0), Vector3(0, 90, 0))
	k.plate(PackedVector2Array([Vector2(0, 0.2), Vector2(0.7, 0.2), Vector2(0.55, 0.0), Vector2(0.7, -0.2), Vector2(0, -0.2)]), 0.03, c["plate"], c["plate"])
	k.box(Vector3(0.22, 0, 0.02), Vector3(0.14, 0.14, 0.02), band)
	k.pop()
	match str(d.get("cargo_module", "none")):
		"crates", "hanging_container":
			for i in 3:
				var z := -0.9 + i * 0.9
				k.tube(Vector3(0.0, -2.45, z + 0.35), Vector3(0.0, -2.8, z + 0.35), 0.015, Color("#4a3a2a"), 4)
				k.box(Vector3(0.0, -3.0, z + 0.35), Vector3(0.5, 0.4, 0.5), Color("#9a6a3a") if i % 2 == 0 else Color("#b07a44"))
	k.pop()
	return k.build()


## Rear propeller authored around its hub (the rig places it at AIRSHIP_PROP_HUB and spins it on Z).
static func airship_props(d: Dictionary) -> ArrayMesh:
	var k := MeshKit.new()
	var c := colors(d)
	var s := float(d.get("scale", 1.0))
	k.push_trs(Vector3.ZERO, Vector3.ZERO, Vector3.ONE * s)
	k.sphere(Vector3.ZERO, 0.16, c["body_dark"], 8, 5)
	for i in 4:
		k.push_trs(Vector3.ZERO, Vector3(0, 0, i * 90.0))
		k.push_trs(Vector3(0, 0.55, 0), Vector3(0, 25, 0))
		k.box(Vector3.ZERO, Vector3(0.2, 0.95, 0.04), Color("#8a5a34"))
		k.box(Vector3(0, 0.42, 0), Vector3(0.21, 0.12, 0.045), Color("#d9b04c"))
		k.pop()
		k.pop()
	k.pop()
	return k.build()
