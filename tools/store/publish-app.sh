#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

usage() {
    echo "usage: bash tools/store/publish-app.sh <app> [--rev N] [--abi N] [--probe] [--dry]"
    echo "  builds /bin/<app>, adds it as a signed sysapp revision to the live system feed (kernel line untouched)"
    echo "  env: FEED_DIR (default /srv/store/osum) FEED_URL (default https://store.fleitec.com/osum) CHANNEL (default dev)"
    exit 2
}

[ $# -ge 1 ] || usage
APP=$1; shift
REV=""; ABI=1; PROBE=""; DRY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --rev) REV=$2; shift ;;
        --abi) ABI=$2; shift ;;
        --probe) PROBE=--probe ;;
        --dry) DRY=1 ;;
        *) usage ;;
    esac
    shift
done
FEED_DIR=${FEED_DIR:-/srv/store/osum}
FEED_URL=${FEED_URL:-https://store.fleitec.com/osum}
CHANNEL=${CHANNEL:-dev}
BUNDLE=${BUNDLE:-/root/.secrets/osum-ota-bund.json}
PASS_FILE=${PASS_FILE:-/root/.secrets/osum-ota-pass.txt}
LIST=$FEED_DIR/system/$CHANNEL/VERZEICHNIS
[ -f "$LIST" ] || { echo "publish-app: no live list at $LIST" >&2; exit 1; }

T0=$EPOCHREALTIME
WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT
. tools/lib/firnenv.sh
bash tools/sync/build.sh "$WORK" 0 "$APP" > "$WORK/build.log" 2>&1 || { tail -15 "$WORK/build.log"; echo "publish-app: build failed" >&2; exit 1; }
ELF=$WORK/$APP.elf
[ -s "$ELF" ] || { echo "publish-app: $APP.elf missing" >&2; exit 1; }
T1=$EPOCHREALTIME

if [ -z "$REV" ]; then
    CURRENT=$(awk -F'\t' -v n="$APP" '$1=="sysapp" && $2==n {print $3}' "$LIST" | head -1)
    REV=$(( ${CURRENT:-0} + 1 ))
fi
if [ "$DRY" = 1 ]; then
    COPY=$WORK/feed
    mkdir -p "$COPY/system/$CHANNEL"
    cp "$FEED_DIR/system/$CHANNEL/VERZEICHNIS" "$COPY/system/$CHANNEL/"
    TARGET=$COPY
else
    TARGET=$FEED_DIR
fi
OSUM_SIGN_PASS=$(cat "$PASS_FILE") python3 -I tools/ota/publish_app.py "$TARGET" "$CHANNEL" \
    --name "$APP" --elf "$ELF" --rev "$REV" --abi "$ABI" $PROBE --bund "$BUNDLE" || { echo "publish-app: publish failed" >&2; exit 1; }
T2=$EPOCHREALTIME

if [ "$DRY" = 0 ]; then
    python3 -I tools/ota/verify_feed.py "$FEED_URL" "$CHANNEL" || { echo "publish-app: live verification failed" >&2; exit 1; }
fi
T3=$EPOCHREALTIME
awk -v a="$T0" -v b="$T1" -v c="$T2" -v d="$T3" -v app="$APP" -v rev="$REV" \
    'BEGIN { printf "publish-app: %s rev %s build %.1f s, sign+write %.1f s, verify %.1f s, total %.1f s\n", app, rev, b-a, c-b, d-c, d-a }'
