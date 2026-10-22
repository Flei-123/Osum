#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/monset/run.sh -- r1590 gate: the Settings switch debug.mon (developer overlay, same overlay as Ctrl+Shift+F).
#
#   /root/jarvis/bin/heavy bash tools/monset/run.sh
#
# Run A: /etc/mouse.conf has mon=true at boot, no key pressed -> the overlay appears (`fpsov: shown`), its rectangle differs from run B.
# Run B (counter-proof): no mon line -> no fpsov line, no monov line.
# Run C: Settings -> Mouse -> click the switch (mmon) on, off, on: `settings: mouse ... mon=1/0/1 ok=1`, `fpsov: shown/hidden/shown` follow within seconds.
# eh6 boots without the `vfs` word and without /proc: both are added (EH_MKFS_EXTRA, extra=).
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

printf '# /etc/mouse.conf\nmon=true\n' > "$TMPD/mouse-on.conf"
cat > "$TMPD/a.txt" <<'DEOF'
warteauf 'taskbar: steht|taskbar: geom' || 120
warte 12
foto 01
DEOF
cp "$TMPD/a.txt" "$TMPD/b.txt"
cat > "$TMPD/c.txt" <<'DEOF'
warte 12
klick 24,780
warte 3
klickauf start_Settings
warte 12
klickauf srecttabp
warte 3
foto c-0
klickauf srectmmon
warte 5
foto c-on
klickauf srectmmon
warte 5
foto c-off
klickauf srectmmon
warte 5
foto c-on2
DEOF

run_one() { # name, drehbuch, etc extra
    mkdir -p "$TMPD/$1"
    EH_ETC_EXTRA="$3" EH_MKFS_EXTRA="/proc/" DESIGNBUILD="$TMPD/$1/build" bash tools/design/eh6.sh "$TMPD/$1/o" res=1280x800 accel=kvm tafel=nein "extra=vfs lang=en" \
        drehbuch="$2" > "$TMPD/$1/o.log" 2>&1
    rm -rf "$TMPD/$1/build"
}

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
run_one a "$TMPD/a.txt" "/etc/mouse.conf=$TMPD/mouse-on.conf@0644"
run_one b "$TMPD/b.txt" ""
run_one c "$TMPD/c.txt" ""
SA="$TMPD/a/o/serial.txt"; SB="$TMPD/b/o/serial.txt"; SC="$TMPD/c/o/serial.txt"
if [ -n "${MONSET_OUT:-}" ]; then
    mkdir -p "$MONSET_OUT"
    for r in a b c; do cp "$TMPD/$r/o/serial.txt" "$MONSET_OUT/serial-$r.txt" 2>/dev/null; cp "$TMPD/$r/o/"*.ppm "$MONSET_OUT/" 2>/dev/null; cp "$TMPD/$r/o.log" "$MONSET_OUT/log-$r.txt" 2>/dev/null; done
fi

diffpix() {
    python3 -I - "$@" <<'PY'
import sys
def load(p):
    d = open(p, "rb").read(); f = []; at = 2
    while len(f) < 3:
        while d[at:at+1].isspace(): at += 1
        s = at
        while not d[at:at+1].isspace(): at += 1
        f.append(int(d[s:at]))
    return f[0], d[at+1:]
W, a = load(sys.argv[1]); _, b = load(sys.argv[2])
x0, y0, w, h = (int(v) for v in sys.argv[3:7])
n = 0
for y in range(y0, y0 + h):
    o = (y * W + x0) * 3
    if a[o:o + w * 3] != b[o:o + w * 3]:
        for x in range(w):
            if a[o + x*3:o + x*3 + 3] != b[o + x*3:o + x*3 + 3]:
                n += 1
print(n)
PY
}
num() { echo "$1" | sed -E "s/.* $2=([0-9]+).*/\1/"; }

grep -aq 'fpsov: shown' "$SA" && ok "A: mon=true in the file at boot -> the overlay was shown" || bad "A: no 'fpsov: shown' with mon=true"
grep -aq 'wm: monov' "$SA" && bad "A: a hotkey line appeared without a key" || ok "A: no key was pressed (no 'wm: monov')"
sl=$(grep -a 'fpsov: shown x=' "$SA" | head -1 | sed 's/.*fpsov: shown/fpsov: shown/')
if [ -n "$sl" ] && [ -s "$TMPD/a/o/01.ppm" ] && [ -s "$TMPD/b/o/01.ppm" ]; then
    x=$(num "$sl" x); y=$(num "$sl" y); w=$(num "$sl" w); h=$(num "$sl" h)
    d=$(diffpix "$TMPD/a/o/01.ppm" "$TMPD/b/o/01.ppm" "$x" "$y" "$w" "$h")
    [ "$d" -gt $((w * h / 3)) ] && ok "A vs B: the overlay rectangle differs ($d of $((w * h)) pixels)" || bad "A vs B: only $d of $((w * h)) pixels differ"
else
    bad "A: no overlay rectangle or no pictures"
fi
if grep -aq 'fpsov: \|wm: monov' "$SB"; then bad "B COUNTER-PROOF: overlay lines without mon=true: $(grep -a 'fpsov: \|wm: monov' "$SB" | head -1)"
else ok "B COUNTER-PROOF: without mon=true there is no fpsov and no monov line"; fi

python3 -I - "$SC" <<'PY' && ok "C: clicks stored mon 1, 0, 1 (ok=1)" || bad "C: click effects"
import re, sys
t = open(sys.argv[1], "rb").read().decode("latin1")
L = [(int(m.group(1)), int(m.group(2))) for m in re.finditer(r"settings: mouse speed=\d+ accel=\d+ natural=\d+ gestures=\d+ ok=(\d+) fps=\d+ mon=(\d+)", t)]
print("states (ok, mon):", L)
L = L[-3:]
if len(L) < 3 or any(s[0] != 1 for s in L) or [s[1] for s in L] != [1, 0, 1]:
    sys.exit(1)
PY
python3 -I - "$SC" <<'PY' && ok "C: the overlay followed the switch: shown, hidden, shown" || bad "C: overlay did not follow (need shown, hidden, shown)"
import re, sys
t = open(sys.argv[1], "rb").read().decode("latin1")
ev = re.findall(r"fpsov: (shown|hidden)", t)
print("events:", ev)
if ev[:3] != ["shown", "hidden", "shown"]:
    sys.exit(1)
PY
grep -aq 'klickauf srectmmon -> KEIN' "$TMPD/c/o.log" && bad "C: click on mmon had no target" || ok "C: every click found its widget"
n=$(grep -ac 'ABSTURZ\|EXCEPTION\|panic' "$SA" "$SB" "$SC" | awk -F: '{s+=$2} END{print s+0}')
[ "$n" = 0 ] && ok "no crash or panic" || bad "crash lines: $n"
echo; echo "MONSET: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
