#!/usr/bin/env python3
"""Apply web-friendly image compression presets to Godot texture import sidecars."""
from __future__ import annotations

import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / "game"


# Painted sprites and portraits use Basis Universal (UASTC): one download for every browser, then
# transcoded at load time to the GPU's own format (BC7 on desktops, ASTC / ETC2 on phones), so
# textures stay compressed in video memory. Two VRAM variants (desktop + mobile) would double the
# download. Building pictures are painted far above their on-screen size, even at the closest
# zoom, so they are capped at 768 px.
BASIS, LOSSLESS = 4, 0
PRESETS = {
    "sprites/buildings/": {"compress/mode": BASIS, "mipmaps/generate": True, "process/size_limit": 768},
    "sprites/": {"compress/mode": BASIS, "mipmaps/generate": True, "process/size_limit": 0},
    "portraits/": {"compress/mode": BASIS, "mipmaps/generate": True, "process/size_limit": 0},
    "ui/": {"compress/mode": LOSSLESS, "mipmaps/generate": False, "process/size_limit": 0},
    "icons/": {"compress/mode": LOSSLESS, "mipmaps/generate": False, "process/size_limit": 0},
}


def preset_for(path: Path) -> dict | None:
    rel = path.relative_to(GAME / "assets").as_posix()
    for prefix, preset in PRESETS.items():
        if rel.startswith(prefix):
            return preset
    return None


def apply(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    if "[params]" not in text or 'importer="texture"' not in text:
        return False
    preset = preset_for(path)
    if preset is None:
        return False
    values = {
        "compress/mode": str(preset["compress/mode"]),
        "compress/uastc_level": "0",
        "compress/rdo_quality_loss": "1.0",
        "mipmaps/generate": "true" if preset["mipmaps/generate"] else "false",
        "mipmaps/limit": "-1",
        "process/size_limit": str(preset["process/size_limit"]),
    }
    before = text
    for key, value in values.items():
        pattern = re.compile(rf"(?m)^{re.escape(key)}=.*$")
        if pattern.search(text):
            text = pattern.sub(f"{key}={value}", text, count=1)
        else:
            params = re.search(r"(?m)^\[params\]\s*$", text)
            if params is None:
                continue
            text = text[:params.end()] + "\n\n" + f"{key}={value}" + text[params.end():]
    if text != before:
        path.write_text(text, encoding="utf-8")
        return True
    return False


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", type=Path, default=GAME)
    args = parser.parse_args()
    count = 0
    for sidecar in sorted((args.game / "assets").rglob("*.import")):
        if apply(sidecar):
            count += 1
    print(f"Updated web texture presets in {count} import sidecars; rerun Godot --import afterward.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
