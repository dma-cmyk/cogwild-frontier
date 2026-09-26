class_name WorldVisualTests
extends TestCase

func test_buildings_all_ids_and_stages() -> void:
	# active effects need the node in the tree; every visual is freed afterwards
	var holder := Node3D.new()
	tree.root.add_child.call_deferred(holder)
	await tree.process_frame
	for id: String in BuildingVisuals.FOOTPRINTS.keys():
		for style: String in ["frontier", "bandit", "ancient", "merchant", "neutral"]:
			var b := BuildingVisuals.create(id, style, 17, 2)
			holder.add_child(b)
			assert_eq(b.footprint, BuildingVisuals.FOOTPRINTS[id], "%s footprint" % id)
			for progress in [0.0, 0.5, 1.0]:
				b.set_construction(progress)
				assert_true(b.get_child_count() > 0, "%s stage child" % id)
			b.set_active(true)
			var body := b.get_node_or_null("StaticBody") as MeshInstance3D
			assert_true(body != null and body.mesh != null, "%s mesh" % id)
			var aabb := body.mesh.get_aabb()
			assert_true(aabb.size.x <= float(b.footprint.x) + 0.6, "%s x fit" % id)
			assert_true(aabb.size.z <= float(b.footprint.y) + 0.6, "%s z fit" % id)
			assert_true(aabb.size.y > 0.1, "%s height" % id)
			b.free()
	holder.free()

func test_props_one_surface_and_budget() -> void:
	for id: String in ["tree_pine","tree_oak","tree_birch","tree_dead","stump","bush","berry_bush","berry_bush_empty","rock_small","rock_large","ore_iron","ore_crystal","grass_tuft","flowers","reeds","tilled_soil","bridge_plank","fence","crate","barrel","lantern_post","log_pile","stone_pile","ore_pile","loot_bag","loot_chest","sign_post","banner_pole","arrow","bolt","bullet","cannon_shell","blaster_bolt"]:
		for v in PropMeshes.variant_count(id):
			var mesh := PropMeshes.get_mesh(id, v)
			assert_eq(mesh.get_surface_count(), 1, "%s one surface" % id)
			assert_true(mesh.get_aabb().size.length_squared() > 0.001, "%s nonempty" % id)
			var tris := _triangles(mesh)
			var budget := 250 if id.begins_with("tree_") else 150 if id.begins_with("crop_") else 120
			assert_true(tris <= budget, "%s triangle budget %d" % [id, tris])
	for stage in 4:
		assert_true(PropMeshes.get_mesh("crop_wheat_%d" % stage).get_surface_count() == 1, "wheat stage")
		assert_true(PropMeshes.get_mesh("crop_veg_%d" % stage).get_surface_count() == 1, "veg stage")

func test_icons_and_item_shapes() -> void:
	var svg_sources: Dictionary = {}
	var svg_pixels: Dictionary = {}
	for id: String in Icons.REQUIRED_IDS:
		var source := FileAccess.get_file_as_string("res://assets/icons/%s.svg" % id)
		assert_false(svg_sources.has(source), "duplicate SVG file: %s / %s" % [id, svg_sources.get(source, "")])
		svg_sources[source] = id
		var tex := Icons.get_icon(id)
		if not assert_true(tex != null, "icon %s" % id):
			continue
		var image := tex.get_image()
		image.resize(32, 32, Image.INTERPOLATE_LANCZOS)
		var pixels := image.get_data().hex_encode()
		assert_false(svg_pixels.has(pixels), "duplicate rendered icon: %s / %s" % [id, svg_pixels.get(pixels, "")])
		svg_pixels[pixels] = id
		assert_eq(image.get_pixel(0, 0).a, 0.0, "%s transparent background" % id)
	var item_pixels: Dictionary = {}
	for shape: String in Icons.SHAPES:
		for quality: String in ["junk", "crude", "common", "fine", "rare", "epic", "legendary", "anomalous"]:
			var item := {"quality": quality, "appearance": {"shape": shape, "primary": "#8ca8bc", "secondary": "#8a5a34", "accent": "#d9b04c", "glow": 0.35}}
			var tex := Icons.item_icon(item, 32)
			if not assert_true(tex != null, "%s %s" % [shape, quality]):
				continue
			assert_eq(tex.get_size(), Vector2(32, 32), "requested item resolution")
			var pixels := tex.get_image().get_data().hex_encode()
			assert_false(item_pixels.has(pixels), "indistinguishable item: %s %s / %s" % [shape, quality, item_pixels.get(pixels, "")])
			item_pixels[pixels] = "%s %s" % [shape, quality]
			assert_eq(Icons.item_icon(item, 32), tex, "cached item texture")
			item["appearance"]["glow"] = 0.0
			assert_ne(Icons.item_icon(item, 32).get_image().get_data(), tex.get_image().get_data(), "visible glow halo")

func test_vfx_kinds_spawn() -> void:
	var parent := Node3D.new()
	tree.root.add_child.call_deferred(parent)
	await tree.process_frame
	for kind: StringName in Vfx.KINDS: Vfx.spawn(parent, kind, Vector3.ZERO, Color("ffbd52"), Vector3.FORWARD)
	await tree.process_frame
	assert_true(parent.get_child_count() > 0, "all vfx nodes")
	parent.queue_free()

func _triangles(mesh: ArrayMesh) -> int:
	var arrays := mesh.surface_get_arrays(0)
	return (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
