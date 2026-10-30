# SideQuest

An EPGP loot, attendance and progression addon for the SideQuest guild (WoW:
Forever), plus a companion `sidequest-sync` uploader that gets SavedVariables
exports onto the guild site without anyone copy-pasting a wall of text.

The full shared contract (loot math, export/import string formats, every
HTTP endpoint) lives on the site side; this addon implements its half.

## Contents

- `SideQuest/` — the in-game addon.
- `uploader/` — `sidequest-sync`, a small Python CLI that watches
  SavedVariables files and uploads exports automatically.
- `tests/` — a headless WoW API stub (`wowstub.lua`) and test runner for the
  addon's pure-Lua logic.

## Installing the addon

1. Copy (or symlink) `SideQuest/` into your WoW `Interface/AddOns/` folder
   so the path reads `Interface/AddOns/SideQuest/SideQuest.toc`.
2. Enable "SideQuest Guild" at the character-select AddOns list.
3. In game, `/sq` opens the main window.

Officers additionally need either:
- the in-game "Edit officer note" guild permission (`C_GuildInfo.CanEditOfficerNote`), or
- a configured fallback rank index (`SideQuestDB.settings.officerRankIndex`,
  1-based guild rank) if your officers don't carry officer-note rights.

## Commands

| Command | Who | What it does |
|---|---|---|
| `/sq` | everyone | toggles the main window (Standings/Raid/Loot/Events/Sync tabs) |
| `/sq export` | officers | builds the `SQX1:` export string from pending data and opens the Sync tab with it selected |
| `/sq export clear` | officers | drops pending data and the last export, after the site has confirmed the import |
| `/sq import` | officers | opens the Sync tab's import box; paste a site-generated `SQI1:` string, or run `/sq import SQI1:...` directly |
| `/sq standby` | everyone | mark yourself standby for tonight (officers add themselves directly in-raid; others send a `GUILD` request an officer can approve) |
| `/sq bid <itemlink>` | officers | opens bidding on an item not in the loot window (e.g. traded to the officer after pickup) |
| `/sq undo <id>` | officers | voids an EP/GP award or loot row by its id (shown next to every auto-award chat line) |
| `/sq help` | everyone | lists all registered commands |

## Officer raid-night walkthrough

1. Zone into the raid instance. If you have officer rights and nobody is
   already recording, the addon prompts you — or open the **Raid** tab and
   click **Record this raid**. This announces you as recorder to the raid
   (`RAID` addon message) so a second officer doesn't double-record and
   cause the site to skip one of your sessions as a conflict.
2. The addon auto-links the new session to the closest site-scheduled raid
   event starting within ±3 hours, for attendance purposes.
3. Click **Start raid** once the roster is set — this is the `on_time` EP
   award (5 EP) for everyone present, standby included.
4. Boss pulls: `ENCOUNTER_START`/`ENCOUNTER_END` are tracked automatically.
   A kill awards `boss_kill` EP (10) to everyone present. The *first* wipe
   of the night on a boss the guild hasn't killed yet awards `progress` EP
   (10), once per boss per night — later wipes on the same boss award
   nothing.
5. Loot: if you're master looter, **Open bidding (loot window)** reads the
   current loot window and opens bidding per item over `RAID` addon
   messages, with a response timer. Raiders get a popup showing the item,
   their current PR, and Main/Off/Pass buttons. The Loot tab ranks
   responses per the contract's bid order (main spec by PR, trials after
   non-trial raiders, then off spec, then alt, then disenchant; ties by EP
   then roll) so you can Award with confidence. Council items (chase,
   legendary, crafted tier) are never auto-ranked — pick the winner
   yourself; they still pay GP.
   If you're not master looter (e.g. someone traded you the item after
   picking it up), use `/sq bid <itemlink>` to run the same bidding flow
   manually.
6. Click **End raid** when you're done — the `full_night` EP award (5 EP)
   goes out to everyone still present (and standby).
7. Every automatic award prints a chat line with an `/sq undo <id>` you (or
   another officer) can run immediately if something was awarded by
   mistake — mis-clicks happen.
8. After the raid, open the **Sync** tab (or `/sq export`), confirm the
   string looks right, and get it to the site via whichever of these is
   convenient:
   - paste the string directly into the site's import page,
   - alt-tab and run `sidequest-sync once` (see below), or
   - just let a running `sidequest-sync watch` pick up the SavedVariables
     change on its own.
   Once the site confirms the import, run `/sq export clear` so the next
   night starts from an empty pending set.

Standings refresh automatically: after any officer imports a new `SQI1:`
string, the addon rebroadcasts compact standings chunks to `GUILD` so every
member's Standings tab updates without anyone pasting anything. Members
also request standings on login (with a short random delay so twenty people
logging in at once doesn't spam the guild channel); only the officer with
the newest `generated_at` answers, and only once.

## Syncing SavedVariables to the site

The addon keeps the latest export string in `SideQuestDB.lastExport` and
everything not-yet-exported in `SideQuestDB.pending`, inside the standard
`WTF/Account/<account>/SavedVariables/SideQuest.lua` file. Three ways to get
that onto the site, in increasing order of automation:

1. **Paste it yourself.** `/sq export`, select-all in the box, paste into
   the site's officer import page.
2. **Upload the whole SavedVariables file.** The site (and the uploader)
   both find the export with the regex `SQX1:[A-Za-z0-9+/=]+`, so uploading
   the raw `SideQuest.lua` file works too.
3. **Run `sidequest-sync`.** See below — it finds the file for you and
   uploads just the export string whenever it changes.

### `sidequest-sync` uploader

Requires Python 3.12+. From the `uploader/` directory:

```sh
uv run sidequest-sync login     # prompts for site URL + sync token, stores them
uv run sidequest-sync once      # finds + uploads any new/changed exports, then exits
uv run sidequest-sync watch     # polls every 5s (--interval to change) and uploads on change
uv run sidequest-sync status    # shows config, detected SavedVariables files, upload history
```

Get a sync token from the site's officer settings (`POST
/api/epgp/sync-tokens`); it's shown once, so `login` is the only place to
paste it. Credentials are stored in your OS config directory
(`~/Library/Application Support/sidequest-sync` on macOS,
`~/.config/sidequest-sync` on Linux, `%APPDATA%\sidequest-sync` on Windows)
with the config file restricted to your user (`0600`) where the OS supports
it.

`sidequest-sync` auto-detects the WoW install at the usual macOS
(`/Applications/World of Warcraft`) and Windows (`C:\Program Files
(x86)\World of Warcraft`, `C:\Program Files\World of Warcraft`) locations,
or pass `--wow-dir` to point at a custom install. It globs every
`_*_/WTF/Account/*/SavedVariables/SideQuest.lua` under that root — Forever's
live flavor folder name isn't settled yet, so every flavor folder is
checked rather than hardcoding one. Each export is uploaded once (deduped
by a sha256 of the payload, recorded in a local state file), so `watch`
re-polling the same unchanged file is a no-op.

## WoW: Forever caveats

Forever is a new, still-settling client build, so a few things here are
best-effort until confirmed in game:

- **Addon messages likely don't work inside instances.** The researched
  Mainline 12.x `Enum.SendAddonMessageResult` suggests
  `C_ChatInfo.SendAddonMessage` can fail with a non-success result while
  you're in an instance — exactly where raid loot bidding and standings
  broadcast happen. The addon checks the result and falls back to manual
  officer actions (award loot directly from the Loot tab, read out standings
  in voice/Discord) when sends fail, with a chat message explaining why.
- **SavedVariables persistence was flaky in beta.** `SideQuestDB.lastExport`
  and `.pending` are written continuously rather than relying on a clean
  logout, but a hard crash could still lose unsaved state since the last
  write. Export often rather than waiting until the end of a long night.
- **Master loot is unconfirmed until December 9.** The Loot tab assumes
  master loot (`GiveMasterLoot`) works as on existing Mainline builds; if it
  doesn't, officers can still record loot manually (item, winner, response)
  from the Loot tab without an actual master-loot hand-off, and the GP/EP
  ledger stays correct either way.
- `issecretvalue` (Midnight's "secret values") is guarded everywhere unit
  names/GUIDs are read, since it isn't present on pre-Midnight builds and
  its exact Forever behavior is unverified.

## Running the addon's tests

```sh
luajit tests/run_tests.lua   # unit tests (pure Lua, no game client needed)
luacheck SideQuest tests     # static analysis, WoW globals declared in .luacheckrc
```

The test suite also writes `tests/fixtures/export_v1.txt`, a real `SQX1:`
export string from a simulated raid night, for the site's import tests to
consume.

## License

MIT — see `LICENSE`.
