# Design System: SideQuest addon

The addon carries the guild site's world into the game, inside the game's own window. Outside, the window is a
Forever ("Camelot") frame: the same gilded, chamfered bronze chrome, portrait ring, tabs and close button the Character
and Spellbook windows use, so it sits naturally beside them. Inside, every panel is the site's citadel
(`sidequest-guild/website/DESIGN.md`: night ground, guild gold as rims and hairlines, chambers with swallowtail
ribbons, diamond ornaments, class colours on names and quality colours on items), cut in the frame's chamfered shape
language. Nothing inside or out is a square box. Direction contract: `.impeccable/surfaces/sidequest-ui-main-lua.md`.

All builders live in `SideQuest/UI/Skin.lua`; `Main.lua` and `BidPopup.lua` only compose them.

## Colours (from the site)
| Role | Value | Use in game |
|---|---|---|
| Night / Night 2 / Night 3 | `#0a0f1a` / `#101a2c` / `#18253d` | window ground, chamber fill gradient, wells |
| Royal / Royal 2 | `#22386a` / `#2e4a85` | ribbons, primary buttons, the selected answer, the crest's disc |
| Stone | `rgba(150,172,210,.26)` | field-well keyline, done step plates |
| Guild Gold / Deep / Hi | `#d8ab5c` / `#a88449` / `#f0dcae` | rims, the chamber hairline, sub-heading dividers, tab labels, current step |
| Ink / Mist / Mist 2 | `#f2efe9` / `#c4cddd` / `#96a2b8` | primary, secondary and tertiary text |
| Flavor | `#ffd36a` | quoted text only (announcements) |
| Class and quality colours | the game's | names and items, always with the class word or item name |

## Type
- **Display:** Libertinus Serif Display (OFL, `Media/Fonts/`), uppercase, tracked by joining glyphs with U+2009 thin
  spaces (FontStrings have no letter-spacing). The title, ribbons, tabs and sub-headings.
- **Body:** EB Garamond and EB Garamond Italic (OFL). Rows, values, placeholders (italic), quoted text (italic).
  Numbers in tables are right-aligned in fixed columns.
- Readable at UI scale 0.64.

## Components

### Window (native)
`UI.ApplyWindowChrome(main, title)` applies Blizzard's `PortraitFrameTemplate` NineSlice layout with Camelot's offset
overrides (the layout is copied into Skin.lua because an addon frame doesn't inherit the XML template). On Forever the
`UI-Frame-Metal-*` atlases resolve to the Camelot art. The crest sits in the portrait ring (`CrestPortrait.tga`,
already round, so no mask texture), the title is centred in the 21-unit title band, and the close button is the native
`UIPanelCloseButton`. The ground under the title band is Night.

Under the title band, the Great Hall painting (`HeaderStrip.tga`) fades into night at its foot; the freshness line
("Synced 2h ago") sits at its lower right on a fading scrim.

### Tabs (native)
`UI.CreatePanelTab(parent, text, isTop, isOfficer)` and `UI.SetPanelTabSelected` rebuild `PanelTabButtonTemplate`
from its atlases (`uiframe-tab-*`, `uiframe-activetab-*`, ADD-blended highlight) with the template's offsets and text
positions. The main tabs hang below the window's bottom edge like the Character frame's (first at (11, 2), each 3 to
the right of the last). The Console's sub-tabs are top tabs, flipped and cropped exactly as `PanelTopTabButtonMixin`
does, standing on the sub-view chamber's top edge; they name the view, so Console chambers carry no ribbon. Labels are
tracked caps, gold idle and ink when selected. The Console tab carries a diamond and shows only for officers.

### Chamber
`createChamber(parent, name)`: a vertical night gradient behind `Chamber.tga`, a 9-slice chamfered gilded rim (dark
keyline, lit outer edge, gold body, shaded inner edge, a soft inner shadow and the guild-gold-deep hairline parallel to
the rim). A faceted `Diamond.tga` is riveted onto each cut corner. Content sits 8 units in. Chambers never nest.

### Ribbon
`createRibbon(chamber, text)`: `Ribbon.tga`, the site's royal swallowtail banner (gold edge lines, dark keyline, soft
shadow), 3-sliced and sized to its label (never to the chamber), centred on the chamber's top edge.

### Sub-heading
Tracked caps, then the site's divider: a small diamond and a guild-gold-deep line fading to the right. No eyebrow
labels anywhere.

### Buttons
`createButton(parent, kind, text, w, h)`: chamfered 3-slice art. Primary is a royal body in a gilded rim
(`ButtonPrimary.tga`); quiet is a night body in a bronze rim (`ButtonQuiet.tga`). Hover lights a warm inner glow
(`ButtonGlow.tga`, ADD), pressed darkens and sinks the label a pixel, disabled desaturates and explains why in a
tooltip. `btn:SetSelected(true)` gives a quiet button the primary face: the chosen Going/Maybe/Can't answer and the
chosen bid.

### Field wells and checkboxes
`skinEditBox`: a sunken chamfered well (`FieldWell.tga`) whose rim warms toward gold while focused, with an italic
placeholder shown only while empty. Checkboxes and checklists use Forever's `checkbox-minimal` and `checkmark-minimal`:
an empty box until done, then the box with its check, so the state reads by shape.

### Lists and tables
Header row in tracked caps over a hairline; numerals right-aligned; your row in a royal tint. Online state is a tinted
`Gem.tga` plus the word. Alts expand under their main with Forever's `common-button-collapseExpand` arrows.

### Scrolling
`buildScroll` keeps the `UIPanelScrollFrameTemplate` slider doing the work (wheel, drag, range) and reskins it: a dark
channel, the gilded chamfered thumb (`ScrollThumb.tga`), arrow buttons invisible and inert. `UI.SetScrollContentHeight`
gives each list its laid-out height so the range matches the content.

### Icons
News kinds use the game's own atlases (`DungeonSkull`, `VignetteKillElite`, `communities-icon-notification`,
`LevelUp-Dot-Gold`, `socialqueuing-icon-group`, `UI-Achievement-Shield-1`); loot shows the item's icon in
`IconFrame.tga` tinted to its quality. Raid sign-up rows use the quest marks `QuestNormal` (open) and `QuestTurnin`
(closed). No typed glyphs or flat colour squares stand in for icons.

### Raid-night course
Numbered `Plate.tga` plates tinted gold-deep (pending), gold (current) or stone (done), with the step, its state and
its time in aligned columns.

### Bid popup
A chamber with a "Bidding" ribbon; the item icon in a quality-tinted `IconFrame.tga`; the name in quality colour; slot
and GP; your PR and where you'd rank; Forever's player cast bar at its native 211x13 (`UI-CastingBar-*`) as the
countdown, with the seconds in words; Main, Off and Pass.

### Toast
A chamber with an "Announcement" ribbon, the officer's name and the quoted text. It never shows in combat.

## Motion
Never in combat and never when `SideQuestDB.settings.reduceMotion` is true; every helper checks `UI.MotionAllowed()`.
- Window open: alpha 0 to 1 and scale 0.98 to 1, 150 ms, ease-out.
- Tab or sub-tab switch: the panel fades in over 120 ms (one reused animation group per panel).
- Toast: slides down into place and fades in, 160 ms.
- **The authored moment:** when an officer completes a raid-night step, a wax seal bearing the crest (`WaxSeal.tga`)
  is pressed onto its plate: it drops in at 1.7x and lands at 0.94x over 170 ms, settles to 1x, and rests at a slight
  tilt. The seal, not the animation, persists; a step stamps once.

## Behaviour rules
- Nothing opens, animates or toasts in combat; it waits for `PLAYER_REGEN_ENABLED`.
- Every automatic action that can't run says so where it would have appeared, with the manual fallback.
- The freshness line always shows how old the imported data is.

## Assets
The addon's own textures are in `SideQuest/Media/Skin/`: 32-bit TGA at power-of-two sizes, drawn at 2x as SVG by
`tools/skin-art/render.mjs` (the painting is a crop of the site's raid hall). Blizzard's Forever art is never shipped;
the addon names atlases and the game supplies them. Sources and commands: `SideQuest/Media/PROVENANCE.md`.

## Checking it outside the game
`tests/preview/` renders every view from the real addon code (see its README). With the atlas cache fetched, every
Blizzard atlas draws Forever's real art (fetched from wago.tools into the gitignored `tests/preview/.atlas-cache/`,
never committed), so the preview shows the actual Camelot chrome. It checks layout, not in-game lighting.
