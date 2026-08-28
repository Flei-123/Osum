#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/viewer/run.sh -- DIE ABNAHME DER RUNDE VIEWER.
#
# Die Zusage dieser Runde ist nicht "es sieht gut aus", sondern:
#
#   1. DIE DEKODIERER STIMMEN GEGEN EINE FREMDE UMSETZUNG. Dieselben
#      Dateien werden auf dem Wirt mit Pillow (libjpeg-turbo, zlib-ng)
#      dekodiert und im System mit `img`. Verglichen wird BILDPUNKT FUER
#      BILDPUNKT: bei PNG, BMP und GIF muss die Abweichung NULL sein,
#      bei JPEG hoechstens zwei Stufen je Kanal -- der Rest ist die
#      Rundung der inversen DCT, und die Zahl steht in docs/IMAGES.md.
#   2. GROSSE BILDER BRINGEN DAS SYSTEM NICHT UM. Ein Foto mit 50
#      Megabildpunkten wird zeilenweise dekodiert, mit einem
#      Arbeitsspeicher, der an der BREITE haengt und nicht an der Zahl
#      der Bildpunkte.
#   3. KAPUTTE DATEIEN AUCH NICHT. Abgeschnitten, mit umgedrehten
#      Oktetten, mit erlogener Groesse -- jedes davon gibt einen Grund
#      MIT NAMEN, und der Kernel lebt danach.
#   4. WAS NICHT GEHT, WIRD BENANNT. WebP, HEIC, SVG, TIFF und
#      progressives JPEG werden erkannt und abgelehnt, nicht als
#      "kaputte Datei" abgetan.
#   5. DER SCHREIBER STIMMT AUCH. Was das System als PNG schreibt, wird
#      vom Abbild geholt und auf dem Wirt mit Pillow gelesen.
#
# Verwendung:  bash tools/viewer/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

TMPD=${OSUM_WORK:-$(mktemp -d)}
mkdir -p "$TMPD"
KEEP=${VIEWER_KEEP:-0}
trap '[ "$KEEP" = 1 ] || rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { local name=$1 wert=$2 op=$3 want=$4
    if [ -z "$wert" ]; then bad "$name: keine Zahl (erwartet $op $want)"; return; fi
    if [ "$wert" -"$op" "$want" ] 2>/dev/null; then ok "$name: $wert"
    else bad "$name: $wert, erwartet $op $want"; fi
}
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "fetch-firnc fehlgeschlagen"; exit 1; }
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "VIEWER: kein qemu"; exit 0; }
python3 -c 'import PIL' 2>/dev/null || { echo "VIEWER: kein Pillow auf dem Wirt"; exit 0; }

FIRNC=vendor/firn/bin/firnc
FC1=vendor/firn/bin/firnc1
ULD=kernel/user/user.ld

echo "== 1. der Bau =="
bash tools/build-kernel.sh "$TMPD/k.mb" > "$TMPD/kernel.log" 2>&1 \
    && ok "der Kern ist gebaut" || { bad "der Kern baut nicht"; tail -5 "$TMPD/kernel.log"; }

as --64 -o "$TMPD/crt.o" kernel/user/crt.s || { echo "crt"; exit 1; }
PROGS="sh ls cat echo imgtest"
[ -f kernel/user/viewer.fi ] && PROGS="$PROGS viewer"
rc=0
for p in $PROGS; do
    if ! $FIRNC "kernel/user/$p.fi" -o "$TMPD/$p.o" > "$TMPD/$p.err" 2>&1; then
        bad "firnc0 uebersetzt $p.fi nicht"; head -6 "$TMPD/$p.err"; rc=1; continue
    fi
    ld -T "$ULD" --defsym=USER_ENTRY=_F0.u_start -o "$TMPD/$p.elf" \
        "$TMPD/crt.o" "$TMPD/$p.o" 2>"$TMPD/$p.ld" || { bad "ld: $p"; rc=1; continue; }
    strip --strip-all "$TMPD/$p.elf"
done
[ $rc -eq 0 ] && ok "firnc0: $(echo $PROGS | wc -w) Programme gebaut"

# Beide Uebersetzer muessen die neuen Module koennen -- das ist die Regel
# des Baums seit K16 und nicht die Kuer dieser Runde.
if [ -x "$FC1" ]; then
    s1=0
    MODULE="imgmem imgjpeg imgpng imggif imgops img imgtest"
    [ -f kernel/user/viewer.fi ] && MODULE="$MODULE viewer"
    for m in $MODULE; do
        $FC1 -c "kernel/user/$m.fi" -o "$TMPD/s1_$m.o" > "$TMPD/s1_$m.err" 2>&1 \
            && s1=$((s1+1)) || { bad "firnc1 uebersetzt $m.fi nicht"; head -4 "$TMPD/s1_$m.err"; }
    done
    num "firnc1 uebersetzt die Module dieser Runde" "$s1" eq "$(echo $MODULE | wc -w)"
fi

# Kein Modul haengt an etwas Fremdem.
undef=""
for p in $PROGS; do
    u=$(nm -u "$TMPD/$p.elf" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
    [ -n "$u" ] && undef="$undef $p:$u"
done
[ -z "$undef" ] && ok "kein undefiniertes Symbol in den neuen Programmen" \
               || bad "undefinierte Symbole:$undef"

for p in imgtest ${VIEWERBIN:-imgtest}; do
    z=$(stat -c%s "$TMPD/$p.elf")
    printf '        %-9s %7d Oktette\n' "$p" "$z"
done

echo "== 2. die Testbilder (Pillow auf dem Wirt) =="
FIX="$TMPD/fix"
python3 tools/viewer/mkbilder.py "$FIX" > "$TMPD/mkbilder.log" 2>&1 \
    && ok "$(cat "$TMPD/mkbilder.log")" \
    || { bad "die Testbilder lassen sich nicht bauen"; tail -5 "$TMPD/mkbilder.log"; exit 1; }

# ---------------------------------------------------------- das Abbild
SPEC=""
for p in $PROGS; do SPEC="$SPEC /bin/$p=$TMPD/$p.elf"; done
DATA=""
while read -r name w h z; do
    [ -z "$name" ] && continue
    DATA="$DATA /b/$name=$FIX/$name"
    [ -f "$FIX/$name.rgba" ] && DATA="$DATA /r/$name.rgba=$FIX/$name.rgba"
done < "$FIX/LISTE"

# Das Prüfskript. Eine Zeile je Bild -- der Kernel bekommt nur
# `sh /pruef.sh` auf die Befehlszeile, der Rest steht auf der Platte.
S="$TMPD/pruef.sh"
: > "$S"
while read -r name w h z; do
    [ -z "$name" ] && continue
    if [ "$z" = "-1" ] || [ "$z" = "-2" ]; then
        echo "imgtest /b/$name" >> "$S"
    else
        echo "imgtest /b/$name /r/$name.rgba" >> "$S"
    fi
done < "$FIX/LISTE"
# Die Miniaturansicht (ein Achtel) und das Schreiben.
cat >> "$S" <<'EOS'
imgtest /b/j12mp.jpg -8
imgtest /b/j444.jpg -p /aus/rund.png
imgtest /b/j444.jpg -r 1 -p /aus/dreh.png
imgtest /b/prgb.png -c 8,6,24,18 -p /aus/schnitt.png
imgtest /b/prgb.png -s 32x24 -p /aus/klein.png
imgtest /b/palpha.png -p /aus/alpha.png
echo FERTIG
EOS

python3 tools/osum/mkfs.py build "$TMPD/d.img" 32768 --inodes=256 \
    /bin/ /b/ /r/ /aus/ $SPEC $DATA /pruef.sh="$S" \
    > "$TMPD/mkfs.log" 2>&1 \
    && ok "ein Plattenabbild mit $(echo $DATA | wc -w) Dateien darauf" \
    || { bad "mkfs fehlgeschlagen"; tail -5 "$TMPD/mkfs.log"; exit 1; }

echo "== 3. der Lauf im System =="
cp "$TMPD/d.img" "$TMPD/live.img"
LOG="$TMPD/lauf.txt"
start=$(date +%s%3N)
timeout 600 $QEMU_X86 -kernel "$TMPD/k.mb" -m 512 \
    -append "osum nokbd nosched noproc nofs script=sh /pruef.sh;exit" \
    -serial "file:$LOG" -display none -no-reboot \
    -drive "file=$TMPD/live.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
qrc=$?
ende=$(date +%s%3N)
printf '        der Lauf: %d ms, QEMU-Code %d, %s\n' "$((ende-start))" "$qrc" "$OSUM_QEMU_ACCEL"
if grep -qa 'FERTIG' "$LOG"; then
    ok "der Lauf ist bis zum Ende gekommen (der Kernel lebt)"
else
    bad "der Lauf ist nicht bis FERTIG gekommen"
    tail -25 "$LOG"
fi

# Aus einer IMG-Zeile ein Feld holen: feld <datei> <bildname> <schluessel>
feld() {
    grep -a "^IMG datei=" "$LOG" | sed -n "$2p" | grep -oE "$3=[0-9]+" | head -1 | cut -d= -f2
}
# Die n-te IMG-Zeile gehoert zum n-ten Bild der Liste. Sicherer ist der
# Weg ueber die Reihenfolge im Skript: jede Zeile des Skripts erzeugt
# genau eine IMG-Zeile.
mapfile -t IMGZEILEN < <(grep -a '^IMG ' "$LOG")
mapfile -t DIFFZEILEN < <(grep -a '^IMGDIFF ' "$LOG")
mapfile -t SAVEZEILEN < <(grep -a '^IMGSAVE ' "$LOG")
num "IMG-Zeilen im Protokoll" "${#IMGZEILEN[@]}" ge 39

wert() { echo "$1" | grep -oE "$2=[0-9]+" | head -1 | cut -d= -f2; }

echo "== 4. Bildpunkt fuer Bildpunkt gegen Pillow =="
i=0
d=0
schlimm_jpeg=0
schlimm_rest=0
while read -r name w h z; do
    [ -z "$name" ] && continue
    zeile="${IMGZEILEN[$i]}"
    i=$((i+1))
    case "$z" in -1|-2) continue;; esac
    dz="${DIFFZEILEN[$d]}"
    d=$((d+1))
    gw=$(wert "$zeile" breite); gh=$(wert "$zeile" hoehe)
    gr=$(wert "$zeile" grund)
    mr=$(wert "$dz" maxr); mg=$(wert "$dz" maxg); mb=$(wert "$dz" maxb)
    ma=$(wert "$dz" maxa); mil=$(wert "$dz" mittel1000); zl=$(wert "$dz" zeilen)
    if [ "$gw" != "$w" ] || [ "$gh" != "$h" ]; then
        bad "$name: Groesse ${gw}x${gh}, Pillow sagt ${w}x${h}"
        continue
    fi
    if [ "$gr" != "0" ]; then bad "$name: Grund $gr statt 0"; continue; fi
    mx=$mr; [ "$mg" -gt "$mx" ] && mx=$mg; [ "$mb" -gt "$mx" ] && mx=$mb
    [ "$ma" -gt "$mx" ] && mx=$ma
    case "$name" in
        *.jpg) grenze=2; [ "$mx" -gt "$schlimm_jpeg" ] && schlimm_jpeg=$mx;;
        *)     grenze=0; [ "$mx" -gt "$schlimm_rest" ] && schlimm_rest=$mx;;
    esac
    if [ "$mx" -le "$grenze" ]; then
        printf '  OK    %-14s %5sx%-5s maxabw=%s mittel=%s/1000 (%s Zeilen)\n' \
            "$name" "$gw" "$gh" "$mx" "$mil" "$zl"
        pass=$((pass+1))
    else
        bad "$name: groesste Abweichung $mx (r=$mr g=$mg b=$mb a=$ma), erlaubt $grenze"
    fi
done < "$FIX/LISTE"
num "groesste Abweichung ueber ALLE JPEG-Bilder" "$schlimm_jpeg" le 2
num "groesste Abweichung ueber PNG, BMP und GIF (bitgenau)" "$schlimm_rest" eq 0

echo "== 5. die Zahlen, die ueber die Brauchbarkeit entscheiden =="
z12=$(grep -a '^IMG datei=' "$LOG" | grep -a 'breite=4000 hoehe=3000' | head -1)
ms12=$(wert "$z12" ms); ar12=$(wert "$z12" arena)
z50=$(grep -a '^IMG datei=' "$LOG" | grep -a 'breite=8000 hoehe=6250' | head -1)
ms50=$(wert "$z50" ms); ar50=$(wert "$z50" arena); gr50=$(wert "$z50" grund)
zmini=$(grep -a '^IMG datei=' "$LOG" | grep -a 'breite=500 hoehe=375' | head -1)
msmini=$(wert "$zmini" ms)
printf '        12 MP (4000x3000, 4:2:0):  %s ms, Arbeitsspeicher %s Oktette\n' "$ms12" "$ar12"
printf '        50 MP (8000x6250, 4:2:0):  %s ms, Arbeitsspeicher %s Oktette\n' "$ms50" "$ar50"
printf '        Miniatur 1/8 desselben:    %s ms\n' "$msmini"
num "das 12-MP-Bild ist wirklich dekodiert worden (ms > 0)" "${ms12:-0}" gt 0
num "das 50-MP-Bild kommt durch (Grund 0)" "${gr50:-9}" eq 0
num "der Arbeitsspeicher fuer 50 MP haengt an der Breite, nicht an der Flaeche" \
    "${ar50:-999999999}" lt 20000000
num "die Miniatur ist deutlich schneller als das ganze Bild" \
    "$(( ${ms12:-0} / (${msmini:-1} + 1) ))" ge 3

echo "== 6. kaputte Dateien: ein Grund mit Namen, kein Absturz =="
for n in kurz.jpg kurz.png kurz.gif kurz.bmp winzig.jpg mues.jpg mues.png luege.png; do
    if grep -qa "^IMG datei=.*" "$LOG"; then :; fi
done
i=0
while read -r name w h z; do
    [ -z "$name" ] && continue
    zeile="${IMGZEILEN[$i]}"; i=$((i+1))
    case "$name" in
      kurz.*|winzig.jpg|mues.*|luege.png)
        gr=$(wert "$zeile" grund); tw=$(echo "$zeile" | grep -oE 'text=[A-Z0-9 ]+')
        pt=$(wert "$zeile" teilweise)
        if [ -n "$gr" ]; then
            printf '  OK    %-12s grund=%s %s teilweise=%s\n' "$name" "$gr" "$tw" "${pt:-0}"
            pass=$((pass+1))
        else
            bad "$name: keine Antwort"
        fi;;
      nein.webp|nein.svg|nein.tif)
        gr=$(wert "$zeile" grund)
        if [ "$gr" = "12" ]; then
            printf '  OK    %-12s wird ERKANNT und beim Namen abgelehnt (NICHT UNTERSTUETZT)\n' "$name"
            pass=$((pass+1))
        else bad "$name: grund=$gr, erwartet 12 (NICHT UNTERSTUETZT)"; fi;;
      jprog.jpg)
        gr=$(wert "$zeile" grund)
        if [ "$gr" = "4" ]; then
            ok "jprog.jpg: progressives JPEG wird BENANNT (PROGRESSIV), nicht falsch gezeigt"
        else bad "jprog.jpg: grund=$gr, erwartet 4 (PROGRESSIV)"; fi;;
    esac
done < "$FIX/LISTE"
has "$LOG" "FERTIG" "nach allen kaputten Dateien laeuft die Shell weiter"

echo "== 7. was das System geschrieben hat, liest Pillow =="
for f in rund.png dreh.png schnitt.png klein.png alpha.png; do
    if python3 tools/viewer/holen.py "$TMPD/live.img" "/aus/$f" "$TMPD/$f" \
        > "$TMPD/holen_$f.log" 2>&1; then
        if python3 - "$TMPD/$f" > "$TMPD/pil_$f.log" 2>&1 <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]); im.load()
print("%s %d %d %s" % (im.format, im.width, im.height, im.mode))
PY
        then ok "$f: $(cat "$TMPD/pil_$f.log") -- von Pillow gelesen"
        else bad "$f: Pillow kann die Datei nicht lesen"; head -3 "$TMPD/pil_$f.log"; fi
    else
        bad "$f: nicht vom Abbild zu holen"; head -2 "$TMPD/holen_$f.log"
    fi
done

# Die eigentliche Zusage: was herauskommt, ist dasselbe Bild.
python3 - "$TMPD/rund.png" "$FIX/j444.jpg" "$TMPD" > "$TMPD/rund.cmp" 2>&1 <<'PY'
import sys
from PIL import Image
a = Image.open(sys.argv[1]).convert("RGBA")
b = Image.open(sys.argv[2]).convert("RGBA")
if a.size != b.size:
    print("GROESSE %s != %s" % (a.size, b.size)); raise SystemExit(1)
da, db = a.tobytes(), b.tobytes()
mx = max(abs(x - y) for x, y in zip(da, db))
print("maxabw=%d" % mx)
PY
mxr=$(grep -oE 'maxabw=[0-9]+' "$TMPD/rund.cmp" | cut -d= -f2)
num "der Umlauf JPEG lesen -> PNG schreiben -> Pillow lesen (Abweichung)" "${mxr:-99}" le 2

python3 - "$TMPD/schnitt.png" "$FIX/prgb.png" > "$TMPD/schnitt.cmp" 2>&1 <<'PY'
import sys
from PIL import Image
a = Image.open(sys.argv[1]).convert("RGBA")
b = Image.open(sys.argv[2]).convert("RGBA").crop((8, 6, 32, 24))
print("groesse=%dx%d soll=%dx%d" % (a.width, a.height, b.width, b.height))
mx = max(abs(x - y) for x, y in zip(a.tobytes(), b.tobytes()))
print("maxabw=%d" % mx)
PY
mxc=$(grep -oE 'maxabw=[0-9]+' "$TMPD/schnitt.cmp" | cut -d= -f2)
num "zuschneiden ist bitgenau dasselbe wie bei Pillow" "${mxc:-99}" eq 0

python3 - "$TMPD/dreh.png" "$FIX/j444.jpg" > "$TMPD/dreh.cmp" 2>&1 <<'PY'
import sys
from PIL import Image
a = Image.open(sys.argv[1]).convert("RGBA")
b = Image.open(sys.argv[2]).convert("RGBA").transpose(Image.ROTATE_270)
print("groesse=%dx%d soll=%dx%d" % (a.width, a.height, b.width, b.height))
if a.size != b.size:
    raise SystemExit(1)
mx = max(abs(x - y) for x, y in zip(a.tobytes(), b.tobytes()))
print("maxabw=%d" % mx)
PY
mxd=$(grep -oE 'maxabw=[0-9]+' "$TMPD/dreh.cmp" | cut -d= -f2)
num "drehen um 90 Grad stimmt gegen Pillow" "${mxd:-99}" le 2

echo
echo "VIEWER: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
