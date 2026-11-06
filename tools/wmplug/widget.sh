#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/wmplug/widget.sh -- DAS LEISTENWIDGET, GEMESSEN.
#
#
#
#
#
# Die Bilder landen in docs/shots/wmplug/.
#
# Gebrauch: bash tools/wmplug/widget.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
. tools/lib/userprog.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

TMPD=$(mktemp -d /tmp/wmplug-widget-XXXXXX)
[ "${WIDGET_KEEP:-0}" = 1 ] || trap 'rm -rf "$TMPD"' EXIT
SHOTS="docs/shots/wmplug"
mkdir -p "$SHOTS"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' sollte nicht da sein" || ok "$3"; }

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "WIDGET: skipped, qemu-system-x86_64 is missing"; exit 0
fi
bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "firnc fehlt"; exit 1; }

echo "== 1. bauen =="
bash tools/build-kernel.sh "$TMPD/k.mb" > "$TMPD/k.log" 2>&1 \
    && ok "Kernel gebaut ($(stat -c%s "$TMPD/k.mb") Oktette)" \
    || { bad "the kernel does not build"; tail -12 "$TMPD/k.log" | sed 's/^/        /'; }
[ -f "$TMPD/k.mb" ] || { echo "WIDGET: $pass bestanden, $((fail+1)) gescheitert"; exit 1; }

as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s assembliert nicht"
PROGS="desktop taskbar launcher pluguhr sh echo ls cat"
[ -f kernel/user/wmplug.fi ] && PROGS="$PROGS wmplug"
gebaut=1
for p in $PROGS; do
    up_build vendor/firn/bin/firnc "$p" "$TMPD/$p.o" "$TMPD/$p.elf" \
        "$TMPD/crt.o" kernel/user/user.ld 0 "$TMPD/$p.err" || {
        bad "firnc0 uebersetzt $p.fi nicht"
        sed 's/^/        /' "$TMPD/$p.err" | head -6; gebaut=0; }
done
[ "$gebaut" = 1 ] && ok "$(echo $PROGS | wc -w) Programme gebaut, /bin/pluguhr ist $(stat -c%s "$TMPD/pluguhr.elf") Oktette"

for sym in pluguhr__bauen pluguhr__u_start; do
    if nm -a "$TMPD/k.mb.elf" 2>/dev/null | grep -q "$sym"; then
        bad "the kernel carries $sym -- a plugin belongs in ring 3"
    else
        ok "the kernel does NOT carry $sym (the widget is a ring 3 process)"
    fi
done

python3 tools/k15/tree.py "$TMPD/baum" > "$TMPD/baum.log" 2>&1 \
    && ok "the directory tree is ready" || bad "tools/k15/tree.py fehlgeschlagen"

echo "== 2. das Abbild =="
ARGS=(build "$TMPD/disk.img" 32768 /lib/
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" /bin/)
for p in $PROGS; do
    ARGS+=("/bin/$p=$TMPD/$p.elf")
done
printf 'on\n' > "$TMPD/uitrace"
ARGS+=(/etc/ "/etc/theme=$TMPD/baum/theme" "/etc/uitrace=$TMPD/uitrace")
[ -f etc/wmplug.conf ] && ARGS+=("/etc/wmplug.conf=etc/wmplug.conf")
while read -r z; do ARGS+=("$z"); done < "$TMPD/baum/liste"
bash tools/mkfsfi/mkfs.sh "${ARGS[@]}" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "the image is built" \
    || { bad "mkfs.py fehlgeschlagen"; sed 's/^/        /' "$TMPD/mkfs.txt" | head -5; }

BASE="gfx wm wig desk wmhold wiglong nokbd nosched noproc nofs wmplug"
OHNE="gfx wm wig desk wmhold wiglong nokbd nosched noproc nofs plugaus"
warte() { # datei marke pid [schritte]
    local f=$1 m=$2 pid=$3 n=${4:-600} i=0
    while [ $i -lt "$n" ]; do
        grep -qa "$m" "$f" 2>/dev/null && return 0
        kill -0 "$pid" 2>/dev/null || return 1
        sleep 0.2; i=$((i+1))
    done
    return 1
}

lauf() { # name zusatz [marke1] [marke2]
    local name=$1 extra=$2 m1=${3:-} m2=${4:-}
    local sock="$TMPD/mon-$name.sock" out="$TMPD/$name.txt" ppm="$TMPD/$name.ppm"
    rm -f "$out" "$ppm" "$sock"
    cp -f "$TMPD/disk.img" "$TMPD/live-$name.img"
    timeout 240 $QEMU_X86 -kernel "$TMPD/k.mb" -m 256 \
        -append "${ZEILE:-$BASE} $extra" -serial "file:$out" -display none -no-reboot \
        -vga std -global VGA.edid=off -monitor "unix:$sock,server,nowait" \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/$name.qemu" 2>&1 &
    local pid=$!
    warte "$out" "${m1:-^wm: hold}" "$pid"
    sleep 2
    python3 tools/gfx/screenshot.py "$sock" "$ppm" 25 > "$TMPD/$name.shot" 2>&1
    wc -l < "$out" > "$TMPD/$name.marke"
    if [ -n "$m2" ]; then
        warte "$out" "$m2" "$pid"
        sleep 3
        python3 tools/gfx/screenshot.py "$sock" "$TMPD/$name-2.ppm" 25 \
            > "$TMPD/$name-2.shot" 2>&1
    fi
    wait "$pid"; rm -f "$sock"
    tr -d '\000' < "$out" > "$out.clean"
}

echo "== 3. the run WITHOUT widget =="
lauf aus ""
has "$TMPD/aus.txt" "wm: hold" "der Schreibtisch steht (aus)"
hasnot "$TMPD/aus.txt" "taskbar: plug nr=" "ohne Widget meldet die Leiste kein Widget-Feld"
cp -f "$TMPD/aus.ppm" "$SHOTS/widget-aus.ppm" 2>/dev/null

echo "== 4. the run WITH widget =="
lauf an "wigapp=/bin/wmplug,enable,uhr,runden=20 wighalt=40" "taskbar: text plug " "pluguhr: end rounds="
has "$TMPD/an.txt" "wm: hold" "der Schreibtisch steht (an)"
has "$TMPD/an.txt" "wmplug: reg uhr" "das Widget hat sich angemeldet"
has "$TMPD/an.txt" "pluguhr: angemeldet" "und sagt es selbst"
has "$TMPD/an.txt" "pluguhr: text " "es schickt Text"
has "$TMPD/an.txt" "pluguhr: frist ticks=" "es liest die Frist des Kerns"
hasnot "$TMPD/an.txt" "pluguhr: KEIN recht" "es hat R_ACT_BAR bekommen"
has "$TMPD/an.txt" "taskbar: plug nr=0" "die Leiste hat ein Widget-Feld"
has "$TMPD/an.txt" "taskbar: text plug " "und malt seinen Text"
if grep -qaE '^wmplug: unreg uhr *grund=2' "$TMPD/an.txt.clean"; then
    bad "the deadline was missed (reason=2) -- the widget collects too rarely"
else
    ok "the deadline was not missed (no reason=2)"
fi
has "$TMPD/an.txt" "pluguhr: barget verweigert r=-2" \
    "das Plugin selbst darf WM_PLUG_BARGET NICHT (E_RIGHTS = -2)"
if grep -qaE '^wmplug: unreg uhr *grund=0' "$TMPD/an.txt.clean"; then
    ok "it unregistered ITSELF at run time (reason=0)"
else
    bad "no unregistration with reason=0 -- the widget did not leave cleanly"
fi
cp -f "$TMPD/an.ppm" "$SHOTS/widget-an.ppm" 2>/dev/null
cp -f "$TMPD/an-2.ppm" "$SHOTS/widget-aus-laufzeit.ppm" 2>/dev/null

echo "== 5. the computation at the named coordinate =="
zeile=$(head -n "$(cat "$TMPD/an.marke")" "$TMPD/an.txt" \
    | grep -a '^taskbar: plug nr=0 ' | tail -1)
gline=$(grep -a '^taskbar: geom ' "$TMPD/an.txt" | tail -1)
zahl() { printf '%s' "$1" | grep -oE " $2=[0-9]+" | head -1 | sed 's/.*=//'; }
pfarbe() { python3 tools/gfx/checkshot.py pixel "$1" "$2" "$3" 2>/dev/null; }

punktdiff() { python3 - "$@" <<'PY'
import sys
def load(p):
    d = open(p, 'rb').read()
    teile = []; i = 2
    while len(teile) < 3:
        while i < len(d) and d[i:i+1].isspace(): i += 1
        if d[i:i+1] == b'#':
            while d[i:i+1] != b'\n': i += 1
            continue
        j = i
        while j < len(d) and not d[j:j+1].isspace(): j += 1
        teile.append(int(d[i:j])); i = j
    i += 1
    return teile[0], teile[1], d[i:]
a = load(sys.argv[1]); b = load(sys.argv[2])
x0, y0, w, h = (int(v) for v in sys.argv[3:7])
n = 0
for y in range(y0, min(y0 + h, a[1], b[1])):
    for x in range(x0, min(x0 + w, a[0], b[0])):
        o = (y * a[0] + x) * 3
        if a[2][o:o+3] != b[2][o:o+3]: n += 1
print(n)
PY
}
px=$(zahl "$zeile" x); py=$(zahl "$zeile" y)
pw=$(zahl "$zeile" w); ph=$(zahl "$zeile" h)
gx=$(zahl "$gline" x); gy=$(zahl "$gline" y)
gx=${gx:-0}; gy=${gy:-0}
if [ -z "$px" ] || [ -z "$pw" ]; then
    bad "the bar reports no widget box -- without it there is nothing to recompute"
else
    cx=$((gx + px + pw / 2)); cy=$((gy + py + ph / 2))
    ok "the widget box is at x=$px y=$py w=$pw h=$ph, centre in the image ($cx,$cy)"
    d=$(punktdiff "$SHOTS/widget-an.ppm" "$SHOTS/widget-aus.ppm" \
        "$((gx+px))" "$((gy+py))" "$pw" "$ph")
    if [ "${d:-0}" -gt 40 ]; then
        ok "in the widget box $d pixels differ between ON and OFF"
    else
        bad "ON and OFF differ in the widget box in only ${d:-0} pixels"
    fi
    aus=$(python3 tools/gfx/checkshot.py pixel "$SHOTS/widget-aus.ppm" "$cx" "$cy" 2>&1)
    an=$(python3 tools/gfx/checkshot.py pixel "$SHOTS/widget-an.ppm" "$cx" "$cy" 2>&1)
    if [ "$aus" != "$an" ]; then
        ok "checkshot pixel ($cx,$cy): off=[$aus] on=[$an] -- different"
    else
        bad "checkshot pixel ($cx,$cy): both [$an] -- no difference at the centre"
    fi
    it=$(python3 tools/gfx/checkshot.py area "$SHOTS/widget-an.ppm" \
        "$((gx+px))" "$((gy+py))" "$pw" "$ph" $(pfarbe "$SHOTS/widget-an.ppm" "$((gx+px+1))" "$((gy+py+1))") 2>&1 \
        | grep -oE '^[0-9]+')
    if [ "${it:-0}" -gt 20 ]; then
        ok "im Widget-Kasten stehen $it Bildpunkte Tinte (AN)"
    else
        bad "no ink in the widget box (${it:-0} points) -- the text is missing"
    fi
fi

echo "== 6. on and off AT RUN TIME, in the same run =="
if [ ! -s "$SHOTS/widget-aus-laufzeit.ppm" ]; then
    bad "the second photo of the run is missing"
elif [ -z "${px:-}" ]; then
    bad "without widget box there is nothing to recompute"
else
    d2=$(punktdiff "$SHOTS/widget-an.ppm" "$SHOTS/widget-aus-laufzeit.ppm" \
        "$((gx+px))" "$((gy+py))" "$pw" "$ph")
    if [ "${d2:-0}" -gt 40 ]; then
        ok "after unregistering $d2 pixels in the box changed"
    else
        bad "after unregistering the image is unchanged (${d2:-0} points)"
    fi
    it2=$(punktdiff "$SHOTS/widget-aus.ppm" "$SHOTS/widget-aus-laufzeit.ppm" \
        "$((gx+px))" "$((gy+py))" "$pw" "$ph")
    ok "in the box $it2 points then differ from the run without widget (ink before: $it)"
    if [ "${it2:-0}" -lt "${it:-0}" ]; then
        ok "the widget text is gone without the window server being restarted"
    else
        bad "the widget text is still there (${it2:-0} instead of fewer than ${it:-0})"
    fi
fi

echo "== 6b. WHERE DOES THE NUMBER IN THE BAR COME FROM? =="
#
#
paare=$(awk '
    /^pluguhr: text / { letzte = substr($0, 15); sub(/[ \t\r]+$/, "", letzte); next }
    /^taskbar: text plug / {
        i = index($0, " t=")
        if (i == 0) next
        gemalt = substr($0, i + 3); sub(/[ \t\r]+$/, "", gemalt)
        if (letzte == "") next          # gemalt, bevor je Text kam
        n++
        if (gemalt != letzte) { schlecht++; if (bsp == "") bsp = gemalt " != " letzte }
    }
    END { printf "%d %d %s\n", n+0, schlecht+0, bsp }
' "$TMPD/an.txt.clean")
set -- $paare
pn=${1:-0}; pfalsch=${2:-0}; shift 2 || true
if [ "$pn" -lt 1 ]; then
    bad "no pair of 'pluguhr: text' und 'taskbar: text plug' im Lauf"
elif [ "$pfalsch" != 0 ]; then
    bad "$pfalsch of $pn painted texts do NOT come from the plugin ($*)"
else
    ok "all $pn painted widget texts are exactly the last one sent (cpu value proven)"
fi
if grep -qaE '^pluguhr: text [0-9][0-9]:[0-9][0-9]' "$TMPD/an.txt.clean"; then
    bad "the widget sends a time of day again -- the bar already has that"
else
    ok "the widget no longer sends a time of day (load only), the clock stays with the bar"
fi
if grep -qaE '^pluguhr: text cpu [0-9]+%' "$TMPD/an.txt.clean"; then
    ok "the text has the form 'cpu NN%' ($(grep -a '^pluguhr: text ' "$TMPD/an.txt.clean" | tail -1))"
else
    bad "the widget text does not have the form 'cpu NN%'"
fi

echo "== 6c. the gap between widget field and clock, at 640x480 =="
ZEILE="$BASE fbres=640x480" lauf eng "wigapp=/bin/wmplug,enable,uhr,runden=20" \
    "taskbar: text plug "
has "$TMPD/eng.txt" "taskbar: plug nr=0" "bei 640x480 hat die Leiste ein Widget-Feld"
ezeile=$(grep -a '^taskbar: plug nr=0 ' "$TMPD/eng.txt" | tail -1)
epx=$(zahl "$ezeile" x); epw=$(zahl "$ezeile" w)
eminx=$(grep -a '^taskbar: field ' "$TMPD/eng.txt" | awk '
    { name = $3; i = index($0, " x="); rest = substr($0, i + 3)
      split(rest, t, " "); x[name] = t[1] + 0 }
    END { m = -1
          for (k in x) if (m < 0 || x[k] < m) m = x[k]
          print m }')
if [ -z "$epx" ] || [ -z "${eminx:-}" ] || [ "${eminx:--1}" -lt 0 ]; then
    bad "at 640x480 the numbers for the gap are missing (box='$ezeile')"
else
    abstand=$((eminx - epx - epw))
    if [ "$abstand" -ge 8 ]; then
        ok "Abstand Widgetfeld -> linkestes Leistenfeld: $abstand px (>= 8), 640x480"
    else
        bad "gap only $abstand px at 640x480 (box x=$epx w=$epw, field x=$eminx)"
    fi
fi
cp -f "$TMPD/eng.ppm" "$SHOTS/widget-eng-640x480.ppm" 2>/dev/null

echo "== 7. control: the same kernel WITHOUT plugin table =="
#
ZEILE="$OHNE" lauf zu ""
has "$TMPD/zu.txt" "wm: hold" "der Schreibtisch steht auch ohne Plugintafel"
has "$TMPD/zu.txt" "taskbar: geom " "die Leiste meldet ihre Lage wie immer"
hasnot "$TMPD/zu.txt" "taskbar: plug nr=" "und hat kein Widget-Feld"
has "$TMPD/zu.txt" "tafel= zu" "mit plugaus ist die Plugintafel zu"

for b in widget-an widget-aus widget-aus-laufzeit widget-eng-640x480; do
    if [ -s "$SHOTS/$b.ppm" ]; then
        python3 tools/gfx/ppm2png.py "$SHOTS/$b.ppm" "$SHOTS/$b.png" \
            > /dev/null 2>&1 && rm -f "$SHOTS/$b.ppm"
    fi
done

echo
echo "WIDGET: $pass bestanden, $fail gescheitert"
[ "$fail" = 0 ] || exit 1
