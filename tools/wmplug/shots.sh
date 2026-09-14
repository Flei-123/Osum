#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/wmplug/shots.sh -- BILDER FUER DIE JURY.
#
# Misst nichts, sondern ZEIGT: derselbe Kernel, dasselbe Abbild, einmal
# ohne und einmal mit Plugin, einmal breit und einmal eng. Die engen
# Bilder sind die wichtigen -- Ueberlappungen in der Leiste faellt erst
# auf, wenn der Schirm schmal ist.
#
# Gebrauch: bash tools/wmplug/shots.sh [zielordner]
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
. tools/lib/userprog.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
ZIEL=${1:-.gauntlet-shots}
mkdir -p "$ZIEL"

TMPD=$(mktemp -d /tmp/wmplug-shots-XXXXXX)
[ "${SHOTS_KEEP:-0}" = 1 ] || trap 'rm -rf "$TMPD"' EXIT

echo "== bauen =="
bash tools/build-kernel.sh "$TMPD/k.mb" > "$TMPD/k.log" 2>&1 \
    || { tail -12 "$TMPD/k.log"; echo "Kernel baut nicht"; exit 1; }
as --64 -o "$TMPD/crt.o" kernel/user/crt.s || exit 1
PROGS="desktop taskbar launcher calc sh pluguhr plugregel plugpaar plugboese wmplug"
for p in $PROGS; do
    up_build vendor/firn/bin/firnc "$p" "$TMPD/$p.o" "$TMPD/$p.elf" \
        "$TMPD/crt.o" kernel/user/user.ld 0 "$TMPD/$p.err" \
        || { head -6 "$TMPD/$p.err"; echo "$p baut nicht"; exit 1; }
done
python3 tools/k15/tree.py "$TMPD/baum" > "$TMPD/baum.log" 2>&1

# ==================================================== RUNDE FIX-R3-3
# DREI ABBILDER, UND /etc/uitrace NUR DORT, WO ES GEBRAUCHT WIRD.
#
# Hier stand EIN Abbild, und in ihm lag immer `/etc/uitrace`. Der
# Schalter macht aus jeder gemalten Textstelle eine Zeile auf der
# seriellen Leitung -- gebraucht wird das genau dann, wenn eine Zusage
# eine KOORDINATE aus der Leiste lesen will (`taskbar: plug nr=0 x= ...`).
# Fuer die Regelbilder braucht es sie nicht, und dort schadet sie: die
# Spur laeuft ueber denselben Weg wie die Ausgabe der Programme, und in
# den Bildern 04/05 stand das Terminalfenster darum voller Zeilen, die
# mit der Fensterregel nichts zu tun haben.
#
#   disk.img       mit uitrace      -- die Leistenbilder (Koordinate)
#   disk-rein.img  OHNE uitrace     -- die Regelbilder 04/05
#   disk-segv.img  mit uitrace und /etc/wmplug.autostart -- der Absturz
printf 'on\n' > "$TMPD/uitrace"
printf 'boesebar segv\n' > "$TMPD/autostart-segv"
mkimg() { # name  spur(0/1)  [autostart-datei]
    local nm=$1 spur=$2 auto=${3:-} p z
    local A=(build "$TMPD/disk-$nm.img" 32768 /lib/
        "/lib/mono.ttf=assets/osum-mono.ttf"
        "/lib/sans.ttf=assets/osum-sans.ttf" /bin/)
    for p in $PROGS; do A+=("/bin/$p=$TMPD/$p.elf"); done
    A+=(/etc/ "/etc/theme=$TMPD/baum/theme")
    [ "$spur" = 1 ] && A+=("/etc/uitrace=$TMPD/uitrace")
    [ -n "$auto" ] && A+=("/etc/wmplug.autostart=$auto")
    [ -f etc/wmplug.conf ] && A+=("/etc/wmplug.conf=etc/wmplug.conf")
    [ -f etc/wmregeln.conf ] && A+=("/etc/wmregeln.conf=etc/wmregeln.conf")
    while read -r z; do A+=("$z"); done < "$TMPD/baum/liste"
    python3 tools/osum/mkfs.py "${A[@]}" > "$TMPD/mkfs-$nm.txt" 2>&1 \
        || { head -5 "$TMPD/mkfs-$nm.txt"; echo "Abbild $nm faellt aus"; exit 1; }
}
mkimg spur 1
mkimg rein 0
mkimg segv 1 "$TMPD/autostart-segv"
cp -f "$TMPD/disk-spur.img" "$TMPD/disk.img"
echo "  drei Abbilder stehen (spur, rein, segv)"

warte() { local f=$1 m=$2 pid=$3 i=0
    while [ $i -lt 700 ]; do
        grep -qa "$m" "$f" 2>/dev/null && return 0
        kill -0 "$pid" 2>/dev/null || return 1
        sleep 0.2; i=$((i+1))
    done; return 1; }

# foto <name> <kommandozeile> <marke> [zweite marke]
# NUR= waehlt einzelne Bilder aus -- sonst werden alle gemacht.
foto() {
    local name=$1 zeile=$2 m1=$3 m2=${4:-} vor=${VOR:-}
    # LEERES `NUR` HEISST: ALLE BILDER. Hier stand einmal
    # `case " ${NUR:-} " in " ") ;;` -- und weil " ${NUR:-} " bei leerem
    # NUR ZWEI Leerzeichen sind und das Muster nur EINES hatte, traf kein
    # Zweig, jedes Foto nahm den Ausgang und das Skript legte nichts ab.
    # Aufgefallen ist es erst, als die Bilder im Ordner alt blieben,
    # obwohl der Lauf gruen aussah. Darum jetzt eine Abfrage, die man
    # lesen kann, statt eines Musters, das man zaehlen muss.
    if [ -n "${NUR:-}" ]; then
        case " $NUR " in *" $name "*) ;; *) return 0;; esac
    fi
    local sock="$TMPD/mon-$name.sock" out="$TMPD/$name.txt"
    rm -f "$out" "$sock"
    # WELCHES ABBILD? `IMG=` nennt es; ohne Angabe das mit der Spur.
    # Siehe den Kopf von `mkimg`: die Spur gehoert nur in die Laeufe,
    # die eine Koordinate aus der Leiste lesen.
    cp -f "$TMPD/disk-${IMG:-spur}.img" "$TMPD/live-$name.img"
    timeout 240 $QEMU_X86 -kernel "$TMPD/k.mb" -m 256 -append "$zeile" \
        -serial "file:$out" -display none -no-reboot \
        -vga std -global VGA.edid=off -monitor "unix:$sock,server,nowait" \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/$name.qemu" 2>&1 &
    local pid=$!
    warte "$out" "$m1" "$pid"
    # AUF DAS FENSTER WARTEN UND NICHT NUR AUF DEN SERVER.
    #
    # GEMESSENER FEHLER DER ERSTEN RUNDE: die Bilder 04 und 05 warteten
    # auf `wm: hold` -- das steht auf der Leitung, BEVOR /bin/calc
    # ueberhaupt geladen ist. Beide Fotos zeigten darum denselben leeren
    # Schreibtisch, und die Bildunterschrift ("das Fenster steht bei
    # 80,60 statt 230,70") war eine Behauptung ohne Bild. `VOR=` nennt
    # die Zeile, die das Bild wirklich beschreibt; gewartet wird darauf
    # zusaetzlich, und wenn sie ausbleibt, faellt das Foto eben so aus,
    # wie es ausfaellt -- gewartet wird endlich, nie ewig.
    [ -n "$vor" ] && warte "$out" "$vor" "$pid"
    sleep 2
    python3 tools/gfx/screenshot.py "$sock" "$TMPD/$name.ppm" 25 > "$TMPD/$name.shot" 2>&1
    if [ -n "$m2" ]; then
        warte "$out" "$m2" "$pid"; sleep 3
        python3 tools/gfx/screenshot.py "$sock" "$TMPD/$name-2.ppm" 25 \
            > "$TMPD/$name-2.shot" 2>&1
    fi
    wait "$pid"; rm -f "$sock"
    printf '  %-26s %s\n' "$name" "$(head -c 20 "$TMPD/$name.ppm" | head -2 | tail -1)"
}

BASE="gfx wm wig desk wmhold wiglong nokbd nosched noproc nofs"
echo "== fotografieren =="
foto start          "$BASE plugaus"                            'wm: hold'
foto uhr            "$BASE wmplug wigapp=/bin/wmplug,enable,uhr,runden=12" \
                    'taskbar: text plug ' 'pluguhr: ende'
# DAS BILD DER VERWALTUNG. Es zeigt ZWEI angemeldete Plugins (das
# Widget und die Regel-Engine, beide von /bin/plugpaar gestartet),
# darunter den Tabellenkopf von `wmplug list` und die Spalten von
# `wmplug info`. Fotografiert wird, wenn der Kopf auf der Leitung steht
# -- nicht bei `wm: hold`, das steht dort, lange bevor ein Plugin lebt.
# Dieselbe Stelle rechnet tools/wmplug/spalten.sh Glyphe fuer Glyphe
# nach; hier entsteht nur das Bild.
foto verwaltung     "$BASE wmplug wigapp=/bin/plugpaar" \
                    'Nr Name'
# Die zwei Bilder der Fensterregel. Sie sind der sichtbare Teil der
# Zusage "ein Plugin wirkt mit, ohne im Compositor zu stecken": mit
# Recht steht das Fenster von /bin/calc dort, wo /etc/wmregeln.conf es
# hinschickt (80,60), ohne Recht dort, wo der Fensterserver es von
# selbst hinlegt (230,70). Fotografiert wird darum ERST, wenn der
# Rechner sein Fenster wirklich hat (`rechner: ready`) UND die Regel
# nachgemessen ist.
IMG=rein VOR='nachgemessen id=' foto regel "$BASE nostart wmplug wigapp=/bin/plugregel,recht,demo" \
                    'rechner: ready'
IMG=rein VOR='nachgemessen id=' foto regel-ohne "$BASE nostart wmplug wigapp=/bin/plugregel,demo" \
                    'rechner: ready'
foto breit          "$BASE fbres=1440x900 wmplug wigapp=/bin/wmplug,enable,uhr,runden=25" \
                    'taskbar: text plug '
foto eng            "$BASE fbres=800x600 wmplug wigapp=/bin/wmplug,enable,uhr,runden=25" \
                    'taskbar: text plug '
foto sehr-eng       "$BASE fbres=640x480 wmplug wigapp=/bin/wmplug,enable,uhr,runden=25" \
                    'taskbar: text plug '
# DIE ZWEI BILDER DES ABSTURZES, AUS EINEM LAUF. /etc/wmplug.autostart
# dieses Abbilds traegt `boesebar segv`: der Schreibtisch schaltet das
# Plugin ein, es besetzt sein Feld in der Leiste (erstes Bild) und
# stuerzt dann mit Absicht ab; der Kern holt es ab, und der Schreibtisch
# malt weiter (zweites Bild). Nachgerechnet wird beides in
# tools/wmplug/run.sh Abschnitt 4 -- hier entstehen nur die Bilder.
IMG=segv foto absturz "$BASE wmplug" \
                    '^plugboese: leiste gesetzt' 'wmplug: tot platz='

echo "== wandeln =="
wandel() { # ppm ziel
    [ -s "$1" ] || { echo "  FEHLT $1"; return 1; }
    python3 tools/gfx/ppm2png.py "$1" "$2" 2>/dev/null \
        || python3 - "$1" "$2" <<'PY'
import sys, zlib, struct
src, dst = sys.argv[1], sys.argv[2]
d = open(src, 'rb').read()
# P6-Kopf lesen: drei Zahlen, Kommentare erlaubt
pos = 0; felder = []
while len(felder) < 4:
    while pos < len(d) and d[pos:pos+1].isspace(): pos += 1
    if d[pos:pos+1] == b'#':
        while d[pos:pos+1] not in (b'\n', b''): pos += 1
        continue
    s = pos
    while pos < len(d) and not d[pos:pos+1].isspace(): pos += 1
    felder.append(d[s:pos])
pos += 1
w, h = int(felder[1]), int(felder[2])
px = d[pos:pos+w*h*3]
roh = b''.join(b'\x00' + px[y*w*3:(y+1)*w*3] for y in range(h))
def chunk(t, b):
    return struct.pack('>I', len(b)) + t + b + struct.pack('>I', zlib.crc32(t+b))
png = (b'\x89PNG\r\n\x1a\n'
       + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
       + chunk(b'IDAT', zlib.compress(roh, 9)) + chunk(b'IEND', b''))
open(dst, 'wb').write(png)
print("  %s  %dx%d" % (dst, w, h))
PY
}
i=1
fehlt=0
benenne() { # ppm zielname
    local n; n=$(printf '%02d' $i); i=$((i+1))
    wandel "$1" "$ZIEL/$n-$2.png" || fehlt=$((fehlt+1))
}
benenne "$TMPD/start.ppm"       "start-ohne-plugin"
benenne "$TMPD/uhr.ppm"         "uhr-widget-an"
benenne "$TMPD/uhr-2.ppm"       "uhr-widget-aus-zur-laufzeit"
benenne "$TMPD/regel.ppm"       "fensterregel-mit-recht"
benenne "$TMPD/regel-ohne.ppm"  "fensterregel-ohne-recht"
benenne "$TMPD/breit.ppm"       "breit-1440x900"
benenne "$TMPD/eng.ppm"         "eng-800x600"
benenne "$TMPD/sehr-eng.ppm"    "sehr-eng-640x480"
# RUNDE FIX-R3-3: die drei Bilder, die es zwar gab, die aber nie in die
# Nummernfolge kamen -- das Foto der Verwaltung wurde in diesem Skript
# aufgenommen und danach vergessen, die zwei Absturzbilder lagen nur in
# docs/shots/wmplug. Ein Bild, das keine Nummer hat, sieht die Jury nicht.
benenne "$TMPD/verwaltung.ppm"  "wmplug-verwaltung"
benenne "$TMPD/absturz.ppm"     "vor-absturz"
benenne "$TMPD/absturz-2.ppm"   "nach-absturz"
GANZ=11
ls -l "$ZIEL"
# EIN LAUF, DER NICHTS ABGELEGT HAT, DARF NICHT GRUEN AUSSEHEN. Vorher
# endete das Skript immer mit 0 -- auch als alle acht Bilder fehlten.
# Wer es aus einem anderen Laeufer ruft, soll das merken koennen.
if [ "$fehlt" -gt 0 ]; then
    echo "SHOTS: $fehlt von $GANZ Bildern fehlen -- die Fotos im Ordner sind dann ALT"
    exit 1
fi
echo "SHOTS: $GANZ Bilder abgelegt in $ZIEL"
