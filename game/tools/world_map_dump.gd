extends Node
## Dev tool: renders the generated world around the start to a PNG (terrain, resources, sites).
## godot --headless --path game res://tools/world_map_dump.tscn -- --seed=123 --radius=6 --out=/tmp/map.png

func _ready() -> void:
	var seed := 12345
	var radius := 6
	var out := "/tmp/cf_world_map.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed = int(arg.substr(7))
		elif arg.begins_with("--radius="):
			radius = int(arg.substr(9))
		elif arg.begins_with("--out="):
			out = arg.substr(6)
	var t0 := Time.get_ticks_msec()
	var gen := WorldGen.new(seed)
	var sc := WorldGen.chunk_of(gen.start_tile)
	var S := ChunkData.S
	var n := radius * 2 + 1
	var img := Image.create(n * S, n * S, false, Image.FORMAT_RGB8)
	var chunks := 0
	var counts := {}
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var cx := sc.x + dx
			var cz := sc.y + dz
			if not gen.chunk_in_bounds(cx, cz):
				continue
			var ch := gen.generate_chunk(cx, cz)
			chunks += 1
			for lz in S:
				for lx in S:
					var i := lz * S + lx
					var tt := ch.terrain[i]
					var hc := ch.height_local(lx + 0.5, lz + 0.5)
					var col: Color = Tiles.COLORS[tt]
					if not Tiles.is_water(tt):
						col = col.lightened(clampf(hc / 14.0, 0.0, 0.5) * 0.6)
					var r := ch.res_type[i]
					if r != Tiles.Res.NONE:
						counts[r] = counts.get(r, 0) + 1
						match r:
							Tiles.Res.TREE_PINE, Tiles.Res.TREE_OAK, Tiles.Res.TREE_BIRCH:
								col = Color("#2f5a2a")
							Tiles.Res.TREE_DEAD:
								col = Color("#6b5a44")
							Tiles.Res.ROCK_SMALL, Tiles.Res.ROCK_LARGE:
								col = Color("#606060")
							Tiles.Res.ORE_IRON:
								col = Color("#d0782c")
							Tiles.Res.ORE_CRYSTAL:
								col = Color("#40e0f0")
							Tiles.Res.BERRY_BUSH:
								col = Color("#c03050")
					if ch.blocked[i] == 1:
						col = Color("#202020")
					img.set_pixel((dx + radius) * S + lx, (dz + radius) * S + lz, col)
	var base := Vector2i((sc.x - radius) * S, (sc.y - radius) * S)
	var kind_col := {"bandit_camp": Color.RED, "machine_outpost": Color("#ff8800"), "ruins": Color("#c0a0ff"),
		"trade_post": Color("#40ff40"), "wanderer_camp": Color("#ffffff"), "wreck": Color("#ffff00"),
		"crystal_grove": Color("#00ffff"), "ore_field": Color("#ff00ff")}
	var kinds := {}
	for id: int in gen.sites:
		var s: Dictionary = gen.sites[id]
		kinds[s["kind"]] = kinds.get(s["kind"], 0) + 1
		var p: Vector2i = Vector2i(s["center"]) - base
		for oy in range(-2, 3):
			for ox in range(-2, 3):
				var q := p + Vector2i(ox, oy)
				if q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height():
					img.set_pixelv(q, kind_col.get(s["kind"], Color.BLACK))
	var st := gen.start_tile - base
	for oy in range(-3, 4):
		for ox in range(-3, 4):
			img.set_pixelv(st + Vector2i(ox, oy), Color.WHITE if abs(ox) + abs(oy) < 4 else Color.BLACK)
	img.save_png(out)
	print("seed=%d start=%s start_h=%.2f chunks=%d time=%d ms sites=%s res=%s" % [seed, gen.start_tile, gen.start_height, chunks, Time.get_ticks_msec() - t0, kinds, counts])
	get_tree().quit()
