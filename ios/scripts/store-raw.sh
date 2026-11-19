#!/bin/zsh
# Captures the raw App Store screenshots (the app's own screens, no captions) for every app
# language, on the 6.9" iPhone and the 13" iPad simulators, using the debug launch arguments.
#
# Output: docs/store/raw/<iphone|ipad>/<lang>/{hero,camera,review,analysis,setup,home}.png
# (gitignored; captions are added by ios/scripts/store-screenshots.mjs).
#
# Usage: ios/scripts/store-raw.sh [iphone|ipad|both] [lang ...]
#        langs default to every app language: en de fr es pt-BR it ru uk tr pl nl id ja zh-Hans ar
#        SHOTS="hero analysis" ios/scripts/store-raw.sh ipad   retakes only those shots
set -euo pipefail

export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DERIVED="$ROOT/ios/build/store-raw"
BUNDLE=com.constantinschreiber.bestmove
KIND=${1:-both}; shift || true
if (( $# )); then LANGS=("$@"); else LANGS=(en de fr es pt-BR it ru uk tr pl nl id ja zh-Hans ar); fi

typeset -A SIMULATOR=(iphone "iPhone 18 Pro Max" ipad "iPad Pro 13-inch (M5)")
typeset -A LOCALE=(en en_US de de_DE fr fr_FR es es_ES pt-BR pt_BR it it_IT ru ru_RU uk uk_UA tr tr_TR
                   pl pl_PL nl nl_NL id id_ID ja ja_JP zh-Hans zh_CN ar ar_SA)

HERO_FEN="4kb1r/p2n1ppp/4q3/4p1B1/4P3/1Q6/PPP2PPP/2KR4 w k - 1 16"        # Morphy's Opera Game, Qb8+ mates in 2
ANALYSIS_FEN="r1bq1rk1/pp1nbppp/2p1p3/3n2B1/2BP4/2N1PN2/PP3PPP/2RQK2R w K - 1 10"

udid_of() {
  xcrun simctl list devices available -j | /usr/bin/python3 -c "
import json, sys
devices = json.load(sys.stdin)['devices']
matches = [d for runtime, ds in sorted(devices.items(), reverse=True) if 'iOS' in runtime for d in ds if d['name'] == '$1']
print(matches[0]['udid'] if matches else '')"
}

capture_device() {
  local kind=$1 name=${SIMULATOR[$1]} udid
  udid=$(udid_of "$name")
  [[ -n "$udid" ]] || { echo "No simulator named $name" >&2; return 1; }
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
  xcodebuild -project "$ROOT/ios/BestMove.xcodeproj" -scheme BestMove -configuration Debug \
    -destination "platform=iOS Simulator,id=$udid" -derivedDataPath "$DERIVED" build -quiet
  local app="$DERIVED/Build/Products/Debug-iphonesimulator/BestMove.app"

  for lang in $LANGS; do
    local out="$ROOT/docs/store/raw/$kind/$lang"
    mkdir -p "$out"
    # Fresh install per language: empty history, so "Recent positions" shows this run's positions.
    xcrun simctl uninstall "$udid" $BUNDLE >/dev/null 2>&1 || true
    xcrun simctl install "$udid" "$app"
    shot() {
      local file=$1 wait=$2; shift 2
      [[ -z "${SHOTS:-}" || " $SHOTS " == *" $file "* ]] || return 0
      xcrun simctl terminate "$udid" $BUNDLE >/dev/null 2>&1 || true
      xcrun simctl launch "$udid" $BUNDLE -AppleLanguages "($lang)" -AppleLocale "${LOCALE[$lang]}" "$@" >/dev/null
      sleep "$wait"
      xcrun simctl io "$udid" screenshot "$out/$file.png" >/dev/null 2>&1
    }
    shot setup 7 -demoSetup
    shot review 9 -demoScan sample-photo
    shot analysis 14 -demoAnalysis "$ANALYSIS_FEN"
    shot hero 14 -demoAnalysis "$HERO_FEN"
    shot camera 8 -demoCamera sample-photo -demoCameraCenterX 0.333
    shot home 25          # the first plain launch renders the 3D hero
    echo "$kind/$lang"
  done
  xcrun simctl status_bar "$udid" clear
}

case $KIND in
  iphone|ipad) capture_device $KIND ;;
  both) capture_device iphone; capture_device ipad ;;
  *) echo "usage: $0 [iphone|ipad|both] [lang ...]" >&2; exit 1 ;;
esac
