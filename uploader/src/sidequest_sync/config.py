"""Config and state storage for sidequest-sync.

Stores the site URL and sync token in the user's config directory, and a
small state file tracking which export payloads have already been uploaded
(by sha256) so re-running `once`/`watch` does not re-upload unchanged data.
"""

from __future__ import annotations

import json
import os
import stat
import sys
from dataclasses import dataclass, field
from pathlib import Path

APP_NAME = "sidequest-sync"
DEFAULT_SITE_URL = "https://sidequest-guild.com"


def config_dir() -> Path:
    """Return the per-OS user config directory for this app, creating it."""
    if sys.platform == "darwin":
        base = Path.home() / "Library" / "Application Support"
    elif sys.platform.startswith("win"):
        base = Path(os.environ.get("APPDATA", Path.home() / "AppData" / "Roaming"))
    else:
        base = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    directory = base / APP_NAME
    directory.mkdir(parents=True, exist_ok=True)
    return directory


def config_path() -> Path:
    return config_dir() / "config.json"


def state_path() -> Path:
    return config_dir() / "state.json"


@dataclass
class Config:
    site_url: str = DEFAULT_SITE_URL
    token: str | None = None

    @classmethod
    def load(cls) -> "Config":
        path = config_path()
        if not path.exists():
            return cls()
        data = json.loads(path.read_text(encoding="utf-8"))
        return cls(site_url=data.get("site_url", DEFAULT_SITE_URL), token=data.get("token"))

    def save(self) -> None:
        path = config_path()
        payload = json.dumps({"site_url": self.site_url, "token": self.token}, indent=2)
        # Create the file as 0600 so the token is never readable by other users, even briefly. O_CREAT keeps an
        # existing file's mode, so tighten that too. Windows ignores the mode; the file sits in the user's own %APPDATA%.
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, stat.S_IRUSR | stat.S_IWUSR)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            if os.name != "nt":
                os.fchmod(f.fileno(), stat.S_IRUSR | stat.S_IWUSR)
            f.write(payload)


@dataclass
class State:
    uploaded_hashes: dict[str, str] = field(default_factory=dict)  # sha256 -> uploaded-at ISO time
    last_file: str | None = None
    last_upload_at: str | None = None

    @classmethod
    def load(cls) -> "State":
        path = state_path()
        if not path.exists():
            return cls()
        data = json.loads(path.read_text(encoding="utf-8"))
        return cls(
            uploaded_hashes=data.get("uploaded_hashes", {}),
            last_file=data.get("last_file"),
            last_upload_at=data.get("last_upload_at"),
        )

    def save(self) -> None:
        path = state_path()
        path.write_text(
            json.dumps(
                {
                    "uploaded_hashes": self.uploaded_hashes,
                    "last_file": self.last_file,
                    "last_upload_at": self.last_upload_at,
                },
                indent=2,
            ),
            encoding="utf-8",
        )
