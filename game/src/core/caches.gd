class_name Caches
extends RefCounted
## Static mesh/material/texture caches are released here when a game or the app shuts down, so no
## resources outlive the scene tree (Godot reports those as leaks at exit).


static func clear_all() -> void:
	MeshKit.clear_cache()
	ChunkView.clear_cache()
	UnitView.clear_cache()
	UiTheme.clear_cache()
	UnitVisualFactory.clear_cache()
	PropMeshes._cache.clear()
	BuildingVisuals._cache.clear()
	Icons._icon_cache.clear()
	Icons._item_cache.clear()
	Vfx._mats.clear()
	Vfx._mesh = null
