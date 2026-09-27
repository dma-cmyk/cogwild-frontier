class_name BldVillage
extends RefCounted
## Procedural geometry for race village buildings (`v_<race>_home` 3x3, `v_<race>_hall` 5x5).
## The shape comes from the race's `build_style` in data/villages and the colours from its
## `colors` block, so a new race only needs a JSON row to get a distinct-looking village.
## Painted cards replace these meshes wherever `data/art/buildings` has a `v_<race>_*` entry.

const STYLES := ["gable", "round", "stone", "tent", "pagoda", "stilt", "reed"]

static var _palettes: Dictionary = {}


## "v_oni_hall" -> "oni"; "" when the id is not a village building.
static func race_of(id: String) -> String:
	if not id.begins_with("v_"):
		return ""
	if id.ends_with("_home"):
		return id.substr(2, id.length() - 7)
	if id.ends_with("_hall"):
		return id.substr(2, id.length() - 7)
	return ""


static func style_of(race: String) -> String:
	var style := str(DB.get_def("villages", race).get("build_style", "gable"))
	return style if style in STYLES else "gable"


## Race-tinted palette: the neutral outland set recoloured from data/villages `colors`.
static func palette(race: String) -> BuildPalette:
	if _palettes.has(race):
		return _palettes[race] as BuildPalette
	var p := BuildPalette.of("neutral")
	var colors: Dictionary = DB.get_def("villages", race).get("colors", {})
	if colors.has("wall"):
		p.plaster = Color(str(colors["wall"]))
		p.plaster_dark = p.plaster.darkened(0.22)
		p.stone = p.plaster.darkened(0.30)
		p.stone_top = p.stone.lightened(0.10)
		p.stone_dark = p.stone.darkened(0.18)
	if colors.has("roof"):
		p.roof = Color(str(colors["roof"]))
		p.roof_dark = p.roof.darkened(0.26)
	if colors.has("timber"):
		p.timber = Color(str(colors["timber"]))
		p.wood = p.timber.lightened(0.24)
		p.wood_dark = p.wood.darkened(0.28)
	if colors.has("cloth"):
		p.cloth = Color(str(colors["cloth"]))
		p.cloth_alt = p.plaster
	_palettes[race] = p
	return p


## Returns true when `id` was handled.
static func build(k: MeshKit, id: String, p: BuildPalette, seed: int, _lv: int) -> bool:
	var race := race_of(id)
	if race == "":
		return false
	var style := style_of(race)
	if id.ends_with("_hall"):
		_hall(k, p, style, seed)
	else:
		_home(k, p, style, seed)
	return true


# --- 3x3 homes ---------------------------------------------------------------------------------

static func _home(k: MeshKit, p: BuildPalette, style: String, seed: int) -> void:
	match style:
		"round":
			_round_hut(k, p, 1.24, 1.9, 1.15, seed)
		"stone":
			_stone_house(k, p, 2.3, 2.1, 1.75, seed)
		"tent":
			_cloth_pavilion(k, p, 2.5, 2.4, 1.6, 1.0, seed)
		"pagoda":
			_pagoda(k, p, 2.3, 2.1, 1.85, 1, seed)
		"stilt":
			_stilt_hut(k, p, 2.0, 1.9, 1.35, 1.25, seed)
		"reed":
			_reed_house(k, p, 2.4, 2.1, 1.6, seed)
		_:
			_framed_house(k, p, 2.4, 2.2, 1.9, seed)


# --- 5x5 halls ---------------------------------------------------------------------------------

static func _hall(k: MeshKit, p: BuildPalette, style: String, seed: int) -> void:
	match style:
		"round":
			_round_hut(k, p, 2.05, 2.5, 1.85, seed)
			BuildParts.banner(k, Vector3(1.55, 0, 1.55), 3.1, 0.5, 1.0, 0.0, p)
		"stone":
			_stone_house(k, p, 4.0, 3.6, 2.5, seed)
			BuildParts.banner(k, Vector3(-1.75, 0, 2.05), 3.3, 0.5, 1.1, 0.0, p)
		"tent":
			_cloth_pavilion(k, p, 4.2, 4.0, 2.4, 1.5, seed)
		"pagoda":
			_pagoda(k, p, 4.0, 3.6, 2.4, 2, seed)
		"stilt":
			_stilt_hut(k, p, 3.4, 3.2, 2.0, 1.7, seed)
		"reed":
			_reed_house(k, p, 4.0, 3.6, 2.2, seed)
			BuildParts.banner(k, Vector3(1.8, 0, 1.9), 3.0, 0.46, 1.0, 0.0, p)
		_:
			_framed_house(k, p, 4.0, 3.6, 2.5, seed)
			BuildParts.banner(k, Vector3(-1.72, 0, 2.0), 3.4, 0.52, 1.1, 0.0, p)
	_hall_dressing(k, p, seed)


## Shared hall dressing: market crates, a sign and two lanterns by the entrance.
static func _hall_dressing(k: MeshKit, p: BuildPalette, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7919 + 13
	BuildParts.crate(k, Vector3(1.55, 0, 2.05), 0.44, p, rng.randf_range(-20.0, 20.0))
	BuildParts.barrel(k, Vector3(-1.45, 0, 2.12), 0.25, 0.58, p)
	BuildParts.sack(k, Vector3(1.05, 0, 2.15), 0.3, p)
	BuildParts.lantern(k, Vector3(-0.95, 1.9, 1.68), p)
	BuildParts.lantern(k, Vector3(0.95, 1.9, 1.68), p)


# --- shape builders ----------------------------------------------------------------------------

## Timber-framed cottage with a gable roof (human, and the default for unknown styles).
static func _framed_house(k: MeshKit, p: BuildPalette, sx: float, sz: float, wall_h: float,
		seed: int) -> void:
	var plinth := 0.26
	BuildParts.stone_base(k, sx, sz, plinth, p)
	BuildParts.framed_walls(k, Vector3(sx - 0.1, wall_h, sz - 0.1), plinth, p)
	var eave := plinth + wall_h
	var ridge := sx * 0.36
	BuildParts.gable_roof(k, Vector3(0, eave, 0), sx - 0.1, sz - 0.1, ridge, 0.28, p)
	for s: float in [-1.0, 1.0]:
		BuildParts.gable_end(k, s * (sx * 0.5 - 0.05), sz - 0.1, eave, ridge, 0.1, p.plaster, p.timber)
	BuildParts.door(k, Vector3(-sx * 0.16, plinth, sz * 0.5 - 0.02), 0.78, 1.32, 0.0, p)
	BuildParts.window(k, Vector3(sx * 0.26, plinth + wall_h * 0.58, sz * 0.5 - 0.02), 0.5, 0.52, 0.0, p)
	BuildParts.window(k, Vector3(-sx * 0.5 + 0.03, plinth + wall_h * 0.58, 0), 0.46, 0.5, -90.0, p)
	var chimney_x := (sx * 0.5 - 0.42) * (1.0 if absi(seed) % 2 == 0 else -1.0)
	BuildParts.chimney(k, Vector3(chimney_x, eave - 0.2, -sz * 0.24), ridge + 0.75, p, 0.36)
	BuildParts.flower_box(k, Vector3(sx * 0.26, plinth + wall_h * 0.32, sz * 0.5 + 0.06), 0.56, 0.0, p)


## Round drum of planks under a conical thatch cone (sylvan).
static func _round_hut(k: MeshKit, p: BuildPalette, radius: float, wall_h: float, roof_h: float,
		seed: int) -> void:
	var sides := 10
	k.cylinder(Vector3(0, 0, 0), 0.22, radius + 0.14, p.stone, sides)
	k.cylinder(Vector3(0, 0.22, 0), wall_h, radius, p.plaster, sides)
	for i in sides:
		var a := TAU * float(i) / float(sides)
		BuildParts.post(k, cos(a) * radius, sin(a) * radius, 0.22, 0.22 + wall_h, 0.075, p.timber)
	k.cylinder(Vector3(0, 0.22 + wall_h - 0.1, 0), 0.16, radius + 0.1, p.timber, sides)
	BuildParts.cone_roof(k, Vector3(0, 0.22 + wall_h, 0), radius + 0.16, roof_h, p)
	k.cylinder(Vector3(0, 0.22 + wall_h + roof_h, 0), 0.3, 0.05, p.wood_dark, 5)
	BuildParts.door(k, Vector3(0, 0.22, radius - 0.02), 0.72, 1.24, 0.0, p, false)
	for s: float in [-1.0, 1.0]:
		var a := 1.1 * s
		BuildParts.round_window(k, Vector3(sin(a) * (radius - 0.02), 0.22 + wall_h * 0.62, cos(a) * (radius - 0.02)),
			0.19, rad_to_deg(a), p)
	if absi(seed) % 2 == 0:
		BuildParts.lantern(k, Vector3(radius * 0.72, 0.22 + wall_h * 0.9, radius * 0.72), p)


## Dry-stone walls with a heavy turf-coloured hip roof (stoutkin, minotaur).
static func _stone_house(k: MeshKit, p: BuildPalette, sx: float, sz: float, wall_h: float,
		seed: int) -> void:
	BuildParts.masonry(k, Vector3(0, wall_h * 0.5, 0), Vector3(sx, wall_h, sz), p, 4)
	for s: float in [-1.0, 1.0]:
		BuildParts.post(k, s * (sx * 0.5 - 0.1), sz * 0.5 - 0.1, 0.0, wall_h + 0.24, 0.13, p.stone_dark)
		BuildParts.post(k, s * (sx * 0.5 - 0.1), -sz * 0.5 + 0.1, 0.0, wall_h + 0.18, 0.13, p.stone_dark)
	BuildParts.hip_roof(k, Vector3(0, wall_h, 0), sx - 0.2, sz - 0.2, sx * 0.34, 0.26, p, false)
	k.box(Vector3(0, wall_h + 0.2, sz * 0.5 + 0.16), Vector3(sx * 0.55, 0.26, 0.3), p.timber)
	BuildParts.opening(k, Vector3(0, 0, sz * 0.5 - 0.02), 0.82, 1.35, 0.3, 0.0, p)
	BuildParts.window(k, Vector3(sx * 0.3, wall_h * 0.62, sz * 0.5 - 0.02), 0.4, 0.4, 0.0, p)
	BuildParts.window(k, Vector3(-sx * 0.3, wall_h * 0.62, sz * 0.5 - 0.02), 0.4, 0.4, 0.0, p)
	BuildParts.chimney(k, Vector3(sx * 0.28 * (1.0 if absi(seed) % 2 == 0 else -1.0), wall_h - 0.1, -sz * 0.2),
		sx * 0.34 + 0.7, p, 0.4)


## Open-sided cloth pavilion on poles (vulpin, centaur).
static func _cloth_pavilion(k: MeshKit, p: BuildPalette, sx: float, sz: float, post_h: float,
		roof_h: float, seed: int) -> void:
	k.box(Vector3(0, 0.05, 0), Vector3(sx + 0.16, 0.1, sz + 0.16), p.stone, p.stone_top)
	for sxx: float in [-1.0, 1.0]:
		for szz: float in [-1.0, 1.0]:
			k.cylinder(Vector3(sxx * sx * 0.5, 0.1, szz * sz * 0.5), post_h, 0.085, p.timber, 6)
	k.box(Vector3(0, 0.1 + post_h, 0), Vector3(sx + 0.2, 0.12, 0.12), p.wood_dark)
	k.box(Vector3(0, 0.1 + post_h, 0), Vector3(0.12, 0.12, sz + 0.2), p.wood_dark)
	k.pyramid(Vector3(0, 0.1 + post_h + 0.06, 0), Vector2(sx + 0.44, sz + 0.44), roof_h, p.cloth)
	k.pyramid(Vector3(0, 0.1 + post_h + 0.06 + roof_h * 0.46, 0),
		Vector2((sx + 0.44) * 0.54, (sz + 0.44) * 0.54), roof_h * 0.04, p.cloth_alt)
	k.cylinder(Vector3(0, 0.1 + post_h + roof_h, 0), 0.34, 0.05, p.wood_dark, 5)
	# back and side screens keep the inside readable; the front stays open
	k.box(Vector3(0, 0.1 + post_h * 0.5, -sz * 0.5), Vector3(sx, post_h, 0.09), p.plaster, p.plaster_dark)
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(s * sx * 0.5, 0.1 + post_h * 0.52, -sz * 0.16), Vector3(0.09, post_h * 0.84, sz * 0.6),
			p.cloth_alt, p.cloth_alt.darkened(0.12))
	k.box(Vector3(0, 0.36, 0), Vector3(sx * 0.6, 0.1, sz * 0.42), p.wood)
	for i in 3:
		k.sphere(Vector3((float(i) - 1.0) * sx * 0.18, 0.47, 0), 0.1,
			[p.gold, p.cloth, p.roof][i], 6, 3)
	BuildParts.banner(k, Vector3(sx * 0.5, 0.1, sz * 0.5), post_h + roof_h * 0.7, 0.36, 0.8, 0.0, p)
	if absi(seed) % 2 == 0:
		BuildParts.lantern(k, Vector3(-sx * 0.5, 0.1 + post_h - 0.12, sz * 0.5), p)


## Tiered eaves on dark posts (oni, tengu). `tiers` = 1 for homes, 2 for halls.
static func _pagoda(k: MeshKit, p: BuildPalette, sx: float, sz: float, wall_h: float, tiers: int,
		seed: int) -> void:
	var plinth := 0.3
	BuildParts.stone_base(k, sx + 0.3, sz + 0.3, plinth, p)
	BuildParts.plank_wall(k, Vector3(sx, wall_h, sz), plinth, p, seed, 0.03)
	for sxx: float in [-1.0, 1.0]:
		for szz: float in [-1.0, 1.0]:
			BuildParts.post(k, sxx * sx * 0.5, szz * sz * 0.5, plinth, plinth + wall_h + 0.1, 0.1, p.timber)
	var y := plinth + wall_h
	var span_x := sx
	var span_z := sz
	for tier in tiers:
		k.box(Vector3(0, y + 0.08, 0), Vector3(span_x + 0.5, 0.16, span_z + 0.5), p.timber)
		k.pyramid(Vector3(0, y + 0.16, 0), Vector2(span_x + 0.56, span_z + 0.56), span_x * 0.3, p.roof)
		# upturned corner tips
		for sxx: float in [-1.0, 1.0]:
			for szz: float in [-1.0, 1.0]:
				k.box(Vector3(sxx * (span_x + 0.5) * 0.5, y + 0.3, szz * (span_z + 0.5) * 0.5),
					Vector3(0.24, 0.1, 0.24), p.roof_dark)
		y += span_x * 0.3 + 0.16
		span_x *= 0.62
		span_z *= 0.62
		if tier < tiers - 1:
			k.box(Vector3(0, y + wall_h * 0.22, 0), Vector3(span_x, wall_h * 0.44, span_z), p.plaster)
			for sxx: float in [-1.0, 1.0]:
				BuildParts.round_window(k, Vector3(sxx * span_x * 0.3, y + wall_h * 0.24, span_z * 0.5), 0.14, 0.0, p)
			y += wall_h * 0.44
	k.cylinder(Vector3(0, y - 0.1, 0), 0.34, 0.06, p.gold, 6)
	BuildParts.door(k, Vector3(0, plinth, sz * 0.5 + 0.01), 0.8, 1.3, 0.0, p, false)
	BuildParts.window(k, Vector3(sx * 0.31, plinth + wall_h * 0.6, sz * 0.5 + 0.01), 0.42, 0.46, 0.0, p)
	BuildParts.window(k, Vector3(-sx * 0.31, plinth + wall_h * 0.6, sz * 0.5 + 0.01), 0.42, 0.46, 0.0, p)
	BuildParts.lantern(k, Vector3(sx * 0.5 - 0.1, plinth + wall_h - 0.1, sz * 0.5 - 0.1), p)


## Nest-house lifted on stilts with a ladder (harpy).
static func _stilt_hut(k: MeshKit, p: BuildPalette, sx: float, sz: float, wall_h: float,
		lift: float, seed: int) -> void:
	for sxx: float in [-1.0, 1.0]:
		for szz: float in [-1.0, 1.0]:
			k.cylinder(Vector3(sxx * (sx * 0.5 - 0.16), 0, szz * (sz * 0.5 - 0.16)), lift + 0.1, 0.1, p.timber, 6)
	k.box(Vector3(0, lift + 0.08, 0), Vector3(sx + 0.3, 0.16, sz + 0.3), p.wood, p.wood.lightened(0.1))
	BuildParts.plank_wall(k, Vector3(sx - 0.2, wall_h, sz - 0.2), lift + 0.16, p, seed, 0.04)
	BuildParts.hip_roof(k, Vector3(0, lift + 0.16 + wall_h, 0), sx - 0.2, sz - 0.2, sx * 0.4, 0.3, p, false)
	# a woven nest rim of sticks around the deck
	var sticks := 12
	for i in sticks:
		var a := TAU * float(i) / float(sticks)
		var r := Vector2(sx * 0.5 + 0.1, sz * 0.5 + 0.1)
		k.box(Vector3(cos(a) * r.x, lift + 0.26, sin(a) * r.y), Vector3(0.28, 0.14, 0.12),
			p.wood_dark, p.wood_dark.lightened(0.1))
	BuildParts.opening(k, Vector3(0, lift + 0.16, sz * 0.5 - 0.12), 0.68, 1.1, 0.24, 0.0, p)
	BuildParts.ladder(k, Vector3(0.3, 0, sz * 0.5 + 0.28), Vector3(0.3, lift + 0.2, sz * 0.5 - 0.06), 0.42, p.wood_dark)
	BuildParts.round_window(k, Vector3(-sx * 0.5 + 0.12, lift + 0.16 + wall_h * 0.6, 0), 0.17, -90.0, p)
	if absi(seed) % 2 == 0:
		BuildParts.banner(k, Vector3(sx * 0.5 - 0.08, 0, -sz * 0.5 + 0.08), lift + wall_h + 1.0, 0.34, 0.7, 0.0, p)


## Bundled-reed walls with a fringed low roof, on a slight water plinth (lamia).
static func _reed_house(k: MeshKit, p: BuildPalette, sx: float, sz: float, wall_h: float,
		seed: int) -> void:
	k.box(Vector3(0, 0.09, 0), Vector3(sx + 0.36, 0.18, sz + 0.36), p.stone, p.stone_top)
	var bundles := maxi(5, int(sx / 0.34))
	for i in bundles:
		var t := (float(i) + 0.5) / float(bundles) - 0.5
		for szz: float in [-1.0, 1.0]:
			k.cylinder(Vector3(t * sx, 0.18, szz * sz * 0.5), wall_h, 0.15, p.plaster if i % 2 == 0 else p.plaster_dark, 6)
	var bz := maxi(4, int(sz / 0.34))
	for i in bz:
		var t := (float(i) + 0.5) / float(bz) - 0.5
		for sxx: float in [-1.0, 1.0]:
			k.cylinder(Vector3(sxx * sx * 0.5, 0.18, t * sz), wall_h, 0.15, p.plaster if i % 2 == 1 else p.plaster_dark, 6)
	var eave := 0.18 + wall_h
	k.box(Vector3(0, eave + 0.07, 0), Vector3(sx + 0.42, 0.14, sz + 0.42), p.timber)
	BuildParts.hip_roof(k, Vector3(0, eave + 0.14, 0), sx, sz, sx * 0.28, 0.24, p, false)
	# reed fringe hanging from the eaves
	var fringe := maxi(6, int(sx / 0.3))
	for i in fringe:
		var t := (float(i) + 0.5) / float(fringe) - 0.5
		k.box(Vector3(t * (sx + 0.3), eave - 0.08, sz * 0.5 + 0.22), Vector3(0.12, 0.3, 0.06), p.roof_dark)
	BuildParts.opening(k, Vector3(0, 0.18, sz * 0.5 + 0.02), 0.78, 1.22, 0.26, 0.0, p)
	BuildParts.round_window(k, Vector3(sx * 0.3, 0.18 + wall_h * 0.62, sz * 0.5 + 0.04), 0.18, 0.0, p)
	BuildParts.round_window(k, Vector3(-sx * 0.3, 0.18 + wall_h * 0.62, sz * 0.5 + 0.04), 0.18, 0.0, p)
	if absi(seed) % 2 == 0:
		BuildParts.lantern(k, Vector3(0, eave + 0.05, sz * 0.5 + 0.2), p)
