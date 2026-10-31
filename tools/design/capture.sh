#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/design/capture.sh -- RUNDE OBERFLAECHE: SIEBEN ANSICHTEN, EIN START.
#
#   bash tools/design/capture.sh <ausgabeverzeichnis> [key=value ...]
#
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
export FIRN_REPO=${FIRN_REPO:-/root/jarvis/projects/u_DiS4in7esMF1/firn}

OUT=${1:?usage: capture.sh <outdir> [key=value ...]}
shift || true

shape=osum
# r402: `startstyle=list` puts /etc/startmenu.conf (`style=list`) on the image: the OLD list window
# of the start menu (the runs that measure the list's rows); empty = the Windows 11 window
startstyle=
# r402: `shadow=on` writes the window shadow switch into /etc/theme.conf (default: off, as shipped)
shadow=
uitrace=no
scheme=day
mode=light
res=1280x800
zweite=""
fs=aus
#
accel=tcg
halt=300
extra=""
nurbau=nein
vorherbild=nein
#
ton=nein
drehbuch=""
qemuargs=""
imgfiles=""
lang=en
dark_scheme=""
accent=""
#
uiscale=""
# 04.10.2026 (menu blur bug): the two glass keys of /etc/theme.conf, empty =
# not written (the theme's default, 100 = opaque)
window_alpha=""
taskbar_alpha=""
progs="desktop taskbar settings launcher explorer edit sh echo ls cat theme"
for a in "$@"; do
    case "$a" in
        shape=*) shape=${a#*=} ;;
        uitrace=*) uitrace=${a#*=} ;;
        lang=*) lang=${a#*=} ;;
        dark_scheme=*) dark_scheme=${a#*=} ;;
        uiscale=*) uiscale=${a#*=} ;;
        accent=*) accent=${a#*=} ;;
        window_alpha=*) window_alpha=${a#*=} ;;
        taskbar_alpha=*) taskbar_alpha=${a#*=} ;;
        clock_lines=*) clock_lines=${a#*=} ;;
        hide_missing=*) hide_missing=${a#*=} ;;
        pins=*) pins=${a#*=} ;;
        battfake=*) battfake=${a#*=} ;;
        clock_seconds=*) clock_seconds=${a#*=} ;;
        scheme=*) scheme=${a#*=} ;;
        startstyle=*) startstyle=${a#*=} ;;
        shadow=*) shadow=${a#*=} ;;
        mode=*) mode=${a#*=} ;;
        res=*) res=${a#*=} ;;
        accel=*) accel=${a#*=} ;;
        progs=*) progs=${a#*=} ;;
        drehbuch=*) drehbuch=${a#*=} ;;
        qemuargs=*) qemuargs=${a#*=} ;;
        imgfiles=*) imgfiles=${a#*=} ;;
        halt=*) halt=${a#*=} ;;
        extra=*) extra=${a#*=} ;;
        zweite=*) zweite=${a#*=} ;;
        fs=*) fs=${a#*=} ;;
        nurbau=*) nurbau=${a#*=} ;;
        vorherbild=*) vorherbild=${a#*=} ;;
        ton=*) ton=${a#*=} ;;
        *) echo "unbekannt: $a" >&2; exit 2 ;;
    esac
done
[ "${battfake:-}" = ja ] && extra="$extra battfake"
XRES=${res%x*}
YRES=${res#*x}
SKAL=""
if [ -n "$uiscale" ]; then SKAL="uiscale=$uiscale"; fi
echo "uiscale ${uiscale:-1 (Vorgabe)}"

mkdir -p "$OUT"
# Build dir: DESIGNBUILD wins; under /root/jarvis/bin/heavy (TMPDIR=/tmp/heavy-run.*, deleted by heavy afterwards) every run gets its own
# $TMPDIR/db so parallel runs in one tree cannot disturb each other; otherwise one dir per tree (hash of the working directory).
case "${TMPDIR:-}" in
    /tmp/heavy-run.*) _bd_default="$TMPDIR/db" ;;
    *) _bd_default="/tmp/osum-designbuild-$(pwd | md5sum | cut -c1-12)" ;;
esac
BUILDD=${DESIGNBUILD:-$_bd_default}
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
USERNEW=$(ls -t kernel/user/*.fi 2>/dev/null | head -1)
for p in $progs; do
    if [ -s "$BUILDD/$p.elf" ] && [ -z "${DESIGNREBUILD:-}" ] \
       && [ "$BUILDD/$p.elf" -nt "kernel/user/$p.fi" ] \
       && [ -n "$USERNEW" ] && [ "$BUILDD/$p.elf" -nt "$USERNEW" ]; then
        continue
    fi
    vendor/firn/bin/firnc -c "kernel/user/$p.fi" -o "$BUILDD/$p.o" \
        > "$BUILDD/e-$p" 2>&1 \
        || { echo "FEHLGESCHLAGEN beim Uebersetzen von $p"; head -30 "$BUILDD/e-$p"; exit 1; }
    CRT="$BUILDD/crt.o"
    if grep -qa '^profile app' "kernel/user/$p.fi"; then
        CRT=""
    fi
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
        -o "$BUILDD/$p.elf" $CRT "$BUILDD/$p.o" 2>"$BUILDD/ld.err" \
        || { echo "FEHLGESCHLAGEN beim Binden von $p"; cat "$BUILDD/ld.err"; exit 1; }
    strip --strip-all "$BUILDD/$p.elf"
done
echo "programme $(echo $progs | wc -w)"

# ------------------------------------------------------------ 2. Platte
python3 tools/k15/tree.py "$OUT/baum" > "$OUT/baum.log" 2>&1 || exit 1
printf '# taskbar.conf\nedge=bottom\nwidth=104\nautohide=0\nontop=1\nalign=left\n' \
    > "$OUT/taskbar.conf"
printf 'clock_seconds=%s\nclock_date=1\nclock_weekday=0\nclock_lines=%s\n' \
    "${clock_seconds:-0}" "${clock_lines:-2}" >> "$OUT/taskbar.conf"
[ -n "${hide_missing:-}" ] && \
    printf 'hide_missing=%s\n' "$hide_missing" >> "$OUT/taskbar.conf"
printf 'pins=%s\n' "${pins:-certus,explorer,terminal,settings}" \
    >> "$OUT/taskbar.conf"
{
  printf '# /etc/theme.conf\nscheme=%s\n' "$scheme"
  [ -n "$dark_scheme" ] && printf 'dark_scheme=%s\n' "$dark_scheme"
  printf 'mode=%s\naccent=%s\nshape=%s\nlight_start=07:00\ndark_start=19:00\n' \
    "$mode" "$accent" "$shape"
  [ -n "$shadow" ] && printf 'shadow=%s\n' "$shadow"
  [ -n "$window_alpha" ] && printf 'window_alpha=%s\n' "$window_alpha"
  [ -n "$taskbar_alpha" ] && printf 'taskbar_alpha=%s\n' "$taskbar_alpha"
} > "$OUT/theme.conf"
printf '# /etc/time.conf\noffset=120\n' > "$OUT/time.conf"
#
printf 'lang=%s\n' "$lang" > "$OUT/locale.conf"
#
#     bash tools/design/capture.sh /tmp/x uitrace=yes
#
if [ "${uitrace:-no}" = yes ]; then
    printf 'on\n' > "$OUT/uitrace"
else
    rm -f "$OUT/uitrace"
fi
cat > "$OUT/passwd" <<'EOF'
root:x:0:0:root:/users/justin:/bin/sh
justin:x:1000:1000:Justin:/users/justin:/bin/sh
EOF
printf '%s\n' "$lang" > "$OUT/userlocale"

ARGS=(build "$OUT/disk.img" 49152 --v3 "--time=${CAPTURE_TIME:-$(date +%s)}" /lib/
      "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" "/lib/bold.ttf=assets/osum-sans-bold.ttf"
      "/lib/icons.ttf=assets/osum-icons.ttf" /bin/)
for p in $progs; do ARGS+=("/bin/$p=$BUILDD/$p.elf"); done
for z in $imgfiles; do ARGS+=("$z"); done
ARGS+=("/bin/files@/bin/explorer")
ARGS+=(/mnt/)
ARGS+=(/etc/
       "/etc/theme.conf=$OUT/theme.conf@0644"
       "/etc/time.conf=$OUT/time.conf@0644"
       "/etc/locale.conf=$OUT/locale.conf@0644"
       "/etc/passwd=$OUT/passwd@0644"
       "/etc/taskbar.conf=$OUT/taskbar.conf@0644")
if [ "$startstyle" = list ]; then
    printf 'style=list\n' > "$OUT/startmenu.conf"
    ARGS+=("/etc/startmenu.conf=$OUT/startmenu.conf@0644")
fi
if [ -f "$OUT/uitrace" ]; then
    ARGS+=("/etc/uitrace=$OUT/uitrace@0644")
fi
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
             tile-fake tile-net tile-hide tile-dark tile-power tile-tile; do
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
mkdir -p "$OUT/heim"
printf 'Notizen zur Runde OBERFLAECHE.\n' > "$OUT/heim/notizen.txt"
printf 'a,b,c\n1,2,3\n' > "$OUT/heim/tabelle.csv"
printf 'Ein Brief an Justin.\n' > "$OUT/heim/brief.txt"
ARGS+=("/users/justin/notizen.txt=$OUT/heim/notizen.txt@0644"
       "/users/justin/tabelle.csv=$OUT/heim/tabelle.csv@0644"
       "/users/justin/brief.txt=$OUT/heim/brief.txt@0644")
# X5: HOMEFILES=<dir> puts every regular file of <dir> into /users/justin (the explorer4 gate brings test pictures)
if [ -n "${HOMEFILES:-}" ] && [ -d "$HOMEFILES" ]; then
    for hf in "$HOMEFILES"/*; do
        [ -f "$hf" ] && ARGS+=("/users/justin/$(basename "$hf")=$hf@0644")
    done
fi
rm -rf "$OUT/apps"; cp -a assets/apps "$OUT/apps"
#
while read -r z; do ARGS+=("$z"); done < <(python3 tools/k15/bundle.py "$OUT/apps" "$OUT/buendel" "nur=$progs" 2>/dev/null || true)
while read -r z; do ARGS+=("$z"); done < "$OUT/baum/liste"
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$OUT/mkfs.log" 2>&1 \
    || { echo "FEHLGESCHLAGEN: mkfs"; tail -25 "$OUT/mkfs.log"; exit 1; }
echo "platte $(stat -c%s "$OUT/disk.img") Oktette"
# ======================================================= RUNDE CLIP-2
#
if [ "${vorherbild:-nein}" = ja ]; then
    cp "$OUT/disk.img" "$OUT/disk.img.vorher"
    echo "vorherbild $(stat -c%s "$OUT/disk.img.vorher") Oktette"
fi
[ "$nurbau" = ja ] && exit 0

# ------------------------------------------------------------ 3. starten
if [ -z "$drehbuch" ]; then
    drehbuch="$OUT/drehbuch.txt"
    cat > "$drehbuch" <<'DREH'
# r837: the start menu is CLOSED after boot (no `wigstart` any more, r835). Esc closes an
# open menu and does nothing otherwise, so the desktop is the desktop either way; then ONE
# click on Start opens the menu (two clicks closed it again).
warteauf 'launcher: ready' || 40
warte 1
taste esc
warte 2
foto 01-schreibtisch
# --- open the start menu
klickauf start
warte 2
foto 02-startmenue
# ==================================================== RUNDE VEKTOR
# HIER DARF NICHT GEWARTET WERDEN, UND DAS IST GEMESSEN.
#
# Justins Befund: "das Abnahmeskript oeffnet Explorer, Einstellungen
# und Kontrollzentrum nie, deshalb sind 02-05 praktisch identisch".
# Er hat recht, und der Grund stand die ganze Zeit auf der Leitung:
#
#     launcher: ready
#     launcher: fokus weg t=9226 gnade=6335
#     launcher: zugemacht
#     ...
#     osum: syscalls=7 forks=0 execves=0     <- NIE ein Programm
#
# Der Starter macht sich SELBST zu, sobald er den Fokus verliert und
# die Gnadenfrist abgelaufen ist (launcher.fi: GNADE_TICKS = 30, also
# 300 ms bei 100 Hz). Ein `warte 1` zwischen den Klicks ist ZEHNMAL
# so lang. Beim Klick auf die Trefferzeile war das Menue also laengst
# zu, der Klick landete auf dem Schreibtisch, der Dateimanager kam nie
# hoch -- und `03-explorer`, `04-dialog` und `05-kontrollzentrum`
# zeigten alle denselben leeren Schreibtisch. Genau das hat er als
# "gleiche Bilder unter verschiedenen Namen" gemeldet.
#
# Es ist WEDER ein 4K-Fehler noch der Strg+N-Fehler aus OFFEN.md
# G-003: die beiden Bilder waren in JEDER Aufloesung Oktett fuer
# Oktett gleich (md5 1abb3b5236 bei 2560x1440, 5019abb57f bei
# 3840x2160).
#
# Also: klicken, ohne dazwischen zu warten.
# --- der Dateimanager: erste Zeile der Trefferliste, dann Ausfuehren
klickauf lzeile0
klickauf lrect3
warteauf 'explorer: ready' || 60
warte 3
# ================================================== RUNDE MERGE-10
# DAS STARTMENUE MUSS ZU SEIN, BEVOR EINE TASTE AN DEN DATEIMANAGER
# GEHEN KANN.
#
# Der Starter startet das Programm und BLEIBT DABEI OFFEN -- er liegt
# auf L_TOP und holt sich den Eingabefokus zurueck, sobald seine
# Bewegung ausgelaufen ist. Im Mitschnitt steht das woertlich:
#
#     wm: fokus id=14 vor=11     <- der Dateimanager bekommt ihn
#     explorer: ready
#     wm: fokus id=11 vor=14     <- der Starter holt ihn zurueck
#     key: ...                   <- und DORT landet Strg+N
#
# Solange das so ist, geht jedes `taste`-Kommando an das Startmenue
# und nicht an das Fenster, das im Bild zu sehen ist. Genau daran ist
# `04-dialog` in jedem bisherigen Lauf gescheitert -- das Bild war
# Oktett fuer Oktett `03-explorer`, und in OFFEN.md steht seitdem
# G-003 "Strg+N oeffnet keinen Dialog, im Emulator reproduzierbar".
#
# ESCAPE UND NICHT NOCH EIN KLICK AUF START. Der Klick ist ein
# UMSCHALTER: das Menue schliesst sich beim Starten eines Programms
# von selbst, ein Klick auf Start macht es dann WIEDER AUF -- gemessen
# als `taskbar: state n=3` mit einem zweiten Dateimanager (id=15)
# hinterher. `Escape` schliesst nur, es oeffnet nie, und der Starter
# nimmt es ausdruecklich entgegen (launcher.fi, `KEY_ESC` -> return).
# Ist das Menue schon zu, geht das Escape ins Leere und schadet nicht.
taste esc
warte 1
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
TONDEV=()
if [ "$ton" = ja ]; then
    extra="$extra audio nosounds"
    TONDEV=(-audiodev none,id=snd0 -device intel-hda
            -device hda-duplex,audiodev=snd0)
fi
ACC=()
if [ "$accel" = kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    ACC=(-accel kvm -cpu host)
fi
FSFLAG="nofs"
[ "${fs:-aus}" = an ] && FSFLAG="vfs"

ZWEITE=()
if [ -n "$zweite" ]; then
    cp "$zweite" "$OUT/zweite.img"
    ZWEITE=(-drive "file=$OUT/zweite.img,format=raw,if=ide,index=1")
fi
timeout 600 qemu-system-x86_64 "${ACC[@]}" -kernel "$BUILDD/k0.mb" -m 512 \
    -append "gfx fbres=${XRES}x${YRES} wm desk wmhold wighalt=$halt nokbd nosched noproc $FSFLAG lang=$lang $SKAL $extra" \
    -serial "file:$OUT/serial.txt" -display none -no-reboot \
    -device "VGA,edid=on,xres=$XRES,yres=$YRES,vgamem_mb=32" \
    -monitor "unix:$SOCK,server,nowait" \
    -drive "file=$OUT/disk.img,format=raw,if=ide,index=0" \
    "${ZWEITE[@]}" \
    "${TONDEV[@]}" \
    $qemuargs \
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

python3 -u tools/design/drive.py "$SOCK" "$OUT/serial.txt" "$OUT" "$drehbuch" \
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
