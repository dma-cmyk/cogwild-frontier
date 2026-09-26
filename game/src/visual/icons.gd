class_name Icons
extends RefCounted
## SVG icon loader and deterministic item icon renderer. Item icons draw the painted inventory art
## (SpriteLibrary "art/icons") inside the quality frame; shapes without a painting use the SVG glyph.

const REQUIRED_IDS := [
	"res_wood", "res_stone", "res_metal", "res_ore", "res_gold", "res_food", "res_energy", "res_pop",
	"cmd_move", "cmd_attack", "cmd_defend", "cmd_explore", "cmd_build", "cmd_gather", "cmd_patrol", "cmd_auto", "cmd_retreat", "cmd_escort", "cmd_stop", "cmd_farm", "cmd_trade", "cmd_cancel",
	"ui_home", "ui_buildings", "ui_people", "ui_target", "ui_search", "ui_pause", "ui_play", "ui_fast", "ui_faster", "ui_sun", "ui_moon", "ui_save", "ui_load", "ui_menu", "ui_close", "ui_squad", "ui_bell", "ui_crest", "ui_skull", "ui_star", "ui_heart", "ui_bolt", "ui_chest", "ui_scroll", "ui_gear",
	"class_shield", "class_spear", "class_archer", "class_scout", "class_engineer", "class_commander", "class_worker", "class_robot", "class_drone", "class_airship", "class_medic", "class_merchant",
	"zone_logging", "zone_mining", "zone_forage", "zone_farm", "zone_clear",
	"bld_hearth", "bld_house", "bld_storehouse", "bld_workshop", "bld_smelter", "bld_windmill", "bld_sky_dock", "bld_watchtower", "bld_wall", "bld_outpost", "bld_farm_plot", "bld_road",
	"poi_ruins", "poi_bandit", "poi_machine", "poi_trade", "poi_wanderer", "poi_wreck", "poi_crystal", "poi_ore"
]
const SHAPES := ["sword", "dagger", "axe", "spear", "bow", "crossbow", "hammer", "mace", "staff", "rifle", "pistol", "wrench", "pickaxe", "shield", "vest", "coat", "plate", "helmet", "boots", "gloves", "scope", "lantern", "compass", "goggles", "gear", "servo", "sensor", "core", "plating", "propeller", "envelope", "engine", "orb", "idol", "relic", "amulet", "ring", "tonic", "ration", "repair_kit", "shard", "ingot", "timber", "pelt", "book", "map"]
static var _icon_cache: Dictionary = {}
static var _item_cache: Dictionary = {}
static var _warned_missing: Dictionary = {}

static func get_icon(id: String) -> Texture2D:
	if _icon_cache.has(id):
		return _icon_cache[id] as Texture2D
	var path := "res://assets/icons/%s.svg" % id
	var tex := load(path) as Texture2D
	if tex == null:
		if not _warned_missing.has(id):
			_warned_missing[id] = true
			push_warning("Icons: missing icon '%s', using fallback" % id)
		tex = _raster_svg(_fallback_svg(id), 64)
	_icon_cache[id] = tex
	return tex

static func item_icon(item: Dictionary, size: int = 64) -> Texture2D:
	var app_variant: Variant = item.get("appearance", item)
	var app: Dictionary = app_variant as Dictionary if app_variant is Dictionary else {}
	if not app.has("quality") and item.has("quality"):
		app = app.duplicate()
		app["quality"] = item["quality"]
	var uid := str(item.get("uid", item.get("id", "")))
	var key := "%s|%d|%s" % [uid, size, str(app)]
	if _item_cache.has(key):
		return _item_cache[key] as Texture2D
	var painted := SpriteLibrary.icon_image(str(app.get("shape", "")), int(round(size * 0.82)))
	var tex: Texture2D
	if painted != null:
		var frame := Image.new()
		if frame.load_svg_from_string(_item_svg(app, false), float(size) / 64.0) != OK:
			frame = Image.create(size, size, false, Image.FORMAT_RGBA8)
		frame.convert(Image.FORMAT_RGBA8)
		var at := Vector2i((frame.get_width() - painted.get_width()) / 2, (frame.get_height() - painted.get_height()) / 2)
		frame.blend_rect(painted, Rect2i(Vector2i.ZERO, painted.get_size()), at)
		tex = ImageTexture.create_from_image(frame)
	else:
		tex = _raster_svg(_item_svg(app), size)
	_item_cache[key] = tex
	return tex

static func quality_color(quality: String) -> Color:
	var fallback := {"junk": Color("777d87"), "crude": Color("8a8d93"), "common": Color("c7cbd1"), "fine": Color("5fc56d"), "uncommon": Color("5fc56d"), "rare": Color("56a9e8"), "epic": Color("a274e8"), "legendary": Color("e6ad46"), "anomalous": Color("e85ec5")}
	var db: Node = Engine.get_main_loop().root.get_node_or_null("DB") if Engine.get_main_loop() != null else null
	if db != null and db.has_method("has_def") and db.has_def("items/qualities", quality):
		var def: Dictionary = db.get_def("items/qualities", quality)
		var c: Variant = def.get("color", "")
		if c is String and String(c).begins_with("#"):
			return Color(String(c))
	return fallback.get(quality.to_lower(), Color("8c929b"))
static func _raster_svg(svg: String, size: int) -> Texture2D:
	var image := Image.new()
	var err := image.load_svg_from_string(svg, float(size) / 64.0)
	if err != OK:
		image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	return ImageTexture.create_from_image(image)

static func _fallback_svg(id: String) -> String:
	var hue := float(abs(id.hash()) % 360)
	var c := Color.from_hsv(hue / 360.0, 0.45, 0.75).to_html(false)
	return "<svg xmlns='http://www.w3.org/2000/svg' width='64' height='64' viewBox='0 0 64 64'><path d='M6 6h52v52H6z' rx='8' fill='#1a1f2b' stroke='#d9b04c' stroke-width='3'/><path d='M18 44L32 16l14 28-14-7z' fill='#%s' stroke='#f1e3bd' stroke-width='3'/></svg>" % c

static func _item_svg(app: Dictionary, with_glyph: bool = true) -> String:
	var shape := str(app.get("shape", "orb"))
	if not SHAPES.has(shape): shape = "orb"
	var primary := _hex(app.get("primary", "#5a78a8"), "#5a78a8")
	var secondary := _hex(app.get("secondary", "#b9a06c"), "#b9a06c")
	var accent := _hex(app.get("accent", "#f1d260"), "#f1d260")
	var glow := clampf(float(app.get("glow", 0.0)), 0.0, 1.0)
	var quality := str(app.get("quality", "common"))
	var frame := quality_color(quality).to_html(false)
	var glyph := _shape_svg(shape, primary, secondary, accent) if with_glyph else ""
	# The halo sits above the backing, not hidden beneath its opaque centre.
	var halo := "<defs><radialGradient id='halo'><stop stop-color='#%s' stop-opacity='%f'/><stop offset='1' stop-color='#%s' stop-opacity='0'/></radialGradient></defs><circle cx='32' cy='32' r='26' fill='url(#halo)'/>" % [accent, glow * 0.8, accent] if glow > 0.0 else ""
	var ornate := "<path d='M5 16V5h11M48 5h11v11M5 48v11h11M48 59h11V48' fill='none' stroke='#%s' stroke-width='3'/><path d='M32 2l3 3-3 3-3-3zM32 56l3 3-3 3-3-3z' fill='#%s'/>" % [frame, frame] if quality in ["legendary", "anomalous"] else ""
	return "<svg xmlns='http://www.w3.org/2000/svg' width='64' height='64' viewBox='0 0 64 64'><rect x='4' y='4' width='56' height='56' rx='7' fill='#1a1f2b' stroke='#%s' stroke-width='2'/>%s<g stroke='#1a1f2b' stroke-width='2.5' stroke-linejoin='round' stroke-linecap='round'>%s</g>%s</svg>" % [frame, halo, glyph, ornate]

static func _hex(value: Variant, fallback: String) -> String:
	var s := str(value)
	return s.trim_prefix("#") if s.begins_with("#") and s.length() >= 7 else fallback.trim_prefix("#")

## Each shape has a separate silhouette; three paths are main material, trim, and accent.
static func _shape_svg(shape: String, a: String, b: String, c: String) -> String:
	var main: String
	var trim: String
	var accent: String
	match shape:
		"sword":
			main = "M45 9l7 2-2 8-25 26-7-7z"
			trim = "M15 34l16 16-5 4-6-6-9 8-4-5 9-8-5-5z"
			accent = "M45 14l-20 22 3-8z"
		"dagger":
			main = "M41 14l6 18-16 11-6-7z"
			trim = "M20 32l17 16-5 4-6-6-9 8-5-5 9-9-5-4z"
			accent = "M41 20l-5 14-5 2z"
		"axe":
			main = "M22 13q17 6 27-3l6 20q-15 8-30-5z"
			trim = "M25 16l7 3-13 37-8-3z"
			accent = "M48 10l7 20-7 3-6-19z"
		"spear":
			main = "M48 7l6 20-15 4-7-7z"
			trim = "M36 25l5 5-27 27-6-5z"
			accent = "M48 13l-9 11 5 1z"
		"bow":
			main = "M17 8Q62 32 17 56l5-12q26-12 0-24z"
			trim = "M16 10h4v44h-4zM12 30h38v5H12z"
			accent = "M44 25l12 8-12 7z"
		"crossbow":
			main = "M10 23q22-24 44 0l-3 12q-19-22-38 0z"
			trim = "M27 22h10v31H27zM12 29h40v4H12z"
			accent = "M30 11h5v30h-5zM32 8l6 9H26z"
		"hammer":
			main = "M14 12h38v17H14z"
			trim = "M27 29h9v26h-9zM14 12h7v17h-7z"
			accent = "M43 12h9v17h-9z"
		"mace":
			main = "M28 8l7 4 9-3 2 9 7 5-7 7-1 9-10-3-9 4-3-10-7-6 8-6z"
			trim = "M29 34l7 3-11 20-8-4z"
			accent = "M31 19h10v10H31z"
		"staff":
			main = "M31 23h6l-7 34h-7zM23 13l5-6 16 1 5 12-7 10H28l-8-9z"
			trim = "M26 29h13v6H26z"
			accent = "M34 10l10 9-10 9-9-9z"
		"rifle":
			main = "M9 25h44v8H28v8H18v-9H9z"
			trim = "M8 29h18v8l-9 1-3 12-8-2zM33 32h16v5H33z"
			accent = "M28 17h17v7H28z"
		"pistol":
			main = "M13 19h39v13H27l-2 10H15z"
			trim = "M14 30h14l-7 23H10z"
			accent = "M42 19h10v8H42z"
		"wrench":
			main = "M37 10l-1 12 8 4 9-8q5 18-12 21L20 55l-8-9 22-19q-8-11 3-17z"
			trim = "M17 44l6 6-4 4-6-6z"
			accent = "M27 34l4 4-8 7-4-4z"
		"pickaxe":
			main = "M8 27Q29 1 55 21L38 16l-8 8-6-4z"
			trim = "M28 20l7 4-17 32-7-4z"
			accent = "M28 15l9 4-4 8-9-4z"
		"shield":
			main = "M13 15l19-7 19 7v19q-3 13-19 21Q16 47 13 34z"
			trim = "M32 14l-12 5v14q2 10 12 15z"
			accent = "M32 24l7 9-7 10-7-10z"
		"vest":
			main = "M19 13h9l4 8 4-8h9v14l-5 3v22H24V30l-5-3z"
			trim = "M28 13l4 8 4-8-4 26zM25 41h14v5H25z"
			accent = "M31 29h3v4h-3zM31 36h3v4h-3z"
		"coat":
			main = "M22 10h20l11 20-8 6-5-10 7 29H34l-2-9-2 9H17l7-29-5 10-8-6z"
			trim = "M24 11l8 5 8-5-8 22zM22 37h20v5H22z"
			accent = "M30 36h5v7h-5z"
		"plate":
			main = "M23 12l9 6 9-6 10 6 4 14-11 1-4 19H24l-4-19-11-1 4-14z"
			trim = "M23 22l9 5 9-5-3 15-6 5-6-5zM24 45h16v7H24z"
			accent = "M29 26h6v9h-6z"
		"helmet":
			main = "M13 43V29q0-19 19-19t19 19v14l-12 8V37H25v14z"
			trim = "M29 10h6v20h-6zM13 29h38v7H13z"
			accent = "M29 40h6v13h-6z"
		"boots":
			main = "M12 15h16v24l9 6v8H10V41zM34 11h15v23l8 6v8H33V35z"
			trim = "M12 15h16v6H12zM34 11h15v6H34zM10 49h27v5H10z"
			accent = "M18 26h9v5h-9zM40 22h8v5h-8z"
		"gloves":
			main = "M15 49l-6-20 6-3 5 10V16l6-1 2 18 3-19 6 1-2 21 6-13 6 3-5 22-11 7z"
			trim = "M16 46l24-3-2 12-17 2z"
			accent = "M24 46h9v6h-9z"
		"scope":
			main = "M15 24l30-12 9 21-31 12z"
			trim = "M15 24l8 21-8 3-9-21zM39 15l8 21 7-3-9-21zM28 41h8v13h-8z"
			accent = "M11 29l4-2 6 15-5 2z"
		"lantern":
			main = "M21 20h22l5 9-4 23H20l-4-23z"
			trim = "M24 20V9h16v11h-5v-6h-6v6zM17 26h30v6H17zM19 49h26v5H19z"
			accent = "M24 33h16v14H24z"
		"compass":
			main = "M25 9h14v8l13 10v18L32 56 12 45V27l13-10z"
			trim = "M25 13v7h14v-7zM32 21l16 11v11l-16 9-16-9V32z"
			accent = "M40 27l-5 15-11 5 5-15z"
		"goggles":
			main = "M9 23h18l5 5 5-5h18v20H37l-5-6-5 6H9z"
			trim = "M6 27h5v12H6zM53 27h5v12h-5zM27 29h10v7H27z"
			accent = "M14 28h10v10H14zM40 28h10v10H40z"
		"gear":
			main = "M26 9h12v8l6 3 7-4 6 11-7 5v6l5 5-8 10-7-5-7 3-2 7-12-3 1-9-5-5-8 1-2-12 8-3 3-6-3-7 10-6z"
			trim = "M24 26h16v16H24z"
			accent = "M29 30h7v8h-7z"
		"servo":
			main = "M15 27h28v23H15zM21 17h16v10H21z"
			trim = "M27 10h6v10h-6zM9 32h6v14H9zM43 32h7v14h-7z"
			accent = "M21 9h25v7H21zM23 34h12v9H23z"
		"sensor":
			main = "M10 22l12-8h23l10 11v22H10z"
			trim = "M17 18l-3-9h6l3 9zM14 44h37v8H14z"
			accent = "M26 22h16l6 8-6 9H26l-6-9z"
		"core":
			main = "M22 10h20l10 15v17L42 54H22L12 42V25z"
			trim = "M22 10h7v44h-7zM35 10h7v44h-7z"
			accent = "M32 19l12 14-12 14-12-14z"
		"plating":
			main = "M13 16l30-5 10 33-31 10z"
			trim = "M18 20l20-3 7 22-21 5z"
			accent = "M18 20h4v4h-4zM37 17h4v4h-4zM24 43h4v4h-4zM44 39h4v4h-4z"
		"propeller":
			main = "M29 29Q10 24 12 11q17-5 20 19M35 29q5-19 18-17 5 17-19 20M35 35q19 5 17 18-17 5-20-19M29 35Q10 40 12 53q17 5 20-19"
			trim = "M25 25h14v14H25z"
			accent = "M29 29h6v6h-6z"
		"envelope":
			main = "M9 20Q31 1 55 20v13Q32 47 9 33z"
			trim = "M26 11h12v30H26zM21 44h22l-5 9H26zM22 37h3v9h-3zM40 37h3v9h-3z"
			accent = "M11 24h42v6H11z"
		"engine":
			main = "M15 25h33v26H15zM10 30h5v16h-5zM48 30h7v16h-7z"
			trim = "M19 12h8v17h-8zM35 9h8v20h-8zM19 47h25v7H19z"
			accent = "M24 32h15v10H24z"
		"orb":
			main = "M32 11C4 11 4 51 32 51s28-40 0-40z"
			trim = "M13 29q19 8 38 0v6q-19 8-38 0zM20 49h24v5H20z"
			accent = "M24 18h9l-5 9h-9z"
		"idol":
			main = "M25 9h14l6 10-7 12 10 13v10H16V44l10-13-7-12z"
			trim = "M24 35h16v7H24zM15 50h34v6H15z"
			accent = "M24 18h6v6h-6zM34 18h6v6h-6z"
		"relic":
			main = "M20 11h26l-2 12 6 6-5 25H16l5-15-5-11z"
			trim = "M24 15h17v6H24zM19 47h26v6H19z"
			accent = "M32 24l9 10-9 10-8-10z"
		"amulet":
			main = "M27 30h10l10 12-15 15-15-15z"
			trim = "M18 9h5l9 23 9-23h5L34 38h-4z"
			accent = "M32 36l8 7-8 8-8-8z"
		"ring":
			main = "M32 18C6 18 6 55 32 55s26-37 0-37zm0 8c17 0 17 22 0 22s-17-22 0-22z"
			trim = "M19 17l6-8h14l6 8-13 16z"
			accent = "M26 12h12l3 5-9 9-9-9z"
		"tonic":
			main = "M26 15h12v11l9 11v16H17V37l9-11z"
			trim = "M24 10h16v9H24z"
			accent = "M21 36h22v13H21z"
		"ration":
			main = "M12 26q16-25 39-6l4 14-8 14H16z"
			trim = "M11 33l22 9 21-8-7 17H17z"
			accent = "M24 18l5 9-4 3-6-9zM36 16l6 9-4 3-6-9z"
		"repair_kit":
			main = "M11 23h42v29H11z"
			trim = "M23 23V12h18v11h-5v-6h-8v6zM10 31h44v7H10z"
			accent = "M28 29h8v17h-8zM23 34h18v7H23z"
		"shard":
			main = "M35 8l14 15-7 27-24 6-3-20z"
			trim = "M35 8l-6 30 13 12 7-27z"
			accent = "M19 35l10 3-11 18z"
		"ingot":
			main = "M15 20l29-8 11 26-10 12-32 3-5-17z"
			trim = "M15 20l8 20 32-2-11-26z"
			accent = "M23 22l15-4 3 7-15 4z"
		"timber":
			main = "M10 30l32-18 13 9v17L24 55 10 46z"
			trim = "M10 30l14 10v15L10 46zM24 40l31-19v7L24 46z"
			accent = "M14 36l7 5v7l-7-5z"
		"pelt":
			main = "M24 10h16l4 10 10-2-3 14-7 2 8 18-14-3-6 8-6-8-14 3 8-18-7-2-3-14 10 2z"
			trim = "M27 23h10l5 15-10 11-10-11z"
			accent = "M26 13h4v5h-4zM34 13h4v5h-4z"
		"book":
			main = "M14 12h35v42H14q-7-5 0-10z"
			trim = "M14 12h7v33h-7zM14 46h35v8H14z"
			accent = "M34 20l8 10-8 10-8-10z"
		"map":
			main = "M9 16l15-6 16 7 15-6v38l-15 6-16-7-15 6z"
			trim = "M23 11h3v37h-3zM39 17h3v37h-3z"
			accent = "M15 28l8 4 12-8 14 14-3 3-12-11-11 8-10-5z"
	return "<path d='%s' fill='#%s' fill-rule='evenodd'/><path d='%s' fill='#%s'/><path d='%s' fill='#%s'/>" % [main, a, trim, b, accent, c]
