#!/usr/bin/env python3
"""Version the optional art pack and teach the generated service worker about it.

Godot writes ``build/web/web-extra.pck``; this renames it to ``web-extra-<hash>.pck``, writes the
little manifest ``WebArt`` reads at runtime, adds both to the service worker's cache list and
replaces the worker's timestamp cache version with a content hash (so a rebuild that changes
nothing does not force every visitor to re-download).
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build" / "web"
MANIFEST = "web-extra.json"


def _digest(paths: list[Path]) -> str:
    digest = hashlib.sha256()
    for path in paths:
        digest.update(path.name.encode("utf-8"))
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1 << 20), b""):
                digest.update(chunk)
    return digest.hexdigest()


def gzip_size(path: Path) -> int:
    compressor = zlib.compressobj(level=9, wbits=zlib.MAX_WBITS | 16)
    size = 0
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1 << 20), b""):
            size += len(compressor.compress(chunk))
    return size + len(compressor.flush())


def require_one(pattern: str) -> Path:
    found = sorted(BUILD.glob(pattern))
    if len(found) != 1:
        raise RuntimeError(f"expected exactly one {pattern} in {BUILD}, found {len(found)}")
    return found[0]


def patch_service_worker(pack_name: str, cache_version: str) -> None:
    worker = require_one("*.service.worker.js")
    text = worker.read_text(encoding="utf-8")
    text, cacheable = re.subn(
        r"const CACHEABLE_FILES = (\[.*?\]);",
        lambda m: "const CACHEABLE_FILES = %s;"
        % json.dumps(json.loads(m.group(1)) + [MANIFEST, pack_name], separators=(",", ":")),
        text,
        count=1,
    )
    text, versioned = re.subn(
        r"const CACHE_VERSION = (['\"]).*?\1;",
        f"const CACHE_VERSION = {json.dumps(cache_version)};",
        text,
        count=1,
    )
    # Optional files must never make navigation depend on the network: Godot's generated worker
    # checks FULL_CACHE on every HTML request, including files not yet downloaded on first play.
    # Only the core's install-time cache is required to open the game offline.
    text, navigation = re.subn(
        r"const fullCache = await Promise\.all\(FULL_CACHE\.map\(",
        "const fullCache = await Promise.all(CACHED_FILES.map(",
        text,
        count=1,
    )
    if navigation != 1:
        raise RuntimeError(f"could not patch the optional-cache navigation gate in {worker.name}")
    if cacheable != 1 or versioned != 1:
        raise RuntimeError(f"could not patch the generated service worker {worker.name}")
    worker.write_text(text, encoding="utf-8")


def main() -> int:
    pack = BUILD / "web-extra.pck"
    if not pack.is_file() or pack.stat().st_size == 0:
        raise RuntimeError(f"Godot did not write a non-empty optional pack: {pack}")
    version = _digest([pack])[:16]
    pack_name = f"web-extra-{version}.pck"
    versioned_pack = BUILD / pack_name
    pack.replace(versioned_pack)
    (BUILD / MANIFEST).write_text(
        json.dumps(
            {"version": version, "file": pack_name, "bytes": versioned_pack.stat().st_size},
            separators=(",", ":"),
        )
        + "\n",
        encoding="utf-8",
    )

    core_pck = BUILD / "index.pck"
    wasm = require_one("*.wasm")
    patch_service_worker(pack_name, _digest([core_pck, wasm, versioned_pack])[:16])

    core = [core_pck, wasm] + sorted(p for p in BUILD.glob("*.js") if "worker" not in p.name)
    core_gzip = sum(gzip_size(path) for path in core)
    for path in core + [versioned_pack]:
        print(f"  {path.name}: {path.stat().st_size / 1e6:.2f} MB, gzip {gzip_size(path) / 1e6:.2f} MB")
    print(f"Core transfer (gzip): {core_gzip / 1e6:.2f} MB")
    print(f"Optional pack (gzip): {gzip_size(versioned_pack) / 1e6:.2f} MB, fetched after the title screen")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # make CI failures actionable
        print(f"Web export postprocessing failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
