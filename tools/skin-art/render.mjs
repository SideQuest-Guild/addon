// tools/skin-art/render.mjs
// Draws the addon's own skin textures as SVG and rasterizes them with Chromium (Playwright), so every rim, chamfer
// and hairline is exact and reproducible. Writes SideQuest/Media/Skin/<name>.tga (32-bit, what the game loads) and
// tests/preview/tex/<name>.png (what the layout preview loads).
//
// All art is drawn at 2x: a 64 px texture covers 32 UI units in game. Slice sizes in SideQuest/UI/Skin.lua are in
// these 2x pixels and halved on screen.
//
// Run from the addon repo root (needs ImageMagick's `magick` and the website checkout for Playwright):
//   node tools/skin-art/render.mjs [/path/to/website/package.json]
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..", "..");
const websitePkg =
  process.argv[2] ?? path.resolve(root, "..", "website", "website", "package.json");
const { chromium } = createRequire(websitePkg)("playwright");

const skinDir = path.join(root, "SideQuest", "Media", "Skin");
const previewDir = path.join(root, "tests", "preview", "tex");

// Palette (DESIGN.md): night ground, royal, guild gold and its metal ramp.
const P = {
  key: "#04070d",
  goldHi: "#f6e4b4",
  gold: "#d8ab5c",
  goldMid: "#b98d48",
  goldDeep: "#a88449",
  goldShade: "#5e4420",
  royalHi: "#4466ad",
  royal2: "#2e4a85",
  royal: "#22386a",
  royalLo: "#182a55",
  night: "#0a0f1a",
  night2: "#101a2c",
  night3: "#18253d",
  bronze: "#8f6d3a",
  bronzeHi: "#d2b072",
  bronzeShade: "#3c2c12",
};

// A rectangle with 45-degree chamfers, inset by `d` from a w x h box whose outer cut is `c` px along each axis.
// The inset polygon stays parallel to the outer one, so stacked strokes read as one bevelled rim.
function chamfer(w, h, c, d) {
  const k = c - d * (2 - Math.SQRT2);
  const pts = [
    [d + k, d], [w - d - k, d], [w - d, d + k], [w - d, h - d - k],
    [w - d - k, h - d], [d + k, h - d], [d, h - d - k], [d, d + k],
  ];
  return pts.map(([x, y]) => `${x.toFixed(2)},${y.toFixed(2)}`).join(" ");
}

function svg(w, h, body, defs = "") {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">` +
    `<defs>${defs}</defs>${body}</svg>`;
}

// A gilded rim: dark keyline outside, a lit outer edge, the gold body and a shaded inner edge.
function gildedRim(w, h, c, start, metal = { hi: P.goldHi, body: P.goldMid, shade: P.goldShade }) {
  return [
    `<polygon points="${chamfer(w, h, c, start + 0.5)}" fill="none" stroke="${P.key}" stroke-opacity=".9" stroke-width="1"/>`,
    `<polygon points="${chamfer(w, h, c, start + 2.5)}" fill="none" stroke="${metal.body}" stroke-width="3"/>`,
    `<polygon points="${chamfer(w, h, c, start + 1.5)}" fill="none" stroke="${metal.hi}" stroke-opacity=".85" stroke-width="1"/>`,
    `<polygon points="${chamfer(w, h, c, start + 3.5)}" fill="none" stroke="${metal.shade}" stroke-opacity=".9" stroke-width="1"/>`,
  ].join("");
}

// Inner shadow just inside a rim: fading 1px strokes, uniform along every edge so stretched slices stay seamless.
function innerShadow(w, h, c, start, alphas) {
  return alphas
    .map((a, i) => `<polygon points="${chamfer(w, h, c, start + i + 0.5)}" fill="none" stroke="#000" stroke-opacity="${a}" stroke-width="1"/>`)
    .join("");
}

const textures = [];

// Chamber: 64x64, 9-sliced at 24 px. Chamfered gilded rim, a soft inner shadow, and the site's guild-gold-deep
// hairline 10 px inside, parallel to the rim. The centre is empty; the frame's night fill shows through.
textures.push({
  name: "Chamber", w: 64, h: 64,
  svg: svg(64, 64,
    gildedRim(64, 64, 14, 0) +
    innerShadow(64, 64, 14, 5, [0.42, 0.26, 0.14, 0.06]) +
    `<polygon points="${chamfer(64, 64, 14, 10.5)}" fill="none" stroke="${P.goldDeep}" stroke-opacity=".7" stroke-width="1"/>`),
});

// Ribbon: 256x64, 3-sliced at 40 px. The site's royal swallowtail ribbon: a 44 px band with notched ends, gold edge
// lines just inside its top and bottom, a dark keyline and a soft shadow below.
{
  const band = "0,10 256,10 242,32 256,54 0,54 14,32";
  textures.push({
    name: "Ribbon", w: 256, h: 64,
    svg: svg(256, 64,
      `<g filter="url(#drop)"><polygon points="${band}" fill="url(#royal)"/></g>` +
      `<g clip-path="url(#bandClip)">` +
      `<rect x="0" y="10" width="256" height="9" fill="url(#gloss)"/>` +
      `<line x1="0" y1="14" x2="256" y2="14" stroke="${P.gold}" stroke-width="1.5" stroke-opacity=".95"/>` +
      `<line x1="0" y1="50" x2="256" y2="50" stroke="${P.gold}" stroke-width="1.5" stroke-opacity=".95"/>` +
      `</g>` +
      `<polygon points="${band}" fill="none" stroke="${P.key}" stroke-opacity=".85" stroke-width="1"/>`,
      `<linearGradient id="royal" x1="0" y1="10" x2="0" y2="54" gradientUnits="userSpaceOnUse">` +
      `<stop offset="0" stop-color="${P.royalHi}"/><stop offset=".5" stop-color="${P.royal2}"/><stop offset="1" stop-color="${P.royalLo}"/></linearGradient>` +
      `<linearGradient id="gloss" x1="0" y1="10" x2="0" y2="19" gradientUnits="userSpaceOnUse">` +
      `<stop offset="0" stop-color="#fff" stop-opacity=".16"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>` +
      `<clipPath id="bandClip"><polygon points="${band}"/></clipPath>` +
      `<filter id="drop" x="-10%" y="-30%" width="120%" height="160%"><feDropShadow dx="0" dy="3" stdDeviation="2.5" flood-color="#000" flood-opacity=".6"/></filter>`),
  });
}

// Buttons: 128x48, 3-sliced at 16 px. A 44 px chamfered body with a 2 px shadow underneath.
function button(name, fillStops, metal, gloss) {
  const body = chamfer(128, 46, 9, 1).split(" ").map((p) => p).join(" ");
  return {
    name, w: 128, h: 48,
    svg: svg(128, 48,
      `<g filter="url(#drop)"><polygon points="${body}" fill="url(#fill)"/></g>` +
      `<rect x="0" y="5" width="128" height="10" fill="url(#gloss)" clip-path="url(#bodyClip)"/>` +
      `<g transform="translate(0,0)">${gildedRim(128, 46, 9, 0, metal)}</g>`,
      `<linearGradient id="fill" x1="0" y1="0" x2="0" y2="46" gradientUnits="userSpaceOnUse">` +
      fillStops.map(([o, c]) => `<stop offset="${o}" stop-color="${c}"/>`).join("") + `</linearGradient>` +
      `<linearGradient id="gloss" x1="0" y1="5" x2="0" y2="15" gradientUnits="userSpaceOnUse">` +
      `<stop offset="0" stop-color="#fff" stop-opacity="${gloss}"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>` +
      `<clipPath id="bodyClip"><polygon points="${chamfer(128, 46, 9, 4)}"/></clipPath>` +
      `<filter id="drop" x="-5%" y="-20%" width="110%" height="150%"><feDropShadow dx="0" dy="1.5" stdDeviation="1" flood-color="#000" flood-opacity=".7"/></filter>`),
  };
}
textures.push(button("ButtonPrimary",
  [[0, P.royalHi], [0.5, P.royal2], [1, P.royalLo]],
  { hi: P.goldHi, body: P.goldMid, shade: P.goldShade }, 0.18));
textures.push(button("ButtonQuiet",
  [[0, "#1f2c46"], [0.55, P.night2], [1, "#0b111e"]],
  { hi: P.bronzeHi, body: P.bronze, shade: P.bronzeShade }, 0.08));

// Button hover light: the same silhouette as a warm inner glow, drawn with ADD blending over either button.
textures.push({
  name: "ButtonGlow", w: 128, h: 48,
  svg: svg(128, 48,
    `<polygon points="${chamfer(128, 46, 9, 5)}" fill="none" stroke="#f0cf86" stroke-width="5" filter="url(#soft)" clip-path="url(#inside)"/>` +
    `<polygon points="${chamfer(128, 46, 9, 2.5)}" fill="none" stroke="#f6e4b4" stroke-width="1.5" stroke-opacity=".9"/>`,
    `<filter id="soft"><feGaussianBlur stdDeviation="2.5"/></filter>` +
    `<clipPath id="inside"><polygon points="${chamfer(128, 46, 9, 3)}"/></clipPath>`),
});

// Field well: 128x48, 3-sliced at 16 px. A sunken chamfered well: near-black fill, shadow along the top, a stone
// keyline and a faint gold catch-light along the bottom.
textures.push({
  name: "FieldWell", w: 128, h: 48,
  svg: svg(128, 48,
    `<polygon points="${chamfer(128, 48, 8, 0.5)}" fill="#03060c" fill-opacity=".9"/>` +
    `<rect x="0" y="0" width="128" height="12" fill="url(#topShade)" clip-path="url(#well)"/>` +
    `<polygon points="${chamfer(128, 48, 8, 0.5)}" fill="none" stroke="#96acd2" stroke-opacity=".34" stroke-width="1"/>` +
    `<line x1="10" y1="45.5" x2="118" y2="45.5" stroke="${P.gold}" stroke-opacity=".28" stroke-width="1"/>`,
    `<linearGradient id="topShade" x1="0" y1="0" x2="0" y2="12" gradientUnits="userSpaceOnUse">` +
    `<stop offset="0" stop-color="#000" stop-opacity=".7"/><stop offset="1" stop-color="#000" stop-opacity="0"/></linearGradient>` +
    `<clipPath id="well"><polygon points="${chamfer(128, 48, 8, 1)}"/></clipPath>`),
});

// Scrollbar thumb: 16x64, 3-sliced vertically at 12 px. A slim gold bar with chamfered ends.
{
  const pts = "8,1 12,5 12,59 8,63 4,59 4,5";
  textures.push({
    name: "ScrollThumb", w: 16, h: 64,
    svg: svg(16, 64,
      `<polygon points="${pts}" fill="url(#metal)" stroke="${P.key}" stroke-opacity=".8" stroke-width="1"/>`,
      `<linearGradient id="metal" x1="4" y1="0" x2="12" y2="0" gradientUnits="userSpaceOnUse">` +
      `<stop offset="0" stop-color="${P.goldHi}"/><stop offset=".45" stop-color="${P.gold}"/><stop offset="1" stop-color="${P.goldShade}"/></linearGradient>`),
  });
}

// Diamond: 32x32. The site's diamond cut as a faceted gold jewel, lit from the top left.
textures.push({
  name: "Diamond", w: 32, h: 32,
  svg: svg(32, 32,
    `<polygon points="16,2 16,16 2,16" fill="${P.goldHi}"/>` +
    `<polygon points="16,2 30,16 16,16" fill="${P.gold}"/>` +
    `<polygon points="30,16 16,30 16,16" fill="${P.goldShade}"/>` +
    `<polygon points="16,30 2,16 16,16" fill="${P.goldMid}"/>` +
    `<polygon points="16,9 23,16 16,23 9,16" fill="${P.gold}" fill-opacity=".55"/>` +
    `<polygon points="16,1.5 30.5,16 16,30.5 1.5,16" fill="none" stroke="#1c1305" stroke-opacity=".85" stroke-width="1"/>`),
});

// Gem: 32x32 cabochon in neutral silver so SetVertexColor tints it (online green, offline grey).
textures.push({
  name: "Gem", w: 32, h: 32,
  svg: svg(32, 32,
    `<circle cx="16" cy="16" r="11" fill="url(#cab)" stroke="#000" stroke-opacity=".75" stroke-width="1.2"/>` +
    `<ellipse cx="12.5" cy="11.5" rx="4.5" ry="3" fill="#fff" fill-opacity=".85" filter="url(#soft)"/>`,
    `<radialGradient id="cab" cx=".4" cy=".35" r=".75"><stop offset="0" stop-color="#ffffff"/><stop offset=".55" stop-color="#cfcfcf"/><stop offset="1" stop-color="#5a5a5a"/></radialGradient>` +
    `<filter id="soft"><feGaussianBlur stdDeviation=".8"/></filter>`),
});

// Icon frame: 64x64, a chamfered metal rim in neutral silver so SetVertexColor
// tints it to the item's quality colour. The middle stays clear for the icon.
textures.push({
  name: "IconFrame", w: 64, h: 64,
  svg: svg(64, 64,
    `<polygon points="${chamfer(64, 64, 10, 0.5)}" fill="none" stroke="${P.key}" stroke-opacity=".9" stroke-width="1"/>` +
    `<polygon points="${chamfer(64, 64, 10, 3)}" fill="none" stroke="#e6e6e6" stroke-width="4"/>` +
    `<polygon points="${chamfer(64, 64, 10, 1.5)}" fill="none" stroke="#ffffff" stroke-width="1"/>` +
    `<polygon points="${chamfer(64, 64, 10, 4.5)}" fill="none" stroke="#7a7a7a" stroke-width="1"/>` +
    `<polygon points="${chamfer(64, 64, 10, 5.5)}" fill="none" stroke="#000" stroke-opacity=".6" stroke-width="1"/>`),
});

// Plate: 48x48, a chamfered metal plate in neutral light metal so
// SetVertexColor makes it gold (current), gold-deep (pending) or stone
// (done). Holds a step number.
textures.push({
  name: "Plate", w: 48, h: 48,
  svg: svg(48, 48,
    `<polygon points="${chamfer(48, 48, 10, 1)}" fill="url(#face)"/>` +
    `<polygon points="${chamfer(48, 48, 10, 0.5)}" fill="none" stroke="${P.key}" stroke-opacity=".9" stroke-width="1"/>` +
    `<polygon points="${chamfer(48, 48, 10, 2)}" fill="none" stroke="#ffffff" stroke-opacity=".7" stroke-width="1"/>` +
    `<polygon points="${chamfer(48, 48, 10, 3.5)}" fill="none" stroke="#000" stroke-opacity=".28" stroke-width="1.5"/>`,
    `<linearGradient id="face" x1="0" y1="0" x2="0" y2="48" gradientUnits="userSpaceOnUse">` +
    `<stop offset="0" stop-color="#ffffff"/><stop offset=".5" stop-color="#d9d9d9"/><stop offset="1" stop-color="#9c9c9c"/></linearGradient>`),
});

// Crest portrait: 128x128, the guild crest on a royal disc, already round so
// the native portrait ring frames it without a mask texture.
function crestPortrait(crestDataUri) {
  return svg(128, 128,
    `<circle cx="64" cy="64" r="63" fill="url(#disc)"/>` +
    `<image href="${crestDataUri}" x="25" y="13" width="78" height="96" preserveAspectRatio="xMidYMid meet" clip-path="url(#round)"/>` +
    `<circle cx="64" cy="64" r="60" fill="none" stroke="#000" stroke-opacity=".45" stroke-width="6" filter="url(#soft)"/>`,
    `<radialGradient id="disc" cx=".5" cy=".42" r=".6"><stop offset="0" stop-color="${P.royalHi}"/><stop offset=".7" stop-color="${P.royal}"/><stop offset="1" stop-color="${P.royalLo}"/></radialGradient>` +
    `<clipPath id="round"><circle cx="64" cy="64" r="62"/></clipPath>` +
    `<filter id="soft"><feGaussianBlur stdDeviation="3"/></filter>`);
}

// Wax seal: 128x128. An organic red wax disc (deterministic lobes), a raised rim, the guild crest pressed into the
// centre (debossed: dark silhouette with a light catch on its lower edge), a soft highlight and a drop shadow.
function waxSeal(crestDataUri) {
  const cx = 64, cy = 62, lobes = 180;
  const pts = [];
  for (let i = 0; i < lobes; i++) {
    const a = (i / lobes) * Math.PI * 2;
    const r = 50 + 2.6 * Math.sin(a * 7 + 0.6) + 1.6 * Math.sin(a * 13 + 2.1) + 1.1 * Math.sin(a * 23 + 4.0);
    pts.push(`${(cx + r * Math.cos(a)).toFixed(2)},${(cy + r * Math.sin(a)).toFixed(2)}`);
  }
  const blob = pts.join(" ");
  return svg(128, 128,
    `<g filter="url(#drop)"><polygon points="${blob}" fill="url(#wax)"/></g>` +
    `<circle cx="${cx}" cy="${cy}" r="39" fill="none" stroke="#3a0507" stroke-opacity=".55" stroke-width="3"/>` +
    `<circle cx="${cx}" cy="${cy}" r="41.5" fill="none" stroke="#e26a5c" stroke-opacity=".35" stroke-width="1.5"/>` +
    `<circle cx="${cx}" cy="${cy}" r="36" fill="url(#well)"/>` +
    `<image href="${crestDataUri}" x="${cx - 27}" y="${cy - 30 + 1.2}" width="54" height="60" filter="url(#catch)"/>` +
    `<image href="${crestDataUri}" x="${cx - 27}" y="${cy - 30}" width="54" height="60" filter="url(#press)"/>` +
    `<ellipse cx="46" cy="38" rx="20" ry="11" fill="#fff" fill-opacity=".09" filter="url(#blur)" transform="rotate(-28 46 38)"/>`,
    `<radialGradient id="wax" cx=".42" cy=".38" r=".7"><stop offset="0" stop-color="#c8392e"/><stop offset=".6" stop-color="#8f1a1b"/><stop offset="1" stop-color="#560a0d"/></radialGradient>` +
    `<radialGradient id="well" cx=".5" cy=".45" r=".6"><stop offset="0" stop-color="#9b1f1f"/><stop offset="1" stop-color="#6e1013"/></radialGradient>` +
    `<filter id="press"><feColorMatrix type="matrix" values="0 0 0 0 0.17  0 0 0 0 0.01  0 0 0 0 0.02  -.22 -.22 -.22 1.05 0"/></filter>` +
    `<filter id="catch"><feColorMatrix type="matrix" values="0 0 0 0 1  0 0 0 0 0.62  0 0 0 0 0.52  .55 .55 .55 0 0"/></filter>` +
    `<filter id="blur"><feGaussianBlur stdDeviation="4"/></filter>` +
    `<filter id="drop" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="3" stdDeviation="3" flood-color="#000" flood-opacity=".65"/></filter>`);
}

const work = mkdtempSync(path.join(tmpdir(), "sq-skin-"));
try {
  const crestPng = path.join(work, "crest.png");
  execFileSync("magick", [path.join(here, "Crest.tga"), crestPng]);
  const crestUri = "data:image/png;base64," + readFileSync(crestPng).toString("base64");
  textures.push({ name: "WaxSeal", w: 128, h: 128, svg: waxSeal(crestUri) });
  textures.push({ name: "CrestPortrait", w: 128, h: 128, svg: crestPortrait(crestUri) });

  const browser = await chromium.launch();
  const page = await browser.newPage({ deviceScaleFactor: 1 });
  // WoW loads power-of-two textures only. Art drawn at another size sits in
  // the top-left of the next power-of-two canvas; Skin.lua crops it back with
  // SetTexCoord (e.g. a 128x48 button lives in a 128x64 file, v 0..0.75).
  const pow2 = (n) => 2 ** Math.ceil(Math.log2(n));
  for (const t of textures) {
    await page.setViewportSize({ width: t.w, height: t.h });
    await page.setContent(`<!doctype html><html><body style="margin:0;background:transparent">${t.svg}</body></html>`);
    const png = path.join(work, `${t.name}.png`);
    await page.screenshot({ path: png, omitBackground: true, clip: { x: 0, y: 0, width: t.w, height: t.h } });
    const cw = pow2(t.w), ch = pow2(t.h);
    if (cw !== t.w || ch !== t.h) {
      execFileSync("magick", [png, "-background", "none", "-gravity", "NorthWest", "-extent", `${cw}x${ch}`, png]);
    }
    execFileSync("magick", [png, "-type", "TrueColorAlpha", "-define", "tga:image-type=2", path.join(skinDir, `${t.name}.tga`)]);
    execFileSync("magick", [png, path.join(previewDir, `${t.name}.png`)]);
    console.log(`${t.name}.tga ${cw}x${ch}${cw !== t.w || ch !== t.h ? ` (art ${t.w}x${t.h})` : ""}`);
  }
  await browser.close();
} finally {
  rmSync(work, { recursive: true, force: true });
}
