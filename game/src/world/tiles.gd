class_name Tiles
extends RefCounted
## Terrain tile types and harvestable resource nodes (one per tile) with their rules.

enum { DEEP_WATER, SHALLOW_WATER, SAND, GRASS, MEADOW, FOREST, DIRT, ROCK, CLIFF, TRAIL, BRIDGE, FARMLAND, PAVED }

const NAMES := ["Deep water", "Shallows", "Sand", "Grass", "Meadow", "Forest floor", "Dirt", "Stony ground",
	"Cliff", "Trail", "Bridge", "Farmland", "Road"]
const WALKABLE := [false, true, true, true, true, true, true, true, false, true, true, true, true]
## Movement cost multipliers for pathfinding (lower = preferred).
const COST := [1.0, 2.4, 1.15, 1.0, 1.0, 1.1, 1.0, 1.25, 1.0, 0.7, 0.72, 1.15, 0.55]
## Base terrain colours (sRGB), also used for the minimap.
const COLORS := [
	Color("#2f6f8f"), Color("#4fa3b5"), Color("#d9c68f"), Color("#79ad4f"), Color("#93bb57"),
	Color("#5b8c3e"), Color("#a08058"), Color("#9c9788"), Color("#8a8479"), Color("#c2a36f"),
	Color("#8a5a34"), Color("#7a5a3a"), Color("#b9ad94")]

## Tiles where buildings may be placed.
const BUILDABLE := [false, false, true, true, true, true, true, true, false, true, false, false, true]

# --- resource nodes -------------------------------------------------------------------------
enum Res { NONE, TREE_PINE, TREE_OAK, TREE_BIRCH, TREE_DEAD, ROCK_SMALL, ROCK_LARGE, ORE_IRON, ORE_CRYSTAL, BERRY_BUSH, BUSH }

## id: prop mesh id; yield: colony resource; amount: [min, max] initial; solid: blocks movement;
## job: gatherer action; work: seconds of work per load at skill 30; regrow: days to regrow (0 = no).
const RES_INFO := {
	Res.TREE_PINE: {"id": "tree_pine", "yield": "wood", "amount": [5, 8], "solid": false, "job": "chop", "work": 5.0, "skill": "woodcutting", "regrow": 0},
	Res.TREE_OAK: {"id": "tree_oak", "yield": "wood", "amount": [6, 9], "solid": false, "job": "chop", "work": 6.0, "skill": "woodcutting", "regrow": 0},
	Res.TREE_BIRCH: {"id": "tree_birch", "yield": "wood", "amount": [4, 6], "solid": false, "job": "chop", "work": 4.0, "skill": "woodcutting", "regrow": 0},
	Res.TREE_DEAD: {"id": "tree_dead", "yield": "wood", "amount": [2, 4], "solid": false, "job": "chop", "work": 3.0, "skill": "woodcutting", "regrow": 0},
	Res.ROCK_SMALL: {"id": "rock_small", "yield": "stone", "amount": [4, 7], "solid": false, "job": "mine", "work": 5.0, "skill": "mining", "regrow": 0},
	Res.ROCK_LARGE: {"id": "rock_large", "yield": "stone", "amount": [12, 20], "solid": true, "job": "mine", "work": 6.0, "skill": "mining", "regrow": 0},
	Res.ORE_IRON: {"id": "ore_iron", "yield": "ore", "amount": [10, 16], "solid": true, "job": "mine", "work": 7.0, "skill": "mining", "regrow": 0},
	Res.ORE_CRYSTAL: {"id": "ore_crystal", "yield": "energy", "amount": [8, 14], "solid": true, "job": "mine", "work": 8.0, "skill": "mining", "regrow": 0},
	Res.BERRY_BUSH: {"id": "berry_bush", "yield": "food", "amount": [4, 6], "solid": false, "job": "forage", "work": 3.0, "skill": "farming", "regrow": 2},
	Res.BUSH: {"id": "bush", "yield": "", "amount": [0, 0], "solid": false, "job": "", "work": 0.0, "skill": "", "regrow": 0},
}

## Extra path cost added by a (non-solid) resource node on the tile.
const RES_PATH_COST := {Res.TREE_PINE: 0.9, Res.TREE_OAK: 0.9, Res.TREE_BIRCH: 0.8, Res.TREE_DEAD: 0.5,
	Res.ROCK_SMALL: 0.6, Res.BERRY_BUSH: 0.3, Res.BUSH: 0.3}


static func is_water(t: int) -> bool:
	return t == DEEP_WATER or t == SHALLOW_WATER


static func res_info(r: int) -> Dictionary:
	return RES_INFO.get(r, {})


static func is_tree(r: int) -> bool:
	return r >= Res.TREE_PINE and r <= Res.TREE_DEAD


## Which zone designation harvests this node ("logging", "mining", "forage") or "".
static func zone_for(r: int) -> String:
	match r:
		Res.TREE_PINE, Res.TREE_OAK, Res.TREE_BIRCH, Res.TREE_DEAD:
			return "logging"
		Res.ROCK_SMALL, Res.ROCK_LARGE, Res.ORE_IRON, Res.ORE_CRYSTAL:
			return "mining"
		Res.BERRY_BUSH:
			return "forage"
	return ""
