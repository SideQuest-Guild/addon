"""sidequest-sync command line interface."""

from __future__ import annotations

import argparse
import getpass
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

from sidequest_sync.config import Config, State, config_path
from sidequest_sync.discovery import (
    default_wow_dir,
    extract_export_from_file,
    find_savedvariables_files,
    payload_hash,
)
from sidequest_sync.upload import UploadError, upload_payload

DEFAULT_POLL_SECONDS = 5


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _resolve_wow_dir(wow_dir_arg: str | None) -> Path:
    if wow_dir_arg:
        return Path(wow_dir_arg)
    detected = default_wow_dir()
    if detected is None:
        print(
            "Could not auto-detect a World of Warcraft install. Pass --wow-dir "
            "to point at your WoW folder (the one containing _retail_, "
            "_classic_, etc).",
            file=sys.stderr,
        )
        sys.exit(1)
    return detected


def cmd_login(args: argparse.Namespace) -> int:
    config = Config.load()
    site_url = input(f"Site URL [{config.site_url}]: ").strip() or config.site_url
    token = getpass.getpass("Sync token (sqs_...): ").strip()
    if not token:
        print("No token entered; aborting.", file=sys.stderr)
        return 1
    config.site_url = site_url
    config.token = token
    config.save()
    print(f"Saved credentials to {config_path()}")
    return 0


def _upload_one(config: Config, state: State, path: Path, *, quiet: bool = False) -> bool:
    """Upload the export found in `path` if not already uploaded. Returns
    True if an upload happened (success or attempted-and-failed), False if
    skipped as unchanged."""
    export = extract_export_from_file(path)
    if not export:
        if not quiet:
            print(f"{path}: no SQX1: export string found, skipping")
        return False

    digest = payload_hash(export)
    if digest in state.uploaded_hashes:
        if not quiet:
            print(f"{path}: unchanged since last upload, skipping")
        return False

    try:
        result = upload_payload(config.site_url, config.token, export)
    except UploadError as exc:
        print(f"{path}: upload failed: {exc}", file=sys.stderr)
        return True

    state.uploaded_hashes[digest] = _now_iso()
    state.last_file = str(path)
    state.last_upload_at = _now_iso()
    state.save()

    print(f"{path}: uploaded by {result.recorder or 'unknown recorder'}")
    print(
        f"  sessions new={result.sessions.get('new', 0)} updated={result.sessions.get('updated', 0)}  "
        f"encounters new={result.encounters.get('new', 0)} updated={result.encounters.get('updated', 0)}"
    )
    print(
        f"  loot new={result.loot.get('new', 0)} updated={result.loot.get('updated', 0)} "
        f"voided={result.loot.get('voided', 0)}  "
        f"awards new={result.awards.get('new', 0)} updated={result.awards.get('updated', 0)} "
        f"voided={result.awards.get('voided', 0)}"
    )
    if any([result.roster, result.professions, result.signups, result.bank,
            result.announcements, result.recruits, result.member_notes]):
        print(
            f"  roster updated={result.roster.get('updated', 0)}  "
            f"professions updated={result.professions.get('updated', 0)}  "
            f"signups applied={result.signups.get('applied', 0)} "
            f"skipped_older={result.signups.get('skipped_older', 0)} "
            f"unlinked={result.signups.get('unlinked', 0)}"
        )
        print(
            f"  bank new={result.bank.get('new', 0)}  "
            f"announcements new={result.announcements.get('new', 0)}  "
            f"recruits new={result.recruits.get('new', 0)} updated={result.recruits.get('updated', 0)}  "
            f"member_notes new={result.member_notes.get('new', 0)} "
            f"updated={result.member_notes.get('updated', 0)} voided={result.member_notes.get('voided', 0)}"
        )
    if result.unlinked_characters:
        print(f"  unlinked characters: {', '.join(result.unlinked_characters)}")
    if result.attendance:
        print(f"  attendance: event {result.attendance.get('event_id')} marked {result.attendance.get('marked')}")
    return True


def _require_token(config: Config) -> None:
    if not config.token:
        print("Not logged in. Run 'sidequest-sync login' first.", file=sys.stderr)
        sys.exit(1)


def cmd_once(args: argparse.Namespace) -> int:
    config = Config.load()
    _require_token(config)
    state = State.load()
    wow_dir = _resolve_wow_dir(args.wow_dir)
    files = find_savedvariables_files(wow_dir)
    if not files:
        print(f"No SideQuest.lua SavedVariables files found under {wow_dir}")
        return 0
    any_uploaded = False
    for path in files:
        if _upload_one(config, state, path):
            any_uploaded = True
    if not any_uploaded:
        print("Nothing new to upload.")
    return 0


def cmd_watch(args: argparse.Namespace) -> int:
    config = Config.load()
    _require_token(config)
    state = State.load()
    wow_dir = _resolve_wow_dir(args.wow_dir)
    interval = args.interval or DEFAULT_POLL_SECONDS

    print(f"Watching {wow_dir} every {interval}s for SideQuest.lua changes. Ctrl+C to stop.")
    last_mtimes: dict[Path, float] = {}
    try:
        while True:
            for path in find_savedvariables_files(wow_dir):
                try:
                    mtime = path.stat().st_mtime
                except OSError:
                    continue
                if last_mtimes.get(path) != mtime:
                    last_mtimes[path] = mtime
                    _upload_one(config, state, path, quiet=True)
            time.sleep(interval)
    except KeyboardInterrupt:
        print("Stopped.")
    return 0


def cmd_status(args: argparse.Namespace) -> int:
    config = Config.load()
    state = State.load()
    print(f"Config file: {config_path()}")
    print(f"Site URL: {config.site_url}")
    print(f"Logged in: {'yes' if config.token else 'no'}")
    wow_dir = default_wow_dir() if not args.wow_dir else Path(args.wow_dir)
    print(f"WoW directory: {wow_dir or '(not auto-detected; pass --wow-dir)'}")
    if wow_dir:
        files = find_savedvariables_files(wow_dir)
        print(f"SavedVariables files found: {len(files)}")
        for f in files:
            print(f"  {f}")
    print(f"Uploads recorded: {len(state.uploaded_hashes)}")
    if state.last_upload_at:
        print(f"Last upload: {state.last_upload_at} ({state.last_file})")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="sidequest-sync", description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("login", help="store the site URL and sync token").set_defaults(func=cmd_login)

    once_parser = sub.add_parser("once", help="upload any new/changed exports now and exit")
    once_parser.add_argument("--wow-dir", help="override the auto-detected WoW install directory")
    once_parser.set_defaults(func=cmd_once)

    watch_parser = sub.add_parser("watch", help="poll SavedVariables files and upload on change")
    watch_parser.add_argument("--wow-dir", help="override the auto-detected WoW install directory")
    watch_parser.add_argument("--interval", type=float, default=DEFAULT_POLL_SECONDS, help="poll interval in seconds (default 5)")
    watch_parser.set_defaults(func=cmd_watch)

    status_parser = sub.add_parser("status", help="show config, detected files and upload history")
    status_parser.add_argument("--wow-dir", help="override the auto-detected WoW install directory")
    status_parser.set_defaults(func=cmd_status)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
