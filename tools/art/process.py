#!/usr/bin/env python3
"""Turns raw generated images (art_src/raw/<id>.*) into game assets + metadata tables.

Needs numpy, Pillow and scipy:
	python3 -m venv --system-site-packages /tmp/artenv && /tmp/artenv/bin/pip install scipy
	/tmp/artenv/bin/python tools/art/process.py [chips|portraits|props|textures|buildings|all] [--only id,id]

Outputs (all under game/):
	assets/sprites/chars/<sheet>.png     3 frames x 4 rows (down, left, right, up) character / machine chips
	assets/portraits/<id>.png            128 px square portraits for UI display.
	assets/sprites/props_atlas.png       tree / rock / plant billboards in one atlas
	assets/textures/terrain_array.png    512 px seamless ground textures stacked vertically (Texture2DArray)
	assets/sprites/buildings/<id>.png    building billboards (+ <id>_glow.png emission masks)
	data/art/{sprites,portraits,props,terrain,buildings}.json   metadata read by the game (DB tables "art/<name>")
"""
import json
import pathlib
import re
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = pathlib.Path(__file__).resolve().parents[2]
RAW = ROOT / "art_src" / "raw"
GAME = ROOT / "game"
DATA = GAME / "data" / "art"

ROW_ORDER = ["down", "left", "right", "up"]
OLD_RACES = ["human", "sylvan", "stoutkin", "vulpin"]
NEW_RACES = ["minotaur", "centaur", "harpy", "lamia", "oni", "tengu"]
RACES = OLD_RACES + NEW_RACES
LOOKS = ["worker", "fighter", "ranger", "engineer", "scholar"]

# chip sheet id -> (left sheet id, right sheet id, anchor mode)
CHIP_SHEETS = {f"chip_{r}_{l}": (f"{r}_{l}_m", f"{r}_{l}_f", "feet") for r in RACES for l in LOOKS}
CHIP_SHEETS.update({f"chip_{r}_{l}_v2": (f"{r}_{l}_m@v2", f"{r}_{l}_f@v2", "feet") for r in RACES for l in LOOKS})
CHIP_SHEETS.update({f"chip_{r}_{l}_v3": (f"{r}_{l}_m@v3", f"{r}_{l}_f@v3", "feet") for r in OLD_RACES for l in LOOKS})
CHIP_SHEETS.update({f"chip_{r}_worker_v4": (f"{r}_worker_m@v4", f"{r}_worker_f@v4", "feet") for r in OLD_RACES})
CHIP_SHEETS.update({f"chip_{r}_worker_v5": (f"{r}_worker_m@v5", f"{r}_worker_f@v5", "feet") for r in OLD_RACES if r != "sylvan"})
CHIP_SHEETS.update({f"chip_{r}_{l}_v4": (f"{r}_{l}_m@v4", f"{r}_{l}_f@v4", "feet") for r in OLD_RACES for l in LOOKS if l != "worker"})
CHIP_SHEETS.update({
	"chip_bandit_a": ("bandit_m", "bandit_f", "feet"),
	"chip_bandit_b": ("bandit_archer", "bandit_captain", "feet"),
	"chip_mach_a": ("work_bot", "walker", "feet"),
	"chip_mach_b": ("scout_drone", "repair_drone", "center"),
	"chip_mach_c": ("sentry", "war_drone", "feet"),
	"chip_mach_d": ("turret", "machine_warden", "feet"),
})
# drones hover: anchor at the middle of the figure (right half of chip_mach_c is a drone too)
CENTER_ANCHOR = {"scout_drone", "repair_drone", "war_drone"}

CELL = (128, 128)       # output chip cell (w, h)
CHIP_HEIGHT = 112       # standing figure height in the cell
CHIP_FOOT = 124         # y of the feet line inside the cell
CHIP_HEIGHT_BY_RACE = {"centaur": 104, "harpy": 108, "tengu": 108}


# --- basic image helpers -------------------------------------------------------------------

def raw_path(asset_id: str) -> pathlib.Path | None:
	hits = sorted(p for p in RAW.glob(asset_id + ".*") if p.suffix.lower() in (".webp", ".png", ".jpg", ".jpeg"))
	return hits[0] if hits else None


def load_rgba(path: pathlib.Path) -> np.ndarray:
	return np.array(Image.open(path).convert("RGBA"))


def foreground(img: np.ndarray) -> np.ndarray:
	"""Boolean mask of the subject. Uses real alpha when present, otherwise keys out magenta."""
	a = img[..., 3]
	if (a < 16).mean() > 0.05:
		return a >= 128
	rgb = img[..., :3].astype(np.int32)
	mag = np.minimum(rgb[..., 0], rgb[..., 2]) - rgb[..., 1]
	fg = mag <= 90
	near_bg = ndimage.binary_dilation(~fg, iterations=2)
	fg &= ~(near_bg & (mag > 30))
	return fg


def despill(img: np.ndarray, mask: np.ndarray) -> np.ndarray:
	"""Removes the magenta tint left on anti-aliased edges and applies the mask as alpha."""
	out = img.copy()
	rgb = out[..., :3].astype(np.int32)
	mag = np.minimum(rgb[..., 0], rgb[..., 2]) - rgb[..., 1]
	edge = mask & ndimage.binary_dilation(~mask, iterations=3) & (mag > 0)
	k = np.where(edge, mag * 0.8, 0).astype(np.int32)
	rgb[..., 0] -= k
	rgb[..., 2] -= k
	out[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8)
	out[..., 3] = np.where(mask, 255, 0).astype(np.uint8)
	return out


def components(mask: np.ndarray, min_area: int, merge: int = 0) -> list[dict]:
	"""Connected parts (optionally merged when closer than `merge` px), largest first."""
	work = ndimage.binary_dilation(mask, iterations=merge) if merge > 0 else mask
	lab, n = ndimage.label(work, structure=np.ones((3, 3)))
	out = []
	for i, sl in enumerate(ndimage.find_objects(lab), start=1):
		if sl is None:
			continue
		part = (lab[sl] == i) & mask[sl]
		area = int(part.sum())
		if area < min_area:
			continue
		ys, xs = np.nonzero(part)
		out.append({"sl": sl, "label": i, "area": area,
			"cx": float(xs.mean() + sl[1].start), "cy": float(ys.mean() + sl[0].start),
			"x0": sl[1].start, "x1": sl[1].stop, "y0": sl[0].start, "y1": sl[0].stop, "lab": lab})
	out.sort(key=lambda c: -c["area"])
	return out


def grid_assign(comps: list[dict], rows: int, cols: int) -> dict:
	"""Assigns parts to a regular rows x cols grid of figures. Returns {(r, c): [parts]}."""
	big = [c for c in comps if c["area"] >= 0.25 * np.median([c["area"] for c in comps[:rows * cols]])]
	xs = np.array([c["cx"] for c in big])
	ys = np.array([c["cy"] for c in big])
	col_c = np.linspace(xs.min(), xs.max(), cols) if cols > 1 else np.array([xs.mean()])
	row_c = np.linspace(ys.min(), ys.max(), rows) if rows > 1 else np.array([ys.mean()])
	for _ in range(4):  # refine centres with the parts assigned to them
		ci = np.abs(xs[:, None] - col_c[None, :]).argmin(1)
		ri = np.abs(ys[:, None] - row_c[None, :]).argmin(1)
		col_c = np.array([xs[ci == k].mean() if (ci == k).any() else col_c[k] for k in range(cols)])
		row_c = np.array([ys[ri == k].mean() if (ri == k).any() else row_c[k] for k in range(rows)])
	pitch_x = (col_c[-1] - col_c[0]) / max(1, cols - 1) if cols > 1 else 1e9
	pitch_y = (row_c[-1] - row_c[0]) / max(1, rows - 1) if rows > 1 else 1e9
	cells: dict = {}
	for c in comps:
		k = int(np.abs(col_c - c["cx"]).argmin())
		r = int(np.abs(row_c - c["cy"]).argmin())
		if abs(col_c[k] - c["cx"]) > 0.6 * pitch_x or abs(row_c[r] - c["cy"]) > 0.6 * pitch_y:
			continue  # stray mark between cells
		cells.setdefault((r, k), []).append(c)
	return cells


def union_crop(img: np.ndarray, parts: list[dict]) -> np.ndarray:
	"""RGBA crop containing exactly the given parts (other pixels transparent)."""
	x0 = min(p["x0"] for p in parts)
	x1 = max(p["x1"] for p in parts)
	y0 = min(p["y0"] for p in parts)
	y1 = max(p["y1"] for p in parts)
	keep = np.zeros((y1 - y0, x1 - x0), bool)
	for p in parts:
		sub = p["lab"][y0:y1, x0:x1] == p["label"]
		keep |= sub
	crop = img[y0:y1, x0:x1].copy()
	keep &= crop[..., 3] > 0
	crop[..., 3] = np.where(keep, crop[..., 3], 0)
	return crop


def trim(rgba: np.ndarray) -> np.ndarray:
	ys, xs = np.nonzero(rgba[..., 3] > 0)
	return rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def resize(rgba: np.ndarray, scale: float) -> np.ndarray:
	"""Premultiplied-alpha area resize (keeps edges clean)."""
	h, w = rgba.shape[:2]
	nw, nh = max(1, round(w * scale)), max(1, round(h * scale))
	f = rgba.astype(np.float32) / 255.0
	pre = np.dstack([f[..., :3] * f[..., 3:4], f[..., 3:4]])
	chans = [np.array(Image.fromarray(pre[..., i]).resize((nw, nh), Image.Resampling.LANCZOS if scale > 1 else Image.Resampling.BOX)) for i in range(4)]
	out = np.dstack(chans)
	a = np.clip(out[..., 3:4], 0.0, 1.0)
	rgb = np.where(a > 1e-4, out[..., :3] / np.maximum(a, 1e-4), 0.0)
	return (np.clip(np.dstack([rgb, a]), 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)


def bleed(rgba: np.ndarray) -> np.ndarray:
	"""Copies the nearest opaque colour into transparent pixels (no dark halos when filtered)."""
	solid = rgba[..., 3] >= 128
	if not solid.any():
		return rgba
	_, (iy, ix) = ndimage.distance_transform_edt(~solid, return_indices=True)
	out = rgba.copy()
	out[..., :3] = rgba[iy, ix, :3]
	return out


def save_png(rgba: np.ndarray, path: pathlib.Path, preset: str = "sprite") -> None:
	path.parent.mkdir(parents=True, exist_ok=True)
	mode = "RGBA" if rgba.ndim == 3 and rgba.shape[2] == 4 else ("RGB" if rgba.ndim == 3 else "L")
	Image.fromarray(rgba, mode).save(path, optimize=True)
	write_import(path, preset)
	match_v2_import_settings(path)


IMPORT_PRESETS = {
	# Character chips retain HEAD VRAM-compressed imports; 128px portraits limit UI residency.
	"sprite": ('importer="texture"\ntype="CompressedTexture2D"', {
		"compress/mode": 1, "compress/high_quality": "false", "compress/lossy_quality": 0.85,
		"compress/rdo_quality_loss": 1.0, "mipmaps/generate": "true", "mipmaps/limit": -1,
		"process/fix_alpha_border": "true", "process/premult_alpha": "false", "process/size_limit": 0, "detect_3d/compress_to": 0}),
	"portrait": ('importer="texture"\ntype="CompressedTexture2D"', {
		"compress/mode": 1, "compress/high_quality": "false", "compress/lossy_quality": 0.9,
		"compress/rdo_quality_loss": 1.0, "mipmaps/generate": "true", "mipmaps/limit": -1,
		"process/fix_alpha_border": "true", "process/premult_alpha": "false", "process/size_limit": 0, "detect_3d/compress_to": 0}),
	"ui": ('importer="texture"\ntype="CompressedTexture2D"', {
		"compress/mode": 0, "mipmaps/generate": "false", "process/fix_alpha_border": "true", "detect_3d/compress_to": 0}),
	"array": ('importer="2d_array_texture"\ntype="CompressedTexture2DArray"', {
		"compress/mode": 2, "compress/high_quality": "true", "mipmaps/generate": "true", "mipmaps/limit": -1,
		"slices/horizontal": 1, "slices/vertical": 8}),
}


def write_import(path: pathlib.Path, preset: str) -> None:
	"""Import settings Godot uses for this file. Rewritten when the importer or one of the preset
	values differs (Godot then reimports the file on the next scan)."""
	imp = path.with_name(path.name + ".import")
	head, params = IMPORT_PRESETS[preset]
	uid_line = ""
	if imp.exists():
		text = imp.read_text()
		if head.split("\n")[0] in text and all(f"\n{k}={v}\n" in text for k, v in params.items()):
			return
		uid_match = re.search(r"(?m)^uid=.*$", text)
		if uid_match:
			uid_line = uid_match.group(0)
	lines = ["[remap]", "", head]
	if uid_line:
		lines.append(uid_line)
	lines += ["", "[params]", ""] + [f"{k}={v}" for k, v in params.items()]
	imp.write_text("\n".join(lines) + "\n")


def variant_suffix(asset_id: str) -> str:
	match = re.search(r"@v(\d+)$", asset_id)
	return f"_v{match.group(1)}" if match else ""


def match_v2_import_settings(path: pathlib.Path) -> None:
	variant_match = re.search(r"_v(\d+)$", path.stem)
	if not variant_match or int(variant_match.group(1)) < 3:
		return
	base_stem = path.stem[:variant_match.start()]
	source_import = path.with_name(f"{base_stem}_v2.png.import")
	target_import = path.with_name(path.name + ".import")
	if not source_import.is_file() or not target_import.is_file():
		return
	source_text = source_import.read_text()
	target_text = target_import.read_text()
	if "[params]" not in source_text or "[params]" not in target_text:
		return
	head = target_text.split("[params]", 1)[0]
	params = source_text.split("[params]", 1)[1]
	target_import.write_text(head + "[params]" + params)


def match_building_view_import_settings(path: pathlib.Path, front_path: pathlib.Path) -> None:
	"""Keep a back view's sampler settings identical to its matching front texture."""
	source_import = front_path.with_name(front_path.name + ".import")
	target_import = path.with_name(path.name + ".import")
	if not source_import.is_file() or not target_import.is_file():
		return
	source_text = source_import.read_text()
	target_text = target_import.read_text()
	if "[params]" not in source_text or "[params]" not in target_text:
		return
	target_import.write_text(target_text.split("[params]", 1)[0] + "[params]" + source_text.split("[params]", 1)[1])


def save_building_png(rgba: np.ndarray, path: pathlib.Path) -> None:
	"""Stage a building image under build/ and atomically replace it without changing presets."""
	staging = ROOT / "build" / "BuildingViews" / "process_staging"
	staging.mkdir(parents=True, exist_ok=True)
	temp_path = staging / path.name
	save_png(rgba, temp_path)
	temp_path.replace(path)
	temp_import = temp_path.with_name(temp_path.name + ".import")
	import_path = path.with_name(path.name + ".import")
	if import_path.exists():
		temp_import.unlink(missing_ok=True)
	else:
		temp_import.replace(import_path)


def write_table(name: str, entries: list[dict]) -> None:
	DATA.mkdir(parents=True, exist_ok=True)
	path = DATA / f"{name}.json"
	old = {}
	if path.exists():
		for e in json.loads(path.read_text()).get("entries", []):
			if variant_file_exists(name, e["id"]):
				old[e["id"]] = e
	for e in entries:
		if variant_file_exists(name, e["id"]):
			old[e["id"]] = e
	doc = {"table": name, "entries": [old[k] for k in sorted(old)]}
	path.write_text(json.dumps(doc, indent=1) + "\n")


def res(path: pathlib.Path) -> str:
	return "res://" + str(path.relative_to(GAME))


VARIANT_DIRS = {"sprites": "sprites/chars", "portraits": "portraits"}


def variant_file_exists(table: str, asset_id: str) -> bool:
	"""A `@vN` row survives only while its own PNG is on disk. Chips and busts are checked apart:
	a look may have a painted chip without a painted bust (the game then shows the chip's front
	frame), and no other table uses the @vN suffix."""
	folder = VARIANT_DIRS.get(table)
	suffix = variant_suffix(asset_id)
	if folder is None or not suffix:
		return True
	png = GAME / "assets" / folder / (asset_id.split("@", 1)[0] + suffix + ".png")
	return png.is_file() and png.with_name(png.name + ".import").is_file()

# --- character / machine chips --------------------------------------------------------------

def figure_anchor_x(frame: np.ndarray) -> float:
	"""Horizontal anchor: centre of mass of the upper body (stable while legs swing)."""
	a = frame[..., 3] > 0
	h = a.shape[0]
	top = a[: max(1, int(h * 0.6))]
	ys, xs = np.nonzero(top if top.any() else a)
	return float(xs.mean())


def build_chip(frames: list[list[np.ndarray]], anchor_mode: str, race_id: str = "") -> tuple[np.ndarray, dict]:
	"""Scale all twelve frames to fit one cell, preserving a shared foot anchor."""
	stand_h = float(np.median([frames[r][1].shape[0] for r in range(4)]))
	max_h = max(frame.shape[0] for row in frames for frame in row)
	max_w = max(frame.shape[1] for row in frames for frame in row)
	target_height = float(CHIP_HEIGHT_BY_RACE.get(race_id, CHIP_HEIGHT))
	scale = min(target_height / max(1.0, stand_h), (CELL[1] - 12) / max(1.0, float(max_h)),
		(CELL[0] - 8) / max(1.0, float(max_w)))
	resolved_height = max(1, round(stand_h * scale))
	cw, ch = CELL
	sheet = np.zeros((ch * 4, cw * 3, 4), np.uint8)
	clipped = 0
	for r in range(4):
		for c in range(3):
			f = resize(frames[r][c], scale)
			fh, fw = f.shape[:2]
			ax = figure_anchor_x(f)
			if anchor_mode == "center":
				oy = (ch - fh) // 2
			else:
				oy = CHIP_FOOT - fh
			ox = int(round(cw / 2 - ax))
			x0, y0 = max(0, ox), max(0, oy)
			x1, y1 = min(cw, ox + fw), min(ch, oy + fh)
			if x1 - x0 < fw or y1 - y0 < fh:
				clipped += 1
			sub = f[y0 - oy:y1 - oy, x0 - ox:x1 - ox]
			dst = sheet[r * ch:(r + 1) * ch, c * cw:(c + 1) * cw]
			dst[y0:y1, x0:x1] = sub
	meta = {"cell": [cw, ch], "cols": 3, "rows": 4, "rows_order": ROW_ORDER,
		"anchor": [cw / 2, ch / 2 if anchor_mode == "center" else CHIP_FOOT], "height_px": resolved_height,
		"anchor_mode": anchor_mode}
	if clipped:
		meta["clipped_frames"] = clipped
	return bleed(sheet), meta


def process_chips(only: set[str]) -> None:
	entries = []
	for sheet_id, (left_id, right_id, mode) in CHIP_SHEETS.items():
		if only and sheet_id not in only:
			continue
		path = raw_path(sheet_id)
		if path is None:
			print(f"  skip {sheet_id}: no raw image")
			continue
		img = load_rgba(path)
		mask = foreground(img)
		img = despill(img, mask)
		comps = components(mask, min_area=40)
		cells = grid_assign(comps, 4, 6)
		missing = [(r, c) for r in range(4) for c in range(6) if (r, c) not in cells]
		if missing:
			print(f"  WARN {sheet_id}: empty cells {missing}")
			continue
		for half, out_id in ((0, left_id), (1, right_id)):
			frames = [[trim(union_crop(img, cells[(r, half * 3 + c)])) for c in range(3)] for r in range(4)]
			race_id = out_id.split("_", 1)[0]
			sheet, meta = build_chip(frames, mode, race_id)
			variant = variant_suffix(out_id)
			file_id = out_id.split("@", 1)[0] + variant
			out = GAME / "assets" / "sprites" / "chars" / f"{file_id}.png"
			save_png(sheet, out)
			entries.append({"id": out_id, "texture": res(out), "source": sheet_id, **meta})
			print(f"  {out_id}: {meta.get('clipped_frames', 0)} clipped")
	for air_id, out_id in (("air_cargo", "cargo_airship"), ("air_trader", "trader_airship")):
		if only and air_id not in only:
			continue
		path = raw_path(air_id)
		if path is None:
			continue
		img = load_rgba(path)
		mask = foreground(img)
		img = despill(img, mask)
		cells = grid_assign(components(mask, min_area=200, merge=6), 2, 2)
		if len(cells) < 4:
			print(f"  WARN {air_id}: found {len(cells)} views")
			continue
		views = {"left": cells[(0, 0)], "right": cells[(0, 1)], "down": cells[(1, 0)], "up": cells[(1, 1)]}
		crops = {k: trim(union_crop(img, v)) for k, v in views.items()}
		side_w = max(crops["left"].shape[1], crops["right"].shape[1])
		scale = 480.0 / side_w
		scaled = {k: resize(v, scale) for k, v in crops.items()}
		cw = max(v.shape[1] for v in scaled.values()) + 8
		chh = max(v.shape[0] for v in scaled.values()) + 8
		sheet = np.zeros((chh * 4, cw, 4), np.uint8)
		for r, k in enumerate(ROW_ORDER):
			v = scaled[k]
			oy = r * chh + (chh - v.shape[0]) // 2
			ox = (cw - v.shape[1]) // 2
			sheet[oy:oy + v.shape[0], ox:ox + v.shape[1]] = v
		out = GAME / "assets" / "sprites" / "chars" / f"{out_id}.png"
		save_png(bleed(sheet), out)
		entries.append({"id": out_id, "texture": res(out), "source": air_id, "cell": [cw, chh], "cols": 1, "rows": 4,
			"rows_order": ROW_ORDER, "anchor": [cw / 2, chh / 2], "height_px": int(scaled["left"].shape[0]),
			"width_px": int(scaled["left"].shape[1]), "anchor_mode": "center"})
		print(f"  {out_id}: cell {cw}x{chh}")
	if entries:
		write_table("sprites", entries)


# --- portraits -----------------------------------------------------------------------------

def process_portraits(only: set[str]) -> None:
	entries = []
	pairs = {f"portrait_{r}_{l}": (f"{r}_{l}_m", f"{r}_{l}_f") for r in RACES for l in LOOKS}
	pairs.update({f"portrait_{r}_{l}_v2": (f"{r}_{l}_m@v2", f"{r}_{l}_f@v2") for r in RACES for l in LOOKS})
	pairs.update({f"portrait_{r}_{l}_v3": (f"{r}_{l}_m@v3", f"{r}_{l}_f@v3") for r in OLD_RACES for l in LOOKS})
	pairs.update({f"portrait_{r}_worker_v4": (f"{r}_worker_m@v4", f"{r}_worker_f@v4") for r in OLD_RACES})
	pairs.update({f"portrait_{r}_worker_v5": (f"{r}_worker_m@v5", f"{r}_worker_f@v5") for r in OLD_RACES if r != "sylvan"})
	pairs.update({f"portrait_{r}_{l}_v4": (f"{r}_{l}_m@v4", f"{r}_{l}_f@v4") for r in OLD_RACES for l in LOOKS if l != "worker"})
	pairs.update({"portrait_bandit_a": ("bandit_m", "bandit_f"), "portrait_bandit_b": ("bandit_archer", "bandit_captain")})
	for pid, (left_id, right_id) in pairs.items():
		if only and pid not in only:
			continue
		path = raw_path(pid)
		if path is None:
			continue
		img = np.array(Image.open(path).convert("RGB"))
		h, w = img.shape[:2]
		half = w // 2
		side = int(min(half, h) * 0.96)
		for i, out_id in enumerate((left_id, right_id)):
			cx = half * i + half // 2
			x0 = int(np.clip(cx - side // 2, half * i, half * (i + 1) - side))
			# heads sit near the top of the generated busts: keep hats/ears, trim the chest
			y0 = int(np.clip(h * 0.02, 0, h - side))
			crop = Image.fromarray(img[y0:y0 + side, x0:x0 + side]).resize((128, 128), Image.Resampling.LANCZOS)
			variant = variant_suffix(out_id)
			file_id = out_id.split("@", 1)[0] + variant
			out = GAME / "assets" / "portraits" / f"{file_id}.png"
			out.parent.mkdir(parents=True, exist_ok=True)
			crop.save(out, optimize=True)
			write_import(out, "portrait")
			match_v2_import_settings(out)
			entries.append({"id": out_id, "texture": res(out), "source": pid})
	if entries:
		write_table("portraits", entries)
		print(f"  {len(entries)} portraits")


# --- props atlas ---------------------------------------------------------------------------

# sheet -> list of (prop id, target height px, world height m) in reading order (row-major)
PROP_SHEETS = {
	"props_trees_a": [("tree_pine", 256, 5.2), ("tree_pine", 256, 4.8), ("tree_pine", 256, 4.4), ("tree_pine", 256, 5.4),
		("tree_oak", 224, 3.8), ("tree_oak", 224, 3.6), ("tree_birch", 224, 4.2), ("tree_dead", 192, 3.3)],
	"props_trees_b": [("tree_pine", 256, 5.6), ("tree_pine", 256, 5.3), ("tree_pine", 232, 4.6), ("tree_pine", 232, 4.4),
		("tree_pine", 232, 4.2), ("tree_pine", 192, 3.4), ("tree_pine", 192, 3.1), ("tree_pine", 192, 2.9)],
	"props_rocks": [("rock_large", 128, 1.2), ("rock_large", 128, 1.1), ("rock_small", 96, 0.55), ("rock_small", 96, 0.5),
		("ore_iron", 112, 0.8), ("ore_iron", 112, 0.8), ("ore_crystal", 128, 1.1), ("ore_crystal", 128, 1.0)],
	"props_plants": [("berry_bush", 112, 0.9), ("berry_bush", 112, 0.9), ("bush", 112, 0.95), ("bush", 112, 0.9),
		("stump", 80, 0.5), ("reeds", 112, 1.1), ("grass_tuft", 80, 0.55), ("flowers", 64, 0.35)],
}


def process_props(only: set[str]) -> None:
	sprites = []  # (prop id, rgba, world height)
	for sheet_id, layout in PROP_SHEETS.items():
		path = raw_path(sheet_id)
		if path is None:
			print(f"  skip {sheet_id}: no raw image")
			continue
		img = load_rgba(path)
		mask = foreground(img)
		img = despill(img, mask)
		cells = grid_assign(components(mask, min_area=150, merge=4), 2, 4)
		for idx, (prop_id, px_h, world_h) in enumerate(layout):
			parts = cells.get((idx // 4, idx % 4))
			if not parts:
				print(f"  WARN {sheet_id}: no sprite in cell {idx}")
				continue
			crop = trim(union_crop(img, parts))
			spr = resize(crop, px_h / crop.shape[0])
			# pad so the trunk / base sits exactly at the horizontal centre (card anchor x = 0.5)
			bx = figure_base_x(spr)
			half = int(np.ceil(max(bx, spr.shape[1] - bx))) + 1
			padded = np.zeros((spr.shape[0], half * 2, 4), np.uint8)
			ox = int(round(half - bx))
			padded[:, ox:ox + spr.shape[1]] = spr
			sprites.append((prop_id, padded, world_h, sheet_id))
	if not sprites:
		return
	# shelf packing into a 2048 wide atlas
	atlas_w = 2048
	x = y = shelf = 0
	placed = []
	for prop_id, spr, world_h, src in sorted(sprites, key=lambda s: -s[1].shape[0]):
		h, w = spr.shape[:2]
		if x + w + 4 > atlas_w:
			x, y, shelf = 0, y + shelf + 4, 0
		placed.append((prop_id, spr, world_h, src, x + 2, y + 2))
		x += w + 4
		shelf = max(shelf, h)
	atlas_h = int(2 ** np.ceil(np.log2(y + shelf + 4)))
	atlas = np.zeros((atlas_h, atlas_w, 4), np.uint8)
	variants: dict = {}
	for prop_id, spr, world_h, src, px, py in placed:
		h, w = spr.shape[:2]
		atlas[py:py + h, px:px + w] = spr
		base_x = figure_base_x(spr)
		variants.setdefault(prop_id, []).append({"rect": [px, py, w, h], "anchor": [round(base_x, 1), h],
			"height_m": world_h, "source": src})
	out = GAME / "assets" / "sprites" / "props_atlas.png"
	save_png(bleed(atlas), out)
	write_table("props", [{"id": k, "texture": res(out), "atlas_size": [atlas_w, atlas_h], "variants": v} for k, v in variants.items()])
	print(f"  atlas {atlas_w}x{atlas_h}, {len(placed)} sprites: " + ", ".join(f"{k}x{len(v)}" for k, v in variants.items()))


def figure_base_x(spr: np.ndarray) -> float:
	"""x of the trunk / base: centre of the lowest 12% of opaque pixels."""
	a = spr[..., 3] > 128
	h = a.shape[0]
	low = a[int(h * 0.88):]
	ys, xs = np.nonzero(low if low.any() else a)
	return float(xs.mean())


# --- terrain textures ----------------------------------------------------------------------

TERRAIN_LAYERS = ["t_grass", "t_meadow", "t_forest", "t_sand", "t_dirt", "t_rock", "t_farmland", "t_paved"]
TEX = 512


def make_seamless(img: np.ndarray) -> np.ndarray:
	"""Variance-preserving blend of the image with its half-offset copy; edges come from the
	offset copy (which wraps continuously), the centre from the original."""
	f = img.astype(np.float32)
	h, w = f.shape[:2]
	off = np.roll(f, (h // 2, w // 2), axis=(0, 1))
	yy, xx = np.mgrid[0:h, 0:w]
	d = np.maximum(np.abs(xx / (w - 1) - 0.5), np.abs(yy / (h - 1) - 0.5)) * 2.0
	m = np.clip((d - 0.55) / 0.4, 0.0, 1.0)
	m = (m * m * (3 - 2 * m))[..., None]
	mean = f.reshape(-1, 3).mean(0)
	blend = mean + (m * (off - mean) + (1 - m) * (f - mean)) / np.sqrt(m * m + (1 - m) ** 2)
	return np.clip(blend, 0, 255).astype(np.uint8)


def process_textures(only: set[str]) -> None:
	layers = []
	entries = []
	for i, tid in enumerate(TERRAIN_LAYERS):
		path = raw_path(tid)
		if path is None:
			print(f"  missing {tid}; terrain array needs all layers")
			return
		img = np.array(Image.open(path).convert("RGB"))
		h, w = img.shape[:2]
		s = min(h, w)
		img = img[(h - s) // 2:(h - s) // 2 + s, (w - s) // 2:(w - s) // 2 + s]
		img = np.array(Image.fromarray(img).resize((TEX, TEX), Image.Resampling.LANCZOS))
		img = make_seamless(img)
		layers.append(img)
		avg = img.reshape(-1, 3).mean(0) / 255.0
		entries.append({"id": tid[2:], "layer": i, "avg_color": [round(float(c), 4) for c in avg]})
	stack = np.concatenate(layers, axis=0)
	out = GAME / "assets" / "textures" / "terrain_array.png"
	out.parent.mkdir(parents=True, exist_ok=True)
	Image.fromarray(stack).save(out, optimize=True)
	write_import(out, "array")
	write_table("terrain", entries)
	print(f"  {len(layers)} layers -> {out.name}")


# --- buildings -----------------------------------------------------------------------------

# raw id -> (building visual id(s), level)
BUILDING_IDS = {
	"b_hearth1": ["hearth@1"], "b_hearth2": ["hearth@2"], "b_hearth3": ["hearth@3"],
	"b_house": ["house@0"], "b_house2": ["house@1"], "b_storehouse": ["storehouse@0"], "b_smelter": ["smelter@0"],
	"b_windmill": ["windmill@0"], "b_workshop": ["workshop@0"], "b_sky_dock": ["sky_dock@0"],
	"b_watchtower": ["watchtower@0"], "b_outpost": ["outpost@0"], "b_construction": ["construction@0"],
	"b_bandit_tent": ["bandit_tent@0"], "b_bandit_hut": ["bandit_hut@0"], "b_bandit_tower": ["bandit_tower@0"],
	"b_campfire": ["campfire@0"], "b_machine_spire": ["machine_spire@0"], "b_machine_block": ["machine_block@0"],
	"b_machine_foundry": ["machine_foundry@0"], "b_trade_hall": ["trade_hall@0"], "b_trade_stall": ["trade_stall@0"],
	"b_trade_mast": ["trade_mast@0"], "b_wanderer_tent": ["wanderer_tent@0"], "b_ruin_arch": ["ruin_arch@0"],
	"b_ruin_pillar": ["ruin_pillar@0"], "b_ruin_wall": ["ruin_wall@0"], "b_ruin_statue": ["ruin_statue@0"],
	"b_ruin_vault": ["ruin_vault@0"], "b_wreck_airship": ["wreck_airship@0"], "props_sails": ["windmill_sails@0"],
}
BUILDING_IDS.update({
	f"b_v_{race}_{kind}": [f"v_{race}_{kind}@0"] for race in RACES for kind in ["home", "hall"]
})
BUILDING_FOOTPRINTS = {f"v_{race}_home": [3, 3] for race in RACES}
BUILDING_FOOTPRINTS.update({f"v_{race}_hall": [5, 5] for race in RACES})
BUILDING_MAX_W = 640


def glow_mask(rgba: np.ndarray) -> np.ndarray:
	"""Warm bright pixels (lit windows, lanterns, fire, furnaces) as an emission mask."""
	rgb = rgba[..., :3].astype(np.float32) / 255.0
	mx = rgb.max(-1)
	mn = rgb.min(-1)
	sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-4), 0)
	r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
	warm = (r >= g) & (g >= b) & (r > 0.86) & (g > 0.58) & (sat > 0.42)
	hot = (r > 0.92) & (g > 0.62) & (b < 0.4)
	m = (warm | hot) & (rgba[..., 3] > 128)
	m = ndimage.binary_opening(m, iterations=1)
	soft = ndimage.gaussian_filter(m.astype(np.float32), 1.2)
	return (np.clip(soft * 1.6, 0, 1) * 255).astype(np.uint8)


def cap_building_glow(glow: np.ndarray) -> np.ndarray:
	"""Keep soft emission masks at or below the documented 512 px cap."""
	h, w = glow.shape
	scale = min(1.0, 512.0 / max(w, h))
	if scale >= 1.0:
		return glow
	size = (max(1, round(w * scale)), max(1, round(h * scale)))
	return np.asarray(Image.fromarray(glow).resize(size, Image.Resampling.LANCZOS))


def base_width(mask: np.ndarray) -> tuple[float, float, float]:
	"""Width and centre of the footprint diamond from the lower silhouette: (width, cx, bottom y)."""
	ys, xs = np.nonzero(mask)
	y_top, y_bot = ys.min(), ys.max()
	h = y_bot - y_top + 1
	lo = mask[int(y_bot - h * 0.45):y_bot + 1]
	rows = [np.nonzero(r)[0] for r in lo if r.any()]
	spans = [(r.min(), r.max()) for r in rows]
	best = max(spans, key=lambda s: s[1] - s[0])
	return float(best[1] - best[0] + 1), float((best[0] + best[1]) / 2), float(y_bot)


# sheets with several separate structures, left to right
BUILDING_SHEETS = {"walls": ["palisade@0", "wall@0"]}
# structures without lights: warm highlights on wood / stone must not glow at night
NO_GLOW = {"palisade", "wall", "ruin_arch", "ruin_pillar", "ruin_wall", "ruin_statue", "construction",
	"trade_mast", "windmill_sails", "wreck_airship", "bandit_tent"}
BACK_VIEW_SOURCES = {
	"b_hearth1_back": "b_hearth1", "b_hearth2_back": "b_hearth2", "b_hearth3_back": "b_hearth3",
	"b_house_back": "b_house", "b_storehouse_back": "b_storehouse",
	"b_smelter_back": "b_smelter", "b_windmill_back": "b_windmill", "b_workshop_back": "b_workshop",
	"b_sky_dock_back": "b_sky_dock", "b_watchtower_back": "b_watchtower", "b_outpost_back": "b_outpost",
	"b_bandit_tent_back": "b_bandit_tent", "b_bandit_hut_back": "b_bandit_hut",
	"b_bandit_tower_back": "b_bandit_tower", "b_machine_spire_back": "b_machine_spire",
	"b_machine_block_back": "b_machine_block", "b_machine_foundry_back": "b_machine_foundry",
	"b_trade_hall_back": "b_trade_hall", "b_trade_stall_back": "b_trade_stall",
	"b_wanderer_tent_back": "b_wanderer_tent", "b_ruin_vault_back": "b_ruin_vault",
}
BACK_VIEW_SOURCES.update({
	f"b_v_{race}_hall_back": f"b_v_{race}_hall" for race in RACES
})
SYMMETRIC_BUILDINGS = {
	"campfire", "construction", "palisade", "wall", "ruin_arch", "ruin_pillar", "ruin_wall",
	"ruin_statue", "trade_mast", "windmill_sails", "wreck_airship",
}
SYMMETRIC_BUILDINGS.update({f"v_{race}_home" for race in RACES})


def process_building_backs(entries: list[dict], only: set[str]) -> None:
	"""Attach opposite-side paintings to their matching front entry, using the front's scale."""
	by_source = {raw_id: targets for raw_id, targets in BUILDING_IDS.items()}
	for back_raw, front_raw in BACK_VIEW_SOURCES.items():
		if only and front_raw not in only:
			continue
		path = raw_path(back_raw)
		if path is None:
			continue
		img = load_rgba(path)
		img = despill(img, foreground(img))
		comps = components(img[..., 3] > 0, min_area=400, merge=3)
		if not comps:
			print(f"  WARN {back_raw}: empty")
			continue
		main = comps[0]
		pad = 24
		keep = [c for c in comps if c["x1"] > main["x0"] - pad and c["x0"] < main["x1"] + pad
			and c["y1"] > main["y0"] - pad and c["y0"] < main["y1"] + pad]
		crop = trim(union_crop(img, keep))
		spr = bleed(resize(crop, min(1.0, BUILDING_MAX_W / crop.shape[1])))
		bw, bcx, bby = base_width(spr[..., 3] > 128)
		targets = by_source[front_raw]
		glow = cap_building_glow(glow_mask(spr))
		bid0, lv0 = targets[0].split("@")
		stem = bid0 if lv0 == "0" else f"{bid0}_{lv0}"
		out = GAME / "assets" / "sprites" / "buildings" / f"{stem}_back.png"
		save_building_png(spr, out)
		match_building_view_import_settings(out, out.with_name(f"{stem}.png"))
		glow_path = None
		if bid0 not in NO_GLOW and glow.max() > 0 and (glow > 128).sum() > 20:
			glow_path = out.with_name(f"{stem}_back_glow.png")
			save_building_png(glow, glow_path)
			match_building_view_import_settings(glow_path, out.with_name(f"{stem}_glow.png"))
		for target in targets:
			bid, lv = target.split("@")
			key = bid if lv == "0" else f"{bid}@{lv}"
			front_key = "house@v1" if front_raw == "b_house2" else key
			entry = next((e for e in entries if e["id"] == front_key), None)
			if entry is None:
				continue
			entry["back_texture"] = res(out)
			entry["back_size_px"] = [int(spr.shape[1]), int(spr.shape[0])]
			entry["back_base_w_px"] = round(bw, 1)
			entry["back_base_cx_px"] = round(bcx, 1)
			entry["back_base_bottom_px"] = round(bby, 1)
			if glow_path is not None:
				entry["back_glow"] = res(glow_path)
		print(f"  {back_raw} -> {targets} {spr.shape[1]}x{spr.shape[0]} base {bw:.0f}px")




def process_buildings(only: set[str]) -> None:
	entries = []
	jobs = []  # (raw id, [targets], cropped RGBA)
	for raw_id, targets in BUILDING_IDS.items():
		if only and raw_id not in only:
			continue
		path = raw_path(raw_id)
		if path is None:
			continue
		img = load_rgba(path)
		mask = foreground(img)
		img = despill(img, mask)
		comps = components(mask, min_area=400, merge=3)
		if not comps:
			print(f"  WARN {raw_id}: empty")
			continue
		# main subject plus everything that touches its (padded) bounding box
		main = comps[0]
		pad = 24
		keep = [c for c in comps if c["x1"] > main["x0"] - pad and c["x0"] < main["x1"] + pad
			and c["y1"] > main["y0"] - pad and c["y0"] < main["y1"] + pad]
		jobs.append((raw_id, targets, trim(union_crop(img, keep))))
	for raw_id, targets in BUILDING_SHEETS.items():
		if only and raw_id not in only:
			continue
		path = raw_path(raw_id)
		if path is None:
			continue
		img = load_rgba(path)
		mask = foreground(img)
		img = despill(img, mask)
		comps = sorted(components(mask, min_area=400, merge=6)[:len(targets)], key=lambda c: c["cx"])
		for c, t in zip(comps, targets):
			jobs.append((raw_id, [t], trim(union_crop(img, [c]))))
	for raw_id, targets, crop in jobs:
		scale = min(1.0, BUILDING_MAX_W / crop.shape[1])
		spr = bleed(resize(crop, scale))
		m = spr[..., 3] > 128
		bw, bcx, bby = base_width(m)
		glow = cap_building_glow(glow_mask(spr))
		bid0, lv0 = targets[0].split("@")
		stem = bid0 if lv0 == "0" else f"{bid0}_{lv0}"
		out = GAME / "assets" / "sprites" / "buildings" / f"{stem}.png"
		save_building_png(spr, out)
		glow_path = None
		if bid0 not in NO_GLOW and glow.max() > 0 and (glow > 128).sum() > 20:
			glow_path = out.with_name(f"{stem}_glow.png")
			save_building_png(glow, glow_path)
		for t in targets:
			bid, lv = t.split("@")
			key = bid if lv == "0" else f"{bid}@{lv}"
			if raw_id == "b_house2":
				key = "house@v1"
			entry = {"id": key, "texture": res(out), "size_px": [int(spr.shape[1]), int(spr.shape[0])],
				"base_w_px": round(bw, 1), "base_cx_px": round(bcx, 1), "base_bottom_px": round(bby, 1), "source": raw_id}
			if key in BUILDING_FOOTPRINTS:
				entry["footprint"] = BUILDING_FOOTPRINTS[key]
			if glow_path is not None:
				entry["glow"] = res(glow_path)
			if bid0 in SYMMETRIC_BUILDINGS:
				entry["back_symmetric"] = True
			entries.append(entry)
		print(f"  {raw_id} -> {targets} {spr.shape[1]}x{spr.shape[0]} base {bw:.0f}px glow {'yes' if glow_path else 'no'}")
	process_building_backs(entries, only)
	for e in entries:
		# Until an opposite-side painting arrives, render the mirrored front rather than a blank card.
		if "back_texture" not in e:
			e["back_symmetric"] = True
			e["back_pending"] = True
	if entries:
		# hand-measured points on the pictures (windmill hub, chimneys, mooring height)
		over_path = pathlib.Path(__file__).with_name("overrides.json")
		over = json.loads(over_path.read_text()) if over_path.exists() else {}
		for e in entries:
			e.update(over.get(e["id"], {}))
		write_table("buildings", entries)


# --- inventory icons -----------------------------------------------------------------------

# sheet -> icon ids in reading order (4 x 3). Item ids are Icons.SHAPES; res_* are resources.
ICON_SHEETS = {
	"icons_a": ["sword", "dagger", "axe", "spear", "bow", "crossbow", "hammer", "mace", "staff", "rifle", "pistol", "wrench"],
	"icons_b": ["pickaxe", "shield", "vest", "coat", "plate", "helmet", "boots", "gloves", "scope", "lantern", "compass", "goggles"],
	"icons_c": ["gear", "servo", "sensor", "core", "plating", "propeller", "envelope", "engine", "orb", "idol", "relic", "amulet"],
	"icons_d": ["ring", "tonic", "ration", "repair_kit", "shard", "ingot", "timber", "pelt", "book", "map", "res_wood", "res_stone"],
	"icons_e": ["res_ore", "res_metal", "res_gold", "res_food", "res_energy", "loot_sack", "loot_chest", "scroll", "bell", "heart", "medal", "tools"],
}
ICON = 128


def process_icons(only: set[str]) -> None:
	icons = []
	for sheet_id, ids in ICON_SHEETS.items():
		path = raw_path(sheet_id)
		if path is None:
			print(f"  skip {sheet_id}: no raw image")
			continue
		img = load_rgba(path)
		mask = foreground(img)
		img = despill(img, mask)
		cells = grid_assign(components(mask, min_area=120, merge=5), 3, 4)
		for idx, icon_id in enumerate(ids):
			parts = cells.get((idx // 4, idx % 4))
			if not parts:
				print(f"  WARN {sheet_id}: no icon in cell {idx} ({icon_id})")
				continue
			crop = trim(union_crop(img, parts))
			fit = (ICON - 8) / max(crop.shape[:2])
			spr = resize(crop, fit)
			cell = np.zeros((ICON, ICON, 4), np.uint8)
			oy = (ICON - spr.shape[0]) // 2
			ox = (ICON - spr.shape[1]) // 2
			cell[oy:oy + spr.shape[0], ox:ox + spr.shape[1]] = spr
			icons.append((icon_id, cell))
	if not icons:
		return
	cols = 8
	rows = (len(icons) + cols - 1) // cols
	atlas = np.zeros((rows * ICON, cols * ICON, 4), np.uint8)
	entries = []
	out = GAME / "assets" / "sprites" / "icons_atlas.png"
	for i, (icon_id, cell) in enumerate(icons):
		x, y = (i % cols) * ICON, (i // cols) * ICON
		atlas[y:y + ICON, x:x + ICON] = cell
		entries.append({"id": icon_id, "texture": res(out), "rect": [x, y, ICON, ICON]})
	save_png(bleed(atlas), out)
	write_table("icons", entries)
	print(f"  {len(entries)} icons -> {out.name}")


def process_keyart(only: set[str]) -> None:
	"""Title screen background: scaled to cover 1920x1080."""
	path = raw_path("keyart_title")
	if path is None:
		return
	img = Image.open(path).convert("RGB")
	scale = max(1920 / img.width, 1080 / img.height)
	img = img.resize((round(img.width * scale), round(img.height * scale)), Image.Resampling.LANCZOS)
	x0 = (img.width - 1920) // 2
	y0 = (img.height - 1080) // 2
	img = img.crop((x0, y0, x0 + 1920, y0 + 1080))
	out = GAME / "assets" / "ui" / "title_keyart.jpg"
	out.parent.mkdir(parents=True, exist_ok=True)
	img.save(out, quality=90)
	write_import(out, "ui")
	print(f"  {out.name} 1920x1080 from {path.name}")


def main() -> None:
	args = sys.argv[1:]
	only: set[str] = set()
	if "--only" in args:
		i = args.index("--only")
		only = set(args[i + 1].split(","))
		del args[i:i + 2]
	what = args[0] if args else "all"
	steps = {"chips": process_chips, "portraits": process_portraits, "props": process_props,
		"textures": process_textures, "buildings": process_buildings, "icons": process_icons, "keyart": process_keyart}
	for name, fn in steps.items():
		if what in ("all", name):
			print(f"[{name}]")
			fn(only)


if __name__ == "__main__":
	main()
