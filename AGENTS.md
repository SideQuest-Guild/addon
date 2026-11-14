# SideQuest addon

The guild's World of Warcraft: Forever addon (Lua), plus `sidequest-sync`, a small Python uploader. It records raid
nights and SQL loot points in game and trades them with [sidequest-guild.com](https://sidequest-guild.com) through
export and import strings. `README.md` explains the addon to people; keep it current and in plain words.
`PRODUCT.md` and `DESIGN.md` hold the product and look decisions.

## Layout
- `SideQuest/`: the addon itself. `SideQuest.toc` lists the files in load order; `Core.lua` starts it, `Codec.lua`
  reads and writes the `SQX1:`/`SQI1:` strings, `UI/` is the window.
- `tests/`: `run_tests.lua` runs the addon outside the game against `wowstub.lua`, a fake copy of the WoW functions
  it uses. `tests/preview/` draws every tab as an image so you can check the layout without the game.
- `uploader/`: `sidequest-sync`, which sends the save file to the site.

## Working
- Before you commit: `luajit tests/run_tests.lua`, `luacheck SideQuest tests` and
  `uv run --directory uploader pytest`. All three must pass; CI runs the same.
- Commits are SSH-signed via 1Password. If signing fails, ask the user to unlock it; never turn signing off.
- Commit subjects are Conventional Commits written as plain sentences. They become the changelog players read on
  CurseForge, so say what changed for them.
- Other agents work in this tree at the same time: never `git stash`, `checkout`, `reset`, or commit files you
  didn't change.

## Releases
Each release adds a section to `CHANGELOG.md`, which CurseForge, GitHub and the docs site show. Without a tag, every
change sits under "Unreleased".
- Cut one when a batch of `feat` or `fix` commits is ready for players.
- Version `v0.MINOR.PATCH`: any `feat` since the last tag bumps MINOR (`v0.1.0` to `v0.2.0`); only fixes bump PATCH.
  The packager writes the version into the `.toc`; don't edit it by hand.

```sh
git cliff --tag v0.2.0 -o CHANGELOG.md
git add CHANGELOG.md && git commit -m "docs: changelog for v0.2.0"
git tag -s v0.2.0 -m "SideQuest v0.2.0"
git push origin main v0.2.0
gh workflow run build.yml -R SideQuest-Guild/docs   # show it on the docs site now, not at tomorrow's build
```

The tag starts `.github/workflows/release.yml`: it uploads the zip to CurseForge and publishes the GitHub release.
`v*` tags can't be moved or deleted, and a published release can't change; fix a bad release with a new version.
To test the workflow without releasing, run it by hand with the tag left blank.

## Rules that bite
- The `SQX1:` export and `SQI1:` import strings are a contract with the website (its pydantic models) and the
  companion app. Change them in all three, and copy the new `tests/fixtures/export_v*.txt` to the website's tests.
- The SQL rules live in the website's `packages/sidequest-common/src/sidequest_common/schemas/epgp.py`. The addon
  follows them; don't invent numbers here.
- Player-facing text says "SQL" for the loot system. Don't rename code, saved-variable keys or wire formats.
- `AGENTS.md` is in the global gitignore; add it with `git add -f AGENTS.md`.

## The Forever client (checked 2026-11-05 on live build 1.60.1.70790)
Trust these, in this order, over blog posts and "AI prompt" guides, which lag the client:
1. The installed game: `/Applications/World of Warcraft/_forever_/` (`Interface/AddOns/SideQuest` is a copy, not
   a link; saved data is `WTF/Account/<id>/SavedVariables/SideQuest.lua`).
2. Blizzard's UI source for the build: `Gethe/wow-ui-source`, branch `forever`. In
   `Blizzard_APIDocumentationGenerated/`, `SecretReturns`, `SecretWhen*` and `HasRestrictions` mark what addons
   can't read or use.
3. The in-game global dump: `Ketho/BlizzardInterfaceResources`, branch `forever`, `Resources/GlobalAPI.lua`
   (functions and Lua built-ins) and `FrameXML.lua`. If a name isn't there, it doesn't exist in game.
4. warcraft.wiki.gg `Patch_1.60.1/API_changes` and its `/notes` page (Blizzard's notes to addon authors).

Facts that matter here:
- Interface `16001`. Game type `camelot`, with `forever` as an alias since build 70291. Forever is in the Mainline
  family with Midnight: `_Mainline.toc` and `[Family]` match both, `_Forever.toc` and `[AllowLoadGameType forever]`
  match Forever only. In Lua, `WOW_PROJECT_ID == WOW_PROJECT_CAMELOT` (18); it is not 1.
- Lua 5.1 with `bit`. There is no `os` or `io` table: use `date()`, `time()` and `difftime()`, or
  `GetServerTime()`. The tests run in LuaJIT, which has `os`, and luacheck's `lua51` std allows it, so neither
  catches `os.date`.
- Many old globals are gone without a fallback, among them `GetItemInfo`, `GetSpellInfo`, `InviteUnit`,
  `ConvertToRaid`, `IsRaidLeader` and `IsPartyLeader` (use `C_Item`, `C_Spell`, `C_PartyInfo` and
  `UnitIsGroupLeader`). Look a name up in `GlobalAPI.lua` before you use it. `wowstub.lua` fakes whatever we tell
  it to, and `if InviteUnit then` on a name that doesn't exist turns the feature off without a word.
- `SendChatMessage`, `ChatFrame_SendTell`, `ChatEdit_InsertLink` and `CombatLogGetCurrentEventInfo` still exist
  only as Blizzard's deprecated aliases, which load while the CVar `loadDeprecationFallbacks` is 1 (the default).
  New code uses `C_ChatInfo` and `ChatFrameUtil`.
- Secrets: `UnitHealth` is always secret. `UnitName`, `UnitGUID`, `UnitClass`, power, auras and cooldowns are
  secret whenever their restriction is on. Pass values through `SideQuest.Unsecret` (or `issecretvalue`) before you
  compare, join, save or send them. Creature GUIDs carry scrambled server and spawn IDs (build 70425).
- `COMBAT_LOG_EVENT_UNFILTERED` is restricted, and registering it from an addon is forbidden. Blizzard ships its
  own damage meter, cooldown manager and, on Forever only, a swing timer.
- Trial accounts can't send addon messages (70291). `SendChatMessage` to `SAY`, `YELL` or `EMOTE` needs a hardware
  event (a click or key press) outside instances.
- SavedVariables load since build 70009 and persist on live. Read them in `ADDON_LOADED`, never at file scope.
- Lua errors are silent by default. When testing in game run `/console scriptErrors 1`;
  `/dump select(4, GetBuildInfo())` and `/dump WOW_PROJECT_ID` show what the client reports.
