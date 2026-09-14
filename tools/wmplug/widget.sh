#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/wmplug/widget.sh -- DAS LEISTENWIDGET, GEMESSEN.
#
# Modul `widget` der Runde WMPLUGIN. Zwei Laeufe desselben Kernels und
# desselben Abbilds, ein einziger Unterschied auf der Kommandozeile:
#
#   AUS: gfx wm wig desk wmplug ...                (kein Widget)
#   AN : ... wigapp=/bin/uhrstart                  (Rechte + /bin/pluguhr)
#
# Danach wird NICHT verglichen, was "anders aussieht", sondern eine
# BENANNTE Koordinate nachgerechnet: die Mitte des Kastens, den die
# Leiste fuer den Widget-Text meldet (`taskbar: plug nr=0 x= y= w= h=`).
# Im AN-Bild steht dort Leistenfarbe mit Text darin, im AUS-Bild die
# Fensterknopf-Zone -- dieselbe Stelle, zwei Bilder, eine Rechnung
# (tools/gfx/checkshot.py).
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
    echo "WIDGET: uebersprungen, qemu-system-x86_64 ist nicht da"; exit 0
fi
bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "firnc fehlt"; exit 1; }

echo "== 1. bauen =="
bash tools/build-kernel.sh "$TMPD/k.mb" > "$TMPD/k.log" 2>&1 \
    && ok "Kernel gebaut ($(stat -c%s "$TMPD/k.mb") Oktette)" \
    || { bad "der Kernel baut nicht"; tail -12 "$TMPD/k.log" | sed 's/^/        /'; }
[ -f "$TMPD/k.mb" ] || { echo "WIDGET: $pass bestanden, $((fail+1)) gescheitert"; exit 1; }

as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s assembliert nicht"
PROGS="desktop taskbar launcher pluguhr _dev_uhrstart sh echo ls cat"
# /bin/wmplug gehoert dem Modul `verwaltung`. Ist es schon da, nimmt der
# Starthelfer es (`wmplug enable uhr`); fehlt es, faellt er auf den
# nackten WM_PLUG_GRANT zurueck. Dieses Modul wartet auf niemanden.
[ -f kernel/user/wmplug.fi ] && PROGS="$PROGS wmplug"
gebaut=1
for p in $PROGS; do
    up_build vendor/firn/bin/firnc "$p" "$TMPD/$p.o" "$TMPD/$p.elf" \
        "$TMPD/crt.o" kernel/user/user.ld 0 "$TMPD/$p.err" || {
        bad "firnc0 uebersetzt $p.fi nicht"
        sed 's/^/        /' "$TMPD/$p.err" | head -6; gebaut=0; }
done
[ "$gebaut" = 1 ] && ok "$(echo $PROGS | wc -w) Programme gebaut, /bin/pluguhr ist $(stat -c%s "$TMPD/pluguhr.elf") Oktette"

# DAS WIDGET TRAEGT KEINEN KERNCODE UND DER KERN KEINEN WIDGETCODE.
for sym in pluguhr__bauen pluguhr__u_start; do
    if nm -a "$TMPD/k.mb.elf" 2>/dev/null | grep -q "$sym"; then
        bad "der Kernel traegt $sym -- ein Plugin gehoert nach Ring 3"
    else
        ok "der Kernel traegt $sym NICHT (das Widget ist ein Ring-3-Prozess)"
    fi
done

python3 tools/k15/tree.py "$TMPD/baum" > "$TMPD/baum.log" 2>&1 \
    && ok "der Verzeichnisbaum steht" || bad "tools/k15/tree.py fehlgeschlagen"

echo "== 2. das Abbild =="
ARGS=(build "$TMPD/disk.img" 32768 /lib/
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" /bin/)
for p in $PROGS; do
    n=$p; [ "$p" = "_dev_uhrstart" ] && n=uhrstart
    ARGS+=("/bin/$n=$TMPD/$p.elf")
done
printf 'on\n' > "$TMPD/uitrace"
ARGS+=(/etc/ "/etc/theme=$TMPD/baum/theme" "/etc/uitrace=$TMPD/uitrace")
[ -f etc/wmplug.conf ] && ARGS+=("/etc/wmplug.conf=etc/wmplug.conf")
while read -r z; do ARGS+=("$z"); done < "$TMPD/baum/liste"
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "das Abbild ist gebaut" \
    || { bad "mkfs.py fehlgeschlagen"; sed 's/^/        /' "$TMPD/mkfs.txt" | head -5; }

BASE="gfx wm wig desk wmhold wiglong nokbd nosched noproc nofs wmplug"
lauf() { # name zusatz
    local name=$1 extra=$2
    local sock="$TMPD/mon-$name.sock" out="$TMPD/$name.txt" ppm="$TMPD/$name.ppm"
    rm -f "$out" "$ppm" "$sock"
    cp -f "$TMPD/disk.img" "$TMPD/live-$name.img"
    timeout 240 $QEMU_X86 -kernel "$TMPD/k.mb" -m 256 \
        -append "$BASE $extra" -serial "file:$out" -display none -no-reboot \
        -vga std -global VGA.edid=off -monitor "unix:$sock,server,nowait" \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/$name.qemu" 2>&1 &
    local pid=$! i=0
    while [ $i -lt 1400 ]; do
        grep -qa '^wm: hold' "$out" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.15; i=$((i+1))
    done
    # Dem Widget zwei Takte lassen: es schickt einmal je Sekunde, die
    # Leiste holt einmal je Sekunde. Ein Foto nach 0,2 Sekunden wuerde
    # etwas messen, das noch niemand geschickt hat.
    sleep 4
    python3 tools/gfx/screenshot.py "$sock" "$ppm" 25 > "$TMPD/$name.shot" 2>&1
    wait "$pid"; rm -f "$sock"
}

echo "== 3. der Lauf OHNE Widget =="
lauf aus ""
has "$TMPD/aus.txt" "wm: hold" "der Schreibtisch steht (aus)"
hasnot "$TMPD/aus.txt" "taskbar: plug nr=" "ohne Widget meldet die Leiste kein Widget-Feld"
cp -f "$TMPD/aus.ppm" "$SHOTS/widget-aus.ppm" 2>/dev/null

echo "== 4. der Lauf MIT Widget =="
lauf an "wigapp=/bin/uhrstart"
has "$TMPD/an.txt" "wm: hold" "der Schreibtisch steht (an)"
has "$TMPD/an.txt" "wmplug: reg uhr" "das Widget hat sich angemeldet"
has "$TMPD/an.txt" "pluguhr: angemeldet" "und sagt es selbst"
has "$TMPD/an.txt" "pluguhr: text " "es schickt Text"
hasnot "$TMPD/an.txt" "pluguhr: KEIN recht" "es hat R_ACT_BAR bekommen"
has "$TMPD/an.txt" "taskbar: plug nr=0" "die Leiste hat ein Widget-Feld"
has "$TMPD/an.txt" "taskbar: text plug " "und malt seinen Text"
hasnot "$TMPD/an.txt" "wmplug: unreg uhr grund=2" "die Frist hat nicht gerissen"
cp -f "$TMPD/an.ppm" "$SHOTS/widget-an.ppm" 2>/dev/null

echo "== 5. die Rechnung an der benannten Koordinate =="
# Die Koordinate kommt aus der Leiste selbst und nicht aus diesem Skript:
# `taskbar: plug nr=0 x=.. y=.. w=.. h=..` plus der Fensterlage
# (`taskbar: geom x= y=`). Gemessen wird die MITTE dieses Kastens.
zeile=$(grep -a '^taskbar: plug nr=0 ' "$TMPD/an.txt" | tail -1)
gline=$(grep -a '^taskbar: geom ' "$TMPD/an.txt" | tail -1)
zahl() { printf '%s' "$1" | grep -oE " $2=[0-9]+" | head -1 | sed 's/.*=//'; }
# Die Farbe an einer Stelle, als "r g b" -- die Leistenfarbe wird nicht
# getippt, sondern aus der Ecke des Kastens GELESEN. Ein fest getippter
# Wert waere nach dem naechsten Farbschema falsch.
pfarbe() { python3 tools/gfx/checkshot.py punkt "$1" "$2" "$3" 2>/dev/null; }
px=$(zahl "$zeile" x); py=$(zahl "$zeile" y)
pw=$(zahl "$zeile" w); ph=$(zahl "$zeile" h)
gx=$(zahl "$gline" x); gy=$(zahl "$gline" y)
gx=${gx:-0}; gy=${gy:-0}
if [ -z "$px" ] || [ -z "$pw" ]; then
    bad "die Leiste meldet keinen Widget-Kasten -- ohne ihn gibt es nichts nachzurechnen"
else
    cx=$((gx + px + pw / 2)); cy=$((gy + py + ph / 2))
    ok "der Widget-Kasten steht bei x=$px y=$py w=$pw h=$ph, Mitte im Bild ($cx,$cy)"
    # Der Unterschied wird NICHT behauptet, sondern gezaehlt: wie viele
    # Bildpunkte im Kasten sind zwischen den beiden Bildern verschieden?
    # Text auf gleichfarbigem Grund heisst: ein Teil der Punkte, nicht
    # alle -- also ist die Zusage "mehr als 40 verschiedene Punkte".
    d=$(python3 - "$SHOTS/widget-an.ppm" "$SHOTS/widget-aus.ppm" \
        "$((gx+px))" "$((gy+py))" "$pw" "$ph" <<'PY'
import sys
def load(p):
    d=open(p,'rb').read()
    # P6, drei Kopfzahlen, dann die Punkte
    parts=[];i=2
    while len(parts)<3:
        while i<len(d) and d[i:i+1].isspace(): i+=1
        if d[i:i+1]==b'#':
            while d[i:i+1]!=b'\n': i+=1
            continue
        j=i
        while j<len(d) and not d[j:j+1].isspace(): j+=1
        parts.append(int(d[i:j])); i=j
    i+=1
    w,h,_=parts
    return w,h,d[i:]
a=load(sys.argv[1]); b=load(sys.argv[2])
x0,y0,w,h=(int(v) for v in sys.argv[3:7])
n=0
for y in range(y0,min(y0+h,a[1],b[1])):
    for x in range(x0,min(x0+w,a[0],b[0])):
        o=(y*a[0]+x)*3
        if a[2][o:o+3]!=b[2][o:o+3]: n+=1
print(n)
PY
)
    if [ "${d:-0}" -gt 40 ]; then
        ok "im Widget-Kasten unterscheiden sich $d Bildpunkte zwischen AN und AUS"
    else
        bad "AN und AUS unterscheiden sich im Widget-Kasten nur in ${d:-0} Bildpunkten"
    fi
    # Und dieselbe Stelle noch einmal mit tools/gfx/checkshot.py, damit
    # die Zahl aus einem Programm kommt, das nicht diesem Modul gehoert.
    aus=$(python3 tools/gfx/checkshot.py punkt "$SHOTS/widget-aus.ppm" "$cx" "$cy" 2>&1)
    an=$(python3 tools/gfx/checkshot.py punkt "$SHOTS/widget-an.ppm" "$cx" "$cy" 2>&1)
    if [ "$aus" != "$an" ]; then
        ok "checkshot punkt ($cx,$cy): aus=[$aus] an=[$an] -- verschieden"
    else
        bad "checkshot punkt ($cx,$cy): beide [$an] -- kein Unterschied an der Mitte"
    fi
    # Die Tinte im Kasten, gegen die Leistenfarbe gezaehlt: mit Widget
    # stehen dort Buchstaben, ohne Widget nicht.
    it=$(python3 tools/gfx/checkshot.py flaeche "$SHOTS/widget-an.ppm" \
        "$((gx+px))" "$((gy+py))" "$pw" "$ph" $(pfarbe "$SHOTS/widget-an.ppm" "$((gx+px+1))" "$((gy+py+1))") 2>&1 \
        | grep -oE '^[0-9]+')
    if [ "${it:-0}" -gt 20 ]; then
        ok "im Widget-Kasten stehen $it Bildpunkte Tinte (AN)"
    else
        bad "im Widget-Kasten steht keine Tinte (${it:-0} Punkte) -- der Text fehlt"
    fi
fi

echo
echo "WIDGET: $pass bestanden, $fail gescheitert"
[ "$fail" = 0 ] || exit 1
