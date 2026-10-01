class_name ZoneShape
extends RefCounted
## Pure helpers for exact tile-set work zones and their derived display geometry.

const CARDINALS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


static func contains(zone: Dictionary, tile: Vector2i) -> bool:
	var tiles: Dictionary = zone.get("tiles", {})
	return tiles.has(tile)


static func tiles_from_rect(rect: Rect2i) -> Dictionary:
	var tiles := {}
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			tiles[Vector2i(x, y)] = true
	return tiles


static func sorted_tiles(tiles: Dictionary) -> Array[Vector2i]:
	var ordered: Array[Vector2i] = []
	for tile: Variant in tiles:
		if tile is Vector2i:
			ordered.append(tile)
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	return ordered


static func bounds(tiles: Dictionary) -> Rect2i:
	var ordered := sorted_tiles(tiles)
	if ordered.is_empty():
		return Rect2i()
	var min_x := ordered[0].x
	var max_x := ordered[0].x
	var min_y := ordered[0].y
	var max_y := ordered[0].y
	for tile: Vector2i in ordered:
		min_x = mini(min_x, tile.x)
		max_x = maxi(max_x, tile.x)
		min_y = mini(min_y, tile.y)
		max_y = maxi(max_y, tile.y)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


static func outline(tiles: Dictionary) -> PackedVector2Array:
	var edges := PackedVector2Array()
	for tile: Vector2i in sorted_tiles(tiles):
		var x := float(tile.x)
		var y := float(tile.y)
		if not tiles.has(tile + CARDINALS[0]):
			edges.append(Vector2(x, y))
			edges.append(Vector2(x + 1.0, y))
		if not tiles.has(tile + CARDINALS[1]):
			edges.append(Vector2(x + 1.0, y))
			edges.append(Vector2(x + 1.0, y + 1.0))
		if not tiles.has(tile + CARDINALS[2]):
			edges.append(Vector2(x + 1.0, y + 1.0))
			edges.append(Vector2(x, y + 1.0))
		if not tiles.has(tile + CARDINALS[3]):
			edges.append(Vector2(x, y + 1.0))
			edges.append(Vector2(x, y))
	return edges


static func rebuild(zone: Dictionary) -> Dictionary:
	var tiles: Dictionary = zone.get("tiles", {})
	zone["tiles"] = tiles
	zone["rect"] = bounds(tiles)
	zone["outline"] = outline(tiles)
	return zone


static func make_zone(id: int, type: String, tiles: Dictionary) -> Dictionary:
	return rebuild({"id": id, "type": type, "tiles": tiles.duplicate()})


static func touches(first: Dictionary, second: Dictionary) -> bool:
	if first.is_empty() or second.is_empty():
		return false
	var smaller: Dictionary = first
	var larger: Dictionary = second
	if first.size() > second.size():
		smaller = second
		larger = first
	for tile: Vector2i in smaller:
		if larger.has(tile):
			return true
		for offset: Vector2i in CARDINALS:
			if larger.has(tile + offset):
				return true
	return false


static func connected_components(tiles: Dictionary) -> Array[Dictionary]:
	var unvisited := tiles.duplicate()
	var ordered := sorted_tiles(tiles)
	var components: Array[Dictionary] = []
	for first: Vector2i in ordered:
		if not unvisited.has(first):
			continue
		var component := {}
		var frontier: Array[Vector2i] = [first]
		unvisited.erase(first)
		component[first] = true
		while not frontier.is_empty():
			var tile: Vector2i = frontier.pop_back()
			for offset: Vector2i in CARDINALS:
				var neighbor := tile + offset
				if not unvisited.has(neighbor):
					continue
				unvisited.erase(neighbor)
				component[neighbor] = true
				frontier.append(neighbor)
		components.append(component)
	return components


