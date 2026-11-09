#!/bin/sh
# Downloads the Stockfish NNUE network(s) the vendored engine expects.
#
#   ios/scripts/fetch-nnue.sh [destDir]      (default: ios/Tempo/Resources/NNUE)
#
# Net names are read from the vendored src/evaluate.h (`#define EvalFileDefaultName*`), so a
# Stockfish upgrade needs no edits here. Each file is verified against the SHA-256 prefix encoded
# in its name (nn-<first 12 hex of sha256>.nnue). Idempotent and silent when already up to date,
# so it can run as an Xcode pre-build phase (needs ENABLE_USER_SCRIPT_SANDBOXING=NO).
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
IOS_DIR=$(dirname "$SCRIPT_DIR")
EVAL_H="$IOS_DIR/Packages/StockfishKit/Sources/CStockfish/src/evaluate.h"
DEST=${1:-"$IOS_DIR/Tempo/Resources/NNUE"}

fail() {
    # "error:" prefix makes Xcode surface the message as a build error.
    echo "error: fetch-nnue: $*" >&2
    exit 1
}

[ -f "$EVAL_H" ] || fail "cannot find $EVAL_H"

NAMES=$(sed -n 's/^#define EvalFileDefaultName[A-Za-z]* *"\(nn-[0-9a-f]\{12\}\.nnue\)".*/\1/p' "$EVAL_H")
[ -n "$NAMES" ] || fail "no EvalFileDefaultName found in $EVAL_H"

# Stamps and partial downloads live outside DEST so they never end up in the app bundle.
WORK="$IOS_DIR/build/fetch-nnue"
mkdir -p "$DEST" "$WORK"

sha_prefix() {
    shasum -a 256 "$1" | cut -c1-12
}

for name in $NAMES; do
    expected=$(echo "$name" | sed 's/^nn-\([0-9a-f]*\)\.nnue$/\1/')
    target="$DEST/$name"

    if [ -f "$target" ]; then
        # Cheap check first: a stamp file records the size+mtime we last verified.
        stamp="$WORK/$name.verified"
        current=$(stat -f '%z-%m' "$target" 2>/dev/null || stat -c '%s-%Y' "$target")
        if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$current" ]; then
            continue
        fi
        if [ "$(sha_prefix "$target")" = "$expected" ]; then
            echo "$current" > "$stamp"
            continue
        fi
        echo "fetch-nnue: $name failed verification, re-downloading"
        rm -f "$target" "$WORK/$name.verified"
    fi

    tmp="$WORK/$name.download"
    ok=0
    for url in "https://tests.stockfishchess.org/api/nn/$name" \
               "https://github.com/official-stockfish/networks/raw/master/$name"; do
        echo "fetch-nnue: downloading $name from $url"
        if curl -fsSL --retry 3 --connect-timeout 15 -o "$tmp" "$url"; then
            if [ "$(sha_prefix "$tmp")" = "$expected" ]; then
                ok=1
                break
            fi
            echo "fetch-nnue: checksum mismatch for $url"
        fi
        rm -f "$tmp"
    done
    [ "$ok" = 1 ] || fail "could not download $name (offline?). Run ios/scripts/fetch-nnue.sh manually."

    mv "$tmp" "$target"
    current=$(stat -f '%z-%m' "$target" 2>/dev/null || stat -c '%s-%Y' "$target")
    echo "$current" > "$WORK/$name.verified"
    echo "fetch-nnue: $name ready ($(du -h "$target" | cut -f1))"
done
