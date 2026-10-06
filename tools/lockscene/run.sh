#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/lockscene/run.sh -- r372: THE LOCK SCREEN IS A SCENE TREE OF fUi.
#
#   bash tools/lockscene/run.sh [<out dir>]
#
# Measures (guest: /bin/lock on a tiny disk, one user with a password):
#   tree      the program reports "fUi Szenenbaum" and its rectangles come
#             from the host's tree (entry, eye, main button = 3 widgets)
#   raster    the 4-pixel grid of the layout (tools/design/messen.py) >= 92 %
#   wrong     a wrong password: "falsches Kennwort", the lock stays
#   right     the right one: "aufgesperrt", the window is gone
#   eye       Tab, Enter on the eye toggles the field without unlocking
#   crash     an absturz leaves the lock standing (kernel restarts the locker)
#   counter   the same run with a WRONG password only must NOT unlock
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
# KVM when the machine has it (the password check, PBKDF2, is slow under TCG)
[ -w /dev/kvm ] && export OSUM_ACCEL=kvm
OUT=${1:-$(mktemp -d)}
[ -n "${1:-}" ] || trap 'rm -rf "$OUT"' EXIT
mkdir -p "$OUT"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
hat()    { grep -qaF "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 -- '$2' missing"; }
hatnicht() { grep -qaF "$2" "$1" 2>/dev/null && bad "$3 -- '$2' present" || ok "$3"; }
B=tools/alltag/build.sh
PROGS="lock theme sh echo ls cat"

python3 - "$OUT" <<'PY'
import binascii, hashlib, sys
d = sys.argv[1]
it, salt = 1024, bytes(range(8))
dk = hashlib.pbkdf2_hmac("sha256", b"geheim12", salt, it, 32)
rec = "$osum1$%d$%s$%s" % (it, binascii.hexlify(salt).decode(), binascii.hexlify(dk).decode())
open(d + "/shadow", "w").write("root:%s:0:0:99999:7:::\n" % rec)
PY
keys() { local m=""; for c in "$@"; do m="$m mon=sendkey\ $c"; done; echo "$m"; }
run() { # name wigapp keys...
    local nm=$1 app=$2; shift 2
    eval bash "$B" "$OUT/$nm" kbd=yes uitrace=yes warten=8 bloecke=32768 \
        extra=\"wigapp=$app\" progs=\"$PROGS\" xfile=/etc/shadow="$OUT/shadow" xfile=/etc/wallpaper=assets/wallpaper-sea.osym \
        $(keys "$@") > "$OUT/$nm.log" 2>&1
}

echo "== tree + raster =="
run t1 /bin/lock
S=$OUT/t1/serial.txt
hat "$S" "sperre: fUi Szenenbaum" "the lock screen is a scene tree"
hat "$S" "sperre: bereit" "and it is ready"
N=$(grep -ac 'lock: rect id=' "$S")
[ "$N" -ge 3 ] && ok "the host reports its widgets ($N rectangles)" || bad "rectangles: $N, expected >= 3"
R=$(python3 tools/design/messen.py "$OUT/t1" 2>/dev/null | grep -a 'raster/4' | grep -aoE '\([0-9]+%\)' | tr -dc '0-9')
[ -n "$R" ] && [ "$R" -ge 92 ] && ok "4-pixel grid: $R %" || bad "4-pixel grid: '${R}' %"
hat "$S" "t=Kennwort anzeigen" "the eye is a named node"
hat "$S" "t=Entsperren" "the main button is a named node"

echo "== wrong, then right =="
run t2 /bin/lock f a l s c h ret g e h e i m 1 2 ret
S=$OUT/t2/serial.txt
hat "$S" "sperre: falsches Kennwort, bleibt zu" "wrong password: the lock stays"
hat "$S" "sperre: aufgesperrt" "right password: it opens"

echo "== counter-proof: only wrong passwords =="
run t3 /bin/lock f a l s c h ret x y z ret
S=$OUT/t3/serial.txt
hat "$S" "sperre: falsches Kennwort, bleibt zu" "wrong password refused"
hatnicht "$S" "sperre: aufgesperrt" "COUNTER-PROOF: wrong passwords never unlock"

echo "== the eye (Tab, Enter) does not unlock =="
run t4 /bin/lock g e h e i m 1 2 tab ret
S=$OUT/t4/serial.txt
hatnicht "$S" "sperre: aufgesperrt" "Tab+Enter on the eye shows the text, does not unlock"

echo "== keys that pile up: a slow guest (TCG) gets 'falsch' Enter 'geheim12' Enter in one go =="
# The scene host used to type everything after an Enter into the field BEFORE
# the program heard of the Enter: one attempt with "falschgeheim12", never open.
OSUM_ACCEL=tcg run t6 /bin/lock f a l s c h ret g e h e i m 1 2 ret
S=$OUT/t6/serial.txt
hat "$S" "sperre: falsches Kennwort, bleibt zu" "burst: the first attempt is refused"
hat "$S" "sperre: aufgesperrt" "burst: the second attempt (typed behind the first Enter) opens it"

echo "== a crash locks, never unlocks =="
bash "$B" "$OUT/t5" warten=10 extra="wigapp=/bin/lock,-absturz" progs="$PROGS" \
    xfile=/etc/shadow="$OUT/shadow" xfile=/etc/wallpaper=assets/wallpaper-sea.osym > "$OUT/t5.log" 2>&1
S=$OUT/t5/serial.txt
hat "$S" "sperre: Sperrer neu, pid=" "the kernel restarts the locker"
hatnicht "$S" "sperre: aufgesperrt" "a crash does not unlock"

echo; echo "LOCKSCENE: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
