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

const WEBSITE_PKG = "/Users/coffee/git/public/JacobCoffee/sidequest-guild/website/package.json";
const requireFromWebsite = createRequire(WEBSITE_PKG);
const { chromium } = requireFromWebsite("playwright");
const here = path.dirname(fileURLToPath(import.meta.url));
const htmlDir = path.join(here, "html");
const outDir = path.join(here, "out");
mkdirSync(outDir, { recursive: true });

const files = readdirSync(htmlDir).filter((f) => f.endsWith(".html"));

const browser = await chromium.launch();
const page = await browser.newPage();

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
  await page.screenshot({ path: path.join(outDir, name + ".png") });
  console.log("captured", name + ".png");
}

await browser.close();
console.log(`Done: ${files.length} screenshots in ${outDir}`);
