#!/bin/sh
# Run a script from a frozen copy of ml/ code so edits during long runs can't leak into spawned workers.
# usage: scripts/run_frozen.sh <run-name> scripts/train.py args...
set -e
ML="$(cd "$(dirname "$0")/.." && pwd)"
NAME="$1"; shift
SNAP="$ML/.cache/runs/$NAME"
rm -rf "$SNAP"; mkdir -p "$SNAP"
cp -R "$ML/tempo_vision" "$ML/scripts" "$SNAP/"
export TEMPO_ML_CACHE="$ML/.cache"
cd "$ML"
SCRIPT="$1"; shift
exec "$ML/.venv/bin/python" "$SNAP/$SCRIPT" "$@"
