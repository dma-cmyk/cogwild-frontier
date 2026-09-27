#!/usr/bin/env python3
"""Fetch only Godot's non-threaded Web export template from the official .tpz ZIP."""
from __future__ import annotations

import argparse
import os
import struct
import sys
import tempfile
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

URL = "https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz"
MEMBERS = ("templates/web_nothreads_debug.zip", "templates/web_nothreads_release.zip")
VERSION = "4.7.2.stable"


def request_range(url: str, start: int, end: int) -> bytes:
    req = urllib.request.Request(url, headers={"Range": f"bytes={start}-{end}", "User-Agent": "CogwildFrontier-template-fetcher/1.0"})
    with urllib.request.urlopen(req, timeout=90) as response:
        data = response.read()
        if response.status == 206:
            return data
        if response.status == 200 and start == 0:
            return data
        raise RuntimeError(f"Server ignored HTTP range request ({response.status}); refusing full 1.28 GB download")


def remote_size(url: str) -> int:
    req = urllib.request.Request(url, headers={"Range": "bytes=0-0", "User-Agent": "CogwildFrontier-template-fetcher/1.0"})
    with urllib.request.urlopen(req, timeout=90) as response:
        content_range = response.headers.get("Content-Range", "")
        if response.status != 206 or "/" not in content_range:
            raise RuntimeError("The release host did not provide Content-Range; ranged extraction is required")
        return int(content_range.rsplit("/", 1)[1])


def find_member(url: str, size: int, member: str) -> tuple[int, int, int, int]:
    tail_size = min(size, 65557)
    tail_start = size - tail_size
    tail = request_range(url, tail_start, size - 1)
    eocd = tail.rfind(b"PK\x05\x06")
    if eocd < 0 or eocd + 22 > len(tail):
        raise RuntimeError("ZIP end-of-central-directory record not found")
    _, disk, cd_disk, disk_entries, entries, cd_size, cd_offset, comment_len = struct.unpack_from("<4s4H2IH", tail, eocd)
    if disk or cd_disk or disk_entries != entries or entries == 0xFFFF or cd_offset == 0xFFFFFFFF:
        raise RuntimeError("Multi-disk or ZIP64 archive is not supported by ranged template extraction")
    central = request_range(url, cd_offset, cd_offset + cd_size - 1)
    cursor = 0
    while cursor + 46 <= len(central):
        fields = struct.unpack_from("<4s6H3I5H2I", central, cursor)
        if fields[0] != b"PK\x01\x02":
            raise RuntimeError("Malformed ZIP central directory")
        method = fields[4]
        compressed_size, uncompressed_size = fields[8], fields[9]
        name_len, extra_len, comment_len = fields[10], fields[11], fields[12]
        local_offset = fields[16]
        name_start = cursor + 46
        name = central[name_start:name_start + name_len].decode("utf-8")
        if name == member:
            if compressed_size == 0xFFFFFFFF or local_offset == 0xFFFFFFFF:
                raise RuntimeError("Selected template uses ZIP64; ranged extraction requires ZIP64 support")
            return local_offset, compressed_size, uncompressed_size, method
        cursor = name_start + name_len + extra_len + comment_len
    raise RuntimeError(f"{member} is missing from official templates archive")


def extract(url: str, member: str, dest: Path) -> None:
    size = remote_size(url)
    offset, compressed_size, uncompressed_size, method = find_member(url, size, member)
    local = request_range(url, offset, offset + 29)
    if local[:4] != b"PK\x03\x04":
        raise RuntimeError("Selected template has an invalid local ZIP header")
    name_len, extra_len = struct.unpack_from("<HH", local, 26)
    data_start = offset + 30 + name_len + extra_len
    compressed = request_range(url, data_start, data_start + compressed_size - 1)
    if method == zipfile.ZIP_STORED:
        payload = compressed
    elif method == zipfile.ZIP_DEFLATED:
        import zlib
        payload = zlib.decompress(compressed, -15)
    else:
        raise RuntimeError(f"Unsupported compression method {method} for template member {member}")
    if len(payload) != uncompressed_size:
        raise RuntimeError(f"Template size mismatch: expected {uncompressed_size}, got {len(payload)}")
    dest.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=dest.parent, prefix=".web-template-", delete=False) as tmp:
        tmp.write(payload)
        temp_path = Path(tmp.name)
    os.replace(temp_path, dest)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default=URL)
    parser.add_argument("--godot-version", default=VERSION)
    parser.add_argument("--templates-dir", type=Path, default=Path.home() / ".local/share/godot/export_templates")
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    template_dir = args.templates_dir / args.godot_version
    missing = [(member, template_dir / Path(member).name) for member in MEMBERS
        if args.force or not (template_dir / Path(member).name).is_file()]
    if not missing:
        print(f"Web export templates already installed: {', '.join(str(template_dir / Path(member).name) for member in MEMBERS)}")
        return 0
    try:
        for member, dest in missing:
            extract(args.url, member, dest)
            print(f"Installed {member} to {dest} ({dest.stat().st_size:,} bytes)")
    except (OSError, urllib.error.URLError, RuntimeError, ValueError) as exc:
        print(f"Template download failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
