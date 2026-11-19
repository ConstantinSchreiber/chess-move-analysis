#!/usr/bin/env node
// App Store Connect from the command line, without an API key.
//
// Drives the App Store Connect web app's own JSON API (/iris/v1/..., same request and response
// shapes as the public App Store Connect API) from inside a Chrome window you are logged in to.
// The window uses its own Chrome profile and a local debugging port; the login lasts a day or two.
//
//   node ios/scripts/asc.cjs browser                 open the App Store Connect Chrome; log in there
//   node ios/scripts/asc.cjs status                  versions, builds, review submissions
//   node ios/scripts/asc.cjs new-version 1.1         create the next version (then build, metadata, submit)
//   node ios/scripts/asc.cjs build [number]          attach the newest valid build (or that build number)
//   node ios/scripts/asc.cjs metadata [locale,...]   push docs/store/metadata.json (texts, URLs, categories)
//   node ios/scripts/asc.cjs screenshots [iphone|ipad|both] [locale,...]
//                                                    replace the 6.9" iPhone / 13" iPad screenshots with
//                                                    docs/store/screenshots[-ipad]/<lang>/*.png (store-screenshots.mjs)
//   node ios/scripts/asc.cjs review-notes [file]     review notes from docs/store/review-notes.txt;
//                                                    optionally attach a file (e.g. a screen recording)
//   node ios/scripts/asc.cjs submit                  submit the editable version for review, or resubmit
//                                                    after App Review reported issues
//   node ios/scripts/asc.cjs api GET v1/apps/...     raw call; a body is JSON text or a .json file
//
// "Editable version" = the newest version that is not live. Needs Google Chrome, Node 18+ and the
// `playwright` npm package (found via require, PLAYWRIGHT_PATH, or the npx cache of `npx @playwright/mcp`).
const { spawn } = require('node:child_process');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const APP = '6834895609';
const PORT = 9333;
const PROFILE = process.env.ASC_CHROME_PROFILE || path.join(os.homedir(), 'Library/Application Support/BestMove-ASC-Chrome');
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const STORE = path.resolve(__dirname, '../../docs/store');
const SCREENSHOT_TYPES = {
  iphone: { type: 'APP_IPHONE_67', dir: 'screenshots' },             // 6.9" iPhone, 1320 x 2868
  ipad: { type: 'APP_IPAD_PRO_3GEN_129', dir: 'screenshots-ipad' },  // 13" iPad, 2064 x 2752
};
const LIVE = new Set(['READY_FOR_SALE', 'READY_FOR_DISTRIBUTION', 'REPLACED_WITH_NEW_VERSION',
  'REMOVED_FROM_SALE', 'DEVELOPER_REMOVED_FROM_SALE']);

function loadPlaywright() {
  const candidates = [process.env.PLAYWRIGHT_PATH, 'playwright'];
  const npx = path.join(os.homedir(), '.npm/_npx');
  if (fs.existsSync(npx)) for (const d of fs.readdirSync(npx)) candidates.push(path.join(npx, d, 'node_modules/playwright'));
  for (const c of candidates.filter(Boolean)) { try { return require(c); } catch {} }
  throw new Error('playwright not found: npm i -g playwright, or set PLAYWRIGHT_PATH');
}

const json = r => JSON.stringify(r, null, 1);
const errors = r => (r.json.errors || []).map(e => e.detail || e.title).join('; ') || JSON.stringify(r.json).slice(0, 400);
function check(what, r) {
  if (r.status >= 300) throw new Error(`${what}: HTTP ${r.status}: ${errors(r)}`);
  return r.json;
}
const list = arg => (arg ? arg.split(',') : null);

async function openBrowser() {
  try {
    if ((await fetch(`http://127.0.0.1:${PORT}/json/version`)).ok) {
      await fetch(`http://127.0.0.1:${PORT}/json/new?https://appstoreconnect.apple.com/apps`, { method: 'PUT' });
      return console.log('The App Store Connect Chrome is already running; opened a new tab in it.');
    }
  } catch {}
  fs.mkdirSync(PROFILE, { recursive: true });
  spawn(CHROME, [`--user-data-dir=${PROFILE}`, `--remote-debugging-port=${PORT}`, '--remote-debugging-address=127.0.0.1',
    '--no-first-run', '--no-default-browser-check', 'https://appstoreconnect.apple.com/apps'],
  { detached: true, stdio: 'ignore' }).unref();
  console.log('Log in to App Store Connect in the new Chrome window, then run the other commands.');
}

async function connect() {
  const { chromium } = loadPlaywright();
  let browser;
  try { browser = await chromium.connectOverCDP(`http://127.0.0.1:${PORT}`); } catch {
    throw new Error('The App Store Connect Chrome is not running: node ios/scripts/asc.cjs browser');
  }
  const context = browser.contexts()[0];
  let page = context.pages().find(p => p.url().startsWith('https://appstoreconnect.apple.com'));
  if (!page) {
    page = await context.newPage();
    await page.goto('https://appstoreconnect.apple.com/apps', { waitUntil: 'domcontentloaded' });
  }
  const call = (method, p, body) => page.evaluate(async ([method, p, body]) => {
    const res = await fetch(p.startsWith('http') ? p : '/iris/' + p.replace(/^\//, ''), {
      method, credentials: 'include', body: body ? JSON.stringify(body) : undefined,
      headers: { 'Content-Type': 'application/json', Accept: 'application/json',
        'X-Requested-With': 'XMLHttpRequest', 'X-Csrf-Itc': 'itc' } });
    const text = await res.text();
    let json; try { json = JSON.parse(text); } catch { json = text; }
    return { status: res.status, json };
  }, [method, p, body]);
  const probe = await call('GET', `v1/apps/${APP}?fields[apps]=name`);
  if (probe.status === 401 || probe.status === 403) {
    await browser.close().catch(() => {});
    throw new Error('Not logged in: log in to App Store Connect in the Chrome window (node ios/scripts/asc.cjs browser).');
  }
  return { browser, call };
}

async function editable(call) {
  const v = check('versions', await call('GET',
    `v1/apps/${APP}/appStoreVersions?limit=20&fields[appStoreVersions]=versionString,appStoreState,createdDate`));
  const ver = v.data.filter(d => !LIVE.has(d.attributes.appStoreState))
    .sort((a, b) => b.attributes.createdDate.localeCompare(a.attributes.createdDate))[0];
  if (!ver) throw new Error('No editable version: node ios/scripts/asc.cjs new-version <x.y>');
  const infos = check('app infos', await call('GET', `v1/apps/${APP}/appInfos`)).data;
  const info = infos.find(d => !LIVE.has(d.attributes.state || d.attributes.appStoreState)) || infos[0];
  return { ver: ver.id, version: ver.attributes.versionString, state: ver.attributes.appStoreState, info: info.id };
}

// docs/store/metadata.json: per locale name, subtitle, keywords, promo, description, optional
// whats_new; "same_as" copies another locale; "@en-US:analyse" = the en-US description in British spelling.
function localeData(M, loc) {
  let d = M.locales[loc];
  if (d.same_as) return localeData(M, d.same_as);
  d = { ...d };
  if ((d.description || '').startsWith('@en-US:analyse'))
    d.description = M.locales['en-US'].description.replace(/analyze/g, 'analyse').replace(/Analyze/g, 'Analyse');
  return d;
}

const commands = {
  async status(call) {
    const v = check('versions', await call('GET', `v1/apps/${APP}/appStoreVersions?limit=10&include=build` +
      '&fields[appStoreVersions]=versionString,appStoreState,createdDate,build&fields[builds]=version,processingState'));
    const builds = Object.fromEntries((v.included || []).map(b => [b.id, b.attributes]));
    for (const d of v.data) {
      const b = d.relationships.build.data && builds[d.relationships.build.data.id];
      console.log(`version ${d.attributes.versionString}: ${d.attributes.appStoreState}` +
        (b ? `, build ${b.version} (${b.processingState})` : ', no build attached'));
    }
    const s = check('submissions', await call('GET',
      `v1/apps/${APP}/reviewSubmissions?limit=5&fields[reviewSubmissions]=state,submittedDate`));
    for (const d of s.data) console.log(`review submission ${d.attributes.submittedDate || '(not submitted)'}: ${d.attributes.state}`);
  },

  async 'new-version'(call, versionString) {
    if (!versionString) throw new Error('Usage: new-version <x.y>');
    const M = JSON.parse(fs.readFileSync(path.join(STORE, 'metadata.json'), 'utf8'));
    const r = check('create version', await call('POST', 'v1/appStoreVersions', { data: { type: 'appStoreVersions',
      attributes: { platform: 'IOS', versionString, copyright: M.copyright, releaseType: 'AFTER_APPROVAL' },
      relationships: { app: { data: { type: 'apps', id: APP } } } } }));
    console.log(`created version ${versionString} (${r.data.id})`);
  },

  async build(call, number) {
    const { ver, version } = await editable(call);
    const b = check('builds', await call('GET', `v1/builds?filter[app]=${APP}&filter[preReleaseVersion.version]=${version}` +
      '&sort=-uploadedDate&limit=50&fields[builds]=version,processingState,uploadedDate'));
    const build = number ? b.data.find(d => d.attributes.version === number)
      : b.data.find(d => d.attributes.processingState === 'VALID');
    if (!build) throw new Error(`No ${number ? `build ${number}` : 'processed build'} for version ${version} yet (upload with ios/scripts/release.sh).`);
    check('attach build', await call('PATCH', `v1/appStoreVersions/${ver}/relationships/build`,
      { data: { type: 'builds', id: build.id } }));
    console.log(`version ${version}: build ${build.attributes.version} attached`);
  },

  async metadata(call, locales) {
    const M = JSON.parse(fs.readFileSync(path.join(STORE, 'metadata.json'), 'utf8'));
    const { ver, info, version } = await editable(call);
    const only = list(locales);
    const infoLocs = check('app info localizations', await call('GET', `v1/appInfos/${info}/appInfoLocalizations?limit=50`)).data;
    const verLocs = check('version localizations', await call('GET', `v1/appStoreVersions/${ver}/appStoreVersionLocalizations?limit=50`)).data;
    for (const loc of Object.keys(M.locales)) {
      if (only && !only.includes(loc)) continue;
      const d = localeData(M, loc);
      try {
        const ia = { name: d.name, subtitle: d.subtitle, privacyPolicyUrl: M.urls.privacy };
        const ie = infoLocs.find(x => x.attributes.locale === loc);
        check('app info localization', ie
          ? await call('PATCH', `v1/appInfoLocalizations/${ie.id}`, { data: { type: 'appInfoLocalizations', id: ie.id, attributes: ia } })
          : await call('POST', 'v1/appInfoLocalizations', { data: { type: 'appInfoLocalizations', attributes: { locale: loc, ...ia },
            relationships: { appInfo: { data: { type: 'appInfos', id: info } } } } }));
        // Creating an app info localization also creates an empty version localization.
        const ve = verLocs.find(x => x.attributes.locale === loc) || (ie ? null : (check('version localizations', await call('GET',
          `v1/appStoreVersions/${ver}/appStoreVersionLocalizations?limit=50`)).data.find(x => x.attributes.locale === loc)));
        const va = { description: d.description, keywords: d.keywords, promotionalText: d.promo,
          supportUrl: M.urls.support, marketingUrl: M.urls.marketing };
        if (d.whats_new && version !== '1.0') va.whatsNew = d.whats_new;
        check('version localization', ve
          ? await call('PATCH', `v1/appStoreVersionLocalizations/${ve.id}`, { data: { type: 'appStoreVersionLocalizations', id: ve.id, attributes: va } })
          : await call('POST', 'v1/appStoreVersionLocalizations', { data: { type: 'appStoreVersionLocalizations', attributes: { locale: loc, ...va },
            relationships: { appStoreVersion: { data: { type: 'appStoreVersions', id: ver } } } } }));
        console.log(loc, 'ok');
      } catch (e) { console.log(loc, 'FAILED', e.message); }
    }
    if (only) return;
    check('categories', await call('PATCH', `v1/appInfos/${info}`, { data: { type: 'appInfos', id: info, relationships: {
      primaryCategory: { data: { type: 'appCategories', id: 'UTILITIES' } },
      secondaryCategory: { data: { type: 'appCategories', id: 'EDUCATION' } } } } }));
    check('copyright', await call('PATCH', `v1/appStoreVersions/${ver}`, { data: { type: 'appStoreVersions', id: ver,
      attributes: { copyright: M.copyright, releaseType: 'AFTER_APPROVAL' } } }));
    console.log('categories, copyright, release type ok');
  },

  async screenshots(call, ...args) {
    const devices = ['iphone', 'ipad'].includes(args[0]) ? [args.shift()] : args[0] === 'both' ? (args.shift(), ['iphone', 'ipad']) : ['iphone', 'ipad'];
    for (const device of devices) await uploadScreenshots(call, SCREENSHOT_TYPES[device], list(args[0]));
  },
  async 'review-notes'(call, attachment) {
    const notes = fs.readFileSync(path.join(STORE, 'review-notes.txt'), 'utf8').trim();
    if (notes.length > 4000) throw new Error(`review notes are ${notes.length} characters; the limit is 4000`);
    const { ver } = await editable(call);
    let detail = check('review detail', await call('GET', `v1/appStoreVersions/${ver}/appStoreReviewDetail`)).data;
    if (!detail) {
      // A new version starts without App Review information: copy the contact from the newest earlier version.
      const v = check('versions', await call('GET', `v1/apps/${APP}/appStoreVersions?limit=20&fields[appStoreVersions]=createdDate`));
      let previous = null;
      for (const d of v.data.filter(d => d.id !== ver).sort((a, b) => b.attributes.createdDate.localeCompare(a.attributes.createdDate))) {
        previous = check('review detail', await call('GET', `v1/appStoreVersions/${d.id}/appStoreReviewDetail`)).data;
        if (previous) break;
      }
      if (!previous) throw new Error('No App Review information yet: fill in the contact once in App Store Connect.');
      const keep = ['contactFirstName', 'contactLastName', 'contactPhone', 'contactEmail', 'demoAccountRequired'];
      detail = check('create review detail', await call('POST', 'v1/appStoreReviewDetails', { data: { type: 'appStoreReviewDetails',
        attributes: Object.fromEntries(keep.map(k => [k, previous.attributes[k]])),
        relationships: { appStoreVersion: { data: { type: 'appStoreVersions', id: ver } } } } })).data;
      console.log('App Review contact copied from the previous version');
    }
    check('notes', await call('PATCH', `v1/appStoreReviewDetails/${detail.id}`,
      { data: { type: 'appStoreReviewDetails', id: detail.id, attributes: { notes } } }));
    console.log(`review notes updated (${notes.length} characters)`);
    if (attachment) {
      await upload(call, 'appStoreReviewAttachments', attachment, { appStoreReviewDetail: { data: { type: 'appStoreReviewDetails', id: detail.id } } });
      console.log(`attached ${path.basename(attachment)}`);
    }
  },

  async submit(call) {
    const { ver, version } = await editable(call);
    const subs = check('submissions', await call('GET',
      `v1/apps/${APP}/reviewSubmissions?limit=10&include=items&fields[reviewSubmissions]=state,items&fields[reviewSubmissionItems]=state`));
    const items = Object.fromEntries((subs.included || []).map(i => [i.id, i.attributes]));
    let sub = subs.data.find(s => s.attributes.state === 'UNRESOLVED_ISSUES') || subs.data.find(s => s.attributes.state === 'READY_FOR_REVIEW');
    if (sub) {
      // After App Review reported issues: mark the rejected items resolved, then submit again.
      for (const ref of sub.relationships.items.data || []) {
        if (items[ref.id] && items[ref.id].state === 'REJECTED')
          check('resolve item', await call('PATCH', `v1/reviewSubmissionItems/${ref.id}`,
            { data: { type: 'reviewSubmissionItems', id: ref.id, attributes: { resolved: true } } }));
      }
    } else {
      sub = check('create submission', await call('POST', 'v1/reviewSubmissions', { data: { type: 'reviewSubmissions',
        attributes: { platform: 'IOS' }, relationships: { app: { data: { type: 'apps', id: APP } } } } })).data;
      check('add version', await call('POST', 'v1/reviewSubmissionItems', { data: { type: 'reviewSubmissionItems', relationships: {
        reviewSubmission: { data: { type: 'reviewSubmissions', id: sub.id } },
        appStoreVersion: { data: { type: 'appStoreVersions', id: ver } } } } }));
    }
    const r = check('submit', await call('PATCH', `v1/reviewSubmissions/${sub.id}`,
      { data: { type: 'reviewSubmissions', id: sub.id, attributes: { submitted: true } } }));
    console.log(`version ${version}: ${r.data.attributes.state}`);
  },

  async api(call, method, p, body) {
    if (!method || !p) throw new Error('Usage: api METHOD path [json|file.json]');
    const payload = body ? JSON.parse(fs.existsSync(body) ? fs.readFileSync(body, 'utf8') : body) : undefined;
    console.log(json(await call(method.toUpperCase(), p, payload)));
  },
};

async function uploadScreenshots(call, kind, only) {
  const spec = JSON.parse(fs.readFileSync(path.join(STORE, 'captions.json'), 'utf8'));
  const { ver } = await editable(call);
  const locs = check('version localizations', await call('GET', `v1/appStoreVersions/${ver}/appStoreVersionLocalizations?limit=50`)).data;
  for (const loc of locs) {
    const locale = loc.attributes.locale;
    if (only && !only.includes(locale)) continue;
    const dir = path.join(STORE, kind.dir, spec.locale_language[locale] || 'en');
    if (!fs.existsSync(dir)) { console.log(locale, `skipped: ${dir} missing (run ios/scripts/store-screenshots.mjs)`); continue; }
    const files = fs.readdirSync(dir).filter(f => f.endsWith('.png')).sort();
    const sets = check('screenshot sets', await call('GET', `v1/appStoreVersionLocalizations/${loc.id}/appScreenshotSets?include=appScreenshots`));
    let set = sets.data.find(s => s.attributes.screenshotDisplayType === kind.type);
    if (set) for (const s of set.relationships.appScreenshots.data || []) await call('DELETE', `v1/appScreenshots/${s.id}`);
    else set = check('create set', await call('POST', 'v1/appScreenshotSets', { data: { type: 'appScreenshotSets',
      attributes: { screenshotDisplayType: kind.type },
      relationships: { appStoreVersionLocalization: { data: { type: 'appStoreVersionLocalizations', id: loc.id } } } } })).data;
    const done = [];
    for (const f of files) {
      try { await upload(call, 'appScreenshots', path.join(dir, f), { appScreenshotSet: { data: { type: 'appScreenshotSets', id: set.id } } }); done.push('ok'); }
      catch (e) { done.push(`${f} FAILED (${e.message})`); }
    }
    console.log(kind.type, locale, done.join(' '));
  }
}

// Reserve, upload the parts, commit with the MD5 checksum (screenshots, review attachments, ...).
async function upload(call, type, file, relationships) {
  const buf = fs.readFileSync(file);
  const asset = check(`reserve ${type}`, await call('POST', `v1/${type}`, { data: { type,
    attributes: { fileName: path.basename(file), fileSize: buf.length }, relationships } })).data;
  for (const op of asset.attributes.uploadOperations) {
    const headers = Object.fromEntries((op.requestHeaders || []).map(h => [h.name, h.value]));
    const res = await fetch(op.url, { method: op.method, headers, body: buf.subarray(op.offset, op.offset + op.length) });
    if (!res.ok) throw new Error(`upload part: HTTP ${res.status}`);
  }
  check(`commit ${type}`, await call('PATCH', `v1/${type}/${asset.id}`, { data: { type, id: asset.id,
    attributes: { uploaded: true, sourceFileChecksum: crypto.createHash('md5').update(buf).digest('hex') } } }));
  return asset.id;
}

(async () => {
  const [cmd, ...args] = process.argv.slice(2);
  if (cmd === 'browser') return openBrowser();
  if (!commands[cmd]) {
    console.log(fs.readFileSync(__filename, 'utf8').split('\n').slice(1, 22).map(l => l.replace(/^\/\/ ?/, '')).join('\n'));
    process.exitCode = cmd ? 1 : 0;
    return;
  }
  const { browser, call } = await connect();
  try { await commands[cmd](call, ...args); } finally { await browser.close().catch(() => {}); }
})().catch(e => { console.error(e.message); process.exitCode = 1; });
