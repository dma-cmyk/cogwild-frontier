extends SceneTree
## Throwaway geometry report for the VisualWorld rework (triangles + footprint fit).

func _initialize() -> void:
	var worst := 0
	for id: String in BuildingVisuals.SITE_FOOTPRINTS.keys():
		var b := BuildingVisuals.create(id, "frontier", 3, 3)
		var mesh: ArrayMesh = (b.get_node("StaticBody") as MeshInstance3D).mesh
		var tris := 0
		if mesh.get_surface_count() > 0:
			tris = (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		var aabb := mesh.get_aabb()
		var fp: Vector2i = BuildingVisuals.footprint(id)
		var ox := maxf(aabb.position.x * -1.0 - float(fp.x) * 0.5, aabb.end.x - float(fp.x) * 0.5)
		var oz := maxf(aabb.position.z * -1.0 - float(fp.y) * 0.5, aabb.end.z - float(fp.y) * 0.5)
		worst = maxi(worst, tris)
		print("%-16s tris=%5d  top=%.2f  overhang x=%+.2f z=%+.2f  %s" % [
			id, tris, aabb.end.y, ox, oz, "OVER" if maxf(ox, oz) > 0.3 else ""])
		b.free()
	print("max tris ", worst)
	quit()
