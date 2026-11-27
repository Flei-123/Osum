#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/titleicon/run.sh -- the program icon at the left of the framed title bar: x within border+padding, vertical middle within 1 px of the bar
# middle, pixels really drawn. Counter-proof on the old tree (no icon word) must go red.
#   bash tools/titleicon/run.sh [<keep-dir>]      TITLEICON_OLD=<ref> (default 86ac307ca^), TITLEICON_NOCP=1 skips the counter-proof
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/firnenv.sh
ROOT=$(pwd)
KEEP=${1:-}
D=$(mktemp -d)
trap 'cd "$ROOT"; [ -n "${OLDWT:-}" ] && git worktree remove --force "$OLDWT" >/dev/null 2>&1; rm -rf "$D"' EXIT
pass=0; fail=0
cat > "$D/dreh.txt" <<DREH
warteauf 'launcher: ready' || 90
warte 25
klick 24,780
warte 4
klickauf start_Settings
warte 14
taste meta_l
warte 4
tippe edit
warte 4
taste ret
warte 14
fahre 1250,780
warte 40
foto s
taste f12
warte 3
DREH
shoot() { # shoot <tree> <out>
    ( cd "$1" && /root/jarvis/bin/heavy bash tools/design/eh6.sh "$2" res=1280x800 accel=kvm ton=ja mode=light lang=en tafel=nein pins=explorer,settings,terminal drehbuch="$D/dreh.txt" "progs=desktop taskbar settings launcher explorer edit sh echo ls cat theme" > "$2.log" 2>&1 )
}
OLDPID=""
if [ -z "${TITLEICON_NOCP:-}" ]; then
    REF=${TITLEICON_OLD:-86ac307ca^}
    OLDWT="$D/oldwt"
    git worktree add --detach "$OLDWT" "$REF" >/dev/null 2>&1
    ( cd "$OLDWT" && firnenv_prepare_old_tree . >/dev/null 2>&1; shoot "$OLDWT" "$D/old" ) &
fi
shoot "$ROOT" "$D/new" &
wait
echo "== new tree"
python3 -I tools/titleicon/check.py "$D/new/s.ppm" "$D/new/serial.txt" | tee "$D/new.res"
pass=$((pass+$(grep -c '^  OK' "$D/new.res"))); fail=$((fail+$(grep -c '^  FAIL' "$D/new.res")))
if [ -z "${TITLEICON_NOCP:-}" ]; then
    echo "== counter-proof: $REF must go red"
    python3 -I tools/titleicon/check.py "$D/old/s.ppm" "$D/old/serial.txt" > "$D/old.res" 2>&1
    grep FAIL "$D/old.res" | sed 's/^/  (old) /'
    fo=$(grep -c '^  FAIL' "$D/old.res")
    [ "$fo" -ge 1 ] && { echo "  OK    counter-proof: $REF has $fo red checks"; pass=$((pass+1)); } || { echo "  FAIL  counter-proof stayed green"; fail=$((fail+1)); }
fi
[ -n "$KEEP" ] && { mkdir -p "$KEEP"; cp "$D"/new/s.ppm "$D"/new/serial.txt "$KEEP/" 2>/dev/null; }
echo
echo "TITLEICON: $pass passed, $fail failed"
[ "$fail" = 0 ]
