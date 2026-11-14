#!/usr/bin/env node
// Renders the captioned App Store screenshots (1320 x 2868, 6.9" iPhone) for every language.
//
// Input:  docs/store/raw/<shot>.png   plain app screenshots (ios/scripts/screenshots.sh + demo modes)
//         docs/store/captions.json    eyebrow + headline per shot and language (*text* = gold, | = line break)
// Output: docs/store/screenshots/<lang>/<n>-<shot>.png
//
// Needs macOS (New York / SF system fonts), Google Chrome and the `playwright` npm package
// (found via require, PLAYWRIGHT_PATH, or the npx cache of `npx @playwright/mcp`).
//
// Usage: ios/scripts/store-screenshots.mjs [lang ...]
import { createRequire } from 'node:module';
import { existsSync, mkdirSync, readdirSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const require = createRequire(import.meta.url);
function loadPlaywright() {
  const candidates = [process.env.PLAYWRIGHT_PATH, 'playwright'];
  const npx = join(homedir(), '.npm/_npx');
  if (existsSync(npx)) for (const d of readdirSync(npx)) candidates.push(join(npx, d, 'node_modules/playwright'));
  for (const c of candidates.filter(Boolean)) { try { return require(c); } catch {} }
  throw new Error('playwright not found: npm i -g playwright, or set PLAYWRIGHT_PATH');
}

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const STORE = join(ROOT, 'docs/store');
const W = 440, H = 956, SCALE = 3;

const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const headline = s => esc(s).replace(/\*(.+?)\*/g, '<em>$1</em>').replace(/\|/g, '<br>');

const page = (lang, eyebrow, title, img) => `<!doctype html><html lang="${lang}"><head><meta charset="utf-8"><style>
@font-face { font-family: "NY"; src: url("file:///System/Library/Fonts/NewYork.ttf"); font-weight: 100 900; }
@font-face { font-family: "SF"; src: url("file:///System/Library/Fonts/SFNS.ttf"); font-weight: 100 900; }
html, body { margin: 0; width: ${W}px; height: ${H}px; overflow: hidden; }
body {
  background:
    radial-gradient(120% 60% at 50% -8%, rgba(230,184,92,.30), rgba(230,184,92,0) 60%),
    radial-gradient(90% 50% at 50% 108%, rgba(230,184,92,.10), rgba(230,184,92,0) 70%),
    #0A0B0E;
  font-family: "SF", "Hiragino Sans", "PingFang SC", sans-serif; color: #F4EFE6;
  -webkit-font-smoothing: antialiased; text-align: center; position: relative;
}
.eyebrow { position: absolute; top: 66px; left: 0; right: 0; font-size: 12.5px; font-weight: 650;
  letter-spacing: .24em; text-transform: uppercase; color: #E6B85C; }
h1 { position: absolute; top: 90px; left: 30px; right: 30px; margin: 0;
  font-family: "NY", "Hiragino Mincho ProN", "Songti SC", serif; font-weight: 600;
  font-size: 38px; line-height: 1.1; letter-spacing: -.012em; text-wrap: balance; }
h1 em { font-style: normal; background: linear-gradient(180deg, #F3D08C, #E6B85C 55%, #C48E33);
  -webkit-background-clip: text; background-clip: text; color: transparent; }
.phone { position: absolute; left: 50%; top: 226px; width: 352px; transform: translateX(-50%);
  padding: 8px; border-radius: 54px; background: linear-gradient(160deg, #2A2D34, #15171B 40%, #1E2026);
  box-shadow: 0 40px 90px rgba(0,0,0,.7), 0 0 0 1px rgba(255,255,255,.09), inset 0 0 0 1px rgba(255,255,255,.05); }
.phone img { display: block; width: 100%; border-radius: 46px; }
</style></head><body>
<div class="eyebrow">${esc(eyebrow)}</div>
<h1 id="h"${title.includes('|') ? ' style="word-break: keep-all"' : ''}>${headline(title)}</h1>
<div class="phone"><img src="${img}"></div>
</body></html>`;

const spec = JSON.parse(readFileSync(join(STORE, 'captions.json'), 'utf8'));
const langs = process.argv.slice(2).length ? process.argv.slice(2) : Object.keys(spec.captions);
const { chromium } = loadPlaywright();
const browser = await chromium.launch({ channel: 'chrome', args: ['--allow-file-access-from-files'] });
const context = await browser.newContext({ viewport: { width: W, height: H }, deviceScaleFactor: SCALE });
const tab = await context.newPage();
for (const lang of langs) {
  const outDir = join(STORE, 'screenshots', lang);
  mkdirSync(outDir, { recursive: true });
  for (const [i, shot] of spec.shots.entries()) {
    const [eyebrow, title] = spec.captions[lang][i];
    const img = pathToFileURL(join(STORE, 'raw', `${shot}.png`)).href;
    // Load from a file:// origin so the system fonts and the screenshot can be read.
    await tab.goto(pathToFileURL(join(STORE, 'raw')).href + '/');
    await tab.setContent(page(lang, eyebrow, title, img), { waitUntil: 'load' });
    await tab.evaluate(async () => {
      await document.fonts.ready;
      const h = document.getElementById('h'); let fs = 38;   // keep the headline to two lines
      while (h.getBoundingClientRect().height > fs * 1.1 * 2 + 2 && fs > 22) { fs -= 1; h.style.fontSize = fs + 'px'; }
    });
    const out = join(outDir, `${i + 1}-${shot}.png`);
    await tab.screenshot({ path: out });
    console.log(out.slice(ROOT.length + 1));
  }
}
await browser.close();
