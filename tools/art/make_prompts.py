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

# --- extra worker paintings (v3, v4) for the later races ---------------------------------------------
# Workers are the look most people wear (over half of a village), so they get two more paintings first.
# Requests are batched to save image-generation quota: one image holds the v3 and v4 sheets of one race
# side by side (12 columns), and one portrait image holds six busts (three sheets). tools/art/split_batches.py
# cuts the results back into the per-sheet raws that process.py reads.
EXTRA_WORKER_VERSIONS = (3, 4)
NEW_RACES_V3 = {
	"minotaur": ("a Minotaur man (bull-headed folk: a tan and cream spotted bull head with short forward-curving horns, one horn wrapped in leather, a shaggy russet mane and a tufted tail)",
		"a Minotaur woman (bull folk: a sleek chestnut head with one broken horn tipped in brass, a long braided black mane over one shoulder, a tufted tail and cloven hooves)"),
	"centaur": ("a Centaur man (human upper body joined at the waist to the body of a bay horse with a black mane and tail) with a red topknot and a freckled sunburnt face",
		"a Centaur woman (human upper body joined at the waist to the body of a piebald black-and-white horse) with long straight black hair and gold hoop earrings"),
	"harpy": ("a Harpy man (bird folk: rust-orange and grey kestrel-patterned wings instead of arms with small clawed hands at the wrist joints, talons) with a spiky crest of orange feather hair",
		"a Harpy woman (bird folk: soft snowy-white owl-like wings instead of arms with small clawed hands at the wrist joints, talons) with a round face and short fluffy white-and-grey feather hair"),
	"lamia": ("a Lamia man (serpent folk: human upper body and a long thick olive snake tail with dark stripes instead of legs, fine scales along the jaw, slit green-gold eyes) with short spiky bronze hair",
		"a Lamia woman (serpent folk: human upper body and a long thick coral-pink and cream snake tail instead of legs, a delicate scaled brow, slit amber eyes) with a high bun of white hair"),
	"oni": ("an Oni man (Japanese ogre folk: moss-green skin, two long curved horns, big tusks, a black topknot and a broad scarred chest)",
		"an Oni woman (Japanese ogre folk: peach-orange skin, two tiny horns half hidden in curly dark-red hair, small fangs and a friendly wide smile)"),
	"tengu": ("a Tengu man (Japanese mountain goblin folk: a human face with a long pale nose, black hair in a tight topknot, a thin grey moustache, brown-black wings folded on the back, bird feet)",
		"a Tengu woman (Japanese crow folk: a human face with red eye markings, short black hair with a white feather streak, glossy black wings folded on the back, bird-clawed feet)"),
	"goblin": ("a Goblin man (small goblin folk: sage-green skin, one huge pointed ear pierced with three brass rings, a big chin and sharp yellow teeth) with a red bandana over shaggy brown hair",
		"a Goblin woman (small goblin folk: warm lime-green skin with darker freckles, huge upswept ears, bright orange eyes and a wide grin) with long black hair in a messy side ponytail"),
	"orc": ("an Orc man (big orc folk: moss-green skin, short stubby tusks, a thick neck and tribal scars) with a shaved head and a braided red beard",
		"an Orc woman (strong orc folk: grey-green skin, small tusks, a broad smile and a bandage over one eyebrow) with a thick blond braid"),
	"kobold": ("a Kobold man (small reptilian kobold folk: mustard-yellow scales with brown stripes, a long thin snout, two tall straight horns, orange eyes and a long tail)",
		"a Kobold woman (small reptilian kobold folk: brick-red scales with a cream chin, a short snout, curled ram-like horns, round yellow eyes and a tail with a fluffy tuft)"),
	"lizardfolk": ("a Lizardfolk man (tall reptilian lizard folk: a chameleon-like head with a small casque crest, mottled green and tan scales, wide round eyes and a long curling tail)",
		"a Lizardfolk woman (tall reptilian lizard folk: a sleek snake-like head, glossy black scales with a yellow throat, a narrow frill and a long tail)"),
	"gnome": ("a Gnome man (tiny gnome folk: a long braided orange beard, a small round nose, thick eyebrows and a floppy pointed brown hat)",
		"a Gnome woman (tiny gnome folk: a big smile, a rosy round nose, white hair in a tall swirl bun and a small pointed yellow hat)"),
	"halfling": ("a Halfling man (small halfling folk: a round face with a neat ginger beard, short messy ginger hair, slightly pointed ears and big bare hairy feet)",
		"a Halfling woman (small halfling folk: a round face, long chestnut hair in a side braid with ribbons, slightly pointed ears and big bare hairy feet)"),
	"android": ("an Android man, a self-aware mechanical citizen with a rounded ivory porcelain helmet-like head, a single wide amber-gold luminous visor band, dark articulated joints, brass rivet accents and broad plated shoulders",
		"an Android woman, a self-aware mechanical citizen with a slim ivory porcelain head with a high swept crest, two narrow amber-gold luminous eyes, dark articulated joints, brass filigree accents and slender plated limbs"),
}
NEW_RACES_V4 = {
	"minotaur": ("a Minotaur man (elderly bull-headed folk: a grey-muzzled white bull head with thick low horns, a bushy grey chin tuft, a broad hunched frame and a tufted tail)",
		"a Minotaur woman (young bull folk: a dappled brown-and-white head with small upswept horns, a red flower tucked behind one ear, wavy auburn hair and a tufted tail)"),
	"centaur": ("a Centaur man (human upper body joined at the waist to the body of a roan horse with a white blaze) with grey-streaked brown hair, a thick moustache and an old scar",
		"a Centaur woman (human upper body joined at the waist to the body of a buckskin horse with dark stockings) with a short blond crop and a beaded braid"),
	"harpy": ("a Harpy man (older bird folk: dark iron-grey eagle wings with white tips instead of arms with small clawed hands at the wrist joints, talons) with slicked-back grey feather hair and a hooked nose",
		"a Harpy woman (bird folk: warm copper and cream falcon wings instead of arms with small clawed hands at the wrist joints, talons) with long braided feather hair in copper and cream"),
	"lamia": ("a Lamia man (older serpent folk: human upper body and a long thick ash-grey and rust snake tail instead of legs, a scarred scaled cheek, slit yellow eyes) with a long grey braid",
		"a Lamia woman (serpent folk: human upper body and a long thick ruby-red and black banded snake tail instead of legs, freckles and cheek scales, slit golden eyes) with wavy dark-red hair and a golden headband"),
	"oni": ("an Oni man (older Japanese ogre folk: pale ash-grey skin, one broken horn, a long white moustache and a bald head with red tattoo-like marks)",
		"an Oni woman (Japanese ogre folk: warm brown skin, two curved golden horns, long straight white hair with a red ribbon and sharp fangs)"),
	"tengu": ("a Tengu man (Japanese crow folk: a grey-feathered crow head with a hooked black beak, wings of dark ash and white feathers folded on the back, bird feet)",
		"a Tengu woman (Japanese mountain goblin folk: a human face with a long rosy nose, wild silver hair with red cord ties, black wings folded on the back, bird-clawed feet)"),
	"goblin": ("a Goblin man (old goblin folk: dull grey-green skin, drooping ears, a long wispy white beard, a hunched back and a toothless grin)",
		"a Goblin woman (small goblin folk: bright olive skin, pointy ears with tiny bells, a small chin and a mischievous grin) with two thick purple braids"),
	"orc": ("an Orc man (older orc folk: dark grey-green skin, large chipped tusks, white mutton-chop whiskers and one milky eye)",
		"an Orc woman (young orc folk: olive skin, tiny tusks and painted white stripes on the forehead) with a black bob and copper earrings"),
	"kobold": ("a Kobold man (old reptilian kobold folk: pale grey-brown scales, one cracked horn, white whisker barbels, a wrinkled snout and a short thick tail)",
		"a Kobold woman (small reptilian kobold folk: dark maroon scales with orange freckle spots, a frilled crest, tiny horns with bone beads and a thin tail)"),
	"lizardfolk": ("a Lizardfolk man (old reptilian lizard folk: a heavy-jawed head, faded grey-green scales with white scars, a broken spine ridge and a thick tail)",
		"a Lizardfolk woman (tall reptilian lizard folk: a gecko-like head with large amber eyes, pale sage scales with orange spots, a small crest and a long tail)"),
	"gnome": ("a Gnome man (tiny old gnome folk: a bald head with a fringe of white hair, a huge white moustache, a red nose and a tall pointed grey hat)",
		"a Gnome woman (tiny gnome folk: freckled cheeks, short curly copper hair, a button nose and a tall pointed maroon hat with a feather)"),
	"halfling": ("a Halfling man (older halfling folk: a bald head, white bushy sideburns, round spectacles, slightly pointed ears and big bare hairy feet)",
		"a Halfling woman (young halfling folk: short black curly hair, a gap-toothed smile, rosy cheeks, slightly pointed ears and big bare hairy feet)"),
	"android": ("an Android man, a self-aware mechanical citizen with a squared ivory porcelain head, a small brass ear-dish on each side, round amber-gold luminous eyes, dark articulated joints and repair seams in the porcelain filled with brass",
		"an Android woman, a self-aware mechanical citizen with an oval ivory porcelain head with a soft pointed chin, amber-gold luminous eyes, a fine brass halo ring behind the head, dark articulated joints and layered petal-like shoulder plates"),
}
EXTRA_WORKER_OUTFIT = {3: ADDITIONAL_WORKER_LOOK, 4: ADDITIONAL_WORKER_V5_LOOK}
ANDROID_WORKER_OUTFIT = {
	3: "wearing a dark leather work harness with a short royal-blue sash and a brass wrench at the hip; no hat, no full shirt, no full trousers",
	4: "wearing a slim brass-buckled utility harness, a short royal-blue cloth half-apron and holding a small brass oil can; no hat, no full shirt, no full trousers",
}
PORTRAITS_PER_BATCH = 3


def extra_worker_looks(race: str, version: int) -> tuple[str, str]:
	male, female = (NEW_RACES_V3 if version == 3 else NEW_RACES_V4)[race]
	outfit = ANDROID_WORKER_OUTFIT[version] if race == "android" else EXTRA_WORKER_OUTFIT[version]
	return f"{male}, {outfit}", f"{female}, {outfit}"


def extra_worker_batch_chip(race: str) -> dict:
	frames = NEW_RACE_FRAMES.get(race, "walking frames: left foot forward, standing, right foot forward")
	sheets = []
	for slot, version in enumerate(EXTRA_WORKER_VERSIONS):
		left, right = extra_worker_looks(race, version)
		first = slot * 6
		sheets.append(f"Columns {first + 1}-{first + 3}: {left}. Columns {first + 4}-{first + 6}: {right}.")
	subject = ("FOUR RPG character sprite sheets in one wide image (character chips) for a cozy frontier fantasy game, "
		"laid out as a single strict grid of 12 columns and 4 rows of equal cells. Rows from top to bottom: facing down toward "
		"the viewer, facing left, facing right, facing up away from the viewer. Each character uses 3 adjacent columns for "
		f"{frames}. " + " ".join(sheets) + " The four characters are four different people, none of them the character in Image 1. "
		"All figures have identical size and chibi proportions, feet on the same baseline in each row, each centred in an equal cell "
		"with empty space around it. " + NEW_RACE_REFERENCE + " " + NEW_RACE_BODY[race])
	args = {"subject": subject, "style": CHIP_STYLE, "scene": BG,
		"composition": "12 columns x 4 rows evenly spaced grid, whole figures fully visible, nothing touching the image edges",
		"aspect_ratio": "3:2", "image_size": "1536x1024", "model": MODEL,
		"input": [{"path": f"art_src/raw/chip_{race}_worker.webp"}]}
	if race == "android":
		args["model"] = "openai-codex/gpt-image-2"
	return args


def extra_worker_batch_portrait(sheets: list) -> dict:
	"""`sheets` is up to three (race, version) pairs; row 1 holds their men, row 2 their women."""
	described = []
	for i, (race, version) in enumerate(sheets, 1):
		left, right = extra_worker_looks(race, version)
		described.append(f"Image {i}: the man is {left}; the woman is {right}.")
	subject = ("Six character portraits in a grid of 3 columns and 2 rows for a fantasy strategy game UI. Images 1, 2 and 3 are "
		"pixel-art sprite sheets, each with two characters (left half = a man, right half = a woman). TOP ROW, left to right: the "
		"man from Image 1, the man from Image 2, the man from Image 3. BOTTOM ROW, left to right: the woman from Image 1, the woman "
		"from Image 2, the woman from Image 3. " + " ".join(described) + " Keep each character's hair, ears, face, race features and "
		"outfit colours exactly as in its sprites.")
	args = {"subject": subject, "style": PORTRAIT_STYLE,
		"scene": "each portrait on its own simple dark slate-blue vignette background",
		"composition": "six equal square head-and-shoulders bust portraits in a 3x2 grid, faces slightly above the middle, whole heads visible with space above, no borders, no text",
		"aspect_ratio": "3:2", "image_size": "1536x1024", "model": MODEL,
		"input": [{"path": f"art_src/raw/chip_{race}_worker_v{version}.webp"} for race, version in sheets]}
	if any(race == "android" for race, _ in sheets):
		args["model"] = "openai-codex/gpt-image-2"
	return args


def extra_worker_batches() -> list:
	out = []
	for race in NEW_RACES_V3:
		out.append({"id": f"batch_chip_{race}_worker", "kind": "chip_batch", "args": extra_worker_batch_chip(race),
			"splits": [f"chip_{race}_worker_v{v}" for v in EXTRA_WORKER_VERSIONS]})
	pairs = [(race, v) for race in NEW_RACES_V3 for v in EXTRA_WORKER_VERSIONS]
	for n in range(0, len(pairs), PORTRAITS_PER_BATCH):
		group = pairs[n:n + PORTRAITS_PER_BATCH]
		out.append({"id": f"batch_portrait_worker_{n // PORTRAITS_PER_BATCH + 1}", "kind": "portrait_batch",
			"args": extra_worker_batch_portrait(group),
			"splits": [f"portrait_{race}_worker_v{v}" for race, v in group]})
	return out


# --- third painting (v3) for the later races' other looks --------------------------------------------
# Same batching as the workers: one chip image per race holds two looks (four characters), portraits three sheets.
EXTRA_LOOK_STEMS = {
	"minotaur": ("a Minotaur man (bull-headed folk: {}, a tufted tail and cloven hooves)", "a Minotaur woman (bull folk: {}, a tufted tail and cloven hooves)"),
	"centaur": ("a Centaur man (human upper body joined at the waist to a horse body: {})", "a Centaur woman (human upper body joined at the waist to a horse body: {})"),
	"harpy": ("a Harpy man (bird folk: feathered wings instead of arms with small clawed hands at the wrist joints, talons; {})", "a Harpy woman (bird folk: feathered wings instead of arms with small clawed hands at the wrist joints, talons; {})"),
	"lamia": ("a Lamia man (serpent folk: human upper body and a long thick snake tail instead of legs; {})", "a Lamia woman (serpent folk: human upper body and a long thick snake tail instead of legs; {})"),
	"oni": ("an Oni man (Japanese ogre folk: {})", "an Oni woman (Japanese ogre folk: {})"),
	"tengu": ("a Tengu man (Japanese crow folk: black wings folded on the back, bird feet; {})", "a Tengu woman (Japanese crow folk: black wings folded on the back, bird-clawed feet; {})"),
	"goblin": ("a Goblin man (small goblin folk: {})", "a Goblin woman (small goblin folk: {})"),
	"orc": ("an Orc man (big orc folk: {})", "an Orc woman (strong orc folk: {})"),
	"kobold": ("a Kobold man (small reptilian kobold folk: {}, a long tail)", "a Kobold woman (small reptilian kobold folk: {}, a long tail)"),
	"lizardfolk": ("a Lizardfolk man (tall reptilian lizard folk: {}, a long tail)", "a Lizardfolk woman (tall reptilian lizard folk: {}, a long tail)"),
	"gnome": ("a Gnome man (tiny gnome folk: {})", "a Gnome woman (tiny gnome folk: {})"),
	"halfling": ("a Halfling man (small halfling folk: {}, slightly pointed ears and big bare hairy feet)", "a Halfling woman (small halfling folk: {}, slightly pointed ears and big bare hairy feet)"),
	"android": ("an Android man, a self-aware mechanical citizen with {}", "an Android woman, a self-aware mechanical citizen with {}"),
}
EXTRA_LOOK_DETAILS = {
	"minotaur": {
		"fighter": ("a rust-red bull head with wide-set horns capped in brass, a torn ear and a thick scarred neck", "a cream bull head with short sharp horns, dark kohl-lined eyes and a long black braid"),
		"ranger": ("a sandy-tan bull head with slender upswept horns, a wispy goatee and leaf-green feathers tied to one horn", "a dappled grey bull head with small horns, long ears with copper rings and windswept white hair"),
		"engineer": ("a dark brown bull head with stubby horns, soot-smudged fur and round brass spectacles", "a chestnut bull head with curled horns, a red bandana and a spray of freckles across the snout"),
		"scholar": ("an elderly white bull head with long drooping horns, a grey chin beard and half-moon spectacles", "a honey-gold bull head with elegant lyre-shaped horns, a silver circlet and long wavy black hair"),
	},
	"centaur": {
		"fighter": ("a dun horse with a black dorsal stripe; a shaved head, a braided black beard and a scarred brow", "a chestnut horse with a white blaze; a long red ponytail and a determined jaw"),
		"ranger": ("a grey dappled horse; long sandy hair tied back and stubble", "a palomino horse with a flaxen tail; short black hair with a braided fringe and freckles"),
		"engineer": ("a black horse with white socks; grey mutton-chop whiskers and soot on the cheek", "a bay horse; a dark bob, goggles pushed up on the forehead and a small burn scar"),
		"scholar": ("a white horse with grey flecks; a long white beard and a thin nose", "a roan horse; long silver-streaked brown hair in a bun and round spectacles"),
	},
	"harpy": {
		"fighter": ("steel-grey and white eagle wings; a shaved head with a black crest of feathers and a fierce brow", "dark brown and gold hawk wings; long black feather hair in a high ponytail"),
		"ranger": ("speckled brown owl wings; messy tawny feather hair and sharp amber eyes", "parrot-like green and yellow wings; short bright feather hair"),
		"engineer": ("sooty black crow-like wings; grey feather hair and brass goggles", "rust-red and cream kestrel wings; short spiky orange feather hair and a smudge of oil on the cheek"),
		"scholar": ("pure white heron wings; a long white feather ruff and calm grey eyes", "soft dove-grey and rose wings; long silver feather hair and a delicate circlet"),
	},
	"lamia": {
		"fighter": ("a dark-green and black banded tail; a shaved head with scale tattoos and a scarred lip", "a crimson and gold tail; long black hair in a warrior's braid"),
		"ranger": ("a mottled brown and tan tail; short spiky hair and green-gold eyes", "a jade-and-cream tail; a long red ponytail and freckled scaled cheeks"),
		"engineer": ("a copper-brown tail with dark stripes; cropped grey hair and goggles pushed onto the forehead", "an emerald tail with black diamonds; pink hair in twin buns and oil-stained fingers"),
		"scholar": ("a pale sand-and-white tail; a hooded cobra frill and a long white beard", "a plum and silver tail; very long white hair and a silver circlet"),
	},
	"oni": {
		"fighter": ("crimson skin, one broken horn, a black topknot and a scarred chest", "deep red skin, two swept-back horns and a long black braid"),
		"ranger": ("moss-green skin, two short horns, a wild grey mane and a bow-callused hand", "coral skin, a single horn, short black hair with a red headband and freckles"),
		"engineer": ("ochre skin, two stubby horns, a bald head and soot-blackened tusks", "rosy skin, tiny horns, curly copper hair and a wide grin"),
		"scholar": ("pale ash-grey skin, one long horn, a white moustache and a calm look", "warm brown skin, two golden horns and long white hair pinned up with sticks"),
	},
	"tengu": {
		"fighter": ("a glossy black crow head with a strong beak and a red war mask painted on the brow", "a human face with a fierce stare, short black hair and a red stripe across the eyes"),
		"ranger": ("a brown hawk head with a hooked beak and keen yellow eyes", "a human face with a long ponytail of black hair with brown feathers, and freckles"),
		"engineer": ("a human face with a long red nose, soot smears and brass goggles", "a crow head with a short beak, goggles and oil-stained feathers"),
		"scholar": ("a white-feathered crow head with a long thin beak and round spectacles", "a human face with very long white hair, a red brow mark and a calm smile"),
	},
	"goblin": {
		"fighter": ("grey-green skin, huge notched ears, a broken tooth and a bandaged eye", "bright green skin, huge pointed ears with studs, a fierce grin and red war-paint stripes"),
		"ranger": ("moss-green skin, huge droopy ears with feathers tied to them and a lean face", "lime-green skin, huge pointed ears, sharp eyes and a long black braid with beads"),
		"engineer": ("yellow-green skin, huge ears, thick goggles pushed up and singed eyebrows", "olive skin, huge ears with tiny brass gears as earrings and messy pink hair"),
		"scholar": ("pale sage skin, huge ears, a long thin white beard and a tiny monocle", "soft green skin, huge ears, big round glasses and a high purple bun"),
	},
	"orc": {
		"fighter": ("dark grey-green skin, big tusks, a scarred bald head and a heavy jaw", "sage-green skin, small tusks, a long red braid and war paint"),
		"ranger": ("olive skin, short tusks, a shaggy black mane with a feather tied in it", "grey-green skin, small tusks and short hair with a white streak"),
		"engineer": ("moss-green skin, chipped tusks, soot-black beard stubble and goggles", "green skin, small tusks, a tight black bun and rolled sleeves stained with oil"),
		"scholar": ("pale grey-green skin, worn tusks, a white braided beard and small round spectacles", "olive skin, tiny tusks, long silver hair and ink-stained fingers"),
	},
	"kobold": {
		"fighter": ("dark red scales, two swept-back horns and a scarred snout", "brown scales with a cream belly, short thick horns and a defiant grin"),
		"ranger": ("sandy-yellow scales, long slim horns and big alert eyes", "olive-green scales, small horns and a frilled crest"),
		"engineer": ("grey scales with soot, stubby horns and goggles on the snout", "rust-orange scales, tiny horns with brass rings and a tool pouch"),
		"scholar": ("pale cream scales, curled horns, tiny round spectacles and whisker barbels", "deep maroon scales with gold speckles, a small crown-like crest and long eyelashes"),
	},
	"lizardfolk": {
		"fighter": ("dark green scales, a crest of spines, a scarred snout and a heavy jaw", "black-green scales with a red throat, a narrow frill and a fierce yellow stare"),
		"ranger": ("sandy-brown striped scales and a lean head with a small crest", "bright leaf-green scales with orange spots and big amber eyes"),
		"engineer": ("olive scales with soot, a blunt snout and goggles pushed onto the brow", "mottled green-and-tan scales, a small frill and a bandana"),
		"scholar": ("pale grey-green scales, a long white crest-mane and small round glasses", "golden-olive scales with dark bands, a tall elegant crest and calm eyes"),
	},
	"gnome": {
		"fighter": ("a bristly ginger beard, a bulbous red nose and a steel helmet with a tall pointed top", "a fierce frown, rosy cheeks, short grey hair and a steel helmet with a tall pointed top"),
		"ranger": ("a bushy brown beard with twigs in it, a round nose and a tall pointed green hat", "freckles, a long chestnut braid and a tall pointed olive hat with a feather"),
		"engineer": ("wild grey hair, a huge moustache, singed eyebrows and a tall pointed orange hat with goggles", "pink hair in two buns, a button nose, oil smudges and a tall pointed brown hat"),
		"scholar": ("a very long white beard down to the belt, tiny spectacles and a tall pointed plum hat", "silver hair in a high knot, round glasses and a tall pointed dark-green hat"),
	},
	"halfling": {
		"fighter": ("a square jaw, short black curls and a scar on the chin", "a round determined face with a short red braid"),
		"ranger": ("tousled sandy hair, stubble and bright green eyes", "long straight dark hair with a leaf tucked behind the ear, and freckles"),
		"engineer": ("thin brown curls, big round goggles and a smudged cheek", "a curly ginger bob, oil-stained cheeks and a wide smile"),
		"scholar": ("a bald head with white side tufts and tiny spectacles", "long silver-blond hair in a low bun and cat-eye glasses"),
	},
	"android": {
		"fighter": ("a heavy visored ivory helmet-head with a single amber slit, a notched brass crest and a reinforced neck ring", "a slim ivory head with two angular swept-back fins, narrow amber eyes and a brass circlet"),
		"ranger": ("a lean ivory head with a long hooded brow shell, small amber eyes and antenna-like brass whiskers", "a rounded ivory head with tall antenna-like brass whiskers, large amber eyes and one open swept fin"),
		"engineer": ("a boxy ivory head with a hinged brass eyepiece, small round amber eyes and exposed brass rivets", "a smooth ivory head with a pair of small brass gear ornaments at the temples and amber eyes"),
		"scholar": ("a tall narrow ivory head with a domed crown, calm amber eyes and a fine brass ring across the brow", "a smooth ivory head shaped like a soft teardrop, thin amber eyes and a cascade of small brass petal plates at the back of the head"),
	},
}
# Outfits are the original races' fourth-look clothes (V4_LOOKS, defined further down), so they differ from v1 and v2.
ANDROID_LOOK_OUTFIT = {
	"fighter": "wearing dark-lacquered ivory armour plates with a royal-blue tabard panel, carrying a longsword and a brass-edged tower shield; head shell fully visible",
	"ranger": "wearing light ivory shell armour with a dark green half-cloak and a royal-blue arm band, carrying a recurve bow and quiver; head shell and hip plates visible",
	"engineer": "wearing ivory armour with a rust-orange work apron panel, a royal-blue neck scarf and brass goggles, carrying a big brass spanner and a tool pouch",
	"scholar": "wearing ivory armour with a long dark-green coat panel and a royal-blue stole, carrying a brass-tipped lantern staff; smooth faceplate unobscured",
}
EXTRA_LOOK_PAIRS = (("fighter", "ranger"), ("engineer", "scholar"))


def extra_look_descriptions(race: str, look: str) -> tuple[str, str]:
	man_stem, woman_stem = EXTRA_LOOK_STEMS[race]
	man, woman = EXTRA_LOOK_DETAILS[race][look]
	outfit = ANDROID_LOOK_OUTFIT[look] if race == "android" else V4_LOOKS[look]
	return f"{man_stem.format(man)}, {outfit}", f"{woman_stem.format(woman)}, {outfit}"


def extra_look_batch_chip(race: str, looks: tuple) -> dict:
	frames = NEW_RACE_FRAMES.get(race, "walking frames: left foot forward, standing, right foot forward")
	sheets = []
	for slot, look in enumerate(looks):
		left, right = extra_look_descriptions(race, look)
		first = slot * 6
		sheets.append(f"Columns {first + 1}-{first + 3}: {left}. Columns {first + 4}-{first + 6}: {right}.")
	subject = ("FOUR RPG character sprite sheets in one wide image (character chips) for a cozy frontier fantasy game, "
		"laid out as a single strict grid of 12 columns and 4 rows of equal cells. Rows from top to bottom: facing down toward "
		"the viewer, facing left, facing right, facing up away from the viewer. Each character uses 3 adjacent columns for "
		f"{frames}. " + " ".join(sheets) + " The four characters are four different people, none of them a character in the reference images. "
		"All figures have identical size and chibi proportions, feet on the same baseline in each row, each centred in an equal cell "
		"with empty space around it. IMPORTANT: draw exactly 12 columns x 4 rows = 48 figures, every column filled in all 4 rows, "
		"with wide equal spacing between figures. " + NEW_RACE_REFERENCE + " " + NEW_RACE_BODY[race])
	args = {"subject": subject, "style": CHIP_STYLE, "scene": BG,
		"composition": "12 columns x 4 rows evenly spaced grid, whole figures fully visible, nothing touching the image edges",
		"aspect_ratio": "3:2", "image_size": "1536x1024", "model": MODEL,
		"input": [{"path": f"art_src/raw/chip_{race}_{look}.webp"} for look in looks]}
	if race == "android":
		args["model"] = "openai-codex/gpt-image-2"
	return args


def extra_look_batch_portrait(sheets: list) -> dict:
	"""`sheets` is up to three (race, look) pairs; row 1 holds their men, row 2 their women."""
	described = []
	for i, (race, look) in enumerate(sheets, 1):
		left, right = extra_look_descriptions(race, look)
		described.append(f"Image {i}: the man is {left}; the woman is {right}.")
	subject = ("Six character portraits in a grid of 3 columns and 2 rows for a fantasy strategy game UI. Images 1, 2 and 3 are "
		"pixel-art sprite sheets, each with two characters (left half = a man, right half = a woman). TOP ROW, left to right: the "
		"man from Image 1, the man from Image 2, the man from Image 3. BOTTOM ROW, left to right: the woman from Image 1, the woman "
		"from Image 2, the woman from Image 3. " + " ".join(described) + " Keep each character's hair, ears, face, race features and "
		"outfit colours exactly as in its sprites.")
	args = {"subject": subject, "style": PORTRAIT_STYLE,
		"scene": "each portrait on its own simple dark slate-blue vignette background",
		"composition": "six equal square head-and-shoulders bust portraits in a 3x2 grid, faces slightly above the middle, whole heads visible with space above, no borders, no text",
		"aspect_ratio": "3:2", "image_size": "1536x1024", "model": MODEL,
		"input": [{"path": f"art_src/raw/chip_{race}_{look}_v3.webp"} for race, look in sheets]}
	if any(race == "android" for race, _ in sheets):
		args["model"] = "openai-codex/gpt-image-2"
	return args


def extra_look_batches() -> list:
	out = []
	for race in EXTRA_LOOK_STEMS:
		for n, looks in enumerate(EXTRA_LOOK_PAIRS, 1):
			out.append({"id": f"batch_chip_{race}_looks{n}", "kind": "chip_batch",
				"args": extra_look_batch_chip(race, looks), "splits": [f"chip_{race}_{look}_v3" for look in looks]})
	sheets = [(race, look) for race in EXTRA_LOOK_STEMS for pair in EXTRA_LOOK_PAIRS for look in pair]
	for n in range(0, len(sheets), PORTRAITS_PER_BATCH):
		group = sheets[n:n + PORTRAITS_PER_BATCH]
		out.append({"id": f"batch_portrait_looks_{n // PORTRAITS_PER_BATCH + 1}", "kind": "portrait_batch",
			"args": extra_look_batch_portrait(group), "splits": [f"portrait_{race}_{look}_v3" for race, look in group]})
	return out

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
	out.extend(extra_worker_batches())
	out.extend(extra_look_batches())
	for entry in out:
		if entry["id"].startswith(("chip_android_", "portrait_android_", "b_v_android_")):
			entry["args"]["model"] = "openai-codex/gpt-image-2"
	return sorted(out, key=_priority)


SITE_BUILDINGS = ("b_bandit", "b_campfire", "b_machine", "b_trade", "b_wanderer", "b_ruin", "b_wreck")


def _priority(entry: dict) -> int:
	"""Generation order: what the player sees first, and chips before the portraits that use them."""
	i = entry["id"]
	if i.startswith("batch_chip_") or (i.startswith("chip_") and not i.startswith("chip_mach")):
		return 0
	if i.startswith("props_"):
		return 1
	if i.startswith("t_"):
		return 2
	if i.startswith("b_") and not i.startswith(SITE_BUILDINGS):
		return 3
	if i.startswith("chip_mach") or i.startswith("air_"):
		return 4
	if i.startswith(("portrait_", "batch_portrait_")):
		return 5
	return 6


if __name__ == "__main__":
	entries = build()
	path = ROOT / "art_src" / "prompts.json"
	path.parent.mkdir(parents=True, exist_ok=True)
	path.write_text(json.dumps(entries, indent=1, ensure_ascii=False) + "\n")
	print(f"{len(entries)} prompts -> {path}")
