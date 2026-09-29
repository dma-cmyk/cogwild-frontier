extends TestCase
## One-column airship sheets must never sample nonexistent walk/stand/action columns.

func test_airships_keep_their_sprite_visible_while_idle_and_moving() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 15
	for id: String in ["cargo_airship", "trader_airship"]:
		var dna := AppearanceGen.airship(rng, id, "frontier", Color("#3a5da8"))
		var visual := UnitVisualFactory.create(dna, {"archetype": id})
		if not assert_true(visual is SpriteUnitVisual, "%s uses painted art" % id):
			visual.free()
			continue
		var sprite := visual as SpriteUnitVisual
		var material := sprite.card.material_override as ShaderMaterial
		sprite.set_anim(UnitVisual.Anim.IDLE)
		sprite._process(0.1)
		var frame: Vector2 = material.get_shader_parameter("frame")
		assert_eq(frame.x, 0.0, "%s idle frame stays in its only column" % id)
		sprite.set_move_speed(3.4)
		sprite.set_anim(UnitVisual.Anim.WALK)
		for step in 8:
			sprite._process(0.12)
			frame = material.get_shader_parameter("frame")
			assert_eq(frame.x, 0.0, "%s walk step %d stays in its only column" % [id, step])
		sprite.free()
