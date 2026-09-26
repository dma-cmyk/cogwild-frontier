extends Node3D
## Machine showcase under the in-game camera and light (art review). Optional user arg
## --zoom=<size> (default 17).

func _ready() -> void:
	var size := 17.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--zoom="):
			size = float(arg.substr(7))
	var k := MeshKit.new()
	k.box(Vector3(0, -0.05, 0), Vector3(40, 0.1, 40), Color("#79ad4f"))
	var ground := MeshInstance3D.new()
	ground.mesh = k.build()
	add_child(ground)
	var rng := RandomNumberGenerator.new()
	var fc := Color("#3a5da8")
	var items := [
		[AppearanceGen.robot(_r(1), "walker", "frontier", fc), Vector3(-3.5, 0, 1.5), UnitVisual.Anim.WALK],
		[AppearanceGen.robot(_r(2), "work_bot", "frontier", fc), Vector3(-1.2, 0, 3.5), UnitVisual.Anim.IDLE],
		[AppearanceGen.robot(_r(3), "work_bot", "frontier", fc), Vector3(0.4, 0, 4.5), UnitVisual.Anim.WALK],
		[AppearanceGen.robot(_r(4), "hauler", "frontier", fc), Vector3(1.8, 0, 3.0), UnitVisual.Anim.IDLE],
		[AppearanceGen.robot(_r(5), "sentry", "ancient", Color("#ff6a2a")), Vector3(3.5, 0, 1.0), UnitVisual.Anim.IDLE],
		[AppearanceGen.robot(_r(6), "turret", "ancient", Color("#ff6a2a")), Vector3(5.2, 0, -1.2), UnitVisual.Anim.IDLE],
		[AppearanceGen.robot(_r(7), "walker", "ancient", Color("#ff6a2a")), Vector3(3.0, 0, -3.0), UnitVisual.Anim.IDLE],
		[AppearanceGen.drone(_r(8), "scout_drone", "frontier", fc), Vector3(-0.8, 3.0, 1.5), UnitVisual.Anim.IDLE],
		[AppearanceGen.drone(_r(9), "repair_drone", "frontier", fc), Vector3(0.8, 2.6, 0.8), UnitVisual.Anim.IDLE],
		[AppearanceGen.drone(_r(10), "war_drone", "ancient", Color("#ff6a2a")), Vector3(2.2, 3.2, -0.2), UnitVisual.Anim.IDLE],
		[AppearanceGen.airship(_r(11), "cargo_airship", "frontier", fc), Vector3(-4.0, 6.0, -6.0), UnitVisual.Anim.IDLE],
		[AppearanceGen.airship(_r(12), "trader_airship", "merchant", Color("#4f8a4b")), Vector3(6.5, 7.0, -9.0), UnitVisual.Anim.IDLE],
	]
	for it: Array in items:
		var v := UnitVisualFactory.create(it[0])
		add_child(v)
		v.position = it[1]
		v.set_anim(int(it[2]))
		v.set_move_speed(2.0)
	LookDev.setup_preview(self, Vector3(0, 1.5, 0), size)


func _r(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s * 7919
	return r
