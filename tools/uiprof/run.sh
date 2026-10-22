#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/uiprof/run.sh -- MON-4 gate (host only, seconds): the flicker detector and the pixel-diff series of tools/uiprof/uiprof.py.
#
#   bash tools/uiprof/run.sh
#
# Synthetic PPM series: a clean series is green, a PLANTED flicker (a region blanked for one frame, then back) is red and named in the
# strip PNG, a change that stays (menu opens) is no flicker, the pointer box and the caret tolerance (max_px) are honoured, and the
# wrapper tools/lockflicker/series.py prints the same SERIES line as before the move.
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
U="python3 -I tools/uiprof/uiprof.py"

python3 -I - "$TMPD" <<'PY'
import sys
import numpy as np
d = sys.argv[1]
def save(name, a):
    h, w, _ = a.shape
    open("%s/%s.ppm" % (d, name), "wb").write(b"P6\n%d %d\n255\n" % (w, h) + a.tobytes())
base = np.zeros((120, 200, 3), dtype=np.uint8)
base[:, :, 0] = 40; base[:, :, 1] = 60; base[:, :, 2] = 90
base[20:40, 20:100] = (200, 200, 200)
save("base", base)
for i in range(6):
    save("clean-%03d" % i, base)
for i in range(6):
    f = base.copy()
    if i == 3:
        f[20:40, 20:100] = (40, 60, 90)
    save("plant-%03d" % i, f)
for i in range(6):
    f = base.copy()
    if i >= 3:
        f[60:100, 20:150] = (255, 255, 255)
    save("step-%03d" % i, f)
for i in range(6):
    f = base.copy()
    f[10:20, 150 + i:160 + i] = (255, 0, 0)
    save("ptr-%03d" % i, f)
for i in range(6):
    f = base.copy()
    if i % 2:
        f[100:104, 10:14] = (255, 255, 255)
    save("caret-%03d" % i, f)
PY

$U flicker "$TMPD" clean > "$TMPD/clean.out" 2>&1; rc=$?
[ "$rc" = 0 ] && grep -q "events=0" "$TMPD/clean.out" && ok "clean series: no flicker" || bad "clean series flagged: $(cat "$TMPD/clean.out")"
$U flicker "$TMPD" plant --strip "$TMPD/strip.png" > "$TMPD/plant.out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q "plant-003.ppm flickers: 1600 px, box x 20..99 y 20..39" "$TMPD/plant.out" && ok "planted flicker is red (frame 3, 1600 px, right box)" || bad "planted flicker not found: $(cat "$TMPD/plant.out")"
[ "$(head -c 8 "$TMPD/strip.png" | od -An -tx1 | tr -d ' \n')" = "89504e470d0a1a0a" ] && [ "$(wc -c < "$TMPD/strip.png")" -gt 200 ] && ok "strip PNG written" || bad "strip PNG missing or invalid"
python3 -I - "$TMPD/strip.png" <<'PY' && ok "strip PNG decodes, red marks present" || bad "strip PNG content wrong"
import struct, sys, zlib
d = open(sys.argv[1], "rb").read()
w, h = struct.unpack(">II", d[16:24])
i, idat = 8, b""
while i < len(d):
    n = struct.unpack(">I", d[i:i+4])[0]
    if d[i+4:i+8] == b"IDAT":
        idat += d[i+8:i+8+n]
    i += 12 + n
raw = zlib.decompress(idat)
assert len(raw) == h * (1 + w * 3)
assert b"\xff\x00\x00" in raw
PY
$U flicker "$TMPD" step > "$TMPD/step.out" 2>&1; rc=$?
[ "$rc" = 0 ] && ok "a change that stays (menu opens) is no flicker" || bad "step flagged: $(cat "$TMPD/step.out")"
$U flicker "$TMPD" plant --minpx 2000 > "$TMPD/min.out" 2>&1; rc=$?
[ "$rc" = 0 ] && ok "minpx above the flicker size tolerates it (caret)" || bad "minpx not honoured"
$U flicker "$TMPD" plant --ignore 0,0,200,60 > "$TMPD/ign.out" 2>&1; rc=$?
[ "$rc" = 0 ] && ok "ignored box hides the flicker (counter-proof of the box)" || bad "ignore box not honoured"
$U flicker "$TMPD" caret --window 1 > "$TMPD/caret.out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q "events=" "$TMPD/caret.out" && ok "blinking caret is red without tolerance" || bad "caret not flagged"
$U flicker "$TMPD" caret --window 1 --minpx 100 > "$TMPD/caret2.out" 2>&1; rc=$?
[ "$rc" = 0 ] && ok "blinking caret is tolerated with minpx" || bad "caret flagged with minpx"
python3 -I tools/lockflicker/series.py "$TMPD" base clean 100 60 > "$TMPD/s1.out" 2>&1; rc=$?
[ "$rc" = 0 ] && grep -q "^SERIES frames=6 differing=0 max=0$" "$TMPD/s1.out" && ok "series wrapper: clean = SERIES frames=6 differing=0" || bad "series wrapper clean: $(cat "$TMPD/s1.out")"
python3 -I tools/lockflicker/series.py "$TMPD" base plant 190 110 > "$TMPD/s2.out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q "^SERIES frames=6 differing=1 max=1600$" "$TMPD/s2.out" && ok "series wrapper: planted frame is red" || bad "series wrapper plant: $(cat "$TMPD/s2.out")"
python3 -I tools/lockflicker/series.py "$TMPD" base ptr 160 15 > "$TMPD/s3.out" 2>&1; rc=$?
[ "$rc" = 0 ] && ok "series wrapper: pointer box ignored" || bad "series wrapper pointer: $(cat "$TMPD/s3.out")"
python3 -I tools/lockflicker/series.py "$TMPD" base none 0 0 > "$TMPD/s4.out" 2>&1; rc=$?
[ "$rc" = 2 ] && ok "no frames = exit 2" || bad "no frames exit $rc"
echo "UIPROF: $pass passed, $fail failed"
[ "$fail" = 0 ]
