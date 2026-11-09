# Publishing Tempo on the App Store

Everything that is needed to go from this repo to a live App Store listing, in order.
Items marked **(you)** need the account owner; everything else is prepared in the repo.

## 1. Accounts & machine

- **(you)** Apple Developer Program membership (99 USD/year) — https://developer.apple.com/programs/enroll/.
  Individual enrolment shows your legal name as the seller; an organisation needs a D-U-N-S number.
- **(you)** Update this Mac to macOS 15.6 or later and install **Xcode 26** from the App Store.
  Since April 2026 App Store Connect only accepts builds made with the iOS 26 SDK (Xcode 26+).
  The project builds with Xcode 16.2 today, so development is not blocked — only the upload is.
- **(you)** Sign in to Xcode with the developer Apple ID (Xcode → Settings → Accounts).

## 2. Project settings

- Team: set `DEVELOPMENT_TEAM` in `ios/project.yml` (or pick the team in Xcode → Signing & Capabilities)
  and regenerate with `xcodegen generate` in `ios/`.
- Bundle ID: `com.constantinschreiber.tempo` (change `PRODUCT_BUNDLE_IDENTIFIER` if you prefer another).
- Version: `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `ios/project.yml`.
- Display name: "Tempo". The App Store *listing* name must be unique store-wide — e.g.
  "Tempo – Chess Position Scanner". Check availability when creating the app record.

## 3. Licensing (important)

Stockfish is GPLv3. Shipping it inside an app means the whole app must be distributed under the
GPLv3 with its complete source available. The repo already carries the GPLv3 `LICENSE`, and the
in-app *Licenses* screen links to the source.

- **(you)** Before the first public release, make the GitHub repo public (or publish the source of
  each released version elsewhere). Several GPL chess apps (e.g. the lichess app, which bundles
  Stockfish) ship on the App Store this way.
- If you ever want a closed-source/commercial app, the engine must be swapped for a permissively
  licensed one (e.g. an MIT-licensed engine) and the GPL piece sets (cburnett, merida) for MIT/CC0 ones.

## 4. App Store Connect record

- Create the app: Platform iOS, name, primary language English, bundle ID from above, SKU `tempo-ios`.
- Category: **Reference** or **Board** (Games → Board requires the app to be a game; Reference/Utilities fits better).
- Age rating questionnaire: all "None" → 4+.
- Price: free (recommended for a GPL app) or paid.
- **App Privacy**: "Data Not Collected". Nothing leaves the device; there is no analytics SDK.
  `PrivacyInfo.xcprivacy` is included in the bundle.
- **Privacy policy URL** (required): `docs/privacy.md` can be published via GitHub Pages
  (Settings → Pages → deploy from `main` / `docs`) once the repo is public.
- Support URL: the GitHub repo or a simple page.
- Export compliance: `ITSAppUsesNonExemptEncryption = NO` is set in Info.plist (no prompt).

## 5. Screenshots & metadata

- Required: 6.9" iPhone screenshots (1320×2868 or 1290×2796). `ios/scripts/` will hold a script to
  capture them from the simulator.
- Subtitle idea: "Scan any board. Find the best move."
- Keywords idea: chess,scanner,stockfish,analysis,board,position,camera,fen,best move,engine
- Review notes for Apple: "Tap Scan position → Try a sample to test recognition without a camera."

## 6. Build & upload

1. In Xcode 26: select *Any iOS Device (arm64)* → Product → Archive.
2. Organizer → Distribute App → App Store Connect → Upload.
3. In App Store Connect: add the build to a TestFlight group, test on a real device, then
   submit for review.

## Known review risks

- **Guideline 4.2 (minimum functionality)** — not an issue: camera recognition + engine analysis.
- **Camera permission text** must explain the purpose (it does).
- **App size**: ~110 MB (Stockfish network ~98 MB). Fine; downloads over cellular up to 200 MB
  without a prompt.
