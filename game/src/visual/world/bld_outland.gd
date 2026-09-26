class_name BldOutland
extends RefCounted
## Geometry for the non-player buildings: bandit camp, ancient machines, trader posts, wanderer
## camp, ruins and the airship wreck. Same conventions as BldFrontier (origin = footprint centre,
## front = +Z).

## Returns true when `id` was handled.
static func build(k: MeshKit, id: String, p: BuildPalette, seed: int, _lv: int) -> bool:
	match id:
		"bandit_tent": bandit_tent(k, p, seed)
		"bandit_hut": bandit_hut(k, p, seed)
		"bandit_tower": bandit_tower(k, p, seed)
		"machine_spire": machine_spire(k, p, seed)
		"machine_block": machine_block(k, p, seed)
		"machine_foundry": machine_foundry(k, p, seed)
		"trade_hall": trade_hall(k, p, seed)
		"trade_stall": trade_stall(k, p, seed)
		"trade_mast": trade_mast(k, p, seed)
		"wanderer_tent": wanderer_tent(k, p, seed)
		"ruin_arch": ruin_arch(k, p, seed)
		"ruin_pillar": ruin_pillar(k, p, seed)
		"ruin_wall": ruin_wall(k, p, seed)
		"ruin_statue": ruin_statue(k, p, seed)
		"ruin_vault": ruin_vault(k, p, seed)
		"wreck_airship": wreck_airship(k, p, seed)
		_: return false
	return true


# --- bandit camp ------------------------------------------------------------------------------

## 2x2 patched ridge tent with crooked poles and guy ropes.
static func bandit_tent(k: MeshKit, p: BuildPalette, _seed: int) -> void:
	var patch: Array[Color] = [p.cloth, p.cloth.darkened(0.2), p.plaster, p.cloth_alt.darkened(0.1)]
	k.box(Vector3(0, 0.03, 0), Vector3(1.9, 0.06, 1.9), Color("6b5f4a"))
	for s: float in [-1.0, 1.0]:
		k.tube(Vector3(s * 0.72, 0, 0.04 * s), Vector3(s * 0.66, 1.42, 0), 0.06, p.wood, 5)
	k.tube(Vector3(-0.78, 1.4, 0), Vector3(0.78, 1.45, 0), 0.05, p.wood_dark, 5)
	# two sloped cloth faces made of patches
	for s: float in [-1.0, 1.0]:
		for i in 4:
			var x := (float(i) - 1.5) * 0.42
			k.push_trs(Vector3(x, 1.42, s * 0.42), Vector3(s * 38.0, 0, 0))
			k.box(Vector3(0, -0.04, 0), Vector3(0.42, 0.07, 1.1),
				patch[(i + int(s > 0.0)) % patch.size()])
			k.pop()
	# gable cloth ends and a flap door on +Z
	for s: float in [-1.0, 1.0]:
		k.push_trs(Vector3(s * 0.82, 0, 0), Vector3(0, 90, 0))
		k.plate(PackedVector2Array([Vector2(-0.78, 0), Vector2(0.78, 0), Vector2(0, 1.42)]), 0.04,
			p.cloth.darkened(0.12))
		k.pop()
	k.push_trs(Vector3(0.3, 0, 0.78), Vector3(0, 0, 0))
	k.plate(PackedVector2Array([Vector2(-0.34, 0), Vector2(0.3, 0.1), Vector2(0.16, 1.0), Vector2(-0.3, 0.88)]),
		0.035, p.cloth_alt)
	k.pop()
	# guy ropes and pegs
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			k.tube(Vector3(sx * 0.7, 1.4, 0), Vector3(sx * 1.05, 0.06, sz * 0.95), 0.018, p.wood_dark, 4)
			k.box(Vector3(sx * 1.05, 0.08, sz * 0.95), Vector3(0.07, 0.16, 0.07), p.wood_dark)
	k.push_trs(Vector3(0, 1.45, 0))
	k.plate(PackedVector2Array([Vector2(0, 0), Vector2(0.5, -0.1), Vector2(0, -0.26)]), 0.03, p.cloth)
	k.pop()
	BuildParts.crate(k, Vector3(-0.85, 0, 0.75), 0.4, p, 22.0)


## 3x3 ramshackle hut: mismatched planks, sagging scrap roof, red awning.
static func bandit_hut(k: MeshKit, p: BuildPalette, seed: int) -> void:
	k.box(Vector3(0, 0.12, 0), Vector3(2.7, 0.24, 2.7), Color("6b5f4a"), Color("7b6c53"))
	BuildParts.plank_wall(k, Vector3(2.4, 1.8, 2.3), 0.24, p, seed, 0.12)
	var eave := 2.04
	# two mismatched roof slabs at different pitches
	for s: float in [1.0, -1.0]:
		var pitch := 30.0 if s > 0.0 else 22.0
		k.push_trs(Vector3(0, eave, 0), Vector3(s * pitch, 0, 0))
		k.box(Vector3(0, -0.06, s * 0.82), Vector3(2.7, 0.12, 1.7), p.roof, p.roof.lightened(0.06))
		for i in 3:
			k.box(Vector3((float(i) - 1.0) * 0.86, 0.03, s * 0.8), Vector3(0.72, 0.05, 1.5),
				p.roof.darkened(0.12) if i % 2 == 0 else p.metal.darkened(0.1))
		k.pop()
	k.box(Vector3(0, eave + 0.44, 0), Vector3(2.5, 0.14, 0.24), p.wood_dark)
	for s: float in [-1.0, 1.0]:
		BuildParts.gable_end(k, s * 1.2, 2.3, eave, 0.62, 0.1, p.wood_dark, p.timber)
	# leaning corner props
	for sx: float in [-1.0, 1.0]:
		k.tube(Vector3(sx * 1.45, 0, 1.05), Vector3(sx * 1.2, 1.9, 1.15), 0.07, p.wood_dark, 5)
	# door with a red awning
	k.box(Vector3(-0.3, 0.24, 1.18), Vector3(0.7, 1.35, 0.1), p.wood_dark)
	k.box(Vector3(-0.3, 0.9, 1.22), Vector3(0.6, 1.2, 0.05), p.wood)
	k.push_trs(Vector3(-0.3, 1.75, 1.2), Vector3(18.0, 0, 0))
	k.box(Vector3(0, 0, 0.3), Vector3(1.1, 0.06, 0.62), p.cloth)
	k.box(Vector3(0, 0.02, 0.3), Vector3(0.3, 0.05, 0.62), p.cloth_alt)
	k.pop()
	for s: float in [-1.0, 1.0]:
		k.tube(Vector3(-0.3 + s * 0.5, 0, 1.5), Vector3(-0.3 + s * 0.5, 1.68, 1.5), 0.045, p.wood_dark, 4)
	BuildParts.window(k, Vector3(0.75, 1.15, 1.16), 0.42, 0.42, 0.0, p)
	# scrap metal chimney
	k.cylinder(Vector3(0.95, 1.6, -0.6), 1.5, 0.14, p.metal, 6)
	k.frustum(Vector3(0.95, 3.0, -0.6), 0.22, 0.22, 0.16, p.metal.darkened(0.2), 6, false)
	k.torus(Vector3(0.95, 2.3, -0.6), 0.17, 0.03, p.metal.darkened(0.3), 6, 3)
	BuildParts.barrel(k, Vector3(1.1, 0, 0.9), 0.26, 0.6, p)
	BuildParts.crate(k, Vector3(-1.15, 0, 0.7), 0.44, p, -16.0)
	BuildParts.banner(k, Vector3(1.25, 0, 1.25), 2.1, 0.44, 0.9, 0.0, p, p.cloth, false)
	BuildParts.campfire(k, Vector3(0.25, 0, 1.32), 0.26, p)


## 2x2 crooked lookout tower with a red banner and a torch.
static func bandit_tower(k: MeshKit, p: BuildPalette, seed: int) -> void:
	k.box(Vector3(0, 0.1, 0), Vector3(1.8, 0.2, 1.8), Color("6b5f4a"))
	var deck := 3.1
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var lean := 0.12 * RngUtil.hash01(seed, int(sx), int(sz))
			k.tube(Vector3(sx * 0.78, 0.1, sz * 0.78),
				Vector3(sx * (0.62 + lean), deck, sz * (0.62 + lean)), 0.1, p.wood, 6)
	for y: float in [1.1, 2.2]:
		for s: float in [-1.0, 1.0]:
			k.box(Vector3(0, y, s * 0.72), Vector3(1.5, 0.1, 0.09), p.wood_dark)
			k.box(Vector3(s * 0.72, y, 0), Vector3(0.09, 0.1, 1.5), p.wood_dark)
	for s: float in [-1.0, 1.0]:
		k.tube(Vector3(-0.74, 1.1, s * 0.74), Vector3(0.7, 2.2, s * 0.7), 0.05, p.wood_dark, 4)
	k.box(Vector3(0, deck + 0.08, 0), Vector3(1.66, 0.16, 1.66), p.wood, p.wood.lightened(0.12))
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(0, deck + 0.42, s * 0.78), Vector3(1.66, 0.5, 0.09), p.wood_dark)
		k.box(Vector3(s * 0.78, deck + 0.42, 0), Vector3(0.09, 0.5, 1.66), p.wood_dark)
	# scrap roof on two posts
	for sx: float in [-1.0, 1.0]:
		k.box(Vector3(sx * 0.66, deck + 0.75, -0.66), Vector3(0.1, 1.0, 0.1), p.wood_dark)
	k.push_trs(Vector3(0, deck + 1.3, 0), Vector3(16.0, 0, 0))
	k.box(Vector3.ZERO, Vector3(1.8, 0.1, 1.7), p.metal.darkened(0.1))
	for i in 3:
		k.box(Vector3((float(i) - 1.0) * 0.58, 0.05, 0), Vector3(0.5, 0.05, 1.7), p.roof.darkened(0.1))
	k.pop()
	BuildParts.ladder(k, Vector3(0, 0, 0.95), Vector3(0, deck, 0.66), 0.46, p.wood_dark)
	BuildParts.banner(k, Vector3(0.78, deck + 0.1, 0.78), 1.6, 0.4, 0.8, 0.0, p, p.cloth, false)
	k.cylinder(Vector3(-0.78, deck + 0.2, 0.78), 0.5, 0.05, p.wood_dark, 5)
	k.sphere(Vector3(-0.78, deck + 0.78, 0.78), 0.15, MeshKit.glow(Color("ff9a3c"), 0.95), 6, 3)


# --- ancient machines ----------------------------------------------------------------------------

## 2x2 pylon: slate obelisk, bronze rings and a glowing core.
static func machine_spire(k: MeshKit, p: BuildPalette, _seed: int) -> void:
	var glowc := MeshKit.glow(p.glow, 0.9)
	k.box(Vector3(0, 0.14, 0), Vector3(1.9, 0.28, 1.9), p.stone, p.stone_top)
	for i in 4:
		var a := TAU * (float(i) + 0.5) / 4.0
		k.box(Vector3(cos(a) * 0.72, 0.45, sin(a) * 0.72), Vector3(0.36, 0.62, 0.36), p.plaster)
		k.box(Vector3(cos(a) * 0.72, 0.8, sin(a) * 0.72), Vector3(0.42, 0.1, 0.42), p.metal)
	k.frustum(Vector3(0, 0.28, 0), 3.4, 0.62, 0.3, p.stone_dark, 6, true, p.plaster)
	for i in 3:
		k.frustum(Vector3(0, 0.7 + float(i) * 1.0, 0), 0.16, 0.58 - float(i) * 0.1, 0.56 - float(i) * 0.1,
			p.metal, 6, false)
	# glowing inlays running up the shaft
	for i in 3:
		var a := TAU * float(i) / 3.0
		k.tube(Vector3(cos(a) * 0.52, 0.5, sin(a) * 0.52), Vector3(cos(a) * 0.26, 3.4, sin(a) * 0.26),
			0.05, glowc, 4)
	# core
	k.frustum(Vector3(0, 3.62, 0), 0.5, 0.34, 0.5, p.metal, 6, true, p.stone_dark)
	k.sphere(Vector3(0, 4.35, 0), 0.34, glowc, 8, 4)
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.4
		k.tube(Vector3(cos(a) * 0.42, 4.1, sin(a) * 0.42), Vector3(cos(a) * 0.5, 4.75, sin(a) * 0.5),
			0.06, p.metal, 4)
	k.cone(Vector3(0, 4.7, 0), 0.7, 0.26, p.stone_dark, 6)
	k.box(Vector3(0, 1.9, 0.44), Vector3(0.18, 0.9, 0.06), glowc)


## 2x2 broken machine block with glow lines in the cracks.
static func machine_block(k: MeshKit, p: BuildPalette, seed: int) -> void:
	var glowc := MeshKit.glow(p.glow, 0.85)
	k.box(Vector3(0, 0.12, 0), Vector3(1.94, 0.24, 1.94), p.stone_dark, p.stone)
	k.box(Vector3(-0.1, 1.0, 0), Vector3(1.6, 1.6, 1.6), p.stone, p.stone_top)
	# bronze frame edges
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			k.box(Vector3(-0.1 + sx * 0.8, 1.0, sz * 0.8), Vector3(0.14, 1.64, 0.14), p.metal)
	k.box(Vector3(-0.1, 1.78, 0), Vector3(1.7, 0.12, 1.7), p.metal)
	# broken upper corner: stepped blocks
	k.box(Vector3(0.52, 1.95, -0.3), Vector3(0.5, 0.34, 0.8), p.stone.darkened(0.1))
	k.box(Vector3(0.3, 2.2, -0.55), Vector3(0.44, 0.3, 0.44), p.stone.darkened(0.16))
	# glow cracks and vents
	k.box(Vector3(-0.1, 1.2, 0.81), Vector3(1.0, 0.1, 0.05), glowc)
	k.box(Vector3(0.24, 0.85, 0.81), Vector3(0.1, 0.62, 0.05), glowc)
	k.box(Vector3(0.71, 1.15, 0.2), Vector3(0.05, 0.12, 0.9), glowc)
	for i in 3:
		k.box(Vector3(-0.66 + float(i) * 0.24, 1.62, 0.8), Vector3(0.14, 0.24, 0.06), p.stone_dark)
	# torn pipe and rubble
	k.tube(Vector3(-0.9, 1.5, 0.3), Vector3(-1.0, 0.9, 0.6), 0.1, p.metal, 6)
	k.tube(Vector3(-1.0, 0.9, 0.6), Vector3(-1.02, 0.25, 0.86), 0.08, p.metal.darkened(0.2), 5)
	for i in 4:
		var h := RngUtil.hash01(seed, i, 11)
		k.box(Vector3(0.66 + h * 0.2, 0.14 + h * 0.1, 0.55 - float(i) * 0.36),
			Vector3(0.26 + h * 0.1, 0.26, 0.28), p.stone.darkened(0.08))
	k.box(Vector3(-0.1, 1.85, 0.2), Vector3(0.5, 0.06, 0.5), p.moss)


## 4x4 enemy foundry: slate mass, bronze plating, smokestacks and a glowing furnace slit.
static func machine_foundry(k: MeshKit, p: BuildPalette, seed: int) -> void:
	var glowc := MeshKit.glow(p.glow, 0.9)
	k.box(Vector3(0, 0.16, 0), Vector3(3.9, 0.32, 3.9), p.stone_dark, p.stone)
	k.box(Vector3(-0.2, 1.4, -0.35), Vector3(3.2, 2.2, 2.7), p.stone, p.stone_top)
	k.box(Vector3(-0.2, 2.58, -0.35), Vector3(3.36, 0.2, 2.86), p.metal)
	# riveted plating on the front
	for i in 4:
		var x := (float(i) - 1.5) * 0.78
		k.box(Vector3(x - 0.2, 1.5, 1.02), Vector3(0.68, 1.7, 0.08), p.metal.darkened(0.08))
		for j in 3:
			k.sphere(Vector3(x - 0.2, 0.9 + float(j) * 0.6, 1.08), 0.05, p.metal.lightened(0.2), 5, 2)
	# furnace slit + vents
	k.box(Vector3(-0.2, 0.62, 1.06), Vector3(2.4, 0.3, 0.06), glowc)
	k.box(Vector3(-0.2, 2.2, 1.06), Vector3(1.5, 0.14, 0.06), glowc)
	k.box(Vector3(1.42, 1.5, 0.2), Vector3(0.05, 0.9, 1.4), glowc)
	# smokestacks
	for i in 2:
		var x := -1.15 + float(i) * 1.5
		var h := 3.3 + float(i) * 0.5
		k.cylinder(Vector3(x, 2.4, -1.1), h, 0.32, p.stone_dark, 8, p.metal)
		for j in 3:
			k.frustum(Vector3(x, 2.9 + float(j) * 1.0, -1.1), 0.14, 0.35, 0.35, p.metal, 8, false)
		k.frustum(Vector3(x, 2.4 + h, -1.1), 0.26, 0.4, 0.32, p.metal.darkened(0.2), 8, false)
		k.frustum(Vector3(x, 2.4 + h - 0.05, -1.1), 0.08, 0.3, 0.3, glowc, 8, false)
	# piston arm and conveyor on the +X side
	k.box(Vector3(1.62, 1.1, 0.9), Vector3(0.5, 0.5, 2.0), p.metal.darkened(0.15))
	k.cylinder(Vector3(1.62, 1.35, 1.7), 0.9, 0.16, p.metal.lightened(0.1), 6)
	k.torus(Vector3(1.62, 1.9, 1.7), 0.22, 0.05, p.stone_dark, 8, 4)
	for i in 4:
		k.box(Vector3(1.62, 0.55, 1.5 - float(i) * 0.45), Vector3(0.6, 0.12, 0.3), p.metal)
	# claw arm over the front yard
	k.cylinder(Vector3(-1.6, 0.32, 1.35), 2.2, 0.18, p.metal.darkened(0.1), 6)
	k.tube(Vector3(-1.6, 2.4, 1.35), Vector3(-0.35, 2.05, 1.7), 0.11, p.metal, 5)
	for s: float in [-1.0, 1.0]:
		k.tube(Vector3(-0.35, 2.0, 1.7), Vector3(-0.35 + s * 0.22, 1.5, 1.72), 0.05, p.metal.darkened(0.2), 4)
	k.sphere(Vector3(-1.6, 2.5, 1.35), 0.2, glowc, 6, 3)
	# scrap piles
	for i in 3:
		var h := RngUtil.hash01(seed, i, 4)
		k.box(Vector3(0.5 + float(i) * 0.5, 0.36 + h * 0.1, 1.55), Vector3(0.44, 0.4, 0.44),
			p.stone.darkened(0.06 + h * 0.1))


# --- traders ----------------------------------------------------------------------------------------

## 4x4 market hall with a colonnade, striped awnings and goods.
static func trade_hall(k: MeshKit, p: BuildPalette, _seed: int) -> void:
	var plinth := 0.34
	k.push_trs(Vector3(0, 0, -0.55))
	BuildParts.stone_base(k, 3.5, 2.5, plinth, p)
	BuildParts.framed_walls(k, Vector3(3.2, 2.1, 2.2), plinth, p)
	var eave := plinth + 2.1
	BuildParts.gable_roof(k, Vector3(0, eave, 0), 3.2, 2.2, 1.1, 0.26, p)
	for s: float in [-1.0, 1.0]:
		BuildParts.gable_end(k, s * 1.6, 2.2, eave, 1.1, 0.12, p.plaster, p.timber)
	BuildParts.window(k, Vector3(-1.05, plinth + 1.15, 1.11), 0.55, 0.7, 0.0, p)
	BuildParts.window(k, Vector3(1.05, plinth + 1.15, 1.11), 0.55, 0.7, 0.0, p)
	BuildParts.door(k, Vector3(0, plinth, 1.11), 0.85, 1.45, 0.0, p, false)
	BuildParts.wall_banner(k, Vector3(-1.55, eave - 0.1, 1.12), 0.44, 0.9, 0.0, p)
	BuildParts.wall_banner(k, Vector3(1.55, eave - 0.1, 1.12), 0.44, 0.9, 0.0, p)
	k.pop()
	# colonnade with striped awning along the front
	var fz := 0.72
	for i in 4:
		var x := (float(i) - 1.5) * 1.0
		k.cylinder(Vector3(x, 0, fz), 2.3, 0.1, p.wood_dark, 6)
		k.box(Vector3(x, 2.3, fz), Vector3(0.24, 0.12, 0.24), p.gold)
	k.box(Vector3(0, 2.42, fz), Vector3(3.4, 0.14, 0.2), p.wood_dark)
	BuildParts.awning(k, Vector3(0, 2.42, fz), 3.4, 1.0, 0.45, p)
	# stall counters with goods under the awning
	for s: float in [-1.0, 1.0]:
		k.push_trs(Vector3(s * 1.05, 0, 1.25))
		k.box(Vector3(0, 0.62, 0), Vector3(1.2, 0.12, 0.62), p.wood, p.wood.lightened(0.14))
		for sx: float in [-1.0, 1.0]:
			k.box(Vector3(sx * 0.5, 0.3, 0), Vector3(0.12, 0.6, 0.5), p.wood_dark)
		for i in 3:
			k.sphere(Vector3(-0.32 + float(i) * 0.3, 0.76, 0.06), 0.1,
				[Color("d46a4a"), Color("d9b04c"), Color("7aa64e")][i], 6, 3)
		k.pop()
	BuildParts.crate(k, Vector3(-1.72, 0, 1.5), 0.46, p, 10.0)
	BuildParts.barrel(k, Vector3(1.72, 0, 1.55), 0.26, 0.62, p)
	BuildParts.signboard(k, Vector3(0, 2.15, 1.35), 0.0, p)
	BuildParts.lantern(k, Vector3(-1.5, 2.15, 0.72), p)
	BuildParts.lantern(k, Vector3(1.5, 2.15, 0.72), p)


## 2x2 market stall: counter, striped awning and goods.
static func trade_stall(k: MeshKit, p: BuildPalette, _seed: int) -> void:
	k.box(Vector3(0, 0.03, 0), Vector3(1.9, 0.06, 1.9), Color("a39271"))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			k.cylinder(Vector3(sx * 0.78, 0, sz * 0.62), 2.0 if sz > 0.0 else 2.25, 0.07, p.wood_dark, 6)
	k.box(Vector3(0, 2.02, 0.62), Vector3(1.7, 0.1, 0.12), p.wood_dark)
	k.box(Vector3(0, 2.27, -0.62), Vector3(1.7, 0.1, 0.12), p.wood_dark)
	k.push_trs(Vector3(0, 2.27, -0.62), Vector3(9.0, 0, 0))
	var n := 5
	for i in n:
		var t := (float(i) + 0.5) / float(n) - 0.5
		k.box(Vector3(t * 1.72, 0, 0.66), Vector3(1.72 / float(n), 0.06, 1.34),
			p.cloth if i % 2 == 0 else p.cloth_alt)
	k.pop()
	# counter with goods
	k.box(Vector3(0, 0.72, 0.5), Vector3(1.66, 0.12, 0.56), p.wood, p.wood.lightened(0.14))
	k.box(Vector3(0, 0.36, 0.5), Vector3(1.5, 0.6, 0.44), p.wood_dark)
	k.box(Vector3(0, 0.4, 0.74), Vector3(1.4, 0.44, 0.04), p.cloth)
	for i in 4:
		k.sphere(Vector3(-0.54 + float(i) * 0.36, 0.86, 0.5), 0.11,
			[Color("d46a4a"), Color("d9b04c"), Color("7aa64e"), Color("b5566a")][i], 6, 3)
	BuildParts.crate(k, Vector3(-0.62, 0, -0.4), 0.42, p, 12.0)
	BuildParts.barrel(k, Vector3(0.66, 0, -0.42), 0.24, 0.56, p)
	# hanging scales
	k.tube(Vector3(0.78, 1.9, 0.62), Vector3(0.78, 1.62, 0.62), 0.02, p.metal, 4)
	k.box(Vector3(0.78, 1.6, 0.62), Vector3(0.44, 0.04, 0.04), p.gold)
	for s: float in [-1.0, 1.0]:
		k.frustum(Vector3(0.78 + s * 0.2, 1.46, 0.62), 0.07, 0.11, 0.13, p.gold, 6, false)
	BuildParts.lantern(k, Vector3(-0.78, 1.86, 0.62), p)


## 2x2 mooring mast for trader airships; `mooring` anchor sits at 8 m.
static func trade_mast(k: MeshKit, p: BuildPalette, _seed: int) -> void:
	BuildParts.stone_base(k, 1.9, 1.9, 0.4, p)
	for i in 6:
		var z := (float(i) - 2.5) * 0.3
		k.box(Vector3(0, 0.46, z), Vector3(1.7, 0.12, 0.26), p.wood, p.wood.lightened(0.12))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			k.tube(Vector3(sx * 0.62, 0.4, sz * 0.62), Vector3(sx * 0.2, 5.6, sz * 0.2), 0.09, p.wood_dark, 5)
	for y: float in [1.6, 3.2, 4.8]:
		var e: float = lerpf(0.62, 0.2, y / 5.6)
		for s: float in [-1.0, 1.0]:
			k.box(Vector3(0, y, s * e), Vector3(e * 2.0, 0.09, 0.08), p.wood)
			k.box(Vector3(s * e, y, 0), Vector3(0.08, 0.09, e * 2.0), p.wood)
		k.tube(Vector3(-e, y, e), Vector3(e, y + 1.4, -e), 0.045, p.wood, 4)
	k.cylinder(Vector3(0, 5.5, 0), 2.1, 0.13, p.wood_dark, 6)
	k.torus(Vector3(0, 7.55, 0), 0.28, 0.055, p.gold, 10, 4)
	k.sphere(Vector3(0, 7.85, 0), 0.14, p.gold, 6, 3)
	for i in 3:
		var a := TAU * float(i) / 3.0
		k.tube(Vector3(0, 7.3, 0), Vector3(cos(a) * 0.85, 0.5, sin(a) * 0.85), 0.02, p.wood_dark, 4)
	for i in 2:
		k.push_trs(Vector3(0, 6.4 - float(i) * 0.7, 0), Vector3(0, 40.0 * float(i), 0))
		k.plate(PackedVector2Array([Vector2(0, 0), Vector2(0.6, -0.12), Vector2(0, -0.28)]), 0.03,
			p.cloth if i == 0 else p.cloth_alt)
		k.pop()
	BuildParts.ladder(k, Vector3(0.3, 0, 0.82), Vector3(0.3, 5.4, 0.28), 0.42, p.wood)
	BuildParts.crate(k, Vector3(-0.62, 0.46, 0.4), 0.42, p, -12.0)
	BuildParts.lantern(k, Vector3(0.66, 1.5, 0.66), p, 1.1)


## 2x2 round wanderer tent with a smoke hole and a cooking fire.
static func wanderer_tent(k: MeshKit, p: BuildPalette, _seed: int) -> void:
	k.box(Vector3(0, 0.04, 0), Vector3(2.0, 0.08, 2.0), Color("8f8060"))
	k.frustum(Vector3(0, 0.06, 0), 1.0, 0.92, 0.86, p.plaster, 10, true, p.plaster)
	k.frustum(Vector3(0, 0.5, 0), 0.1, 0.94, 0.9, p.cloth, 10, false)
	k.frustum(Vector3(0, 1.06, 0), 0.1, 0.88, 0.88, p.wood_dark, 10, false)
	k.cone(Vector3(0, 1.1, 0), 0.75, 0.9, p.plaster_dark, 10)
	k.cylinder(Vector3(0, 1.66, 0), 0.2, 0.18, p.wood_dark, 8)
	for i in 8:
		var a := TAU * float(i) / 8.0
		k.tube(Vector3(cos(a) * 0.88, 1.08, sin(a) * 0.88), Vector3(0, 1.72, 0), 0.035, p.wood_dark, 4)
	# door flap on +Z
	k.push_trs(Vector3(0, 0.06, 0.9))
	k.plate(PackedVector2Array([Vector2(-0.3, 0), Vector2(0.3, 0), Vector2(0.3, 0.9), Vector2(-0.3, 0.9)]),
		0.04, p.cloth)
	k.pop()
	k.box(Vector3(0, 1.0, 0.92), Vector3(0.74, 0.1, 0.1), p.wood_dark)
	BuildParts.campfire(k, Vector3(0.05, 0, 0.88), 0.26, p)
	for s: float in [-1.0, 1.0]:
		k.tube(Vector3(-0.95 + s * 0.1, 0, -0.85), Vector3(-0.95, 1.1, -0.85 + s * 0.3), 0.04, p.wood_dark, 4)
	k.tube(Vector3(-1.0, 1.05, -0.95), Vector3(-0.9, 1.05, -0.55), 0.03, p.wood_dark, 4)
	for i in 2:
		k.box(Vector3(-0.97, 0.85, -0.85 + float(i) * 0.24), Vector3(0.2, 0.3, 0.05), p.cloth_alt)


# --- ruins ------------------------------------------------------------------------------------------

static func _rubble(k: MeshKit, around: Vector3, count: int, spread: float, p: BuildPalette,
		seed: int, spread_z: float = -1.0) -> void:
	var sz := spread if spread_z < 0.0 else spread_z
	for i in count:
		var h := RngUtil.hash01(seed, i, 21)
		var h2 := RngUtil.hash01(seed, i, 33)
		var s := 0.16 + h * 0.2
		k.box(around + Vector3((h - 0.5) * spread, s * 0.5, (h2 - 0.5) * sz),
			Vector3(s * 1.4, s, s * 1.2), p.stone.darkened(0.05 + h * 0.12), p.stone_top)


## 3x1 broken arch with mossy voussoirs.
static func ruin_arch(k: MeshKit, p: BuildPalette, seed: int) -> void:
	for s: float in [-1.0, 1.0]:
		var h := 2.2 if s > 0.0 else 2.35
		BuildParts.masonry(k, Vector3(s * 1.08, h * 0.5, 0), Vector3(0.66, h, 0.8), p, 4)
		k.box(Vector3(s * 1.08, h + 0.06, 0), Vector3(0.78, 0.14, 0.92), p.stone_top)
	# arch ring of voussoirs
	for i in 7:
		var a: float = PI * (0.12 + 0.76 * float(i) / 6.0)
		var x := -cos(a) * 1.08
		var y := 2.3 + sin(a) * 0.62
		if i == 5:
			continue  # a missing stone
		k.push_trs(Vector3(x, y, 0), Vector3(0, 0, rad_to_deg(a) - 90.0))
		k.box(Vector3.ZERO, Vector3(0.34, 0.42, 0.78), p.stone, p.stone_top)
		k.pop()
	k.box(Vector3(-0.5, 3.0, 0), Vector3(0.6, 0.3, 0.84), p.stone.darkened(0.08))
	k.box(Vector3(-0.5, 3.18, 0.1), Vector3(0.5, 0.08, 0.4), p.moss)
	k.box(Vector3(1.08, 1.4, 0.42), Vector3(0.4, 0.5, 0.04), p.moss)
	_rubble(k, Vector3(0, 0, 0.05), 5, 1.9, p, seed, 0.5)


## 1x1 broken fluted column.
static func ruin_pillar(k: MeshKit, p: BuildPalette, seed: int) -> void:
	k.box(Vector3(0, 0.12, 0), Vector3(0.86, 0.24, 0.86), p.stone_dark, p.stone)
	k.cylinder(Vector3(0, 0.24, 0), 2.3, 0.33, p.stone, 8, p.stone_top)
	for i in 8:
		var a := TAU * float(i) / 8.0
		k.tube(Vector3(cos(a) * 0.32, 0.3, sin(a) * 0.32), Vector3(cos(a) * 0.32, 2.4, sin(a) * 0.32),
			0.045, p.stone_dark, 4)
	k.cylinder(Vector3(0, 2.5, 0), 0.22, 0.4, p.stone, 8, p.stone_top)
	k.box(Vector3(0.06, 2.72, -0.04), Vector3(0.76, 0.2, 0.76), p.stone_top)
	k.box(Vector3(-0.1, 2.86, 0.12), Vector3(0.42, 0.12, 0.4), p.stone.darkened(0.08))
	k.box(Vector3(0, 1.1, 0.34), Vector3(0.3, 0.5, 0.04), p.moss)
	_rubble(k, Vector3(0, 0, 0), 3, 0.8, p, seed)


## 3x1 broken wall with an arched opening.
static func ruin_wall(k: MeshKit, p: BuildPalette, seed: int) -> void:
	var heights: Array[float] = [1.5, 2.3, 2.15, 1.75, 1.1]
	for i in heights.size():
		var x := (float(i) - 2.0) * 0.56
		var h: float = heights[i] * (0.9 + 0.2 * RngUtil.hash01(seed, i, 3))
		BuildParts.masonry(k, Vector3(x, h * 0.5, 0), Vector3(0.56, h, 0.62), p, maxi(2, int(h / 0.6)))
		k.box(Vector3(x, h + 0.04, 0), Vector3(0.6, 0.1, 0.66), p.stone_top)
	# arched opening through the tall part
	k.box(Vector3(-0.28, 0.5, 0), Vector3(0.44, 1.0, 0.72), Color("2f2b26"))
	for i in 5:
		var a: float = PI * (0.1 + 0.8 * float(i) / 4.0)
		k.push_trs(Vector3(-0.28 - cos(a) * 0.26, 1.0 + sin(a) * 0.24, 0), Vector3(0, 0, rad_to_deg(a) - 90.0))
		k.box(Vector3.ZERO, Vector3(0.18, 0.2, 0.7), p.stone_top)
		k.pop()
	k.box(Vector3(0.62, 1.2, 0.33), Vector3(0.5, 0.5, 0.05), p.moss)
	k.box(Vector3(-1.05, 0.5, 0.33), Vector3(0.4, 0.7, 0.05), p.moss)
	for i in 3:
		k.tube(Vector3(0.3 + float(i) * 0.3, 2.1, 0.3), Vector3(0.25 + float(i) * 0.3, 1.3, 0.36),
			0.035, p.moss.darkened(0.1), 4)
	_rubble(k, Vector3(0.2, 0, 0.05), 4, 1.7, p, seed, 0.5)


## 2x2 weathered statue on a stepped pedestal.
static func ruin_statue(k: MeshKit, p: BuildPalette, seed: int) -> void:
	k.box(Vector3(0, 0.14, 0), Vector3(1.8, 0.28, 1.8), p.stone_dark, p.stone)
	k.box(Vector3(0, 0.4, 0), Vector3(1.45, 0.3, 1.45), p.stone, p.stone_top)
	BuildParts.masonry(k, Vector3(0, 0.95, 0), Vector3(1.1, 0.8, 1.1), p, 2)
	k.box(Vector3(0, 1.4, 0), Vector3(1.24, 0.14, 1.24), p.stone_top)
	# robed figure
	k.frustum(Vector3(0, 1.47, 0), 1.0, 0.44, 0.3, p.stone, 8, true, p.stone_top)
	for i in 5:
		k.box(Vector3(0, 1.7 + float(i) * 0.16, 0.3 - float(i) * 0.04), Vector3(0.7, 0.07, 0.1),
			p.stone_dark)
	k.box(Vector3(0, 2.62, 0), Vector3(0.62, 0.42, 0.42), p.stone, p.stone_top)
	k.sphere(Vector3(0, 3.0, 0), 0.26, p.stone, 7, 4)
	k.box(Vector3(0, 3.08, 0.2), Vector3(0.3, 0.06, 0.12), p.stone_dark)
	# one raised arm, the other broken off
	k.tube(Vector3(0.28, 2.66, 0.05), Vector3(0.52, 3.3, 0.12), 0.1, p.stone, 5)
	k.box(Vector3(0.56, 3.42, 0.12), Vector3(0.18, 0.3, 0.18), p.stone_top)
	k.tube(Vector3(-0.28, 2.66, 0.05), Vector3(-0.44, 2.35, 0.1), 0.1, p.stone.darkened(0.06), 5)
	k.box(Vector3(0, 2.1, 0.26), Vector3(0.44, 0.34, 0.05), p.moss)
	k.box(Vector3(-0.5, 0.58, 0.4), Vector3(0.4, 0.06, 0.4), p.moss)
	_rubble(k, Vector3(0.4, 0, 0.7), 3, 1.0, p, seed)


## 3x3 sealed vault: stone bunker with a glowing round door.
static func ruin_vault(k: MeshKit, p: BuildPalette, seed: int) -> void:
	var glowc := MeshKit.glow(Color("6fd2c8"), 0.6)
	k.box(Vector3(0, 0.16, 0), Vector3(2.9, 0.32, 2.9), p.stone_dark, p.stone)
	BuildParts.masonry(k, Vector3(0, 1.2, -0.25), Vector3(2.5, 1.9, 2.2), p, 4)
	k.box(Vector3(0, 2.2, -0.25), Vector3(2.7, 0.2, 2.4), p.stone_top)
	k.box(Vector3(0, 2.4, -0.25), Vector3(2.2, 0.22, 1.9), p.stone)
	# sloped entrance block with the round door
	k.box(Vector3(0, 0.7, 0.95), Vector3(1.9, 1.4, 0.7), p.stone, p.stone_top)
	k.push_trs(Vector3(0, 0.82, 1.32), Vector3(90, 0, 0))
	k.cylinder(Vector3(0, -0.06, 0), 0.12, 0.72, p.stone_dark, 12)
	k.cylinder(Vector3(0, 0.0, 0), 0.1, 0.6, p.metal, 12, p.metal)
	k.cylinder(Vector3(0, 0.06, 0), 0.06, 0.2, glowc, 10)
	for i in 6:
		var a := TAU * float(i) / 6.0
		k.push_trs(Vector3(cos(a) * 0.36, 0.08, sin(a) * 0.36), Vector3(0, rad_to_deg(-a), 0))
		k.box(Vector3.ZERO, Vector3(0.4, 0.05, 0.08), glowc)
		k.pop()
	k.pop()
	k.torus(Vector3(0, 0.82, 1.3), 0.72, 0.06, p.gold.darkened(0.2), 12, 4)
	# steps and glyph strip
	k.box(Vector3(0, 0.08, 1.52), Vector3(1.5, 0.16, 0.4), p.stone_top)
	k.box(Vector3(0, 1.62, 1.28), Vector3(1.3, 0.12, 0.06), glowc)
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(s * 1.1, 1.0, 1.1), Vector3(0.24, 2.0, 0.24), p.stone_dark)
		k.sphere(Vector3(s * 1.1, 2.12, 1.1), 0.16, glowc, 6, 3)
	k.box(Vector3(-0.5, 2.32, 0.4), Vector3(0.9, 0.08, 0.6), p.moss)
	k.box(Vector3(1.1, 1.5, 0.05), Vector3(0.1, 0.7, 0.5), p.moss)
	_rubble(k, Vector3(-0.9, 0, 1.05), 3, 0.9, p, seed, 0.6)


# --- wreck ------------------------------------------------------------------------------------------

## 6x3 crashed airship: broken hull, torn striped balloon, scattered cargo.
static func wreck_airship(k: MeshKit, p: BuildPalette, seed: int) -> void:
	var hull := Color("8a6a4a")
	var hull_dark := Color("5f4a33")
	# ground scar
	k.box(Vector3(0.6, 0.03, 0.2), Vector3(4.6, 0.06, 2.0), Color("6d5b45"))
	# hull, nose down and rolled
	k.push_trs(Vector3(-0.4, 0.55, 0.1), Vector3(0, 8.0, -12.0))
	k.push_trs(Vector3.ZERO, Vector3(0, 0, -90))
	k.frustum(Vector3(0, -1.9, 0), 1.2, 0.22, 0.62, hull, 7, true, hull)
	k.frustum(Vector3(0, -0.7, 0), 2.1, 0.62, 0.72, hull, 7, true, hull)
	k.frustum(Vector3(0, 1.4, 0), 0.9, 0.72, 0.5, hull_dark, 7, true, hull_dark)
	for i in 5:
		k.frustum(Vector3(0, -1.5 + float(i) * 0.7, 0), 0.1, 0.72, 0.72, hull_dark, 7, false)
	k.pop()
	# deck rails and a broken mast
	k.box(Vector3(0.2, 0.6, 0), Vector3(3.0, 0.1, 1.0), hull_dark)
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(0.2, 0.78, s * 0.5), Vector3(3.0, 0.26, 0.07), hull)
	k.tube(Vector3(0.9, 0.6, 0), Vector3(1.5, 1.7, -0.25), 0.1, hull_dark, 5)
	k.box(Vector3(1.55, 1.75, -0.28), Vector3(0.3, 0.2, 0.2), hull_dark)
	k.pop()
	# torn striped balloon lying over the hull
	k.push_trs(Vector3(0.9, 1.5, -0.1), Vector3(-6.0, 12.0, -16.0))
	k.push_trs(Vector3.ZERO, Vector3(0, 0, -90))
	var segs := 7
	var length := 4.6
	for i in segs:
		if i == 4:
			continue  # torn open section
		var t0 := -length * 0.5 + length * float(i) / float(segs)
		var t1 := -length * 0.5 + length * float(i + 1) / float(segs)
		var r0: float = 0.98 * sqrt(maxf(0.0, 1.0 - pow(t0 / (length * 0.55), 2.0)))
		var r1: float = 0.98 * sqrt(maxf(0.0, 1.0 - pow(t1 / (length * 0.55), 2.0)))
		var col: Color = p.plaster if i % 2 == 0 else Color("3a5da8")
		k.frustum(Vector3(0, t0, 0), t1 - t0, r0, r1, col, 9, false)
		k.frustum(Vector3(0, t0, 0), 0.06, r0 + 0.02, r0 + 0.02, hull_dark, 9, false)
	# torn edges and exposed ribs
	for s: int in [3, 5]:
		var t: float = -length * 0.5 + length * float(s + (1 if s == 3 else 0)) / float(segs)
		var r: float = 0.98 * sqrt(maxf(0.0, 1.0 - pow(t / (length * 0.55), 2.0)))
		for i in 9:
			var a := TAU * float(i) / 9.0
			var jag: float = 0.12 + 0.22 * RngUtil.hash01(seed, i, s)
			var dir := 1.0 if s == 3 else -1.0
			k.tri(Vector3(cos(a) * r, t, sin(a) * r),
				Vector3(cos(a + TAU / 9.0) * r, t, sin(a + TAU / 9.0) * r),
				Vector3(cos(a + TAU / 18.0) * r * 0.95, t + jag * dir, sin(a + TAU / 18.0) * r * 0.95),
				p.plaster.darkened(0.1))
	k.torus(Vector3(0, -length * 0.5 + length * 4.0 / float(segs), 0), 0.72, 0.05, hull_dark, 9, 3)
	k.pop()
	k.pop()
	# bent propeller at the stern
	k.push_trs(Vector3(-2.35, 0.95, 0.15), Vector3(0, 0, 14.0))
	k.cylinder(Vector3(0, -0.12, 0), 0.24, 0.16, p.metal, 6)
	for i in 3:
		k.push_trs(Vector3(0, 0.12, 0), Vector3(0, 120.0 * float(i), 0))
		k.box(Vector3(0.42, 0, 0), Vector3(0.8, 0.05, 0.22), p.metal.lightened(0.1))
		k.pop()
	k.pop()
	# scattered cargo and debris
	BuildParts.crate(k, Vector3(2.1, 0, 0.8), 0.5, p, 24.0)
	BuildParts.crate(k, Vector3(2.55, 0, 0.1), 0.44, p, -12.0)
	BuildParts.barrel(k, Vector3(1.6, 0, -0.9), 0.26, 0.6, p)
	for i in 4:
		var h := RngUtil.hash01(seed, i, 17)
		k.box(Vector3(-2.0 + float(i) * 1.2, 0.08, -1.0 + h * 0.5), Vector3(0.7, 0.12, 0.2),
			hull_dark, hull)
	k.push_trs(Vector3(2.6, 0.06, -0.6), Vector3(0, 30.0, 0))
	k.plate(PackedVector2Array([Vector2(-0.5, 0), Vector2(0.5, 0.1), Vector2(0.4, 0.6), Vector2(-0.45, 0.5)]),
		0.03, Color("3a5da8"))
	k.pop()
