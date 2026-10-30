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

## Textures/

Source room paintings: `website/assets/rooms/*.webp` (8 files). Dimensions checked via
`magick identify -format "%f: %wx%h\n" *.webp`:

```
armory.webp: 1698x926        hall-of-heroes.webp: 1698x926
great-hall.webp: 1536x1024    ledger-chamber.webp: 1698x926
muster-yard.webp: 1536x1024   raid-hall.webp: 1698x926
round-table.webp: 1698x926    war-room.webp: 1698x926
```

(Note: the assignment described these as `*.png`; the actual files on disk are `*.webp` — used
as-is, same content role.) `raid-hall.webp` was chosen for `HeaderStrip.tga`: at 1698x926
(~1.83:1) it is tied for the widest aspect ratio among the available paintings, and depicts an
open hall interior (no single dominant foreground figure), so a 1024x256 (4:1) crop from its
upper-middle band reads as atmospheric architectural detail rather than cutting through a face or
character — well suited to sit behind a UI header ribbon.

### Crest.tga

Source: `website/assets/brand/sidequest-logo.png` (959x1182, sRGB + alpha). Resized to fit within
128x128 and padded to exactly 128x128 with a transparent background (power-of-two, alpha
preserved):

```sh
magick website/assets/brand/sidequest-logo.png \
  -resize 128x128 \
  -background none -gravity center -extent 128x128 \
  -define tga:compression=none \
  Crest.tga
```

### HeaderStrip.tga

Source: `website/assets/rooms/raid-hall.webp` (1698x926). Resized to 1024px width, cropped to a
1024x256 strip from the upper-middle region (avoids the floor and avoids being cropped straight
off the top edge), then the bottom ~25% (64 of 256px) is faded to transparent via a generated
alpha mask (top 192px solid white = fully opaque, bottom 64px linear white→black gradient =
fade-to-transparent), applied with `-compose CopyOpacity` per DESIGN.md's edge-mask technique:

```sh
magick website/assets/rooms/raid-hall.webp -resize 1024x -gravity North -crop 1024x256+0+120 +repage crop.png

magick -size 1024x192 xc:white mask_top.png
magick -size 1024x64 gradient:white-black mask_fade.png
magick mask_top.png mask_fade.png -append mask.png

magick crop.png mask.png -alpha off -compose CopyOpacity -composite \
  -define tga:compression=none HeaderStrip.tga
```

### RibbonEndCapLeft.tga / RibbonEndCapRight.tga

Authored (no external source). 64x64, royal (#22386a) fill with gold-deep (#a88449) 1px top/bottom
lines, trimmed to the shape's horizontal span, and a triangular notch cut into the outward-facing
short edge (left edge for the left cap, right edge for the right cap) via a single concave filled
polygon. `-define tga:image-type=2` forces genuine 32bpp truecolor+alpha storage (verified via raw
header bytes, since `magick identify`'s "Type" field is a heuristic based on unique-color count
and otherwise misreports these low-color-count images as "PaletteAlpha" even though the file is
stored as full truecolor):

```sh
magick -size 64x64 xc:none \
  -fill "#22386a" -draw "polygon 12,0 63,0 63,63 12,63 0,32" \
  -fill "#a88449" -draw "line 12,0 63,0" \
  -fill "#a88449" -draw "line 12,63 63,63" \
  -define tga:image-type=2 -define tga:compression=none RibbonEndCapLeft.tga

magick -size 64x64 xc:none \
  -fill "#22386a" -draw "polygon 0,0 51,0 63,32 51,63 0,63" \
  -fill "#a88449" -draw "line 0,0 51,0" \
  -fill "#a88449" -draw "line 0,63 51,63" \
  -define tga:image-type=2 -define tga:compression=none RibbonEndCapRight.tga
```

### CornerBracket.tga

Authored (no external source). 64x64, gold (#d8ab5c) 1px stroke L-shaped bracket (vertical arm
along the left edge, horizontal arm along the top edge) whose inner corner is chamfered (cut
corner) instead of meeting at a sharp right angle, plus a small solid gold diamond filling that
chamfered joint. Meant to be rotated/flipped by the Lua UI code to serve all four chamber corners:

```sh
magick -size 64x64 xc:none -strokewidth 1 -stroke "#d8ab5c" -fill none \
  -draw "path 'M 0,48 L 0,6 L 6,0 L 48,0'" \
  -fill "#d8ab5c" -draw "polygon 3,0 6,3 3,6 0,3" \
  -define tga:compression=none CornerBracket.tga
```

### Diamond.tga

Authored (no external source). 32x32, small solid gold (#d8ab5c) rotated-square (diamond) mark,
transparent background:

```sh
magick -size 32x32 xc:none \
  -fill "#d8ab5c" -draw "polygon 16,2 30,16 16,30 2,16" \
  -define tga:compression=none Diamond.tga
```

---

## Verification performed

All TGA outputs confirmed 32-bit (truecolor + 8-bit alpha, 32 bits/pixel) and power-of-two
dimensioned by inspecting the raw TGA header (byte 2 = image type, byte 16 = bits-per-pixel):

```sh
for f in *.tga; do
  dims=$(magick identify -format "%wx%h" "$f")
  echo "$f: $dims"; xxd -l 18 "$f"
done
```

| file | dimensions | image type (byte 2) | bits/pixel (byte 16) |
|---|---|---|---|
| Crest.tga | 128x128 | `02` (truecolor) | `20` (32) |
| HeaderStrip.tga | 1024x256 | `02` | `20` |
| RibbonEndCapLeft.tga | 64x64 | `02` | `20` |
| RibbonEndCapRight.tga | 64x64 | `02` | `20` |
| CornerBracket.tga | 64x64 | `02` | `20` |
| Diamond.tga | 32x32 | `02` | `20` |

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
1.3M  SideQuest/Media
```
