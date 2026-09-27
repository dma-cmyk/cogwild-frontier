class_name SpriteLibrary
extends RefCounted
## Painted art generated with an image model and prepared by tools/art/process.py: character and
## machine chip sheets, portraits, the prop atlas, building pictures and terrain layers. Metadata
## lives in the DB tables "art/sprites", "art/portraits", "art/props", "art/buildings" and
## "art/terrain". Everything without a picture falls back to the procedural low-poly visuals.

## Galleries and tests switch this off to inspect the procedural fallback art.
static var enabled := true

const PAINTED_BLUE_HUE := 0.615
const UNIT_SHADER := "res://src/visual/shaders/sprite_unit.gdshader"
const PROP_SHADER := "res://src/visual/shaders/sprite_prop.gdshader"
const BUILDING_SHADER := "res://src/visual/shaders/sprite_building.gdshader"
## Standing height (metres) of a character chip figure per race.
const RACE_HEIGHT := {"human": 1.55, "sylvan": 1.65, "stoutkin": 1.3, "vulpin": 1.5}
## Figure height (metres) for machines; airships use their side-view length instead.
const MACHINE_HEIGHT := {"work_bot": 1.15, "walker": 2.5, "sentry": 1.7, "turret": 1.8, "machine_warden": 3.1,
	"scout_drone": 0.75, "repair_drone": 0.75, "war_drone": 0.95}
const AIRSHIP_LENGTH := 9.5

static var _textures: Dictionary = {}
static var _materials: Dictionary = {}
static var _portraits: Dictionary = {}
static var _icon_atlas_image: Image
static var _icon_atlas_texture: Texture2D
static var _icon_images: Dictionary = {}
static var _icon_textures: Dictionary = {}


static func clear_cache() -> void:
	_textures.clear()
	_materials.clear()
	_portraits.clear()
	_icon_atlas_image = null
	_icon_atlas_texture = null
	_icon_images.clear()
	_icon_textures.clear()
	SpriteUnitVisual._quad = null
	BuildingVisual._quad = null

## Release cache references that no live node in the view tree is using.
static func prune_unused(scene_root: Node) -> void:
	var live_materials: Dictionary = {}
	var live_textures: Dictionary = {}
	_retain_texture(_icon_atlas_texture, live_textures)
	for node: Node in scene_root.find_children("*", "", true, false):
		if node is CanvasItem:
			_retain_material((node as CanvasItem).material, live_materials, live_textures)
		if node is GeometryInstance3D:
			_retain_material((node as GeometryInstance3D).material_override, live_materials, live_textures)
		if node is MeshInstance3D:
			var mesh_instance: MeshInstance3D = node as MeshInstance3D
			if mesh_instance.mesh != null:
				for surface: int in mesh_instance.mesh.get_surface_count():
					_retain_material(mesh_instance.get_active_material(surface), live_materials, live_textures)
		if node is TextureRect:
			_retain_texture((node as TextureRect).texture, live_textures)
		elif node is TextureButton:
			var button: TextureButton = node as TextureButton
			for texture: Texture2D in [button.texture_normal, button.texture_pressed, button.texture_hover,
					button.texture_disabled, button.texture_focused]:
				_retain_texture(texture, live_textures)
		elif node is TextureProgressBar:
			var bar: TextureProgressBar = node as TextureProgressBar
			for texture: Texture2D in [bar.texture_under, bar.texture_over, bar.texture_progress]:
				_retain_texture(texture, live_textures)
		elif node is Sprite2D:
			_retain_texture((node as Sprite2D).texture, live_textures)
		elif node is Sprite3D:
			_retain_texture((node as Sprite3D).texture, live_textures)
		elif node is AnimatedSprite2D:
			var sprite: AnimatedSprite2D = node as AnimatedSprite2D
			if sprite.sprite_frames != null:
				for animation: StringName in sprite.sprite_frames.get_animation_names():
					for frame_index: int in sprite.sprite_frames.get_frame_count(animation):
						_retain_texture(sprite.sprite_frames.get_frame_texture(animation, frame_index), live_textures)
	for key: Variant in _materials.keys():
		var material: Variant = _materials[key]
		if material is ShaderMaterial and not live_materials.has((material as ShaderMaterial).get_instance_id()):
			_materials.erase(key)
	_prune_texture_cache(_textures, live_textures)
	_prune_texture_cache(_portraits, live_textures)
	_prune_texture_cache(_icon_textures, live_textures)


static func _retain_material(material: Material, live_materials: Dictionary, live_textures: Dictionary) -> void:
	if not material is ShaderMaterial:
		return
	var shader_material: ShaderMaterial = material as ShaderMaterial
	live_materials[shader_material.get_instance_id()] = true
	for parameter: String in ["sheet", "atlas", "tex", "glow_tex", "layers", "terrain_tex"]:
		_retain_texture(shader_material.get_shader_parameter(parameter), live_textures)


static func _retain_texture(value: Variant, live_textures: Dictionary) -> void:
	if value is AtlasTexture:
		var atlas_texture: AtlasTexture = value as AtlasTexture
		live_textures[atlas_texture.get_instance_id()] = true
		_retain_texture(atlas_texture.atlas, live_textures)
	elif value is Texture:
		live_textures[(value as Texture).get_instance_id()] = true


static func _prune_texture_cache(cache: Dictionary, live_textures: Dictionary) -> void:
	for key: Variant in cache.keys():
		var texture: Variant = cache[key]
		if texture == null or not live_textures.has((texture as Object).get_instance_id()):
			cache.erase(key)


static func texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if not _textures.has(path):
		var texture_exists := ResourceLoader.exists(path)
		var profile := World.profile_chunks()
		var load_start_usec: int = Time.get_ticks_usec() if profile else 0
		_textures[path] = load(path) if texture_exists else null
		if profile:
			print("PERF_TEXTURE_FIRST_USE path=%s exists=%s load_ms=%.2f" % [
				path, texture_exists, (Time.get_ticks_usec() - load_start_usec) / 1000.0])
		# Jobs reuse this shared atlas intermittently; do not decode it again after pruning.
		if path == str(DB.get_def("art/icons", "res_wood").get("texture", "")):
			_icon_atlas_texture = _textures[path] as Texture2D
	return _textures[path] as Texture2D


# --- characters and machines -----------------------------------------------------------------

## Look group of a person from what they wear and carry (so re-equipping changes the sprite).
static func look_for(dna: Dictionary) -> String:
	var weapon := str(dna.get("weapon", "none"))
	var offhand := str(dna.get("offhand", "none"))
	var armor := str(dna.get("armor", "none"))
	if weapon in ["bow", "crossbow"]:
		return "ranger"
	if weapon in ["sword", "spear", "mace"] or offhand in ["shield", "buckler"] or armor in ["chain", "plate"]:
		return "fighter"
	if str(dna.get("outfit", "")) == "robe":
		return "scholar"
	if weapon in ["wrench", "rifle", "pistol"] or str(dna.get("headgear", "")) == "goggles":
		return "engineer"
	if weapon == "staff" or offhand == "book":
		return "scholar"
	return "worker"


## Chip sheet id for a unit. `hints` may carry the unit's archetype, role and whether it is named.
static func chip_id(dna: Dictionary, hints: Dictionary = {}) -> String:
	var kind := str(dna.get("kind", "character"))
	var archetype := str(hints.get("archetype", dna.get("unit", dna.get("archetype", ""))))
	match kind:
		"robot":
			if archetype in ["walker", "sentry", "turret", "machine_warden"]:
				return archetype
			return "work_bot"
		"drone":
			return archetype if archetype in ["scout_drone", "repair_drone", "war_drone"] else "scout_drone"
		"airship":
			if archetype == "trader_airship" or str(dna.get("faction_style", "")) == "merchant":
				return "trader_airship"
			return "cargo_airship"
	var gender := str(dna.get("gender", "male"))
	var g := "f" if gender == "female" else "m"
	if gender not in ["female", "male"]:
		g = "f" if int(dna.get("seed", 0)) % 2 == 0 else "m"
	var role := str(hints.get("role", ""))
	var weapon := str(dna.get("weapon", "none"))
	if str(dna.get("faction_style", "")) == "bandit" or role.begins_with("bandit"):
		if role == "bandit_captain" or bool(hints.get("named", false)) or weapon == "sword":
			return "bandit_captain"
		if role == "bandit_archer" or weapon in ["bow", "crossbow"]:
			return "bandit_archer"
		return "bandit_" + g
	return "%s_%s_%s" % [str(dna.get("race", "human")), look_for(dna), g]


## Number of loadable painted looks for this unit's base sheet.
static func variant_count(dna: Dictionary, hints: Dictionary = {}) -> int:
	var base_id := chip_id(dna, hints)
	var count := 0
	# existence only: loading every variant's sheet here would put unused textures in video memory
	for variant: int in range(6):
		var variant_id := _variant_id(base_id, variant)
		var entry := DB.get_def("art/sprites", variant_id)
		if entry.is_empty() or not ResourceLoader.exists(str(entry.get("texture", ""))):
			continue
		if str(dna.get("kind", "character")) == "character":
			var portrait_entry := DB.get_def("art/portraits", variant_id)
			if portrait_entry.is_empty() or not ResourceLoader.exists(str(portrait_entry.get("texture", ""))):
				continue
		count += 1
	return count


## The founder's explicit choice (dna["art_variant"]) wins; everyone else gets a stable look derived
## from their appearance DNA, so generation does not draw extra random numbers.
static func art_variant(dna: Dictionary, hints: Dictionary = {}) -> int:
	var count := variant_count(dna, hints)
	if count <= 1:
		return 0
	if dna.has("art_variant"):
		return posmod(int(dna["art_variant"]), count)
	var base_id := chip_id(dna, hints)
	var identity := "%s|%s|%s|%s|%s|%s" % [
		str(dna.get("seed", 0)), str(dna.get("hair", "")), str(dna.get("hair_color", "")),
		str(dna.get("skin", "")), str(dna.get("gender", "")), base_id]
	# People from saves predating explicit colony assignment retain their exact two-look mapping.
	return posmod(hash(identity), mini(count, 2))


static func _variant_id(base_id: String, variant: int) -> String:
	if variant <= 0:
		return base_id
	return "%s@v%d" % [base_id, variant + 1]

static func _variant_entry(table: String, base_id: String, variant: int) -> Dictionary:
	var entry := DB.get_def(table, _variant_id(base_id, variant))
	if entry.is_empty() and variant != 0:
		entry = DB.get_def(table, base_id)
	return entry

## "art/sprites" entry for a unit, or {} when it has no painted sheet.
static func chip(dna: Dictionary, hints: Dictionary = {}) -> Dictionary:
	if not enabled:
		return {}
	var id := chip_id(dna, hints)
	var entry := _variant_entry("art/sprites", id, art_variant(dna, hints))
	if entry.is_empty() or texture(str(entry.get("texture", ""))) == null:
		return {}
	return entry


## Card size in metres (width, height) of one chip cell for this unit.
static func chip_cell_size(entry: Dictionary, dna: Dictionary, hints: Dictionary = {}) -> Vector2:
	var cell: Array = entry.get("cell", [128, 128])
	var cw := float(cell[0])
	var chh := float(cell[1])
	var kind := str(dna.get("kind", "character"))
	var metres_per_px: float
	if kind == "airship":
		metres_per_px = AIRSHIP_LENGTH * float(dna.get("scale", 1.0)) / maxf(1.0, float(entry.get("width_px", cw)))
	else:
		var h: float
		if kind == "character":
			h = float(RACE_HEIGHT.get(str(dna.get("race", "human")), 1.5)) * float(dna.get("height", 1.0))
			if str(entry.get("id", "")) == "bandit_captain":
				h *= 1.12
		else:
			h = float(MACHINE_HEIGHT.get(chip_id(dna, hints), 1.2)) * float(dna.get("scale", 1.0))
		metres_per_px = h / maxf(1.0, float(entry.get("height_px", chh)))
	return Vector2(cw, chh) * metres_per_px


## Hue rotation (turns) that turns the painted company blue into the unit's faction colour.
static func hue_shift_for(dna: Dictionary) -> float:
	var style := str(dna.get("faction_style", "neutral"))
	if style in ["bandit", "ancient"]:
		return 0.0
	var c := Color(str(dna.get("faction_color", "#3a5da8")))
	if c.s < 0.12:
		return 0.0
	var d := c.h - PAINTED_BLUE_HUE
	if absf(d) < 0.02:
		return 0.0
	return wrapf(d, -0.5, 0.5)


static func unit_material(entry: Dictionary) -> ShaderMaterial:
	var key := "unit:" + str(entry.get("id", ""))
	if _materials.has(key):
		return _materials[key] as ShaderMaterial
	var m := ShaderMaterial.new()
	m.shader = load(UNIT_SHADER)
	var cell: Array = entry.get("cell", [128, 128])
	var anchor: Array = entry.get("anchor", [64, 124])
	m.set_shader_parameter("sheet", texture(str(entry.get("texture", ""))))
	m.set_shader_parameter("grid", Vector2(float(entry.get("cols", 3)), float(entry.get("rows", 4))))
	m.set_shader_parameter("anchor", Vector2(float(anchor[0]) / float(cell[0]), float(anchor[1]) / float(cell[1])))
	m.set_shader_parameter("depth_bias", 0.9 if str(entry.get("anchor_mode", "")) == "center" else 0.45)
	_materials[key] = m
	return m


## Front-facing standing frame of a chip as a UI texture (portrait fallback for machines).
static func chip_front_frame(entry: Dictionary) -> Texture2D:
	var tex := texture(str(entry.get("texture", "")))
	if tex == null:
		return null
	var cell: Array = entry.get("cell", [128, 128])
	var cols := int(entry.get("cols", 3))
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(float(cell[0]) * float(mini(1, cols - 1)), 0.0, float(cell[0]), float(cell[1]))
	return at


## Painted portrait for a unit: the generated bust for people, the chip's front frame for
## machines, or null (caller renders the procedural fallback).
static func portrait(dna: Dictionary, hints: Dictionary = {}) -> Texture2D:
	if not enabled:
		return null
	var id := chip_id(dna, hints)
	var variant := art_variant(dna, hints)
	var key := _variant_id(id, variant)
	if _portraits.has(key):
		return _portraits[key] as Texture2D
	var tex: Texture2D = null
	var entry := _variant_entry("art/portraits", id, variant)
	if not entry.is_empty():
		tex = texture(str(entry.get("texture", "")))
	if tex == null:
		var c := chip(dna, hints)
		if not c.is_empty():
			tex = chip_front_frame(c)
	_portraits[key] = tex
	return tex


# --- inventory / resource icons --------------------------------------------------------------

## Painted icon (item shape or res_* resource) scaled to `px`, or null when not painted.
static func icon_image(icon_id: String, px: int) -> Image:
	if not enabled or px <= 0:
		return null
	var key := "%s:%d" % [icon_id, px]
	if _icon_images.has(key):
		return _icon_images[key] as Image
	var entry := DB.get_def("art/icons", icon_id)
	var img: Image = null
	if not entry.is_empty():
		if _icon_atlas_image == null:
			var tex := texture(str(entry.get("texture", "")))
			if tex != null:
				_icon_atlas_image = tex.get_image()
				if _icon_atlas_image.is_compressed():
					_icon_atlas_image.decompress()
				_icon_atlas_image.convert(Image.FORMAT_RGBA8)
		if _icon_atlas_image != null:
			var r: Array = entry.get("rect", [0, 0, 128, 128])
			img = _icon_atlas_image.get_region(Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])))
			img.resize(px, px, Image.INTERPOLATE_LANCZOS)
	_icon_images[key] = img
	return img


## Painted icon as a texture region of the icon atlas (world cards: carried goods, loot).
static func icon_texture(icon_id: String) -> Texture2D:
	if not enabled:
		return null
	if _icon_textures.has(icon_id):
		return _icon_textures[icon_id] as Texture2D
	var entry := DB.get_def("art/icons", icon_id)
	var at: AtlasTexture = null
	if not entry.is_empty():
		var tex := texture(str(entry.get("texture", "")))
		if tex != null:
			var r: Array = entry.get("rect", [0, 0, 128, 128])
			at = AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	_icon_textures[icon_id] = at
	return at


# --- props ---------------------------------------------------------------------------------

## Atlas variants of a world prop: [{rect, height_m, ...}], empty when not painted.
static func prop_variants(prop_id: String) -> Array:
	if not enabled:
		return []
	return DB.get_def("art/props", prop_id).get("variants", []) as Array


static func prop_atlas() -> Texture2D:
	for id: String in DB.ids("art/props"):
		return texture(str(DB.get_def("art/props", id).get("texture", "")))
	return null


static func prop_atlas_size() -> Vector2:
	for id: String in DB.ids("art/props"):
		var s: Array = DB.get_def("art/props", id).get("atlas_size", [2048, 1024])
		return Vector2(float(s[0]), float(s[1]))
	return Vector2(2048, 1024)


static func prop_material(sway: float) -> ShaderMaterial:
	var key := "prop:%.2f" % sway
	if _materials.has(key):
		return _materials[key] as ShaderMaterial
	var m := ShaderMaterial.new()
	m.shader = load(PROP_SHADER)
	m.set_shader_parameter("atlas", prop_atlas())
	m.set_shader_parameter("sway", sway)
	m.set_shader_parameter("receive_shadow", 0.6)
	_materials[key] = m
	return m


# --- buildings -----------------------------------------------------------------------------

## Picture entry for a building type / level / variant, or {}.
static func building(type_id: String, level: int = 1, variant: int = 0) -> Dictionary:
	if not enabled:
		return {}
	var entry: Dictionary = {}
	if type_id == "hearth":
		entry = DB.get_def("art/buildings", "hearth@%d" % clampi(level, 1, 3))
	elif type_id == "house" and posmod(variant, 2) == 1:
		entry = DB.get_def("art/buildings", "house@v1")
	if entry.is_empty():
		entry = DB.get_def("art/buildings", type_id)
	if entry.is_empty() or texture(str(entry.get("texture", ""))) == null:
		return {}
	return entry


static func building_material(entry: Dictionary, footprint: Vector2i) -> ShaderMaterial:
	var key := "bld:%s:%d:%d" % [str(entry.get("id", "")), footprint.x, footprint.y]
	if _materials.has(key):
		return _materials[key] as ShaderMaterial
	var m := ShaderMaterial.new()
	m.shader = load(BUILDING_SHADER)
	m.set_shader_parameter("tex", texture(str(entry.get("texture", ""))))
	var glow := texture(str(entry.get("glow", "")))
	if glow != null:
		m.set_shader_parameter("glow_tex", glow)
	m.set_shader_parameter("anchor", building_anchor(entry))
	m.set_shader_parameter("half_size", Vector2(footprint) * 0.5)
	m.set_shader_parameter("receive_shadow", 0.0)
	_materials[key] = m
	return m


## Footprint centre inside the picture (0..1): the base diamond's middle, assuming the painted
## isometric footprint is twice as wide as it is tall.
static func building_anchor(entry: Dictionary) -> Vector2:
	var size: Array = entry.get("size_px", [512, 512])
	var bw := float(entry.get("base_w_px", size[0]))
	var cx := float(entry.get("base_cx_px", float(size[0]) * 0.5))
	var bottom := float(entry.get("base_bottom_px", size[1]))
	return Vector2(cx / float(size[0]), (bottom - bw * 0.25) / float(size[1]))


## Card size in metres for a building picture on a footprint (camera at 45° yaw).
static func building_card_size(entry: Dictionary, footprint: Vector2i) -> Vector2:
	var size: Array = entry.get("size_px", [512, 512])
	var world_w := float(footprint.x + footprint.y) / sqrt(2.0)
	var m_per_px := world_w / maxf(1.0, float(entry.get("base_w_px", size[0])))
	return Vector2(float(size[0]), float(size[1])) * m_per_px
