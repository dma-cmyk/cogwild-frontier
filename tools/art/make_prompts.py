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

# Android-specific clothing keeps the porcelain shell, dark joints and head silhouette visible.
ANDROID_LOOKS = {
	"worker": "wearing a narrow leather tool belt, a short royal-blue sash at one hip and a small brass hand tool; no hat, no full shirt, no full trousers",
	"fighter": "wearing articulated ivory armour plates over dark joints with a small royal-blue shoulder sash, carrying a short sword and compact shield; head shell fully visible",
	"ranger": "wearing articulated ivory armour with a light charcoal half-cloak and short royal-blue scarf, carrying a compact bow and quiver; head shell and hip plates visible",
	"engineer": "wearing articulated ivory armour with a short dark apron panel, brass goggles mounted above the faceplate and a royal-blue waist sash, carrying a brass wrench",
	"scholar": "wearing articulated ivory armour with a short plum mantle and royal-blue trim, carrying a slim book and brass-tipped staff; smooth faceplate unobscured",
}
ANDROID_LOOKS_V2 = {
	"worker": "wearing a narrow dark tool belt, a short royal-blue sash and brass calipers; no hat, no full shirt, no full trousers",
	"fighter": "wearing layered ivory shell armour over dark joints with restrained brass edges and a short royal-blue half-cape, carrying a sword and shield; distinctive faceted head shell visible",
	"ranger": "wearing ivory shell armour with a light charcoal shoulder cape and royal-blue neck ribbon, carrying a bow and quiver; distinctive head and hip shell silhouette visible",
	"engineer": "wearing ivory shell armour with a short charcoal work apron, brass goggles above the faceplate and royal-blue belt sash, carrying a large wrench",
	"scholar": "wearing ivory shell armour with a short plum mantle and muted-gold clasp, royal-blue trim, book and brass staff; distinctive teardrop head shell unobscured",
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

# --- mythic races (round 5): Greek and Japanese folklore peoples, playable and village folk ---------
# v1 uses LOOKS, v2 uses V2_LOOKS. Avoid blue/teal/cyan on bodies: only the company cloth is blue.
NEW_RACES = {
	"minotaur": ("a Minotaur man (towering bull-headed folk: a brown bull head with long curved ivory horns, a brass nose ring, a shaggy dark mane, broad furry shoulders, a tufted bull tail and cloven hooves)",
		"a Minotaur woman (bull folk with short curved ivory horns, floppy cow ears, a tufted cow tail, dark brown wavy hair, a strong build and cloven hooves)"),
	"centaur": ("a Centaur man (human upper body joined at the waist to the full body of a chestnut horse with four legs and a dark tail) with a short black beard and long dark hair",
		"a Centaur woman (human upper body joined at the waist to the full body of a dappled grey horse with four legs and a pale tail) with long ash-blond hair in a braid"),
	"harpy": ("a Harpy man (bird folk: large tawny-brown feathered wings instead of arms with small clawed hands at the wrist joints, scaly yellow bird legs with talons) with short dark-brown feather hair",
		"a Harpy woman (bird folk: large pale-gold feathered wings instead of arms with small clawed hands at the wrist joints, scaly yellow bird legs with talons) with long white-and-amber feathery hair"),
	"lamia": ("a Lamia man (serpent folk: human upper body and a long thick emerald-green snake tail instead of legs, green scales on the cheeks and forearms, slit golden eyes) with black hair tied back",
		"a Lamia woman (serpent folk: human upper body and a long thick crimson snake tail with gold bands instead of legs, scales on the cheeks, slit golden eyes) with long black hair"),
	"oni": ("an Oni man (Japanese ogre folk: crimson-red skin, two short ivory horns on the forehead, small tusks, wild black hair and a big muscular build)",
		"an Oni woman (Japanese ogre folk: coral-red skin, a single ivory horn on the forehead, small fangs, long black hair in a high ponytail and an athletic build)"),
	"tengu": ("a Tengu man (Japanese crow folk: a glossy black crow head with a strong yellow beak, black feathered wings folded on the back, clawed hands and bird feet, a small black tokin cap)",
		"a Tengu woman (Japanese crow folk: a human face with a small red mask marking, long black hair with crow feathers, black feathered wings folded on the back and bird-clawed feet)"),
}
NEW_RACES_V2 = {
	"minotaur": ("a Minotaur man (bull-headed folk: a black bull head with long sweeping horns, a silver nose ring, a scarred snout, black fur, a tufted tail and cloven hooves)",
		"a Minotaur woman (bull folk with curved dark horns, cow ears, a tufted tail, cream-white hair in a thick braid, freckles and cloven hooves)"),
	"centaur": ("a Centaur man (human upper body joined at the waist to the body of a black horse with white socks) with a shaved head and a braided brown beard",
		"a Centaur woman (human upper body joined at the waist to the body of a palomino horse with a cream tail) with short auburn curls and freckles"),
	"harpy": ("a Harpy man (bird folk: ash-brown and white hawk-patterned wings instead of arms with small clawed hands at the wrist joints, talons) with short speckled feather hair",
		"a Harpy woman (bird folk: crimson and gold parrot-like wings instead of arms with small clawed hands at the wrist joints, talons) with long red feather hair"),
	"lamia": ("a Lamia man (serpent folk: human upper body and a long sand-gold snake tail with brown diamond markings instead of legs, a hooded cobra frill, slit amber eyes) with a shaved head",
		"a Lamia woman (serpent folk: human upper body and a long emerald-and-cream snake tail instead of legs, slit golden eyes) with long black hair and gold ornaments"),
	"oni": ("an Oni man (Japanese ogre folk: ochre-yellow skin, one thick horn, tusks and a wild white mane)",
		"an Oni woman (Japanese ogre folk: rosy-pink skin, two small curved horns, fangs and short black bob hair)"),
	"tengu": ("a Tengu man (Japanese mountain goblin folk: a human face with a long red nose, white shaggy hair and beard, large black-feathered wings on the back)",
		"a Tengu woman (Japanese crow folk: a black crow head with a sharp beak and a feathered crest, glossy black wings on the back, bird feet)"),
}
NEW_RACE_BODY = {
	"minotaur": "Hats and helmets have holes for the horns; hooves instead of shoes.",
	"centaur": "Adapt every outfit to the centaur body: clothing only on the human upper body, the four horse legs bare with hooves, a small royal-blue saddle blanket on the horse back.",
	"harpy": "Adapt every outfit to the harpy body: no sleeves, the feathered wings grow from the shoulders, bare scaly bird legs with talons, no shoes.",
	"lamia": "Adapt every outfit to the serpent body: clothing only on the human upper body, no trousers or shoes, the long bare snake tail coils slightly behind.",
	"oni": "Hats and helmets leave room for the horns.",
	"tengu": "The black wings stay folded on the back over the outfit; bird-clawed feet instead of shoes.",
}
NEW_RACE_FRAMES = {
	"centaur": "trotting frames: front legs stepping forward, standing, hind legs stepping forward",
	"lamia": "slithering frames: tail curving left, tail straight, tail curving right",
}
NEW_RACE_REFERENCE = ("Use Image 1 only as style, pixel density, chibi proportion and sprite-sheet layout reference; draw the "
	"new characters described here, a different race. Keep only the royal-blue company cloth accent blue for shader hue "
	"rotation; avoid other blue, teal or cyan areas.")

# --- classic roguelike races (round 6): playable, village folk and town residents ------------------
# Added to the NEW_RACES tables so they share the chip/portrait prompts (v1 references the human chip,
# v2 the race's own v1). Avoid blue/teal/cyan on bodies: only the company cloth is blue.
CLASSIC_RACES = {
	"goblin": ("a Goblin man (small wiry goblin folk: bright green skin, very large pointed ears sticking out sideways, a long crooked nose, yellow eyes and a sharp toothy grin) with a messy black topknot",
		"a Goblin woman (small wiry goblin folk: olive-green skin, very large pointed ears with brass rings, yellow eyes and a cheeky toothy grin) with orange hair in two short tails"),
	"orc": ("an Orc man (big muscular orc folk: grey-green skin, two lower tusks jutting from the jaw, a heavy brow and small dark eyes) with a black mohawk and a braided goatee",
		"an Orc woman (tall strong orc folk: sage-green skin, small lower tusks, a heavy jaw and red war-paint stripes on the cheeks) with long black hair in thick braids"),
	"kobold": ("a Kobold man (small reptilian kobold folk: rust-red scales, a short dragon-like snout, two small curved horns, yellow slit eyes, clawed hands and feet and a long scaly tail)",
		"a Kobold woman (small reptilian kobold folk: ochre-orange scales with a cream belly, a short snout, small backswept horns, amber eyes, a long scaly tail and a bead necklace)"),
	"lizardfolk": ("a Lizardfolk man (tall reptilian lizard folk: a lizard head with a long snout, green scales, a spiny crest along the head, yellow eyes, clawed hands and feet and a long thick tail)",
		"a Lizardfolk woman (tall reptilian lizard folk: a lizard head, olive-and-ochre banded scales, a small red head frill, amber eyes, clawed feet and a long tail)"),
	"gnome": ("a Gnome man (tiny gnome folk: a big round red nose, a long white beard, rosy cheeks and a tall pointed red hat)",
		"a Gnome woman (tiny gnome folk: a button nose, rosy cheeks, long honey-blond braids and a tall pointed green hat)"),
	"halfling": ("a Halfling man (small halfling folk: a round friendly face, curly chestnut hair, slightly pointed ears and big bare hairy feet)",
		"a Halfling woman (small halfling folk: round rosy cheeks, curly golden hair with a small flower, slightly pointed ears and big bare hairy feet)"),
}
CLASSIC_RACES_V2 = {
	"goblin": ("a Goblin man (small goblin folk: moss-green skin, huge droopy pointed ears, a warty nose and a missing tooth) with a bald head and a notched ear",
		"a Goblin woman (small goblin folk: pale lime-green skin, huge pointed ears, freckles and sharp little fangs) with a spiky white bob"),
	"orc": ("an Orc man (big orc folk: dark olive-brown skin, large lower tusks with a brass ring, a broken nose and scars) with a shaved head and a grey topknot",
		"an Orc woman (strong orc folk: ash-grey-green skin, lower tusks and a gold nose ring) with one shaved side and a long red ponytail"),
	"kobold": ("a Kobold man (small reptilian kobold folk: charcoal-grey scales with rust spots, a blunt snout, short stubby horns, a torn ear frill and a long tail)",
		"a Kobold woman (small reptilian kobold folk: pale sand-yellow scales, a slender snout, small horns with copper rings and a long striped tail)"),
	"lizardfolk": ("a Lizardfolk man (tall reptilian lizard folk: a crocodile-like head, dark brown-green scales, bony ridges and a long heavy tail)",
		"a Lizardfolk woman (tall reptilian lizard folk: a slender lizard head, emerald-green scales with gold speckles, a feathered crest and a long tail)"),
	"gnome": ("a Gnome man (tiny gnome folk: a big round nose, bushy brown eyebrows, a forked grey beard, round spectacles and a tall pointed ochre hat)",
		"a Gnome woman (tiny gnome folk: a pointed nose, freckles, short pink curls and a tall pointed purple hat)"),
	"halfling": ("a Halfling man (small halfling folk: curly sandy hair, long sideburns, a round belly, slightly pointed ears and big bare hairy feet)",
		"a Halfling woman (small halfling folk: dark curly hair in a bun, freckles, slightly pointed ears and big bare hairy feet)"),
}
CLASSIC_RACE_BODY = {
	"goblin": "Goblins are small and wiry with a big head: outfits look patched and slightly too big, and the large ears stick out sideways past hats and helmets.",
	"orc": "Orcs are broad and heavily muscled: every outfit fits a big frame, helmets leave the tusks visible.",
	"kobold": "Adapt every outfit to the kobold body: the scaly tail comes out behind, clawed bare feet instead of shoes, hats and helmets sit between the small horns.",
	"lizardfolk": "Adapt every outfit to the lizard body: the long scaly tail comes out behind, clawed bare feet instead of shoes, helmets fit the long lizard head.",
	"gnome": "Gnomes keep the tall pointed hat instead of any cap (the fighter wears a steel helmet with a tall pointed top); boots with curled toes.",
	"halfling": "Halflings never wear shoes: big bare hairy feet in every outfit.",
}
NEW_RACES.update(CLASSIC_RACES)
NEW_RACES_V2.update(CLASSIC_RACES_V2)
NEW_RACE_BODY.update(CLASSIC_RACE_BODY)

# Androids are self-aware mechanical citizens, not drones: porcelain/ivory armour over
# slender dark articulated joints, amber eyes and restrained brass details. v2 changes
# the head and shell silhouette, not merely the palette.
ANDROID_RACES = {
	"android": ("an Android man, an elegant self-aware mechanical citizen with a smooth nonhuman ivory porcelain faceplate, small luminous amber-gold eyes, a narrow visor shell, slender dark articulated neck and joints, restrained brass collar details and sturdy plated limbs",
		"an Android woman, an elegant self-aware mechanical citizen with a smooth nonhuman ivory porcelain faceplate, small luminous amber-gold eyes, a graceful swept shell silhouette, slender dark articulated neck and joints, restrained brass collar details and sturdy plated limbs"),
}
ANDROID_RACES_V2 = {
	"android": ("an Android man, a self-aware mechanical citizen with a faceted ivory porcelain mask, paired amber-gold luminous eye slits, a broad hexagonal head shell, dark articulated joints, brass hinge accents and layered armour plates",
		"an Android woman, a self-aware mechanical citizen with a smooth ivory porcelain mask, tiny amber-gold luminous eyes, a tall elegant teardrop head shell, dark articulated joints, brass hinge accents and layered armour plates"),
}
ANDROID_BODY = {
	"android": "Androids remain visibly armoured through every profession: add only small sashes, belts, capes or half-skirts over the ivory shell; never depict flesh, exposed human faces or ordinary cloth bodies. Use normal bipedal walking frames and about 1.6m visual height.",
}
NEW_RACES.update(ANDROID_RACES)
NEW_RACES_V2.update(ANDROID_RACES_V2)
NEW_RACE_BODY.update(ANDROID_BODY)

# Fourth look for the non-worker outfits of the original races (the worker look already has v4/v5).

NONWORKER_V4_APPEARANCE = {
	"human": {
		"fighter": ("a broad human man with a shaved head, a thick black beard and a scarred eyebrow", "a tall human woman with a long black ponytail and a determined look"),
		"ranger": ("a lean human man with shoulder-length sandy hair and stubble", "a human woman with short copper curls and freckles"),
		"engineer": ("a stocky older human man with grey mutton-chop sideburns", "a young human woman with a dark bob and soot on her cheek"),
		"scholar": ("a thin elderly human man with a long white beard and spectacles", "a middle-aged human woman with grey-streaked brown hair in a bun"),
	},
	"sylvan": {
		"fighter": ("a Sylvan man with long pointed ears and a long black braid", "a Sylvan woman with long pointed ears and short silver hair"),
		"ranger": ("a Sylvan man with long pointed ears and auburn hair with leaf ornaments", "a Sylvan woman with long pointed ears and golden hair in a side braid"),
		"engineer": ("a Sylvan man with long pointed ears, cropped dark-green hair and a brass monocle", "a Sylvan woman with long pointed ears and pink hair in twin buns"),
		"scholar": ("an old Sylvan man with long pointed ears, a long silver beard and a circlet", "a Sylvan woman with long pointed ears, very long white hair and a circlet"),
	},
	"stoutkin": {
		"fighter": ("a stocky Stoutkin man with a forked black beard and a mohawk", "a sturdy Stoutkin woman with fiery orange hair in a thick braid and a scar"),
		"ranger": ("a stocky Stoutkin man with a brown beard tied with leather cords", "a sturdy Stoutkin woman with ash-blond braids and freckles"),
		"engineer": ("a stocky Stoutkin man with a soot-grey beard and welding marks", "a sturdy Stoutkin woman with short black hair and a brass ear cuff"),
		"scholar": ("an old stocky Stoutkin man with a long white beard tucked into his belt", "an old sturdy Stoutkin woman with silver hair in a crown braid and spectacles"),
	},
	"vulpin": {
		"fighter": ("a Vulpin man with tall fox ears, a russet tail with white tip and a black topknot", "a Vulpin woman with fox ears, a russet tail with white tip and a short silver bob"),
		"ranger": ("a Vulpin man with fox ears, a russet tail with cream tip and messy cream hair", "a Vulpin woman with fox ears, a russet tail with cream tip and a long dark braid"),
		"engineer": ("a Vulpin man with fox ears, a russet tail with cream tip and spiky dark-red hair", "a Vulpin woman with fox ears, a russet tail with cream tip and orange pigtails"),
		"scholar": ("an old Vulpin man with fox ears, a greying tail and a long wispy beard", "a Vulpin woman with fox ears, a russet tail and long black hair with a jade hairpin"),
	},
}
V4_LOOKS = {
	"fighter": "wearing a royal-blue company surcoat over a dark leather brigandine and a steel open-faced helm, holding a short sword and a kite shield with a cream emblem",
	"ranger": "wearing a forest-green leather jerkin, a brown hooded half-cape and a royal-blue company arm band, carrying a short bow and a quiver",
	"engineer": "wearing a rust-orange work apron over a cream shirt with rolled sleeves, a royal-blue company neck scarf and brass goggles on the forehead, carrying a steel wrench",
	"scholar": "wearing a dark-green long coat with brass buttons, a royal-blue company stole and a leather satchel, holding a wooden staff with a small hanging lantern",
}

# Race villages: one dwelling (3x3 footprint) and one central hall (5x5) per race. Village colours
# avoid blue so they never read as the player's company.
VILLAGE_BUILDINGS = {
	"human": ("a rustic farmhouse cottage of an independent human hamlet: whitewashed walls, a thick straw thatch roof, a small vegetable garden, a hay cart, red and ochre cloth",
		"an independent human village longhouse meeting hall: a long timber hall with a thatched roof, carved gable ends, a bell post and a small well in front, red and ochre banners"),
	"sylvan": ("a Sylvan treehouse dwelling: a small round wooden cottage built around the trunk of a great living tree, a curved leaf-shingle roof, glowing moss lanterns, a rope ladder, green-and-silver pennants",
		"a Sylvan moot hall: an elegant hall woven from living trees and arched branches, leaf canopies, carved wooden pillars, glowing green lanterns, green-and-silver banners"),
	"stoutkin": ("a Stoutkin hill house: a squat stone house half dug into a grassy mound, a round heavy door with brass fittings, a stone chimney and copper pipes",
		"a Stoutkin forge hall: a massive carved stone hall with a great arched doorway, brass gears, a glowing forge chimney, copper-and-brick banners"),
	"vulpin": ("a Vulpin cottage: a cozy wooden cottage with a curved orange-tiled roof, paper lanterns, a round window and wind chimes",
		"a Vulpin market hall: a lively wooden pavilion with sweeping orange-tiled roofs, hanging paper lanterns, stacked trade goods, orange-and-cream banners"),
	"minotaur": ("a Minotaur stone house: a heavy dry-stone house with a flat slab roof, a bull skull over the doorway, crimson and bronze cloth",
		"a Minotaur labyrinth hall: a massive ancient Greek style stone hall with thick columns, a maze pattern carved on the walls, a great bronze bull statue by the entrance, crimson banners"),
	"centaur": ("a Centaur hide tent: a large round tent of stretched hides on long poles, painted horse motifs, a hitching post and a bow rack, green-and-ochre streamers",
		"a Centaur council lodge: a very large ring of hide tents around a tall carved wooden totem pole with horse heads, a fire pit, green-and-ochre banners"),
	"harpy": ("a Harpy nest hut: a giant woven twig-and-feather nest hut perched on a rocky outcrop, a round entrance, hanging shiny trinkets, gold-and-brown feathers",
		"a Harpy roost tower: a tall rocky spire topped by a huge woven nest, wooden perches, hanging charms and gold streamers"),
	"lamia": ("a Lamia reed pavilion: a round stone-based pavilion with a reed roof beside a small pool, carved serpent pillars, emerald-and-gold cloth",
		"a Lamia serpent temple: a white marble temple with coiled serpent statues, a small reflecting pool, emerald-and-gold banners and incense smoke"),
	"oni": ("an Oni mountain lodge: a rough timber house with a heavy thatched roof, a shimenawa rope with paper streamers over the door, a huge iron club leaning by the door, red-and-black cloth",
		"an Oni war hall: a large Japanese timber hall with a curved dark tile roof, a big red gate in front, stone lanterns, a glowing forge, red-and-black banners"),
	"tengu": ("a Tengu mountain hermitage: a small Japanese wooden shrine hut on stilts with a steep cedar-bark roof, paper charms, a stone lantern, black-and-red streamers",
		"a Tengu pagoda: a tall narrow three-tier Japanese pagoda on a rocky base with red railings, black-feather ornaments, wind chimes, black-and-red banners"),
	"goblin": ("a Goblin scrap shanty: a crooked little hut patched together from salvaged planks, rusty tin sheets and old barrels, a lopsided chimney, bottle charms, green-and-ochre rags",
		"a Goblin junk hall: a big ramshackle hall on short stilts built from wrecked cart wheels, rusty metal sheets and planks, a crooked lookout tower, a giant cooking pot, green-and-ochre rag banners"),
	"orc": ("an Orc hide longhouse: a long low hut of stretched hides over bent timber ribs, tusks and horns over the door, a war shield on the wall, red-and-black painted cloth",
		"an Orc war lodge: a big timber-and-hide great hall behind a short palisade of sharpened logs, huge tusk arches over the entrance, a war drum, red-and-black banners"),
	"kobold": ("a Kobold burrow mound: a low earth-and-stone mound with a small round tunnel entrance braced by timber, hanging lanterns, a short mine-cart rail, glowing crystals, rust-and-yellow cloth",
		"a Kobold mine hall: a large rocky mound hall with a timber-braced tunnel gate, a small dragon statue, mine carts full of ore, glowing amber crystals, rust-and-yellow banners"),
	"lizardfolk": ("a Lizardfolk stilt hut: a round reed-and-mud hut on wooden stilts over a small marsh pool, a woven reed roof, bone charms, a dugout canoe",
		"a Lizardfolk swamp temple: a large stepped mud-brick and reed temple on stilts over marsh water, carved crocodile skulls, totems, green-and-ochre banners"),
	"gnome": ("a Gnome mushroom house: a giant red-capped mushroom with white spots made into a cozy home, a round wooden door, tiny windows, brass pipes and a little gear weathervane",
		"a Gnome tinkerers' hall: a cluster of giant red and ochre mushrooms joined into a workshop hall with brass gears, clockwork, a copper chimney, a small telescope on top, red-and-cream pennants"),
	"halfling": ("a Halfling hill burrow: a round green door set into a small grassy hill with round windows, a flower garden, a little picket fence and a chimney poking out of the grass",
		"a Halfling feast hall: a large grassy hill home with several round doors and windows, a big round green main door, an apple tree, a festive awning over long food tables, yellow-and-green bunting"),
	"android": ("an original android Precision Workshop dwelling: elegant compact porcelain-and-ivory masonry, charcoal roof plates, dark structural seams, restrained brass ribs and trim, small amber glowing windows, a brass tool crane and subtle gear vents; 3 x 3 tile footprint, no blue, no people, no text",
		"an original android Concordance Hall: dignified large ivory porcelain-and-stone civic hall, charcoal shell-like roof, dark structural seams, restrained brass columns and circular motifs, many warm amber glowing windows, central oculus and workshop chimneys; 5 x 5 tile footprint, no blue, no people, no text"),
}


# The mixed-race trade town (round 6): service buildings around a plaza. Footprint in tiles.
TOWN_BUILDINGS = {
	"guild_hall": (5, "an adventurers' guild hall of a busy frontier trade town: a large two-storey timber-and-stone hall with a wide front porch, a big notice board covered with paper notices beside the door, a crossed-swords emblem over the entrance, flags of many different peoples in red, green, gold and purple, warm lit windows"),
	"tavern": (4, "a lively frontier town tavern: a two-storey half-timbered building with a hanging sign shaped like a foaming mug, barrels stacked by the door, an outdoor table with benches, lanterns and a smoking chimney"),
	"general_store": (4, "a frontier town general store: a timber shop with a wide striped red-and-cream front awning, crates, sacks, barrels, rope and tools displayed outside, a hanging sign shaped like a sack"),
	"smithy": (4, "a frontier town blacksmith: a stone-and-timber forge with a glowing open hearth under a lean-to roof, an anvil, racks of swords, axes and shields outside, a water trough and a tall smoking stone chimney"),
	"inn": (4, "a cozy frontier town inn: a three-storey timber inn with small balconies, flower boxes, a hanging sign shaped like a crescent moon over a bed, a small stable at the side and warm lit windows"),
	"fountain": (3, "a town plaza fountain: a round carved stone fountain basin with a statue of a traveller holding up a lantern in the middle, water spouting into the basin, a ring of paving stones around it"),
}
TOWN_BACK_FEATURES = {
	"guild_hall": "porch entrance, notice board and emblem",
	"tavern": "front door, mug sign and outdoor table",
	"general_store": "front awning, sign and displayed goods",
	"smithy": "open hearth, anvil and weapon racks",
	"inn": "front door, moon sign and balconies",
}


def town_building_args(key: str) -> dict:
	size, text = TOWN_BUILDINGS[key]
	return building_args(f"{text}; a building on a {size} x {size} tile square footprint, no letters or text on signs, no blue anywhere")


def new_race_chip(race: str, look: str, version: int) -> dict:
	male, female = (NEW_RACES if version == 1 else NEW_RACES_V2)[race]
	outfit = ((ANDROID_LOOKS if version == 1 else ANDROID_LOOKS_V2)[look] if race == "android"
		else (LOOKS if version == 1 else V2_LOOKS)[look])
	frames = NEW_RACE_FRAMES.get(race, "walking frames: left foot forward, standing, right foot forward")
	reference = f"chip_human_{look}" if version == 1 else f"chip_{race}_{look}"
	# Human worker references transfer hats and obscure the designed mechanical head shells.
	if race == "android" and look == "worker" and version == 1:
		reference = ""
	args = chip_args(f"{male}, {outfit}", f"{female}, {outfit}", frames, reference, NEW_RACE_REFERENCE)
	args["subject"] += " " + NEW_RACE_BODY[race]
	if race == "android":
		args["model"] = "openai-codex/gpt-image-2"
	return args


def new_race_portrait(race: str, look: str, version: int) -> dict:
	male, female = (NEW_RACES if version == 1 else NEW_RACES_V2)[race]
	outfit = ((ANDROID_LOOKS if version == 1 else ANDROID_LOOKS_V2)[look] if race == "android"
		else (LOOKS if version == 1 else V2_LOOKS)[look])
	cid = f"chip_{race}_{look}" + ("" if version == 1 else f"_v{version}")
	args = portrait_args(cid, f"{male}, {outfit}", f"{female}, {outfit}")
	if race == "android":
		args["model"] = "openai-codex/gpt-image-2"
	return args


def village_building_args(race: str, hall: bool) -> dict:
	home, hall_text = VILLAGE_BUILDINGS[race]
	size = ("a large central village hall filling a 5 x 5 tile square footprint" if hall
		else "a single small dwelling on a 3 x 3 tile square footprint")
	return building_args(f"{hall_text if hall else home}; {size}, no blue anywhere")





def chip_args(left: str, right: str, frames: str = "walking frames: left foot forward, standing, right foot forward",
		reference: str = "", ref_note: str = "") -> dict:
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
		args["subject"] += " " + (ref_note or ("Use Image 1 only as style, scale and sprite-sheet layout reference; create different hair, hair colour, accessories and outfit accent colours. "
			"Keep only the royal-blue company cloth accent blue for shader hue rotation; avoid other blue, teal or cyan areas."))
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
	for race in NEW_RACES:
		for look in LOOKS:
			for version in (1, 2):
				suffix = "" if version == 1 else f"_v{version}"
				out.append({"id": f"chip_{race}_{look}{suffix}", "kind": "chip", "args": new_race_chip(race, look, version)})
				out.append({"id": f"portrait_{race}_{look}{suffix}", "kind": "portrait", "args": new_race_portrait(race, look, version)})
	for race, looks in NONWORKER_V4_APPEARANCE.items():
		for look, (male, female) in looks.items():
			cid = f"chip_{race}_{look}_v4"
			left, right = f"{male}, {V4_LOOKS[look]}", f"{female}, {V4_LOOKS[look]}"
			out.append({"id": cid, "kind": "chip", "args": chip_args(left, right, reference=f"chip_{race}_{look}")})
			out.append({"id": f"portrait_{race}_{look}_v4", "kind": "portrait", "args": portrait_args(cid, left, right)})
	for race in VILLAGE_BUILDINGS:
		out.append({"id": f"b_v_{race}_home", "kind": "building", "args": village_building_args(race, False)})
		out.append({"id": f"b_v_{race}_hall", "kind": "building", "args": village_building_args(race, True)})
		out.append({"id": f"b_v_{race}_hall_back", "kind": "building_back",
			"args": building_back_args(f"b_v_{race}_hall", "entrance, statues and front banners")})
	for key in TOWN_BUILDINGS:
		out.append({"id": f"b_t_{key}", "kind": "building", "args": town_building_args(key)})
		if key in TOWN_BACK_FEATURES:
			out.append({"id": f"b_t_{key}_back", "kind": "building_back",
				"args": building_back_args(f"b_t_{key}", TOWN_BACK_FEATURES[key])})
	for entry in out:
		if entry["id"].startswith(("chip_android_", "portrait_android_", "b_v_android_")):
			entry["args"]["model"] = "openai-codex/gpt-image-2"
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
