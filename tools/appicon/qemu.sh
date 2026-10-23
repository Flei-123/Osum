#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/appicon/qemu.sh -- FALLBACK ICON ON THE SCREEN (W-ICON gate, QEMU/KVM, one desktop boot per case).
#
#   bash /root/jarvis/bin/heavy bash tools/appicon/qemu.sh [outdir]
#
# A program without a bundle symbol must not show an empty button: the bar paints the letter tile of lib/appicon.fi.
# Machine: tools/design/eh6.sh with the pins explorer (own symbol), snip (own symbol, W-ICON) and zzfb (no bundle at all).
# Checks (serial + the photo 00-bar.ppm):
#   1. the three `taskbar: pin <name> x= y= w= h= sym=` lines, all three with sym=1
#   2. `taskbar: sym fb n=` says the fallback was used (and the pin of a real symbol is not the tile: explorer differs from zzfb)
#   3. PIXELS: the zzfb pin rectangle is a solid tile (>= 40 % of its pixels differ from the bar colour and >= 12 % are one
#      colour) and carries white letter ink (>= 15 pixels)
# COUNTER-PROOF `nofb`: a copy of the tree whose sym_fallback() returns 0 at once -- no `sym fb` line, zzfb has sym=0, and
# the pixel check of 3. FAILS (the gate has teeth).
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
OUTD=${1:-${APPICON_OUT:-}}
if [ -z "$OUTD" ]; then OUTD=$(mktemp -d); trap 'rm -rf "$OUTD"' EXIT; fi
mkdir -p "$OUTD"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

cat > "$OUTD/dreh.txt" <<'EOF'
warteauf 'taskbar: steht|taskbar: geom' || 120
warte 8
foto 00-bar
EOF

run() { # <tree> <name>
    local tree=$1 name=$2
    mkdir -p "$OUTD/$name"
    ( cd "$tree" && DESIGNBUILD="$OUTD/$name-build" bash tools/design/eh6.sh "$OUTD/$name" mode=light \
        "pins=explorer,snip,zzfb" "tbextra=hide_missing=0" "drehbuch=$OUTD/dreh.txt" accel=kvm ) > "$OUTD/$name.log" 2>&1
}

# prints OK/FAIL lines; <expect> is "fb" (fallback wanted) or "nofb"
judge() { # <name> <expect>
python3 -I - "$OUTD/$1/serial.txt" "$OUTD/$1/00-bar.ppm" "$2" <<'PY'
import re, sys
ser, ppm, expect = sys.argv[1:4]
t = open(ser, "rb").read().decode("latin1")
def say(ok, m): print(("OK    " if ok else "FAIL  ") + m)
pins = {}
for m in re.finditer(r"taskbar: pin (\S+) x=(\d+) y=(\d+) w=(\d+) h=(\d+) sym=(\d)", t):
    pins[m[1]] = tuple(int(m[i]) for i in range(2, 7))
want = ("explorer", "snip", "zzfb")
say(all(n in pins for n in want), "pin lines for %s (got %s)" % (", ".join(want), ", ".join(sorted(pins)) or "none"))
if not all(n in pins for n in want):
    sys.exit(0)
if expect == "fb":
    say(all(pins[n][4] == 1 for n in want), "all three pins report sym=1 (%s)" % ", ".join("%s=%d" % (n, pins[n][4]) for n in want))
    fbn = [int(x) for x in re.findall(r"taskbar: sym fb n=(\d+)", t)]
    say(bool(fbn), "`taskbar: sym fb n=` seen (%s)" % (fbn[-1] if fbn else "none"))
else:
    say(pins["zzfb"][4] == 0, "COUNTER: zzfb has sym=%d without the fallback (want 0)" % pins["zzfb"][4])
    say("taskbar: sym fb n=" not in t, "COUNTER: no `sym fb` line without the fallback")
# the photo
d = open(ppm, "rb").read(); f = []; at = 2
while len(f) < 3:
    while d[at:at+1].isspace(): at += 1
    s = at
    while not d[at:at+1].isspace(): at += 1
    f.append(int(d[s:at]))
W, H, px = f[0], f[1], d[at+1:]
def P(x, y):
    i = (y * W + x) * 3
    return (px[i], px[i+1], px[i+2])
x, y, w, h, _ = pins["zzfb"]
bg = P(max(x - 6, 0), y + h // 2)
cnt = {}; diff = 0; white = 0; tot = 0
for yy in range(y + 2, y + h - 2):
    for xx in range(x + 2, x + w - 2):
        p = P(xx, yy); tot += 1
        cnt[p] = cnt.get(p, 0) + 1
        if sum(abs(p[i] - bg[i]) for i in range(3)) > 40: diff += 1
        if min(p) >= 235: white += 1
top = max(cnt.values()) if cnt else 0
solid = diff * 100 // max(tot, 1); one = top * 100 // max(tot, 1)
isTile = solid >= 40 and one >= 12 and white >= 15
print(("OK    " if (isTile == (expect == "fb")) else "FAIL  ") +
      "zzfb pin %dx%d at %d,%d: %d %% differ from the bar (bg %s), %d %% one colour, %d white ink px -> %s%s"
      % (w, h, x, y, solid, bg, one, white, "tile" if isTile else "no tile",
         "" if expect == "fb" else " (COUNTER: must NOT be a tile)"))
# the real symbols are not the tile: explorer's rectangle differs from zzfb's
ex = pins["explorer"]
a = [P(ex[0] + i, ex[1] + j) for j in range(0, ex[3], 3) for i in range(0, ex[2], 3)]
b = [P(x + i, y + j) for j in range(0, h, 3) for i in range(0, w, 3)]
n = min(len(a), len(b)); dd = sum(1 for i in range(n) if a[i] != b[i])
if expect == "fb":
    say(dd * 100 // max(n, 1) >= 20, "explorer (own symbol) differs from the zzfb tile in %d %% of the samples" % (dd * 100 // max(n, 1)))
PY
}

echo "== fallback on =="
run "$ROOT" fb
S="$OUTD/fb/serial.txt"
if [ ! -s "$S" ] || [ ! -s "$OUTD/fb/00-bar.ppm" ]; then bad "no serial/photo"; tail -5 "$OUTD/fb.log"; else
    while IFS= read -r l; do case "$l" in "OK "*) ok "${l#OK    }" ;; "FAIL "*) bad "${l#FAIL  }" ;; esac; done < <(judge fb fb)
fi

echo "== COUNTER-PROOF nofb (sym_fallback returns 0) =="
OLD="$OUTD/oldtree"
mkdir -p "$OLD"
tar -C "$ROOT" --exclude=.git --exclude='docs/shots' -cf - . | tar -C "$OLD" -xf -
python3 -I - "$OLD/kernel/user/taskbar.fi" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="latin1").read()
k = "fn sym_fallback(platz: u64, app: u64, ziel: u64) -> u64 {\n"
assert k in s
open(p, "w", encoding="latin1").write(s.replace(k, k + "    return 0\n", 1))
PY
run "$OLD" nofb
S="$OUTD/nofb/serial.txt"
if [ ! -s "$S" ] || [ ! -s "$OUTD/nofb/00-bar.ppm" ]; then bad "nofb: no serial/photo"; tail -5 "$OUTD/nofb.log"; else
    while IFS= read -r l; do case "$l" in "OK "*) ok "${l#OK    }" ;; "FAIL "*) bad "${l#FAIL  }" ;; esac; done < <(judge nofb nofb)
fi
rm -rf "$OLD" "$OUTD"/*-build
echo
echo "APPICON-QEMU: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
