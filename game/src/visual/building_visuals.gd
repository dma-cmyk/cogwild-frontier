class_name BuildingVisuals
extends RefCounted
## Building factory: picks the geometry builder for a type id, caches the four construction-stage
## meshes per visual key and attaches the moving / particle / light nodes.
## Geometry lives in src/visual/world/ (BuildParts + BldFrontier + BldOutland).

const FOOTPRINTS := {
	"hearth": Vector2i(4, 4), "house": Vector2i(3, 3), "storehouse": Vector2i(3, 4),
	"workshop": Vector2i(4, 4), "smelter": Vector2i(3, 3), "windmill": Vector2i(3, 3),
	"sky_dock": Vector2i(4, 4), "watchtower": Vector2i(2, 2), "wall": Vector2i(1, 1),
	"bridge_segment": Vector2i(1, 1), "cliff_stairs": Vector2i(1, 1),
	"outpost": Vector2i(3, 3), "bandit_tent": Vector2i(2, 2), "bandit_hut": Vector2i(3, 3),
	"bandit_tower": Vector2i(2, 2), "palisade": Vector2i(1, 1), "campfire": Vector2i(1, 1),
	"machine_spire": Vector2i(2, 2), "machine_block": Vector2i(2, 2), "machine_foundry": Vector2i(4, 4),
	"trade_hall": Vector2i(4, 4), "trade_stall": Vector2i(2, 2), "trade_mast": Vector2i(2, 2),
	"wanderer_tent": Vector2i(2, 2), "ruin_arch": Vector2i(3, 1), "ruin_pillar": Vector2i(1, 1),
	"ruin_wall": Vector2i(3, 1), "ruin_statue": Vector2i(2, 2), "ruin_vault": Vector2i(3, 3),
	"wreck_airship": Vector2i(6, 3)
}
## Style is fixed for the non-player factions; only the frontier ids honour the `style` argument.
const FIXED_STYLE := {
	"bandit_tent": "bandit", "bandit_hut": "bandit", "bandit_tower": "bandit",
	"machine_spire": "ancient", "machine_block": "ancient", "machine_foundry": "ancient",
	"trade_hall": "merchant", "trade_stall": "merchant", "trade_mast": "merchant",
	"wanderer_tent": "neutral", "ruin_arch": "neutral", "ruin_pillar": "neutral",
	"ruin_wall": "neutral", "ruin_statue": "neutral", "ruin_vault": "neutral",
	"wreck_airship": "frontier"
}
const STYLES := ["frontier", "bandit", "ancient", "merchant", "neutral"]

static var _cache: Dictionary = {}


static func create(type_id: String, style: String, variant_seed: int, level: int = 1) -> BuildingVisual:
	var profile := World.profile_chunks()
	var create_start_usec: int = Time.get_ticks_usec() if profile else 0
	var id := type_id if FOOTPRINTS.has(type_id) else "house"
	var faction: String = FIXED_STYLE.get(id, style if STYLES.has(style) else "frontier")
	var lv := clampi(level, 1, 3)
	var fp: Vector2i = FOOTPRINTS[id]
	var stages: Array[ArrayMesh] = [null, null, null, stage_mesh(id, faction, variant_seed, lv, 3)]
	var mesh_cache_usec: int = Time.get_ticks_usec() - create_start_usec if profile else 0
	var fx := _effects(id, variant_seed, lv)
	var visual := BuildingVisual.new()
	visual.name = "Building_%s" % id
	visual.configure(id, faction, variant_seed, lv, {
		"footprint": fp,
		"height": stages[3].get_aabb().end.y if stages[3].get_surface_count() > 0 else 2.0,
		"stages": stages,
		"anchors": _anchors(id, fp),
	})
	var pal := BuildPalette.of(faction)
	if id == "windmill":
		var sails := MeshInstance3D.new()
		sails.name = "WindmillSails"
		sails.position = Vector3(0, 5.0, 1.05)
		sails.mesh = BldFrontier.windmill_sails(pal).build()
		sails.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.set_moving(sails, Vector3(0, 0, 1))
	var smoke: Array[Vector3] = fx["smoke"]
	for i in smoke.size():
		visual.add_smoke(make_smoke(smoke[i], float(fx["smoke_scale"])))
	if fx["light"] != null:
		visual.add_light(_make_light(fx["light"], pal.glow, float(fx["light_range"])))
	var picture := SpriteLibrary.building(id, lv, variant_seed)
	if not picture.is_empty():
		visual.set_sprite(picture, SpriteLibrary.building("construction"), 0.0,
			SpriteLibrary.building("windmill_sails") if id == "windmill" else {})
	if profile:
		print("PERF_BUILDING_VISUAL type=%s mesh_stage_ms=%.2f total_ms=%.2f" % [
			id, mesh_cache_usec / 1000.0, (Time.get_ticks_usec() - create_start_usec) / 1000.0])
	return visual


## Finished sites never use construction meshes. Build intermediate stages only on demand.
static func stage_mesh(id: String, faction: String, seed: int, lv: int, stage: int) -> ArrayMesh:
	var key := "%s|%s|%d|%d|%d" % [id, faction, seed, lv, stage]
	if not _cache.has(key):
		_cache[key] = _make_mesh(id, faction, seed, lv, stage)
	return _cache[key] as ArrayMesh


static func _make_mesh(id: String, style: String, seed: int, lv: int, stage: int) -> ArrayMesh:
	var p := BuildPalette.of(style)
	var fp: Vector2i = FOOTPRINTS[id]
	var k := MeshKit.new()
	k.shade_jitter = 0.03
	if stage <= 1:
		_construction(k, p, fp, stage, seed)
		return k.build()
	if not BldFrontier.build(k, id, p, seed, lv):
		BldOutland.build(k, id, p, seed, lv)
	if stage == 2:
		# nearly finished: the real building wrapped in scaffolding and builders' clutter
		var h: float = minf(k.get_aabb().end.y * 0.82, 6.0)
		BuildParts.scaffold(k, float(fp.x) - 0.12, float(fp.y) - 0.12, maxf(h, 1.4), p)
		BuildParts.crate(k, Vector3(float(fp.x) * 0.5 - 0.35, 0, float(fp.y) * 0.5 - 0.3), 0.4, p, 20.0)
	return k.build()


## Stage 0 = staked-out foundation, stage 1 = plinth, part-built walls and scaffolding.
static func _construction(k: MeshKit, p: BuildPalette, fp: Vector2i, stage: int,
		seed: int) -> void:
	var sx := float(fp.x)
	var sz := float(fp.y)
	k.box(Vector3(0, 0.03, 0), Vector3(sx * 0.94, 0.06, sz * 0.94), Color("8a7352"), Color("9c8460"))
	# stone footing around the outline
	var fw := 0.38
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(0, 0.14, s * (sz * 0.5 - fw * 0.5 - 0.06)), Vector3(sx * 0.9, 0.28, fw),
			p.stone, p.stone_top)
		k.box(Vector3(s * (sx * 0.5 - fw * 0.5 - 0.06), 0.14, 0), Vector3(fw, 0.28, sz * 0.9),
			p.stone, p.stone_top)
	if stage == 0:
		for sx2: float in [-1.0, 1.0]:
			for sz2: float in [-1.0, 1.0]:
				var x := sx2 * (sx * 0.5 - 0.12)
				var z := sz2 * (sz * 0.5 - 0.12)
				k.cylinder(Vector3(x, 0.0, z), 0.62, 0.05, p.wood_dark, 5)
				k.box(Vector3(x, 0.66, z), Vector3(0.12, 0.1, 0.12), p.cloth)
		for s: float in [-1.0, 1.0]:
			k.box(Vector3(0, 0.56, s * (sz * 0.5 - 0.12)), Vector3(sx - 0.24, 0.02, 0.02), p.plaster)
			k.box(Vector3(s * (sx * 0.5 - 0.12), 0.56, 0), Vector3(0.02, 0.02, sz - 0.24), p.plaster)
		BuildParts.log_stack(k, Vector3(0, 0, 0), p, 2)
		for i in 3:
			var h := RngUtil.hash01(seed, i, 6)
			k.box(Vector3(-sx * 0.22 + float(i) * 0.4, 0.34 + h * 0.05, sz * 0.18),
				Vector3(0.34, 0.3, 0.34), p.stone.darkened(0.05))
		return
	# stage 1: plinth, half-built walls, joists and scaffolding
	k.box(Vector3(0, 0.36, 0), Vector3(sx * 0.86, 0.3, sz * 0.86), p.stone, p.stone_top)
	for i in 5:
		var z := (float(i) - 2.0) * sz * 0.18
		k.box(Vector3(0, 0.58, z), Vector3(sx * 0.82, 0.14, 0.16), p.wood)
	var wall_h := 0.95
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(0, 0.51 + wall_h * 0.5, s * sz * 0.4), Vector3(sx * 0.78, wall_h, 0.2), p.plaster)
		k.box(Vector3(s * sx * 0.4, 0.51 + wall_h * 0.5, 0), Vector3(0.2, wall_h * 0.66, sz * 0.78),
			p.plaster)
	for sx2: float in [-1.0, 1.0]:
		for sz2: float in [-1.0, 1.0]:
			k.box(Vector3(sx2 * sx * 0.4, 1.4, sz2 * sz * 0.4), Vector3(0.18, 2.2, 0.18), p.timber)
	k.box(Vector3(0, 2.45, 0), Vector3(sx * 0.82, 0.16, 0.18), p.timber)
	BuildParts.scaffold(k, sx - 0.12, sz - 0.12, 2.9, p)
	BuildParts.crate(k, Vector3(sx * 0.5 - 0.35, 0, sz * 0.5 - 0.3), 0.4, p, 14.0)


## Smoke outlets, working light position and range for a type/variant.
static func _effects(id: String, seed: int, lv: int) -> Dictionary:
	var smoke: Array[Vector3] = []
	var light: Variant = null
	var light_range := 2.4
	var smoke_scale := 1.0
	match id:
		"house":
			var v: int = absi(seed) % 3
			var eave := 3.16 if v == 1 else 2.26
			smoke.append(Vector3(-0.95 if v == 1 else 0.95, eave + 1.6, -0.55))
			light = Vector3(0, 1.2, 1.5)
			light_range = 2.6
		"hearth":
			smoke.append(Vector3(-0.25, 0.9, 1.72))
			light = Vector3(-0.25, 0.7, 1.72)
			light_range = 4.2
			smoke_scale = 1.2
		"smelter":
			smoke.append(Vector3(0.72, 3.35, -0.72))
			light = Vector3(-0.15, 0.7, 1.15)
			light_range = 3.2
			smoke_scale = 1.3
		"workshop":
			smoke.append(Vector3(-1.5, 4.3, -0.7))
			light = Vector3(0.65, 0.8, 1.45)
			light_range = 2.8
		"machine_foundry":
			smoke.append(Vector3(-1.15, 5.8, -1.1))
			smoke.append(Vector3(0.35, 6.3, -1.1))
			light = Vector3(-0.2, 0.7, 1.2)
			light_range = 4.0
			smoke_scale = 1.5
		"campfire":
			smoke.append(Vector3(0, 0.75, 0))
			light = Vector3(0, 0.5, 0)
			light_range = 3.0
		"bandit_hut":
			smoke.append(Vector3(0.95, 3.2, -0.6))
			light = Vector3(0.25, 0.5, 1.6)
			light_range = 2.6
		"bandit_tent":
			light = Vector3(0, 0.6, 0.4)
			light_range = 1.6
		"wanderer_tent":
			smoke.append(Vector3(0, 1.9, 0))
			light = Vector3(0.05, 0.5, 1.28)
			light_range = 2.4
		"outpost":
			smoke.append(Vector3(0.62, 0.8, -0.55))
			light = Vector3(0.62, 0.5, -0.55)
			light_range = 2.4
		"bandit_tower":
			light = Vector3(-0.78, 3.9, 0.78)
			light_range = 2.4
		"machine_spire":
			light = Vector3(0, 4.35, 0)
			light_range = 3.4
		"machine_block":
			light = Vector3(0, 1.2, 0.9)
			light_range = 2.2
		"ruin_vault":
			light = Vector3(0, 0.9, 1.5)
			light_range = 2.2
		"trade_hall", "trade_stall", "windmill", "sky_dock", "watchtower", "storehouse", "trade_mast":
			light = Vector3(0, 1.2, 1.2)
			light_range = 2.2
	return {"smoke": smoke, "light": light, "light_range": light_range, "smoke_scale": smoke_scale}


static func _anchors(id: String, fp: Vector2i) -> Dictionary:
	var out := {
		&"door": Vector3(0, 0, float(fp.y) * 0.5 + 0.05),
		&"banner": Vector3(float(fp.x) * 0.5 - 0.3, 2.2, float(fp.y) * 0.5 - 0.35),
	}
	match id:
		"hearth":
			out[&"door"] = Vector3(-0.65, 0, 1.45)
			out[&"banner"] = Vector3(1.72, 2.2, 1.6)
		"windmill":
			out[&"door"] = Vector3(0, 0, 1.1)
		"sky_dock":
			out[&"mooring"] = Vector3(0, 8.0, 0)
			out[&"door"] = Vector3(0.55, 0, 1.75)
			out[&"banner"] = Vector3(-1.5, 3.0, 1.5)
		"trade_mast":
			out[&"mooring"] = Vector3(0, 7.55, 0)
			out[&"door"] = Vector3(0.3, 0, 0.95)
		"outpost":
			out[&"door"] = Vector3(0, 0, 1.4)
			out[&"banner"] = Vector3(-1.12, 2.4, 0.92)
		"wreck_airship":
			out[&"door"] = Vector3(0.2, 0.7, 0.55)
		"campfire", "wall", "palisade", "ruin_pillar":
			out[&"banner"] = Vector3(0, 1.6, 0)
	return out


static func make_smoke(pos: Vector3, scale: float) -> CPUParticles3D:
	var smoke := CPUParticles3D.new()
	smoke.name = "Smoke"
	smoke.position = pos
	smoke.amount = 12
	smoke.lifetime = 2.8
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 0.1 * scale
	smoke.direction = Vector3.UP
	smoke.spread = 14.0
	smoke.gravity = Vector3(0.25, 0.28, 0)
	smoke.initial_velocity_min = 0.3
	smoke.initial_velocity_max = 0.6
	smoke.scale_amount_min = 0.5 * scale
	smoke.scale_amount_max = 1.5 * scale
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.35))
	curve.add_point(Vector2(0.35, 1.0))
	curve.add_point(Vector2(1, 0.15))
	smoke.scale_amount_curve = curve
	var sphere := SphereMesh.new()
	sphere.radius = 0.16
	sphere.height = 0.32
	sphere.radial_segments = 6
	sphere.rings = 3
	smoke.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.79, 0.8, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	smoke.material_override = mat
	smoke.emitting = false
	return smoke


static func _make_light(pos: Vector3, col: Color, range_m: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = "WorkGlow"
	light.position = pos
	light.omni_range = range_m
	light.light_color = col
	light.light_energy = 1.1
	light.shadow_enabled = false
	light.visible = false
	return light
