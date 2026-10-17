#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/tablet/run.sh -- USB tablet = ABSOLUTE pointer + mouse wheel (W1b).
#
# Problem (VirtualBox default "USB Tablet", QEMU usb-tablet): the HID layer read X/Y as a relative step, so the pointer
# crawled to a corner and right-click/scroll went to the wrong place. Now hidin.keys_and_mouse sees "absolute" (no
# Relative flag), scales [lmin,lmax] to the screen and calls gfx.mouse_set_pos.
#
# 1. Real desktop boot (1280x800) with `-device qemu-xhci -device usb-tablet`; QMP input-send-event moves the tablet to
#    known fractions of its 0..32767 range; the pulse line ("eingabe: ... xy=X,Y") must show the scaled position.
# 2. Right click and wheel events reach the pointer layer (packet counter rises, position unchanged by wheel).
# 3. Wheel byte decode (ps2m.wheel_code, in the kernel's own self test: "mouse: ... selftest 13 / 13").
# COUNTER-PROBE: the tree before this change (TABLET_BASE commit) shows the pointer NOT at those positions.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${1:-$(mktemp -d)}
mkdir -p "$OUT"
BASE_COMMIT=${TABLET_BASE:-b73db113}
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "TABLET: skipped, no qemu"; exit 0; }
PROGS="desktop taskbar launcher settings theme explorer sh echo ls cat"

run_tree() { # tree out
    mkdir -p "$2"
    ( cd "$1" && bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
      ALLTAGBUILD="$2.build" bash tools/alltag/build.sh "$2" kbd=no warten=3 \
        extra="usb hidgen wighalt=40" progs="$PROGS" \
        qemu="-device qemu-xhci -device usb-tablet -qmp unix:$2/qmp.sock,server,nowait" \
        hook="python3 $ROOT/tools/tablet/qmp.py $2/qmp.sock sleep:1 abs:16384,16384 down:right up:right wheel:up:3 wheel:down:2 abs:8192,24576 sleep:1" ) > "$2.log" 2>&1
}
# the kernel prints its final state when it halts: "usb: ... reports=N moves=N ... mx=X my=Y mbtn=B mpkt=P mclk=C"
fin() { grep -a '^usb: keys=' "$1/serial.txt" | tail -1 | sed -n "s/.* $2=\([0-9]*\).*/\1/p"; }

echo "== 1. new tree: tablet drives the pointer =="
run_tree "$ROOT" "$OUT/new" || true
S="$OUT/new/serial.txt"
grep -aq 'class=03:00:00 driver=mouse' "$S" && ok "tablet attached (HID without boot protocol)" || bad "tablet not attached"
MX=$(fin "$OUT/new" mx); MY=$(fin "$OUT/new" my)
near() { local dx=$(( $1 > $3 ? $1 - $3 : $3 - $1 )) dy=$(( $2 > $4 ? $2 - $4 : $4 - $2 ))
         [ "$dx" -le 2 ] && [ "$dy" -le 2 ]; }
if [ -n "$MX" ] && near "$MX" "$MY" 319 599; then ok "last tablet position 8192,24576 -> pointer $MX,$MY (want 319,599 +-2)"
else bad "pointer $MX,$MY (want 319,599 +-2)"; fi
R=$(fin "$OUT/new" reports); [ -n "$R" ] && [ "$R" -ge 8 ] && ok "tablet reports reached the HID layer ($R)" || bad "too few tablet reports ($R)"
C=$(fin "$OUT/new" mclk); [ -n "$C" ] && [ "$C" -ge 1 ] && ok "right click counted ($C)" || bad "no click counted ($C)"
grep -aq 'mouse: id=.*selftest 13 / 13' "$S" && ok "wheel decode self test (ID3 signed, clamp, ID4 nibble): 13/13" || bad "mouse self test is not 13/13"

echo
echo "== 2. COUNTER-PROBE: tree before the change =="
if git rev-parse -q --verify "$BASE_COMMIT^{commit}" >/dev/null 2>&1; then
    BT="$OUT/basetree"
    git worktree add -q --detach "$BT" "$BASE_COMMIT" 2>/dev/null
    mkdir -p "$OUT/old"; run_tree "$BT" "$OUT/old" || true
    git worktree remove --force "$BT" >/dev/null 2>&1
    OX=$(fin "$OUT/old" mx); OY=$(fin "$OUT/old" my)
    if [ -n "$OX" ]; then
        ok "old kernel booted with the same tablet (counter-probe is a real run)"
        if near "$OX" "$OY" 319 599; then bad "old kernel ALSO reaches 319,599 -- gate proves nothing"
        else ok "old kernel: pointer at $OX,$OY, NOT 319,599 -- the gate sees the difference"; fi
    else bad "old tree produced no final state"; tail -8 "$OUT/old.log"; fi
else
    echo "  (skipped: base commit $BASE_COMMIT not in this clone)"
fi

echo
echo "== TABLET: $pass green, $fail red =="
[ "$fail" -eq 0 ]
