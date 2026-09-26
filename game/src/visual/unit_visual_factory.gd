class_name UnitVisualFactory
extends RefCounted
## Builds units from DNA and reuses immutable ArrayMesh instances by content.

static var _mesh_cache: Dictionary = {}

static func create(dna: Dictionary) -> UnitVisual:
	var normalized := dna.duplicate(true)
	if not normalized.has("kind"): normalized["kind"] = "character"
	var key := JSON.stringify(normalized, "", false)
	var meshes: Array
	if _mesh_cache.has(key):
		meshes = _mesh_cache[key] as Array
	else:
		meshes = UnitVisual.build_meshes(normalized)
		_mesh_cache[key] = meshes
	var visual := UnitVisual.new()
	visual.name = "%s_%s" % [str(normalized.get("kind", "unit")), str(normalized.get("seed", 0))]
	visual.configure(normalized, meshes)
	return visual

static func clear_cache() -> void:
	_mesh_cache.clear()

static func cache_size() -> int:
	return _mesh_cache.size()
