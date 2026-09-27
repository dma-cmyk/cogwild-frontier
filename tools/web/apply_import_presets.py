#!/usr/bin/env python3
"""Apply web-friendly image compression presets to Godot texture import sidecars."""
from __future__ import annotations

import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / "game"


# Character sheets use the original VRAM-compressed web payload; portrait source PNGs are generated at 128px.
BASIS, LOSSY, LOSSLESS = 4, 1, 0
PRESETS = {
    "ui/title_keyart.jpg": {"compress/mode": LOSSY, "compress/lossy_quality": "0.9", "mipmaps/generate": False, "process/size_limit": 0},
    "portraits/": {"compress/mode": LOSSY, "compress/high_quality": "false", "compress/lossy_quality": "0.9", "compress/rdo_quality_loss": "1.0", "mipmaps/generate": True, "process/size_limit": 0},
    "sprites/chars/": {"compress/mode": LOSSY, "compress/high_quality": "false", "compress/lossy_quality": "0.85", "compress/rdo_quality_loss": "1.0", "mipmaps/generate": True, "process/size_limit": 0},
    "sprites/buildings/": {"compress/mode": BASIS, "mipmaps/generate": True, "process/size_limit": 768},
    "sprites/": {"compress/mode": BASIS, "compress/rdo_quality_loss": 1.5, "mipmaps/generate": True, "process/size_limit": 0},
    "ui/": {"compress/mode": LOSSLESS, "mipmaps/generate": False, "process/size_limit": 0},
    "icons/": {"compress/mode": LOSSLESS, "mipmaps/generate": False, "process/size_limit": 0},
}
GLOW_PRESET = {"compress/mode": BASIS, "mipmaps/generate": True, "process/size_limit": 512}


def preset_for(path: Path) -> dict | None:
    rel = path.relative_to(GAME / "assets").as_posix()
    if rel.startswith("sprites/buildings/") and rel.endswith("_glow.png.import"):
        return GLOW_PRESET
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
        "compress/rdo_quality_loss": str(preset.get("compress/rdo_quality_loss", 1.0)),
        "mipmaps/generate": "true" if preset["mipmaps/generate"] else "false",
        "mipmaps/limit": "-1",
        "process/size_limit": str(preset["process/size_limit"]),
    }
    if "compress/high_quality" in preset:
        values["compress/high_quality"] = str(preset["compress/high_quality"])
    if "compress/lossy_quality" in preset:
        values["compress/lossy_quality"] = str(preset["compress/lossy_quality"])
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
