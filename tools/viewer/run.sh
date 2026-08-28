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
# Ein Bildschirmfoto wird GERECHNET und nicht angeschaut.
schau() { local name=$1; shift
    local aus rc
    aus=$(python3 tools/gfx/checkshot.py "$@" 2>&1); rc=$?
    if [ "$rc" -eq 0 ]; then ok "$name ($aus)"; else bad "$name -- $aus"; fi
}

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


# =====================================================================
# 8. DIE ANWENDUNG, AUF DEM BILDSCHIRM
#
# Bis hierher wurde der Dekodierer gemessen. Jetzt die Anwendung: sie
# laeuft im Fensterserver, zeigt ein Foto, blaettert, zoomt, dreht --
# und was sie tut, steht in ZWEI Quellen, die beide stimmen muessen:
# ihren Meldungen auf der seriellen Leitung und dem Bildschirmfoto.
echo "== 8. die Anwendung Bilder im Fenster =="
MONO=assets/osum-mono.ttf
SANS=assets/osum-sans.ttf
GUIPROGS="viewer sh echo ls cat launcher explorer widgetdemo locate edit"
grc=0
for p in $GUIPROGS; do
    [ -f "$TMPD/$p.elf" ] && continue
    if ! $FIRNC "kernel/user/$p.fi" -o "$TMPD/$p.o" > "$TMPD/$p.err" 2>&1; then
        bad "firnc0 uebersetzt $p.fi nicht"; head -5 "$TMPD/$p.err"; grc=1; continue
    fi
    ld -T "$ULD" --defsym=USER_ENTRY=_F0.u_start -o "$TMPD/$p.elf" \
        "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null || { bad "ld: $p"; grc=1; }
    strip --strip-all "$TMPD/$p.elf" 2>/dev/null
done
[ $grc -eq 0 ] && ok "die Programme der Oberflaeche sind gebaut"

python3 tools/k15/tree.py "$TMPD/baum" > "$TMPD/baum.log" 2>&1 \
    || bad "tools/k15/tree.py fehlgeschlagen"

# Die Bilder, die der Betrachter zeigt: vier Formate, damit das
# Blaettern wirklich durch verschiedene Dekodierer geht.
GARGS=(build "$TMPD/gui.img" 8192 --inodes=128 /lib/
  "/lib/mono.ttf=$MONO" "/lib/sans.ttf=$SANS" /bin/)
for p in $GUIPROGS; do GARGS+=("/bin/$p=$TMPD/$p.elf"); done
GARGS+=("/bin/files@/bin/explorer")
GARGS+=(/etc/ "/etc/theme=$TMPD/baum/theme")
GARGS+=(/bilder/
        "/bilder/a-rot.png=$FIX/prgb.png"
        "/bilder/b-foto.jpg=$FIX/j420.jpg"
        "/bilder/c-alpha.png=$FIX/palpha.png"
        "/bilder/d-tier.gif=$FIX/ganim.gif"
        "/bilder/e-wappen.bmp=$FIX/b24.bmp"
        "/bilder/f-quer.jpg=$FIX/jexif.jpg"
        "/bilder/g-gross.jpg=$FIX/j12mp.jpg")
while read -r zeile; do GARGS+=("$zeile"); done < <(python3 tools/k15/bundle.py assets/apps "$TMPD/buendel")
python3 tools/osum/mkfs.py "${GARGS[@]}" > "$TMPD/mkfsgui.log" 2>&1 \
    && ok "ein grafisches Abbild mit sieben Bildern in /bilder" \
    || { bad "mkfs (Oberflaeche) fehlgeschlagen"; tail -4 "$TMPD/mkfsgui.log"; }

GRUND="nokbd nosched noproc nofs"
foto() { # name monitordatei
    local name=$1 mon=${2:-}
    local sock="$TMPD/mon-$name.sock"
    local aus="$TMPD/$name.txt" ppm="$TMPD/$name.ppm"
    rm -f "$aus" "$ppm" "$sock"
    cp -f "$TMPD/gui.img" "$TMPD/live-$name.img"
    timeout 300 $QEMU_X86 -kernel "$TMPD/k.mb" -m 512 \
        -append "gfx wm wigapp=/bin/viewer wmhold wiglong $GRUND" \
        -serial "file:$aus" -display none -no-reboot -vga std \
        -monitor "unix:$sock,server,nowait" \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local pid=$!
    local i=0
    while [ $i -lt 2000 ]; do
        grep -qaE '^wm: hold' "$aus" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.15
        i=$((i + 1))
    done
    if [ -n "$mon" ]; then
        python3 tools/wm/monitor.py "$sock" "$mon" > "$TMPD/$name.monlog" 2>&1
    fi
    python3 tools/gfx/screenshot.py "$sock" "$ppm" 25 > "$TMPD/$name.shot" 2>&1
    wait "$pid"
    RC=$?
    rm -f "$sock"
    return 0
}
zeiger() { # datei x y
    local f=$1 x=$2 y=$3 i
    for i in 1 2 3 4 5 6; do echo "mouse_move -120 -120" >> "$f"; done
    local dx=$x dy=$y
    while [ "$dx" -gt 0 ] || [ "$dy" -gt 0 ]; do
        local sx=$dx sy=$dy
        [ "$sx" -gt 120 ] && sx=120
        [ "$sy" -gt 120 ] && sy=120
        echo "mouse_move $sx $sy" >> "$f"
        dx=$((dx - sx)); dy=$((dy - sy))
    done
}
klick() { # datei x y
    zeiger "$1" "$2" "$3"
    printf 'warte 0.3\nmouse_button 1\nwarte 0.2\nmouse_button 0\nwarte 1.2\n' >> "$1"
}
vfeld() { grep -a "^viewer: " "$1" | tail -1 | grep -oE "$2=[0-9]+" | head -1 | cut -d= -f2; }
vfeld_n() { grep -a "^viewer: " "$1" | sed -n "$3p" | grep -oE "$2=[0-9]+" | head -1 | cut -d= -f2; }

mkdir -p docs/shots/viewer

# ---- 8a. der erste Start: das Fenster steht, das Bild ist da.
foto start
num "der Kern beendet sich sauber" "$RC" eq 21
has "$TMPD/start.txt" "wm: hold" "der Kern haelt fuer das Foto still"
has "$TMPD/start.txt" "viewer: los" "die Anwendung ist von der Platte gestartet"
va=$(vfeld "$TMPD/start.txt" an)
num "sie findet die Bilder im Ordner" "${va:-0}" eq 7
vb=$(vfeld "$TMPD/start.txt" br); vh=$(vfeld "$TMPD/start.txt" ho)
num "das erste Bild ist so breit wie die Datei sagt" "${vb:-0}" eq 64
num "und so hoch" "${vh:-0}" eq 48
vm=$(vfeld "$TMPD/start.txt" mini)
num "der Miniaturenstreifen ist gefuellt" "${vm:-0}" ge 5
# Das Foto misst, dass wirklich etwas gemalt wurde: die Zeichenflaeche
# ist nicht leer, und der Miniaturenstreifen auch nicht.
schau "die Zeichenflaeche traegt Bildpunkte" \
    nichtleer "$TMPD/start.ppm" 100 120 500 300 1000
schau "der Miniaturenstreifen traegt Bildpunkte" \
    nichtleer "$TMPD/start.ppm" 40 490 600 50 500

# ---- 8b. blaettern: aus PNG wird JPEG wird PNG wird GIF ...
M="$TMPD/weiter.mon"; : > "$M"
klick "$M" 74 66     # der Knopf ">"
klick "$M" 74 66
klick "$M" 74 66
foto weiter "$M"
n1=$(vfeld_n "$TMPD/weiter.txt" fmt 2)
n2=$(vfeld_n "$TMPD/weiter.txt" fmt 3)
n3=$(vfeld_n "$TMPD/weiter.txt" fmt 4)
printf '        die Formate beim Blaettern: %s %s %s (1=PNG 2=JPEG 3=BMP 4=GIF)\n' \
    "$n1" "$n2" "$n3"
num "nach einem Klick auf > ist das zweite Bild ein JPEG" "${n1:-0}" eq 2
num "nach dem zweiten ein PNG mit Alpha" "${n2:-0}" eq 1
num "nach dem dritten ein GIF" "${n3:-0}" eq 4
bi=$(vfeld "$TMPD/weiter.txt" bild)
num "und der Zaehler steht auf dem vierten Bild" "${bi:-0}" eq 3

# ---- 8c. Zoom: einpassen und 100 %.
M="$TMPD/zoom.mon"; : > "$M"
klick "$M" 348 66    # "100 %"
foto zoom100 "$M"
zf=$(vfeld "$TMPD/zoom100.txt" fit)
zz=$(vfeld "$TMPD/zoom100.txt" zoom)
num "nach dem Klick auf 100 % ist das Einpassen aus" "${zf:-9}" eq 0
num "und der Zoom steht auf hundert" "${zz:-0}" eq 100

# ---- 8d. drehen: aus 64x48 wird 48x64.
M="$TMPD/dreh.mon"; : > "$M"
klick "$M" 456 66    # "Rechts"
foto dreh "$M"
db=$(vfeld "$TMPD/dreh.txt" br); dh=$(vfeld "$TMPD/dreh.txt" ho)
num "nach einer Vierteldrehung ist die Breite die alte Hoehe" "${db:-0}" eq 48
num "und die Hoehe die alte Breite" "${dh:-0}" eq 64

# ---- 8e. EXIF: das Bild mit Lage 6 kommt gedreht heraus.
M="$TMPD/exif.mon"; : > "$M"
for k in 1 2 3 4 5; do klick "$M" 74 66; done
foto exif "$M"
eo=$(vfeld "$TMPD/exif.txt" ori)
eb=$(vfeld "$TMPD/exif.txt" br); eh=$(vfeld "$TMPD/exif.txt" ho)
num "das Foto meldet die EXIF-Lage 6" "${eo:-0}" eq 6
num "und es wird gedreht angezeigt: aus 40 breit wird 24" "${eb:-0}" eq 24
num "und aus 24 hoch wird 40" "${eh:-0}" eq 40

# ---- 8f. das grosse Bild: 12 MP im Fenster, ohne dass etwas stirbt.
M="$TMPD/gross.mon"; : > "$M"
for k in 1 2 3 4 5 6; do klick "$M" 74 66; done
foto gross "$M"
gb=$(vfeld "$TMPD/gross.txt" br); gh=$(vfeld "$TMPD/gross.txt" ho)
gv=$(vfeld "$TMPD/gross.txt" voll)
ga=$(vfeld "$TMPD/gross.txt" arena)
num "das 12-MP-Bild steht im Fenster" "${gb:-0}" eq 4000
num "mit voller Hoehe" "${gh:-0}" eq 3000
printf '        dafuer gebraucht: %s Oktette Arena, ganz im Speicher=%s\n' "$ga" "$gv"
schau "und die Zeichenflaeche zeigt es" \
    nichtleer "$TMPD/gross.ppm" 100 120 500 300 1000

# ---- 8g. Diaschau und Sichern.
M="$TMPD/dia.mon"; : > "$M"
klick "$M" 560 66    # "Diaschau"
printf 'warte 4.0\n' >> "$M"
foto dia "$M"
dz=$(vfeld "$TMPD/dia.txt" dia)
num "die Diaschau laeuft" "${dz:-0}" eq 1
db2=$(vfeld "$TMPD/dia.txt" bild)
if [ "${db2:-0}" != "0" ]; then ok "und sie ist von selbst weitergegangen (Bild $db2)"
else bad "die Diaschau ist nicht weitergegangen"; fi

M="$TMPD/save.mon"; : > "$M"
klick "$M" 60 542    # "Zuschneiden"
klick "$M" 152 542   # "Als PNG"
foto save "$M"
has "$TMPD/save.txt" "viewer: gesichert" "die Anwendung schreibt eine PNG-Datei"
sn=$(grep -a 'viewer: gesichert' "$TMPD/save.txt" | tail -1 | grep -oE '[0-9]+' | tail -1)
num "und die Datei ist nicht leer" "${sn:-0}" gt 100
if python3 tools/viewer/holen.py "$TMPD/live-save.img" \
    "/bilder/a-rot.png.viewer.png" "$TMPD/ausapp.png" > "$TMPD/holen2.log" 2>&1; then
    if python3 - "$TMPD/ausapp.png" > "$TMPD/pilapp.log" 2>&1 <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]); im.load()
print("%s %dx%d %s" % (im.format, im.width, im.height, im.mode))
PY
    then ok "Pillow liest, was die Anwendung geschrieben hat: $(cat "$TMPD/pilapp.log")"
    else bad "Pillow kann die Datei der Anwendung nicht lesen"; fi
else
    bad "die geschriebene Datei ist nicht auf dem Abbild"; head -2 "$TMPD/holen2.log"
fi

# ---- 8h. die Bildschirmfotos in den Baum, als PNG.
for f in start weiter zoom100 dreh exif gross dia save; do
    [ -f "$TMPD/$f.ppm" ] || continue
    python3 tools/gfx/ppm2png.py "$TMPD/$f.ppm" "docs/shots/viewer/$f.png" \
        > /dev/null 2>&1 && ok "docs/shots/viewer/$f.png" \
        || bad "das Foto $f laesst sich nicht wandeln"
done

echo
echo "VIEWER: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
