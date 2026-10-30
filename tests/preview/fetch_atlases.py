#!/usr/bin/env -S uv run --with pillow
"""tests/preview/fetch_atlases.py

Fetches real Forever ("Camelot") Blizzard chrome art so the out-of-game
preview renderer (record.lua) can draw it, without ever committing Blizzard
art to the repo.

What it does:
  1. Scans SideQuest/**/*.lua for every atlas element name the addon
     actually references (SetAtlas("Name", ...) calls and NineSlice
     layout-table `atlas = "Name"` fields), plus any names passed with
     --name on the command line.
  2. Downloads (and caches) the three UiTextureAtlas* DB2 tables for a
     fixed Forever build from wago.tools, to resolve each element name to
     a specific texture-sheet crop.
  3. For every needed element, prefers the Camelot member (the atlas whose
     UiTextureAtlasSetID == 1, i.e. the "-c60" art) over the Mainline one,
     and within that set prefers the "-2x" member for crispness while
     reporting the *logical* (1x) width/height SetAtlas callers expect.
  4. Downloads (and caches) only the BLP sprite sheets actually needed,
     decodes them to PNG (BLP2 encoding 3 is raw BGRA and isn't supported
     by Pillow, so that one encoding is hand-decoded; everything else goes
     through Pillow's native BLP reader), and writes an index.json the
     Lua stub/renderer can read to crop/scale/tile the right region.

Run: `uv run --with pillow tests/preview/fetch_atlases.py` from the addon
repo root (or anywhere; paths are resolved relative to this file).

Everything this script writes lives under tests/preview/.atlas-cache/,
which is gitignored -- Blizzard-extracted art must never be committed.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import struct
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path

BUILD = "1.60.1.69913"
WAGO_DB2 = "https://wago.tools/db2/{table}/csv?build={build}"
WAGO_CASC = "https://wago.tools/api/casc/{fdid}?download"

HERE = Path(__file__).resolve().parent
ADDON_ROOT = HERE.parent.parent
CACHE_DIR = HERE / ".atlas-cache"
CSV_DIR = CACHE_DIR / "csv"
BLP_DIR = CACHE_DIR / "blp"
PNG_DIR = CACHE_DIR / "png"
ELEMENTS_DIR = CACHE_DIR / "elements"
INDEX_PATH = CACHE_DIR / "index.json"
VALID_NAMES_PATH = CACHE_DIR / "valid_names.txt"

TABLES = {
    "UiTextureAtlasElement": CSV_DIR / "uitae.csv",
    "UiTextureAtlasMember": CSV_DIR / "uitam.csv",
    "UiTextureAtlas": CSV_DIR / "uita.csv",
}

ATLAS_NAME_PATTERNS = [
    re.compile(r'SetAtlas\(\s*["\']([^"\']+)["\']'),
    re.compile(r'atlas\s*=\s*["\']([^"\']+)["\']'),
]
# Atlas names also live in data tables and helper arguments (news icons, the
# tab template's pieces). Every other string literal is a candidate and is kept
# only if it is exactly a real element name.
STRING_LITERAL = re.compile(r'"([A-Za-z0-9_!][A-Za-z0-9_\-!]{3,})"')


def log(msg: str) -> None:
    print(f"[fetch_atlases] {msg}", file=sys.stderr)


# --------------------------------------------------------------------------
# 1. Scan the addon source for atlas element names actually used.
# --------------------------------------------------------------------------


def scan_used_names(extra: list[str]) -> tuple[set[str], set[str]]:
    """Returns (explicit atlas names, other string literals that may be atlas names)."""
    names: set[str] = set(extra)
    candidates: set[str] = set()
    sources = list(ADDON_ROOT.glob("SideQuest/**/*.lua"))
    # wowstub.lua itself references atlas names for template-synthesized
    # chrome the addon never writes a literal SetAtlas() call for (e.g.
    # the UIPanelCloseButton template's RedButton-Exit icon).
    sources.append(ADDON_ROOT / "tests" / "wowstub.lua")
    for path in sources:
        text = path.read_text(encoding="utf-8", errors="replace")
        for pattern in ATLAS_NAME_PATTERNS:
            for m in pattern.finditer(text):
                names.add(m.group(1))
        candidates.update(m.group(1) for m in STRING_LITERAL.finditer(text))
    return names, candidates - names


# --------------------------------------------------------------------------
# 2. Download + cache the DB2 CSV extracts.
# --------------------------------------------------------------------------


def download(url: str, dest: Path, what: str) -> bool:
    if dest.exists() and dest.stat().st_size > 0:
        return True
    dest.parent.mkdir(parents=True, exist_ok=True)
    log(f"fetching {what} -> {dest.relative_to(CACHE_DIR)}")
    req = urllib.request.Request(url, headers={"User-Agent": "sidequest-addon-preview/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = resp.read()
    except urllib.error.HTTPError as e:
        log(f"  FAILED ({e.code}): {url}")
        return False
    except urllib.error.URLError as e:
        log(f"  FAILED ({e.reason}): {url}")
        return False
    tmp = dest.with_suffix(dest.suffix + ".part")
    tmp.write_bytes(data)
    tmp.rename(dest)
    return True


def ensure_csvs() -> bool:
    ok = True
    for table, dest in TABLES.items():
        url = WAGO_DB2.format(table=table, build=BUILD)
        ok = download(url, dest, f"{table}.csv") and ok
    return ok


def load_csv(path: Path) -> list[dict]:
    with path.open(newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


# --------------------------------------------------------------------------
# 3. Resolve each needed element name to a specific atlas-sheet crop.
# --------------------------------------------------------------------------


def build_indices(elements: list[dict], members: list[dict], atlases: list[dict]):
    by_name: dict[str, str] = {}
    by_name_ci: dict[str, str] = {}
    for row in elements:
        by_name[row["Name"]] = row["ID"]
        by_name_ci.setdefault(row["Name"].lower(), row["ID"])

    members_by_element: dict[str, list[dict]] = {}
    for row in members:
        members_by_element.setdefault(row["UiTextureAtlasElementID"], []).append(row)

    atlas_by_id: dict[str, dict] = {row["ID"]: row for row in atlases}

    return by_name, by_name_ci, members_by_element, atlas_by_id


def resolve_element(name, by_name, by_name_ci, members_by_element, atlas_by_id):
    eid = by_name.get(name)
    exact = eid is not None
    if eid is None:
        eid = by_name_ci.get(name.lower())
    if eid is None:
        return None, "not-found"

    cands = members_by_element.get(eid, [])
    if not cands:
        return None, "no-members"

    def set_id_of(m):
        atlas = atlas_by_id.get(m["UiTextureAtlasID"])
        return atlas["UiTextureAtlasSetID"] if atlas else None

    camelot = [m for m in cands if set_id_of(m) == "1"]
    group = camelot if camelot else cands
    set_id = "1" if camelot else (set_id_of(group[0]) if group else None)

    twox = [m for m in group if m["CommittedName"].lower().endswith("-2x")]
    pool = twox if twox else group
    chosen = max(pool, key=lambda m: int(m["Width"]) * int(m["Height"]))
    is2x = chosen["CommittedName"].lower().endswith("-2x")

    atlas = atlas_by_id.get(chosen["UiTextureAtlasID"])
    if atlas is None:
        return None, "missing-atlas-row"

    raw_w, raw_h = int(chosen["Width"]), int(chosen["Height"])
    ow, oh = int(chosen["OverrideWidth"]), int(chosen["OverrideHeight"])
    logical_w = (ow or raw_w)
    logical_h = (oh or raw_h)
    if is2x:
        logical_w /= 2
        logical_h /= 2

    info = {
        "fileDataID": int(atlas["FileDataID"]),
        "imageWidth": int(atlas["AtlasWidth"]),
        "imageHeight": int(atlas["AtlasHeight"]),
        "left": int(chosen["CommittedLeft"]),
        "right": int(chosen["CommittedRight"]),
        "top": int(chosen["CommittedTop"]),
        "bottom": int(chosen["CommittedBottom"]),
        "width": logical_w,
        "height": logical_h,
        "tilesHorizontally": name.startswith("_"),
        "tilesVertically": name.startswith("!"),
        "setID": set_id,
        "memberName": chosen["CommittedName"],
    }
    return info, ("ok" if exact else "ok-case-insensitive")


# --------------------------------------------------------------------------
# 4. Download + decode only the BLP sheets actually referenced.
# --------------------------------------------------------------------------


def decode_blp(path: Path) -> "tuple[bytes, int, int] | None":
    """Returns (RGBA bytes, width, height) or None on failure.

    BLP2 encoding 3 is raw BGRA mip data, which Pillow's BlpImagePlugin
    does not support; every other encoding (palette, DXT1/3/5) is handed
    to Pillow directly.
    """
    data = path.read_bytes()
    if data[:4] != b"BLP2":
        return None
    encoding = data[8]
    width, height = struct.unpack_from("<II", data, 12)
    if encoding != 3:
        from PIL import Image

        im = Image.open(path).convert("RGBA")
        return im.tobytes(), im.width, im.height
    offset = struct.unpack_from("<I", data, 20)[0]
    bgra = data[offset : offset + width * height * 4]
    # BGRA -> RGBA
    rgba = bytearray(len(bgra))
    rgba[0::4] = bgra[2::4]
    rgba[1::4] = bgra[1::4]
    rgba[2::4] = bgra[0::4]
    rgba[3::4] = bgra[3::4]
    return bytes(rgba), width, height


def fetch_and_decode(fdid: int) -> bool:
    png_path = PNG_DIR / f"{fdid}.png"
    if png_path.exists():
        return True
    blp_path = BLP_DIR / f"{fdid}.blp"
    if not download(WAGO_CASC.format(fdid=fdid), blp_path, f"FileDataID {fdid}"):
        return False
    decoded = decode_blp(blp_path)
    if decoded is None:
        log(f"  could not decode {blp_path.name} (not a recognized BLP)")
        return False
    from PIL import Image

    rgba, w, h = decoded
    PNG_DIR.mkdir(parents=True, exist_ok=True)
    Image.frombytes("RGBA", (w, h), rgba, "raw", "RGBA").save(png_path)
    return True


def crop_element(info: dict) -> str | None:
    """Crops one element's region out of its already-decoded sheet PNG and
    saves it as its own small PNG, so the Lua renderer can draw/tile it
    directly instead of doing texcoord math against a shared sprite sheet
    (which CSS has no native way to tile a sub-rect of). Filename is keyed
    by (fileDataID, crop bounds), so elements that share a crop (aliases)
    or atlas (neighbors) naturally dedupe.
    """
    sheet_path = PNG_DIR / f"{info['fileDataID']}.png"
    if not sheet_path.exists():
        return None
    left, top, right, bottom = info["left"], info["top"], info["right"], info["bottom"]
    name = f"{info['fileDataID']}-{left}-{top}-{right}-{bottom}.png"
    dest = ELEMENTS_DIR / name
    if not dest.exists():
        from PIL import Image

        ELEMENTS_DIR.mkdir(parents=True, exist_ok=True)
        with Image.open(sheet_path) as sheet:
            sheet.crop((left, top, right, bottom)).save(dest)
    return f"elements/{name}"



# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------


def main() -> int:
    global BUILD
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--name", action="append", default=[], help="extra atlas element name to fetch")
    ap.add_argument("--build", default=BUILD, help=f"Forever build to fetch DB2 tables for (default {BUILD})")
    args = ap.parse_args()

    BUILD = args.build

    CACHE_DIR.mkdir(parents=True, exist_ok=True)

    needed, candidates = scan_used_names(args.name)
    log(f"{len(needed)} atlas element name(s) referenced by the addon source" + (f" + --name" if args.name else ""))
    if not needed:
        log("nothing to fetch")
        INDEX_PATH.write_text(json.dumps({"build": BUILD, "elements": {}}, indent=2))
        return 0

    if not ensure_csvs():
        log("could not fetch one or more DB2 CSV tables; aborting")
        return 1

    elements = load_csv(TABLES["UiTextureAtlasElement"])
    members = load_csv(TABLES["UiTextureAtlasMember"])
    atlases = load_csv(TABLES["UiTextureAtlas"])
    by_name, by_name_ci, members_by_element, atlas_by_id = build_indices(elements, members, atlases)

    # valid_names.txt: every real atlas element name, for record.lua to
    # tell "not fetched yet" (present here, missing from index) apart from
    # "not a real atlas name" (missing from here -- an addon-side typo).
    VALID_NAMES_PATH.write_text("\n".join(sorted(by_name.keys())) + "\n")
    needed |= {c for c in candidates if c in by_name}

    index: dict[str, dict] = {}
    unresolved: list[str] = []
    fdids_needed: set[int] = set()
    for name in sorted(needed):
        info, status = resolve_element(name, by_name, by_name_ci, members_by_element, atlas_by_id)
        if info is None:
            unresolved.append(f"{name} ({status})")
            continue
        if status == "ok-case-insensitive":
            log(f"'{name}' matched case-insensitively (check addon call site capitalization)")
        index[name] = info
        fdids_needed.add(info["fileDataID"])

    log(f"resolved {len(index)}/{len(needed)} names, {len(fdids_needed)} distinct texture sheet(s) to fetch")
    if unresolved:
        log("UNRESOLVED (not in UiTextureAtlasElement -- likely a typo in the addon):")
        for u in unresolved:
            log(f"  - {u}")

    fetched = 0
    for fdid in sorted(fdids_needed):
        if fetch_and_decode(fdid):
            fetched += 1
    log(f"{fetched}/{len(fdids_needed)} texture sheet(s) available as PNG")

    cropped = 0
    for name, info in index.items():
        info["png"] = f"png/{info['fileDataID']}.png"
        elementPng = crop_element(info)
        if elementPng:
            info["elementPng"] = elementPng
            cropped += 1
    log(f"{cropped}/{len(index)} element crop(s) saved")

    INDEX_PATH.write_text(json.dumps(
        {"build": BUILD, "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "elements": index},
        indent=2,
    ))
    log(f"wrote {INDEX_PATH.relative_to(ADDON_ROOT)}")

    if fetched < len(fdids_needed):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
