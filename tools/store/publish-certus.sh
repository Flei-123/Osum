#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

usage() {
    echo "usage: bash tools/store/publish-certus.sh [--force] [--dry] [--gate-log FILE --elf FILE]"
    echo "  publishes the current Certus main as the OrientOS system app of the live store when it changed"
    echo "  gate: tools/browserdef/run.sh with BROWSERDEF_REAL=1 must end with 0 failed, otherwise nothing is touched"
    echo "  env: CERTUS_REPO STORE_REPO STORE_TOOLS FEED_DIR STATE_DIR BACKUP_ROOT"
    exit 2
}

FORCE=0; DRY=0; GATE_LOG=""; ELF=""
while [ $# -gt 0 ]; do
    case "$1" in
        --force) FORCE=1 ;;
        --dry) DRY=1 ;;
        --gate-log) GATE_LOG=$2; shift ;;
        --elf) ELF=$2; shift ;;
        *) usage ;;
    esac
    shift
done

CERTUS_REPO=${CERTUS_REPO:-/root/certus-ui}
STORE_REPO=${STORE_REPO:-/srv/store}
STORE_TOOLS=${STORE_TOOLS:-/root/orientstore/werkzeug}
FEED_DIR=${FEED_DIR:-$STORE_REPO/osum}
CHANNEL=${CHANNEL:-dev}
STATE_DIR=${STATE_DIR:-/var/lib/orientstore/autorelease}
BACKUP_ROOT=${BACKUP_ROOT:-/root/orientstore/bau}
HEAVY=${HEAVY:-/root/jarvis/bin/heavy}
APP_ID=com.fleitec.certus
APP_NAME=certus
GATE=tools/browserdef/run.sh
STATE_FILE=$STATE_DIR/certus-published.head
FEED_LIST=$FEED_DIR/system/$CHANNEL

die() { echo "publish-certus: $*" >&2; exit 1; }

[ -e "$CERTUS_REPO/.git" ] || die "no Certus checkout at $CERTUS_REPO"
HEAD_ID=$(git -C "$CERTUS_REPO" rev-parse HEAD)
SHORT=$(git -C "$CERTUS_REPO" rev-parse --short=9 HEAD)
VERSION=$(sed -n 's/.*android:versionName="\([^"]*\)".*/\1/p' "$CERTUS_REPO/android/AndroidManifest.xml" | head -1)
[ -n "$VERSION" ] || die "no versionName in $CERTUS_REPO/android/AndroidManifest.xml"
if [ "$FORCE" = 0 ] && [ -f "$STATE_FILE" ] && [ "$(cat "$STATE_FILE")" = "$HEAD_ID" ]; then
    echo "publish-certus: Certus $SHORT already published"
    exit 0
fi

WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT

if [ -z "$ELF" ]; then
    ELF=$WORK/certus.elf
    "$HEAVY" bash tools/store/builders/certus.sh "$ELF" > "$WORK/build.log" 2>&1 || { tail -5 "$WORK/build.log"; die "build failed"; }
fi
[ -s "$ELF" ] || die "no Certus ELF"
ELF_SHA=$(sha256sum "$ELF" | cut -c1-64)
if [ -z "$GATE_LOG" ]; then
    GATE_LOG=$WORK/gate.log
    CERTUS=$ELF BROWSERDEF_REAL=1 "$HEAVY" bash "$GATE" > "$GATE_LOG" 2>&1 || true
fi
SUMMARY=$(grep -a '^BROWSERDEF: ' "$GATE_LOG" | tail -1 || true)
echo "$SUMMARY" | grep -q ' 0 failed' || die "gate not green (${SUMMARY:-no summary}); live store untouched"
PASSED=$(echo "$SUMMARY" | sed -n 's/^BROWSERDEF: \([0-9]*\) passed.*/\1/p')
[ "${PASSED:-0}" -gt 0 ] || die "gate ran no checks; live store untouched"
[ "$(git -C "$CERTUS_REPO" rev-parse HEAD)" = "$HEAD_ID" ] || die "Certus main moved during the gate; run again"
[ "$DRY" = 0 ] || { echo "publish-certus: dry run ok ($SUMMARY, Certus $SHORT, version $VERSION)"; exit 0; }

mkdir -p "$STATE_DIR"
exec 9>>"$STATE_DIR/lock"
flock -n 9 || die "another store run is active"

BACKUP=$BACKUP_ROOT/live-backup-$(date +%Y%m%d-%H%M%S)-certus
mkdir -p "$BACKUP/feed"
for f in apps.tsv apps.tsv.sig index.json index.json.sig entry.json entry.json.sig; do
    cp -p "$STORE_REPO/$f" "$BACKUP/$f"
done
for f in VERZEICHNIS VERZEICHNIS.sig LISTING LISTING.sig; do
    [ ! -f "$FEED_LIST/$f" ] || cp -p "$FEED_LIST/$f" "$BACKUP/feed/$f"
done
cp -p "$STORE_TOOLS/unified_system/system_apps.json" "$STORE_TOOLS/compat.json" "$BACKUP/"

restore() {
    cp -p "$BACKUP"/apps.tsv "$BACKUP"/apps.tsv.sig "$BACKUP"/index.json "$BACKUP"/index.json.sig \
        "$BACKUP"/entry.json "$BACKUP"/entry.json.sig "$STORE_REPO/"
    cp -p "$BACKUP"/feed/* "$FEED_LIST/"
    cp -p "$BACKUP/system_apps.json" "$STORE_TOOLS/unified_system/system_apps.json"
    cp -p "$BACKUP/compat.json" "$STORE_TOOLS/compat.json"
    echo "publish-certus: restored $BACKUP" >&2
}

FEED_REV=$(awk -F'\t' -v n="$APP_NAME" '$1=="sysapp" && $2==n {print $3}' "$FEED_LIST/VERZEICHNIS" | head -1)
CATALOG_REV=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["apps"][sys.argv[2]].get("revision", 0))' \
    "$STORE_TOOLS/unified_system/system_apps.json" "$APP_ID")
NEXT_REV=$(( $(printf '%s\n' "${FEED_REV:-0}" "$CATALOG_REV" | sort -n | tail -1) + 1 ))
"$HEAVY" bash tools/store/publish-app.sh "$APP_NAME" --rev "$NEXT_REV" || { restore; die "feed publish failed"; }
awk -F'\t' -v n="$APP_NAME" -v h="$ELF_SHA" '$1=="sysapp" && $2==n && $5==h {f=1} END {exit !f}' "$FEED_LIST/VERZEICHNIS" \
    || { restore; die "published binary differs from the gated binary"; }
python3 "$STORE_TOOLS/refresh_system_app.py" --repo "$STORE_REPO" --app "$APP_ID" --version "$VERSION" \
    --level works --build "certus-ui $SHORT + osum $(git rev-parse --short=9 HEAD)" --device QEMU --gate "$GATE" \
    --notes-de "Gate grün ($PASSED/0): Standardbrowser startet Certus, Seite lädt und ist auf dem Bildschirm." \
    --notes-en "Gate green ($PASSED/0): default browser starts Certus, the page loads and is on screen." \
    || { restore; die "catalog refresh failed"; }
python3 "$STORE_TOOLS/store" --repo "$STORE_REPO" verify || { restore; die "catalog verify failed"; }
printf '%s\n' "$HEAD_ID" > "$STATE_FILE"
echo "publish-certus: Certus $SHORT (version $VERSION) is live; backup $BACKUP"
