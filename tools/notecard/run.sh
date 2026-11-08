#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
SCALE=${SCALE:-1}
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq notify"
cat > "$TMPD/script.txt" <<'SEOF'
warteauf 'taskbar: steht|taskbar: geom' || 120
warte 6
klick 300,200
warte 2
taste ret
warte 1
tippe notify ev+ jack
taste ret
warte 2
foto 01-toast
warte 8
klickauf glocke
warte 4
foto 02-center
SEOF
run_one() {
    bash tools/design/eh6.sh "$TMPD/$1" res=1280x800 accel=kvm uiscale=$SCALE progs="$PROGS" \
        drehbuch="$TMPD/script.txt" tbextra="$2" > "$TMPD/$1.log" 2>&1
}
run_one new ""
run_one old "note_old=1"
if [ -n "${NOTECARD_OUT:-}" ]; then
    mkdir -p "$NOTECARD_OUT"
    for r in new old; do mkdir -p "$NOTECARD_OUT/$r"; cp "$TMPD/$r"/*.ppm "$TMPD/$r/serial.txt" "$NOTECARD_OUT/$r/" 2>/dev/null; done
fi
python3 -I tools/notecard/check.py "$TMPD/new" "$TMPD/old" "$SCALE"
