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
uv run --with pillow tests/preview/fetch_atlases.py   # once per checkout / whenever new atlas names are added
luajit tests/preview/record.lua
mise exec -C /path/to/sidequest-guild/website/website -- node "$PWD/tests/preview/screenshot.mjs"
```

(`screenshot.mjs` borrows Playwright from the `sidequest-guild` website
repo's `node_modules`, since this addon repo has no JS toolchain of its
own. The three repos live as sibling checkouts, e.g.
`~/git/public/sidequest-guild/{addon,website,bot}` — the website's actual
npm package is nested one level further, at `website/website`; point
`mise exec -C` there, not at the outer `website/` checkout root.)

Output:
- `tests/preview/html/<view>.html` and `<view>-064.html` — one static page
  per view, openable directly in a browser.
- `tests/preview/index.html` — a gallery linking every `html/` page.
- `tests/preview/out/<view>.png` and `<view>-064.png` — Playwright
  screenshots of each, sized to the view's stage.

Add `--docs` to the `screenshot.mjs` command to refresh the README's pictures instead: it captures just the window,
with no caption, at twice the size, into `docs/screenshots/*.jpg`. Do this after a UI change so the README stays
current.

## Real Forever ("Camelot") chrome

Forever runs Blizzard's modern FrameXML, which draws native window chrome
(corners, edges, tabs, the close button, …) from `UiTextureAtlas*` DB2
entries rather than loose texture files — `tex:SetAtlas("UI-Frame-Metal-
CornerTopLeft")` resolves to real gilded-bronze Camelot art at runtime.
This preview reproduces that: `tests/preview/fetch_atlases.py` downloads
the three `UiTextureAtlas*` tables (for a fixed Forever build) from
[wago.tools](https://wago.tools), resolves every atlas element name the
addon's Lua source references (`SetAtlas("...")` calls, layout-table
`atlas = "..."` fields, and any other string literal that is exactly a real
element name, such as the news-icon table) to its Camelot (`-c60`)
sprite-sheet crop in preference to the Mainline one, downloads and decodes
only the texture sheets actually needed, and writes small per-element
cropped PNGs plus an index the stub/renderer both read.

Everything that script fetches or decodes lives under
`tests/preview/.atlas-cache/`, which is **gitignored and must never be
committed** — it's Blizzard-extracted game art, fetched fresh from
wago.tools at preview time, not shipped with the addon. Re-run the fetch
script whenever the addon starts using a new atlas element name; it's
idempotent and only re-downloads what it doesn't already have cached.

Without the cache (a fresh checkout, or before the first fetch run),
`C_Texture.GetAtlasInfo` and the renderer both degrade gracefully: the
stub returns plausible non-zero sizes so addon logic and unit tests never
need the network, and the renderer draws an orange-striped placeholder
labelled with the atlas name instead of crashing. If the addon ever uses
an atlas name that isn't real Blizzard API (a typo), `record.lua` fails
outright and lists the bad name(s), rather than silently drawing nothing.

## What it does and doesn't prove

**Does:** real anchor math, including WoW's rule that anchors on opposite
edges set a region's size over any `SetSize` (so an over-constrained anchor
shows up here the way it would in game); text laid out inside a sized
FontString per `SetJustifyH` and centred vertically, as WoW does; real
colours, fonts and text content straight from the running Lua; real
scroll-list clipping, with the template's slider reskinned the way
`buildScroll()` does it; a font-size floor so text stays legible once the
0.64-scale views are scaled down; real Forever art for every
`SetAtlas`-backed piece (the window's portrait frame, the close button,
tabs, checkboxes, quest marks, news icons, the cast bar), cropped, tiled,
flipped, tinted and blended the way the client composites atlas pieces
(`SetTexCoord` crops and flips, tiling edges, `SetVertexColor` multiply,
`SetDesaturated`, additive blend, `SetRotation`, `SetGradient` fills), and
the same modifiers on the addon's own textures; font shadow and outline.

**Doesn't:** item icons are game file paths this renderer can't load, so a
loot row shows its quality-tinted frame around an empty well. Hover and
pressed states aren't modelled; everything renders at rest, and animations
render at their end state.

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
