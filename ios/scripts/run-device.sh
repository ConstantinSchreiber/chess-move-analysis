#!/bin/zsh
# Builds a Release build, installs it on a connected iPhone and launches it.
# Release because Stockfish and the recognizer are much faster optimized.
#
# Usage:
#   ios/scripts/run-device.sh           # the first connected physical iPhone
#   ios/scripts/run-device.sh <UDID>    # a specific device (xcrun devicectl list devices)
#
# Needs: DEVELOPMENT_TEAM in project.yml (scripts/setup-signing.sh), the iPhone paired with this
# Mac and Developer Mode on (Settings → Privacy & Security → Developer Mode).
set -euo pipefail

IOS_DIR=$(cd "$(dirname "$0")/.." && pwd)
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
BUNDLE_ID=com.constantinschreiber.bestmove

UDID=${1:-}
if [[ -z "$UDID" ]]; then
  UDID=$(xcrun devicectl list devices 2>/dev/null \
    | awk '/physical/ && /iPhone/ { for (i = 1; i <= NF; i++) if ($i == "(UDID)") { print $(i-1); exit } }')
fi
if [[ -z "$UDID" ]]; then
  echo "No iPhone connected. Plug it in, unlock it and tap Trust." >&2
  exit 1
fi

cd "$IOS_DIR"
echo "Building for $UDID…"
xcodebuild build -project BestMove.xcodeproj -scheme BestMove -configuration Release \
  -destination "id=$UDID" -derivedDataPath build/device \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration -quiet

APP=build/device/Build/Products/Release-iphoneos/BestMove.app
echo "Installing…"
xcrun devicectl device install app --device "$UDID" "$APP" >/dev/null
echo "Launching…"
xcrun devicectl device process launch --device "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 \
  || echo "Installed. Unlock the iPhone and open Best Move."
