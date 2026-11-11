#!/bin/zsh
# Captures App Store screenshots (6.9" iPhone) from the simulator using the app's debug launch
# arguments. Output: docs/screenshots/*.png
# Usage: ios/scripts/screenshots.sh [simulator-name]
set -euo pipefail

export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DEVICE_NAME=${1:-"iPhone 18 Pro Max"}
OUT="$ROOT/docs/screenshots"
DERIVED="$ROOT/ios/build/screenshots"
BUNDLE=com.constantinschreiber.bestmove
mkdir -p "$OUT"

UDID=$(xcrun simctl list devices available -j | /usr/bin/python3 -c "
import json, sys
devices = json.load(sys.stdin)['devices']
matches = [d for runtime, ds in sorted(devices.items(), reverse=True) if 'iOS' in runtime for d in ds if d['name'] == '$DEVICE_NAME']
print(matches[0]['udid'] if matches else '')")
[[ -n "$UDID" ]] || { echo "No simulator named $DEVICE_NAME" >&2; exit 1; }

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl status_bar "$UDID" override --time 9:41 --dataNetwork wifi --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

xcodebuild -project "$ROOT/ios/BestMove.xcodeproj" -scheme BestMove -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$DERIVED" build -quiet
xcrun simctl install "$UDID" "$DERIVED/Build/Products/Debug-iphonesimulator/BestMove.app"

shot() {
  local name=$1 wait=$2; shift 2
  xcrun simctl terminate "$UDID" $BUNDLE >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" $BUNDLE "$@" >/dev/null
  sleep "$wait"
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null
  echo "$OUT/$name.png"
}

# The first launch renders and caches the 3D hero; give it time.
shot 1-home 30
shot 2-review 8 -demoScan sample-photo
shot 3-analysis 14 -demoAnalysis "r1bq1rk1/pp1nbppp/2p1p3/3n2B1/2BP4/2N1PN2/PP3PPP/2RQK2R w K - 1 10"
shot 4-setup 6 -demoSetup
shot 5-settings 6 -demoSettings
xcrun simctl status_bar "$UDID" clear
