#!/usr/bin/env python3
"""Writes art_src/prompts.json: every image-generation request used for the game art.

Each entry: {"id", "kind", "args"} where "args" is the exact JSON sent to the image tool
(OMP generate_image, model openai-codex/gpt-image-1). Raw results are stored as
art_src/raw/<id>.<ext>; tools/art/process.py turns them into game assets.
Portrait entries reference their chip sheet as input, so chips must be generated first.
"""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
MODEL = "openai-codex/gpt-image-1"

CHIP_STYLE = ("high quality 16-bit JRPG pixel art, crisp dark outlines, warm limited palette, clean readable "
	"silhouettes, top-down three-quarter view like classic RPG Maker character chips")
WORLD_STYLE = ("detailed painterly pixel art like a modern high-resolution isometric strategy game, crisp dark "
	"outlines, warm saturated colours")
PORTRAIT_STYLE = ("polished anime-style fantasy strategy game character portrait, soft cel shading, clean line art, "
	"warm rim light, expressive eyes, painterly details")
BG = "flat solid pure magenta #FF00FF background filling the whole image, no ground, no shadows, no text, no labels, no grid lines"
ISO = ("classic isometric view: camera looking down about 35 degrees from the south-east, the square footprint forms "
	"a diamond at the bottom, the whole subject centred with empty space around it, nothing touching the image edges")

RACES = {
	"human": ("a human man with short messy brown hair", "a human woman with shoulder-length chestnut hair"),
	"sylvan": ("a Sylvan man (elf-like woodland folk with long pointed ears) with silver-blond hair",
		"a Sylvan woman (elf-like woodland folk with long pointed ears) with long pale-green hair in a braid"),
	"stoutkin": ("a Stoutkin man (short, stocky dwarf-like folk with broad shoulders) with a thick braided copper-red beard",
		"a Stoutkin woman (short, stocky dwarf-like folk with broad shoulders) with copper-red hair in two thick braids"),
	"vulpin": ("a Vulpin man (fox-folk with large orange fox ears and a bushy orange fox tail with a white tip) with orange hair",
		"a Vulpin woman (fox-folk with large orange fox ears and a bushy orange fox tail with a white tip) with long orange hair"),
}
LOOKS = {
	"worker": "wearing a cream linen shirt, brown work trousers, a blue neckerchief, a leather tool belt and a straw hat, a small hand axe hanging at the belt",
	"fighter": "wearing a blue tabard over light chainmail and a round steel helmet, holding a short sword and a round wooden shield with a blue emblem",
	"ranger": "wearing a green hooded cloak with the hood down, a leather tunic and a blue scarf, a short bow and a quiver on the back",
	"engineer": "wearing brown overalls over a blue shirt, brass goggles on the forehead and leather tool pouches, carrying a big steel wrench",
	"scholar": "wearing a long blue and cream robe and a leather satchel, holding a wooden staff with a small hanging lantern",
}

V2_APPEARANCE = {
	"human": ("a human man with tightly curled black hair, a short neat beard",
		"a human woman with dark auburn hair in a high braided bun"),
	"sylvan": ("a Sylvan man (elf-like woodland folk with long pointed ears) with pale silver hair in a short braid",
		"a Sylvan woman (elf-like woodland folk with long pointed ears) with dark violet hair in a braided crown"),
	"stoutkin": ("a Stoutkin man (short, stocky dwarf-like folk with broad shoulders) with a long dark-plum braided beard",
		"a Stoutkin woman (short, stocky dwarf-like folk with broad shoulders) with dark-plum hair in a pair of looped braids"),
	"vulpin": ("a Vulpin man (fox-folk with large russet fox ears and a russet bushy tail with a cream tip) with deep russet hair",
		"a Vulpin woman (fox-folk with large russet fox ears and a russet bushy tail with a cream tip) with dark russet hair in a high ponytail"),
}
V2_LOOKS = {
	"worker": "wearing a warm ochre work shirt, charcoal trousers, a royal-blue company neck scarf, a leather tool belt and a dark green cap, a hand axe at the belt",
	"fighter": "wearing a royal-blue company tabard with a cream sunburst emblem over light chainmail and a steel kettle helmet, holding a short sword and a wooden shield",
	"ranger": "wearing a rust-red hooded cloak with the hood down, a leather tunic and a royal-blue company scarf, carrying a short bow and a quiver",
	"engineer": "wearing charcoal overalls over a rust-red shirt with a royal-blue company neck scarf, brass goggles on the forehead and leather tool pouches, carrying a steel wrench",
	"scholar": "wearing a plum and muted-gold robe with a royal-blue company sash and a dark leather satchel, holding a wooden staff with a small hanging lantern",
}

V3_APPEARANCE = {
	"human": [
		("a young human man with sandy-blond hair in a low ponytail and freckles", "an older human woman with a silver bob, round spectacles and a sturdy build"),
		("an older human man with close-cropped salt-and-pepper hair, a moustache and a scar", "a young human woman with a copper-red undercut and freckles"),
		("a young human man with shoulder-length black curls and a slim build", "an older human woman with dark braided hair and a small mole"),
		("an older human man with wavy white hair and a short beard", "a young human woman with a chestnut pixie cut and round glasses"),
		("a young human man with a shaved head, auburn moustache and freckles", "an older human woman with long ash-blond hair in a braid and a broad build"),
	],
	"sylvan": [
		("a young Sylvan man with long pointed ears and dark forest-green curls", "an older Sylvan woman with long pointed ears, white hair in a high knot and freckles"),
		("an older Sylvan man with long pointed ears, pale-gold hair, a thin beard and spectacles", "a young Sylvan woman with long pointed ears and a short black bob"),
		("a young Sylvan man with long pointed ears and copper hair in a loose braid", "an older Sylvan woman with long pointed ears, silver twin braids and a strong build"),
		("an older Sylvan man with long pointed ears, auburn hair, a moustache and a weathered face", "a young Sylvan woman with long pointed ears, violet-black curls and freckles"),
		("a young Sylvan man with long pointed ears and white shoulder-length hair", "an older Sylvan woman with long pointed ears, dark green hair in a bun and round glasses"),
	],
	"stoutkin": [
		("a young stocky Stoutkin man with a short braided ginger beard and shaved sides", "an older stocky Stoutkin woman with silver hair in a single thick braid and spectacles"),
		("an older broad-shouldered Stoutkin man with a long white beard bound in brass rings", "a young sturdy Stoutkin woman with dark plum twin buns and freckles"),
		("a young stocky Stoutkin man with black curls, a narrow moustache and round glasses", "an older broad Stoutkin woman with copper hair in a crown braid"),
		("an older stocky Stoutkin man with a bald crown, grey side locks and a beard", "a young sturdy Stoutkin woman with short sandy hair and a cheek scar"),
		("a young broad Stoutkin man with pale blond braids and freckles", "an older stocky Stoutkin woman with dark red hair in two long braids and a strong jaw"),
	],
	"vulpin": [
		("a young Vulpin man with large pointed fox ears, a russet tail with cream tip, and dark brown swept-back hair", "an older Vulpin woman with large fox ears, a russet tail with cream tip, silver hair and round spectacles"),
		("an older Vulpin man with large fox ears, a russet tail with cream tip, black hair and a grey moustache", "a young Vulpin woman with large fox ears, a russet tail with cream tip and a short pale-gold bob"),
		("a young Vulpin man with large fox ears, a russet tail with cream tip, and sandy curls with freckles", "an older Vulpin woman with large fox ears, a russet tail with cream tip and dark auburn braids"),
		("an older Vulpin man with large fox ears, a russet tail with cream tip, long cream hair and a thin beard", "a young Vulpin woman with large fox ears, a russet tail with cream tip, charcoal hair and glasses"),
		("a young Vulpin man with large fox ears, a russet tail with cream tip, and dark-red hair in a topknot", "an older Vulpin woman with large fox ears, a russet tail with cream tip, white curls and a broad build"),
	],
}

V3_LOOKS = {
	"worker": "wearing an ochre work shirt, charcoal trousers, a royal-blue company neck scarf, leather tool belt and dark green cap, a hand axe at the belt",
	"fighter": "wearing a royal-blue company tabard with a cream sunburst emblem over light chainmail and steel kettle helmet, holding a short sword and wooden shield",
	"ranger": "wearing a rust-red hooded cloak with hood down, leather tunic and royal-blue company scarf, carrying a short bow and quiver",
	"engineer": "wearing charcoal overalls over a rust-red shirt with a royal-blue company neck scarf, brass goggles on forehead and leather tool pouches, carrying a steel wrench",
	"scholar": "wearing a plum and muted-gold robe with a royal-blue company sash and dark leather satchel, holding a wooden staff with a small hanging lantern",
}

V4_APPEARANCE = {
	"human": ("a human man with dark curly hair, a short beard and a leather cap",
		"a human woman with auburn hair in two braids, freckles and a green headscarf"),
	"sylvan": ("an older Sylvan man with long pointed ears, white hair in a loose braid and a narrow moustache",
		"a young Sylvan woman with long pointed ears, midnight-blue hair in a bob and a small nose ring"),
	"stoutkin": ("a broad Stoutkin man with long iron-grey braids, a square beard and a brass ear cuff",
		"a sturdy Stoutkin woman with black curls in two high buns, a braided beard and a cheek scar"),
	"vulpin": ("a Vulpin man with tall russet fox ears, a russet tail with white tip, black curls and a neat beard",
		"a Vulpin woman with russet fox ears, a russet tail with white tip, pale blond curls and a red hair ribbon"),
}
V5_APPEARANCE = {
	"human": ("an older human man with wavy silver hair, a thick moustache and round spectacles",
		"a young human woman with short black curls, a copper hair clip and a strong jaw"),
	"sylvan": ("an older Sylvan man with long pointed ears, white hair in a loose braid and a narrow moustache",
		"a young Sylvan woman with long pointed ears, midnight-blue hair in a bob and a small nose ring"),
	"stoutkin": ("an older stocky Stoutkin man with a bald crown, russet side braids and a large white beard",
		"a young broad Stoutkin woman with sandy hair in one thick braid, spectacles and a strong jaw"),
	"vulpin": ("an older Vulpin man with large russet fox ears, russet tail with cream tip, a cream beard and dark hair",
		"a young Vulpin woman with large russet fox ears, russet tail with cream tip, dark auburn curls and freckles"),
}
ADDITIONAL_WORKER_LOOK = "wearing a cream work shirt, deep-brown trousers, a royal-blue company neck scarf, a leather tool belt and a rust-red cap, a hand axe at the belt"
ADDITIONAL_WORKER_V5_LOOK = "wearing a muted-olive work shirt, charcoal trousers, a royal-blue company neck scarf, a leather tool belt and a pale linen head wrap, a hand axe at the belt"

def additional_worker_variants(race: str) -> list:
	if race == "sylvan":
		return [(4, V4_APPEARANCE[race], ADDITIONAL_WORKER_V5_LOOK)]
	return [(4, V4_APPEARANCE[race], ADDITIONAL_WORKER_LOOK),
		(5, V5_APPEARANCE[race], ADDITIONAL_WORKER_V5_LOOK)]



def chip_args(left: str, right: str, frames: str = "walking frames: left foot forward, standing, right foot forward",
		reference: str = "") -> dict:
	subject = ("Two RPG character sprite sheets side by side (character chips) for a cozy frontier fantasy game. "
		f"LEFT HALF (columns 1-3): {left}. RIGHT HALF (columns 4-6): {right}. "
		"Each character is drawn 12 times in a strict grid of 4 rows x 3 columns inside its half. "
		"Row 1: moving toward the viewer (front view). Row 2: moving to the left (facing left). "
		"Row 3: moving to the right (facing right). Row 4: moving away from the viewer (back view). "
		f"Each row has 3 {frames}. All 24 figures have identical size and chibi proportions, "
		"each centred in an equal cell with empty space around it.")
	args = {"subject": subject, "style": CHIP_STYLE, "scene": BG,
		"composition": "6 columns x 4 rows evenly spaced grid, whole figures fully visible, nothing touching the image edges",
		"aspect_ratio": "3:2", "image_size": "1536x1024", "model": MODEL}
	if reference:
		args["subject"] += (" Use Image 1 only as style, scale and sprite-sheet layout reference; create different hair, hair colour, accessories and outfit accent colours. "
			"Keep only the royal-blue company cloth accent blue for shader hue rotation; avoid other blue, teal or cyan areas.")
		args["input"] = [{"path": f"art_src/raw/{reference}.webp"}]
	return args


def portrait_args(chip_id: str, left: str, right: str) -> dict:
	subject = ("Two character portraits side by side for a fantasy strategy game UI, based on Image 1 (a pixel-art sprite "
		"sheet with two characters). LEFT portrait: the character from the left half of Image 1 - "
		f"{left}. RIGHT portrait: the character from the right half of Image 1 - {right}. "
		"Keep each character's hair, ears, face and outfit colours exactly as in the sprites.")
	return {"subject": subject, "style": PORTRAIT_STYLE,
		"scene": "each portrait on its own simple dark slate-blue vignette background",
		"composition": "two equal square head-and-shoulders bust portraits side by side, faces slightly above the middle, whole heads visible with space above, no borders, no text",
		"aspect_ratio": "3:2", "image_size": "1536x1024",
		"input": [{"path": f"art_src/raw/{chip_id}.webp"}], "model": MODEL}


def sheet_args(subject: str, rows: int, cols: int) -> dict:
	return {"subject": subject, "style": WORLD_STYLE, "scene": BG,
		"composition": f"{rows} rows x {cols} columns, every asset isolated in its own cell with generous empty space, nothing overlapping or touching the edges, seen from a high three-quarter isometric camera",
		"aspect_ratio": "3:2", "image_size": "1536x1024", "model": MODEL}



def texture_args(subject: str) -> dict:
	return {"subject": f"Seamless tileable ground texture: {subject}.",
		"style": "painterly pixel art like a modern high-resolution isometric strategy game, rich but soft detail",
		"scene": "texture fills the entire image edge to edge, no objects, no borders, no text",
		"composition": "straight top-down orthographic view, flat even lighting without cast shadows, uniform density so it tiles seamlessly",
		"aspect_ratio": "1:1", "image_size": "1024x1024", "model": MODEL}


def building_args(subject: str) -> dict:
	return {"subject": subject, "style": WORLD_STYLE,
		"scene": BG + ", isolated structure only, no ground tile, no grass, no people",
		"composition": ISO, "aspect_ratio": "1:1", "image_size": "1024x1024", "model": MODEL}


def building_back_args(front_id: str, feature: str) -> dict:
	return {
		"subject": ("Create a genuine opposite-diagonal rear view of Image 1, the same building. "
			"Preserve building identity, complete silhouette, scale, placement, materials and painterly pixel-isometric style. "
			f"Hide the front entrance, door, signs and front-only details ({feature}); show plausible plain rear planes without a door or sign. "
			"This must be a true opposite-side view, not a mirrored front."),
		"style": WORLD_STYLE,
		"scene": BG + ", same building only, no ground, shadows, people or text",
		"composition": "same framing and scale as input, opposite diagonal isometric view, footprint diamond at bottom, whole subject centered",
		"aspect_ratio": "1:1", "image_size": "1024x1024", "model": MODEL,
		"input": [{"path": f"art_src/raw/{front_id}.webp"}],
	}


BUILDING_BACK_REFERENCES = {
	"b_hearth1_back": ("b_hearth1", "entrance and banner"),
	"b_hearth2_back": ("b_hearth2", "entrance and banner"),
	"b_hearth3_back": ("b_hearth3", "entrance and banner"),
	"b_house_back": ("b_house", "door, lantern and company banner"),
	"b_storehouse_back": ("b_storehouse", "double doors and loading sign"),
	"b_smelter_back": ("b_smelter", "entrance and furnace mouth"),
	"b_windmill_back": ("b_windmill", "door and company banner; do not include sails"),
	"b_workshop_back": ("b_workshop", "garage entrance and crane"),
	"b_sky_dock_back": ("b_sky_dock", "entrance and company banner"),
	"b_watchtower_back": ("b_watchtower", "door and company banner"),
	"b_outpost_back": ("b_outpost", "entrance and banner"),
	"b_bandit_tent_back": ("b_bandit_tent", "entrance flap and red pennant"),
	"b_bandit_hut_back": ("b_bandit_hut", "entrance and red sign"),
	"b_bandit_tower_back": ("b_bandit_tower", "entrance and red insignia"),
	"b_machine_spire_back": ("b_machine_spire", "entrance and front insignia"),
	"b_machine_block_back": ("b_machine_block", "front panel markings"),
	"b_machine_foundry_back": ("b_machine_foundry", "entrance and furnace port"),
	"b_trade_hall_back": ("b_trade_hall", "door and merchant banners"),
	"b_trade_stall_back": ("b_trade_stall", "display counter and wares"),
	"b_wanderer_tent_back": ("b_wanderer_tent", "entrance flap and lantern"),
	"b_ruin_vault_back": ("b_ruin_vault", "doorway and glowing front runes"),
}


FRONTIER = "frontier fantasy style: dark timber frames, cream plaster, deep-blue slate roofs, grey stone foundations, blue company banners with a white emblem, warm glowing windows"

BUILDINGS = {
	"b_hearth1": f"Town Hearth, a settlement's first meeting hall: a sturdy log-and-stone longhouse with a large stone fire pit glowing under an open front porch, crates and sacks of supplies, a notice board; {FRONTIER}",
	"b_hearth2": f"Village Hall: a larger two-storey hall with a stone ground floor and a small bell turret, a warm hearth glow at the open doors, supply crates; {FRONTIER}",
	"b_hearth3": f"Town Hall: a grand three-storey hall with a clock tower, many warm windows and wide stone steps; {FRONTIER}",
	"b_house": f"A single cozy two-storey cottage with a stone chimney, a flower box, a small wooden door with a lantern, a barrel and a few crates beside the door; {FRONTIER}",
	"b_house2": f"A single small one-storey cottage with a woodpile, a tiny vegetable patch, a stone chimney and a lantern by the door; {FRONTIER}",
	"b_storehouse": f"Storehouse: a long timber barn warehouse with big open double doors, stacks of crates, barrels, sacks and a hand cart outside; {FRONTIER}",
	"b_smelter": f"Smelter: a stone furnace workshop with a tall brick chimney, a glowing orange furnace mouth, an ore pile, an anvil and stacked metal ingots; {FRONTIER}",
	"b_windmill": f"Windmill tower WITHOUT sails: a round stone-and-timber windmill tower with a conical blue slate cap, only an empty round sail hub on its front face, a small door and flour sacks; {FRONTIER}",
	"b_workshop": f"Robot Workshop: a big steampunk timber-and-brick workshop with a large open garage door, brass gears, pipes and a small crane arm, a half-built brass robot on a work stand; {FRONTIER}",
	"b_sky_dock": f"Sky Dock: a tall wooden scaffold mooring tower with stairs and a landing platform on top, a docking mast with ropes and a lantern, a winch crane, NO airship; {FRONTIER}",
	"b_watchtower": f"Watchtower: a tall narrow wooden watchtower on a stone base with a lookout platform, a small blue roof, a torch; {FRONTIER}",
	"b_outpost": f"Outpost: a small fortified timber cabin with a short wooden palisade, a supply shed, a flag pole and a campfire; {FRONTIER}",
	"b_construction": "Construction site: a square wooden scaffolding frame with ladders, stacked logs and cut stone blocks, rope, a wheelbarrow and tools, the square base staked out with string",
	"b_bandit_tent": "Bandit tent: a patched red-and-brown canvas tent on a crude wooden frame, a red flag with a skull emblem, crates of stolen loot",
	"b_bandit_hut": "Bandit hut: a ramshackle hut of rough logs and planks with a patched roof, red banners with a skull emblem, a weapon rack and loot sacks",
	"b_bandit_tower": "Bandit lookout tower: a crude wooden tower of lashed logs with sharpened stakes, red banners and a burning torch",
	"b_campfire": "A small campfire: a ring of stones with burning logs, a cooking spit and glowing embers",
	"b_machine_spire": "Ancient machine spire: a tall dark iron and bronze obelisk with glowing orange runes, pipes and a red banner with a gear emblem",
	"b_machine_block": "Ancient machine bunker: a squat armoured dark iron block with a glowing orange vent, rivets and red banners with a gear emblem",
	"b_machine_foundry": "Ancient machine foundry: a large dark iron factory with two smokestacks, glowing orange furnace windows, pipes, gear emblems and red banners",
	"b_trade_hall": "Trade post hall: a busy merchant hall of timber with green-and-gold striped awnings, crates of goods, barrels, scales and lanterns",
	"b_trade_stall": "A small market stall with a green-and-gold striped awning and goods on the counter",
	"b_trade_mast": "An airship mooring mast: a tall timber mast with a small platform, rope ladders and a green-and-gold flag",
	"b_wanderer_tent": "A small weathered traveller's tent of beige canvas with a bedroll, a backpack and a cooking pot",
	"b_ruin_arch": "A crumbling ancient stone archway overgrown with ivy and moss",
	"b_ruin_pillar": "A single broken ancient stone pillar with ivy",
	"b_ruin_wall": "A crumbling section of ancient stone wall overgrown with ivy",
	"b_ruin_statue": "A weathered ancient stone statue of a robed figure on a pedestal, cracked and mossy",
	"b_ruin_vault": "A sunken ancient stone vault entrance with stairs leading down, carved glowing blue runes and ivy",
	"b_wreck_airship": "A crashed airship wreck: a torn deflated striped balloon draped over a broken wooden gondola hull half buried in the ground, scattered crates and a bent propeller",
}

# Painted inventory icons: item shapes (Icons.SHAPES) and resources. Order = reading order in the
# 4 x 3 grid; tools/art/process.py ICON_SHEETS maps cells back to ids.
ICON_SHEETS = {
	"icons_a": ["a steel sword", "a dagger", "a hand axe", "a spear", "a wooden longbow", "a crossbow", "a war hammer",
		"a spiked mace", "a wooden wizard staff", "a brass rifle", "a brass pistol", "a steel wrench"],
	"icons_b": ["a pickaxe", "a round wooden shield with a blue emblem", "a leather vest", "a long canvas coat",
		"a steel breastplate", "a steel helmet", "a pair of leather boots", "a pair of leather gloves",
		"a brass spyglass telescope", "a brass lantern with warm light", "a brass compass", "brass goggles"],
	"icons_c": ["a brass gear cog", "a brass servo motor", "a brass sensor eye lens", "a glowing blue power core",
		"a riveted steel armour plate", "a small brass propeller", "a folded striped airship balloon canvas",
		"a small brass steam engine", "a glowing crystal orb", "a small golden idol statuette",
		"an ancient stone relic tablet with glowing runes", "a pendant amulet with a red gem"],
	"icons_d": ["a gold ring with a blue gem", "a potion bottle of red tonic", "a wrapped travel ration of bread and cheese",
		"a leather repair kit with tools", "a glowing blue aether crystal shard", "a steel ingot", "a bundle of timber planks",
		"a folded fur pelt", "a leather-bound book", "a rolled parchment map", "a bundle of chopped logs", "a pile of cut grey stone blocks"],
	"icons_e": ["a chunk of iron ore with rusty veins", "a stack of three metal ingots", "a small pile of gold coins",
		"a loaf of bread with wheat ears", "a glowing blue energy battery with a lightning bolt", "a brown loot sack",
		"a small wooden treasure chest", "a rolled scroll with a red seal", "a brass bell", "a red heart crystal",
		"a golden star medal", "a crossed hammer and wrench"],
}


TEXTURES = {
	"t_grass": "lush green grass, fine grass blades, small clover, subtle lighter and darker patches",
	"t_meadow": "bright green meadow grass dotted with tiny yellow, white and purple wildflowers",
	"t_forest": "dark green forest floor of moss, fallen pine needles and tiny ferns with dark soil peeking through",
	"t_sand": "light river sand with small pebbles and gentle ripples",
	"t_dirt": "packed brown dirt ground with small pebbles, cracks and a few dry grass bits",
	"t_rock": "grey granite rock surface with cracks, small ledges, lichen and small moss patches",
	"t_farmland": "tilled dark brown soil in straight parallel furrows",
	"t_paved": "cobblestone pavement of rounded grey and tan stones with thin grass in the gaps",
}


def build() -> list:
	out = []
	for race, (male, female) in RACES.items():
		for look, outfit in LOOKS.items():
			left = f"{male}, {outfit}"
			right = f"{female}, {outfit}"
			cid = f"chip_{race}_{look}"
			out.append({"id": cid, "kind": "chip", "args": chip_args(left, right)})
			v2_male, v2_female = V2_APPEARANCE[race]
			v2_outfit = V2_LOOKS[look]
			v2_left = f"{v2_male}, {v2_outfit}"
			v2_right = f"{v2_female}, {v2_outfit}"
			out.append({"id": f"{cid}_v2", "kind": "chip",
				"args": chip_args(v2_left, v2_right, reference=cid)})
			v3_male, v3_female = V3_APPEARANCE[race][list(LOOKS).index(look)]
			v3_outfit = V3_LOOKS[look]
			v3_left = f"{v3_male}, {v3_outfit}"
			v3_right = f"{v3_female}, {v3_outfit}"
			out.append({"id": f"{cid}_v3", "kind": "chip",
				"args": chip_args(v3_left, v3_right, reference=cid)})
			if look == "worker":
				for version, appearances, worker_outfit in additional_worker_variants(race):
					v_left = f"{appearances[0]}, {worker_outfit}"
					v_right = f"{appearances[1]}, {worker_outfit}"
					out.append({"id": f"{cid}_v{version}", "kind": "chip",
						"args": chip_args(v_left, v_right, reference=cid)})
	bandit_a = ("a human man bandit in a patched brown leather coat, a red bandana and a red scarf over the mouth, holding a rusty hand axe",
		"a human woman bandit in a red hood and patched brown leather, holding a rusty hand axe")
	bandit_b = ("a bandit crossbowman: a human man in a red hood and patched leather armour, holding a crossbow",
		"a bandit captain: a big burly human man in a long red coat with a fur collar, a black tricorn hat and an eye patch, holding a heavy steel sword")
	out.append({"id": "chip_bandit_a", "kind": "chip", "args": chip_args(*bandit_a)})
	out.append({"id": "chip_bandit_b", "kind": "chip", "args": chip_args(*bandit_b)})
	hover = "hovering animation frames with rotor motion"
	machines = {
		"chip_mach_a": ("a work bot: a chibi brass steampunk worker robot with a round glass dome head with one glowing blue eye, stubby legs, a riveted barrel body, a small claw arm and a drill arm",
			"a walker: a bipedal brass and steel steampunk war mech with a round armoured body, a glowing blue eye slit, a cannon on its right shoulder and two sturdy bird-like legs", None),
		"chip_mach_b": ("a scout drone: a small hovering brass drone with one big glowing blue lens and four small rotors, no legs",
			"a repair drone: a small hovering white-and-brass drone with a green cross emblem, two little mechanical arms and four small rotors", hover),
		"chip_mach_c": ("a sentry: an ancient hostile guard robot of dark rusty iron and bronze with a glowing orange eye and a spear arm",
			"a war drone: a hostile hovering machine of dark iron with a glowing red-orange eye, a small cannon underneath and four rotors", None),
		"chip_mach_d": ("a turret: a stationary ancient gun turret of dark iron on a round stone base with a glowing orange lens, its barrel pointing in the facing direction; its 3 frames are idle, charging glow and firing flash",
			"a machine warden: a huge hunched ancient boss robot of dark iron and bronze with a glowing orange core in its chest and heavy fists", None),
	}
	for mid, (left, right, frames) in machines.items():
		out.append({"id": mid, "kind": "chip", "args": chip_args(left, right, frames or "walking frames: left foot forward, standing, right foot forward")})
	airship = ("Four views of the same steampunk airship for a cozy isometric fantasy RTS in a 2x2 grid: top-left facing left "
		"(side view), top-right facing right (side view), bottom-left flying toward the viewer (front three-quarter view), "
		"bottom-right flying away (rear three-quarter view). ")
	out.append({"id": "air_cargo", "kind": "sheet", "args": sheet_args(airship + "The airship has a large cream-and-blue striped gas balloon with brass ribs and a blue company emblem, a wooden ship-like gondola hanging below with round windows, a brass propeller at the back and small side fins.", 2, 2)})
	out.append({"id": "air_trader", "kind": "sheet", "args": sheet_args(airship + "The airship has a large green-and-gold striped gas balloon with a golden coin emblem, a polished wooden merchant gondola with lanterns and cargo nets below, a brass propeller at the back.", 2, 2)})
	out.append({"id": "props_trees_a", "kind": "sheet", "args": sheet_args("Sprite sheet of 8 separate tree game assets: 4 tall dark green pine / fir trees of different heights and shapes, 2 round leafy oak trees, 1 slender white birch tree with yellow-green leaves, 1 dead leafless grey tree. Each tree complete from trunk base to top, upright, rich layered foliage, bright highlights on the upper left and deep shadowed needles.", 2, 4)})
	out.append({"id": "props_trees_b", "kind": "sheet", "args": sheet_args("Sprite sheet of 8 separate conifer tree game assets: dark green pines and firs of varied heights and shapes (2 tall, 3 medium, 3 small young firs), each complete from trunk base to top, upright, layered needles with bright highlights on the upper left.", 2, 4)})
	out.append({"id": "props_rocks", "kind": "sheet", "args": sheet_args("Sprite sheet of 8 separate rock game assets: 2 large grey boulders with moss patches, 2 small grey rocks, 2 iron ore rocks (dark grey rock with rusty orange-brown ore veins and metallic glints), 2 glowing cyan-blue aether crystal clusters growing out of rock.", 2, 4)})
	out.append({"id": "props_plants", "kind": "sheet", "args": sheet_args("Sprite sheet of 8 separate plant game assets: 2 round berry bushes with red berries, 2 leafy green bushes, 1 cut tree stump, 1 clump of cattail reeds, 1 clump of tall grass with small wildflowers, 1 small patch of colourful wildflowers.", 2, 4)})
	out.append({"id": "props_sails", "kind": "sheet", "args": {
		"subject": "Only the rotor of a windmill as a separate game sprite: four long wooden sail arms with cream canvas panels arranged in a perfect X around a small round wooden hub. No tower, no building, no cap, no roof, no ground, nothing else.",
		"style": WORLD_STYLE, "scene": "flat solid pure magenta #FF00FF background filling the whole image, no shadows, no text",
		"composition": "seen straight from the front, perfectly centred on the hub, all four sail tips fully visible with empty space around them",
		"aspect_ratio": "1:1", "image_size": "1024x1024", "model": MODEL}})
	out.append({"id": "walls", "kind": "building", "args": {
		"subject": "Sprite sheet of 2 separate wall segment game assets side by side: LEFT a short section of a bandit palisade made of four sharpened vertical logs lashed together with rope, RIGHT a short square block of grey stone castle wall with crenellations on top and a little moss. Each segment is a compact square block about as wide as it is tall, so many of them can be placed in a row.",
		"style": WORLD_STYLE, "scene": "flat solid pure magenta #FF00FF background filling the whole image, no ground, no shadows, no text",
		"composition": "classic isometric view: camera looking down about 35 degrees from the south-east, each segment's square footprint forms a small diamond at its bottom, the two segments separated by wide empty space, nothing touching the edges",
		"aspect_ratio": "3:2", "image_size": "1536x1024", "model": MODEL}})
	out.append({"id": "keyart_title", "kind": "keyart", "args": {
		"subject": "Wide key art for the title screen of a cozy frontier fantasy strategy game: a young timber-and-stone frontier settlement with deep-blue slate roofs and blue banners in a lush green valley, a cream-and-blue striped steampunk airship docked at a tall wooden mooring tower, a windmill, small settlers and a brass walker robot on a dirt road, dense dark pine forests, misty mountains and waterfalls in the distance, a bandit camp with red banners far away on a ridge",
		"style": "detailed painterly pixel art like a modern high-resolution isometric strategy game, warm golden-hour light, saturated colours, atmospheric haze",
		"scene": "late afternoon, soft clouds, sun low on the right",
		"composition": "wide panoramic high three-quarter view, the settlement in the right half, calm open sky and forest in the left third for menu text, no text, no logo, no UI",
		"aspect_ratio": "3:2", "image_size": "1536x1024", "model": MODEL}})
	for sid, names in ICON_SHEETS.items():
		listing = ", ".join(f"{i + 1} {n}" for i, n in enumerate(names))
		out.append({"id": sid, "kind": "icons", "args": {
			"subject": f"Sprite sheet of {len(names)} separate painted fantasy RPG inventory icons in a 4 x 3 grid, in reading order: {listing}. Each icon shows exactly one object, large and centred in its own cell, slightly tilted three-quarter view, rich detail with bright highlights.",
			"style": WORLD_STYLE, "scene": BG,
			"composition": "4 columns x 3 rows evenly spaced grid, every icon isolated in its own cell with empty space around it, nothing touching the edges, no frames, no text",
			"aspect_ratio": "3:2", "image_size": "1536x1024", "model": MODEL}})
	for tid, text in TEXTURES.items():
		out.append({"id": tid, "kind": "texture", "args": texture_args(text)})
	for bid, text in BUILDINGS.items():
		out.append({"id": bid, "kind": "building", "args": building_args(text)})
	for back_id, (front_id, feature) in BUILDING_BACK_REFERENCES.items():
		out.append({"id": back_id, "kind": "building_back", "args": building_back_args(front_id, feature)})
	for race, (male, female) in RACES.items():
		for look, outfit in LOOKS.items():
			cid = f"chip_{race}_{look}"
			out.append({"id": f"portrait_{race}_{look}", "kind": "portrait",
				"args": portrait_args(cid, f"{male}, {outfit}", f"{female}, {outfit}")})
			v2_male, v2_female = V2_APPEARANCE[race]
			v2_outfit = V2_LOOKS[look]
			out.append({"id": f"portrait_{race}_{look}_v2", "kind": "portrait",
				"args": portrait_args(f"{cid}_v2", f"{v2_male}, {v2_outfit}", f"{v2_female}, {v2_outfit}")})
			v3_male, v3_female = V3_APPEARANCE[race][list(LOOKS).index(look)]
			v3_outfit = V3_LOOKS[look]
			out.append({"id": f"portrait_{race}_{look}_v3", "kind": "portrait",
				"args": portrait_args(f"{cid}_v3", f"{v3_male}, {v3_outfit}", f"{v3_female}, {v3_outfit}")})
			if look == "worker":
				for version, appearances, worker_outfit in additional_worker_variants(race):
					v_left = f"{appearances[0]}, {worker_outfit}"
					v_right = f"{appearances[1]}, {worker_outfit}"
					out.append({"id": f"portrait_{race}_{look}_v{version}", "kind": "portrait",
						"args": portrait_args(f"{cid}_v{version}", v_left, v_right)})
	out.append({"id": "portrait_bandit_a", "kind": "portrait", "args": portrait_args("chip_bandit_a", *bandit_a)})
	out.append({"id": "portrait_bandit_b", "kind": "portrait", "args": portrait_args("chip_bandit_b", *bandit_b)})
	return sorted(out, key=_priority)


SITE_BUILDINGS = ("b_bandit", "b_campfire", "b_machine", "b_trade", "b_wanderer", "b_ruin", "b_wreck")


def _priority(entry: dict) -> int:
	"""Generation order: what the player sees first, and chips before the portraits that use them."""
	i = entry["id"]
	if i.startswith("chip_") and not i.startswith("chip_mach"):
		return 0
	if i.startswith("props_"):
		return 1
	if i.startswith("t_"):
		return 2
	if i.startswith("b_") and not i.startswith(SITE_BUILDINGS):
		return 3
	if i.startswith("chip_mach") or i.startswith("air_"):
		return 4
	if i.startswith("portrait_"):
		return 5
	return 6


if __name__ == "__main__":
	entries = build()
	path = ROOT / "art_src" / "prompts.json"
	path.parent.mkdir(parents=True, exist_ok=True)
	path.write_text(json.dumps(entries, indent=1, ensure_ascii=False) + "\n")
	print(f"{len(entries)} prompts -> {path}")
