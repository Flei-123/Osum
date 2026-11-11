#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/ota/publish.sh [--apply] [--stand DIR] [--pub FILE] ["<notes>"]
#   One command for the HP dev feed. Default is a dry run: checks prerequisites, builds + signs into a
#   temp copy (tools/ota/publish-dev.sh --dry), verifies and lists packages, hashes and the target path.
#   --apply   publishes for real (tools/ota/publish-dev.sh) after a successful dry run. Never implicit.
#   --stand DIR  skip the build and only verify + list the signed stand directory DIR (system/<channel> content).
#   --pub FILE   public key for --stand (default: the live feed key aktuell/schluessel.pub).
#   Env: FEED_DIR (default /srv/store/osum)  FEED_URL (default https://store.fleitec.com/osum)  HP_BASE  HP_REF
#        OSUM_BUND / OSUM_SIGN_PASS_FILE (default /root/.secrets/osum-ota-{bund.json,pass.txt})
set -euo pipefail
cd "$(dirname "$0")/../.."
APPLY=0; STAND=""; PUB=""; NOTES=""
while [ $# -gt 0 ]; do
    case "$1" in
        --apply) APPLY=1 ;;
        --stand) STAND=$2; shift ;;
        --pub) PUB=$2; shift ;;
        -h|--help) sed -n 2,11p "$0"; exit 0 ;;
        *) NOTES=$1 ;;
    esac
    shift
done
FEED_DIR=${FEED_DIR:-/srv/store/osum}
CHANNEL=${HP_CHANNEL:-dev}
BUND=${OSUM_BUND:-/root/.secrets/osum-ota-bund.json}
PASS_FILE=${OSUM_SIGN_PASS_FILE:-/root/.secrets/osum-ota-pass.txt}
HP_BASE=${HP_BASE:-/root/abbilder/hp-stick36-base}
MIN_BASE_PROGRAMS=100
fail() { echo "publish: $*" >&2; exit 1; }

check_common() {
    command -v python3 > /dev/null || fail "python3 missing"
    [ -d "$FEED_DIR/aktuell" ] || fail "feed dir $FEED_DIR has no aktuell/"
    [ -s "$FEED_DIR/aktuell/schluessel.pub" ] || fail "$FEED_DIR/aktuell/schluessel.pub missing"
}

check_build() {
    [ -s "$BUND" ] || fail "signing bundle $BUND missing"
    [ -s "$PASS_FILE" ] || [ -n "${OSUM_SIGN_PASS:-}" ] || fail "signing passphrase missing ($PASS_FILE)"
    [ -d "$HP_BASE" ] || fail "HP_BASE $HP_BASE missing"
    [ -f "$HP_BASE/SYSVERSION" ] || fail "HP_BASE $HP_BASE has no SYSVERSION"
    local programs
    programs=$(find "$HP_BASE" -maxdepth 1 -name '*.elf' | wc -l)
    [ "$programs" -ge "$MIN_BASE_PROGRAMS" ] || fail "HP_BASE has only $programs programs (need >= $MIN_BASE_PROGRAMS)"
    [ -x "${HEAVY_BIN:-/root/jarvis/bin/heavy}" ] || fail "heavy wrapper missing"
    git diff --quiet HEAD -- . || fail "working tree not clean (the stand names the commit)"
    git fetch -q origin
}

report() {
    python3 -I tools/ota/feedreport.py "$1" "${PUB:-$FEED_DIR/aktuell/schluessel.pub}" --target "$FEED_DIR/system/$CHANNEL"
}

if [ -n "$STAND" ]; then
    [ "$APPLY" = 0 ] || fail "--stand only verifies; it cannot be combined with --apply"
    [ -d "$STAND" ] || fail "stand dir $STAND missing"
    [ -z "$PUB" ] || [ -s "$PUB" ] || fail "public key $PUB missing"
    [ -n "$PUB" ] || check_common
    report "$STAND"
    echo "publish: verify-only OK, nothing changed"
    exit 0
fi

check_common
check_build
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
echo "publish: dry run (nothing is changed)"
DRY_OUT="$OUT" bash tools/ota/publish-dev.sh --dry ${NOTES:+"$NOTES"} | tail -n 4
[ -s "$OUT/VERZEICHNIS" ] || fail "dry run produced no stand"
report "$OUT"
if [ "$APPLY" = 0 ]; then
    echo "publish: DRY RUN ONLY. To publish: bash tools/ota/publish.sh --apply"
    exit 0
fi
echo "publish: --apply, publishing to $FEED_DIR/system/$CHANNEL"
bash tools/ota/publish-dev.sh ${NOTES:+"$NOTES"}
