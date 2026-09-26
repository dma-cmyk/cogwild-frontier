class_name PropMeshes
extends RefCounted
## Cached one-surface meshes for world MultiMesh props.

const COUNTS := {
	"tree_pine": 3, "tree_oak": 3, "tree_birch": 2, "tree_dead": 2, "stump": 1,
	"bush": 2, "berry_bush": 2, "berry_bush_empty": 1, "rock_small": 3, "rock_large": 3,
	"ore_iron": 2, "ore_crystal": 2, "grass_tuft": 3, "flowers": 3, "reeds": 2,
	"tilled_soil": 1, "bridge_plank": 1, "fence": 1, "crate": 1, "barrel": 1,
	"lantern_post": 1, "log_pile": 1, "stone_pile": 1, "ore_pile": 1, "loot_bag": 1,
	"loot_chest": 1, "sign_post": 1, "banner_pole": 1, "arrow": 1, "bolt": 1,
	"bullet": 1, "cannon_shell": 1, "blaster_bolt": 1
}
static var _cache: Dictionary = {}

static func variant_count(prop_id: String) -> int:
	if prop_id.begins_with("crop_wheat_") or prop_id.begins_with("crop_veg_"):
		return 1
	return int(COUNTS.get(prop_id, 0))

static func get_mesh(prop_id: String, variant: int = 0) -> ArrayMesh:
	var id := prop_id
	if not COUNTS.has(id) and not id.begins_with("crop_wheat_") and not id.begins_with("crop_veg_"):
		id = "rock_small"
	var count: int = maxi(variant_count(id), 1)
	var v: int = posmod(variant, count)
	var key := "%s:%d" % [id, v]
	if _cache.has(key):
		return _cache[key] as ArrayMesh
	var k := MeshKit.new()
	k.shade_jitter = 0.04
	_build(k, id, v)
	var mesh := k.build()
	_cache[key] = mesh
	return mesh

static func _build(k: MeshKit, id: String, v: int) -> void:
	var wood := Color("8a5a34")
	var bark := Color("62452e")
	var leaf: Color = [Color("3d7548"), Color("4f8b50"), Color("679a52")][v % 3]
	var leaf_dark: Color = leaf.darkened(0.22)
	var stone: Color = [Color("817d73"), Color("928b7c"), Color("6e736e")][v % 3]
	if id == "tree_pine":
		var h := 3.5 + float(v) * 0.65
		k.cylinder(Vector3(0, 0, 0), 0.38, 0.12, bark, 6)
		for i in 3:
			var y := 1.1 + float(i) * 0.88
			var r := 0.92 - float(i) * 0.2
			k.cone(Vector3(0, y, 0), h * 0.38, r, leaf if i != 1 else leaf_dark, 7)
		return
	if id == "tree_oak":
		k.cylinder(Vector3(0, 0, 0), 1.55 + v * 0.12, 0.16, bark, 6)
		k.tube(Vector3(0, 1.05, 0), Vector3(-0.55, 1.9, 0.1), 0.09, bark, 5)
		k.tube(Vector3(0, 1.12, 0), Vector3(0.55, 1.82, -0.1), 0.09, bark, 5)
		k.ellipsoid(Vector3(0, 2.15, 0), Vector3(1.05, 0.95, 0.95), leaf, 8, 3)
		k.ellipsoid(Vector3(0.45, 2.0, 0.15), Vector3(0.6, 0.55, 0.6), leaf_dark, 7, 3)
		return
	if id == "tree_birch":
		k.cylinder(Vector3(0, 0, 0), 3.0 + v * 0.5, 0.13, Color("ddd5bb"), 6)
		for y in [2.0, 2.65, 3.2]: k.box(Vector3(0, y, 0), Vector3(0.22, 0.08, 0.2), bark)
		k.ellipsoid(Vector3(0, 3.35 + v * 0.2, 0), Vector3(0.72, 0.58, 0.72), leaf, 7, 3)
		return
	if id == "tree_dead":
		k.tube(Vector3(0, 0, 0), Vector3(0.1, 2.5 + v * 0.4, 0), 0.14, bark, 6)
		k.tube(Vector3(0, 1.6, 0), Vector3(-0.6, 2.25, 0.1), 0.08, bark, 5)
		k.tube(Vector3(0, 1.9, 0), Vector3(0.55, 2.35, -0.12), 0.075, bark, 5)
		return
	if id == "stump":
		k.cylinder(Vector3(0, 0, 0), 0.48, 0.38, bark, 8, Color("aa7a45"))
		k.torus(Vector3(0, 0.5, 0), 0.22, 0.025, Color("d7a261"), 8, 4)
		return
	if id in ["bush", "berry_bush", "berry_bush_empty"]:
		k.ellipsoid(Vector3(-0.25, 0.38, 0), Vector3(0.42, 0.42, 0.42), leaf, 7, 3)
		k.ellipsoid(Vector3(0.27, 0.42, 0.05), Vector3(0.45, 0.45, 0.42), leaf_dark, 7, 3)
		if id == "berry_bush":
			for p in [Vector3(-0.38, 0.55, 0.3), Vector3(0.04, 0.7, 0.35), Vector3(0.34, 0.5, 0.28)]: k.sphere(p, 0.08, Color("d44c3d"), 5, 2)
		return
	if id in ["rock_small", "rock_large", "ore_iron", "ore_crystal"]:
		var scale := 0.32 if id in ["rock_small", "ore_iron", "ore_crystal"] else 0.62
		k.ellipsoid(Vector3(0, scale * 0.55, 0), Vector3(scale, scale * 0.72, scale * 0.82), stone, 7, 3)
		if id == "ore_iron":
			k.tube(Vector3(-scale * 0.45, scale * 0.6, scale * 0.5), Vector3(scale * 0.35, scale * 0.78, scale * 0.5), 0.035, Color("c26a3b"), 5)
			k.tube(Vector3(-scale * 0.28, scale * 0.4, -scale * 0.55), Vector3(scale * 0.4, scale * 0.65, -scale * 0.55), 0.03, Color("d17441"), 5)
		elif id == "ore_crystal":
			for x in [-0.16, 0.12]: k.cone(Vector3(x, 0.25, 0), 0.75 + 0.1 * v, 0.15, MeshKit.glow(Color("50d6df"), 0.75), 5)
		return
	if id == "grass_tuft":
		for x in [-0.22, 0.0, 0.22]:
			k.plate(PackedVector2Array([Vector2(x - 0.04, 0), Vector2(x + 0.04, 0), Vector2(x + 0.08, 0.52 + v * 0.08), Vector2(x, 0.34), Vector2(x - 0.08, 0.52)]), 0.025, Color("6eaa4e"))
		return
	if id == "flowers":
		for x in [-0.28, 0, 0.28]:
			k.tube(Vector3(x, 0, 0), Vector3(x, 0.38, 0), 0.025, Color("558c4b"), 4)
			k.sphere(Vector3(x, 0.43, 0), 0.09, [Color("e6ba55"), Color("dd6b58"), Color("b68be0")][v % 3], 5, 2)
		return
	if id == "reeds":
		for x in [-0.24, -0.08, 0.08, 0.24]: k.tube(Vector3(x, 0, 0), Vector3(x - 0.1, 0.8 + v * 0.12, 0.05), 0.025, Color("789b45"), 4)
		return
	if id.begins_with("crop_wheat_") or id.begins_with("crop_veg_"):
		var stage := clampi(int(id.get_slice("_", 2)), 0, 3)
		if id.begins_with("crop_wheat_"):
			for x in [-0.32, -0.1, 0.12, 0.34]:
				var h := 0.25 + stage * 0.24
				k.tube(Vector3(x, 0, 0), Vector3(x + 0.04, h, 0), 0.025, Color("698e43"), 4)
				if stage >= 2: k.sphere(Vector3(x + 0.04, h + 0.06, 0), 0.07, Color("e0b54f"), 5, 2)
		else:
			var h2 := 0.18 + stage * 0.08
			for x in [-0.28, 0, 0.28]: k.ellipsoid(Vector3(x, h2 * 0.5, 0), Vector3(0.22 + stage * 0.04, h2, 0.2 + stage * 0.04), Color("719b49"), 7, 3)
			if stage >= 3: k.ellipsoid(Vector3(0, 0.18, 0.1), Vector3(0.25, 0.2, 0.25), Color("9cb64d"), 7, 3)
		return
	if id == "tilled_soil":
		k.box(Vector3(0, 0.04, 0), Vector3(0.96, 0.08, 0.96), Color("604b38"), Color("795b3c"))
		for z in [-0.3, 0.0, 0.3]: k.box(Vector3(0, 0.09, z), Vector3(0.82, 0.025, 0.045), Color("9b754a"))
		return
	if id == "bridge_plank":
		for x in [-0.36, -0.12, 0.12, 0.36]: k.box(Vector3(x, 0.14, 0), Vector3(0.2, 0.18, 0.9), wood, Color("b27a42"))
		k.tube(Vector3(-0.48, 0.38, -0.42), Vector3(0.48, 0.38, -0.42), 0.045, bark, 5)
		k.tube(Vector3(-0.48, 0.38, 0.42), Vector3(0.48, 0.38, 0.42), 0.045, bark, 5)
		return
	if id == "fence":
		k.tube(Vector3(-0.48, 0, 0), Vector3(-0.48, 0.85, 0), 0.055, wood, 5)
		k.tube(Vector3(0.48, 0, 0), Vector3(0.48, 0.85, 0), 0.055, wood, 5)
		k.box(Vector3(0, 0.35, 0), Vector3(1.0, 0.12, 0.1), wood)
		k.box(Vector3(0, 0.68, 0), Vector3(1.0, 0.12, 0.1), wood)
		return
	if id == "crate":
		k.box(Vector3(0, 0.3, 0), Vector3(0.62, 0.6, 0.62), wood, Color("ae7740"))
		k.box(Vector3(0, 0.3, 0.325), Vector3(0.12, 0.55, 0.02), bark)
		k.box(Vector3(0, 0.3, -0.325), Vector3(0.12, 0.55, 0.02), bark)
		return
	if id == "barrel":
		k.cylinder(Vector3(0, 0, 0), 0.7, 0.3, wood, 8, Color("bd8247"))
		k.torus(Vector3(0, 0.18, 0), 0.31, 0.035, Color("4c3d31"), 6, 3)
		k.torus(Vector3(0, 0.52, 0), 0.31, 0.035, Color("4c3d31"), 6, 3)
		return
	if id == "lantern_post":
		k.cylinder(Vector3(0, 0, 0), 1.5, 0.065, bark, 6)
		k.box(Vector3(0, 1.5, 0), Vector3(0.32, 0.4, 0.32), MeshKit.glow(Color("ffd46a"), 0.8))
		k.cone(Vector3(0, 1.72, 0), 0.15, 0.24, wood, 6)
		return
	if id in ["log_pile", "stone_pile", "ore_pile"]:
		var c: Color = wood if id == "log_pile" else (Color("bd7140") if id == "ore_pile" else stone)
		for i in 4: k.cylinder(Vector3(-0.24 + (i % 2) * 0.3, 0.14 + (i / 2) * 0.2, 0), 0.5, 0.12, c, 6)
		return
	if id == "loot_bag":
		k.ellipsoid(Vector3(0, 0.24, 0), Vector3(0.34, 0.28, 0.3), Color("9e6945"), 7, 3)
		k.tube(Vector3(-0.14, 0.4, 0), Vector3(0.14, 0.4, 0), 0.035, Color("d8ba70"), 5)
		return
	if id == "loot_chest":
		k.box(Vector3(0, 0.26, 0), Vector3(0.8, 0.52, 0.52), Color("704a31"), Color("aa7640"))
		k.box(Vector3(0, 0.28, 0.29), Vector3(0.12, 0.24, 0.03), Color("d9b04c"))
		return
	if id == "sign_post":
		k.cylinder(Vector3(0, 0, 0), 1.1, 0.06, bark, 5)
		k.box(Vector3(0, 1.02, 0), Vector3(0.7, 0.4, 0.08), wood, Color("d1a36a"))
		return
	if id == "banner_pole":
		k.cylinder(Vector3(0, 0, 0), 1.8, 0.05, bark, 5)
		k.plate(PackedVector2Array([Vector2(0, 0), Vector2(0.48, 0), Vector2(0.4, -0.7), Vector2(0.2, -0.55), Vector2(0, -0.7)]), 0.025, Color("3a5da8"))
		return
	# Projectiles point along +Z, with a clear silhouette at gameplay scale.
	if id in ["arrow", "bolt"]:
		k.tube(Vector3(0, 0, -0.42), Vector3(0, 0, 0.42), 0.025 if id == "arrow" else 0.04, wood, 5)
		k.cone(Vector3(0, 0, 0.42), 0.18, 0.08, Color("c9c7bd"), 5)
		k.plate(PackedVector2Array([Vector2(-0.12, 0), Vector2(0, 0.14), Vector2(0.12, 0), Vector2(0, -0.14)]), 0.025, Color("b33a2e"))
		return
	if id == "bullet":
		k.ellipsoid(Vector3(0, 0, 0), Vector3(0.07, 0.07, 0.16), Color("d9b04c"), 6, 3)
		return
	if id == "cannon_shell":
		k.ellipsoid(Vector3(0, 0, 0), Vector3(0.16, 0.16, 0.32), Color("4e555c"), 7, 3)
		return
	if id == "blaster_bolt":
		k.ellipsoid(Vector3(0, 0, 0), Vector3(0.1, 0.1, 0.32), MeshKit.glow(Color("55d7ff"), 0.9), 7, 3)
