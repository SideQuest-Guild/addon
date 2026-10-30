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
