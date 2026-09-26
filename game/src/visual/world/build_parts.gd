class_name BuildParts
extends RefCounted
## Reusable architectural pieces for the world buildings: stone plinths, timber-framed walls,
## tiled gable/hip roofs, framed windows, doors, chimneys, banners, scaffolding and small
## dressing props (crates, barrels, flower boxes, lanterns, signs).
##
## Every function emits into the MeshKit's *current* transform frame, so callers can push/pop to
## place a part anywhere. Conventions: +Y up, model front = +Z, origin = footprint centre.

const YAW_FRONT := 0.0
const YAW_RIGHT := 90.0
const YAW_BACK := 180.0
const YAW_LEFT := 270.0


# --- masonry ----------------------------------------------------------------------------------

## Stone plinth with a few proud stones on the camera-facing sides.
static func stone_base(k: MeshKit, size_x: float, size_z: float, height: float, p: BuildPalette,
		y0: float = 0.0) -> void:
	k.box(Vector3(0, y0 + height * 0.5, 0), Vector3(size_x, height, size_z), p.stone, p.stone_top)
	var nx := maxi(2, int(size_x / 0.95))
	for i in nx:
		var t := (float(i) + 0.5) / float(nx) - 0.5
		k.box(Vector3(t * size_x, y0 + height * 0.66, size_z * 0.5),
			Vector3(size_x / float(nx) * 0.6, height * 0.4, 0.07), p.stone_dark)
	var nz := maxi(2, int(size_z / 0.95))
	for i in nz:
		var t := (float(i) + 0.5) / float(nz) - 0.5
		k.box(Vector3(size_x * 0.5, y0 + height * 0.32, t * size_z),
			Vector3(0.07, height * 0.36, size_z / float(nz) * 0.6), p.stone_dark)


## Rough stone masonry block with staggered courses (castle walls, towers, ruins).
static func masonry(k: MeshKit, centre: Vector3, size: Vector3, p: BuildPalette,
		courses: int = 3) -> void:
	k.box(centre, size, p.stone, p.stone_top)
	var ch := size.y / float(maxi(courses, 1))
	for c in courses:
		var y := centre.y - size.y * 0.5 + ch * (float(c) + 0.5)
		var blocks := maxi(2, int(size.x / 0.7))
		for b in blocks:
			var t := (float(b) + (0.5 if c % 2 == 0 else 0.85)) / float(blocks) - 0.5
			if absf(t) > 0.48:
				continue
			k.box(Vector3(centre.x + t * size.x, y, centre.z + size.z * 0.5),
				Vector3(size.x / float(blocks) * 0.72, ch * 0.66, 0.06), p.stone_dark)
		k.box(Vector3(centre.x + size.x * 0.5, y, centre.z + (0.12 if c % 2 == 0 else -0.16)),
			Vector3(0.06, ch * 0.66, size.z * 0.42), p.stone_dark)


# --- timber-framed walls ------------------------------------------------------------------------

## Plaster wall block with a corner-post timber frame, sill and top plate.
## `size` = (x, height, z), `y0` = ground height of the wall foot.
static func framed_walls(k: MeshKit, size: Vector3, y0: float, p: BuildPalette,
		braces: bool = true, infill: Color = Color(0, 0, 0, 0)) -> void:
	var fill := infill if infill.a > 0.0 else p.plaster
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var yc := y0 + size.y * 0.5
	k.box(Vector3(0, yc, 0), size, fill, fill.lightened(0.05))
	var post := 0.17
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			k.box(Vector3(sx * hx, yc, sz * hz), Vector3(post, size.y, post), p.timber)
	k.box(Vector3(0, y0 + 0.09, 0), Vector3(size.x + 0.09, 0.18, size.z + 0.09), p.timber)
	k.box(Vector3(0, y0 + size.y - 0.09, 0), Vector3(size.x + 0.11, 0.18, size.z + 0.11), p.timber)
	if braces:
		_braces(k, size.x, y0 + 0.2, size.y - 0.4, hz, 0.0, p.timber)
		_braces(k, size.z, y0 + 0.2, size.y - 0.4, hx, 90.0, p.timber)


## Diagonal frame braces on one wall face (yaw selects the face).
static func _braces(k: MeshKit, width: float, y0: float, height: float, dist: float, yaw: float,
		col: Color) -> void:
	var run := width * 0.3
	var rise := height * 0.8
	var length := sqrt(run * run + rise * rise)
	var ang := rad_to_deg(atan2(run, rise))
	k.push_trs(Vector3.ZERO, Vector3(0, yaw, 0))
	for s: float in [-1.0, 1.0]:
		k.push_trs(Vector3(s * width * 0.27, y0 + height * 0.5, dist), Vector3(0, 0, s * ang))
		k.box(Vector3.ZERO, Vector3(0.13, length, 0.09), col)
		k.pop()
	k.pop()


## Vertical plank wall (barns, sheds, ramshackle huts). `jitter` lets planks vary in width.
static func plank_wall(k: MeshKit, size: Vector3, y0: float, p: BuildPalette, seed: int = 0,
		jitter: float = 0.0) -> void:
	k.box(Vector3(0, y0 + size.y * 0.5, 0), size, p.wood_dark, p.wood_dark)
	var n := maxi(3, int(size.x / 0.34))
	for i in n:
		var t := (float(i) + 0.5) / float(n) - 0.5
		var h := size.y * (1.0 - jitter * RngUtil.hash01(seed, i, 3))
		k.box(Vector3(t * size.x, y0 + h * 0.5, size.z * 0.5),
			Vector3(size.x / float(n) * 0.82, h, 0.08), p.wood if i % 2 == 0 else p.wood.darkened(0.12))
	var m := maxi(3, int(size.z / 0.34))
	for i in m:
		var t := (float(i) + 0.5) / float(m) - 0.5
		var h := size.y * (1.0 - jitter * RngUtil.hash01(seed, i, 7))
		k.box(Vector3(size.x * 0.5, y0 + h * 0.5, t * size.z),
			Vector3(0.08, h, size.z / float(m) * 0.82), p.wood.darkened(0.06) if i % 2 == 0 else p.wood)
	k.box(Vector3(0, y0 + size.y - 0.08, 0), Vector3(size.x + 0.1, 0.16, size.z + 0.1), p.timber)


# --- roofs ---------------------------------------------------------------------------------------

## Tiled gable roof: two thick slabs with eaves, shingle courses, fascia boards and a ridge beam.
## `centre` is the eave-line centre (top of the walls); the ridge runs along X.
static func gable_roof(k: MeshKit, centre: Vector3, span_x: float, span_z: float, height: float,
		overhang: float, p: BuildPalette, roof_col: Color = Color(0, 0, 0, 0)) -> void:
	var col := roof_col if roof_col.a > 0.0 else p.roof
	var half_z := span_z * 0.5 + overhang
	var slope := sqrt(half_z * half_z + height * height)
	var ang := rad_to_deg(atan2(height, half_z))
	var length := span_x + overhang * 2.0
	var thick := 0.13
	for s: float in [1.0, -1.0]:
		k.push_trs(centre + Vector3(0, height, 0), Vector3(s * ang, 0, 0))
		k.box(Vector3(0, -thick * 0.5, s * slope * 0.5), Vector3(length, thick, slope), col, col.lightened(0.06))
		for c in 3:
			var z := slope * (0.28 + 0.26 * float(c))
			k.box(Vector3(0, 0.016, s * z), Vector3(length, 0.045, 0.06), p.roof_dark)
		k.box(Vector3(0, -thick * 0.55, s * (slope - 0.05)), Vector3(length + 0.06, 0.14, 0.07), p.wood_dark)
		k.pop()
	k.box(centre + Vector3(0, height + 0.05, 0), Vector3(length + 0.12, 0.15, 0.2), p.wood_dark)


## Triangular gable end filling the wall top up to the ridge, at x = `x`.
static func gable_end(k: MeshKit, x: float, span_z: float, y0: float, height: float,
		thickness: float, col: Color, timber: Color) -> void:
	var hz := span_z * 0.5
	k.push_trs(Vector3(x, y0, 0), Vector3(0, 90, 0))
	k.plate(PackedVector2Array([Vector2(-hz, 0), Vector2(hz, 0), Vector2(0, height)]), thickness, col)
	k.pop()
	k.box(Vector3(x, y0 + height * 0.5, 0), Vector3(thickness + 0.04, height * 0.96, 0.13), timber)


## Mono-pitch (lean-to) roof sloping down toward +Z.
static func shed_roof(k: MeshKit, centre: Vector3, span_x: float, span_z: float, drop: float,
		overhang: float, p: BuildPalette, col: Color = Color(0, 0, 0, 0)) -> void:
	var c := col if col.a > 0.0 else p.roof
	var run := span_z + overhang * 2.0
	var ang := rad_to_deg(atan2(drop, run))
	k.push_trs(centre + Vector3(0, drop * 0.5, 0), Vector3(ang, 0, 0))
	k.box(Vector3.ZERO, Vector3(span_x + overhang * 2.0, 0.12, run), c, c.lightened(0.06))
	k.box(Vector3(0, 0.02, run * 0.1), Vector3(span_x + overhang * 2.0, 0.04, 0.06), p.roof_dark)
	k.box(Vector3(0, 0.02, -run * 0.22), Vector3(span_x + overhang * 2.0, 0.04, 0.06), p.roof_dark)
	k.pop()


## Four-sided hip roof with eaves and a finial (towers, wells, watch platforms).
static func hip_roof(k: MeshKit, base: Vector3, span_x: float, span_z: float, height: float,
		overhang: float, p: BuildPalette, finial: bool = true) -> void:
	k.box(base + Vector3(0, 0.07, 0), Vector3(span_x + overhang * 2.0, 0.14, span_z + overhang * 2.0),
		p.wood_dark)
	k.pyramid(base + Vector3(0, 0.14, 0), Vector2(span_x + overhang * 1.7, span_z + overhang * 1.7),
		height, p.roof)
	k.pyramid(base + Vector3(0, 0.14 + height * 0.34, 0),
		Vector2((span_x + overhang * 1.7) * 0.62, (span_z + overhang * 1.7) * 0.62), height * 0.05,
		p.roof_dark)
	if finial:
		k.cylinder(base + Vector3(0, 0.14 + height, 0), 0.26, 0.05, p.gold, 5)
		k.sphere(base + Vector3(0, 0.14 + height + 0.3, 0), 0.1, p.gold, 6, 3)


## Conical roof (windmill cap, yurt).
static func cone_roof(k: MeshKit, base: Vector3, radius: float, height: float, p: BuildPalette,
		col: Color = Color(0, 0, 0, 0)) -> void:
	var c := col if col.a > 0.0 else p.roof
	k.frustum(base, 0.12, radius + 0.1, radius + 0.1, p.wood_dark, 10)
	k.cone(base + Vector3(0, 0.1, 0), height, radius, c, 10)


# --- openings -------------------------------------------------------------------------------------

## Framed window with a warm pane, mullions and a sill. `pos` sits on the wall surface.
static func window(k: MeshKit, pos: Vector3, w: float, h: float, yaw: float, p: BuildPalette,
		lit: bool = true, shutters: bool = false) -> void:
	k.push_trs(pos, Vector3(0, yaw, 0))
	k.box(Vector3(0, 0, 0.02), Vector3(w + 0.16, h + 0.16, 0.08), p.timber)
	var pane := MeshKit.glow(p.glow, 0.85) if lit else Color("2c3442")
	k.box(Vector3(0, 0, 0.06), Vector3(w, h, 0.03), pane)
	k.box(Vector3(0, 0, 0.08), Vector3(0.05, h, 0.02), p.timber)
	k.box(Vector3(0, 0, 0.08), Vector3(w, 0.05, 0.02), p.timber)
	k.box(Vector3(0, -h * 0.5 - 0.11, 0.07), Vector3(w + 0.3, 0.09, 0.18), p.wood)
	if shutters:
		for s: float in [-1.0, 1.0]:
			k.box(Vector3(s * (w * 0.5 + 0.16), 0, 0.05), Vector3(0.2, h + 0.08, 0.05), p.cloth)
	k.pop()


## Small round/arched window (towers, halls).
static func round_window(k: MeshKit, pos: Vector3, radius: float, yaw: float, p: BuildPalette,
		lit: bool = true) -> void:
	k.push_trs(pos, Vector3(0, yaw, 90))
	k.cylinder(Vector3(0, -0.02, 0), 0.09, radius + 0.09, p.timber, 8)
	k.cylinder(Vector3(0, 0.04, 0), 0.04, radius, MeshKit.glow(p.glow, 0.85) if lit else Color("2c3442"), 8)
	k.pop()


## Plank door with frame, handle, hood and a stone step. `pos` is the doorstep on the wall surface.
static func door(k: MeshKit, pos: Vector3, w: float, h: float, yaw: float, p: BuildPalette,
		hood: bool = true) -> void:
	k.push_trs(pos, Vector3(0, yaw, 0))
	k.box(Vector3(0, h * 0.5, 0.02), Vector3(w + 0.2, h + 0.14, 0.09), p.timber)
	k.box(Vector3(0, h * 0.5, 0.06), Vector3(w, h, 0.05), p.wood_dark)
	for t: float in [-0.3, 0.0, 0.3]:
		k.box(Vector3(t * w, h * 0.5, 0.09), Vector3(0.05, h - 0.1, 0.02), p.wood)
	k.box(Vector3(0, h * 0.72, 0.09), Vector3(w - 0.06, 0.07, 0.02), p.metal)
	k.box(Vector3(w * 0.3, h * 0.45, 0.11), Vector3(0.09, 0.09, 0.04), p.gold)
	if hood:
		k.box(Vector3(0, h + 0.2, 0.16), Vector3(w + 0.46, 0.1, 0.42), p.roof, p.roof.lightened(0.05))
		for s: float in [-1.0, 1.0]:
			k.box(Vector3(s * (w * 0.5 + 0.12), h + 0.05, 0.16), Vector3(0.08, 0.24, 0.4), p.wood_dark)
	k.box(Vector3(0, 0.05, 0.2), Vector3(w + 0.3, 0.1, 0.34), p.stone, p.stone_top)
	k.pop()


## Open archway / barn opening with a dark interior and a timber lintel.
static func opening(k: MeshKit, pos: Vector3, w: float, h: float, depth: float, yaw: float,
		p: BuildPalette) -> void:
	k.push_trs(pos, Vector3(0, yaw, 0))
	k.box(Vector3(0, h * 0.5, -depth * 0.5), Vector3(w, h, depth), Color("241d18"), Color("2b241d"))
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(s * (w * 0.5 + 0.08), h * 0.5, 0.04), Vector3(0.18, h + 0.12, 0.16), p.timber)
	k.box(Vector3(0, h + 0.1, 0.04), Vector3(w + 0.34, 0.2, 0.18), p.timber)
	k.pop()


# --- chimneys, banners, lights ---------------------------------------------------------------------

## Stone chimney with a capstone; returns the smoke outlet height.
static func chimney(k: MeshKit, pos: Vector3, height: float, p: BuildPalette, width: float = 0.42) -> float:
	masonry(k, pos + Vector3(0, height * 0.5, 0), Vector3(width, height, width), p, 3)
	k.box(pos + Vector3(0, height + 0.06, 0), Vector3(width + 0.22, 0.12, width + 0.22), p.stone_top)
	for s: float in [-1.0, 1.0]:
		k.box(pos + Vector3(s * width * 0.3, height + 0.2, 0), Vector3(width * 0.28, 0.16, width * 0.8),
			p.stone_dark)
	return pos.y + height + 0.28


## Banner: pole, crossbar, hanging cloth and a small gold crest.
static func banner(k: MeshKit, pos: Vector3, pole_h: float, cloth_w: float, cloth_h: float,
		yaw: float, p: BuildPalette, cloth_col: Color = Color(0, 0, 0, 0), crest_on: bool = true) -> void:
	var c := cloth_col if cloth_col.a > 0.0 else p.cloth
	k.push_trs(pos, Vector3(0, yaw, 0))
	k.cylinder(Vector3.ZERO, pole_h, 0.055, p.wood_dark, 6)
	k.sphere(Vector3(0, pole_h + 0.06, 0), 0.08, p.gold, 6, 3)
	k.box(Vector3(0, pole_h - 0.12, 0.06), Vector3(cloth_w + 0.14, 0.07, 0.07), p.wood_dark)
	var top := pole_h - 0.18
	k.plate(PackedVector2Array([
		Vector2(-cloth_w * 0.5, top), Vector2(cloth_w * 0.5, top),
		Vector2(cloth_w * 0.5, top - cloth_h), Vector2(0, top - cloth_h + cloth_h * 0.22),
		Vector2(-cloth_w * 0.5, top - cloth_h)]), 0.035, c, c.darkened(0.18))
	if crest_on:
		crest(k, Vector3(0, top - cloth_h * 0.42, 0.04), cloth_w * 0.5, 0.0, p.gold)
	k.pop()


## Wall-hung banner cloth (no pole), hanging from `pos` downward.
static func wall_banner(k: MeshKit, pos: Vector3, w: float, h: float, yaw: float, p: BuildPalette,
		cloth_col: Color = Color(0, 0, 0, 0)) -> void:
	var c := cloth_col if cloth_col.a > 0.0 else p.cloth
	k.push_trs(pos, Vector3(0, yaw, 0))
	k.box(Vector3(0, 0.04, 0.02), Vector3(w + 0.16, 0.08, 0.1), p.wood_dark)
	k.plate(PackedVector2Array([
		Vector2(-w * 0.5, 0), Vector2(w * 0.5, 0), Vector2(w * 0.5, -h),
		Vector2(0, -h + h * 0.16), Vector2(-w * 0.5, -h)]), 0.03, c, c.darkened(0.18))
	crest(k, Vector3(0, -h * 0.45, 0.035), w * 0.52, 0.0, p.gold)
	k.pop()


## Frontier crest: a winged gold lozenge, drawn on the local XY plane facing +Z.
static func crest(k: MeshKit, pos: Vector3, size: float, yaw: float, col: Color) -> void:
	k.push_trs(pos, Vector3(0, yaw, 0), Vector3(size, size, 1.0))
	k.plate(PackedVector2Array([Vector2(0, 0.62), Vector2(0.3, 0.0), Vector2(0, -0.62), Vector2(-0.3, 0.0)]),
		0.03, col)
	for s: float in [-1.0, 1.0]:
		k.plate(PackedVector2Array([
			Vector2(s * 0.24, 0.3), Vector2(s * 0.78, 0.5), Vector2(s * 0.68, 0.12),
			Vector2(s * 0.84, -0.16), Vector2(s * 0.3, -0.06)]), 0.025, col)
	k.pop()


## Lantern on a short bracket or a post (glowing).
static func lantern(k: MeshKit, pos: Vector3, p: BuildPalette, post_h: float = 0.0) -> void:
	if post_h > 0.0:
		k.cylinder(pos - Vector3(0, post_h, 0), post_h, 0.06, p.wood_dark, 6)
	k.box(pos + Vector3(0, 0.02, 0), Vector3(0.2, 0.24, 0.2), MeshKit.glow(p.glow, 0.9))
	k.box(pos + Vector3(0, 0.16, 0), Vector3(0.26, 0.05, 0.26), p.metal)
	k.cone(pos + Vector3(0, 0.18, 0), 0.14, 0.15, p.metal, 6)
	k.box(pos - Vector3(0, 0.14, 0), Vector3(0.24, 0.05, 0.24), p.metal)


# --- dressing props ----------------------------------------------------------------------------------

static func crate(k: MeshKit, pos: Vector3, s: float, p: BuildPalette, yaw: float = 0.0) -> void:
	k.push_trs(pos, Vector3(0, yaw, 0))
	k.box(Vector3(0, s * 0.5, 0), Vector3(s, s, s), p.wood, p.wood.lightened(0.12))
	for sz: float in [-1.0, 1.0]:
		k.box(Vector3(0, s * 0.5, sz * s * 0.5), Vector3(s * 0.9, s * 0.16, 0.03), p.wood_dark)
		k.box(Vector3(sz * s * 0.5, s * 0.5, 0), Vector3(0.03, s * 0.16, s * 0.9), p.wood_dark)
	k.pop()


static func barrel(k: MeshKit, pos: Vector3, r: float, h: float, p: BuildPalette) -> void:
	k.cylinder(pos, h, r * 0.86, p.wood, 8, p.wood.lightened(0.14))
	k.frustum(pos + Vector3(0, h * 0.18, 0), h * 0.64, r, r, p.wood, 8, false)
	k.frustum(pos + Vector3(0, h * 0.2, 0), 0.07, r + 0.02, r + 0.02, p.metal, 8, false)
	k.frustum(pos + Vector3(0, h * 0.7, 0), 0.07, r + 0.02, r + 0.02, p.metal, 8, false)


static func sack(k: MeshKit, pos: Vector3, s: float, p: BuildPalette) -> void:
	k.ellipsoid(pos + Vector3(0, s * 0.5, 0), Vector3(s * 0.5, s * 0.55, s * 0.45), p.plaster_dark, 7, 3)
	k.cylinder(pos + Vector3(0, s * 0.92, 0), s * 0.18, s * 0.16, p.plaster_dark, 6)
	k.torus(pos + Vector3(0, s * 0.92, 0), s * 0.18, 0.03, p.wood_dark, 6, 3)


## Window flower box with blossoms.
static func flower_box(k: MeshKit, pos: Vector3, w: float, yaw: float, p: BuildPalette) -> void:
	k.push_trs(pos, Vector3(0, yaw, 0))
	k.box(Vector3(0, 0, 0.1), Vector3(w, 0.16, 0.2), p.wood_dark, p.wood)
	for i in 3:
		var x := (float(i) - 1.0) * w * 0.3
		k.ellipsoid(Vector3(x, 0.1, 0.1), Vector3(0.09, 0.07, 0.08), Color("5e8b46"), 6, 3)
		k.sphere(Vector3(x, 0.17, 0.11), 0.055, [Color("d9604e"), Color("e8b34a"), Color("c07ad0")][i % 3], 5, 2)
	k.pop()


## Hanging signboard on a bracket.
static func signboard(k: MeshKit, pos: Vector3, yaw: float, p: BuildPalette) -> void:
	k.push_trs(pos, Vector3(0, yaw, 0))
	k.box(Vector3(0, 0, 0.14), Vector3(0.07, 0.07, 0.3), p.metal)
	k.box(Vector3(0, -0.06, 0.28), Vector3(0.06, 0.12, 0.06), p.metal)
	k.box(Vector3(0, -0.28, 0.28), Vector3(0.46, 0.34, 0.05), p.wood, p.wood.lightened(0.1))
	k.box(Vector3(0, -0.28, 0.31), Vector3(0.3, 0.06, 0.02), p.gold)
	k.pop()


## Stack of firewood / cut logs along X.
static func log_stack(k: MeshKit, pos: Vector3, p: BuildPalette, rows: int = 2) -> void:
	for r in rows:
		var n := 3 - r
		for i in n:
			var z := (float(i) - float(n - 1) * 0.5) * 0.24
			k.push_trs(pos + Vector3(0, 0.12 + float(r) * 0.22, z), Vector3(0, 0, 90))
			k.cylinder(Vector3(0, -0.3, 0), 0.6, 0.11, p.wood_dark, 6, p.wood.lightened(0.2))
			k.pop()


## Ladder between two points (rails + rungs).
static func ladder(k: MeshKit, foot: Vector3, top: Vector3, width: float, col: Color) -> void:
	var dir := top - foot
	var length := dir.length()
	if length < 0.2:
		return
	var side := dir.normalized().cross(Vector3.UP)
	if side.length_squared() < 0.001:
		side = Vector3.RIGHT
	side = side.normalized() * width * 0.5
	k.tube(foot + side, top + side, 0.05, col, 5)
	k.tube(foot - side, top - side, 0.05, col, 5)
	var rungs := maxi(2, int(length / 0.38))
	for i in rungs:
		var t := (float(i) + 0.5) / float(rungs)
		var c := foot.lerp(top, t)
		k.tube(c + side, c - side, 0.035, col, 4)


## Scaffolding cage used by the construction stages.
static func scaffold(k: MeshKit, size_x: float, size_z: float, height: float, p: BuildPalette) -> void:
	var hx := size_x * 0.5
	var hz := size_z * 0.5
	var pole := Color("9c7a4e")
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			k.cylinder(Vector3(sx * hx, 0, sz * hz), height, 0.06, pole, 5)
	for y: float in [height * 0.42, height * 0.86]:
		for sz: float in [-1.0, 1.0]:
			k.box(Vector3(0, y, sz * hz), Vector3(size_x, 0.08, 0.08), pole)
		for sx: float in [-1.0, 1.0]:
			k.box(Vector3(sx * hx, y, 0), Vector3(0.08, 0.08, size_z), pole)
	k.box(Vector3(0, height * 0.46, hz), Vector3(size_x * 0.92, 0.07, 0.42), p.wood)
	k.box(Vector3(hx, height * 0.46, 0), Vector3(0.42, 0.07, size_z * 0.92), p.wood)
	ladder(k, Vector3(hx * 0.55, 0, hz + 0.18), Vector3(hx * 0.55, height * 0.46, hz - 0.1), 0.36, p.wood_dark)


## Ring of sharpened stakes (outpost/bandit palisades). `gap_front` leaves a gate on +Z.
static func stake_ring(k: MeshKit, rx: float, rz: float, height: float, p: BuildPalette,
		count: int = 16, gap_front: bool = true, sharp: bool = true) -> void:
	for i in count:
		var a := TAU * float(i) / float(count)
		var dz := cos(a)
		if gap_front and sin(a) > -0.28 and sin(a) < 0.28 and dz > 0.0:
			continue
		var x := sin(a) * rx
		var z := dz * rz
		var h := height * (0.86 + 0.14 * RngUtil.hash01(i, 5, 9))
		k.cylinder(Vector3(x, 0, z), h, 0.09, p.wood, 5, p.wood.lightened(0.1))
		if sharp:
			k.cone(Vector3(x, h, z), 0.26, 0.09, p.wood_dark, 5)
	k.torus(Vector3(0, height * 0.6, 0), (rx + rz) * 0.5, 0.035, p.wood_dark, 12, 3)


## Straight fence/rail run along X.
static func rail_run(k: MeshKit, x0: float, x1: float, z: float, height: float, p: BuildPalette) -> void:
	var n := maxi(2, int(absf(x1 - x0) / 1.0) + 1)
	for i in n:
		var x: float = lerpf(x0, x1, float(i) / float(n - 1))
		k.cylinder(Vector3(x, 0, z), height, 0.06, p.wood, 5)
	for y: float in [height * 0.42, height * 0.8]:
		k.box(Vector3((x0 + x1) * 0.5, y, z), Vector3(absf(x1 - x0), 0.08, 0.07), p.wood_dark)


## Striped awning sloping down toward +Z (market stalls and halls).
static func awning(k: MeshKit, pos: Vector3, w: float, depth: float, drop: float,
		p: BuildPalette) -> void:
	var ang := rad_to_deg(atan2(drop, depth))
	k.push_trs(pos, Vector3(ang, 0, 0))
	var n := maxi(4, int(w / 0.42))
	for i in n:
		var t := (float(i) + 0.5) / float(n) - 0.5
		k.box(Vector3(t * w, 0, depth * 0.5), Vector3(w / float(n), 0.06, depth),
			p.cloth if i % 2 == 0 else p.cloth_alt)
	k.box(Vector3(0, 0.02, depth), Vector3(w + 0.06, 0.1, 0.08), p.wood_dark)
	k.pop()


## Square pillar / post helper.
static func post(k: MeshKit, x: float, z: float, y0: float, y1: float, r: float, col: Color) -> void:
	k.box(Vector3(x, (y0 + y1) * 0.5, z), Vector3(r * 2.0, y1 - y0, r * 2.0), col)


## Campfire: stone ring, logs and a glowing flame.
static func campfire(k: MeshKit, pos: Vector3, radius: float, p: BuildPalette, lit: bool = true) -> void:
	for i in 8:
		var a := TAU * float(i) / 8.0 + 0.2
		k.box(pos + Vector3(cos(a) * radius, 0.09, sin(a) * radius),
			Vector3(radius * 0.7, 0.2, radius * 0.55), p.stone, p.stone_top)
	k.box(pos + Vector3(0, 0.03, 0), Vector3(radius * 1.5, 0.06, radius * 1.5), Color("2a231d"))
	for i in 3:
		var a := TAU * float(i) / 3.0
		k.tube(pos + Vector3(cos(a) * radius * 0.72, 0.05, sin(a) * radius * 0.72),
			pos + Vector3(-cos(a) * radius * 0.16, radius * 1.15, -sin(a) * radius * 0.16),
			0.075, p.wood_dark, 5)
	if lit:
		k.cone(pos + Vector3(0, 0.08, 0), radius * 1.9, radius * 0.72, MeshKit.glow(Color("ff9a3c"), 0.9), 6)
		k.cone(pos + Vector3(0, 0.16, 0), radius * 1.1, radius * 0.4, MeshKit.glow(Color("ffe08a"), 1.0), 5)


## Glowing furnace mouth on a wall face.
static func furnace_mouth(k: MeshKit, pos: Vector3, w: float, h: float, yaw: float,
		p: BuildPalette) -> void:
	k.push_trs(pos, Vector3(0, yaw, 0))
	k.box(Vector3(0, h * 0.5, -0.04), Vector3(w + 0.22, h + 0.2, 0.14), p.stone_dark)
	k.box(Vector3(0, h * 0.5, 0.02), Vector3(w, h, 0.06), MeshKit.glow(Color("ff7a28"), 0.95))
	k.box(Vector3(0, h * 0.12, 0.06), Vector3(w * 0.9, h * 0.22, 0.06), MeshKit.glow(Color("ffd06a"), 1.0))
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(s * (w * 0.5 + 0.13), h * 0.5, 0.05), Vector3(0.1, h + 0.14, 0.1), p.metal)
	k.pop()


## Riveted metal pipe run with elbow, from `a` to `b` then up by `rise`.
static func pipe(k: MeshKit, a: Vector3, b: Vector3, radius: float, p: BuildPalette) -> void:
	k.tube(a, b, radius, p.metal, 6)
	k.tube(a, a.lerp(b, 0.12), radius + 0.03, p.metal.darkened(0.2), 6)
	k.tube(b.lerp(a, 0.12), b, radius + 0.03, p.metal.darkened(0.2), 6)


## Cog wheel standing upright, its face toward +Z (rotated by `yaw`) — workshop/machine dressing.
static func gear(k: MeshKit, pos: Vector3, radius: float, teeth: int, col: Color,
		yaw: float = 0.0) -> void:
	var thick := radius * 0.28
	k.push_trs(pos, Vector3(90, yaw, 0))  # local +Y -> world +Z
	k.cylinder(Vector3(0, -thick * 0.5, 0), thick, radius, col, 10, col.lightened(0.08))
	k.cylinder(Vector3(0, -thick, 0), thick * 2.0, radius * 0.22, col.darkened(0.25), 6)
	for i in 4:
		var sa := PI * float(i) / 4.0
		k.push_trs(Vector3(0, 0, 0), Vector3(0, rad_to_deg(sa), 0))
		k.box(Vector3(0, 0.01, 0), Vector3(radius * 1.5, thick * 0.55, radius * 0.22), col.darkened(0.12))
		k.pop()
	for i in teeth:
		var a := TAU * float(i) / float(teeth)
		k.push_trs(Vector3(cos(a) * radius, -thick * 0.5, sin(a) * radius), Vector3(0, rad_to_deg(-a), 0))
		k.box(Vector3.ZERO, Vector3(radius * 0.3, thick, radius * 0.26), col.lightened(0.08))
		k.pop()
	k.pop()
