class_name BldTown
extends RefCounted
## Procedural fallback geometry for the town's painted-card buildings.


static func build(k: MeshKit, id: String, p: BuildPalette, seed: int, _level: int) -> bool:
	match id:
		"t_fountain":
			_fountain(k, p)
		"t_guild_hall":
			_guild_hall(k, p)
		"t_tavern":
			_tavern(k, p, seed)
		"t_general_store":
			_general_store(k, p)
		"t_smithy":
			_smithy(k, p, seed)
		"t_inn":
			_inn(k, p)
		_:
			return false
	return true


static func _fountain(k: MeshKit, p: BuildPalette) -> void:
	k.cylinder(Vector3(0, 0.08, 0), 0.16, 1.34, p.stone_dark, 8, p.stone_top)
	k.cylinder(Vector3(0, 0.24, 0), 0.24, 1.16, p.stone, 8, p.stone_top)
	k.cylinder(Vector3(0, 0.42, 0), 0.08, 0.88, Color("#6599a0"), 8)
	k.cylinder(Vector3(0, 0.46, 0), 0.44, 0.2, p.stone_top, 8)
	k.cylinder(Vector3(0, 0.9, 0), 0.13, 0.3, p.gold, 8)
	k.sphere(Vector3(0, 1.22, 0), 0.22, Color("#8fc7c7"), 8, 4)
	for i in 4:
		var a := TAU * float(i) / 4.0
		BuildParts.post(k, cos(a) * 1.18, sin(a) * 1.18, 0.16, 0.68, 0.08, p.stone_top)


static func _guild_hall(k: MeshKit, p: BuildPalette) -> void:
	BuildParts.stone_base(k, 4.5, 4.5, 0.36, p)
	BuildParts.framed_walls(k, Vector3(4.2, 2.6, 4.2), 0.36, p, true)
	BuildParts.gable_roof(k, Vector3(0, 2.96, 0), 4.3, 4.3, 1.72, 0.34, p, Color("#66513b"))
	BuildParts.door(k, Vector3(0, 0.36, 2.12), 1.0, 1.65, 0.0, p)
	BuildParts.window(k, Vector3(-1.35, 1.65, 2.12), 0.58, 0.66, 0.0, p)
	BuildParts.window(k, Vector3(1.35, 1.65, 2.12), 0.58, 0.66, 0.0, p)
	BuildParts.banner(k, Vector3(-1.72, 0.36, 2.12), 3.1, 0.46, 0.82, 0.0, p, Color("#9b552f"))
	BuildParts.lantern(k, Vector3(1.55, 2.55, 2.14), p)
	k.box(Vector3(0, 0.46, 2.48), Vector3(1.6, 0.16, 0.42), p.wood_dark)


static func _tavern(k: MeshKit, p: BuildPalette, seed: int) -> void:
	BuildParts.stone_base(k, 3.6, 3.6, 0.28, p)
	BuildParts.framed_walls(k, Vector3(3.4, 2.25, 3.4), 0.28, p, true, Color("#c5a879"))
	BuildParts.gable_roof(k, Vector3(0, 2.53, 0), 3.5, 3.5, 1.35, 0.3, p, Color("#8b4938"))
	BuildParts.door(k, Vector3(-0.55, 0.28, 1.72), 0.82, 1.45, 0.0, p)
	BuildParts.window(k, Vector3(0.82, 1.42, 1.72), 0.58, 0.62, 0.0, p)
	BuildParts.chimney(k, Vector3(1.12 if absi(seed) % 2 == 0 else -1.12, 3.0, -0.72), 1.28, p, 0.38)
	BuildParts.lantern(k, Vector3(-1.22, 2.0, 1.83), p)
	BuildParts.barrel(k, Vector3(-1.05, 0.0, 2.15), 0.28, 0.64, p)
	# hanging sign: a gold kettle over the public entrance
	BuildParts.post(k, 1.15, 1.8, 1.8, 2.82, 0.055, p.wood_dark)
	k.box(Vector3(1.15, 2.57, 2.02), Vector3(0.64, 0.46, 0.14), p.cloth, p.gold)
	k.cylinder(Vector3(1.15, 2.62, 2.12), 0.2, 0.13, p.gold, 8)


static func _general_store(k: MeshKit, p: BuildPalette) -> void:
	BuildParts.stone_base(k, 3.6, 3.6, 0.26, p)
	BuildParts.framed_walls(k, Vector3(3.4, 2.15, 3.4), 0.26, p, true, Color("#d7c291"))
	BuildParts.gable_roof(k, Vector3(0, 2.41, 0), 3.5, 3.5, 1.22, 0.3, p, Color("#65704b"))
	BuildParts.door(k, Vector3(-0.72, 0.26, 1.72), 0.78, 1.4, 0.0, p)
	BuildParts.window(k, Vector3(0.9, 1.3, 1.72), 0.68, 0.54, 0.0, p, true, true)
	k.box(Vector3(0.92, 2.12, 2.0), Vector3(1.56, 0.16, 0.88), p.wood_dark)
	k.box(Vector3(0.92, 2.42, 2.0), Vector3(1.56, 0.52, 0.82), p.cloth, p.cloth_alt)
	BuildParts.crate(k, Vector3(-1.25, 0.0, 2.15), 0.48, p, -8.0)
	BuildParts.sack(k, Vector3(1.38, 0.0, 1.8), 0.3, p)
	BuildParts.lantern(k, Vector3(-1.15, 1.95, 1.82), p)


static func _smithy(k: MeshKit, p: BuildPalette, seed: int) -> void:
	BuildParts.stone_base(k, 3.6, 3.6, 0.34, p)
	BuildParts.masonry(k, Vector3(0, 1.53, 0), Vector3(3.35, 2.38, 3.35), p, 4)
	BuildParts.hip_roof(k, Vector3(0, 2.72, 0), 3.55, 3.55, 1.05, 0.24, p, false)
	BuildParts.opening(k, Vector3(0.0, 0.34, 1.68), 1.25, 1.72, 0.44, 0.0, p)
	BuildParts.chimney(k, Vector3(-1.05, 2.65, -0.92), 1.82, p, 0.54)
	BuildParts.lantern(k, Vector3(1.42, 2.3, 1.8), p)
	# open forge mouth, anvil and a spare hammer make the workshop legible at game scale
	k.box(Vector3(-0.9, 0.58, 1.88), Vector3(0.72, 0.74, 0.18), p.stone_dark, Color("#e18b3a"))
	k.box(Vector3(0.9, 0.45, 2.0), Vector3(0.72, 0.28, 0.42), p.metal)
	k.box(Vector3(0.82, 0.66, 2.0), Vector3(0.94, 0.14, 0.32), p.metal.lightened(0.18))
	BuildParts.post(k, 1.18, 1.82, 0.66, 1.28, 0.055, p.wood_dark)
	k.box(Vector3(1.18, 1.32, 1.82), Vector3(0.42, 0.12, 0.12), p.metal)
	if absi(seed) % 2 == 0:
		BuildParts.barrel(k, Vector3(-1.35, 0.0, 1.75), 0.25, 0.58, p)


static func _inn(k: MeshKit, p: BuildPalette) -> void:
	BuildParts.stone_base(k, 3.6, 3.6, 0.3, p)
	BuildParts.framed_walls(k, Vector3(3.4, 2.4, 3.4), 0.3, p, true, Color("#e3cfaa"))
	BuildParts.gable_roof(k, Vector3(0, 2.7, 0), 3.5, 3.5, 1.48, 0.32, p, Color("#4d7158"))
	BuildParts.door(k, Vector3(0, 0.3, 1.72), 0.84, 1.48, 0.0, p)
	BuildParts.window(k, Vector3(-1.05, 1.5, 1.72), 0.58, 0.72, 0.0, p)
	BuildParts.window(k, Vector3(1.05, 1.5, 1.72), 0.58, 0.72, 0.0, p)
	BuildParts.chimney(k, Vector3(1.12, 3.0, -0.82), 1.08, p, 0.32)
	BuildParts.banner(k, Vector3(-1.45, 0.3, 1.75), 2.45, 0.42, 0.7, 0.0, p, Color("#537754"))
	BuildParts.lantern(k, Vector3(0, 2.0, 1.88), p)
	k.box(Vector3(0, 0.42, 2.0), Vector3(1.34, 0.14, 0.42), p.wood)
