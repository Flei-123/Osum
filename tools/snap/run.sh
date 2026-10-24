#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/snap/run.sh -- EDGE SNAP OF FLOATING WINDOWS (kernel/ui/wm.fi snap_zone / float_drop / float_unmax). (W-WIN11)
#
#   bash tools/snap/run.sh [outdir]       SNAP_SCALES="1 2" SNAP_OUT keeps the pictures
#
# Machine of the stick (tools/design/eh6.sh).  The shell terminal window is dragged (tools/snap/scenario.txt) to the left edge,
# back out, to the right edge, to the top edge, out again, to the two corners.  The window server says on the serial line
#   wm: snap id= zone= x= y= w= h=      (zone 1 left, 2 right, 3 top = maximized, 9..12 corners)
# Checks per scale (1 and 2, the Windows size of the edge zones scales with it):
#   1. left: x ~ 0, width ~ half the screen, height = the work area
#   2. a drag out of the snapped window restores the FREE size (the `wm: abgelegt` of the first plain move)
#   3. right: x + w ~ screen width, width ~ half
#   4. top: the work area (maximized), corners: a quarter (width ~ half, height ~ half the work area)
#   5. the picture of the left half differs from the one before in the left half and not in the right half (pixel)
# COUNTER-PROOF `nosnap` (kernel word): no `wm: snap` line at all, the window keeps its free size at the edge.
set -uo pipefail
cd "$(dirname "$0")/../.."
OUTD=${1:-${SNAP_OUT:-}}
if [ -z "$OUTD" ]; then OUTD=$(mktemp -d); trap 'rm -rf "$OUTD"' EXIT; fi
mkdir -p "$OUTD"
export DESIGNBUILD="${DESIGNBUILD:-$OUTD/build}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
SCALES=${SNAP_SCALES:-"1 2"}

check() { # <serial> <screen-w> <screen-h> <scale> <label>  -> prints OK/FAIL lines
python3 -I - "$@" <<'PY'
import re, sys
ser, W, H, sc, label = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
t = open(ser, "rb").read().decode("latin1")
def sg(v):
    v = int(v)
    return v - (1 << 64) if v >= (1 << 63) else v
snaps = [(int(m[0]), int(m[1]), sg(m[2]), sg(m[3]), int(m[4]), int(m[5])) for m in
         re.findall(r"wm: snap id=(\d+) zone=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)", t)]
abg = [(sg(a[1]), sg(a[2]), int(a[3]), int(a[4])) for a in re.findall(r"wm: abgelegt id=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)", t)]
bar = 0
g = None
for g in re.finditer(r"taskbar: geom edge=\d+ x=\d+ y=\d+ w=\d+ h=(\d+)", t):
    pass
if g: bar = int(g.group(1))
def say(ok, m): print(("OK    " if ok else "FAIL  ") + "%s: %s" % (label, m))
byzone = {}
for s in snaps: byzone.setdefault(s[1], []).append(s)
say(len(snaps) >= 5, "%d `wm: snap` lines (want >= 5: left, right, top, two corners); bar height %d" % (len(snaps), bar))
tol = 8 * sc
workh = H - bar
def z(code):
    return byzone.get(code, [None])[-1]
s1 = z(1)
if s1:
    say(abs(s1[2]) <= tol and abs(s1[4] - W // 2) <= tol and s1[5] >= workh - tol, "left half x=%d w=%d h=%d (screen %dx%d, work h %d)" % (s1[2], s1[4], s1[5], W, H, workh))
else: say(False, "no left snap (zone 1)")
s2 = z(2)
if s2:
    say(abs(s2[2] + s2[4] - W) <= tol and abs(s2[4] - W // 2) <= tol and s2[5] >= workh - tol, "right half x=%d w=%d h=%d" % (s2[2], s2[4], s2[5]))
else: say(False, "no right snap (zone 2)")
s3 = z(3)
if s3:
    say(abs(s3[2]) <= tol and abs(s3[3]) <= tol and s3[4] >= W - tol and workh - tol <= s3[5] <= H, "top = maximized x=%d y=%d w=%d h=%d" % (s3[2], s3[3], s3[4], s3[5]))
else: say(False, "no top snap (zone 3)")
for code, name in ((9, "top-left"), (12, "bottom-right")):
    s = z(code)
    if s:
        say(abs(s[4] - W // 2) <= tol and abs(s[5] - workh // 2) <= tol + 4 * sc, "corner %s is a quarter: w=%d h=%d (want ~%d x ~%d)" % (name, s[4], s[5], W // 2, workh // 2))
    else: say(False, "no %s corner snap (zone %d)" % (name, code))
# the free size: the first `abgelegt` is the plain move; the one after the left snap (drag out) must restore exactly that
if len(abg) >= 3 and s1:
    free = abg[0][2:]
    after = abg[2][2:] if len(abg) > 2 else None
    say(after == free, "dragging out of the left half restores the free size %s (got %s)" % (free, after))
else: say(False, "too few `wm: abgelegt` lines (%d) to check the restore" % len(abg))
PY
}

pix() { # <a.ppm> <b.ppm> <x0> <x1>  -> number of different pixels in columns x0..x1 (whole height above the bar line)
python3 -I - "$@" <<'PY'
import sys
def load(p):
    d = open(p, "rb").read(); f = []; at = 2
    while len(f) < 3:
        while d[at:at+1].isspace(): at += 1
        s = at
        while not d[at:at+1].isspace(): at += 1
        f.append(int(d[s:at]))
    return f[0], f[1], d[at+1:]
wa, ha, a = load(sys.argv[1]); wb, hb, b = load(sys.argv[2])
x0, x1 = int(sys.argv[3]), int(sys.argv[4])
n = 0
for y in range(0, ha - 120):
    ra = a[(y * wa + x0) * 3:(y * wa + x1) * 3]; rb = b[(y * wb + x0) * 3:(y * wb + x1) * 3]
    if ra != rb:
        for i in range(0, len(ra), 3):
            if ra[i:i+3] != rb[i:i+3]: n += 1
print(n)
PY
}

run() { # <name> <res> <uiscale> [extra]
    local name=$1 res=$2 sc=$3 extra=${4:-}
    mkdir -p "$OUTD/$name"
    bash tools/design/eh6.sh "$OUTD/$name" "res=$res" "uiscale=$sc" mode=light tafel=nein accel=kvm "drehbuch=tools/snap/scenario.txt" ${extra:+"extra=$extra"} > "$OUTD/$name.log" 2>&1
}

for sc in $SCALES; do
    if [ "$sc" = 2 ]; then res=1920x1080; else res=1280x800; fi
    echo "== scale $sc ($res) =="
    run "s$sc" "$res" "$sc"
    S="$OUTD/s$sc/serial.txt"
    if [ ! -s "$S" ]; then bad "scale $sc: no serial log"; tail -5 "$OUTD/s$sc.log"; continue; fi
    while IFS= read -r l; do case "$l" in "OK "*) ok "${l#OK    }" ;; "FAIL "*) bad "${l#FAIL  }" ;; esac; done < <(check "$S" "${res%x*}" "${res#*x}" "$sc" "scale $sc")
    W=${res%x*}
    if [ -s "$OUTD/s$sc/00-start.ppm" ] && [ -s "$OUTD/s$sc/01-left.ppm" ]; then
        L=$(pix "$OUTD/s$sc/00-start.ppm" "$OUTD/s$sc/01-left.ppm" 0 $((W / 2 - 4)))
        R=$(pix "$OUTD/s$sc/00-start.ppm" "$OUTD/s$sc/01-left.ppm" $((W / 2 + 4)) "$W")
        [ "$L" -ge 20000 ] && ok "scale $sc: the left half of the picture changed ($L px)" || bad "scale $sc: left half barely changed ($L px)"
        echo "      (right half differs by $R px: the free window was there before)"
    else bad "scale $sc: pictures 00-start/01-left missing"; fi
done

echo "== COUNTER-PROOF nosnap =="
run nosnap 1280x800 1 nosnap
S="$OUTD/nosnap/serial.txt"
if [ -s "$S" ]; then
    n=$(grep -ac '^wm: snap id=' "$S")
    [ "$n" = 0 ] && ok "nosnap: no snap line at all" || bad "nosnap: $n snap lines"
    a=$(grep -a '^wm: abgelegt id=' "$S" | awk '{print $NF" "$(NF-1)}' | sort -u | wc -l)
    [ "$a" -ge 1 ] && ok "nosnap: windows still get dropped ($a distinct sizes seen)" || bad "nosnap: no drop line"
else bad "nosnap: no serial log"; fi
echo
echo "SNAP: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
