extends TestCase
## Painted (image-generated) art from tools/art/process.py: every unit the game can create gets a
## painted sheet and portrait, sheets follow what a person wears, and every picture referenced by
## the art tables loads. A gap here silently drops a unit or building back to the procedural look.

const LOOKS := ["worker", "fighter", "ranger", "engineer", "scholar"]
const ROLES := ["settler", "mercenary", "commander", "merchant", "engineer", "explorer", "scholar", "researcher",
	"farmer", "woodcutter", "miner", "builder", "guard", "archer", "hunter", "medic", "cook", "tinkerer", "trader",
	"bandit", "bandit_archer", "bandit_captain"]


func _rng(seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return rng


func test_every_person_the_game_makes_is_painted() -> void:
	var rng := _rng(4242)
	for race: String in AppearanceGen.RACES:
		for role: String in ROLES:
			for style: String in ["frontier", "bandit", "merchant", "neutral"]:
				for gender: String in ["female", "male", "nonbinary"]:
					var dna := AppearanceGen.character(rng, race, role, style, Color("#3a5da8"), gender)
					var hints := {"role": role}
					var entry := SpriteLibrary.chip(dna, hints)
					assert_true(not entry.is_empty(), "sheet for %s %s %s %s -> %s" % [race, role, style, gender, SpriteLibrary.chip_id(dna, hints)])
					assert_true(SpriteLibrary.portrait(dna, hints) != null, "portrait for " + SpriteLibrary.chip_id(dna, hints))
	for race: String in AppearanceGen.RACES:
		for look: String in LOOKS:
			for g: String in ["m", "f"]:
				assert_true(DB.has_def("art/portraits", "%s_%s_%s" % [race, look, g]), "painted bust %s_%s_%s" % [race, look, g])


func test_every_person_has_three_painted_variants() -> void:
	for race: String in AppearanceGen.RACES:
		for look: String in LOOKS:
			for gender: String in ["m", "f"]:
				var id := "%s_%s_%s" % [race, look, gender]
				var dna := {"kind":"character", "race":race, "gender":"female" if gender == "f" else "male",
					"seed":91, "hair":"braids", "hair_color":"#241c28", "skin":"#c58d70"}
				match look:
					"ranger":
						dna["weapon"] = "bow"
					"engineer":
						dna["weapon"] = "wrench"
					"scholar":
						dna["weapon"] = "staff"
					"fighter":
						dna["weapon"] = "sword"
					_:
						dna["weapon"] = "none"
				dna["armor"] = "none"
				dna["offhand"] = "none"
				dna["outfit"] = "robe" if look == "scholar" else "tunic"
				var hints: Dictionary = {}
				var expected_count := 4 if race == "sylvan" and look == "worker" else 5 if look == "worker" else 3
				assert_eq(SpriteLibrary.variant_count(dna, hints), expected_count,
					"%s has %d loadable chips" % [id, expected_count])
				var entries: Array[Dictionary] = []
				for variant: int in expected_count:
					var variant_id := id if variant == 0 else "%s@v%d" % [id, variant + 1]
					entries.append(DB.get_def("art/sprites", variant_id))
				for variant: int in expected_count:
					var entry := entries[variant]
					assert_true(not entry.is_empty(), "%s has chip metadata variant %d" % [id, variant])
					assert_true(SpriteLibrary.texture(str(entry.get("texture", ""))) != null, "%s chip texture loads v%d" % [id, variant + 1])
					assert_true(not DB.get_def("art/portraits", str(entry["id"])).is_empty(), "%s portrait metadata v%d" % [id, variant + 1])
					var portrait_entry := DB.get_def("art/portraits", str(entry["id"]))
					assert_true(SpriteLibrary.texture(str(portrait_entry.get("texture", ""))) != null, "%s portrait texture loads v%d" % [id, variant + 1])
				var old_save := dna.duplicate()
				var old_variant := SpriteLibrary.art_variant(old_save, hints)
				assert_true(old_variant >= 0 and old_variant < 2, "%s legacy look is in v1/v2 range" % id)
				var old_id := id if old_variant == 0 else id + "@v2"
				assert_eq(str(SpriteLibrary.chip(old_save, hints).get("id", "")), old_id, "%s legacy look uses its v1/v2 painting" % id)
				for selected: int in expected_count:
					dna["art_variant"] = selected
					var selected_id := id if selected == 0 else "%s@v%d" % [id, selected + 1]
					assert_eq(str(SpriteLibrary.chip(dna, hints).get("id", "")), selected_id,
						"%s explicit chip variant %d" % [id, selected])
					var portrait_entry := DB.get_def("art/portraits", selected_id)
					var expected_portrait := SpriteLibrary.texture(str(portrait_entry.get("texture", "")))
					assert_true(expected_portrait != null and SpriteLibrary.portrait(dna, hints) == expected_portrait,
						"%s explicit portrait variant %d" % [id, selected])


func test_joining_residents_get_least_used_painting_and_save_stably() -> void:
	var w := World.new()
	w.setup(3703)
	var people: Array[Unit] = []
	for i in 5:
		var u := Unit.new()
		u.faction = "player"
		u.dna = {"kind":"character", "race":"human", "gender":"female", "seed":i + 10,
			"hair":"braids", "hair_color":"#241c28", "skin":"#c58d70", "weapon":"none",
			"armor":"none", "offhand":"none", "outfit":"tunic"}
		w.add_unit(u)
		people.append(u)
	var used := {}
	for u: Unit in people:
		var v := int(u.dna["art_variant"])
		used[v] = int(used.get(v, 0)) + 1
	assert_eq(used.size(), 5, "same-combo residents use all five available paintings")
	for count: int in used.values():
		assert_eq(count, 1, "five residents have distinct paintings")
	var save := SaveGame.to_dict(w)
	var loaded := SaveGame.from_dict(save)
	assert_true(loaded is World, "world save reload succeeds")
	var restored := (loaded as World).player_people()
	for i in people.size():
		assert_eq(int(restored[i].dna["art_variant"]), int(people[i].dna["art_variant"]),
			"resident variant %d survives save/load" % i)
	(loaded as World).dispose()
	w.dispose()


func test_legacy_unit_save_keeps_its_two_variant_look() -> void:
	var u := Unit.new()
	u.dna = {"kind":"character", "race":"human", "gender":"female", "seed":556,
		"hair":"braids", "hair_color":"#241c28", "skin":"#c58d70", "weapon":"none",
		"armor":"none", "offhand":"none", "outfit":"tunic"}
	var legacy_variant := SpriteLibrary.art_variant(u.dna)
	var restored := Unit.from_dict(u.to_dict())
	assert_false(restored.dna.has("art_variant"), "legacy save stays unbackfilled")
	assert_eq(SpriteLibrary.art_variant(restored.dna), legacy_variant, "legacy two-variant painting remains unchanged")

func test_every_machine_the_game_makes_is_painted() -> void:
	var rng := _rng(7)
	for id: String in DB.ids("robots"):
		var d := DB.get_def("robots", id)
		var kind := str(d.get("kind", "robot"))
		var dna: Dictionary
		if kind == "drone":
			dna = AppearanceGen.drone(rng, id, "frontier", Color("#3a5da8"))
		else:
			dna = AppearanceGen.robot(rng, id, "ancient", Color("#a07a4a"))
		var entry := SpriteLibrary.chip(dna, {"archetype": id})
		assert_true(not entry.is_empty(), "machine sheet for " + id)
		assert_eq(str(entry.get("id", "")), id, "machine %s uses its own sheet" % id)
	for id: String in DB.ids("airships"):
		var dna := AppearanceGen.airship(rng, id, "merchant" if id == "trader_airship" else "frontier", Color("#3a5da8"))
		assert_eq(str(SpriteLibrary.chip(dna, {"archetype": id}).get("id", "")), id, "airship sheet for " + id)


func test_look_follows_equipment() -> void:
	var dna := AppearanceGen.character(_rng(3), "vulpin", "settler", "frontier", Color("#3a5da8"), "female")
	dna["weapon"] = "pickaxe"
	dna["offhand"] = "none"
	dna["armor"] = "none"
	dna["outfit"] = "tunic"
	dna["headgear"] = "cap"
	assert_eq(SpriteLibrary.chip_id(dna), "vulpin_worker_f", "tools -> worker")
	dna["weapon"] = "bow"
	assert_eq(SpriteLibrary.chip_id(dna), "vulpin_ranger_f", "bow -> ranger")
	dna["weapon"] = "dagger"
	dna["offhand"] = "shield"
	assert_eq(SpriteLibrary.chip_id(dna), "vulpin_fighter_f", "shield -> fighter")
	dna["offhand"] = "none"
	dna["weapon"] = "wrench"
	assert_eq(SpriteLibrary.chip_id(dna), "vulpin_engineer_f", "wrench -> engineer")
	var bandit := AppearanceGen.character(_rng(4), "human", "bandit", "bandit", Color.TRANSPARENT, "male")
	bandit["weapon"] = "sword"
	assert_eq(SpriteLibrary.chip_id(bandit), "bandit_captain", "bandit with a sword leads")
	bandit["weapon"] = "crossbow"
	assert_eq(SpriteLibrary.chip_id(bandit), "bandit_archer", "bandit crossbow")


func test_company_colour_only_turns_painted_blue() -> void:
	assert_eq(SpriteLibrary.hue_shift_for({"faction_style": "frontier", "faction_color": "#3a5da8"}), 0.0, "default company blue keeps the painting")
	var green := SpriteLibrary.hue_shift_for({"faction_style": "merchant", "faction_color": "#4f8a4b"})
	assert_true(green < -0.2 and green > -0.4, "green company rotates blue toward green (%f)" % green)
	assert_eq(SpriteLibrary.hue_shift_for({"faction_style": "bandit", "faction_color": "#b33a2e"}), 0.0, "bandits keep their painted red")


func test_buildings_props_and_ground_are_painted() -> void:
	for id: String in BuildingVisuals.FOOTPRINTS.keys():
		# Crossings and race village buildings are allowed to stay procedural: they are tinted from
		# data and a painted card is used only when data/art/buildings has one.
		if id in ["bridge_segment", "cliff_stairs"] or BldVillage.race_of(id) != "":
			var mesh := BuildingVisuals._make_mesh(id, "frontier", 17, 1, 3)
			assert_true(mesh.get_surface_count() > 0, "procedural mesh for " + id)
			continue
		assert_true(not SpriteLibrary.building(id).is_empty(), "picture for building " + id)
	for level in [1, 2, 3]:
		assert_true(not SpriteLibrary.building("hearth", level).is_empty(), "hearth level %d picture" % level)
	assert_true(not SpriteLibrary.building("construction").is_empty(), "construction site picture")


	for prop: String in ["tree_pine", "tree_oak", "tree_birch", "tree_dead", "rock_small", "rock_large", "ore_iron",
			"ore_crystal", "bush", "berry_bush", "stump", "reeds", "grass_tuft", "flowers"]:
		assert_true(not SpriteLibrary.prop_variants(prop).is_empty(), "painted prop " + prop)
	var layers := load("res://assets/textures/terrain_array.png") as TextureLayered
	assert_true(layers != null and layers.get_layered_type() == TextureLayered.LAYERED_TYPE_2D_ARRAY and layers.get_layers() == 8, "8 ground texture layers")
	assert_true(bool(ChunkView.terrain_material().get_shader_parameter("use_layers")), "terrain draws the painted layers")
	assert_eq(DB.ids("art/terrain").size(), 8, "terrain layer table")
func test_buildings_have_loadable_back_views_or_explicit_symmetry() -> void:
	for id: String in DB.ids("art/buildings"):
		var entry := DB.get_def("art/buildings", id)
		if bool(entry.get("back_symmetric", false)):
			continue
		var back_path := str(entry.get("back_texture", ""))
		assert_true(not back_path.is_empty(), "%s needs a back texture or symmetric flag" % id)
		assert_true(SpriteLibrary.texture(back_path) != null, "%s back texture loads" % id)




func test_every_art_table_texture_loads() -> void:
	for table: String in ["art/sprites", "art/portraits", "art/buildings", "art/props", "art/icons"]:
		for id: String in DB.ids(table):
			var e := DB.get_def(table, id)
			assert_true(SpriteLibrary.texture(str(e.get("texture", ""))) != null, "%s %s texture" % [table, id])
			if e.has("glow"):
				assert_true(SpriteLibrary.texture(str(e["glow"])) != null, "%s %s glow" % [table, id])
			if e.has("back_glow"):
				assert_true(SpriteLibrary.texture(str(e["back_glow"])) != null, "%s %s back glow" % [table, id])
	for shape: String in Icons.SHAPES:
		assert_true(SpriteLibrary.icon_image(shape, 48) != null, "painted icon for item shape " + shape)
