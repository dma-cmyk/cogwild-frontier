class_name Minimap
extends PanelContainer
## Bottom-left minimap: terrain window around the camera (explored areas only), markers for your
## units, buildings, known sites, visible enemies and loot, the camera view outline, and quick
## buttons. Left-click a place for details; empty-map clicks and drags move the camera.

const SIZE := 236.0
const SPAN := 150.0  # world metres shown

var g: Game
var _map: Control
var _mat: ShaderMaterial
var _img: Image
var _tex: ImageTexture
var _painted: Dictionary = {}  # chunk key -> version painted
var _pending_paints: Array[Vector2i] = []
var _queued_paints: Dictionary = {}
var _t := 0.0
var _pressed_marker: Dictionary = {}
var _press_pos := Vector2.ZERO
var _dragging := false
var _places_button: Button
var _legend_button: Button
var _legend: PanelContainer
var _legend_labels: Dictionary = {}
var _legend_close: Button


func setup(game: Game) -> void:
	g = game
	name = "Minimap"
	add_theme_stylebox_override("panel", UiTheme.panel_box())
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 10
	offset_right = 10 + SIZE + 24 + 52
	offset_top = -(SIZE + 30)
	offset_bottom = -10
	var h := UiTheme.hbox(6)
	add_child(h)
	_map = Control.new()
	_map.custom_minimum_size = Vector2(SIZE, SIZE)
	_map.mouse_filter = Control.MOUSE_FILTER_STOP
	_map.clip_contents = true
	h.add_child(_map)
	_img = Image.create(g.world.W, g.world.W, false, Image.FORMAT_RGBA8)
	_img.fill(Color(0.1, 0.12, 0.16))
	_tex = ImageTexture.create_from_image(_img)
	var tr := ColorRect.new()
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://src/visual/shaders/minimap.gdshader")
	_mat.set_shader_parameter("terrain_tex", _tex)
	tr.material = _mat
	_map.add_child(tr)
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_markers.bind(overlay))
	_map.add_child(overlay)
	_map.set_meta("overlay", overlay)
	_map.name = "MapSurface"
	_map.gui_input.connect(_on_map_input)
	var col := UiTheme.vbox(4)
	h.add_child(col)
	for b: Array in [["ui_home", "Back to the hearth (Home)", func() -> void: g.focus_home()],
			["ui_buildings", "Build menu (B)", func() -> void: g.hud.build_menu.toggle("build")],
			["ui_people", "Your people and machines", func() -> void: g.hud.roster.toggle()],
			["poi_village", "Neighbouring villages", func() -> void: g.hud.villages.diplomacy_panel.toggle()],
			["ui_search", "Find an idle settler", _find_idle]]:
		var btn := UiTheme.button("", str(b[0]), Loc.t(str(b[1])))
		btn.custom_minimum_size = Vector2(44, 30)
		btn.pressed.connect(b[2])
		col.add_child(btn)
	_places_button = UiTheme.button(Loc.t("places.title"))
	_places_button.name = "MinimapPlaces"
	_places_button.add_theme_font_size_override("font_size", 12)
	_places_button.custom_minimum_size = Vector2(44, 30)
	_places_button.pressed.connect(func() -> void: g.hud.open_management("places"))
	col.add_child(_places_button)
	_legend_button = UiTheme.button(Loc.t("places.legend"))
	_legend_button.name = "MinimapLegend"
	_legend_button.add_theme_font_size_override("font_size", 12)
	_legend_button.custom_minimum_size = Vector2(44, 30)
	_legend_button.pressed.connect(func() -> void: _legend.visible = not _legend.visible)
	col.add_child(_legend_button)
	_build_legend()
	Loc.language_changed.connect(_localize)
	g.world.chunk_ready.connect(_queue_chunk)
	g.world.chunk_changed.connect(func(k: Vector2i) -> void:
		_painted.erase(k)
		_queue_chunk(k))
	var initial_painted := false
	for key: Vector2i in g.world.chunks:
		var ch: ChunkData = g.world.chunks[key]
		var version := ch.version + ch.res_version * 7919
		if int(_painted.get(key, -1)) != version:
			_paint(ch)
			_painted[key] = version
			initial_painted = true
	if initial_painted:
		_tex.update(_img)

func _view_rect() -> Rect2:
	var c := Vector2(g.rig.target.x, g.rig.target.z)
	return Rect2(c - Vector2(SPAN, SPAN) * 0.5, Vector2(SPAN, SPAN))


func _queue_chunk(key: Vector2i) -> void:
	if not _queued_paints.has(key):
		_pending_paints.append(key)
		_queued_paints[key] = true


func _paint_chunks() -> void:
	if _pending_paints.is_empty():
		return
	var key: Vector2i = _pending_paints.pop_front()
	_queued_paints.erase(key)
	var ch: ChunkData = g.world.chunks.get(key)
	if ch == null:
		return
	var version := ch.version + ch.res_version * 7919
	if int(_painted.get(key, -1)) != version:
		_painted[key] = version
		var profile := World.profile_chunks()
		var paint_start_usec: int = Time.get_ticks_usec() if profile else 0
		_paint(ch)
		var paint_usec: int = Time.get_ticks_usec() - paint_start_usec if profile else 0
		var update_start_usec: int = Time.get_ticks_usec() if profile else 0
		_tex.update(_img)
		if profile:
			print("PERF_MINIMAP key=(%d,%d) paint_ms=%.2f texture_update_ms=%.2f" % [
				key.x, key.y, paint_usec / 1000.0, (Time.get_ticks_usec() - update_start_usec) / 1000.0])


func _paint(ch: ChunkData) -> void:
	var ox := ch.cx * ChunkData.S - g.world.gen.min_tile
	var oz := ch.cz * ChunkData.S - g.world.gen.min_tile
	for z in ChunkData.S:
		for x in ChunkData.S:
			var i := z * ChunkData.S + x
			var c: Color = Tiles.COLORS[ch.terrain[i]]
			var r := ch.res_type[i]
			if Tiles.is_tree(r):
				c = Color("#3f6f35")
			elif r == Tiles.Res.ROCK_LARGE or r == Tiles.Res.ROCK_SMALL:
				c = Color("#8a8a86")
			elif r == Tiles.Res.ORE_IRON:
				c = Color("#b8743a")
			elif r == Tiles.Res.ORE_CRYSTAL:
				c = Color("#5fe0f0")
			if ch.blocked[i] != 0:
				c = Color("#6a4a34")
			var h := ch.height_local(x + 0.5, z + 0.5)
			if h > 0.0:
				c = c.lightened(clampf(h / 30.0, 0.0, 0.25))
			_img.set_pixel(ox + x, oz + z, c)


func _process(delta: float) -> void:
	if not _pending_paints.is_empty():
		_paint_chunks()
	var r := _view_rect()
	_mat.set_shader_parameter("view_rect", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
	_t -= delta
	if _t <= 0.0:
		_t = 0.2
		(_map.get_meta("overlay") as Control).queue_redraw()


func _w2m(p: Vector2) -> Vector2:
	var r := _view_rect()
	return (p - r.position) / r.size * SIZE


func _draw_markers(c: Control) -> void:
	c.draw_string(ThemeDB.fallback_font, Vector2(SIZE - 22.0, 18.0), "N", HORIZONTAL_ALIGNMENT_CENTER, -1.0, 12, Color("#fff2cc"))
	c.draw_line(Vector2(SIZE - 22.0, 22.0), Vector2(SIZE - 22.0, 10.0), Color("#fff2cc"), 1.5)
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(SIZE - 22.0, 7.0), Vector2(SIZE - 25.0, 13.0), Vector2(SIZE - 19.0, 13.0)
	]), Color("#fff2cc"))
	var w := g.world
	for b: Building in w.buildings.values():
		if b.faction != "player" or not _on_current_map(b.center()):
			continue
		var p := _w2m(b.center())
		_draw_place_marker(c, p, "facility", Color("#9fc4ff") if b.is_built() else Color("#9fc4ff", 0.5))
	for st: Dictionary in w.sites.values():
		if not PlacesPanel.known_surface(st) or not _on_current_map(Vector2(st["center"])):
			continue
		var p := _w2m(Vector2(st["center"]))
		if str(st["kind"]) in ["village", "town"]:
			# villages get a house-shaped pip in their relation colour
			var tint := VillagePanel.tier_color(Diplomacy.tier_for(int(st.get("relation", 0))))
			if bool(st.get("ruined", false)):
				tint = tint.darkened(0.45)
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -6), p + Vector2(6, 0),
				p + Vector2(4, 6), p + Vector2(-4, 6), p + Vector2(-6, 0)]), Color(0, 0, 0, 0.65))
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -4.4), p + Vector2(4.4, 0),
				p + Vector2(2.8, 4.4), p + Vector2(-2.8, 4.4), p + Vector2(-4.4, 0)]), tint)
			continue
		var col: Color = Color("#ff5a4a") if (st.get("hostile", false) and not st.get("cleared", false)) else ({"trade_post": Color("#7dff8a"), "ruins": Color("#c7a8ff"), "wreck": Color("#ffe07a"), "dungeon": Color("#d98cff")}.get(str(st["kind"]), Color("#e8e0c8")))
		_draw_place_marker(c, p, str(st.get("kind", "")), col)
	for bag: Dictionary in w.loot_bags.values():
		if not _on_current_map(Vector2(bag["pos"])):
			continue
		c.draw_circle(_w2m(bag["pos"]), 2.2, UiTheme.GOLD)
	for u: Unit in w.unit_list:
		if not u.alive or u.hidden or not _on_current_map(u.pos):
			continue
		var p := _w2m(u.pos)
		if p.x < -4 or p.y < -4 or p.x > SIZE + 4 or p.y > SIZE + 4:
			continue
		if u.is_player():
			var col := Color("#5fd0ff")
			if u.squad_id >= 0:
				var s := w.get_squad(u.squad_id)
				col = s.color() if s else col
			var rad := 4.0 if u.kind == "airship" else (2.6 if u.squad_id >= 0 else 1.8)
			c.draw_circle(p, rad, col)
		elif u.visible:
			c.draw_circle(p, 2.4, Color("#ff5a4a") if w.hostile("player", u.faction) else Color("#ffd25a"))
	_draw_zones(c)
	_draw_orders(c)
	# camera view outline
	var vp := g.get_viewport().get_visible_rect().size
	var pts: PackedVector2Array = []
	for sp: Vector2 in [Vector2(0, 0), Vector2(vp.x, 0), vp, Vector2(0, vp.y)]:
		var gp: Variant = g.rig.screen_to_ground(sp)
		if gp == null:
			var o := g.rig.cam.project_ray_origin(sp)
			var d := g.rig.cam.project_ray_normal(sp)
			gp = o + d * ((o.y - 0.0) / -d.y)
		pts.append(_w2m(Vector2(gp.x, gp.z)))
	pts.append(pts[0])
	c.draw_polyline(pts, Color(1, 1, 1, 0.45), 1.0)


## Gather zones: the minimap is the only view wide enough to hold them all at once.
func _draw_zones(c: Control) -> void:
	for z: Dictionary in g.world.zones:
		var outline: PackedVector2Array = z.get("outline", PackedVector2Array())
		var col: Color = WorldView.ZONE_COLORS.get(str(z["type"]), Color.WHITE)
		for i in range(0, outline.size() - 1, 2):
			c.draw_line(_w2m(outline[i]), _w2m(outline[i + 1]), Color(col, 0.75), 1.5)


## Where the squads the command bar addresses were sent. An explore region is wider than the
## camera ever shows, so the minimap is where its extent is actually readable.
func _draw_orders(c: Control) -> void:
	if g.hud == null:
		return
	for id: int in g.hud.command_squad_ids():
		var squad := g.world.get_squad(id)
		if squad == null or squad.members.is_empty():
			continue
		var col := Color(squad.color(), 0.85)
		var from := _w2m(g.world.squad_ai.center(squad))
		var order := squad.order
		match str(order.get("type", "")):
			"defend", "explore":
				var at := _w2m(order.get("pos", g.world.squad_ai.center(squad)))
				var radius := float(order.get("radius", 10.0)) / SPAN * SIZE
				c.draw_arc(at, radius, 0.0, TAU, 40, col, 1.5)
				c.draw_line(from, at, col, 1.0)
			"patrol":
				var points: Array = order.get("points", [])
				for i in points.size():
					c.draw_line(_w2m(points[i]), _w2m(points[(i + 1) % points.size()]), col, 1.5)
			"move", "visit", "attack", "retreat", "escort":
				c.draw_line(from, _w2m(_goal_of(squad)), col, 1.5)
				c.draw_circle(_w2m(_goal_of(squad)), 3.0, col, false, 1.5)


func _goal_of(squad: Squad) -> Vector2:
	var order := squad.order
	var target := g.world.get_unit(int(order.get("target", -1)))
	if target != null and target.alive:
		return target.pos
	if str(order.get("type", "")) == "retreat":
		return g.world.home_pos()
	var site: Dictionary = g.world.sites.get(int(order.get("site", -1)), {})
	if not site.is_empty():
		return Vector2(site["center"])
	return order.get("pos", g.world.squad_ai.center(squad))


func _on_map_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_press_pos = ev.position
			_pressed_marker = _marker_at(ev.position)
			_dragging = _pressed_marker.is_empty()
			if _dragging:
				_jump(ev.position)
		else:
			if not _dragging and not _pressed_marker.is_empty():
				_focus_marker(_pressed_marker)
			_dragging = false
			_pressed_marker = {}
	elif ev is InputEventMouseMotion:
		if not _pressed_marker.is_empty() and ev.position.distance_to(_press_pos) > 5.0:
			_pressed_marker = {}
			_dragging = true
		if _dragging:
			_jump(ev.position)
		var hit := _marker_at(ev.position)
		_map.tooltip_text = str(hit.get("label", Loc.t("places.map.hint")))
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
		var r := _view_rect()
		var wp: Vector2 = r.position + (ev as InputEventMouseButton).position / SIZE * r.size
		if not g.selected_units().is_empty():
			g.input_ctl.issue("move", {"pos": wp})


func _jump(mp: Vector2) -> void:
	var r := _view_rect()
	var wp := r.position + mp / SIZE * r.size
	g.rig.focus(Vector3(wp.x, 0, wp.y), true)


func _find_idle() -> void:
	for u: Unit in g.world.unit_list:
		if u.is_player() and u.alive and u.labor == "worker" and u.squad_id < 0 and str(u.job.get("type", "idle")) in ["idle", ""]:
			g.select_units([u.id])
			g.focus_pos(u.pos)
			return
	g.hud.add_note({"text": Loc.t("Everyone is busy."), "kind": "good"}, 2.5)


func _on_current_map(pos: Vector2) -> bool:
	return g.world.dungeons.same_map(Vector2(g.rig.target.x, g.rig.target.z), pos)


func _marker_at(mp: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var distance := 8.0
	var bounds := Rect2(Vector2.ZERO, Vector2(SIZE, SIZE))
	for b: Building in g.world.buildings.values():
		if b.faction != "player" or not _on_current_map(b.center()):
			continue
		var p := _w2m(b.center())
		var d := p.distance_to(mp)
		if bounds.has_point(p) and d < distance:
			distance = d
			best = {"building": b.id, "label": PlacesPanel.facility_name(b) + " · " + Loc.def_name("buildings", b.type)}
	for st: Dictionary in g.world.sites.values():
		if not PlacesPanel.known_surface(st) or not _on_current_map(Vector2(st["center"])):
			continue
		var p := _w2m(Vector2(st["center"]))
		var d := p.distance_to(mp)
		if bounds.has_point(p) and d < distance:
			distance = d
			best = {"site": int(st["id"]), "label": PlacesPanel.site_name(st) + " · " + PlacesPanel.site_type(st)}
	return best


func _focus_marker(hit: Dictionary) -> void:
	if hit.has("building"):
		var b: Building = g.world.buildings.get(int(hit["building"]))
		if b == null or b.faction != "player":
			return
		g.select_building(b.id)
		g.focus_pos(b.center())
	else:
		var st: Dictionary = g.world.sites.get(int(hit["site"]), {})
		if not PlacesPanel.known_surface(st):
			return
		g.select_site(int(st["id"]))
		g.focus_pos(Vector2(st["center"]))


func _draw_place_marker(c: Control, p: Vector2, kind: String, color: Color) -> void:
	c.draw_circle(p, 6.0, Color(0, 0, 0, 0.75))
	match kind:
		"ruins":
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -5), p + Vector2(5, 4), p + Vector2(-5, 4)]), color)
		"dungeon":
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -5), p + Vector2(5, 0), p + Vector2(0, 5), p + Vector2(-5, 0)]), color)
		"trade_post":
			c.draw_line(p + Vector2(-5, 0), p + Vector2(5, 0), color, 3.0)
			c.draw_line(p + Vector2(0, -5), p + Vector2(0, 5), color, 3.0)
		"facility":
			c.draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), color)
		"village", "town":
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -5), p + Vector2(5, 0), p + Vector2(3, 5), p + Vector2(-3, 5), p + Vector2(-5, 0)]), color)
		_:
			c.draw_circle(p, 3.6, color)


func _build_legend() -> void:
	# A sibling overlay keeps the existing fixed minimap/HUD footprint intact.
	_legend = UiTheme.panel()
	_legend.name = "MinimapLegendPanel"
	get_parent().add_child(_legend)
	_legend.anchor_top = 1.0
	_legend.anchor_bottom = 1.0
	_legend.offset_left = 10
	_legend.offset_right = 330
	_legend.offset_top = -570
	_legend.offset_bottom = -(SIZE + 40)
	var body := UiTheme.vbox(5)
	_legend.add_child(body)
	var head := UiTheme.hbox(8)
	var title := UiTheme.title(Loc.t("places.legend"), 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_legend_labels["places.legend"] = title
	var close := UiTheme.button("", "ui_close", Loc.t("places.close"))
	_legend_close = close
	close.name = "MinimapLegendClose"
	close.pressed.connect(func() -> void: _legend.hide())
	head.add_child(close)
	body.add_child(head)
	for kind: String in ["ruins", "dungeon", "trade_post", "facility", "village", "other"]:
		var line := UiTheme.hbox(8)
		var swatch := Control.new()
		swatch.custom_minimum_size = Vector2(18, 20)
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		swatch.draw.connect(_draw_place_marker.bind(swatch, Vector2(9, 10), kind, UiTheme.GOLD))
		line.add_child(swatch)
		var label := UiTheme.label(Loc.t("places.legend." + kind), 13)
		_legend_labels["places.legend." + kind] = label
		line.add_child(label)
		body.add_child(line)
	var hint := UiTheme.label(Loc.t("places.map.hint"), 12, UiTheme.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_legend_labels["places.map.hint"] = hint
	body.add_child(hint)
	_legend.hide()
	tree_exiting.connect(func() -> void: _legend.queue_free())


func _localize() -> void:
	_places_button.text = Loc.t("places.title")
	_legend_button.text = Loc.t("places.legend")
	_legend_close.tooltip_text = Loc.t("places.close")
	for key: String in _legend_labels:
		(_legend_labels[key] as Label).text = Loc.t(key)
