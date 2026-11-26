#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/ota/publish-dev.sh [--dry] ["<notes>"]
#   One command: publish origin/main as the ONE dev feed (system/dev) for every device (HP, Dell, VM) and verify it over https.
#   --dry builds + signs + verifies in a temp copy, publishes nothing, then checks the live feed over https.
#   Env: HP_BASE (space separated baseline dirs, default tools/ota/device-bases.txt; the first must be a full baseline)  HP_REF (default origin/main)
#        FEED_URL (default https://store.fleitec.com/osum)  HEAVY_TIMELIMIT (default 90)
set -euo pipefail
cd "$(dirname "$0")/../.."
DRY=""
NOTES=""
for a in "$@"; do
    case "$a" in
        --dry) DRY=--dry ;;
        *) NOTES=$a ;;
    esac
done
DEVICE_BASES_FILE=tools/ota/device-bases.txt
export HP_BASE=${HP_BASE:-$(grep -v '^$' "$DEVICE_BASES_FILE" | tr '\n' ' ')}
export HP_REF=${HP_REF:-origin/main}
export HP_SKIP_EXTRAS="/etc/jarvis/permissions.conf ${HP_SKIP_EXTRAS:-}"
unset FEED_ROOT HP_DEV
export HEAVY_TIMELIMIT=${HEAVY_TIMELIMIT:-90}
FEED_URL=${FEED_URL:-https://store.fleitec.com/osum}
MIN_BASE_PROGRAMS=100
fail() { echo "publish-dev: $*" >&2; exit 1; }
read -r -a BASES <<< "$HP_BASE"
PRIMARY_BASE=${BASES[0]:-}
[ -d "$PRIMARY_BASE" ] || fail "HP_BASE $PRIMARY_BASE missing"
[ -f "$PRIMARY_BASE/SYSVERSION" ] || fail "HP_BASE $PRIMARY_BASE has no SYSVERSION (not a baseline image dir)"
PROGRAMS=$(find "$PRIMARY_BASE" -maxdepth 1 -name '*.elf' | wc -l)
[ "$PROGRAMS" -ge "$MIN_BASE_PROGRAMS" ] || fail "HP_BASE $PRIMARY_BASE has only $PROGRAMS programs (need >= $MIN_BASE_PROGRAMS)"
for base in "${BASES[@]:1}"; do
    [ -f "$base/osum.mb" ] || fail "baseline $base has no osum.mb"
done
git fetch -q origin
[ -n "$NOTES" ] || NOTES="dev feed from $(git rev-parse --short "$HP_REF")"
LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT
echo "publish-dev: bases ${#BASES[@]} (primary $PRIMARY_BASE, $PROGRAMS programs), ref $HP_REF $DRY"
HEAVY=${HEAVY_BIN:-/root/jarvis/bin/heavy}
"$HEAVY" bash tools/ota/republish-hp.sh "$NOTES" $DRY 2>&1 | tee "$LOG" | grep -E '^(republish-hp|verify OK|VERZEICHNIS|package feed|published|\(dry|publish)' || true
grep -q '^verify OK' "$LOG" || { tail -20 "$LOG"; fail "no 'verify OK' from the publisher (see output above)"; }
grep -q '^package feed unchanged' "$LOG" || fail "package feed check missing"
if [ -n "$DRY" ]; then
    grep -q '^(dry run, nothing published)' "$LOG" || fail "dry run did not finish"
    python3 -I tools/ota/verify_feed.py "$FEED_URL" dev
    echo "publish-dev: DRY OK. Publish for real: bash tools/ota/publish-dev.sh"
    exit 0
fi
STAND=$(sed -n 's/^republish-hp: [0-9a-f]* count \([0-9]*\)$/\1/p' "$LOG" | head -1)
[ -n "$STAND" ] || fail "cannot read the stand number from the output"
python3 -I tools/ota/verify_feed.py "$FEED_URL" dev --count "$STAND"
cat <<MSG

publish-dev: stand $STAND is live and verified (signature, hashes, https).
Every device (HP, Dell, VM; same stand, same files), via bridge/terminal, in this order:
  1. /bin/grep wlanfirst /etc/wlan.knobs      optional: wlanfirst is inert while a wired or USB card is alive (only wlanforce overrides, boot word)
  2. /bin/ota system status                   shows the running stand
  3. /bin/ota system apply bg                 downloads + applies the overlay (owner's decision)
  4. /bin/reboot
  5. /bin/ota system status                   must show stand $STAND
  6. /bin/cat /proc/wlan                      link must be up
  7. /bin/ota confirm
Note: without wlanforce the WLAN never takes the uplink from a living wired or USB card.
MSG
