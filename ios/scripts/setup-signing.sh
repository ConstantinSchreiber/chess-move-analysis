#!/bin/zsh
# Writes your Apple Developer Team ID into project.yml and regenerates the Xcode project.
#
# Usage:
#   ios/scripts/setup-signing.sh            # detect the team from Xcode (sign in first:
#                                           # Xcode → Settings → Accounts → + → Apple ID)
#   ios/scripts/setup-signing.sh ABCDE12345 # or pass the Team ID explicitly
#                                           # (developer.apple.com/account → Membership details)
set -euo pipefail

IOS_DIR=$(cd "$(dirname "$0")/.." && pwd)
SPEC="$IOS_DIR/project.yml"

detect_team() {
  # 1. Teams Xcode knows about. Paid teams win over free "Personal Team" entries.
  defaults export com.apple.dt.Xcode - 2>/dev/null | /usr/bin/python3 -c '
import plistlib, sys
try:
    prefs = plistlib.loads(sys.stdin.buffer.read())
except Exception:
    sys.exit(0)
found = []
def walk(node):
    if isinstance(node, dict):
        team = node.get("teamID")
        if isinstance(team, str) and len(team) == 10:
            found.append((bool(node.get("isFreeProvisioningTeam", False)), team, node.get("teamName", "")))
        for value in node.values():
            walk(value)
    elif isinstance(node, list):
        for value in node:
            walk(value)
walk(prefs)
paid = sorted({(t, n) for free, t, n in found if not free})
for team, name in paid:
    print(team, name, sep="\t")
'
}

TEAM=${1:-}
if [[ -z "$TEAM" ]]; then
  TEAMS=$(detect_team || true)
  COUNT=$(printf "%s" "$TEAMS" | grep -c . || true)
  if [[ "$COUNT" -eq 1 ]]; then
    TEAM=$(printf "%s" "$TEAMS" | cut -f1)
    echo "Using team $(printf "%s" "$TEAMS" | cut -f2) ($TEAM)"
  elif [[ "$COUNT" -gt 1 ]]; then
    echo "Several paid teams found — run again with the one you want:" >&2
    printf "%s\n" "$TEAMS" >&2
    exit 1
  else
    # 2. Fall back to the team in an installed Apple Development/Distribution certificate.
    TEAM=$(security find-certificate -a -c "Apple D" -p 2>/dev/null \
      | openssl x509 -noout -subject 2>/dev/null | sed -nE 's/.*OU ?= ?([A-Z0-9]{10}).*/\1/p' | head -1 || true)
    if [[ -z "$TEAM" ]]; then
      echo "No paid developer team found. Sign in to Xcode (Settings → Accounts) or pass the Team ID." >&2
      exit 1
    fi
    echo "Using team from signing certificate: $TEAM"
  fi
fi

[[ "$TEAM" =~ ^[A-Z0-9]{10}$ ]] || { echo "\"$TEAM\" doesn't look like a Team ID (10 characters)." >&2; exit 1; }

sed -i '' -E "s/^( *DEVELOPMENT_TEAM:).*/\1 \"$TEAM\"/" "$SPEC"
XCODEGEN=$(command -v xcodegen || echo /opt/homebrew/bin/xcodegen)
(cd "$IOS_DIR" && "$XCODEGEN" generate --quiet)
echo "DEVELOPMENT_TEAM set to $TEAM and BestMove.xcodeproj regenerated."
