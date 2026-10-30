"""Finds SideQuest.lua SavedVariables files under a WoW installation, and
extracts the last SQX1:... export token from one.
"""

from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path

# Flavor folders (e.g. "_classic_", "_retail_") vary by client; Forever's
# live flavor folder name is not yet known, so we glob every "_*_" directory
# rather than hardcoding one.
SAVEDVARIABLES_GLOB = "_*_/WTF/Account/*/SavedVariables/SideQuest.lua"

EXPORT_RE = re.compile(r"SQX1:[A-Za-z0-9+/=]+")

MACOS_DEFAULT = Path("/Applications/World of Warcraft")
WINDOWS_DEFAULTS = [
    Path(r"C:\Program Files (x86)\World of Warcraft"),
    Path(r"C:\Program Files\World of Warcraft"),
]


def default_wow_dir() -> Path | None:
    """Best-effort auto-detection of the WoW install root for this OS."""
    if sys.platform == "darwin":
        return MACOS_DEFAULT if MACOS_DEFAULT.exists() else None
    if sys.platform.startswith("win"):
        for candidate in WINDOWS_DEFAULTS:
            if candidate.exists():
                return candidate
        return None
    return None


def find_savedvariables_files(wow_dir: Path) -> list[Path]:
    """Return every SideQuest.lua SavedVariables file under `wow_dir`."""
    if not wow_dir.exists():
        return []
    return sorted(wow_dir.glob(SAVEDVARIABLES_GLOB))


def extract_export(text: str) -> str | None:
    """Return the *last* SQX1:... token in `text`, or None."""
    matches = EXPORT_RE.findall(text)
    return matches[-1] if matches else None


def extract_export_from_file(path: Path) -> str | None:
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    return extract_export(text)


def payload_hash(payload: str) -> str:
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()
