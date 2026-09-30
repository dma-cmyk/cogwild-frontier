#!/usr/bin/env python3
"""Cuts batched generation results back into the per-sheet raws that process.py reads.

art_src/prompts.json lists batch requests (kind "chip_batch" / "portrait_batch") whose `splits` are the
raw ids they contain. A raw batch image `art_src/raw/<batch id>.webp` is split like this:

* chip_batch: one wide image of side-by-side chip sheets, each a 6 x 4 grid (two characters). It is cut
  into equal vertical strips, one per split id.
* portrait_batch: a 3 x 2 grid of busts; column i holds split i's man (top row) and woman (bottom row).
  Each split becomes the usual two-portrait image (man left, woman right).

    python3 tools/art/split_batches.py            # every batch whose raw exists
    python3 tools/art/split_batches.py --only batch_chip_orc_worker,batch_portrait_worker_1
"""
from __future__ import annotations

import json
import pathlib
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
RAW = ROOT / "art_src" / "raw"


def save(img: Image.Image, asset_id: str) -> None:
    # Lossless so the sprite processing sees exactly what the model returned (alpha kept).
    img.save(RAW / f"{asset_id}.webp", lossless=True, quality=100, method=1)
    print(f"  {asset_id}: {img.width}x{img.height}")


def split_chips(img: Image.Image, splits: list[str]) -> None:
    strip = img.width // len(splits)
    for i, asset_id in enumerate(splits):
        save(img.crop((i * strip, 0, (i + 1) * strip if i < len(splits) - 1 else img.width, img.height)), asset_id)


def split_portraits(img: Image.Image, splits: list[str]) -> None:
    img = img.convert("RGB")
    cell_w, cell_h = img.width // 3, img.height // 2  # always a 3 x 2 grid, even when fewer sheets were sent
    side = min(cell_w, cell_h)
    for i, asset_id in enumerate(splits):
        pair = Image.new("RGB", (side * 2, side))
        for row in range(2):
            x0 = i * cell_w + (cell_w - side) // 2
            y0 = row * cell_h  # heads sit at the top of tall cells; process.py trims the chest
            pair.paste(img.crop((x0, y0, x0 + side, y0 + side)), (side * row, 0))
        save(pair, asset_id)


def main() -> None:
    args = sys.argv[1:]
    only: set[str] = set()
    if "--only" in args:
        only = set(args[args.index("--only") + 1].split(","))
    entries = json.loads((ROOT / "art_src" / "prompts.json").read_text())
    for entry in entries:
        kind = entry.get("kind", "")
        if kind not in ("chip_batch", "portrait_batch") or (only and entry["id"] not in only):
            continue
        source = next(iter(sorted(RAW.glob(entry["id"] + ".*"))), None)
        if source is None:
            print(f"  skip {entry['id']}: no raw image")
            continue
        img = Image.open(source)
        print(entry["id"])
        (split_chips if kind == "chip_batch" else split_portraits)(img.convert("RGBA") if kind == "chip_batch" else img, entry["splits"])


if __name__ == "__main__":
    main()
