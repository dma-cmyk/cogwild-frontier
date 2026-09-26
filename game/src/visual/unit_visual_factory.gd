class_name UnitVisualFactory
extends RefCounted
## Builds unit visuals from DNA: the painted chip-sheet sprite when SpriteLibrary has one for the
## unit, otherwise the procedural low-poly model (immutable ArrayMeshes reused by content).
## `hints` may carry {archetype, role, named} from the Unit (see SpriteLibrary.chip_id).

static var _mesh_cache: Dictionary = {}


static func create(dna: Dictionary, hints: Dictionary = {}) -> UnitVisual:
	var normalized := dna.duplicate(true)
	if not normalized.has("kind"):
		normalized["kind"] = "character"
	var entry := SpriteLibrary.chip(normalized, hints)
	if not entry.is_empty():
		var sv := SpriteUnitVisual.new()
		sv.name = "%s_%s" % [str(normalized.get("kind", "unit")), str(normalized.get("seed", 0))]
		sv.setup_sprite(normalized, entry, hints)
		if str(normalized.get("kind", "")) in ["drone", "airship"]:
			sv.card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return sv
	return create_mesh(normalized)


## The procedural low-poly model regardless of painted art (fallback, galleries, mesh tests).
static func create_mesh(dna: Dictionary) -> UnitVisual:
	var normalized := dna.duplicate(true)
	if not normalized.has("kind"):
		normalized["kind"] = "character"
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
