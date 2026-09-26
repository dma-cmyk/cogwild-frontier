extends TestCase

func _mesh_triangles(node: UnitVisual) -> int:
	var total := 0
	for child: Node in node.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is ArrayMesh:
			var mesh := (child as MeshInstance3D).mesh as ArrayMesh
			for surface in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surface)
				if arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
					total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return total

func _mesh_instances(node: UnitVisual) -> int:
	var count := 0
	for child: Node in node.get_children():
		if child is MeshInstance3D: count += 1
	return count

func _new_rng(seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return rng

func test_determinism() -> void:
	var a := AppearanceGen.character(_new_rng(42), "sylvan", "guard", "frontier", Color("#3a5da8"), "female")
	var b := AppearanceGen.character(_new_rng(42), "sylvan", "guard", "frontier", Color("#3a5da8"), "female")
	assert_eq(a, b, "same seed produces same DNA")
	var va := UnitVisualFactory.create_mesh(a)
	var vb := UnitVisualFactory.create_mesh(b)
	assert_eq(_mesh_triangles(va), _mesh_triangles(vb), "same DNA produces same triangles")
	assert_eq(_mesh_instances(va), 4, "character mesh count")
	va.free()
	vb.free()

func test_domains_and_budgets() -> void:
	var rng := _new_rng(90210)
	for i in 500:
		var c := AppearanceGen.character(rng, AppearanceGen.RACES[i % 4], "settler", "frontier", Color("#3a5da8"))
		assert_true(AppearanceGen.RACES.has(str(c["race"])), "character race domain")
		var cv := UnitVisualFactory.create_mesh(c)
		var tris = _mesh_triangles(cv)
		if tris > 1800:
			print("Character ", c["race"], " ", c["body_type"], " ", c["outfit"], " ", c["armor"], " ", c["headgear"], " ", c["weapon"], " ", c["offhand"], " ", c["accessory"], " tris: ", tris)
		assert_true(tris <= 1800, "character triangle budget")
		assert_true(_mesh_instances(cv) <= 4, "character instance budget")
		cv.free()
		var r := AppearanceGen.robot(rng, AppearanceGen.ROBOT_ARCHETYPES[i % 5], "ancient", Color("#a07a4a"))
		var rv := UnitVisualFactory.create_mesh(r)
		assert_true(_mesh_triangles(rv) <= 3000, "robot triangle budget")
		assert_true(_mesh_instances(rv) <= 4, "robot instance budget")
		rv.free()
		var d := AppearanceGen.drone(rng, AppearanceGen.DRONE_ARCHETYPES[i % 3], "frontier", Color("#3a5da8"))
		var dv := UnitVisualFactory.create_mesh(d)
		assert_true(_mesh_triangles(dv) <= 1200, "drone triangle budget")
		assert_true(_mesh_instances(dv) <= 3, "drone instance budget")
		dv.free()
		var s := AppearanceGen.airship(rng, AppearanceGen.AIRSHIP_ARCHETYPES[i % 4], "merchant", Color("#4f8a4b"))
		var sv := UnitVisualFactory.create_mesh(s)
		assert_true(_mesh_triangles(sv) <= 6000, "airship triangle budget")
		assert_true(_mesh_instances(sv) <= 3, "airship instance budget")
		sv.free()

func test_race_role_style_matrix() -> void:
	var roles: Array[String] = ["settler", "mercenary", "commander", "merchant", "engineer", "explorer", "scholar", "researcher", "farmer", "woodcutter", "miner", "builder", "guard", "archer", "hunter", "medic", "cook", "tinkerer", "trader", "bandit", "bandit_archer", "bandit_captain", "unknown"]
	var rng := _new_rng(777)
	for style: String in AppearanceGen.STYLES:
		for race: String in AppearanceGen.RACES:
			for role: String in roles:
				var visual := UnitVisualFactory.create(AppearanceGen.character(rng, race, role, style, Color("#3a5da8")))
				visual.set_anim(UnitVisual.Anim.WALK)
				visual.set_move_speed(1.3)
				visual.trigger(&"attack_melee")
				visual.set_held("pickaxe")
				visual.set_carry("ore")
				assert_true(visual.get_visual_height() > 0.0, "valid visual height")
				visual.free()

func test_all_actions() -> void:
	var visual := UnitVisualFactory.create(AppearanceGen.character(_new_rng(1), "human", "settler", "neutral", Color.TRANSPARENT))
	for action: StringName in [&"attack_melee", &"attack_ranged", &"hit", &"work_chop", &"work_mine", &"work_build", &"work_farm", &"cheer", &"levelup"]:
		visual.trigger(action)
	visual.set_held("")
	for resource: String in ["", "wood", "stone", "ore", "metal", "food", "gold", "crate"]:
		visual.set_carry(resource)
	assert_true(visual.get_head_position().y > 0.0, "head anchor")
	assert_true(visual.get_muzzle_position().z > 0.0, "muzzle anchor")
	visual.free()
