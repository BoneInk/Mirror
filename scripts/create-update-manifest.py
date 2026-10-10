#!/usr/bin/env python3
"""Generate release update metadata from the exact packages being uploaded."""
import argparse
import hashlib
import json
from pathlib import Path
import re

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--tag", required=True)
parser.add_argument("--output-dir", type=Path, default=Path("dist"))
parser.add_argument("installers", type=Path, nargs="+")
args = parser.parse_args()
if not re.fullmatch(r"v\d+\.\d+\.\d+", args.tag):
    parser.error("Use a stable vX.Y.Z tag")
version = args.tag[1:]
required = {f"Mirror-{version}.dmg", f"Mirror-{version}-windows-x64-setup.exe", f"Mirror-{version}-windows-x64-portable.exe"}
assets = []
for file in args.installers:
    if file.name not in required or not file.is_file() or file.stat().st_size == 0:
        parser.error(f"Unexpected or missing release installer: {file}")
    digest = hashlib.sha256()
    with file.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    assets.append({"name": file.name, "size": file.stat().st_size, "state": "uploaded", "digest": "sha256:" + digest.hexdigest(),
                   "browser_download_url": f"https://github.com/BoneInk/Mirror/releases/download/{args.tag}/{file.name}"})
if {asset["name"] for asset in assets} != required or len(assets) != len(required):
    parser.error("Include the macOS DMG and both Windows x64 packages exactly once")
args.output_dir.mkdir(parents=True, exist_ok=True)
(args.output_dir / "Mirror-update.json").write_text(json.dumps({"tag_name": args.tag, "draft": False, "prerelease": False, "assets": assets}, indent=2) + "\n")
(args.output_dir / "SHA256SUMS.txt").write_text("".join(f'{asset["digest"][7:]}  {asset["name"]}\n' for asset in assets))
print(f"Generated update manifest and checksums in {args.output_dir}")
