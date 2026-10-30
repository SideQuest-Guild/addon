"""Uploads an export payload to the site's /api/epgp/imports endpoint."""

from __future__ import annotations

import json
import urllib.error
import urllib.request
from dataclasses import dataclass, field


class UploadError(Exception):
    """Raised with a human-readable message for any upload failure."""


@dataclass
class UploadResult:
    recorder: str
    sessions: dict
    encounters: dict
    loot: dict
    awards: dict
    unlinked_characters: list[str]
    attendance: dict | None
    roster: dict = field(default_factory=dict)
    professions: dict = field(default_factory=dict)
    signups: dict = field(default_factory=dict)
    bank: dict = field(default_factory=dict)
    announcements: dict = field(default_factory=dict)
    recruits: dict = field(default_factory=dict)
    member_notes: dict = field(default_factory=dict)

    @classmethod
    def from_json(cls, data: dict) -> "UploadResult":
        return cls(
            recorder=data.get("recorder", ""),
            sessions=data.get("sessions", {}),
            encounters=data.get("encounters", {}),
            loot=data.get("loot", {}),
            awards=data.get("awards", {}),
            unlinked_characters=data.get("unlinked_characters", []),
            attendance=data.get("attendance"),
            roster=data.get("roster", {}),
            professions=data.get("professions", {}),
            signups=data.get("signups", {}),
            bank=data.get("bank", {}),
            announcements=data.get("announcements", {}),
            recruits=data.get("recruits", {}),
            member_notes=data.get("member_notes", {}),
        )


def upload_payload(site_url: str, token: str, payload: str, timeout: float = 30.0) -> UploadResult:
    """POST {"payload": payload} to `<site_url>/api/epgp/imports`.

    Raises UploadError with a readable message on any non-2xx response or
    network failure.
    """
    url = site_url.rstrip("/") + "/api/epgp/imports"
    body = json.dumps({"payload": payload}).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {token}",
        },
    )

    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read()
    except urllib.error.HTTPError as exc:
        raw_body = exc.read()
        message = _extract_message(raw_body) or exc.reason
        if exc.code == 400:
            raise UploadError(f"The site rejected the export: {message}") from exc
        if exc.code == 401:
            raise UploadError("Not authenticated: your sync token is missing or invalid. Run 'sidequest-sync login'.") from exc
        if exc.code == 403:
            raise UploadError(f"Forbidden: {message or 'your account is no longer an officer, or the token was revoked.'}") from exc
        raise UploadError(f"Site returned HTTP {exc.code}: {message}") from exc
    except urllib.error.URLError as exc:
        raise UploadError(f"Could not reach {site_url}: {exc.reason}") from exc
    except TimeoutError as exc:
        raise UploadError(f"Timed out talking to {site_url}") from exc

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise UploadError("Site returned a response that was not valid JSON") from exc

    return UploadResult.from_json(data)


def _extract_message(raw_body: bytes) -> str | None:
    try:
        data = json.loads(raw_body)
    except (json.JSONDecodeError, UnicodeDecodeError):
        return None
    if isinstance(data, dict):
        for key in ("detail", "message", "error"):
            if isinstance(data.get(key), str):
                return data[key]
    return None
