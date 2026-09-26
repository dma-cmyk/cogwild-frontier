class_name BuildPalette
extends RefCounted
## Faction colour set for building geometry. Statically typed so part builders never index
## Dictionaries in hot paths. Colours are sRGB and follow contracts.md §1.

var stone: Color            ## masonry plinths, walls, chimneys
var stone_top: Color        ## lit top faces of masonry
var stone_dark: Color       ## mortar joints / individual stones
var plaster: Color          ## wall infill between the timbers
var plaster_dark: Color     ## shaded infill, wall interiors
var timber: Color           ## structural frame beams
var wood: Color             ## boards, doors, decks
var wood_dark: Color        ## shaded boards, ridge beams
var roof: Color             ## roof tiles
var roof_dark: Color        ## shingle courses, roof underside
var metal: Color            ## iron fittings, pipes, ballista
var gold: Color             ## trim, crests, finials
var cloth: Color            ## banners, awnings, tents
var cloth_alt: Color        ## second awning stripe
var glow: Color             ## window / furnace light
var moss: Color             ## moss and overgrowth


static func of(style: String) -> BuildPalette:
	var p := BuildPalette.new()
	match style:
		"bandit":
			p.stone = Color("8a8377"); p.stone_dark = Color("6d6759"); p.plaster = Color("7a6a55")
			p.timber = Color("4a3426"); p.wood = Color("6f4c30"); p.roof = Color("6e2b25")
			p.metal = Color("8c4a2a"); p.gold = Color("b9883c"); p.cloth = Color("b33a2e")
			p.cloth_alt = Color("7a6a55"); p.glow = Color("ff8a39"); p.moss = Color("5f6a3e")
		"ancient":
			p.stone = Color("5b6470"); p.stone_dark = Color("434b55"); p.plaster = Color("6c7480")
			p.timber = Color("47505b"); p.wood = Color("a07a4a"); p.roof = Color("38434f")
			p.metal = Color("a07a4a"); p.gold = Color("c79a5a"); p.cloth = Color("7a4a32")
			p.cloth_alt = Color("5b6470"); p.glow = Color("ff6a2a"); p.moss = Color("4d6350")
		"merchant":
			p.stone = Color("a9a293"); p.stone_dark = Color("847e71"); p.plaster = Color("efe3c2")
			p.timber = Color("6b4327"); p.wood = Color("9a6a3c"); p.roof = Color("3b7650")
			p.metal = Color("6d737c"); p.gold = Color("d9b04c"); p.cloth = Color("4f8a4b")
			p.cloth_alt = Color("efe3c2"); p.glow = Color("ffbe5a"); p.moss = Color("6f8a4e")
		"neutral":
			p.stone = Color("8d8f86"); p.stone_dark = Color("6e7069"); p.plaster = Color("cdbf9f")
			p.timber = Color("6b5238"); p.wood = Color("8a6a4a"); p.roof = Color("68756f")
			p.metal = Color("6d737c"); p.gold = Color("c0a45e"); p.cloth = Color("3f8f8a")
			p.cloth_alt = Color("cdbf9f"); p.glow = Color("ffd36a"); p.moss = Color("6f8a4e")
		_:
			p.stone = Color("9a958c"); p.stone_dark = Color("7a766e"); p.plaster = Color("e9dcc0")
			p.timber = Color("6b4327"); p.wood = Color("8a5a34"); p.roof = Color("3f5fa0")
			p.metal = Color("6d737c"); p.gold = Color("d9b04c"); p.cloth = Color("3a5da8")
			p.cloth_alt = Color("e9dcc0"); p.glow = Color("ffbd52"); p.moss = Color("6f8a4e")
	p.stone_top = p.stone.lightened(0.10)
	p.plaster_dark = p.plaster.darkened(0.22)
	p.wood_dark = p.wood.darkened(0.28)
	p.roof_dark = p.roof.darkened(0.26)
	return p
