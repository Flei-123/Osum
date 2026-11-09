#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/monset/run.sh -- r1590 gate: the Settings switch debug.mon (developer overlay, same overlay as Ctrl+Shift+F).
#
#   /root/jarvis/bin/heavy bash tools/monset/run.sh
#
# Run A: /etc/mouse.conf has mon=true at boot, no key pressed -> the overlay appears (`fpsov: shown`), its rectangle differs from run B.
# Run B (counter-proof): no mon line -> no fpsov line, no monov line.
# Run C: Settings -> System -> Developer -> click the switch (dmon) on, off, on: `settings: mouse ... mon=1/0/1 ok=1`, `fpsov: shown/hidden/shown` follow within seconds, at scale 1 (1280x800) and scale 2 (1920x1080).
# Run M (counter-proof): settings built so the switch value never reaches the bus or /etc/mouse.conf -> the clicks are stored but the overlay never follows.
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
write_click_script() {
    local yres=$1
    cat > "$2" <<DEOF
warte 12
klick 24,$((yres - 20))
warte 3
klickauf start_Settings
warte 12
klickauf srecttabp
warte 3
foto c-mouse
klicksuche srecttabl 140,300
warte 3
klicksuche srecttab34 140,300
warte 3
foto c-0
klickauf srectdmon
warte 5
foto c-on
klickauf srectdmon
warte 5
foto c-off
klickauf srectdmon
warte 5
foto c-on2
DEOF
}
write_click_script 800 "$TMPD/c.txt"
write_click_script 1080 "$TMPD/c2.txt"
cp "$TMPD/c.txt" "$TMPD/m.txt"

SHARED_BUILD="$TMPD/build"
run_one() {
    local name=$1 script=$2 etc=$3 res=${4:-1280x800} scale=${5:-1} build=${6:-$SHARED_BUILD}
    mkdir -p "$TMPD/$name"
    EH_ETC_EXTRA="$etc" EH_MKFS_EXTRA="/proc/" DESIGNBUILD="$build" bash tools/design/eh6.sh "$TMPD/$name/o" res="$res" uiscale="$scale" accel=kvm tafel=nein "extra=vfs lang=en" \
        drehbuch="$script" > "$TMPD/$name/o.log" 2>&1
}

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
export FIRNLIB="$PWD/lib"
MUT="$TMPD/mutant"
mkdir -p "$MUT"
cp -a kernel/user "$MUT/user"
sed -i -e 's/mouse_bus_set((&k_mon\[0 as usize\]) as u64, ms_mon)/mouse_bus_set((\&k_mon[0 as usize]) as u64, 0)/' -e 's/^    if ms_mon != 0 {/    if 0 != 0 {/' "$MUT/user/settings/setpages.fi"
if cmp -s kernel/user/settings/setpages.fi "$MUT/user/settings/setpages.fi"; then bad "mutant source is identical to the real source"; fi

run_one a "$TMPD/a.txt" "/etc/mouse.conf=$TMPD/mouse-on.conf@0644"
run_one b "$TMPD/b.txt" ""
MUT_BUILD="$TMPD/build-mut"
cp -a "$SHARED_BUILD" "$MUT_BUILD"
if vendor/firn/bin/firnc -c "$MUT/user/settings.fi" -o "$MUT/settings.o" > "$MUT/cc.log" 2>&1 \
   && ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" -o "$MUT/settings.elf" "$MUT/settings.o" 2>>"$MUT/cc.log"; then
    strip --strip-all "$MUT/settings.elf"
    cp "$MUT/settings.elf" "$MUT_BUILD/settings.elf"
    ok "mutant settings (switch value never sent to the bus or the file) builds"
else
    bad "mutant settings does not build: $(head -5 "$MUT/cc.log")"
fi
run_one c "$TMPD/c.txt" "" &
run_one c2 "$TMPD/c2.txt" "" 1920x1080 2 &
run_one m "$TMPD/m.txt" "" 1280x800 1 "$MUT_BUILD" &
wait
SA="$TMPD/a/o/serial.txt"; SB="$TMPD/b/o/serial.txt"; SC="$TMPD/c/o/serial.txt"; SC2="$TMPD/c2/o/serial.txt"; SM="$TMPD/m/o/serial.txt"
if [ -n "${MONSET_OUT:-}" ]; then
    mkdir -p "$MONSET_OUT"
    for r in a b c c2 m; do cp "$TMPD/$r/o/serial.txt" "$MONSET_OUT/serial-$r.txt" 2>/dev/null; cp "$TMPD/$r/o/"*.ppm "$MONSET_OUT/" 2>/dev/null; cp "$TMPD/$r/o.log" "$MONSET_OUT/log-$r.txt" 2>/dev/null; done
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

clicks_stored() {
    python3 -I - "$1" <<'PY'
import re, sys
t = open(sys.argv[1], "rb").read().decode("latin1")
L = [(int(m.group(1)), int(m.group(2))) for m in re.finditer(r"settings: mouse speed=\d+ accel=\d+ natural=\d+ gestures=\d+ ok=(\d+) fps=\d+ mon=(\d+)", t)]
print("states (ok, mon):", L)
L = L[-3:]
if len(L) < 3 or any(s[0] != 1 for s in L) or [s[1] for s in L] != [1, 0, 1]:
    sys.exit(1)
PY
}
overlay_followed() {
    python3 -I - "$1" <<'PY'
import re, sys
t = open(sys.argv[1], "rb").read().decode("latin1")
ev = re.findall(r"fpsov: (shown|hidden)", t)
print("events:", ev)
if ev[:3] != ["shown", "hidden", "shown"]:
    sys.exit(1)
PY
}
placement_ok() {
    grep -aq 'settings: nav route=settings://system/developer page=34' "$1" || return 1
    for r in dfps dmon dpg mspeed; do grep -aq "settings: rect name=$r " "$1" || return 1; done
    for r in mfps mmon mpgd; do grep -aq "settings: rect name=$r " "$1" && return 1; done
    return 0
}
page_has() { python3 -I tools/monset/pagetext.py "$1" "$2"; }
for run in "C:$SC:$TMPD/c/o.log:$TMPD/c/o" "C2 (scale 2):$SC2:$TMPD/c2/o.log:$TMPD/c2/o"; do
    label=${run%%:*}; rest=${run#*:}; serial=${rest%%:*}; rest=${rest#*:}; log=${rest%%:*}; shots=${rest#*:}
    page_has "$shots/c-0.ppm" 'overlay' && page_has "$shots/c-0.ppm" 'pixel' && ok "$label: OCR of the Developer page shows the overlay and pixel check labels" || bad "$label: OCR of the Developer page lacks the switch labels"
    page_has "$shots/c-mouse.ppm" 'pointer|speed|accel|scroll|gesture' && ! page_has "$shots/c-mouse.ppm" 'overlay' && ! page_has "$shots/c-mouse.ppm" 'pixel.check' && ok "$label: OCR of the Mouse page shows pointer controls and none of the debug labels" || bad "$label: OCR of the Mouse page (pointer label missing or debug labels left)"
    placement_ok "$serial" && ok "$label: switches live on the Developer page (dfps, dmon, dpg), the Mouse page keeps only its own controls" || bad "$label: switch placement (Developer page or leftovers on the Mouse page)"
    clicks_stored "$serial" && ok "$label: clicks stored mon 1, 0, 1 (ok=1)" || bad "$label: click effects"
    overlay_followed "$serial" && ok "$label: the overlay followed the switch: shown, hidden, shown" || bad "$label: overlay did not follow (need shown, hidden, shown)"
    grep -aq 'klickauf srectdmon -> KEIN' "$log" && bad "$label: click on dmon had no target" || ok "$label: every click found its widget"
done
sed -e 's/name=dmon /name=mmon /' "$SC" > "$TMPD/doctored.txt"
page_has "$TMPD/c/o/c-mouse.ppm" 'overlay' && bad "OCR COUNTER-PROOF: the Mouse picture matched the Developer label" || ok "OCR COUNTER-PROOF: the Mouse picture does not match the Developer label (the check tells the pages apart)"
placement_ok "$TMPD/doctored.txt" && bad "PLACEMENT COUNTER-PROOF: a log with the old mmon rect still passed" || ok "PLACEMENT COUNTER-PROOF: a log with the switch back on the Mouse page fails the placement check"
clicks_stored "$SM" && ok "M COUNTER-PROOF: the mutant still stores mon 1, 0, 1" || bad "M COUNTER-PROOF: mutant did not take the clicks"
overlay_followed "$SM" && bad "M COUNTER-PROOF: the overlay followed although the value never reached the bus or the file" || ok "M COUNTER-PROOF: without the value on the bus or in the file the overlay does not follow"
n=$(grep -ac 'CRASH\|EXCEPTION\|panic' "$SA" "$SB" "$SC" "$SC2" | awk -F: '{s+=$2} END{print s+0}')
[ "$n" = 0 ] && ok "no crash or panic" || bad "crash lines: $n"
echo; echo "MONSET: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
