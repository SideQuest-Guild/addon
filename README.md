# SideQuest

The SideQuest guild's own app, inside the game: one window that's both the
member's guild companion and the officers' console, kept in step with
[sidequest-guild.com](https://sidequest-guild.com) via export/import strings.
Plus a companion `sidequest-sync` uploader that gets those strings onto the
site without anyone copy-pasting a wall of text.

The full shared contract (loot math, export/import string formats, every
HTTP endpoint) lives on the site side; this addon implements its half.

## Contents

- `SideQuest/` — the in-game addon.
- `uploader/` — `sidequest-sync`, a small Python CLI that watches
  SavedVariables files and uploads exports automatically.
- `tests/` — a headless WoW API stub (`wowstub.lua`) and test runner for the
  addon's pure-Lua logic, plus `tests/preview/` (see
  [tests/preview/README.md](tests/preview/README.md)), a layout-check
  renderer for the window and its popups.

## Installing the addon

1. Copy (or symlink) `SideQuest/` into your WoW `Interface/AddOns/` folder
   so the path reads `Interface/AddOns/SideQuest/SideQuest.toc`.
2. Enable "SideQuest Guild" at the character-select AddOns list.
3. In game, `/sq` (or any slash command below) opens the main window on the
   **You** tab — your standing, next raid and who's on, the way the game's
   own Character frame opens on you rather than a roster grid.

Officers additionally need either:
- the in-game "Edit officer note" guild permission (`C_GuildInfo.CanEditOfficerNote`), or
- a configured fallback rank index (`SideQuestDB.settings.officerRankIndex`,
  1-based guild rank) if your officers don't carry officer-note rights.

## The window

Bottom tabs: **You**, **Guild**, **Crafters**, **Raids**, **Ledger**, **News**,
and (officers/GMs only, gold-edged) **Console**.

### Members

- **You** — your name in class colour, rank and alts, PR with your rank
  among the guild, a four-week EP/GP table, your next raid with
  Going/Maybe/Can't (your current answer stays highlighted), and your
  badges/guild EP/attendance. **Guild Now** beside it: who's online right
  now and the news feed (boss kills, loot, level-ups, joins, announcements —
  one icon per kind, grouped by day).
- **Guild** — the roster: name, level, rank, zone, last seen, grouped by
  member with alts collapsed under their main (click **+** to expand).
  Search, an online-only filter, and class/rank filters; Whisper/Invite on
  hover or selection.
- **Crafters** — search a recipe or a profession name; results group by
  recipe (or profession, if no specific recipe matched) with every crafter
  who can make it, online first, with their skill and a Whisper button.
  Online members answer live; an officer's addon answers once more for
  everyone offline, from the last profession sync.
- **Raids** — upcoming events: day/time, how many are signed per role, your
  own answer, and your sign-up buttons. Answering here (or on the **You**
  tab) reaches the site at the next officer sync — you never have to paste
  anything.
- **Ledger** — everyone's EP/GP/PR (your row highlighted), then your own
  ledger and recent loot history (ask for it — an officer's addon answers;
  if none are online it says so instead of hanging forever).
- **News** — the full history of the feed shown on **You**, grouped by day.

### Officers and GMs (Console)

Seven gold-edged sub-tabs, in the order you'd actually run a raid night:

1. **Raid Night** — the numbered course for tonight: **Prep** (ask the raid
   to report consumables/durability), **Invite** (bring in everyone
   signed), **Start raid** (on-time EP, begin recording), **Boss**
   (encounters record automatically as `ENCOUNTER_START`/`ENCOUNTER_END`
   fire), **Loot** (jumps to the Loot sub-tab), **End raid** (full-night EP,
   stop recording). Each step punches with its time once it's done. Below
   it: who the recorder currently has present (raid vs. standby), the
   standby list, and an auto-award log with **Undo** on every row.
2. **Loot** — open bidding on the current loot window (or `/sq bid` for an
   item traded to you after pickup); responses come back ranked in the
   contract's bid order (main spec by PR — raiders, then trials — then off
   spec, then alt, then disenchant; ties by EP then roll). Council items
   (chase, legendary, crafted tier) are never auto-ranked; pick the winner
   yourself.
3. **Roster** — sweep the guild roster for export, see who's flagged
   inactive, and suggest a rank change (recorded as a member note).
4. **Recruits** — applicants and trials with their checklist, and
   Yes/No officer votes.
5. **Bank** — capture the open guild bank tab's log (when the API exists on
   this client; it's unverified on Forever, see below).
6. **Announce** — write once; it shows in every online member's News feed
   and a toast, drops in guild chat, and — with the Discord checkbox — queues
   for the guild's Discord channel at the next sync. Recently posted
   announcements list below it.
7. **Sync** — last sync time, pending (not-yet-exported) counts per section,
   and the **Export**/**Import** buttons (see below).

## Commands

| Command | Who | What it does |
|---|---|---|
| `/sq` | everyone | opens/closes the main window |
| `/sq export` | officers | builds the `SQX1:` export string from pending data and opens the Sync tab with it selected |
| `/sq export clear` | officers | drops pending data and the last export, after the site has confirmed the import |
| `/sq import` | officers | opens the Sync tab's import box; paste a site-generated `SQI1:` string, or run `/sq import SQI1:...` directly |
| `/sq roster` | officers | sweeps the guild roster now (otherwise swept from the Console's Roster tab) |
| `/sq standby` | everyone | mark yourself standby for tonight (officers add themselves directly in-raid; others send a request an officer can approve) |
| `/sq bid <itemlink>` | officers | opens bidding on an item not in the loot window (e.g. traded to the officer after pickup) |
| `/sq undo <id>` | officers | voids an EP/GP award or loot row by its id (shown next to every auto-award chat line, and on every row of the Raid Night sub-tab's award log) |
| `/sq help` | everyone | lists all registered commands |

## Officer raid-night walkthrough

Follow the numbered course on the Console's **Raid Night** sub-tab:

1. Zone into the raid instance. If you have officer rights and nobody is
   already recording, the addon prompts you — or click **Mark done** on
   step 1 (**Prep**) to ask the raid to report readiness, then step 3
   (**Start raid**) once the roster is set. This announces you as recorder
   to the raid (`RAID` addon message) so a second officer doesn't
   double-record and cause the site to skip one of your sessions as a
   conflict.
2. The addon auto-links the new session to the closest site-scheduled raid
   event starting within ±3 hours, for attendance purposes.
3. **Start raid** is the `on_time` EP award (5 EP) for everyone present,
   standby included.
4. Boss pulls: `ENCOUNTER_START`/`ENCOUNTER_END` are tracked automatically.
   A kill awards `boss_kill` EP (10) to everyone present. The *first* wipe
   of the night on a boss the guild hasn't killed yet awards `progress` EP
   (10), once per boss per night — later wipes on the same boss award
   nothing.
5. **Loot**: jumps to the Loot sub-tab. If you're master looter, **Open
   bidding (loot window)** reads the current loot window and opens bidding
   per item over `RAID` addon messages, with a response timer and a
   countdown bar. Raiders get a popup showing the item (icon + name in its
   quality colour), its slot and GP cost, their PR and where they'd rank,
   and Main/Off/Pass buttons. The Loot sub-tab ranks responses per the
   contract's bid order so you can award with confidence.
   If you're not master looter, `/sq bid <itemlink>` runs the same bidding
   flow manually.
6. **End raid** — the `full_night` EP award (5 EP) goes out to everyone
   still present (and standby).
7. Every automatic award prints a chat line with an `/sq undo <id>`, and
   also shows up with its own **Undo** button in the Raid Night sub-tab's
   auto-award log — mis-clicks happen.
8. After the raid, open the **Sync** sub-tab (or `/sq export`), confirm the
   pending counts and string look right, and get it to the site via
   whichever of these is convenient (see below). Once the site confirms the
   import, run `/sq export clear` so the next night starts from an empty
   pending set.

Standings and the public roster/news refresh automatically: after any
officer imports a new `SQI1:` string, the addon rebroadcasts them to
`GUILD` so every member's window updates without anyone pasting anything.
Members also request their own standings/sheet on demand (with a short
random delay and answer suppression so twenty people asking at once doesn't
spam the channel or get twenty answers).

## Syncing SavedVariables to the site

The addon keeps the latest export string in `SideQuestDB.lastExport` and
everything not-yet-exported in `SideQuestDB.pending`, inside the standard
`WTF/Account/<account>/SavedVariables/SideQuest.lua` file. Three ways to get
that onto the site, in increasing order of automation:

1. **Paste it yourself.** `/sq export` (or the Console's Sync tab), select-all
   in the box, paste into the site's officer import page.
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

Each upload prints the v1 result (sessions/encounters/loot/awards
new/updated/voided counts) and, when the payload carried any v2 sections, a
second line with roster/professions/signups/bank/announcements/recruits/
member-notes counts too.

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
best-effort until confirmed in game, and every one of them degrades to a
manual path and says so in the window rather than failing silently:

- **Addon messages likely don't work inside instances.** The researched
  Mainline 12.x `Enum.SendAddonMessageResult` suggests
  `C_ChatInfo.SendAddonMessage` can fail with a non-success result while
  you're in an instance — exactly where raid loot bidding and standings
  broadcast happen. The addon checks the result and falls back to manual
  officer actions (award loot directly from the Console's Loot tab, read
  out standings in voice/Discord) when sends fail, with a chat message
  explaining why.
- **SavedVariables persistence was flaky in beta.** `SideQuestDB.lastExport`
  and `.pending` are written continuously rather than relying on a clean
  logout, but a hard crash could still lose unsaved state since the last
  write. Export often rather than waiting until the end of a long night.
- **Master loot is unconfirmed until December 9.** The Loot tab assumes
  master loot (`GiveMasterLoot`) works as on existing Mainline builds; if it
  doesn't, officers can still record loot manually (item, winner, response)
  from the Loot tab without an actual master-loot hand-off, and the GP/EP
  ledger stays correct either way.
- **Guild bank log and profession recipe APIs are unverified on Forever.**
  `SideQuest.Bank.IsAvailable()`/`SideQuest.Professions.IsAvailable()` detect
  the APIs at runtime; the Console's Bank tab and the Crafters directory say
  plainly when they can't capture anything here, instead of showing an
  empty list with no explanation.
- `issecretvalue` (Midnight's "secret values") is guarded everywhere unit
  names/GUIDs are read, since it isn't present on pre-Midnight builds and
  its exact Forever behavior is unverified.

## Running the addon's tests

```sh
luajit tests/run_tests.lua   # unit tests (pure Lua, no game client needed)
luacheck SideQuest tests     # static analysis, WoW globals declared in .luacheckrc
```

The test suite also writes `tests/fixtures/export_v1.txt` and
`tests/fixtures/export_v2.txt` — real `SQX1:` export strings from simulated
raid nights, covering every v1 and v2 section — for the site's import tests
to consume.

## Checking the window's layout

`tests/preview/` renders every tab, every Console sub-tab, the bid popup and
the announcement toast to static PNGs at both UI scales, without a game
client. See [tests/preview/README.md](tests/preview/README.md) for how to
run it and what it is (and isn't) evidence of.

## License

MIT — see `LICENSE`.
