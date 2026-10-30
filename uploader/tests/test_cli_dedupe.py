from pathlib import Path

import sidequest_sync.cli as cli
import sidequest_sync.config as config_module
from sidequest_sync.config import Config, State
from sidequest_sync.upload import UploadResult


def _make_result(**overrides):
    base = dict(
        recorder="Officername-Whitemane",
        sessions={"new": 1, "updated": 0},
        encounters={"new": 0, "updated": 0},
        loot={"new": 0, "updated": 0, "voided": 0},
        awards={"new": 0, "updated": 0, "voided": 0},
        unlinked_characters=[],
        attendance=None,
    )
    base.update(overrides)
    return UploadResult(**base)


def test_upload_one_skips_unchanged_payload(tmp_path: Path, monkeypatch):
    monkeypatch.setattr(config_module, "config_dir", lambda: tmp_path)

    calls = []

    def fake_upload(site_url, token, payload, timeout=30.0):
        calls.append(payload)
        return _make_result()

    monkeypatch.setattr(cli, "upload_payload", fake_upload)

    sv_file = tmp_path / "SideQuest.lua"
    sv_file.write_text('SideQuestDB = { ["lastExport"] = "SQX1:eyJ2IjoxfQ==" }', encoding="utf-8")

    config = Config(site_url="https://example.test", token="sqs_token")
    state = State()

    uploaded_first = cli._upload_one(config, state, sv_file, quiet=True)
    assert uploaded_first is True
    assert len(calls) == 1

    uploaded_second = cli._upload_one(config, state, sv_file, quiet=True)
    assert uploaded_second is False, "unchanged payload must be skipped (dedupe by sha256)"
    assert len(calls) == 1, "no second network call for an unchanged export"


def test_upload_one_reuploads_after_file_changes(tmp_path: Path, monkeypatch):
    monkeypatch.setattr(config_module, "config_dir", lambda: tmp_path)

    calls = []

    def fake_upload(site_url, token, payload, timeout=30.0):
        calls.append(payload)
        return _make_result()

    monkeypatch.setattr(cli, "upload_payload", fake_upload)

    sv_file = tmp_path / "SideQuest.lua"
    sv_file.write_text('SideQuestDB = { ["lastExport"] = "SQX1:eyJ2IjoxfQ==" }', encoding="utf-8")

    config = Config(site_url="https://example.test", token="sqs_token")
    state = State()

    assert cli._upload_one(config, state, sv_file, quiet=True) is True

    sv_file.write_text('SideQuestDB = { ["lastExport"] = "SQX1:eyJ2IjoyfQ==" }', encoding="utf-8")
    assert cli._upload_one(config, state, sv_file, quiet=True) is True
    assert calls == ["SQX1:eyJ2IjoxfQ==", "SQX1:eyJ2IjoyfQ=="]


def test_upload_one_skips_file_with_no_export(tmp_path: Path, monkeypatch):
    calls = []
    monkeypatch.setattr(cli, "upload_payload", lambda *a, **kw: calls.append(1))

    sv_file = tmp_path / "SideQuest.lua"
    sv_file.write_text("SideQuestDB = { }", encoding="utf-8")

    config = Config(site_url="https://example.test", token="sqs_token")
    state = State()

    assert cli._upload_one(config, state, sv_file, quiet=True) is False
    assert calls == []


def test_config_round_trip_persists_with_restricted_perms(tmp_path: Path, monkeypatch):
    monkeypatch.setattr(config_module, "config_dir", lambda: tmp_path)

    config = Config(site_url="https://example.test", token="sqs_secret")
    config.save()

    loaded = Config.load()
    assert loaded.site_url == "https://example.test"
    assert loaded.token == "sqs_secret"

    import os
    import stat

    if os.name != "nt":
        mode = stat.S_IMODE((tmp_path / "config.json").stat().st_mode)
        assert mode == 0o600
