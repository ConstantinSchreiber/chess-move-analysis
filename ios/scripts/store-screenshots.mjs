#!/usr/bin/env node
// Renders the captioned App Store screenshots for every language:
//   iPhone 6.9" 1320 x 2868 -> docs/store/screenshots/<lang>/<n>-<shot>.png
//   iPad 13"    2064 x 2752 -> docs/store/screenshots-ipad/<lang>/<n>-<shot>.png
//
// Input:  docs/store/raw/<iphone|ipad>/<app-lang>/<shot>.png  the app's own screens in that language
//         (ios/scripts/store-raw.sh); falls back to the English raw/<iphone|ipad>/en, then raw/<shot>.png
//         docs/store/captions.json  eyebrow + headline per shot and language (*text* = gold, | = line break)
//
// Needs macOS (New York / SF system fonts), Google Chrome and the `playwright` npm package
// (found via require, PLAYWRIGHT_PATH, or the npx cache of `npx @playwright/mcp`).
//
// Usage: ios/scripts/store-screenshots.mjs [--device iphone|ipad|both] [lang ...]
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
// CSS size x scale = output pixels. Layout values are per device.
const DEVICES = {
  iphone: { W: 440, H: 956, scale: 3, out: 'screenshots', eyebrowTop: 66, eyebrowSize: 12.5, h1Top: 90, h1Size: 38, side: 30,
            frameTop: 226, frameWidth: 352, framePad: 8, frameRadius: 54, screenRadius: 46 },
  ipad:   { W: 1032, H: 1376, scale: 2, out: 'screenshots-ipad', eyebrowTop: 92, eyebrowSize: 19, h1Top: 128, h1Size: 62, side: 120,
            frameTop: 330, frameWidth: 820, framePad: 18, frameRadius: 52, screenRadius: 36 },
};
// Caption language -> app language of the raw screenshots.
const APP_LANG = { pt: 'pt-BR', zh: 'zh-Hans' };
// Right-to-left scripts: mirrored layout, SF Arabic, taller lines and no letter spacing (it would
// break the joined letters apart).
const RTL = new Set(['ar']);
const lineHeight = lang => (RTL.has(lang) ? 1.32 : 1.1);
let D = DEVICES.iphone, W = D.W, H = D.H;

const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const headline = s => esc(s).replace(/\*(.+?)\*/g, '<em>$1</em>').replace(/\|/g, '<br>');

const page = (lang, eyebrow, title, img) => `<!doctype html><html lang="${lang}"${RTL.has(lang) ? ' dir="rtl"' : ''}><head><meta charset="utf-8"><style>
@font-face { font-family: "NY"; src: url("file:///System/Library/Fonts/NewYork.ttf"); font-weight: 100 900; }
@font-face { font-family: "SF"; src: url("file:///System/Library/Fonts/SFNS.ttf"); font-weight: 100 900; }
@font-face { font-family: "SFArabic"; src: url("file:///System/Library/Fonts/SFArabic.ttf"); font-weight: 100 900; }
html, body { margin: 0; width: ${W}px; height: ${H}px; overflow: hidden; }
body {
  background:
    radial-gradient(120% 60% at 50% -8%, rgba(230,184,92,.30), rgba(230,184,92,0) 60%),
    radial-gradient(90% 50% at 50% 108%, rgba(230,184,92,.10), rgba(230,184,92,0) 70%),
    #0A0B0E;
  font-family: "SF", "Hiragino Sans", "PingFang SC", sans-serif; color: #F4EFE6;
  -webkit-font-smoothing: antialiased; text-align: center; position: relative;
}
.eyebrow { position: absolute; top: ${D.eyebrowTop}px; left: 0; right: 0; font-size: ${D.eyebrowSize}px; font-weight: 650;
  letter-spacing: .24em; text-transform: uppercase; color: #E6B85C; }
h1 { position: absolute; top: ${D.h1Top}px; left: ${D.side}px; right: ${D.side}px; margin: 0;
  font-family: "NY", "Hiragino Mincho ProN", "Songti SC", serif; font-weight: 600;
  font-size: ${D.h1Size}px; line-height: 1.1; letter-spacing: -.012em; text-wrap: balance; }
h1 em { font-style: normal; background: linear-gradient(180deg, #F3D08C, #E6B85C 55%, #C48E33);
  -webkit-background-clip: text; background-clip: text; color: transparent; }
.phone { position: absolute; left: 50%; top: ${D.frameTop}px; width: ${D.frameWidth}px; transform: translateX(-50%);
  padding: ${D.framePad}px; border-radius: ${D.frameRadius}px; background: linear-gradient(160deg, #2A2D34, #15171B 40%, #1E2026);
  box-shadow: 0 40px 90px rgba(0,0,0,.7), 0 0 0 1px rgba(255,255,255,.09), inset 0 0 0 1px rgba(255,255,255,.05); }
.phone img { display: block; width: 100%; border-radius: ${D.screenRadius}px; }
[dir=rtl] .eyebrow { font-family: "SFArabic", sans-serif; font-size: ${D.eyebrowSize * 1.28}px; font-weight: 600; letter-spacing: 0; top: ${D.eyebrowTop - 6}px; }
[dir=rtl] h1 { font-family: "SFArabic", sans-serif; font-weight: 700; line-height: ${lineHeight(lang)}; letter-spacing: 0; top: ${D.h1Top - 2}px; }
</style></head><body>
<div class="eyebrow">${esc(eyebrow)}</div>
<h1 id="h"${title.includes('|') ? ' style="word-break: keep-all"' : ''}>${headline(title)}</h1>
<div class="phone"><img src="${img}"></div>
</body></html>`;

const spec = JSON.parse(readFileSync(join(STORE, 'captions.json'), 'utf8'));
const argv = process.argv.slice(2);
const deviceArg = argv[0] === '--device' ? argv[1] : 'iphone';
const langs = (argv[0] === '--device' ? argv.slice(2) : argv);
const devices = deviceArg === 'both' ? ['iphone', 'ipad'] : [deviceArg];
const rawFor = (device, lang, shot) => [join(STORE, 'raw', device, APP_LANG[lang] || lang, `${shot}.png`),
  join(STORE, 'raw', device, 'en', `${shot}.png`), join(STORE, 'raw', `${shot}.png`)].find(existsSync);
const { chromium } = loadPlaywright();
const browser = await chromium.launch({ channel: 'chrome', args: ['--allow-file-access-from-files'] });
for (const device of devices) {
D = DEVICES[device]; W = D.W; H = D.H;
const context = await browser.newContext({ viewport: { width: W, height: H }, deviceScaleFactor: D.scale });
const tab = await context.newPage();
for (const lang of (langs.length ? langs : Object.keys(spec.captions))) {
  const outDir = join(STORE, D.out, lang);
  mkdirSync(outDir, { recursive: true });
  for (const [i, shot] of spec.shots.entries()) {
    const [eyebrow, title] = spec.captions[lang][i];
    const img = pathToFileURL(rawFor(device, lang, shot)).href;
    // Load from a file:// origin so the system fonts and the screenshot can be read.
    await tab.goto(pathToFileURL(join(STORE, 'raw')).href + '/');
    await tab.setContent(page(lang, eyebrow, title, img), { waitUntil: 'load' });
    await tab.evaluate(async ([lh, start]) => {
      await document.fonts.ready;
      const h = document.getElementById('h'); let fs = start;   // keep the headline to two lines
      while (h.getBoundingClientRect().height > fs * lh * 2 + 2 && fs > start * 0.58) { fs -= 1; h.style.fontSize = fs + 'px'; }
    }, [lineHeight(lang), D.h1Size]);
    const out = join(outDir, `${i + 1}-${shot}.png`);
    await tab.screenshot({ path: out });
    console.log(out.slice(ROOT.length + 1));
  }
}
await context.close();
}
await browser.close();
