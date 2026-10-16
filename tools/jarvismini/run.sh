#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/jarvismini/run.sh -- W-S5B gate: JARVIS MINI (kernel/user/jarvismini.fi) in the real desktop, with a chat stub on the host.
#
#   /root/jarvis/bin/heavy bash tools/jarvismini/run.sh
#
# Machine: the stick's (tools/design/eh6.sh, netz=ja: e1000 + QEMU user net, the guest reaches the host at 10.0.2.2) with the bus, the
# hotkey helper (started by the DESKTOP autostart: /etc/wmplug.autostart + /etc/hotkeys.conf), the bundle /apps/jarvismini.osp and the
# test driver /bin/mbg (wigapp: a black background window over the lower right half; 14 s later it starts `jarvismini --as-app`, i.e. the
# process labels itself app:jarvismini and drops to uid 1000 so the rights are REALLY checked; a pointer press on it switches black <-> white).
# /etc/apprights.conf grants window.float,hotkey,net (boot A) or nothing (boot B). tools/jarvismini/stub.py runs on the host.
#
# Boot A (rights granted):
#   1. the box is on the layer L_FLOAT (8), lower right of the work area (12 px from the edges), translucent
#   2. a typed line goes to the stub; the three answer lines come back and the box GROWS (lines, height, y moves up)
#   3. Ctrl+Alt+J (QEMU sendkey -> window server -> hotkeyd -> bus -> jarvismini.toggle): the box hides (pixels differ), again: it shows
#   4. the text colour: white on the black background; the background turns white -> ONE change to black (flips=1), no flicker before
# Boot B (COUNTER-PROOF, no grants): the float request is refused (E_RIGHTS), the box is an ordinary window on layer 1; hotkeyd refuses the
#   binding (reason=no-right); Ctrl+Alt+J does nothing.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
D=$(mktemp -d)
STUBPIDS=""
cleanup() { for p in $STUBPIDS; do kill "$p" 2>/dev/null; done; rm -rf "$D"; [ -n "${JM_BUILD:-}" ] || rm -rf "$BUILD"; }
trap cleanup EXIT
BUILD=${JM_BUILD:-$D/build}
mkdir -p "$BUILD"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
RES=1280x800
SW=1280; SH=800
if [ -z "${DRIVE_TIPPE_GAP:-}" ]; then
    LOAD1=$(cut -d. -f1 /proc/loadavg)
    if [ "$LOAD1" -ge 40 ]; then DRIVE_TIPPE_GAP=0.8; elif [ "$LOAD1" -ge 20 ]; then DRIVE_TIPPE_GAP=0.5; else DRIVE_TIPPE_GAP=0.3; fi
fi
export DRIVE_TIPPE_GAP
PORT=$(( 24000 + ($$ % 3000) ))

# ---------------------------------------------------------------- shared image parts
printf '10.0.2.2 %s\n' "$PORT" > "$D/jarvismini.conf"
printf '# test: the hotkey helper\nhotkey\n' > "$D/autostart"
printf 'jarvismini window.float,hotkey,net\n' > "$D/rights.yes"
printf '# no grants\n' > "$D/rights.no"
MORE="orientbus act wmplug hotkeyd jarvismini apprights mbg"
EXTRA_COMMON="/etc/jarvismini.conf=$D/jarvismini.conf@0644 /etc/hotkeys.conf=etc/hotkeys.conf@0644 /etc/wmplug.conf=etc/wmplug.conf@0644 /etc/wmplug.autostart=$D/autostart@0644 /etc/actions.d/jarvismini.actions=etc/actions.d/jarvismini.actions@0644 /apps/ /apps/jarvismini.osp/ /apps/jarvismini.osp/INFO=pakete/jarvismini/INFO@0644 /apps/jarvismini.osp/start@/bin/jarvismini"

start_stub() { # $1 = name
    python3 -u tools/jarvismini/stub.py "$PORT" 127.0.0.1 > "$D/$1.stub" 2>&1 &
    STUBPIDS="$STUBPIDS $!"
    local i=0; while [ $i -lt 50 ] && ! grep -qa 'stub: listening' "$D/$1.stub" 2>/dev/null; do sleep 0.1; i=$((i+1)); done
}
stop_stubs() { for p in $STUBPIDS; do kill "$p" 2>/dev/null; done; STUBPIDS=""; sleep 0.3; }

run_boot() { # $1 = name, $2 = rights file
    local O="$D/$1"
    EH_APPEND=rtcutc EH_MKFS_EXTRA="$EXTRA_COMMON /etc/apprights.conf=$2@0644" \
        DESIGNBUILD="$BUILD" bash tools/design/eh6.sh "$O" "res=$RES" accel=kvm netz=ja tafel=nein "moreprogs=$MORE" \
            "extra=wmplug wigapp=/bin/mbg" "drehbuch=$D/$1.book" > "$D/$1.log" 2>&1
}

S_CLK="$(( SW / 2 + 40 )),$(( SH * 3 / 8 + 40 ))"
S_IN="$(( SW - 150 )),$(( 760 - 12 - 24 ))"

# ---------------------------------------------------------------- boot A script
cat > "$D/A.book" <<EOF
warteauf '(?m)^mbg: up' || 150
warteauf 'jarvismini: up float=1' || 120
warte 4
foto 01-up
klick $S_IN
warte 1
tippe hello
taste ret
warteauf 'jarvismini: sent len=5' || 30
warte 8
foto 02-answer
marke 'jarvismini: toggle='
taste ctrl-alt-j
warteneu 'jarvismini: toggle=' || 30
warte 5
foto 03-hidden
marke 'jarvismini: toggle='
taste ctrl-alt-j
warteneu 'jarvismini: toggle=' || 30
warte 5
foto 04-shown
klick $S_CLK
warteauf 'mbg: flip 1' || 30
warteauf 'jarvismini: text=black' || 40
warte 6
foto 05-black
EOF
cat > "$D/B.book" <<EOF
warteauf '(?m)^mbg: up' || 150
warteauf 'jarvismini: (up float=|float refused)' || 120
warte 8
foto 01-up
taste ctrl-alt-j
warte 6
foto 02-key
EOF

echo "== boot A (rights granted) =="
start_stub A
run_boot A "$D/rights.yes"
stop_stubs
SA="$D/A/serial.txt"
[ -s "$SA" ] || { bad "boot A: no serial output"; tail -15 "$D/A.log"; }
echo "== boot B (no grants, counter-proof) =="
start_stub B
run_boot B "$D/rights.no"
stop_stubs
SB="$D/B/serial.txt"
[ -s "$SB" ] || { bad "boot B: no serial output"; tail -15 "$D/B.log"; }

# ---------------------------------------------------------------- checks (python reads the serial lines tolerantly and the photos)
OUTP="$D/checks.txt"
python3 - "$D" "$SW" "$SH" > "$OUTP" 2>&1 <<'PYEOF'
import re, sys
d, SW, SH = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
def rd(p):
    try:
        return open(p, "rb").read().decode("latin1")
    except OSError:
        return ""
def clean(t):
    # cut kernel lines written in the middle of an app line
    t = re.sub(r"(elf: (?:seg|start) [^\n]*|wm: [^\n]*|wmplug: [^\n]*|desk: [^\n]*)\n", "", t)
    return t
def res(name, okv, text):
    print(("OK    " if okv else "FAIL  ") + name + (": " + text if text else ""))
def ppm(p):
    b = open(p, "rb").read()
    m = re.match(rb"P6\s+(\d+)\s+(\d+)\s+(\d+)\s", b)
    w, h = int(m.group(1)), int(m.group(2))
    return w, h, b[m.end():]
def px(img, x, y):
    w, h, data = img
    o = (y * w + x) * 3
    return data[o], data[o + 1], data[o + 2]
def lum(c):
    return (2126 * c[0] + 7152 * c[1] + 722 * c[2]) / 10000.0
def region(img, x, y, w, h):
    return [px(img, i, j) for j in range(y, y + h) for i in range(x, x + w)]

for tag in ("A", "B"):
    raw = rd(f"{d}/{tag}/serial.txt")
    t = clean(raw)
    geoms = re.findall(r"jarvismini: geom x=(\d+) y=(\d+) w=(\d+) h=(\d+) layer=(\d+) hidden=(\d+) opac=(\d+) lines=(\d+) vis=(\d+) work=(\d+),(\d+),(\d+),(\d+)", t)
    print(f"# boot {tag}: {len(geoms)} geom lines")
    if tag == "A":
        res("A: the box came up on the float layer with the bus and the net", bool(re.search(r"jarvismini: up float=1 bus=1 net=\d+", t)), "")
        ups = [g for g in geoms]
        lay = [int(g[4]) for g in ups]
        res("A: every geometry report says layer 8 (L_FLOAT)", bool(lay) and all(l == 8 for l in lay), f"layers={sorted(set(lay))}")
        if ups:
            g0 = ups[0]
            x, y, w, h = map(int, g0[:4]); wx, wy, ww, wh = map(int, g0[9:13])
            # growth: first report vs last report with hidden=0
            vis = [g for g in ups if g[5] == "0"]
            gl = vis[-1]
            xl, yl, wl, hl = map(int, gl[:4])
            res("A: lower right corner: right edge 12 px from the work area edge", abs((xl + wl) - (wx + ww - 12)) <= 2, f"x+w={xl+wl} work right={wx+ww}")
            res("A: lower right corner: bottom edge 12 px above the work area bottom", abs((yl + hl) - (wy + wh - 12)) <= 2, f"y+h={yl+hl} work bottom={wy+wh}")
            res("A: the height GROWS after the answer (3 reply lines)", hl > h and int(gl[7]) >= 4, f"h {h} -> {hl}, lines {g0[7]} -> {gl[7]}")
            res("A: the window is translucent (opac < 256)", 100 < int(gl[6]) < 256, f"opac={gl[6]}")
        res("A: the stub got the typed line", "stub: rx hello" in rd(f"{d}/A.stub"), "")
        tg = re.findall(r"jarvismini: toggle=(\d)", t)
        res("A: Ctrl+Alt+J twice: toggle 0 then 1", tg[:2] == ["0", "1"], f"toggles={tg}")
        res("A: hidden=1 seen while hidden, hidden=0 after", any(g[5] == "1" for g in geoms) and geoms and geoms[-1][5] == "0", "")
        res("A: hotkeyd was started by the desktop autostart", bool(re.search(r"desktop: autostart \[hotkey\] pid=", clean(raw)) or "hotkeyd: bound ctrl+alt+j jarvismini.toggle" in raw), "")
        res("A: hotkeyd bound the key", "hotkeyd: bound ctrl+alt+j jarvismini.toggle" in raw, "")
        tx = re.findall(r"jarvismini: text=(white|black) lum=(\d+) flips=(\d+) opac=(\d+)", t)
        cols = [c[0] for c in tx]
        firstblack = cols.index("black") if "black" in cols else -1
        res("A: text colour white on the black background", bool(cols) and cols[0] == "white", f"first={cols[:1]}")
        res("A: after the background turned white the text is black", firstblack > 0, "")
        fl = [int(c[2]) for c in tx]
        res("A: exactly ONE colour change in total (hysteresis, no flicker)", bool(fl) and max(fl) == 1 and fl[-1] == 1, f"flips max={max(fl) if fl else None}")
        if firstblack > 0:
            res("A: no white report after the change", "white" not in cols[firstblack:], "")
        # photos
        try:
            i1, i3, i4, i5 = (ppm(f"{d}/A/{n}.ppm") for n in ("01-up", "03-hidden", "04-shown", "05-black"))
            i2 = ppm(f"{d}/A/02-answer.ppm")
            if ups and vis:
                xl, yl, wl, hl = map(int, vis[-1][:4])
                R2 = region(i2, xl, yl, wl, hl); R3 = region(i3, xl, yl, wl, hl); R4 = region(i4, xl, yl, wl, hl)
                diff = sum(1 for a, b in zip(R2, R3) if max(abs(a[k] - b[k]) for k in range(3)) > 24)
                res("A: hidden: the box area differs from the shown box (pixels)", diff > wl * hl // 5, f"{diff} of {wl*hl}")
                same = sum(1 for a, b in zip(R2, R4) if max(abs(a[k] - b[k]) for k in range(3)) > 24)
                res("A: shown again: the box area equals the first shown picture", same < wl * hl // 20, f"{same} of {wl*hl} differ")
                R5 = region(i5, xl, yl, wl, hl)
                m2 = sum(lum(c) for c in R2) / len(R2); m5 = sum(lum(c) for c in R5) / len(R5)
                res("A: black background -> dark box area, white background -> bright box area", m2 < 90 and m5 > 160, f"mean lum {m2:.0f} -> {m5:.0f}")
                dark5 = sum(1 for c in R5 if lum(c) < 70); bright2 = sum(1 for c in R2 if lum(c) > 190)
                res("A: text pixels: bright text on black, dark text on white", dark5 > 150 and bright2 > 150, f"dark text px {dark5}, bright text px {bright2}")
        except Exception as e:
            res("A: photos readable", False, repr(e))
    else:
        res("B: the float request was refused, the box fell back", "jarvismini: float refused: ordinary window" in t, "")
        res("B: the box still came up (ordinary window)", "jarvismini: up float=0" in t, "")
        lay = [int(g[4]) for g in geoms]
        res("B: the window sits on layer 1 (L_NORMAL)", bool(lay) and all(l == 1 for l in lay), f"layers={sorted(set(lay))}")
        res("B: hotkeyd refused the binding (no right)", "hotkeyd: refused ctrl+alt+j jarvismini.toggle reason=no-right" in clean(raw) or "reason=no-right" in raw, "")
        res("B: Ctrl+Alt+J did nothing (no toggle line)", "jarvismini: toggle=" not in t, "")
PYEOF
cat "$OUTP"
pass=$((pass + $(grep -c '^OK' "$OUTP")))
fail=$((fail + $(grep -c '^FAIL' "$OUTP")))
if [ -n "${JM_KEEP:-}" ]; then rm -rf "$JM_KEEP"; mkdir -p "$JM_KEEP"; cp -r "$D/A" "$D/B" "$JM_KEEP"/ 2>/dev/null; cp "$D"/*.log "$D"/*.stub "$OUTP" "$JM_KEEP"/ 2>/dev/null; rm -f "$JM_KEEP"/*/disk.img; fi
echo "JARVISMINI: $pass passed, $fail failed"
[ "$fail" = 0 ]
