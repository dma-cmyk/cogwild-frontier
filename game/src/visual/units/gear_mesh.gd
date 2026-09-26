class_name GearMesh
extends RefCounted
## Weapons, tools and carried resources (authored around the shoulder, right arm).

static func arm_pose(weapon: String, carry: String) -> Vector3:
	if not carry.is_empty():
		return Vector3(15.0, -10.0, -15.0) # reaching forward/up slightly to hold box
	
	match weapon:
		"sword", "dagger", "axe", "hammer", "mace", "pickaxe", "hoe", "wrench", "torch":
			return Vector3(10.0, 0.0, -5.0)
		"spear", "staff":
			return Vector3(15.0, 0.0, -10.0)
		"bow", "crossbow", "rifle", "pistol":
			return Vector3(5.0, 10.0, -5.0)
		_:
			return Vector3(5.0, 0.0, -5.0)


static func held(kit: MeshKit, d: Dictionary, c: Dictionary, weapon: String, h: float) -> void:
	if weapon.is_empty() or weapon == "none":
		return
		
	var w_col: Color = c.wood
	var m_col: Color = c.metal
	var d_col: Color = c.dark_metal
	var g_col: Color = c.glow
	
	kit.push_trs(Vector3(0, -0.02, 0)) # move from wrist to grip center

	match weapon:
		"sword":
			# grip
			kit.cylinder(Vector3(0, 0, 0), h * 0.12, 0.015, c.leather, 6)
			# crossguard
			kit.box(Vector3(0, h * 0.07, 0), Vector3(0.10, 0.02, 0.03), m_col)
			# blade
			kit.prism_xz(PackedVector2Array([Vector2(-0.025, 0.0), Vector2(0.0, 0.01), Vector2(0.025, 0.0), Vector2(0.0, -0.01)]),
				h * 0.08, h * 0.45, m_col.lightened(0.1))
			kit.prism_xz(PackedVector2Array([Vector2(-0.025, 0.0), Vector2(0.0, 0.01), Vector2(0.025, 0.0), Vector2(0.0, -0.01)]),
				h * 0.45, h * 0.52, m_col.lightened(0.1), Vector2(0, 0))
		"dagger":
			kit.cylinder(Vector3(0, 0, 0), h * 0.06, 0.013, c.leather, 5)
			kit.box(Vector3(0, h * 0.04, 0), Vector3(0.06, 0.015, 0.02), m_col)
			kit.prism_xz(PackedVector2Array([Vector2(-0.015, 0.0), Vector2(0.0, 0.005), Vector2(0.015, 0.0), Vector2(0.0, -0.005)]),
				h * 0.05, h * 0.22, m_col.lightened(0.1), Vector2(0, 0))
		"axe":
			kit.cylinder(Vector3(0, 0, 0), h * 0.40, 0.018, w_col, 6)
			kit.push_trs(Vector3(0, h * 0.17, 0.05), Vector3(0, 90.0, 0))
			kit.prism_xz(PackedVector2Array([Vector2(-0.05, -0.02), Vector2(-0.10, 0.02), Vector2(0.10, 0.02), Vector2(0.05, -0.02)]),
				-0.015, 0.015, d_col)
			kit.prism_xz(PackedVector2Array([Vector2(-0.10, 0.02), Vector2(-0.11, 0.04), Vector2(0.11, 0.04), Vector2(0.10, 0.02)]),
				-0.012, 0.012, m_col)
			kit.pop()
		"pickaxe":
			kit.cylinder(Vector3(0, 0, 0), h * 0.42, 0.018, w_col, 6)
			kit.push_trs(Vector3(0, h * 0.18, 0))
			kit.box(Vector3(0, 0, 0), Vector3(0.05, 0.04, 0.35), d_col)
			kit.box(Vector3(0, 0, -0.19), Vector3(0.03, 0.02, 0.08), m_col)
			kit.box(Vector3(0, 0, 0.19), Vector3(0.03, 0.02, 0.08), m_col)
			kit.pop()
		"hammer":
			kit.cylinder(Vector3(0, 0, 0), h * 0.35, 0.018, w_col, 6)
			kit.box(Vector3(0, h * 0.16, 0.04), Vector3(0.08, 0.10, 0.18), d_col)
			kit.box(Vector3(0, h * 0.16, 0.14), Vector3(0.09, 0.11, 0.03), m_col)
		"hoe":
			kit.cylinder(Vector3(0, 0, 0), h * 0.50, 0.018, w_col, 6)
			kit.push_trs(Vector3(0, h * 0.23, 0))
			kit.box(Vector3(0, 0, 0.06), Vector3(0.04, 0.03, 0.12), d_col)
			kit.box(Vector3(0, -0.06, 0.12), Vector3(0.16, 0.12, 0.01), m_col)
			kit.pop()
		"wrench":
			kit.box(Vector3(0, 0, 0), Vector3(0.03, h * 0.45, 0.02), m_col)
			kit.box(Vector3(0, h * 0.22, 0), Vector3(0.12, 0.08, 0.03), m_col)
			kit.box(Vector3(0.04, h * 0.27, 0), Vector3(0.03, 0.06, 0.03), m_col)
			kit.box(Vector3(-0.04, h * 0.27, 0), Vector3(0.03, 0.06, 0.03), m_col)
		"mace":
			kit.cylinder(Vector3(0, 0, 0), h * 0.35, 0.018, m_col, 6)
			kit.ellipsoid(Vector3(0, h * 0.17, 0), Vector3(0.08, 0.10, 0.08), d_col, 6, 4)
			# spikes
			for i in 4:
				kit.push_trs(Vector3(0, h * 0.17, 0), Vector3(0, i * 90.0, 0))
				kit.box(Vector3(0, 0, 0.09), Vector3(0.02, 0.02, 0.04), m_col)
				kit.pop()
		"spear":
			kit.cylinder(Vector3(0, 0, 0), h * 0.8, 0.016, w_col, 6)
			kit.prism_xz(PackedVector2Array([Vector2(-0.02, 0.0), Vector2(0.0, 0.01), Vector2(0.02, 0.0), Vector2(0.0, -0.01)]),
				h * 0.4, h * 0.52, m_col.lightened(0.1), Vector2(0, 0))
		"staff":
			kit.cylinder(Vector3(0, 0, 0), h * 0.85, 0.018, w_col, 6)
			kit.ellipsoid(Vector3(0, h * 0.44, 0), Vector3(0.05, 0.07, 0.05), g_col, 6, 4)
		"bow":
			kit.push_trs(Vector3(0, 0, 0.15))
			kit.box(Vector3(0, 0, 0), Vector3(0.025, h * 0.5, 0.025), w_col)
			kit.box(Vector3(0, h * 0.25, -0.04), Vector3(0.02, 0.015, 0.08), w_col)
			kit.box(Vector3(0, -h * 0.25, -0.04), Vector3(0.02, 0.015, 0.08), w_col)
			kit.tube(Vector3(0, h * 0.25, -0.08), Vector3(0, -h * 0.25, -0.08), 0.005, c.leather, 3)
			kit.pop()
		"crossbow":
			kit.box(Vector3(0, 0, 0.15), Vector3(0.04, 0.04, h * 0.35), w_col)
			kit.box(Vector3(0, 0.01, 0.30), Vector3(h * 0.35, 0.02, 0.04), d_col)
		"rifle":
			kit.box(Vector3(0, -0.03, -0.08), Vector3(0.035, 0.06, 0.20), w_col)
			kit.box(Vector3(0, 0, 0.15), Vector3(0.035, 0.04, 0.35), w_col)
			kit.cylinder(Vector3(0, 0.03, 0.25), 0.35, 0.015, d_col, 5)
		"pistol":
			kit.box(Vector3(0, -0.03, -0.02), Vector3(0.03, 0.08, 0.04), w_col)
			kit.box(Vector3(0, 0.02, 0.05), Vector3(0.03, 0.04, 0.15), d_col)
			kit.cylinder(Vector3(0, 0.02, 0.12), 0.18, 0.012, d_col, 5)
		"torch":
			kit.cylinder(Vector3(0, 0, 0), h * 0.25, 0.015, w_col, 5)
			kit.box(Vector3(0, h * 0.13, 0), Vector3(0.04, 0.04, 0.04), d_col)
			kit.ellipsoid(Vector3(0, h * 0.16, 0), Vector3(0.04, 0.06, 0.04), MeshKit.glow(UnitStyle.col("#ff6a2a", "#ff6a2a"), 1.0), 5, 3)
		_:
			pass
	kit.pop()


static func carry_load(kit: MeshKit, d: Dictionary, c: Dictionary, carry: String, h: float) -> void:
	if carry.is_empty():
		return
	
	kit.push_trs(Vector3(0, 0.15, 0)) # Shift up to fit in arms
	match carry:
		"wood":
			for i in 3:
				for j in 2:
					kit.cylinder(Vector3((i - 1) * 0.08, j * 0.08, 0), 0.4, 0.035, c.wood, 6)
		"stone":
			kit.box(Vector3(0, 0, 0), Vector3(0.25, 0.25, 0.25), UnitStyle.col("#9a958c", "#9a958c"))
			kit.box(Vector3(0, 0.1, 0.05), Vector3(0.2, 0.15, 0.2), UnitStyle.col("#8d8f86", "#8d8f86"))
		"ore":
			kit.box(Vector3(0, 0, 0), Vector3(0.25, 0.25, 0.25), UnitStyle.col("#5b6470", "#5b6470"))
			kit.ellipsoid(Vector3(0, 0, 0), Vector3(0.15, 0.15, 0.15), c.dark_metal, 5, 4)
		"metal":
			for i in 3:
				kit.box(Vector3(0, i * 0.05, 0), Vector3(0.3, 0.04, 0.15), c.metal)
		"food":
			# Sack
			kit.frustum(Vector3(0, -0.05, 0), 0.2, 0.15, 0.1, UnitStyle.col("#e9dcc0", "#e9dcc0"), 8)
			kit.cylinder(Vector3(0, 0.17, 0), 0.05, 0.05, UnitStyle.col("#e9dcc0", "#e9dcc0"), 8)
		"gold":
			for i in 2:
				for j in 3:
					kit.box(Vector3((j - 1) * 0.1, i * 0.05, 0), Vector3(0.08, 0.04, 0.15), UnitStyle.col("#d9b04c", "#d9b04c"))
		"crate":
			kit.box(Vector3(0, 0, 0), Vector3(0.35, 0.25, 0.25), c.wood)
			# Straps
			kit.box(Vector3(0, 0, 0), Vector3(0.36, 0.26, 0.02), c.metal)
			kit.box(Vector3(0, 0, 0), Vector3(0.02, 0.26, 0.26), c.metal)
		_:
			pass
	kit.pop()
