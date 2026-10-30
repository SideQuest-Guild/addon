# SideQuest/Media Asset Provenance

All commands below were actually run to produce these files (not guessed). Repo root for
relative source paths is `sidequest-guild/` (sibling checkout of this addon repo), working
directory `sidequest-guild/` unless noted. Font conversion used a throwaway venv:

```sh
python3 -m venv /tmp/fonttools-venv
source /tmp/fonttools-venv/bin/activate
pip install fonttools brotli   # fonttools v4.68.0
```

Image work used ImageMagick 7.1.2-31 (`magick`).

---

## Fonts/

Source directory: `website/.impeccable/prototypes/eldritch/fonts/` (woff2, OFL licensed).

### LibertinusSerifDisplay.ttf, EBGaramond.ttf, EBGaramond-Italic.ttf

`TTFont.save()` preserves the loaded `.flavor` ("woff2") unless explicitly cleared, which would
re-emit a woff2-wrapped stream with a `.ttf` extension — confirmed by inspecting the first bytes
of an initial attempt (`774f4632` = `wOF2` magic) and corrected by setting `flavor = None` before
saving so the output is a plain sfnt TrueType stream (first bytes `00010000`).

```sh
source /tmp/fonttools-venv/bin/activate
python3 -c "
from fontTools.ttLib import TTFont
pairs = [
  ('website/.impeccable/prototypes/eldritch/fonts/LibertinusSerifDisplay.woff2', 'LibertinusSerifDisplay.ttf'),
  ('website/.impeccable/prototypes/eldritch/fonts/EBGaramond.woff2', 'EBGaramond.ttf'),
  ('website/.impeccable/prototypes/eldritch/fonts/EBGaramond-italic.woff2', 'EBGaramond-Italic.ttf'),
]
for src, dst in pairs:
    f = TTFont(src)
    f.flavor = None
    f.save(dst)
"
```

Verified each output parses and lists its table directory:

```sh
fonttools ttx -l LibertinusSerifDisplay.ttf
fonttools ttx -l EBGaramond.ttf
fonttools ttx -l EBGaramond-Italic.ttf
python3 -c "from fontTools.ttLib import TTFont; TTFont('LibertinusSerifDisplay.ttf').close()"
python3 -c "from fontTools.ttLib import TTFont; TTFont('EBGaramond.ttf').close()"
python3 -c "from fontTools.ttLib import TTFont; TTFont('EBGaramond-Italic.ttf').close()"
```

All three parsed without error (`glyf`/`loca`/`cmap`/`name`/etc. tables present, sfnt version
`00010000`).

#### cmap hair-space / thin-space check

Checked via `fontTools.ttLib.TTFont(path).getBestCmap()`:

```sh
python3 -c "
from fontTools.ttLib import TTFont
for f in ['LibertinusSerifDisplay.ttf','EBGaramond.ttf','EBGaramond-Italic.ttf']:
    t = TTFont(f)
    cmap = t.getBestCmap()
    print(f, 'U+200A:', cmap.get(0x200A), 'U+2009:', cmap.get(0x2009), 'U+0020:', cmap.get(0x0020))
"
```

Result (identical for all three fonts — Libertinus and EB Garamond share a cmap-generation
convention here):

| codepoint | glyph mapped | present? |
|---|---|---|
| U+200A HAIR SPACE | *(none)* | **not mapped** — absent from cmap |
| U+2009 THIN SPACE | `uni2009` | mapped |
| U+0020 SPACE | `space` | mapped |

**Finding for tracked-caps/letterspacing use:** none of the three fonts map U+200A (hair space).
All three *do* map U+2009 (thin space) to a dedicated glyph `uni2009`. For addon UI tracked-caps
headings, use **U+2009 (thin space)** as the spacing character; do not use U+200A, as it will fall
back to the font's `.notdef`/missing-glyph behavior. U+0020 (regular space) is present in all
three as a fallback of last resort if thin-space width is too wide for a given context.

### OFL.txt

No existing OFL license file was found anywhere in `sidequest-guild` (checked via grep for "SIL
OPEN FONT LICENSE" and glob for `**/OFL*`/`**/LICENSE*` — no hits), so the canonical license body
was fetched from the upstream Libertinus project's OFL.txt and the font-specific copyright header
line was stripped (kept only the license body starting at the "SIL OPEN FONT LICENSE" banner),
since this single `OFL.txt` covers two different font families/copyright holders — those are
recorded here instead of baked into the file:

```sh
curl -fsSL "https://raw.githubusercontent.com/alerque/libertinus/master/OFL.txt" -o /tmp/libertinus_ofl.txt
sed -n '9,$p' /tmp/libertinus_ofl.txt > OFL.txt
```

**Copyright holders** (read from each font's own `name` table where present):

- **LibertinusSerifDisplay.ttf** — the font's `name` table has no nameID 0 (copyright) record
  (checked: `TTFont('LibertinusSerifDisplay.ttf')['name'].getDebugName(0)` → `None`). Per the
  upstream Libertinus project's own `OFL.txt`
  (https://github.com/alerque/libertinus/blob/master/OFL.txt), the governing copyright is:
  *"Copyright © 2012-2024 The Libertinus Project Authors, with Reserved Font Name 'Linux
  Libertine', 'Biolinum', 'STIX Fonts'."* Portions are further attributed to Khaled Hosny
  (2012-2016) and Philipp H. Poll (2003-2012, original Linux Libertine), per the Libertinus
  project's license history.
- **EBGaramond.ttf** / **EBGaramond-Italic.ttf** — read directly from the font's own `name` table
  (nameID 0): *"Copyright 2017 The EB Garamond Project Authors
  (https://github.com/octaviopardo/EBGaramond12)"*.

All three are licensed SIL Open Font License 1.1 (see `OFL.txt` in this directory).

---

## Skin/

Every custom (non-Blizzard) texture the addon ships. Blizzard's own Forever art (the window
frame, tabs, close button, cast bar, checkboxes, quest marks, news icons) is never shipped: the
addon names those atlases with `SetAtlas` and the game supplies them.

### HeaderStrip.tga

Source: `website/assets/rooms/raid-hall.webp` (1698x926), the guild site's raid hall painting.
Resized to 1024px wide, a 1024x256 band cropped from the upper middle, and its bottom 64px faded
to transparent with a generated mask:

```sh
magick website/assets/rooms/raid-hall.webp -resize 1024x -gravity North -crop 1024x256+0+120 +repage crop.png
magick -size 1024x192 xc:white mask_top.png
magick -size 1024x64 gradient:white-black mask_fade.png
magick mask_top.png mask_fade.png -append mask.png
magick crop.png mask.png -alpha off -compose CopyOpacity -composite \
  -define tga:compression=none HeaderStrip.tga
```

### Everything else: tools/skin-art/render.mjs

All other textures are drawn as SVG in `tools/skin-art/render.mjs` and rasterized with Chromium
(Playwright, borrowed from the website checkout), so every rim, chamfer and hairline is exact and
the set can be regenerated after a palette change:

```sh
node tools/skin-art/render.mjs [/path/to/website/website/package.json]
```

It writes `SideQuest/Media/Skin/<name>.tga` (32-bit truecolor, `-type TrueColorAlpha`) and
`tests/preview/tex/<name>.png`. Art is drawn at 2x: Skin.lua halves slice sizes on screen. Art
whose size isn't a power of two is placed in the top-left of the next power-of-two canvas and
cropped back in Lua with `SetTexCoord`.

The guild crest source for the seal and the portrait is `tools/skin-art/Crest.tga` (128x128),
made from `website/assets/brand/sidequest-logo.png` (959x1182):

```sh
magick website/assets/brand/sidequest-logo.png -resize 128x128 \
  -background none -gravity center -extent 128x128 -define tga:compression=none Crest.tga
```

| file | file size | art | use |
|---|---|---|---|
| Chamber.tga | 64x64 | 64x64 | 9-slice at 24 px: chamfered gilded rim, inner shadow, guild-gold-deep hairline |
| Ribbon.tga | 256x64 | 256x64 | 3-slice at 40 px: royal swallowtail ribbon with gold edge lines and a drop shadow |
| ButtonPrimary.tga | 128x64 | 128x48 | 3-slice at 16 px: royal body in a gilded rim |
| ButtonQuiet.tga | 128x64 | 128x48 | 3-slice at 16 px: night body in a bronze rim |
| ButtonGlow.tga | 128x64 | 128x48 | 3-slice at 16 px: hover light, drawn with ADD blending |
| FieldWell.tga | 128x64 | 128x48 | 3-slice at 16 px: sunken chamfered well for edit boxes |
| ScrollThumb.tga | 16x64 | 16x64 | the scrollbar thumb |
| Diamond.tga | 32x32 | 32x32 | faceted gold diamond: chamber corners, dividers, the officers' tab |
| Gem.tga | 32x32 | 32x32 | silver cabochon tinted per state (online/offline) |
| IconFrame.tga | 64x64 | 64x64 | silver chamfered frame tinted to an item's quality |
| Plate.tga | 64x64 | 48x48 | silver chamfered number plate tinted per raid-night step state |
| WaxSeal.tga | 128x128 | 128x128 | red wax seal with the crest pressed in: the raid-night stamp |
| CrestPortrait.tga | 128x128 | 128x128 | the crest on a royal disc, already round, for the portrait ring |

---

## Verification performed

Every TGA is power-of-two and 32-bit truecolor with alpha, checked from the raw header (byte 2 =
image type `02` truecolor, byte 16 = `20`, 32 bits per pixel):

```sh
for f in SideQuest/Media/Skin/*.tga; do
  echo "$f $(magick identify -format '%wx%h' "$f") type=$(xxd -s 2 -l 1 -p "$f") bpp=$(xxd -s 16 -l 1 -p "$f")"
done
```

All 14 files report `type=02 bpp=20`.

All TTF fonts confirmed to parse with fontTools:

```sh
python3 -c "from fontTools.ttLib import TTFont; TTFont('LibertinusSerifDisplay.ttf').close()"
python3 -c "from fontTools.ttLib import TTFont; TTFont('EBGaramond.ttf').close()"
python3 -c "from fontTools.ttLib import TTFont; TTFont('EBGaramond-Italic.ttf').close()"
```

## Total size

```sh
du -sh SideQuest/Media
```

```
1.8M  SideQuest/Media
```
