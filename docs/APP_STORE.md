# Publishing Best Move

From this repo to a live App Store listing. Steps marked **(you)** need you at the Mac or in a
browser. Everything else is scripted or already done.

| | |
|---|---|
| App Store name | **Best Move: Chess Scanner** |
| Home-screen name | Best Move |
| Bundle ID | `com.constantinschreiber.bestmove` |
| SKU | `bestmove-ios` |
| Version | 1.0 (`MARKETING_VERSION` in `ios/project.yml`) |
| Build number | set automatically by `release.sh` (UTC `yyDDDHHMM`) |
| Minimum iOS | 17.0, iPhone only |

## 1. One-time Mac setup (5 minutes)

1. **(you)** Open **Xcode 27** once. Click **Agree** on the license and enter your Mac password so it
   can install its components. When it asks which platforms to download, pick **iOS**.
2. **(you)** Xcode → Settings → **Accounts** → **+** → Apple ID. Sign in with the Apple account
   that holds the developer membership.
3. Run `ios/scripts/setup-signing.sh`. It finds your Team ID, writes it into `ios/project.yml`
   and regenerates `ios/BestMove.xcodeproj`. You can also pass the Team ID yourself; it is listed
   at developer.apple.com/account → Membership details.

## 2. Run it on your iPhone

1. Connect the iPhone with a cable and tap **Trust** on the phone.
2. On the iPhone, turn on Settings → Privacy & Security → **Developer Mode**. It only appears
   after the phone has been connected to Xcode, and the phone restarts to turn it on.
3. Open `ios/BestMove.xcodeproj`, choose your iPhone in the device menu at the top and press
   **Run** (⌘R). The first build takes a few minutes because Stockfish is compiled.

Running from Xcode registers the phone with your developer account. After the first time it also
works over Wi‑Fi.

## 3. Create the app in App Store Connect (5 minutes)

**(you)** Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → Apps → **+** →
New App:

- Platforms: **iOS**
- Name: **Best Move: Chess Scanner**
- Primary language: **English (U.S.)**
- Bundle ID: **com.constantinschreiber.bestmove**. It appears in the list after the app has been
  built once with your team (step 2). Otherwise register it at developer.apple.com →
  Identifiers → +.
- SKU: **bestmove-ios**
- User access: Full access

## 4. Upload a build

```sh
ios/scripts/release.sh
```

This archives a Release build and uploads it with your Xcode account. After 10–30 minutes of
processing it appears under **TestFlight**. Add yourself as an internal tester to install it
through the TestFlight app. `release.sh --export` only produces a signed `.ipa` and does not upload.

## 5. Publish the source and the support pages

```sh
ios/scripts/publish-source.sh
```

This makes the GitHub repo public and turns on GitHub Pages for `docs/`, which hosts:

- Support URL: https://constantinschreiber.github.io/chess-move-analysis/
- Privacy policy URL: https://constantinschreiber.github.io/chess-move-analysis/privacy.html

Why public: Stockfish is GPLv3, so the app's complete source code has to be available to everyone
who downloads it. The lichess app and other Stockfish-based apps on the App Store work the same way.
The repo carries the GPLv3 `LICENSE`, and the app's Settings → Licenses screen links to the source.
The repo history has been checked: no secrets and no personal files. The only email address in
it is your commit email, which your other public repos already show.

## 6. Fill in the listing

App Store Connect → your app → **App Store** tab → iOS App 1.0.

**Screenshots (6.9" display):** upload `docs/screenshots/1-home.png` … `5-settings.png`
(1320 × 2868). Apple scales them down for smaller iPhones.

**Promotional text** (can be changed at any time, ≤170):

> Point your camera at a chess board on any screen, or import a screenshot, and see the best move in seconds. Stockfish runs right on your iPhone, fully offline.

**Description:**

```
Stuck on a position? Point your camera at a chess board on your computer, tablet or TV, or import a screenshot. Best Move reads the position, works out whose turn it is, and shows you the strongest move in seconds.

SCAN
• The live camera finds the board and outlines it for you
• Import screenshots from Photos or paste an image
• Works with chess websites and apps on any screen

CONFIRM
• Reads every piece and works out whose move it is from the last-move highlight or a check
• Squares it isn't sure about are outlined, so you know what to double-check
• Compare with your photo and fix any piece with a tap
• Set castling rights, set up a position by hand or paste a FEN

ANALYZE
• Stockfish 19, one of the strongest chess engines in the world, runs right on your iPhone
• Best-move arrow, evaluation bar and up to five engine lines
• A plain-English summary of the best move
• Drag pieces to try your own ideas, and the engine follows every move
• Explore variations with a branching move list, step back and forward, flip the board

PRIVATE AND OFFLINE
• No account, no ads, no tracking
• Photos never leave your phone
• Works without an internet connection

OPEN SOURCE
Best Move is free software under the GNU General Public License v3. The source code is on GitHub.
```

**Keywords** (≤100, the words in the name and subtitle are indexed already):

```
analysis,analyzer,engine,position,camera,screenshot,photo,fen,tactics,puzzle,checkmate,solver,coach
```

- **Support URL:** https://constantinschreiber.github.io/chess-move-analysis/
- **Marketing URL:** leave empty, or use the support URL
- **Version / Copyright:** 1.0 / `2026 Constantin Schreiber`
- **Build:** pick the uploaded build. The encryption question is already answered in Info.plist.

**App Review information:**

- Sign-in required: **No**
- Contact: your name, phone and email. Apple sees these; they are not public.
- Notes:

```
No account is needed. To try the app without a chess board: tap "Scan position", then "Try a sample", pick one of the two samples and tap "Analyze". Best Move reads chess boards shown on screens (chess websites and apps) from the camera, Photos or a pasted image. The Stockfish engine runs on the device; the app makes no network requests (the menu item "Open on lichess.org" opens Safari). The app is open source under GPLv3: https://github.com/ConstantinSchreiber/chess-move-analysis
```

## 7. App-level settings

- **App Information** → Subtitle: **Scan any board. Get the move.**
- **App Information** → Category: Primary **Games**, subcategories **Board** and **Strategy**.
  Most chess scanners and analysis apps are listed there. Secondary category: **Education**.
- **App Information** → Age rating: answer **No / None** to everything (there is no web view,
  no user content and no purchases). The result is the lowest rating, 4+.
- **App Information** → Digital Services Act (EU): declare **not a trader**. That fits if the app
  is free and you don't earn money from it. Without this declaration the app is not shown in EU
  storefronts.
- **App Privacy** → Privacy Policy URL (above) → Data collection: **No, we do not collect data
  from this app**.
- **Pricing and Availability** → Price: **Free** → all countries and regions.

Then go back to the version page → **Add for Review** → **Submit**. Review usually takes 1–2 days.

## Later releases

1. Bump `MARKETING_VERSION` in `ios/project.yml` (e.g. 1.1) and run `xcodegen generate` in `ios/`.
2. `ios/scripts/release.sh`
3. App Store Connect → **+** new version → pick the build → What's New → Submit.

## Review risks

- **Minimum functionality (4.2):** not an issue. The app does camera recognition and on-device
  engine analysis.
- **Camera permission text:** it explains the purpose.
- **App size:** about 120 MB, mostly the Stockfish network. That is under the 200 MB limit for
  downloading over mobile data without asking.
- **GPL:** keep the repo public. Tag every release (`git tag v1.0`) so the exact source of each
  App Store build is easy to find.
