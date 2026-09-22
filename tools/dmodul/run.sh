#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/dmodul/run.sh -- RUNDE MODULE: DER BEWEIS, DASS EIN MODUL SICH
# ZIEHEN LAESST UND DEN NEUSTART UEBERLEBT.
#
#   bash tools/dmodul/run.sh <ausgabe> [accel=kvm|tcg]
#
# WARUM `dmodul` UND NICHT `modul`. `tools/module/run.sh` GIBT ES SCHON
# -- das ist der Laeufer des NACHLADBAREN TREIBERS (kernel/ldr/module.fi,
# `ps2m.ko`). Er hat mit den Schreibtischmodulen nichts zu tun, und zwei
# Laeufer mit fast demselben Namen im selben Verzeichnis sind genau die
# Falle, in die eine spaetere Runde tritt. `d` steht fuer Desktop.
#
# ============================================================ WAS ER MISST
#
# Drei Bilder, und das dritte ist das einzige, das wirklich etwas
# beweist:
#
#   1-vorgabe.png    Ohne /etc/module.conf. Die drei Kaestchen stehen
#                    an ihrer Vorgabe (Anker 1 = rechts oben).
#   2-gezogen.png    Nach einem ZUG mit gehaltener Maustaste: F9 macht
#                    den Bearbeitungsmodus auf, das Uhrmodul wandert in
#                    die LINKE UNTERE Ecke. Der Zug geht ueber den
#                    QEMU-Monitor, also durch denselben PS/2-Weg, den
#                    ein Mensch benutzt.
#   3-neustart.png   DIESELBE PLATTE noch einmal gebootet, ohne
#                    irgendetwas anzufassen. Liegt die Uhr wieder links
#                    unten, hat der Schreibtisch sie wirklich nach
#                    /etc/module.conf geschrieben und wieder gelesen.
#
# DIE GEGENPROBE, OHNE DIE BILD 3 NICHTS SAGT: die Platte wird zwischen
# Lauf 2 und Lauf 3 NICHT neu gebaut. Wuerde sie neu gebaut, stuende
# darin wieder die ausgelieferte Vorgabe, und ein Bild, das die Uhr
# rechts oben zeigt, waere kein Fehler, sondern der Bauplan. Deshalb:
# ein `mkfs`, zwei Boots.
#
# UND DIE ZWEITE GEGENPROBE: nach Lauf 2 wird die Datei AUS DER PLATTE
# zurueckgelesen (`mkfs.py cat`) und neben das Bild gelegt. Wer dem Bild
# nicht traut, liest die vier Zahlen.
set -uo pipefail
# Die Wurzel des Arbeitsbaums, ABSOLUT und einmal.
# `tools/build-kernel.sh` wechselt das Arbeitsverzeichnis; danach
# zeigt jeder relative Pfad woandershin. Deshalb steht hier eine
# Zahl und keine Hoffnung.
WURZEL=$(cd "$(dirname "$0")/../.." && pwd)
cd "$WURZEL" || exit 1

OUT=${1:?usage: run.sh <ausgabe> [accel=kvm|tcg]}
accel=kvm
for a in "${@:2}"; do
    case "$a" in
        accel=*) accel=${a#*=} ;;
    esac
done
mkdir -p "$OUT"
BUILDD=${LOOKBUILD:-/tmp/osum-dmodul-build}
mkdir -p "$BUILDD"
export FIRNLIB="$(pwd)/lib"

sagen() { printf '%-12s %s\n' "$1" "$2"; }
fehler() { echo "FEHLGESCHLAGEN: $*" >&2; exit 1; }

# ------------------------------------------------------------ 1. bauen
newer=$(find "$WURZEL/kernel" "$WURZEL/tools/build-kernel.sh" -newer "$BUILDD/k0.mb" -print -quit 2>/dev/null || true)
if [ ! -s "$BUILDD/k0.mb" ] || [ -n "$newer" ]; then
    "$WURZEL/tools/build-kernel.sh" "$BUILDD/k0.mb" > "$BUILDD/k.log" 2>&1 \
        || { tail -20 "$BUILDD/k.log"; fehler "der Kern baut nicht"; }
fi
sagen kern "$(stat -c%s "$BUILDD/k0.mb") Oktette"

PROGS="desktop taskbar settings launcher explorer sh echo ls cat"
USERNEW=$(ls -t "$WURZEL"/kernel/user/*.fi 2>/dev/null | head -1)
for p in $PROGS; do
    if [ -s "$BUILDD/$p.elf" ] \
       && [ "$BUILDD/$p.elf" -nt "$WURZEL/kernel/user/$p.fi" ] \
       && [ -n "$USERNEW" ] && [ "$BUILDD/$p.elf" -nt "$USERNEW" ]; then
        continue
    fi
    "$WURZEL/vendor/firn/bin/firnc" -c "$WURZEL/kernel/user/$p.fi" -o "$BUILDD/$p.o" \
        > "$BUILDD/e-$p" 2>&1 \
        || { head -20 "$BUILDD/e-$p"; fehler "$p uebersetzt nicht"; }
    CRT="$BUILDD/crt.o"
    if grep -qa '^profile app' "$WURZEL/kernel/user/$p.fi"; then
        CRT=""
    else
        [ -s "$BUILDD/crt.o" ] || as --64 -o "$BUILDD/crt.o" "$WURZEL/kernel/user/crt.s" 2>/dev/null || CRT=""
    fi
    ld -T "$WURZEL/kernel/user/user.ld" --defsym=USER_ENTRY="_F0.u_start" \
        -o "$BUILDD/$p.elf" $CRT "$BUILDD/$p.o" \
        > "$BUILDD/l-$p" 2>&1 \
        || { head -20 "$BUILDD/l-$p"; fehler "$p bindet nicht"; }
done
sagen programme "$(echo $PROGS | wc -w)"

# ------------------------------------------------------------ 2. Platte
platte_bauen() {
    local ziel=$1
    local mitconf=$2
    local ARGS=(build "$ziel" 32768 /lib/)
    # DIE SCHRIFTEN HEISSEN AUF DER PLATTE ANDERS ALS IM BAUM.
    # Ohne sie sagt der Kern `ttf: keine Schrift gefunden` und der
    # Schreibtisch startet gar nicht erst -- gemessen beim ersten Lauf
    # dieser Runde, und im Bild war nichts zu sehen ausser Schwarz.
    ARGS+=("/lib/sans.ttf=$WURZEL/assets/osum-sans.ttf"
           "/lib/mono.ttf=$WURZEL/assets/osum-mono.ttf"
           "/lib/icons.ttf=$WURZEL/assets/osum-icons.ttf")
    [ -s "$WURZEL/assets/osum-sans-bold.ttf" ] \
        && ARGS+=("/lib/bold.ttf=$WURZEL/assets/osum-sans-bold.ttf")
    ARGS+=(/bin/)
    for p in $PROGS; do ARGS+=("/bin/$p=$BUILDD/$p.elf"); done
    printf '# taskbar.conf\nedge=bottom\nheight=28\nwidth=104\nautohide=0\nontop=1\nalign=left\n' \
        > "$OUT/taskbar.conf"
    printf 'scheme=day\nmode=light\nshape=osum\n' > "$OUT/theme.conf"
    printf 'lang=de\n' > "$OUT/locale.conf"
    printf '# /etc/time.conf\noffset=120\n' > "$OUT/time.conf"
    printf 'root:0:0:/users/root:/bin/sh\n' > "$OUT/passwd"
    ARGS+=(/etc/
           "/etc/taskbar.conf=$OUT/taskbar.conf@0644"
           "/etc/theme.conf=$OUT/theme.conf@0644"
           "/etc/locale.conf=$OUT/locale.conf@0644"
           "/etc/time.conf=$OUT/time.conf@0644"
           "/etc/passwd=$OUT/passwd@0644")
    # DER SCHALTER DER MESSUNG. Ohne /etc/uitrace ist der Schreibtisch
    # stumm (Runde BELEG), und genau seine `desktop: modul`-Zeilen sind
    # hier der halbe Beweis.
    printf 'on\n' > "$OUT/uitrace"
    ARGS+=("/etc/uitrace=$OUT/uitrace@0644")
    if [ "$mitconf" = ja ]; then
        ARGS+=("/etc/module.conf=$OUT/module.conf@0644")
    fi
    ARGS+=(/etc/schemas/)
    for s in "$WURZEL"/assets/schemes/*.scheme; do
        ARGS+=("/etc/schemas/$(basename "$s" .scheme)=$s@0644")
    done
    if ls "$WURZEL"/assets/shapes/*.shape >/dev/null 2>&1; then
        ARGS+=(/etc/shapes/)
        for s in "$WURZEL"/assets/shapes/*.shape; do
            ARGS+=("/etc/shapes/$(basename "$s" .shape)=$s@0644")
        done
    fi
    ARGS+=(/users/ /users/root/ /users/root/config/)
    python3 "$WURZEL"/tools/osum/mkfs.py "${ARGS[@]}" > "$OUT/mkfs.log" 2>&1 \
        || { tail -20 "$OUT/mkfs.log"; fehler "mkfs"; }
}

# ------------------------------------------------------------ 3. booten
booten() {
    local disk=$1 bild=$2 seriell=$3 klicks=$4
    gx=${gx:-0}
    gy=${gy:-0}
    local SOCK="$OUT/mon.sock"
    rm -f "$SOCK" "$seriell"
    local ACC=()
    if [ "$accel" = kvm ] && [ -e /dev/kvm ]; then ACC=(-accel kvm); fi
    timeout 420 qemu-system-x86_64 "${ACC[@]}" -kernel "$BUILDD/k0.mb" \
        -m 512 \
        -append "gfx wm wig wigicons desk wmhold wiglong nokbd nosched noproc nofs" \
        -serial "file:$seriell" -display none -no-reboot -vga std \
        -monitor "unix:$SOCK,server,nowait" \
        -drive "file=$disk,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        > "$OUT/qemu.log" 2>&1 &
    local PID=$!
    local i=0
    while [ $i -lt 3200 ]; do
        grep -qaE '^wm: hold' "$seriell" 2>/dev/null && break
        kill -0 "$PID" 2>/dev/null || break
        sleep 0.15; i=$((i+1))
    done
    if [ -n "$klicks" ]; then
        python3 "$WURZEL"/tools/themestore/click.py $klicks > "$OUT/mon.txt" 2>"$OUT/click.err"
        # ERST DER RECHTE KNOPF AUF DAS MODUL, DANN DER ZUG.
        #
        # Ohne Bearbeitungsmodus nimmt der Schreibtisch den Zug nicht
        # an -- das ist der Sinn des Modus und zugleich seine
        # Gegenprobe. Geplant war dafuer F9; die Taste kommt bei einem
        # Fenster auf `L_DESK` nie an (gemessen, siehe der lange
        # Kommentar in kernel/user/desktop.fi bei EV_DOWN). Also der
        # rechte Knopf, an genau der Stelle, an der gleich gegriffen
        # wird.
        #
        # `mouse_button 2` ist rechts (1 links, 2 rechts, 4 Mitte im
        # QEMU-Monitor). Die Fahrt dorthin macht click.py, indem der
        # Zug ohnehin an dieser Stelle anfaengt -- deshalb wird hier
        # nur der Knopf davorgesetzt, nachdem der Zeiger schon steht.
        {
            python3 "$WURZEL"/tools/themestore/click.py "$gx,$gy" \
                | sed 's/^mouse_button 1$/mouse_button 2/'
            echo "warte 1.5"
            cat "$OUT/mon.txt"
        } > "$OUT/mon2.txt"
        python3 "$WURZEL"/tools/wm/monitor.py "$SOCK" "$OUT/mon2.txt" \
            > "$OUT/click.log" 2>&1
        # Warten, bis der Gast still ist -- nicht auf die Uhr, sondern
        # auf ihn (derselbe Grund wie in tools/themestore/build.sh).
        local LAST=-1 QUIET=0 j=0 NOW
        while [ $j -lt 24 ]; do
            sleep 0.5
            NOW=$(stat -c %s "$seriell" 2>/dev/null || echo 0)
            if [ "$NOW" = "$LAST" ]; then
                QUIET=$((QUIET+1))
                if [ "$QUIET" -ge 2 ]; then break; fi
            else
                QUIET=0
            fi
            LAST=$NOW
            j=$((j+1))
        done
    fi
    python3 "$WURZEL"/tools/gfx/screenshot.py "$SOCK" "${bild%.png}.ppm" 25 \
        > "$OUT/shot.log" 2>&1 || true
    kill "$PID" 2>/dev/null
    wait "$PID" 2>/dev/null
    if [ -s "${bild%.png}.ppm" ]; then
        python3 "$WURZEL"/tools/gfx/ppm2png.py "${bild%.png}.ppm" "$bild" \
            > /dev/null 2>&1 || true
        rm -f "${bild%.png}.ppm"
    fi
}

# ================================================== LAUF 1: die Vorgabe
sagen lauf1 "ohne /etc/module.conf -- die Vorgabe"
platte_bauen "$OUT/disk.img" nein
booten "$OUT/disk.img" "$OUT/1-vorgabe.png" "$OUT/s1.txt" ""
grep -a 'desktop: modul ' "$OUT/s1.txt" > "$OUT/1-modul.txt" || true
sagen "  module" "$(wc -l < "$OUT/1-modul.txt") Zeilen gemeldet"

# ================================================== LAUF 2: ziehen
#
# Wohin gegriffen wird, steht NICHT hier als getippte Zahl, sondern wird
# aus Lauf 1 GELESEN: die Mitte des Uhrmoduls ist der Griff. Eine
# getippte Zahl waere nach der naechsten Schriftaenderung falsch, und der
# Zug ginge ins Leere, ohne dass jemand merkt warum.
GRIFF=$(awk '/name=uhr /{for(i=1;i<=NF;i++){if($i ~ /^x=/)x=substr($i,3);if($i ~ /^y=/)y=substr($i,3);if($i ~ /^w=/)w=substr($i,3);if($i ~ /^h=/)h=substr($i,3)}print int(x+w/2)" "int(y+h/2)}' "$OUT/1-modul.txt" | head -1)
[ -n "$GRIFF" ] || fehler "Lauf 1 hat die Lage der Uhr nicht gemeldet (uitrace?)"
gx=${GRIFF% *}
gy=${GRIFF#* }
sagen "  griff" "Uhr-Mitte bei $gx,$gy"
# Ziel: linke untere Ecke. 40/700 liegt im Fangbereich der Kanten, also
# rastet das Kaestchen dort ein -- und bekommt beim Loslassen den Anker
# LINKS UNTEN (A_LU = 2). Genau das ist die Zahl, die Lauf 3 prueft.
sagen lauf2 "F9, dann Uhr nach links unten ziehen"
booten "$OUT/disk.img" "$OUT/2-gezogen.png" "$OUT/s2.txt" "$gx,$gy>300,600>40,700"
grep -a 'desktop: modul' "$OUT/s2.txt" > "$OUT/2-modul.txt" || true

# Die Datei AUS DER PLATTE lesen -- der Beleg neben dem Bild.
python3 "$WURZEL"/tools/osum/mkfs.py cat "$OUT/disk.img" /etc/module.conf \
    > "$OUT/2-module.conf" 2>/dev/null || true
if [ -s "$OUT/2-module.conf" ]; then
    sagen "  datei" "$(tr '\n' ' ' < "$OUT/2-module.conf")"
else
    sagen "  datei" "NICHT GESCHRIEBEN"
fi

# ================================================== LAUF 3: Neustart
#
# DIESELBE PLATTE. Kein mkfs, kein Kopieren, nichts angefasst.
sagen lauf3 "Neustart auf DERSELBEN Platte"
booten "$OUT/disk.img" "$OUT/3-neustart.png" "$OUT/s3.txt" ""
grep -a 'desktop: modul ' "$OUT/s3.txt" > "$OUT/3-modul.txt" || true

# ================================================== DIE ZUSAGEN
feld() {
    awk -v f="$2" '/name=uhr /{for(i=1;i<=NF;i++){n=index($i,"=");
        if(substr($i,1,n-1)==f){print substr($i,n+1); exit}}}' "$1" | head -1
}

echo
echo "== ZUSAGEN =="
gruen=0; rot=0
zusage() {
    if [ "$2" = ja ]; then
        echo "  ok    $1"; gruen=$((gruen+1))
    else
        echo "  ROT   $1"; rot=$((rot+1))
    fi
}

a1=$(feld "$OUT/1-modul.txt" anker)
a3=$(feld "$OUT/3-modul.txt" anker)
y1=$(feld "$OUT/1-modul.txt" y)
y3=$(feld "$OUT/3-modul.txt" y)
x3=$(feld "$OUT/3-modul.txt" x)

zusage "Lauf 1 meldet drei Module" \
    "$([ "$(wc -l < "$OUT/1-modul.txt")" -ge 3 ] && echo ja || echo nein)"
zusage "Lauf 1: die Uhr haengt rechts oben (anker=1)" \
    "$([ "$a1" = 1 ] && echo ja || echo nein)"
zusage "/etc/module.conf steht nach dem Zug auf der Platte" \
    "$([ -s "$OUT/2-module.conf" ] && echo ja || echo nein)"
zusage "die Datei traegt den Anker links unten (uhr=1,2,...)" \
    "$(grep -qa '^uhr=1,2,' "$OUT/2-module.conf" 2>/dev/null && echo ja || echo nein)"
zusage "nach dem Neustart haengt die Uhr links unten (anker=2)" \
    "$([ "$a3" = 2 ] && echo ja || echo nein)"
zusage "nach dem Neustart liegt sie WEITER UNTEN als vorher" \
    "$([ -n "$y1" ] && [ -n "$y3" ] && [ "$y3" -gt "$y1" ] && echo ja || echo nein)"
zusage "und am linken Rand (x < 64)" \
    "$([ -n "$x3" ] && [ "$x3" -lt 64 ] && echo ja || echo nein)"
for b in 1-vorgabe 2-gezogen 3-neustart; do
    zusage "Bild $b.png ist da" \
        "$([ -s "$OUT/$b.png" ] && echo ja || echo nein)"
done

echo
echo "  gruen=$gruen  rot=$rot"
[ "$rot" = 0 ] || exit 1
echo "DMODUL PASSED."
