#!/bin/zsh
# Makes the GitHub repo public and serves docs/ with GitHub Pages, which hosts the App Store
# support page and privacy policy:
#   https://constantinschreiber.github.io/chess-move-analysis/          (support URL)
#   https://constantinschreiber.github.io/chess-move-analysis/privacy.html (privacy policy URL)
#
# Required before the first App Store release: Best Move bundles Stockfish (GPLv3), so the
# complete source has to be available to everyone who gets the app.
set -euo pipefail

REPO=ConstantinSchreiber/chess-move-analysis

if [[ "$(gh repo view "$REPO" --json visibility --jq .visibility)" != "PUBLIC" ]]; then
  gh repo edit "$REPO" --visibility public --accept-visibility-change-consequences
  echo "✓ $REPO is now public"
fi

if ! gh api "repos/$REPO/pages" >/dev/null 2>&1; then
  gh api -X POST "repos/$REPO/pages" -f "source[branch]=main" -f "source[path]=/docs" >/dev/null
  echo "✓ GitHub Pages enabled (main:/docs)"
fi

echo "Waiting for the site to build…"
for i in {1..40}; do
  if curl -fsI "https://constantinschreiber.github.io/chess-move-analysis/privacy.html" >/dev/null 2>&1; then
    echo "✓ Live: https://constantinschreiber.github.io/chess-move-analysis/"
    exit 0
  fi
  sleep 15
done
echo "Pages is still building — check https://github.com/$REPO/settings/pages in a few minutes."
