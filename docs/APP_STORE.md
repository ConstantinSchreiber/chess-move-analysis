# Publishing Best Move

**Status (18 November 2026): LIVE.** Version 1.0 was approved on 18 November (18:05 CET) and is
on the App Store worldwide: https://apps.apple.com/us/app/best-move-chess-scanner-ai/id6834895609

History: version 1.0 (build 263181930, git tag `v1.0`) was submitted on 14 November. On 15 November App Review answered with **Guideline 2.1 – Information Needed** (not
a rejection of the app itself): they want a screen recording from a physical device, starting at
app launch, plus answers about purpose, usage, external services, regional differences and
third-party material. On 16 November the answers (`docs/store/review-notes.txt`) went into the
Notes field, a 20-second recording from the iPhone (camera background blurred: a password manager
was visible) into App Review Information → Attachment, and the version was **resubmitted: waiting
for review**. It is released automatically once approved.

Resubmitting through the API after "unresolved issues": PATCH the `reviewSubmissionItems` entry
with `resolved: true`, then PATCH the `reviewSubmissions` entry with `submitted: true`.

| | |
|---|---|
| App Store name | **Best Move: Chess Scanner AI** |
| Subtitle | **Stockfish Next Move Finder** |
| Home-screen name | Best Move |
| Apple ID (app) | 6834895609 · https://apps.apple.com/app/id6834895609 |
| Bundle ID | `com.constantinschreiber.bestmove` |
| SKU | `bestmove-ios` |
| Team | RP44S72CV4 (Constantin Schreiber, individual) |
| Category | Utilities, secondary Education |
| Price | Free, all 175 storefronts, new storefronts automatically |
| Age rating | 4+ (every questionnaire answer "none") |
| App Privacy | Data Not Collected (published) |
| EU DSA | non-trader (account level) |
| Support / marketing URL | https://constantinschreiber.github.io/chess-move-analysis/ |
| Privacy policy | https://constantinschreiber.github.io/chess-move-analysis/privacy.html |

## Where the listing lives

- `docs/store/metadata.json`: name, subtitle, keywords, promotional text and description for
  18 locales (en-US/GB/AU/CA, de, fr, es-ES/MX, pt-BR, it, ru, uk, tr, pl, nl, id, ja, zh-Hans).
  The app itself is English; the localized descriptions say so.
- `docs/store/captions.json` + `docs/store/raw/*.png`: the six App Store screenshots and their
  captions in 14 languages. `node ios/scripts/store-screenshots.mjs [lang…]` renders them to
  `docs/store/screenshots/<lang>/` (1320 × 2868, gitignored).
- Raw screenshots come from the simulator with the debug launch arguments
  (`ios/scripts/screenshots.sh`, plus `-demoCamera sample-photo -demoCameraCenterX 0.333` for the
  camera shot and `-demoAnalysis "4kb1r/p2n1ppp/4q3/4p1B1/4P3/1Q6/PPP2PPP/2KR4 w k - 1 16"` for
  the hero, Morphy's Opera Game).

### Search optimization notes

- The name and subtitle carry the strongest search weight: "chess scanner", "AI", "Stockfish",
  "next move", "best move", "finder". The keyword field adds analyzer, analysis, engine, solver,
  bot, helper, camera, photo, screenshot, position, board, fen, puzzle, tactics. Words in the
  name or subtitle are not repeated there.
- Other apps' names (Next Chess Move, Chessify, Chessvision…) must not be used anywhere in the
  metadata: guideline 2.3.7, rejection. The generic phrase "next chess move" is covered by
  "Chess" + "Next Move".
- Every locale has its own keywords in its language, so people searching in German, Spanish,
  Russian… find the app too.

## Releasing an update

1. Change the code, bump `MARKETING_VERSION` in `ios/project.yml` (e.g. 1.1), `xcodegen generate`
   in `ios/`.
2. `ios/scripts/release.sh` archives and uploads (Xcode account; no API key needed).
3. Add a `whats_new` text per locale to `docs/store/metadata.json` (locales with `same_as` copy it).
4. App Store Connect, either in the web UI (**+** new version → build → What's New → Add for
   Review → Submit) or with `ios/scripts/asc.cjs`:
   ```
   node ios/scripts/asc.cjs browser          # once per login; log in in that Chrome window
   node ios/scripts/asc.cjs new-version 1.1
   node ios/scripts/asc.cjs build            # after the upload has finished processing
   node ios/scripts/asc.cjs metadata         # texts incl. What's New
   node ios/scripts/asc.cjs screenshots      # only if the screenshots changed
   node ios/scripts/asc.cjs submit
   node ios/scripts/asc.cjs status
   ```
5. Tag the commit: `git tag -a v1.1 -m "…" && git push origin v1.1` (GPL: the source of every
   App Store build must be findable).

Changing listing text or screenshots does not need a new build while a version is being
prepared; promotional text can be changed any time. If App Review asks for information, update
`docs/store/review-notes.txt`, then `asc.cjs review-notes [recording.mov]` and `asc.cjs submit`.
App Review emails go to the account's Apple ID mail address.

## One-time setup (done)

- Xcode 27 signed in with the developer Apple ID; `ios/scripts/setup-signing.sh` wrote the team.
- iPhone registered for development; `ios/scripts/run-device.sh` builds, installs and launches
  a Release build on the connected phone.
- App record, listing, screenshots, age rating, App Privacy, pricing and availability, review
  contact and notes were filled in through App Store Connect.
- `ios/scripts/publish-source.sh` made the repo public and turned on GitHub Pages for `docs/`.

## App Review information

- Sign-in required: no. Contact: the same as for the account's other app.
- Notes:

```
No account is needed. To try the app without a chess board: tap "Scan position", then "Try a sample", pick one of the two samples and tap "Analyze". Best Move reads chess boards shown on screens (chess websites and apps) from the camera, Photos or a pasted image, and the Stockfish chess engine (GPLv3) runs on the device. The app makes no network requests of its own; the menu item "Open on lichess.org" opens Safari. Source code: https://github.com/ConstantinSchreiber/chess-move-analysis
```

## Review risks

- **Minimum functionality (4.2):** not an issue. Camera recognition and on-device engine analysis.
- **Fair play:** the description asks people not to use it in games against others.
- **"Stockfish" in the subtitle:** factual (the app ships Stockfish under its GPL licence) and
  common on the store. If a reviewer objects, change the subtitle to "Chess Engine Next Move Finder".
- **App size:** about 100 MB download, mostly the Stockfish network; under the 200 MB
  cellular-download limit.
- **GPL:** keep the repo public and tag every release.
