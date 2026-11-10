#!/bin/zsh
# Archives Best Move and uploads it to App Store Connect (TestFlight + App Store).
#
# Prerequisites (once):
#   1. Signed in to Xcode with your developer Apple ID (Xcode → Settings → Accounts).
#   2. ios/scripts/setup-signing.sh has set DEVELOPMENT_TEAM.
#   3. The app record exists in App Store Connect (bundle ID com.constantinschreiber.bestmove).
#
# Usage:
#   ios/scripts/release.sh            # archive + upload
#   ios/scripts/release.sh --export   # archive + export a signed .ipa only (no upload)
#
# Each run gets a fresh, increasing build number (yyDDDHHMM, UTC); the version comes from
# MARKETING_VERSION in project.yml.
set -euo pipefail

export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
IOS_DIR=$(cd "$(dirname "$0")/.." && pwd)
MODE=${1:-upload}
[[ "$MODE" == "--export" ]] && MODE=export
[[ "$MODE" == upload || "$MODE" == export ]] || { echo "Usage: $0 [--export]" >&2; exit 1; }

TEAM=$(sed -nE 's/^ *DEVELOPMENT_TEAM: *"?([A-Z0-9]{10})"?.*/\1/p' "$IOS_DIR/project.yml" | head -1)
[[ -n "$TEAM" ]] || { echo "DEVELOPMENT_TEAM is empty — run ios/scripts/setup-signing.sh first." >&2; exit 1; }

BUILD=$(date -u +%y%j%H%M)
VERSION=$(sed -nE 's/^ *MARKETING_VERSION: *"?([0-9.]+)"?.*/\1/p' "$IOS_DIR/project.yml" | head -1)
OUT="$IOS_DIR/build/release/$VERSION-$BUILD"
ARCHIVE="$OUT/BestMove.xcarchive"
mkdir -p "$OUT"

echo "▸ Archiving Best Move $VERSION ($BUILD) for team $TEAM…"
xcodebuild -project "$IOS_DIR/BestMove.xcodeproj" -scheme BestMove -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" CURRENT_PROJECT_VERSION="$BUILD" \
  archive -quiet

cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$MODE</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

if [[ "$MODE" == upload ]]; then
  echo "▸ Uploading to App Store Connect…"
else
  echo "▸ Exporting signed .ipa…"
fi
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$OUT" -allowProvisioningUpdates

if [[ "$MODE" == upload ]]; then
  echo "✓ Uploaded $VERSION ($BUILD). It appears in App Store Connect → TestFlight after processing (≈10–30 min)."
else
  echo "✓ Exported to $OUT"
fi
