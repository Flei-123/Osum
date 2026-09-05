#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/design/aufnahme.sh -- RUNDE OBERFLAECHE: SIEBEN ANSICHTEN, EIN START.
#
#   bash tools/design/aufnahme.sh <ausgabeverzeichnis> [key=value ...]
#
#     shape=classic|modern|<name>   /etc/theme.conf shape=
#     scheme=day|paper|night|...    /etc/theme.conf scheme=
#     mode=light|dark|auto
#     res=<b>x<h>                   Bildschirmgroesse (Vorgabe 1280x800)
#     accel=kvm|tcg
#     progs="..."                   Programmliste
#     drehbuch=<pfad>               eigenes Drehbuch statt des eingebauten
#
# WARUM EIN START UND NICHT SIEBEN.  Jede Runde davor hat je Bild eine
# eigene Maschine gebootet.  Sieben Maschinen sind sieben Uhrzeiten in
# der Leiste und sieben verschiedene Zufaelle beim Start; ein
# Vorher/Nachher-Vergleich, in dem sich nebenbei die Uhr bewegt, misst
# Rauschen mit.  Hier laeuft EINE Maschine, und `tools/design/fahren.py`
# klickt sich durch die Ansichten.
#
# DIE SIEBEN ANSICHTEN, und warum genau diese: es sind die Flaechen, die
# ein Mensch in der ersten Minute sieht.  Schreibtisch, Taskleiste (als
# Ausschnitt desselben Bildes), Startmenue, Dateimanager, Einstellungen,
# Kontrollzentrum, ein Dialog.
#
# Es druckt die Zahlen, auf die ein Aufrufer sich stuetzen darf: die
# Groesse des Kerns, die der Platte, den QEMU-Beendigungscode und je
# Ansicht die Groesse der Aufnahme.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
export FIRN_REPO=${FIRN_REPO:-/root/jarvis/projects/u_DiS4in7esMF1/firn}

OUT=${1:?usage: aufnahme.sh <outdir> [key=value ...]}
shift || true

shape=osum
scheme=day
mode=light
res=1280x800
# RUNDE OBERFLAECHE, GEMESSEN AM 05.09.2026: AUF DIESEM ZWEIG IST TCG
# DIE VORGABE, UND DAS IST KEIN GESCHMACK.
#
# Der Kern des Zweiges `hidweg` (1493451, Runde VIELKERN 2/n) kommt
# UNTER KVM nicht bis `wm: hold`.  Gemessen, mit demselben Plattenabbild
# und demselben Kern, nur der Beschleuniger getauscht:
#
#     -accel kvm -cpu host        keine Zeile `wm: hold` in 130 s, die
#                                 Stufentafel bleibt bei ST 22 stehen
#                                 (also mitten in `kgui.desk_start`)
#     -accel kvm -cpu host -smp 1 dasselbe
#     -accel tcg                  `wm: hold`, QEMU-Beendigungscode 21
#
# Gegenprobe, dass es nicht an dieser Runde liegt: derselbe Versuch mit
# einem Kern aus `main` laeuft unter KVM durch, und ein Kern aus
# `hidweg` OHNE die zwei Zeilen dieser Runde haengt genauso.  Das ist
# also eine Regression des Zweiges und keine dieses Werkzeugs -- sie
# steht in docs/RUNDE-OBERFLAECHE.md, damit sie nicht verlorengeht.
accel=tcg
halt=300
extra=""
nurbau=nein
drehbuch=""
progs="desktop taskbar settings launcher explorer edit sh echo ls cat theme"
for a in "$@"; do
    case "$a" in
        shape=*) shape=${a#*=} ;;
        scheme=*) scheme=${a#*=} ;;
        mode=*) mode=${a#*=} ;;
        res=*) res=${a#*=} ;;
        accel=*) accel=${a#*=} ;;
        progs=*) progs=${a#*=} ;;
        drehbuch=*) drehbuch=${a#*=} ;;
        halt=*) halt=${a#*=} ;;
        extra=*) extra=${a#*=} ;;
        nurbau=*) nurbau=${a#*=} ;;
        *) echo "unbekannt: $a" >&2; exit 2 ;;
    esac
done
XRES=${res%x*}
YRES=${res#*x}

mkdir -p "$OUT"
BUILDD=${DESIGNBUILD:-/tmp/osum-designbuild-$(pwd | md5sum | cut -c1-12)}
mkdir -p "$BUILDD"

# ---------------------------------------------------------- 1. bauen
bash vendor/firn/fetch-firnc.sh > "$BUILDD/fetch.log" 2>&1 || {
    echo "FEHLGESCHLAGEN: fetch-firnc.sh"; tail -5 "$BUILDD/fetch.log"; exit 1; }
newer=$(find kernel tools/build-kernel.sh -newer "$BUILDD/k0.mb" -print -quit 2>/dev/null || true)
if [ ! -s "$BUILDD/k0.mb" ] || [ -n "$newer" ] || [ -n "${DESIGNREBUILD:-}" ]; then
    ./tools/build-kernel.sh "$BUILDD/k0.mb" > "$BUILDD/k.log" 2>&1 \
        || { echo "FEHLGESCHLAGEN: der Kern baut nicht"; tail -25 "$BUILDD/k.log"; exit 1; }
fi
echo "kernel $(stat -c%s "$BUILDD/k0.mb") Oktette"

if [ ! -s "$BUILDD/crt.o" ] || [ -n "${DESIGNREBUILD:-}" ]; then
    as --64 -o "$BUILDD/crt.o" kernel/user/crt.s 2>"$BUILDD/as.err" \
        || { echo "FEHLGESCHLAGEN: crt.s"; cat "$BUILDD/as.err"; exit 1; }
fi
# Ein Programm ist nicht nur seine eigene Datei: jedes hier importiert
# wlib und wlibc.  Die neueste Datei in kernel/user entscheidet fuer
# alle -- die Runde LOOK hat das auf die langsame Art gelernt.
USERNEW=$(ls -t kernel/user/*.fi 2>/dev/null | head -1)
for p in $progs; do
    if [ -s "$BUILDD/$p.elf" ] && [ -z "${DESIGNREBUILD:-}" ] \
       && [ "$BUILDD/$p.elf" -nt "kernel/user/$p.fi" ] \
       && [ -n "$USERNEW" ] && [ "$BUILDD/$p.elf" -nt "$USERNEW" ]; then
        continue
    fi
    vendor/firn/bin/firnc "kernel/user/$p.fi" -o "$BUILDD/$p.o" \
        > "$BUILDD/e-$p" 2>&1 \
        || { echo "FEHLGESCHLAGEN beim Uebersetzen von $p"; head -30 "$BUILDD/e-$p"; exit 1; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
        -o "$BUILDD/$p.elf" "$BUILDD/crt.o" "$BUILDD/$p.o" 2>"$BUILDD/ld.err" \
        || { echo "FEHLGESCHLAGEN beim Binden von $p"; cat "$BUILDD/ld.err"; exit 1; }
    strip --strip-all "$BUILDD/$p.elf"
done
echo "programme $(echo $progs | wc -w)"

# ------------------------------------------------------------ 2. Platte
python3 tools/k15/tree.py "$OUT/baum" > "$OUT/baum.log" 2>&1 || exit 1
# KEIN `height=`.  Die Dicke der Leiste ist seit dieser Runde eine
# MARKE (`ctrl_h` + zweimal `spacing_xs`, kernel/user/taskbar.fi
# `def_h`); wer sie hier hineinschreibt, misst seine eigene Zahl und
# nicht die des Formsatzes.  `width=` bleibt: das ist die Dicke einer
# SENKRECHTEN Leiste und die haengt an der Breite der Beschriftungen.
printf '# taskbar.conf\nedge=bottom\nwidth=104\nautohide=0\nontop=1\nalign=left\n' \
    > "$OUT/taskbar.conf"
printf '# /etc/theme.conf\nscheme=%s\nmode=%s\naccent=\nshape=%s\nlight_start=07:00\ndark_start=19:00\n' \
    "$scheme" "$mode" "$shape" > "$OUT/theme.conf"
printf '# /etc/time.conf\noffset=120\n' > "$OUT/time.conf"
printf 'lang=de\n' > "$OUT/locale.conf"
printf 'on\n' > "$OUT/uitrace"
cat > "$OUT/passwd" <<'EOF'
root:x:0:0:root:/users/justin:/bin/sh
justin:x:1000:1000:Justin:/users/justin:/bin/sh
EOF
printf 'de\n' > "$OUT/userlocale"

ARGS=(build "$OUT/disk.img" 20480 /lib/
      "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf"
      "/lib/icons.ttf=assets/osum-icons.ttf" /bin/)
for p in $progs; do ARGS+=("/bin/$p=$BUILDD/$p.elf"); done
ARGS+=("/bin/files@/bin/explorer")
ARGS+=(/etc/
       "/etc/theme.conf=$OUT/theme.conf@0644"
       "/etc/time.conf=$OUT/time.conf@0644"
       "/etc/locale.conf=$OUT/locale.conf@0644"
       "/etc/passwd=$OUT/passwd@0644"
       "/etc/uitrace=$OUT/uitrace@0644"
       "/etc/taskbar.conf=$OUT/taskbar.conf@0644")
ARGS+=(/etc/schemas/)
for s in assets/schemes/*.scheme; do
    ARGS+=("/etc/schemas/$(basename "$s" .scheme)=$s@0644")
done
ARGS+=(/etc/shapes/)
for s in assets/shapes/*.shape; do
    ARGS+=("/etc/shapes/$(basename "$s" .shape)=$s@0644")
done
ARGS+=(/etc/themes/)
for s in assets/themes/*.preset; do
    ARGS+=("/etc/themes/$(basename "$s" .preset)=$s@0644")
done
if python3 tools/netview/icons.py bauen "$OUT/nvicons" > "$OUT/nvicons.log" 2>&1; then
    ARGS+=(/etc/netview/)
    for q in state-nocarrier state-noip state-noroute state-online \
             mark-filtered mark-faked mark-none sys-faking \
             tile-fake tile-net tile-hide; do
        [ -e "$OUT/nvicons/$q" ] && ARGS+=("/etc/netview/$q=$OUT/nvicons/$q")
    done
fi
ARGS+=(/usr/ /usr/share/ /usr/share/locale/
       /usr/share/locale/en/ "/usr/share/locale/en/messages=locale/en/messages"
       /usr/share/locale/de/ "/usr/share/locale/de/messages=locale/de/messages")
[ -e locale/en/icons ] && ARGS+=("/usr/share/locale/en/icons=locale/en/icons")
[ -e locale/de/icons ] && ARGS+=("/usr/share/locale/de/icons=locale/de/icons")
ARGS+=(/users/ /users/justin/ /users/justin/config/
       "/users/justin/config/locale=$OUT/userlocale@0644")
# Ein paar Dateien, damit der Dateimanager etwas zu zeigen hat.
mkdir -p "$OUT/heim"
printf 'Notizen zur Runde OBERFLAECHE.\n' > "$OUT/heim/notizen.txt"
printf 'a,b,c\n1,2,3\n' > "$OUT/heim/tabelle.csv"
printf 'Ein Brief an Justin.\n' > "$OUT/heim/brief.txt"
ARGS+=("/users/justin/notizen.txt=$OUT/heim/notizen.txt@0644"
       "/users/justin/tabelle.csv=$OUT/heim/tabelle.csv@0644"
       "/users/justin/brief.txt=$OUT/heim/brief.txt@0644")
rm -rf "$OUT/apps"; cp -a assets/apps "$OUT/apps"
rm -rf "$OUT/apps/widgets.osp"
while read -r z; do ARGS+=("$z"); done < <(python3 tools/k15/bundle.py "$OUT/apps" "$OUT/buendel" 2>/dev/null || true)
while read -r z; do ARGS+=("$z"); done < "$OUT/baum/liste"
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$OUT/mkfs.log" 2>&1 \
    || { echo "FEHLGESCHLAGEN: mkfs"; tail -25 "$OUT/mkfs.log"; exit 1; }
echo "platte $(stat -c%s "$OUT/disk.img") Oktette"
[ "$nurbau" = ja ] && exit 0

# ------------------------------------------------------------ 3. starten
if [ -z "$drehbuch" ]; then
    drehbuch="$OUT/drehbuch.txt"
    cat > "$drehbuch" <<'DREH'
# `wig wigstart` laesst den Starter mit hochkommen -- das Startmenue ist
# also schon offen.  Zuerst wird es zugemacht, damit der Schreibtisch der
# Schreibtisch ist und nicht der Schreibtisch mit einem Fenster darauf.
warteauf 'launcher: ready' || 40
warte 1
klickauf start
warte 2
foto 01-schreibtisch
# --- das Startmenue wieder auf
klickauf start
warte 2
foto 02-startmenue
# --- der Dateimanager: erste Zeile der Trefferliste, dann Ausfuehren
klickauf lzeile0
warte 1
klickauf lrect3
warteauf 'explorer: ready' || 60
warte 3
foto 03-explorer
# --- ein Dialog aus dem Dateimanager
taste ctrl-n
warte 3
foto 04-dialog
taste esc
warte 2
# --- das Kontrollzentrum in der Ecke der Leiste
klickauf netz
warte 3
foto 05-kontrollzentrum
# --- die Einstellungen ueber die unterste Zeile des Kontrollzentrums
klickauf qsalle
warteauf 'settings: ready' || 60
warte 3
foto 06-einstellungen
DREH
fi

SOCK="$OUT/mon.sock"; rm -f "$SOCK" "$OUT/serial.txt"
ACC=()
if [ "$accel" = kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    ACC=(-accel kvm -cpu host)
fi
timeout 600 qemu-system-x86_64 "${ACC[@]}" -kernel "$BUILDD/k0.mb" -m 512 \
    -append "gfx fbres=${XRES}x${YRES} wm desk wmhold wighalt=$halt nokbd nosched noproc nofs $extra" \
    -serial "file:$OUT/serial.txt" -display none -no-reboot \
    -device "VGA,edid=on,xres=$XRES,yres=$YRES,vgamem_mb=32" \
    -monitor "unix:$SOCK,server,nowait" \
    -drive "file=$OUT/disk.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$OUT/qemu.log" 2>&1 &
PID=$!
i=0
while [ $i -lt 2400 ]; do
    grep -qaE '^wm: hold' "$OUT/serial.txt" 2>/dev/null && break
    kill -0 "$PID" 2>/dev/null || break
    sleep 0.15; i=$((i+1))
done
if ! grep -qaE '^wm: hold' "$OUT/serial.txt" 2>/dev/null; then
    echo "FEHLGESCHLAGEN: der Fensterserver ist nie bis 'wm: hold' gekommen"
    tail -20 "$OUT/serial.txt" 2>/dev/null
fi

python3 -u tools/design/fahren.py "$SOCK" "$OUT/serial.txt" "$OUT" "$drehbuch" \
    2>&1 | tee "$OUT/fahren.log"

wait "$PID"; RC=$?
rm -f "$SOCK"
echo "qemu exit $RC"

# ------------------------------------------------------------ 4. PNG
python3 - "$OUT" <<'PY'
import glob, os, sys
from PIL import Image
o = sys.argv[1]
for p in sorted(glob.glob(os.path.join(o, "*.ppm"))):
    im = Image.open(p).convert("RGB")
    q = p[:-4] + ".png"
    im.save(q)
    print("bild %s %dx%d farben=%d"
          % (os.path.basename(q), im.size[0], im.size[1],
             len(im.getcolors(maxcolors=1 << 24) or [])))
PY
exit 0
