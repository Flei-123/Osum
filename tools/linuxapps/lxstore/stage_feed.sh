#!/usr/bin/env bash
# usage: stage_feed.sh <packages-dir> [--live]
set -euo pipefail
cd "$(dirname "$0")/../../.."
PKGS=${1:?packages dir}
LIVE_ROOT=${STORE_FEED_ROOT:-/srv/store/osum}
BUND=${OSUM_BUND:-/root/.secrets/osum-ota-bund.json}
PASS_FILE=${OSUM_PASS_FILE:-/root/.secrets/osum-ota-pass.txt}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/stand"
cp "$LIVE_ROOT"/aktuell/*.opk "$T/stand/"
cp "$PKGS"/*.opk "$T/stand/"
if [ "${2:-}" = "--live" ]; then OUT=$LIVE_ROOT; else OUT=$T/out; mkdir -p "$OUT"; cp "$LIVE_ROOT/register.json" "$OUT/"; fi
export OSUM_SIGN_PASS="$(head -1 "$PASS_FILE")" OSUM_ERSATZ_PASS="$(tail -1 "$PASS_FILE")"
python3 -I tools/ota/publish.py "$OUT" --stand "$T/stand" --bund "$BUND" --notiz "${STAGE_NOTE:-Linux apps}" < /dev/null
STORECAT_FEED="$OUT/aktuell" bash tools/storecat/run.sh
