class_name DungeonZone
extends RefCounted
## Dungeon floors live in a reserved block of the world grid (a corner far from the start), so the
## simulation, navigation, fog of war, saving and every panel keep working unchanged. Each dungeon
## owns one column ("slot") of the block; its floors are stacked down the column. Everything that is
## not a floor tile is solid rock. Floors are pure functions of (seed, dungeon id, floor index,
## difficulty), so nothing but a few numbers has to be saved.

const FLOOR_SIZE := 36
const PITCH := 40  # floor size plus the rock between neighbours
const COLS := 4  # dungeons that can exist at the same time
const ROWS := 10  # deepest possible dungeon
const ZONE_W := COLS * PITCH  # 160 tiles: five chunks
const ZONE_H := 416  # thirteen chunks (ROWS * PITCH = 400 fit inside)
const FLOOR_H := 2.0
const WALL_H := 4.4

enum Kind { WALL, ROOM, CORRIDOR }


## Where the zone sits for a start tile: the edge band on the far side of the start.
static func zone_rect(min_tile: int, max_tile: int, start: Vector2i) -> Rect2i:
	var x0 := min_tile if start.x >= 0 else max_tile - ZONE_W
	return Rect2i(x0, min_tile, ZONE_W, ZONE_H)


static func slot_origin(zone: Rect2i, slot: int, floor_index: int) -> Vector2i:
	return zone.position + Vector2i(slot * PITCH + 2, floor_index * PITCH + 2)


static func floor_rect(zone: Rect2i, slot: int, floor_index: int) -> Rect2i:
	return Rect2i(slot_origin(zone, slot, floor_index), Vector2i(FLOOR_SIZE, FLOOR_SIZE))


## (slot, floor, local x, local z) of a tile, or [] when it is not inside any floor rectangle.
static func locate(zone: Rect2i, t: Vector2i) -> Array:
	if not zone.has_point(t):
		return []
	var rel := t - zone.position
	var slot := rel.x / PITCH
	var row := rel.y / PITCH
	if slot >= COLS or row >= ROWS:
		return []
	var lx := rel.x % PITCH - 2
	var lz := rel.y % PITCH - 2
	if lx < 0 or lz < 0 or lx >= FLOOR_SIZE or lz >= FLOOR_SIZE:
		return []
	return [slot, row, lx, lz]


static func _floors_for(difficulty: int, rng: RandomNumberGenerator) -> int:
	var ranges := {1: [2, 3], 2: [3, 4], 3: [4, 6], 4: [6, 8], 5: [8, 10]}
	var r: Array = ranges[clampi(difficulty, 1, 5)]
	return rng.randi_range(int(r[0]), int(r[1]))


static func floors_for(difficulty: int, rng: RandomNumberGenerator) -> int:
	return clampi(_floors_for(difficulty, rng), 2, ROWS)


# --- floor generation -------------------------------------------------------------------------

static func _room_ok(rooms: Array, r: Rect2i, gap: int) -> bool:
	for other: Rect2i in rooms:
		if other.grow(gap).intersects(r):
			return false
	return true


static func _carve_rect(tiles: PackedByteArray, r: Rect2i, kind: int) -> void:
	for z in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if x < 2 or z < 2 or x >= FLOOR_SIZE - 2 or z >= FLOOR_SIZE - 2:
				continue
			var i := z * FLOOR_SIZE + x
			if kind == Kind.CORRIDOR and tiles[i] == Kind.ROOM:
				continue
			tiles[i] = kind


static func _carve_corridor(tiles: PackedByteArray, a: Vector2i, b: Vector2i, horizontal_first: bool) -> void:
	var corner := Vector2i(b.x, a.y) if horizontal_first else Vector2i(a.x, b.y)
	for leg: Array in [[a, corner], [corner, b]]:
		var p: Vector2i = leg[0]
		var q: Vector2i = leg[1]
		var lo := Vector2i(mini(p.x, q.x), mini(p.y, q.y))
		var hi := Vector2i(maxi(p.x, q.x), maxi(p.y, q.y))
		_carve_rect(tiles, Rect2i(lo, hi - lo + Vector2i(2, 2)), Kind.CORRIDOR)


## Walls need two tiles of thickness to read as walls with the terrain mesh: fill any wall that
## has floor on both sides of it.
static func _fill_thin_walls(tiles: PackedByteArray) -> void:
	for _pass in 3:
		var changed := false
		for z in range(1, FLOOR_SIZE - 1):
			for x in range(1, FLOOR_SIZE - 1):
				var i := z * FLOOR_SIZE + x
				if tiles[i] != Kind.WALL:
					continue
				var horizontal := tiles[i - 1] != Kind.WALL and tiles[i + 1] != Kind.WALL
				var vertical := tiles[i - FLOOR_SIZE] != Kind.WALL and tiles[i + FLOOR_SIZE] != Kind.WALL
				if horizontal or vertical:
					tiles[i] = Kind.CORRIDOR
					changed = true
		if not changed:
			break


static func _bfs(tiles: PackedByteArray, from: Vector2i) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(FLOOR_SIZE * FLOOR_SIZE)
	dist.fill(-1)
	var queue: Array[Vector2i] = [from]
	dist[from.y * FLOOR_SIZE + from.x] = 0
	var head := 0
	while head < queue.size():
		var p := queue[head]
		head += 1
		var d := dist[p.y * FLOOR_SIZE + p.x]
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q := p + step
			if q.x < 0 or q.y < 0 or q.x >= FLOOR_SIZE or q.y >= FLOOR_SIZE:
				continue
			var j := q.y * FLOOR_SIZE + q.x
			if tiles[j] == Kind.WALL or dist[j] >= 0:
				continue
			dist[j] = d + 1
			queue.append(q)
	return dist


## One floor: {tiles, rooms, start_room, dest_room, boss_room, up, down, arrival, chests, spawn_rooms}.
## All positions are local to the floor (0..FLOOR_SIZE-1). `down` is (-1,-1) on the last floor.
static func generate_floor(seed_value: int, dungeon_id: int, floor_index: int, difficulty: int, floors: int) -> Dictionary:
	var rng := RngUtil.make([seed_value, "dungeon_floor", dungeon_id, floor_index])
	var tiles := PackedByteArray()
	tiles.resize(FLOOR_SIZE * FLOOR_SIZE)
	tiles.fill(Kind.WALL)
	var last := floor_index == floors - 1
	var rooms: Array = []
	var boss_index := -1
	if last:
		for attempt in 40:
			var bw := rng.randi_range(11, 13)
			var bh := rng.randi_range(11, 13)
			var br := Rect2i(rng.randi_range(3, FLOOR_SIZE - 3 - bw), rng.randi_range(3, FLOOR_SIZE - 3 - bh), bw, bh)
			if br.end.x <= FLOOR_SIZE - 3 and br.end.y <= FLOOR_SIZE - 3:
				rooms.append(br)
				boss_index = 0
				break
	var target := rng.randi_range(5, 8)
	for attempt in 120:
		if rooms.size() >= target:
			break
		var w := rng.randi_range(5, 9)
		var h := rng.randi_range(5, 9)
		var r := Rect2i(rng.randi_range(3, FLOOR_SIZE - 3 - w), rng.randi_range(3, FLOOR_SIZE - 3 - h), w, h)
		if _room_ok(rooms, r, 3):
			rooms.append(r)
	# Always enough rooms, even when the dice place them badly.
	var fallback_grid := [Vector2i(4, 4), Vector2i(22, 4), Vector2i(4, 22), Vector2i(22, 22)]
	var gi := 0
	while rooms.size() < 4 and gi < fallback_grid.size():
		var fr := Rect2i(fallback_grid[gi], Vector2i(8, 8))
		gi += 1
		if _room_ok(rooms, fr, 3):
			rooms.append(fr)
	for r: Rect2i in rooms:
		_carve_rect(tiles, r, Kind.ROOM)
	# Chain the rooms by nearest neighbour, then add a loop or two.
	var centers: Array[Vector2i] = []
	for r: Rect2i in rooms:
		centers.append(r.position + r.size / 2)
	var order: Array[int] = [0]
	var left: Array[int] = []
	for i in range(1, rooms.size()):
		left.append(i)
	while not left.is_empty():
		var from := centers[order[order.size() - 1]]
		var best := 0
		var best_d := INF
		for k in left.size():
			var d := Vector2(from).distance_squared_to(Vector2(centers[left[k]]))
			if d < best_d:
				best_d = d
				best = k
		order.append(left[best])
		left.remove_at(best)
	for k in range(1, order.size()):
		_carve_corridor(tiles, centers[order[k - 1]], centers[order[k]], rng.randf() < 0.5)
	for extra in rng.randi_range(1, 2):
		var a := rng.randi_range(0, rooms.size() - 1)
		var b := rng.randi_range(0, rooms.size() - 1)
		if a != b:
			_carve_corridor(tiles, centers[a], centers[b], rng.randf() < 0.5)
	_fill_thin_walls(tiles)
	# Start room and stairs: on the last floor the stairs room is the boss room.
	var start_room := 0
	var dest_room := 0
	if last:
		dest_room = boss_index
		var far := -1.0
		for i in rooms.size():
			if i != dest_room:
				var d := Vector2(centers[i]).distance_to(Vector2(centers[dest_room]))
				if d > far:
					far = d
					start_room = i
	else:
		start_room = rng.randi_range(0, rooms.size() - 1)
		var dist := _bfs(tiles, centers[start_room])
		var far_d := -1
		for i in rooms.size():
			if i == start_room:
				continue
			var dd := dist[centers[i].y * FLOOR_SIZE + centers[i].x]
			if dd > far_d:
				far_d = dd
				dest_room = i
	var up := centers[start_room]
	var down := Vector2i(-1, -1) if last else centers[dest_room]
	var chests: Array[Vector2i] = []
	var spawn_rooms: Array[int] = []
	for i in rooms.size():
		if i == start_room:
			continue
		spawn_rooms.append(i)
		if not (last and i == dest_room):
			chests.append((rooms[i] as Rect2i).position + Vector2i(1, 1))
	return {"tiles": tiles, "rooms": rooms, "start_room": start_room, "dest_room": dest_room,
		"boss_room": boss_index if last else -1, "up": up, "down": down,
		"arrival": up + Vector2i(1, 1), "chests": chests, "spawn_rooms": spawn_rooms,
		"center": Vector2i(FLOOR_SIZE / 2, FLOOR_SIZE / 2), "last": last}


static func kind_of(layout: Dictionary, lx: int, lz: int) -> int:
	if layout.is_empty() or lx < 0 or lz < 0 or lx >= FLOOR_SIZE or lz >= FLOOR_SIZE:
		return Kind.WALL
	return (layout["tiles"] as PackedByteArray)[lz * FLOOR_SIZE + lx]


# --- chunk generation -------------------------------------------------------------------------

## Fills a chunk (new or existing) of the zone. `lookup` maps (slot, floor) to a floor layout
## ({} when that floor does not exist).
static func fill_chunk(ch: ChunkData, zone: Rect2i, lookup: Callable) -> void:
	var cache := {}
	var ox := ch.cx * ChunkData.S
	var oz := ch.cz * ChunkData.S
	# tile kind grid for the chunk and a one-tile border (corner heights read four tiles)
	var side := ChunkData.S + 2
	var wall := PackedByteArray()
	wall.resize(side * side)
	for z in side:
		for x in side:
			var t := Vector2i(ox + x - 1, oz + z - 1)
			var loc := locate(zone, t)
			var is_wall := true
			if not loc.is_empty():
				var key: int = int(loc[0]) * 100 + int(loc[1])
				if not cache.has(key):
					cache[key] = lookup.call(int(loc[0]), int(loc[1]))
				is_wall = kind_of(cache[key], int(loc[2]), int(loc[3])) == Kind.WALL
			wall[z * side + x] = 1 if is_wall else 0
	for lz in ChunkData.S + 1:
		for lx in ChunkData.S + 1:
			# corner (lx, lz) touches tiles (lx-1..lx, lz-1..lz) => border-grid indices (lx..lx+1, lz..lz+1)
			var count: int = wall[lz * side + lx] + wall[lz * side + lx + 1] + wall[(lz + 1) * side + lx] + wall[(lz + 1) * side + lx + 1]
			ch.heights[lz * (ChunkData.S + 1) + lx] = WALL_H if count >= 3 else FLOOR_H
	for lz in ChunkData.S:
		for lx in ChunkData.S:
			var i := lz * ChunkData.S + lx
			var is_wall: bool = wall[(lz + 1) * side + lx + 1] == 1
			var tt := Tiles.CLIFF
			if not is_wall:
				var loc := locate(zone, Vector2i(ox + lx, oz + lz))
				var key: int = int(loc[0]) * 100 + int(loc[1])
				tt = Tiles.PAVED if kind_of(cache[key], int(loc[2]), int(loc[3])) == Kind.ROOM else Tiles.ROCK
			ch.terrain[i] = tt
			ch.blocked[i] = 1 if is_wall else 0
			ch.res_type[i] = Tiles.Res.NONE
			ch.res_amount[i] = 0
	ch.decor.clear()
	ch.site_ids.clear()
	ch.version += 1
	ch.res_version += 1
