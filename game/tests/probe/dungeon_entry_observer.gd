extends Node
## Pause on the real transfer signal so a UI probe can inspect both maps without fighting on.
var game: Game
var entrance_id := -1
var entered := false
var returned := false

func setup(scene: Game, eid: int) -> void:
	game = scene
	entrance_id = eid
	game.world.dungeons.relocated.connect(_on_relocated)

func _on_relocated(_pos: Vector2, eid: int, floor_index: int) -> void:
	if eid != entrance_id:
		return
	if floor_index >= 0:
		entered = true
	else:
		returned = entered
	game.set_speed(0)


func ground_visible() -> bool:
	var centre := game.world.squad_ai.center(game.world.squads[0])
	var chunk: ChunkView = game.view.chunk_views.get(game.world.chunk_key(Vector2i(centre)))
	return chunk != null and chunk.terrain_mi != null and chunk.terrain_mi.mesh != null \
		and chunk.terrain_mi.is_visible_in_tree() and chunk.terrain_mi.mesh.get_surface_count() > 0
