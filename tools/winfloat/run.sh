#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/winfloat/run.sh -- W-WINOPTS stage 2 (docs/APP-WINDOW-OPTS.md): THE LAYER L_FLOAT AND THE RIGHT `window.float`.
#
#   bash tools/winfloat/run.sh        (start it through /root/jarvis/bin/heavy)
#
# /bin/winfloat (kernel/user/winfloat.fi) runs in the desktop image: an ordinary window N (root, red), a window T on L_TOP (root, green;
# the task bar and the lock screen are L_TOP windows too) and a window F (app:fprobe, uid 1000, WO_KEYS, blue). One serial line
# `winfloat: <name> <a> <b>` per step. The host drives the QEMU monitor (one key) and takes the screenshot.
#   1. without the right: L_FLOAT and L_TOP are refused with E_RIGHTS (2), L_NORMAL is allowed; root may use L_FLOAT; layer 9 = E_INVALID
#   2. with the right (granted by unlabelled root, ceiling first): L_FLOAT works, WI_LAYER reads 8
#   3. COUNTER-PROOF: the right is taken away -> the kernel puts the window back on L_NORMAL (WI_LAYER 1), a new request is E_RIGHTS;
#      granted again -> the request works again
#   4. screenshot: F lies OVER N, and T (L_TOP) lies OVER F (three overlap areas sampled)
#   5. the key typed in the monitor reaches the float window (WO_KEYS)
set -uo pipefail
cd "$(dirname "$0")/../.."
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
pass=0; fail=0
export CAPTURE_TIME=${CAPTURE_TIME:-1760000000}
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

val() { # val <serial> <name> <field 3|4>   the FIRST line "winfloat: name a b"
    grep -a "^winfloat: $2 " "$1" | head -1 | awk -v f="$3" '{print $f}'
}
eq() { # eq <serial> <name> <field> <expected> <text>
    local v; v=$(val "$1" "$2" "$3")
    if [ "$v" = "$4" ]; then ok "$5"; else bad "$5 (got '$v', want '$4')"; fi
}
lineno() { # lineno <serial> <regex>   first line number of a match (0 = none)
    local n; n=$(grep -an -- "$2" "$1" | head -1 | cut -d: -f1); echo "${n:-0}"
}

cat > "$D/book" <<'EOF'
warteauf ^winfloat: final || 90
warte 1
taste a
warte 1.5
EOF

echo "== build + run /bin/winfloat in the desktop =="
bash tools/alltag/build.sh "$D/w1" kbd=yes accel=kvm shot=yes uitrace=no \
    "extra=wigapp=/bin/winfloat wighalt=120" progs="winfloat sh echo" drive="$D/book" > "$D/w1.log" 2>&1
S="$D/w1/serial.txt"
if [ ! -s "$S" ]; then
    grep -a "FEHLGESCHLAGEN\|error" "$D/w1.log" | head -5
    bad "no serial output"
fi
grep -a '^winfloat:' "$S" | sed 's/^/        /'

echo "== 1. without the right =="
eq "$S" begin 3 1 "the window library started"
R=$(val "$S" p-top 3); [ "$R" = 0 ] && ok "root: L_TOP allowed" || bad "root: L_TOP refused ($R)"
eq "$S" p-rootfl 3 0 "root may use L_FLOAT without the right (the rule is about labelled apps)"
eq "$S" p-rootfl 4 8 "  and the layer reads 8"
eq "$S" p-maxl 3 4 "layer 9 (above L_MAX) is refused with E_INVALID"
eq "$S" p-maxl 4 8 "  and the window stays where it was"
eq "$S" p-back 3 0 "root puts the window back on L_NORMAL"
eq "$S" p-ceil 3 1 "the manifest ceiling for app:fprobe allows window.float"
eq "$S" c1-lab 3 1 "c1 carries the label app:fprobe"
eq "$S" c1-make 3 1 "c1 made a window"
eq "$S" c1-float 3 2 "NO RIGHT: L_FLOAT is refused with E_RIGHTS (2)"
eq "$S" c1-float 4 1 "  and the window stays on L_NORMAL"
eq "$S" c1-top 3 2 "L_TOP is still E_RIGHTS for an app"
eq "$S" c1-norm 3 0 "L_NORMAL is allowed"
eq "$S" p-c1 3 0 "c1 ran to the end"

echo "== 2. with the right =="
eq "$S" p-grant 3 1 "the person grants window.float"
eq "$S" c2-lab 3 1 "c2 carries the label app:fprobe"
eq "$S" c2-make 3 1 "c2 made a window (uid 1000, WO_KEYS)"
eq "$S" c2-float 3 0 "WITH THE RIGHT: L_FLOAT is allowed"
eq "$S" c2-float 4 8 "  and WI_LAYER reads 8"

echo "== 3. counter-proof: right taken away, right given back =="
eq "$S" p-revoke 3 1 "the right is taken away"
L_REV=$(lineno "$S" '^winfloat: p-revoke ')
L_BACK=$(lineno "$S" '^winfloat: c2-layer 1 ')
[ "$L_BACK" -gt "$L_REV" ] && [ "$L_REV" -gt 0 ] && ok "after the revoke the kernel puts the window back on L_NORMAL (c2 reads WI_LAYER 1)" || bad "no fall back to L_NORMAL after the revoke (lines $L_REV / $L_BACK)"
L_RT=$(lineno "$S" '^winfloat: c2-retry 2 1')
[ "$L_RT" -gt "$L_REV" ] && ok "a new request without the right is E_RIGHTS and the window stays on L_NORMAL" || bad "the retry after the revoke was not refused (line $L_RT)"
L_REG=$(lineno "$S" '^winfloat: p-regrant ')
L_UP=$(grep -an '^winfloat: c2-layer 8 ' "$S" | tail -1 | cut -d: -f1)
[ "${L_REG:-0}" -gt 0 ] && [ "${L_UP:-0}" -gt "$L_REG" ] && ok "granted again: the request works and the window is on L_FLOAT again" || bad "no L_FLOAT after the second grant (lines $L_REG / $L_UP)"
L_RT0=$(lineno "$S" '^winfloat: c2-retry 0 8')
[ "$L_RT0" -gt "$L_REG" ] && ok "the request after the second grant answers 0" || bad "retry after regrant: line $L_RT0"

echo "== 4. the screen: N < F < T =="
cat > "$D/px.py" <<'PYEOF'
import sys
from PIL import Image
img = Image.open(sys.argv[1]).convert("RGB")
px = img.load()
def near(p, want):
    return all(abs(p[i] - want[i]) <= 24 for i in range(3))
R, G, B = (204, 0, 0), (0, 204, 0), (0, 0, 204)
checks = [("N only", (150, 120), R), ("N+F: F over N", (250, 200), B), ("F only", (450, 200), B),
          ("N+F+T: T over F", (350, 280), G), ("F+T: T over F", (450, 320), G)]
for name, (x, y), want in checks:
    p = px[x, y]
    print("%s %s %s" % ("OK" if near(p, want) else "BAD", name, p))
PYEOF
if [ -s "$D/w1/desktop.ppm" ]; then
    python3 "$D/px.py" "$D/w1/desktop.ppm" > "$D/px.txt" 2>&1
    while IFS= read -r l; do
        case "$l" in OK\ *) ok "pixel: ${l#OK }";; *) bad "pixel: ${l#BAD }";; esac
    done < "$D/px.txt"
else
    bad "no screenshot"
fi

echo "== 5. typing reaches the float window (WO_KEYS) =="
K=$(grep -a '^winfloat: c2-key ' "$S" | head -1 | awk '{print $3}')
[ -n "$K" ] && [ "$K" != 0 ] && ok "the key typed in the monitor arrived in the float window (code $K)" || bad "no key reached the float window"

echo
echo "winfloat: OK=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
