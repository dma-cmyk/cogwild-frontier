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


func test_every_person_has_two_painted_variants() -> void:
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
				assert_eq(SpriteLibrary.variant_count(dna, hints), 2, "%s has two loadable chips" % id)
				var first := DB.get_def("art/sprites", id)
				var second := DB.get_def("art/sprites", id + "@v2")
				assert_true(not first.is_empty() and not second.is_empty(), "%s has v1 and v2 chip metadata" % id)
				for entry: Dictionary in [first, second]:
					assert_true(SpriteLibrary.texture(str(entry.get("texture", ""))) != null, "%s chip texture loads" % entry["id"])
					assert_true(not DB.get_def("art/portraits", str(entry["id"])).is_empty(), "%s portrait metadata exists" % entry["id"])
				var old_save := dna.duplicate()
				var old_variant := SpriteLibrary.art_variant(old_save, hints)
				assert_true(old_variant >= 0 and old_variant < 2, "%s legacy look is in range" % id)
				assert_eq(old_variant, SpriteLibrary.art_variant(old_save, hints), "%s legacy look is deterministic" % id)
				assert_eq(str(SpriteLibrary.chip(old_save, hints).get("id", "")),
					id if old_variant == 0 else id + "@v2", "%s legacy chip uses its derived look" % id)
				for selected: int in [0, 1]:
					dna["art_variant"] = selected
					var selected_entry := SpriteLibrary.chip(dna, hints)
					assert_eq(str(selected_entry.get("id", "")), id if selected == 0 else id + "@v2", "%s explicit chip variant %d" % [id, selected])
					var portrait_entry := DB.get_def("art/portraits", id if selected == 0 else id + "@v2")
					var expected_portrait := SpriteLibrary.texture(str(portrait_entry.get("texture", "")))
					assert_true(expected_portrait != null and SpriteLibrary.portrait(dna, hints) == expected_portrait,
						"%s explicit portrait variant %d" % [id, selected])


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


func test_every_art_table_texture_loads() -> void:
	for table: String in ["art/sprites", "art/portraits", "art/buildings", "art/props", "art/icons"]:
		for id: String in DB.ids(table):
			var e := DB.get_def(table, id)
			assert_true(SpriteLibrary.texture(str(e.get("texture", ""))) != null, "%s %s texture" % [table, id])
			if e.has("glow"):
				assert_true(SpriteLibrary.texture(str(e["glow"])) != null, "%s %s glow" % [table, id])
	for shape: String in Icons.SHAPES:
		assert_true(SpriteLibrary.icon_image(shape, 48) != null, "painted icon for item shape " + shape)
