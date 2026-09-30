#!/usr/bin/env python3
"""Single source of truth for how the Web build is split into two packs.

The browser downloads the core pack before the engine starts, so it holds every playable race's base
art (including races added later), UI, fonts, audio, terrain, props and the buildings the player can
construct. Optional art is limited to additional looks, painted back views, race villages and buildings
that only stand at world sites; ``WebArt`` fetches it in the background (see src/core/web_extra_pack.gd).

Classification is by path pattern, not by a file list, so art merged later lands in the right pack
on its own. Running this script rewrites the two filter fields in game/export_presets.cfg, which is
what ``tools/web/build_web.sh`` does before exporting; the result is committed so the two stay in
sync.

"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PRESETS = ROOT / "game" / "export_presets.cfg"

## Buildings that only ever stand at a world site (including the town, `t_*`), never in the player's colony.
SITE_BUILDINGS = ("bandit", "machine", "ruin", "trade", "wanderer", "wreck", "t")
## The later peoples' extra third/fourth paintings are optional art (the founding peoples' third look stays in the core pack).
LATER_PEOPLES = ("minotaur", "centaur", "harpy", "lamia", "oni", "tengu", "goblin", "orc", "kobold",
                 "lizardfolk", "gnome", "halfling", "android")

EXTRA_PATTERNS: list[str] = [
    "assets/sprites/chars/*_v4.png",
    "assets/sprites/chars/*_v5.png",
    "assets/portraits/*_v4.png",
    "assets/portraits/*_v5.png",
    "assets/sprites/buildings/*_back.png",
    "assets/sprites/buildings/*_back_glow.png",
    "assets/sprites/buildings/v_*.png",
] + [f"assets/sprites/buildings/{site}_*.png" for site in SITE_BUILDINGS] + [
    f"assets/{folder}/{race}_*_v3.png" for race in LATER_PEOPLES for folder in ("sprites/chars", "portraits")
]

## Kept out of both packs.
BASE_EXCLUDE = ["tests/*", "tools/*", "docs/*", "*.md"]

CORE_PRESET = "Web"
EXTRA_PRESET = "WebExtra"


def is_extra(res_path: str) -> bool:
    """Whether res://<res_path> belongs in the optional pack (mirrors Godot's export filters)."""
    from fnmatch import fnmatchcase

    return any(fnmatchcase(res_path, pattern) for pattern in EXTRA_PATTERNS)


def _preset_blocks(text: str) -> dict[str, tuple[int, int]]:
    """Line ranges of every ``[preset.N]`` header block, keyed by its ``name=`` value."""
    lines = text.splitlines()
    blocks: dict[str, tuple[int, int]] = {}
    start: int | None = None
    name = ""
    for index, line in enumerate(lines + ["[preset.end]"]):
        if re.fullmatch(r"\[preset\.\d+\]|\[preset\.end\]", line.strip()):
            if start is not None and name:
                blocks[name] = (start, index)
            start, name = index, ""
        elif start is not None and not name:
            match = re.fullmatch(r'name="(.*)"', line.strip())
            if match:
                name = match.group(1)
    return blocks


def _set_key(lines: list[str], span: tuple[int, int], key: str, value: str) -> None:
    for index in range(*span):
        if lines[index].startswith(key + "="):
            lines[index] = f'{key}="{value}"'
            return
    raise RuntimeError(f"{key} not found in export preset block {span}")


def main() -> int:
    text = PRESETS.read_text(encoding="utf-8")
    lines = text.splitlines()
    blocks = _preset_blocks(text)
    for preset in (CORE_PRESET, EXTRA_PRESET):
        if preset not in blocks:
            raise RuntimeError(f"export preset {preset!r} is missing from {PRESETS}")
    extra = ",".join(EXTRA_PATTERNS)
    _set_key(lines, blocks[CORE_PRESET], "exclude_filter", ",".join(BASE_EXCLUDE) + "," + extra)
    _set_key(lines, blocks[EXTRA_PRESET], "include_filter", extra)
    _set_key(lines, blocks[EXTRA_PRESET], "exclude_filter", ",".join(BASE_EXCLUDE))
    updated = "\n".join(lines) + "\n"
    if updated != text:
        PRESETS.write_text(updated, encoding="utf-8")
        print(f"Updated pack filters in {PRESETS.relative_to(ROOT)}")
    matched = sum(
        1 for path in (ROOT / "game" / "assets").rglob("*.png") if is_extra(str(path.relative_to(ROOT / "game")))
    )
    print(f"Optional pack: {len(EXTRA_PATTERNS)} patterns, {matched} source images")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"Pack split failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
