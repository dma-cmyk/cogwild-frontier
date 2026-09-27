class_name BldFrontier
extends RefCounted
## Geometry for the player-faction buildings (and the style-agnostic wall/palisade/campfire).
## Each builder writes one merged mesh into `k`; origin is the footprint centre on the ground and
## the door/front faces +Z. Dimensions stay inside the contract footprint + 0.3 m of roof overhang.

## Returns true when `id` was handled.
static func build(k: MeshKit, id: String, p: BuildPalette, seed: int, lv: int) -> bool:
	match id:
		"house": house(k, p, seed)
		"hearth": hearth(k, p, seed, lv)
		"storehouse": storehouse(k, p, seed)
		"workshop": workshop(k, p, seed)
		"smelter": smelter(k, p, seed)
		"windmill": windmill(k, p, seed)
		"sky_dock": sky_dock(k, p, seed)
		"watchtower": watchtower(k, p, seed)
		"bridge_segment": bridge_segment(k, p)
		"cliff_stairs": cliff_stairs(k, p)
		"wall": wall(k, p, seed)
		"palisade": palisade(k, p, seed)
		"outpost": outpost(k, p, seed)
		"campfire": campfire(k, p, seed)
		_: return false
	return true


# --- cottage ------------------------------------------------------------------------------------

## 3x3 cottage. variant_seed picks roof tint, chimney side, upper-floor jetty and the dressing.
static func house(k: MeshKit, p: BuildPalette, seed: int) -> void:
	var v: int = absi(seed) % 3
	var roof_col: Color = [p.roof, p.roof.lightened(0.10), p.roof.darkened(0.12)][v]
	var chim_side: float = -1.0 if v == 1 else 1.0
	var plinth_h := 0.34
	BuildParts.stone_base(k, 2.78, 2.78, plinth_h, p)
	var wall_h := 1.5 if v == 1 else 1.92
	BuildParts.framed_walls(k, Vector3(2.5, wall_h, 2.5), plinth_h, p)
	var eave := plinth_h + wall_h
	if v == 1:
		# jettied upper storey: the first floor overhangs the ground floor on all sides
		k.box(Vector3(0, eave + 0.12, 0), Vector3(2.76, 0.2, 2.76), p.timber)
		BuildParts.framed_walls(k, Vector3(2.7, 1.1, 2.7), eave + 0.22, p, false)
		eave += 1.32
		BuildParts.window(k, Vector3(-0.62, eave - 0.55, 1.36), 0.5, 0.52, 0.0, p)
		BuildParts.window(k, Vector3(0.62, eave - 0.55, 1.36), 0.5, 0.52, 0.0, p)
	var span := 2.7 if v == 1 else 2.5
	BuildParts.gable_roof(k, Vector3(0, eave, 0), span, span, 1.12, 0.26, p, roof_col)
	for s: float in [-1.0, 1.0]:
		BuildParts.gable_end(k, s * span * 0.5, span, eave, 1.12, 0.1, p.plaster, p.timber)
	# front: door, windows, dressing
	var front := 1.26
	BuildParts.door(k, Vector3(-0.45, plinth_h, front), 0.72, 1.3, 0.0, p)
	if v != 1:
		BuildParts.window(k, Vector3(0.72, plinth_h + 0.95, front), 0.58, 0.62, 0.0, p, true, v == 2)
		BuildParts.flower_box(k, Vector3(0.72, plinth_h + 0.58, front + 0.02), 0.72, 0.0, p)
	BuildParts.window(k, Vector3(1.26, plinth_h + 0.95, 0.55), 0.58, 0.62, 90.0, p)
	if v == 0:
		# dormer on the front roof slope
		var dy := eave + 0.5
		k.box(Vector3(0.28, dy + 0.2, 1.02), Vector3(0.68, 0.72, 0.6), p.plaster, p.plaster)
		BuildParts.gable_roof(k, Vector3(0.28, dy + 0.56, 1.02), 0.68, 0.6, 0.3, 0.12, p, roof_col)
		BuildParts.window(k, Vector3(0.28, dy + 0.26, 1.32), 0.36, 0.4, 0.0, p)
	elif v == 2:
		# lean-to shed on the +X side
		k.box(Vector3(1.0, plinth_h + 0.55, -0.85), Vector3(1.0, 1.1, 1.0), p.wood_dark)
		BuildParts.shed_roof(k, Vector3(1.0, plinth_h + 1.2, -0.85), 1.16, 1.1, 0.34, 0.1, p, p.wood)
		BuildParts.log_stack(k, Vector3(-1.05, 0, -0.95), p, 2)
	var _chim_top := BuildParts.chimney(k, Vector3(chim_side * 0.95, plinth_h + 0.6, -0.55),
		eave + 1.3 - (plinth_h + 0.6), p)
	k.box(Vector3(chim_side * 0.95, plinth_h + 0.3, -0.55), Vector3(0.6, 0.6, 0.6), p.stone, p.stone_top)
	if v == 1:
		BuildParts.barrel(k, Vector3(1.05, 0, 1.0), 0.24, 0.6, p)
		BuildParts.crate(k, Vector3(-1.15, 0, 0.95), 0.44, p, 18.0)
	else:
		BuildParts.barrel(k, Vector3(-1.2, 0, 0.55), 0.22, 0.56, p)
	BuildParts.lantern(k, Vector3(0.05, plinth_h + 1.55, 1.34), p)


# --- town hall ----------------------------------------------------------------------------------

## 4x4 great hall with a bell/clock tower and a bonfire at the front. Levels add a back wing,
## tower height and banners.
static func hearth(k: MeshKit, p: BuildPalette, _seed: int, lv: int) -> void:
	var hall_x := -0.75
	var hall_z := 0.05
	var w := 2.4
	var d := 2.7
	var plinth := 0.4
	k.push_trs(Vector3(hall_x, 0, hall_z))
	BuildParts.stone_base(k, w + 0.3, d + 0.3, plinth, p)
	BuildParts.framed_walls(k, Vector3(w, 2.15, d), plinth, p)
	var eave := plinth + 2.15
	BuildParts.gable_roof(k, Vector3(0, eave, 0), w, d, 1.25, 0.28, p)
	for s: float in [-1.0, 1.0]:
		BuildParts.gable_end(k, s * w * 0.5, d, eave, 1.25, 0.12, p.plaster, p.timber)
	# entrance porch on +Z
	var front := d * 0.5
	BuildParts.door(k, Vector3(0.1, plinth, front), 0.95, 1.6, 0.0, p, false)
	k.box(Vector3(0.1, plinth + 1.9, front + 0.3), Vector3(1.75, 0.14, 0.8), p.roof, p.roof.lightened(0.05))
	for s: float in [-1.0, 1.0]:
		k.cylinder(Vector3(0.1 + s * 0.8, plinth, front + 0.6), 1.85, 0.09, p.wood_dark, 6)
	BuildParts.window(k, Vector3(-0.92, plinth + 1.2, front), 0.5, 0.95, 0.0, p)
	BuildParts.window(k, Vector3(w * 0.5, plinth + 1.2, 0.72), 0.5, 0.95, 90.0, p)
	BuildParts.window(k, Vector3(w * 0.5, plinth + 1.2, -0.72), 0.5, 0.95, 90.0, p)
	# dormers on the front slope
	for s: float in [-1.0, 1.0]:
		var dx := s * 0.72
		k.box(Vector3(dx, eave + 0.42, front - 0.58), Vector3(0.62, 0.66, 0.6), p.plaster)
		BuildParts.gable_roof(k, Vector3(dx, eave + 0.75, front - 0.58), 0.62, 0.6, 0.28, 0.1, p)
		BuildParts.window(k, Vector3(dx, eave + 0.46, front - 0.28), 0.34, 0.38, 0.0, p)
	BuildParts.wall_banner(k, Vector3(-0.92, plinth + 2.02, front + 0.06), 0.5, 1.0, 0.0, p)
	if lv >= 2:
		BuildParts.wall_banner(k, Vector3(w * 0.5 + 0.06, plinth + 2.02, 0.72), 0.5, 1.0, 90.0, p)
	if lv >= 3:
		BuildParts.wall_banner(k, Vector3(w * 0.5 + 0.06, plinth + 2.02, -0.72), 0.5, 1.0, 90.0, p)
		BuildParts.wall_banner(k, Vector3(0.95, plinth + 2.02, front + 0.06), 0.5, 1.0, 0.0, p)
	k.pop()
	# back wing (level 2+)
	if lv >= 2:
		k.push_trs(Vector3(-0.6, 0, -1.62))
		BuildParts.stone_base(k, 1.9, 0.9, 0.3, p)
		BuildParts.framed_walls(k, Vector3(1.7, 1.35, 0.72), 0.3, p, false)
		BuildParts.shed_roof(k, Vector3(0, 1.72, 0.1), 1.9, 0.9, 0.42, 0.12, p)
		k.pop()
	# bell / clock tower on +X
	var tx := 1.25
	var tz := 0.45
	var th := 3.5 + 0.85 * float(lv - 1)
	k.push_trs(Vector3(tx, 0, tz))
	BuildParts.masonry(k, Vector3(0, 0.55, 0), Vector3(1.42, 1.1, 1.42), p, 2)
	BuildParts.framed_walls(k, Vector3(1.24, th - 1.1, 1.24), 1.1, p, false)
	BuildParts.window(k, Vector3(0, 2.0, 0.64), 0.36, 0.5, 0.0, p)
	BuildParts.window(k, Vector3(0.64, 2.0, 0), 0.36, 0.5, 90.0, p)
	# clock face
	k.push_trs(Vector3(0, th - 0.55, 0.64), Vector3(90, 0, 0))
	k.cylinder(Vector3(0, -0.06, 0), 0.08, 0.32, p.gold, 10)
	k.cylinder(Vector3(0, 0.0, 0), 0.05, 0.25, p.plaster, 10)
	k.box(Vector3(0, 0.05, 0.08), Vector3(0.04, 0.05, 0.17), p.timber)
	k.box(Vector3(0.1, 0.05, 0), Vector3(0.14, 0.05, 0.04), p.timber)
	k.pop()
	# open belfry with a bell
	var belfry := th
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			k.box(Vector3(sx * 0.56, belfry + 0.35, sz * 0.56), Vector3(0.14, 0.7, 0.14), p.wood_dark)
	k.box(Vector3(0, belfry + 0.04, 0), Vector3(1.34, 0.12, 1.34), p.wood_dark)
	k.frustum(Vector3(0, belfry + 0.24, 0), 0.4, 0.12, 0.3, p.gold, 8, true, p.gold)
	k.sphere(Vector3(0, belfry + 0.22, 0), 0.08, p.metal, 6, 3)
	BuildParts.hip_roof(k, Vector3(0, belfry + 0.7, 0), 1.3, 1.3, 0.85, 0.16, p)
	if lv >= 2:
		BuildParts.banner(k, Vector3(-0.62, 1.1, 0.68), 1.5, 0.42, 0.85, 0.0, p)
	k.pop()
	# bonfire in front of the hall
	BuildParts.campfire(k, Vector3(-0.25, 0.0, 1.6), 0.32, p)
	BuildParts.log_stack(k, Vector3(-1.62, 0, 1.6), p, 2)
	BuildParts.banner(k, Vector3(1.72, 0, 1.6), 2.4, 0.5, 1.1, 0.0, p)
	if lv >= 3:
		BuildParts.banner(k, Vector3(-1.85, 0, 0.6), 2.4, 0.5, 1.1, 270.0, p)


# --- barn ----------------------------------------------------------------------------------------

## 3x4 storehouse: plank barn with an open front, loft door and stacked goods.
static func storehouse(k: MeshKit, p: BuildPalette, seed: int) -> void:
	var plinth := 0.3
	BuildParts.stone_base(k, 2.84, 3.74, plinth, p)
	BuildParts.plank_wall(k, Vector3(2.5, 2.2, 3.4), plinth, p, seed, 0.0)
	var eave := plinth + 2.2
	# ridge runs along Z: build the gable rotated a quarter turn
	k.push_trs(Vector3.ZERO, Vector3(0, 90, 0))
	BuildParts.gable_roof(k, Vector3(0, eave, 0), 3.4, 2.5, 1.2, 0.26, p)
	for s: float in [-1.0, 1.0]:
		BuildParts.gable_end(k, s * 1.7, 2.5, eave, 1.2, 0.12, p.wood, p.timber)
	k.pop()
	# open front on +Z with goods inside
	BuildParts.opening(k, Vector3(0, plinth, 1.71), 1.5, 1.85, 0.7, 0.0, p)
	BuildParts.crate(k, Vector3(-0.45, plinth, 1.15), 0.5, p, 8.0)
	BuildParts.crate(k, Vector3(-0.45, plinth + 0.5, 1.2), 0.42, p, -12.0)
	BuildParts.barrel(k, Vector3(0.42, plinth, 1.2), 0.26, 0.64, p)
	BuildParts.sack(k, Vector3(0.0, plinth, 1.44), 0.42, p)
	# loft door + hoist beam in the front gable
	k.box(Vector3(0, eave + 0.52, 1.66), Vector3(0.72, 0.8, 0.1), p.wood_dark)
	k.box(Vector3(0, eave + 0.52, 1.7), Vector3(0.66, 0.74, 0.06), p.wood)
	k.box(Vector3(0, eave + 1.05, 1.85), Vector3(0.14, 0.14, 0.7), p.timber)
	k.tube(Vector3(0, eave + 1.0, 2.14), Vector3(0, eave + 0.55, 2.14), 0.02, p.metal, 4)
	k.box(Vector3(0, eave + 0.42, 2.14), Vector3(0.24, 0.24, 0.24), p.wood)
	# side windows and dressing
	BuildParts.window(k, Vector3(1.26, plinth + 1.35, 0.6), 0.46, 0.5, 90.0, p)
	BuildParts.window(k, Vector3(1.26, plinth + 1.35, -0.7), 0.46, 0.5, 90.0, p)
	BuildParts.crate(k, Vector3(1.1, 0, 1.55), 0.46, p, -14.0)
	BuildParts.barrel(k, Vector3(-1.12, 0, 1.5), 0.25, 0.62, p)
	BuildParts.barrel(k, Vector3(-1.16, 0, 1.0), 0.25, 0.62, p)
	BuildParts.signboard(k, Vector3(1.24, plinth + 2.0, 1.2), 90.0, p)


# --- workshop --------------------------------------------------------------------------------------

## 4x4 robot workshop: brick shell, iron roof, gears, pipes, a crane arm and a glowing furnace.
static func workshop(k: MeshKit, p: BuildPalette, _seed: int) -> void:
	var brick := Color("a35b45")
	var iron := p.metal.darkened(0.12)
	var plinth := 0.32
	k.push_trs(Vector3(-0.25, 0, -0.2))
	BuildParts.stone_base(k, 3.3, 2.9, plinth, p)
	BuildParts.framed_walls(k, Vector3(3.0, 2.3, 2.6), plinth, p, false, brick)
	# brick courses
	for c in 4:
		var y := plinth + 0.3 + float(c) * 0.5
		k.box(Vector3(0, y, 1.31), Vector3(2.9, 0.06, 0.04), brick.darkened(0.2))
		k.box(Vector3(1.51, y, 0), Vector3(0.04, 0.06, 2.5), brick.darkened(0.2))
	var eave := plinth + 2.3
	BuildParts.shed_roof(k, Vector3(0, eave + 0.2, 0), 3.0, 2.6, 0.55, 0.2, p, iron)
	for i in 5:
		var x := (float(i) - 2.0) * 0.62
		k.box(Vector3(x, eave + 0.3, 0), Vector3(0.07, 0.1, 2.9), iron.lightened(0.16))
	BuildParts.opening(k, Vector3(-0.55, plinth, 1.31), 1.0, 1.7, 0.4, 0.0, p)
	BuildParts.furnace_mouth(k, Vector3(0.85, plinth + 0.1, 1.33), 0.62, 0.72, 0.0, p)
	BuildParts.window(k, Vector3(1.51, plinth + 1.5, 0.6), 0.5, 0.5, 90.0, p)
	k.pop()
	# gears on the +X wall
	BuildParts.gear(k, Vector3(1.32, 1.5, 1.14), 0.62, 9, p.gold.darkened(0.15))
	BuildParts.gear(k, Vector3(1.6, 0.85, 1.14), 0.34, 7, p.metal.lightened(0.1))
	# pipework and chimney
	BuildParts.pipe(k, Vector3(-1.5, 0.6, 1.0), Vector3(-1.5, 2.5, 1.0), 0.11, p)
	BuildParts.pipe(k, Vector3(-1.5, 2.5, 1.0), Vector3(-1.5, 2.5, -0.4), 0.11, p)
	var _chim := BuildParts.chimney(k, Vector3(-1.5, 2.4, -0.7), 1.6, p, 0.36)
	# crane arm with a hanging crate
	k.cylinder(Vector3(1.4, 0, 0.55), 4.0, 0.12, p.wood_dark, 6)
	k.tube(Vector3(1.4, 3.9, 0.55), Vector3(1.4, 3.35, 1.75), 0.09, p.wood_dark, 5)
	k.tube(Vector3(1.4, 3.3, 0.6), Vector3(1.4, 3.85, 1.55), 0.05, p.metal, 4)
	k.tube(Vector3(1.4, 3.4, 1.72), Vector3(1.4, 2.6, 1.72), 0.02, p.metal, 4)
	BuildParts.crate(k, Vector3(1.4, 2.25, 1.72), 0.44, p, 10.0)
	# yard dressing
	BuildParts.crate(k, Vector3(-1.5, 0, 1.5), 0.46, p, -10.0)
	k.box(Vector3(0.5, 0.3, 1.75), Vector3(1.0, 0.12, 0.5), p.wood, p.wood.lightened(0.1))
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(0.5 + s * 0.4, 0.15, 1.75), Vector3(0.1, 0.3, 0.44), p.wood_dark)
	k.cylinder(Vector3(0.2, 0.36, 1.75), 0.3, 0.13, iron, 6)
	k.box(Vector3(0.75, 0.42, 1.72), Vector3(0.36, 0.12, 0.12), p.metal)
	BuildParts.lantern(k, Vector3(1.75, 1.9, 1.62), p, 1.9)


# --- smelter -----------------------------------------------------------------------------------------

## 3x3 stone furnace with a glowing mouth, ember bed and a tall banded chimney.
static func smelter(k: MeshKit, p: BuildPalette, _seed: int) -> void:
	BuildParts.stone_base(k, 2.7, 2.7, 0.36, p)
	# tapered kiln body
	k.frustum(Vector3(-0.15, 0.36, -0.1), 1.9, 1.15, 0.78, p.stone, 8, true, p.stone_top)
	for i in 3:
		k.frustum(Vector3(-0.15, 0.5 + float(i) * 0.6, -0.1), 0.1,
			1.13 - float(i) * 0.12, 1.11 - float(i) * 0.12, p.stone_dark, 8, false)
	BuildParts.furnace_mouth(k, Vector3(-0.15, 0.4, 0.95), 0.78, 0.82, 0.0, p)
	# ember bed spilling out of the mouth
	k.box(Vector3(-0.15, 0.4, 1.2), Vector3(0.9, 0.1, 0.4), MeshKit.glow(Color("ff7a28"), 0.7))
	for i in 3:
		k.sphere(Vector3(-0.5 + float(i) * 0.36, 0.46, 1.28), 0.09,
			MeshKit.glow(Color("ffb14a"), 0.8), 5, 2)
	# chimney
	var cx := 0.72
	BuildParts.masonry(k, Vector3(cx, 1.4, -0.72), Vector3(0.72, 2.8, 0.72), p, 4)
	for i in 3:
		k.box(Vector3(cx, 0.9 + float(i) * 0.9, -0.72), Vector3(0.8, 0.09, 0.8), p.metal)
	k.box(Vector3(cx, 2.88, -0.72), Vector3(0.92, 0.14, 0.92), p.stone_top)
	k.frustum(Vector3(cx, 2.95, -0.72), 0.3, 0.42, 0.34, p.metal, 8, false)
	# bellows and fuel on the sides
	k.push_trs(Vector3(-1.2, 0.36, 0.1), Vector3(0, 0, 0))
	k.box(Vector3(0, 0.36, 0), Vector3(0.36, 0.1, 0.72), p.wood_dark)
	k.box(Vector3(0, 0.5, 0.05), Vector3(0.32, 0.2, 0.6), Color("6e4b33"))
	k.box(Vector3(0, 0.62, -0.1), Vector3(0.34, 0.08, 0.5), p.wood)
	k.tube(Vector3(0, 0.42, -0.36), Vector3(0.55, 0.42, -0.36), 0.05, p.metal, 5)
	k.pop()
	BuildParts.log_stack(k, Vector3(1.1, 0, 1.2), p, 2)
	k.box(Vector3(-1.05, 0.12, -1.0), Vector3(0.7, 0.24, 0.7), p.stone_dark)
	for i in 4:
		k.sphere(Vector3(-1.2 + float(i % 2) * 0.3, 0.3 + float(i / 2) * 0.16, -1.1 + float(i / 2) * 0.2),
			0.14, Color("8a6a4a"), 5, 2)


# --- windmill --------------------------------------------------------------------------------------

## 3x3 tapered mill tower; the sails live on a separate spinning node.
static func windmill(k: MeshKit, p: BuildPalette, _seed: int) -> void:
	BuildParts.stone_base(k, 2.6, 2.6, 0.45, p)
	k.frustum(Vector3(0, 0.45, 0), 4.3, 1.12, 0.78, p.plaster, 10, true, p.plaster)
	for i in 4:
		k.frustum(Vector3(0, 0.7 + float(i) * 1.0, 0), 0.12,
			1.1 - float(i) * 0.08, 1.08 - float(i) * 0.08, p.timber, 10, false)
	# vertical timbers
	for i in 8:
		var a := TAU * float(i) / 8.0
		k.tube(Vector3(cos(a) * 1.08, 0.5, sin(a) * 1.08), Vector3(cos(a) * 0.76, 4.7, sin(a) * 0.76),
			0.05, p.timber, 4)
	BuildParts.door(k, Vector3(0, 0.45, 1.02), 0.62, 1.2, 0.0, p, false)
	BuildParts.round_window(k, Vector3(0.62, 2.4, 0.72), 0.22, 40.0, p)
	BuildParts.window(k, Vector3(0, 3.35, 0.86), 0.34, 0.42, 0.0, p)
	# gallery balcony
	k.torus(Vector3(0, 2.05, 0), 1.06, 0.07, p.wood_dark, 12, 4)
	for i in 10:
		var a := TAU * float(i) / 10.0
		k.cylinder(Vector3(cos(a) * 1.02, 1.72, sin(a) * 1.02), 0.36, 0.035, p.wood_dark, 4)
	k.frustum(Vector3(0, 1.66, 0), 0.1, 1.12, 1.06, p.wood, 10)
	# cap
	BuildParts.cone_roof(k, Vector3(0, 4.75, 0), 0.92, 1.0, p)
	k.box(Vector3(0, 5.0, 0.6), Vector3(0.3, 0.3, 0.8), p.wood_dark)
	# tail pole at the back
	k.tube(Vector3(0, 5.0, -0.5), Vector3(0, 4.0, -1.25), 0.06, p.wood_dark, 5)
	BuildParts.crate(k, Vector3(-1.05, 0, 1.0), 0.44, p, 12.0)
	BuildParts.sack(k, Vector3(1.0, 0, 1.05), 0.42, p)


## Four lattice sails for the windmill's spinning node (local origin = hub, blades in XY).
static func windmill_sails(p: BuildPalette) -> MeshKit:
	var k := MeshKit.new()
	k.shade_jitter = 0.02
	k.cylinder(Vector3(0, 0, -0.16), 0.34, 0.16, p.metal, 8)
	k.sphere(Vector3(0, 0, 0.06), 0.18, p.wood_dark, 6, 3)
	for i in 4:
		k.push_trs(Vector3.ZERO, Vector3(0, 0, 90.0 * float(i)))
		k.box(Vector3(0, 0.75, 0), Vector3(0.11, 1.5, 0.11), p.wood_dark)
		k.box(Vector3(0.16, 0.78, 0.02), Vector3(0.36, 1.32, 0.05), p.plaster)
		for j in 4:
			k.box(Vector3(0.16, 0.3 + float(j) * 0.35, 0.05), Vector3(0.38, 0.05, 0.04), p.wood_dark)
		k.box(Vector3(0.16, 0.78, 0.05), Vector3(0.05, 1.32, 0.04), p.wood_dark)
		k.pop()
	return k


# --- sky dock ----------------------------------------------------------------------------------------

## 4x4 mooring tower: braced scaffold, plank platform, mast, lanterns and a loading derrick.
static func sky_dock(k: MeshKit, p: BuildPalette, _seed: int) -> void:
	var deck := 5.3
	var b := 1.52   # post offset at the ground
	var t := 1.32   # post offset at the deck
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			k.box(Vector3(sx * b, 0.16, sz * b), Vector3(0.5, 0.32, 0.5), p.stone, p.stone_top)
			k.tube(Vector3(sx * b, 0.2, sz * b), Vector3(sx * t, deck, sz * t), 0.11, p.wood_dark, 6)
	# ring beams and cross bracing on each side
	for lvl in 3:
		var y := 1.3 + float(lvl) * 1.55
		var e: float = lerpf(b, t, y / deck)
		for s: float in [-1.0, 1.0]:
			k.box(Vector3(0, y, s * e), Vector3(e * 2.0, 0.12, 0.1), p.wood)
			k.box(Vector3(s * e, y, 0), Vector3(0.1, 0.12, e * 2.0), p.wood)
		if lvl < 2:
			var y2 := y + 1.55
			var e2: float = lerpf(b, t, y2 / deck)
			for s: float in [-1.0, 1.0]:
				k.tube(Vector3(-e, y, s * e), Vector3(e2, y2, s * e2), 0.055, p.wood, 4)
				k.tube(Vector3(e, y, s * e), Vector3(-e2, y2, s * e2), 0.055, p.wood, 4)
				k.tube(Vector3(s * e, y, -e), Vector3(s * e2, y2, e2), 0.055, p.wood, 4)
	# deck
	for i in 9:
		var z := (float(i) - 4.0) * 0.36
		k.box(Vector3(0, deck + 0.1, z), Vector3(3.2, 0.14, 0.32), p.wood, p.wood.lightened(0.12))
	k.box(Vector3(0, deck + 0.02, 0), Vector3(3.3, 0.12, 3.3), p.wood_dark)
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(s * 1.6, deck + 0.06, 0), Vector3(0.14, 0.2, 3.3), p.timber)
	# railings on the back and both sides of the deck (front stays open for the ladder)
	k.push_trs(Vector3(0, deck + 0.16, 0))
	BuildParts.rail_run(k, -1.5, 1.5, -1.55, 0.8, p)
	k.push_trs(Vector3(0, 0, 0), Vector3(0, 90, 0))
	BuildParts.rail_run(k, -1.5, 1.5, -1.55, 0.8, p)
	BuildParts.rail_run(k, -1.5, 1.5, 1.55, 0.8, p)
	k.pop()
	# mooring mast with ring and pennant
	k.frustum(Vector3(0, 0.2, 0), 2.2, 0.18, 0.14, p.wood_dark, 6)
	k.cylinder(Vector3(0, 0.2, 0), 2.45, 0.13, p.wood_dark, 6)
	k.torus(Vector3(0, 2.5, 0), 0.26, 0.05, p.gold, 10, 4)
	k.push_trs(Vector3(0, 2.62, 0))
	k.plate(PackedVector2Array([Vector2(0, 0), Vector2(0.75, -0.16), Vector2(0, -0.34)]), 0.03, p.cloth)
	k.pop()
	for sx: float in [-1.0, 1.0]:
		k.tube(Vector3(0, 2.3, 0), Vector3(sx * 1.4, 0.2, -1.4), 0.025, p.wood_dark, 4)
	# deck dressing
	BuildParts.crate(k, Vector3(-1.05, 0.16, 0.95), 0.5, p, 12.0)
	BuildParts.crate(k, Vector3(-1.05, 0.66, 1.0), 0.42, p, -8.0)
	BuildParts.barrel(k, Vector3(1.05, 0.16, -0.9), 0.26, 0.62, p)
	for sx: float in [-1.0, 1.0]:
		BuildParts.lantern(k, Vector3(sx * 1.5, 1.0, 1.5), p)
	k.pop()
	# loading derrick beside the deck
	k.cylinder(Vector3(1.45, 0, 1.45), deck + 1.3, 0.12, p.wood_dark, 6)
	k.tube(Vector3(1.45, deck + 1.2, 1.45), Vector3(0.35, deck + 0.95, 1.85), 0.08, p.wood_dark, 5)
	k.tube(Vector3(0.4, deck + 0.98, 1.83), Vector3(0.4, deck + 0.2, 1.83), 0.02, p.metal, 4)
	BuildParts.crate(k, Vector3(0.4, deck - 0.2, 1.83), 0.42, p, 6.0)
	# ladder from the ground to the deck at the front
	BuildParts.ladder(k, Vector3(0.55, 0, 1.62), Vector3(0.55, deck + 0.1, 1.38), 0.5, p.wood)
	BuildParts.banner(k, Vector3(-1.5, 0.2, 1.5), 3.0, 0.5, 1.2, 0.0, p)


# --- watchtower --------------------------------------------------------------------------------------

## 2x2 tower: stone foot, timber shaft, overhanging roofed platform, banner and a ballista.
static func watchtower(k: MeshKit, p: BuildPalette, _seed: int) -> void:
	BuildParts.masonry(k, Vector3(0, 0.7, 0), Vector3(1.62, 1.4, 1.62), p, 3)
	BuildParts.framed_walls(k, Vector3(1.26, 2.1, 1.26), 1.4, p, false)
	BuildParts.window(k, Vector3(0, 2.3, 0.64), 0.3, 0.42, 0.0, p)
	BuildParts.door(k, Vector3(0, 0.0, 0.82), 0.5, 1.05, 0.0, p, false)
	# corbels + platform
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			k.tube(Vector3(sx * 0.6, 3.1, sz * 0.6), Vector3(sx * 0.85, 3.52, sz * 0.85), 0.08, p.wood_dark, 4)
	k.box(Vector3(0, 3.58, 0), Vector3(1.82, 0.16, 1.82), p.wood, p.wood.lightened(0.12))
	for i in 5:
		var z := (float(i) - 2.0) * 0.36
		k.box(Vector3(0, 3.68, z), Vector3(1.78, 0.06, 0.3), p.wood.lightened(0.06))
	# railing
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(0, 3.95, s * 0.86), Vector3(1.82, 0.42, 0.1), p.wood_dark)
		k.box(Vector3(s * 0.86, 3.95, 0), Vector3(0.1, 0.42, 1.82), p.wood_dark)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			k.box(Vector3(sx * 0.86, 4.0, sz * 0.86), Vector3(0.16, 0.6, 0.16), p.timber)
	# roof on four posts
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			k.box(Vector3(sx * 0.76, 4.45, sz * 0.76), Vector3(0.12, 1.0, 0.12), p.timber)
	BuildParts.hip_roof(k, Vector3(0, 4.9, 0), 1.75, 1.75, 0.8, 0.12, p)
	# small ballista facing +Z
	k.box(Vector3(0, 3.9, 0.15), Vector3(0.5, 0.18, 0.62), p.wood_dark)
	k.cylinder(Vector3(0, 3.76, 0.15), 0.2, 0.1, p.wood_dark, 6)
	k.box(Vector3(0, 4.02, 0.42), Vector3(1.0, 0.09, 0.1), p.wood)
	for s: float in [-1.0, 1.0]:
		k.tube(Vector3(s * 0.5, 4.02, 0.42), Vector3(0, 4.02, 0.2), 0.02, p.metal, 4)
	k.tube(Vector3(0, 4.05, 0.2), Vector3(0, 4.05, 0.75), 0.04, p.wood, 4)
	k.cone(Vector3(0, 4.05, 0.75), 0.16, 0.06, p.metal, 5)
	BuildParts.banner(k, Vector3(0.86, 3.68, -0.86), 1.9, 0.44, 0.95, 270.0, p)
	BuildParts.ladder(k, Vector3(0, 0, -0.95), Vector3(0, 3.55, -0.78), 0.44, p.wood)
	BuildParts.lantern(k, Vector3(-0.86, 4.05, 0.86), p)


# --- wall & palisade ------------------------------------------------------------------------------------

## 1x1 crenellated stone wall block; spans the full tile in X so runs tile seamlessly.
static func wall(k: MeshKit, p: BuildPalette, _seed: int) -> void:
	k.box(Vector3(0, 0.75, 0), Vector3(1.0, 1.5, 0.84), p.stone, p.stone_top)
	for c in 3:
		var y := 0.25 + float(c) * 0.5
		for b in 3:
			var x := (float(b) + (0.5 if c % 2 == 0 else 0.0)) / 3.0 - 0.5
			if absf(x) > 0.42:
				continue
			k.box(Vector3(x, y, 0.42), Vector3(0.26, 0.34, 0.05), p.stone_dark)
	# walkway + crenellation
	k.box(Vector3(0, 1.54, 0), Vector3(1.0, 0.08, 0.92), p.stone_dark, p.stone_top)
	for i in 3:
		var x := (float(i) - 1.0) / 3.0
		k.box(Vector3(x, 1.72, 0), Vector3(0.28, 0.3, 0.9), p.stone, p.stone_top)
	k.box(Vector3(0, 1.0, 0.44), Vector3(0.12, 0.4, 0.04), Color("2c3442"))
	k.box(Vector3(-0.24, 1.5, 0.3), Vector3(0.4, 0.06, 0.3), p.moss)


## 1x1 sharpened stake wall segment.
static func palisade(k: MeshKit, p: BuildPalette, seed: int) -> void:
	k.box(Vector3(0, 0.08, -0.1), Vector3(1.0, 0.16, 0.44), Color("6c5a43"))
	for i in 4:
		var x := (float(i) - 1.5) * 0.25
		var h := 1.62 + 0.12 * RngUtil.hash01(seed, i, 2)
		k.cylinder(Vector3(x, 0.05, 0.0), h, 0.125, p.wood, 6, p.wood.lightened(0.1))
		k.cone(Vector3(x, 0.05 + h, 0.0), 0.3, 0.125, p.wood_dark, 6)
	for y: float in [0.55, 1.25]:
		k.box(Vector3(0, y, -0.16), Vector3(1.0, 0.11, 0.1), p.wood_dark)


# --- outpost & campfire ------------------------------------------------------------------------------------

## 3x3 frontier outpost: stockade ring with a gate, tent, crates, banner and a fire.
static func outpost(k: MeshKit, p: BuildPalette, _seed: int) -> void:
	k.box(Vector3(0, 0.04, 0), Vector3(2.9, 0.08, 2.9), Color("9c8a6a"), Color("ad9a78"))
	BuildParts.stake_ring(k, 1.35, 1.35, 1.75, p, 18, true, true)
	# gate posts and lintel
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(s * 0.52, 1.0, 1.28), Vector3(0.2, 2.0, 0.2), p.wood_dark)
	k.box(Vector3(0, 1.95, 1.28), Vector3(1.4, 0.18, 0.24), p.timber)
	BuildParts.crest(k, Vector3(0, 1.95, 1.42), 0.3, 0.0, p.gold)
	# ridge tent
	k.push_trs(Vector3(-0.42, 0, -0.35))
	k.tube(Vector3(-0.62, 0, 0), Vector3(-0.62, 1.15, 0), 0.05, p.wood_dark, 4)
	k.tube(Vector3(0.62, 0, 0), Vector3(0.62, 1.15, 0), 0.05, p.wood_dark, 4)
	k.tube(Vector3(-0.68, 1.12, 0), Vector3(0.68, 1.12, 0), 0.045, p.wood_dark, 4)
	k.prism_xz(PackedVector2Array([Vector2(-0.66, -0.62), Vector2(0.66, -0.62), Vector2(0.66, 0.62),
		Vector2(-0.66, 0.62)]), 0.0, 0.02, p.plaster)
	for s: float in [-1.0, 1.0]:
		k.push_trs(Vector3(0, 1.12, s * 0.32), Vector3(s * 30.0, 0, 0))
		k.box(Vector3(0, -0.03, 0), Vector3(1.34, 0.06, 0.78), p.plaster, p.plaster.lightened(0.06))
		k.pop()
	for s: float in [-1.0, 1.0]:
		k.push_trs(Vector3(s * 0.67, 0, 0), Vector3(0, 90, 0))
		k.plate(PackedVector2Array([Vector2(-0.6, 0), Vector2(0.6, 0), Vector2(0, 1.12)]), 0.03,
			p.plaster_dark)
		k.pop()
	k.pop()
	BuildParts.campfire(k, Vector3(0.62, 0, -0.55), 0.28, p)
	BuildParts.crate(k, Vector3(0.75, 0, 0.5), 0.46, p, 14.0)
	BuildParts.barrel(k, Vector3(0.18, 0, 0.72), 0.24, 0.58, p)
	BuildParts.banner(k, Vector3(-1.12, 0, 0.92), 2.6, 0.48, 1.05, 0.0, p)


## 1x1 campfire: stone ring, burning logs, cooking tripod.
static func campfire(k: MeshKit, p: BuildPalette, _seed: int) -> void:
	BuildParts.campfire(k, Vector3.ZERO, 0.3, p)
	for i in 3:
		var a := TAU * float(i) / 3.0 + 0.5
		k.tube(Vector3(cos(a) * 0.36, 0, sin(a) * 0.36), Vector3(0, 1.0, 0), 0.035, p.wood_dark, 4)
	k.tube(Vector3(0, 0.98, 0), Vector3(0, 0.78, 0), 0.015, p.metal, 4)
	k.frustum(Vector3(0, 0.55, 0), 0.24, 0.16, 0.2, p.metal, 8, true, p.metal.darkened(0.3))
	k.box(Vector3(0.44, 0.1, 0.4), Vector3(0.46, 0.2, 0.2), p.wood_dark)


## Single metre of a timber bridge: raised deck, bolted joists and camera-independent rails.
static func bridge_segment(k: MeshKit, p: BuildPalette) -> void:
	k.box(Vector3(0, 0.14, 0), Vector3(0.96, 0.12, 0.96), p.wood_dark)
	for i in 4:
		var z := (float(i) - 1.5) * 0.23
		k.box(Vector3(0, 0.23, z), Vector3(0.92, 0.08, 0.21), p.wood, p.wood.lightened(0.1))
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(s * 0.43, 0.38, 0), Vector3(0.09, 0.4, 0.09), p.timber)
		k.box(Vector3(s * 0.43, 0.52, 0), Vector3(0.08, 0.07, 0.88), p.wood)
		for z: float in [-0.34, 0.34]:
			k.box(Vector3(s * 0.43, 0.23, z), Vector3(0.035, 0.04, 0.035), p.metal)


## Single metre of stout cliff stair: stone foot, visible treads and timber side rails.
static func cliff_stairs(k: MeshKit, p: BuildPalette) -> void:
	k.box(Vector3(0, 0.06, 0), Vector3(0.92, 0.12, 0.92), p.stone, p.stone_top)
	for i in 4:
		var z := -0.36 + float(i) * 0.24
		var y := 0.18 + float(i) * 0.2
		k.box(Vector3(0, y, z), Vector3(0.78, 0.1, 0.28), p.wood, p.wood.lightened(0.12))
	for s: float in [-1.0, 1.0]:
		k.tube(Vector3(s * 0.43, 0.22, 0.43), Vector3(s * 0.43, 1.0, -0.43), 0.055, p.timber, 5)
		for i in 3:
			var z := 0.28 - float(i) * 0.24
			var y := 0.48 + float(i) * 0.2
			k.box(Vector3(s * 0.43, y, z), Vector3(0.12, 0.12, 0.12), p.wood_dark)
