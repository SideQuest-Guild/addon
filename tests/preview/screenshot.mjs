// tests/preview/screenshot.mjs
// Screenshots every tests/preview/html/*.html page into tests/preview/out/*.png
// using Playwright (chromium), at a viewport sized to the view's declared
// stage size and scale (encoded in the filename / parsed out of the HTML).
// Playwright is resolved from the sidequest-guild website's node_modules
// (this addon repo does not have its own JS toolchain).
import { readdirSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";
import path from "node:path";

const WEBSITE_PKG = "/Users/coffee/git/public/sidequest-guild/website/website/package.json";
const requireFromWebsite = createRequire(WEBSITE_PKG);
const { chromium } = requireFromWebsite("playwright");
const here = path.dirname(fileURLToPath(import.meta.url));
const htmlDir = path.join(here, "html");

// --docs: capture just the window (no margin or caption) at 2x as JPEG for the views shown in the README, into
// docs/screenshots/. Otherwise capture every view, with its caption, into tests/preview/out/.
const DOCS = process.argv.includes("--docs");
const DOCS_VIEWS = ["you", "guild", "ledger", "console-raid-night", "console-loot", "bidpopup"];
const outDir = DOCS ? path.join(here, "..", "..", "docs", "screenshots") : path.join(here, "out");
mkdirSync(outDir, { recursive: true });

const files = readdirSync(htmlDir)
  .filter((f) => f.endsWith(".html"))
  .filter((f) => !DOCS || DOCS_VIEWS.includes(f.replace(/\.html$/, "")));

const browser = await chromium.launch();
const page = await browser.newPage({ deviceScaleFactor: DOCS ? 2 : 1 });

for (const file of files) {
  const name = file.replace(/\.html$/, "");
  const fileUrl = "file://" + path.join(htmlDir, file);
  await page.goto(fileUrl);
  const stage = await page.$(".stage");
  const box = await stage.boundingBox();
  await page.setViewportSize({
    width: Math.ceil(box.width) + 20,
    height: Math.ceil(box.height) + 40,
  });
  if (DOCS) {
    await stage.screenshot({ path: path.join(outDir, name + ".jpg"), type: "jpeg", quality: 85 });
  } else {
    await page.screenshot({ path: path.join(outDir, name + ".png") });
  }
  console.log("captured", name + ".png");
}

await browser.close();
console.log(`Done: ${files.length} screenshots in ${outDir}`);
