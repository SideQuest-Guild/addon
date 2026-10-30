from pathlib import Path

from sidequest_sync.discovery import (
    extract_export,
    extract_export_from_file,
    find_savedvariables_files,
    payload_hash,
)


def test_extract_export_finds_token_in_arbitrary_text():
    text = 'SideQuestDB = {\n  ["lastExport"] = "SQX1:eyJ2IjoxfQ==",\n}'
    assert extract_export(text) == "SQX1:eyJ2IjoxfQ=="


def test_extract_export_returns_last_when_multiple():
    text = "SQX1:AAAA== some other text SQX1:BBBB=="
    assert extract_export(text) == "SQX1:BBBB=="


def test_extract_export_returns_none_when_absent():
    assert extract_export("no export here") is None


def test_extract_export_from_file(tmp_path: Path):
    f = tmp_path / "SideQuest.lua"
    f.write_text('SideQuestDB = { ["lastExport"] = "SQX1:eyJ2IjoxfQ==" }', encoding="utf-8")
    assert extract_export_from_file(f) == "SQX1:eyJ2IjoxfQ=="


def test_extract_export_from_missing_file(tmp_path: Path):
    assert extract_export_from_file(tmp_path / "missing.lua") is None


def test_find_savedvariables_files_matches_flavor_glob(tmp_path: Path):
    wow_dir = tmp_path / "World of Warcraft"
    live = wow_dir / "_retail_" / "WTF" / "Account" / "ACCOUNTNAME" / "SavedVariables"
    classic = wow_dir / "_classic_" / "WTF" / "Account" / "OTHERACCOUNT" / "SavedVariables"
    live.mkdir(parents=True)
    classic.mkdir(parents=True)
    (live / "SideQuest.lua").write_text("SQX1:AAAA==", encoding="utf-8")
    (classic / "SideQuest.lua").write_text("SQX1:BBBB==", encoding="utf-8")
    (live / "OtherAddon.lua").write_text("not us", encoding="utf-8")

    found = find_savedvariables_files(wow_dir)
    names = sorted(str(p) for p in found)
    assert len(found) == 2
    assert all(p.name == "SideQuest.lua" for p in found)
    assert any("_retail_" in n for n in names)
    assert any("_classic_" in n for n in names)


def test_find_savedvariables_files_missing_root_returns_empty(tmp_path: Path):
    assert find_savedvariables_files(tmp_path / "nope") == []


def test_payload_hash_is_stable_sha256():
    h1 = payload_hash("SQX1:AAAA==")
    h2 = payload_hash("SQX1:AAAA==")
    h3 = payload_hash("SQX1:BBBB==")
    assert h1 == h2
    assert h1 != h3
    assert len(h1) == 64
