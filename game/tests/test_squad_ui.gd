extends TestCase
## Squad UI-adjacent visual invariants that can be proven without rendering.


func test_combat_floaters_merge_and_stay_bounded() -> void:
	var parent := Node3D.new()
	tree.root.add_child(parent)
	Vfx.spawn_combat_text(parent, &"combat_damage|7|0|", Vector3(2.0, 1.0, 3.0))
	Vfx.spawn_combat_text(parent, &"combat_damage|5|1|", Vector3(2.1, 1.0, 3.1))
	assert_eq(parent.get_child_count(), 1, "nearby damage merges per target")
	var merged := parent.get_child(0) as Label3D
	assert_eq(merged.text, "-12", "merged damage total")
	for index in Vfx.MAX_COMBAT_TEXTS + 8:
		Vfx.spawn_combat_text(parent, &"combat_tactic|Flank!", Vector3(float(index) * 2.0, 1.0, 0.0))
	assert_eq(parent.get_child_count(), Vfx.MAX_COMBAT_TEXTS, "combat floater cap")
	parent.queue_free()
	await tree.process_frame
