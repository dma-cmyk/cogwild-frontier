class_name ChunkData
extends RefCounted
## One 32×32-tile chunk: generated deterministically from the world seed, plus the player's
## modifications (recorded separately so saves only store deltas).

const S := 32

var cx: int
var cz: int
## Corner heights, (S+1)×(S+1), index = z * (S + 1) + x.
var heights := PackedFloat32Array()
var terrain := PackedByteArray()
## 1 = occupied by a structure or building (not walkable, not buildable).
var blocked := PackedByteArray()
var res_type := PackedByteArray()
var res_amount := PackedByteArray()
var res_var := PackedByteArray()
## Purely visual scatter: [[prop_id, local_x, local_z, rot_y, scale], ...].
var decor: Array = []
## Sites whose centre lies in this chunk (ids into WorldGen sites).
var site_ids: Array = []

## Player/world modifications since generation (saved): tile index -> value.
var mod_res: Dictionary = {}  # index -> [type, amount]
var mod_terrain: Dictionary = {}  # index -> terrain type
var mod_height: Dictionary = {}  # corner index -> height (building foundations)
## Regrowth schedule: tile index -> [type, day].
var regrow: Dictionary = {}
## Bumped on every change so views know when to rebuild.
var version := 0
var res_version := 0


func _init(p_cx: int = 0, p_cz: int = 0) -> void:
	cx = p_cx
	cz = p_cz
	heights.resize((S + 1) * (S + 1))
	terrain.resize(S * S)
	blocked.resize(S * S)
	res_type.resize(S * S)
	res_amount.resize(S * S)
	res_var.resize(S * S)


func origin() -> Vector2i:
	return Vector2i(cx * S, cz * S)


static func idx(lx: int, lz: int) -> int:
	return lz * S + lx


func corner(lx: int, lz: int) -> float:
	return heights[lz * (S + 1) + lx]


## Height at local continuous coordinates (0..S) by bilinear interpolation of the corners.
func height_local(x: float, z: float) -> float:
	var ix := clampi(int(floor(x)), 0, S - 1)
	var iz := clampi(int(floor(z)), 0, S - 1)
	var fx := clampf(x - ix, 0.0, 1.0)
	var fz := clampf(z - iz, 0.0, 1.0)
	var h00 := corner(ix, iz)
	var h10 := corner(ix + 1, iz)
	var h01 := corner(ix, iz + 1)
	var h11 := corner(ix + 1, iz + 1)
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)


func set_resource(i: int, type: int, amount: int) -> void:
	res_type[i] = type
	res_amount[i] = clampi(amount, 0, 255)
	mod_res[i] = [type, clampi(amount, 0, 255)]
	res_version += 1
	version += 1


func set_terrain(i: int, t: int) -> void:
	terrain[i] = t
	mod_terrain[i] = t
	version += 1


func set_corner_height(ci: int, h: float) -> void:
	heights[ci] = h
	mod_height[ci] = h
	version += 1


## Re-applies saved modifications after regeneration.
func apply_mods(p_mod_res: Dictionary, p_mod_terrain: Dictionary, p_regrow: Dictionary, p_mod_height: Dictionary = {}) -> void:
	for k: Variant in p_mod_height:
		heights[int(k)] = float(p_mod_height[k])
		mod_height[int(k)] = float(p_mod_height[k])
	for k: Variant in p_mod_res:
		var i := int(k)
		var v: Array = p_mod_res[k]
		res_type[i] = int(v[0])
		res_amount[i] = int(v[1])
		mod_res[i] = [int(v[0]), int(v[1])]
	for k: Variant in p_mod_terrain:
		var i := int(k)
		terrain[i] = int(p_mod_terrain[k])
		mod_terrain[i] = int(p_mod_terrain[k])
	for k: Variant in p_regrow:
		regrow[int(k)] = p_regrow[k]
	version += 1
	res_version += 1
