# SideQuest layout preview

A **layout check, not a pixel-identical render of the game.** This renders
every view of the real `SideQuest/UI/Main.lua` / `BidPopup.lua` code —
every tab, every Console sub-tab, the bid popup, and the announcement
toast — to static HTML/PNG at the game's default UI scale (1.0) and at 0.64,
without a WoW client, so layout regressions (clipping, overlap, misalignment,
illegible text at 0.64) show up without anyone opening the game.

It works by loading the addon under `tests/wowstub.lua` (the same headless
API stub the unit tests use), feeding it synthetic, labelled demo data
("Demo1", "Demo Boss", …), building the real UI frames, then walking every
visible frame's recorded `SetPoint`/`SetAllPoints`/`SetSize` calls to
resolve an absolute CSS rect for it — the same anchor math the game's own
layout engine does, just computed in Lua instead of C++.

## Running it

From the addon repo root:

```sh
luajit tests/preview/record.lua
mise exec -C /path/to/sidequest-guild/website -- node "$PWD/tests/preview/screenshot.mjs"
```

(`screenshot.mjs` borrows Playwright from the `sidequest-guild` website
repo's `node_modules`, since this addon repo has no JS toolchain of its
own — point the `mise exec -C` at wherever that checkout lives.)

Output:
- `tests/preview/html/<view>.html` and `<view>-064.html` — one static page
  per view, openable directly in a browser.
- `tests/preview/index.html` — a gallery linking every `html/` page.
- `tests/preview/out/<view>.png` and `<view>-064.png` — Playwright
  screenshots of each, sized to the view's stage.

Add `--docs` to the `screenshot.mjs` command to refresh the README's pictures instead: it captures just the window,
with no caption, at twice the size, into `docs/screenshots/*.jpg`. Do this after a UI change so the README stays
current.

## What it does and doesn't prove

**Does:** real anchor math (so a row genuinely overlapping the tab bar or a
column genuinely misaligned shows up exactly where it would in game); real
colours, fonts and text content straight from the running Lua; real
scroll-list clipping (`ScrollFrame` children are clipped to the frame's own
rect, with a themed scrollbar track/thumb drawn beside them, same as
`buildScroll()` in `Main.lua` does for real play); a font-size floor so text
stays legible once the 0.64-scale views are scaled down.

**Doesn't:** stock Blizzard template chrome — `UIPanelButtonTemplate`'s
painted button face, `InputBoxTemplate`'s inset border, the `ScrollFrame`
template's own up/down arrow buttons, the close button's texture — none of
that is reproduced; buttons/edit boxes show their label text (if any) in a
plain box so their presence and wiring stay checkable, not their in-game
skin. Item/class icon *textures* are real Blizzard file paths the addon
would use in game, but this renderer has no access to Blizzard's art, so
each one falls back to a flat quality/class-colour swatch instead of the
actual icon image.

**Fonts:** headings use the shipped Libertinus Serif Display, body text the
shipped EB Garamond (both OFL-licensed, see `SideQuest/Media/PROVENANCE.md`).
The game's own default font, Friz Quadrata, is proprietary and is not
reproduced here — line lengths and wrapping will differ slightly from the
in-game look as a result.

## Demo data

Every row (`Demo1` … `Demo20`, `Demo Boss`, `DemoRecruit`, …) is synthetic
and labelled as such per `PRODUCT.md`'s evidence principle — no real guild
roster, kills, loot or recruits exist yet. `tests/preview/record.lua` is the
single source of that data; see its comments for what each view needs.
