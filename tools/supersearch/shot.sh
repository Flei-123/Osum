#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/supersearch/shot.sh -- RUNDE SUPERSEARCH: EIN LAUF, EINE TASTE,
# EIN BILD.
#
#   bash tools/supersearch/shot.sh <ausgabeordner> [schluessel=wert ...]
#
#     drive=<datei>   Tastendruecke und Mausbewegungen fuer
#                     tools/wm/monitor.py -- das ist der Weg in die
#                     Maschine hinein, `sendkey meta_l` ist eine ECHTE
#                     Taste durch den PS/2-Baustein.
#     shape=classic|modern
#     scheme=day|night|paper|midnight|contrast
#     mode=light|dark
#     lang=de|en
#     extra="..."     weitere Woerter auf die Kernel-Befehlszeile
#     keep=yes        das Plattenabbild stehen lassen
#
# WAS AUF DER PLATTE LIEGT UND WARUM. Ein Heimatverzeichnis mit echten
# Dateien, und zwei davon tragen einen Umlaut IM DATEINAMEN -- sonst
# misst die Zusage "Umlaute gehen" nichts. Und eine Datei mit demselben
# Namen liegt AUSSERHALB des Heimatverzeichnisses: sie darf im Suchfeld
# NICHT auftauchen, und das ist die Gegenprobe zum Heimatfilter.
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"

OUT=${1:?usage: shot.sh <outdir> [key=value ...]}
shift || true

drive=""
shape=modern
scheme=day
mode=light
lang=de
extra=""
keep=no
# EIN LAUF OHNE OBERFLAECHE. `script=<befehl>` startet dieselbe Platte im
# Wortmodus `osum` und laesst die Shell den Befehl ausfuehren -- so wird
# die Rangfolge auf der Standardausgabe gemessen und nicht an einem Bild.
script=""
progs="desktop taskbar settings launcher explorer widgetdemo locate sucht sh echo ls cat edit"
for a in "$@"; do
    case "$a" in
        drive=*) drive=${a#*=} ;;
        shape=*) shape=${a#*=} ;;
        scheme=*) scheme=${a#*=} ;;
        mode=*) mode=${a#*=} ;;
        lang=*) lang=${a#*=} ;;
        extra=*) extra=${a#*=} ;;
        keep=*) keep=${a#*=} ;;
        script=*) script=${a#*=} ;;
        progs=*) progs=${a#*=} ;;
        *) echo "unbekannte Option: $a" >&2; exit 2 ;;
    esac
done

MONO=assets/osum-mono.ttf
SANS=assets/osum-sans.ttf
ICONF=assets/osum-icons.ttf

# Der Bauordner haengt am ABSOLUTEN PFAD DES BAUMS -- die Lehre der
# Runde PAINT: zwei Arbeitsbaeume desselben Repos teilten einen Kern,
# und ein Foto vom alten Zweig zeigte den Schatten des neuen.
BUILDD=${SSBUILD:-/tmp/osum-ssbuild-$(pwd | md5sum | cut -c1-12)}
mkdir -p "$BUILDD" "$OUT"

newer=$(find kernel tools/build-kernel.sh -newer "$BUILDD/k0.mb" -print -quit 2>/dev/null || true)
if [ ! -s "$BUILDD/k0.mb" ] || [ -n "$newer" ] || [ -n "${SSREBUILD:-}" ]; then
    ./tools/build-kernel.sh "$BUILDD/k0.mb" > "$BUILDD/k.log" 2>&1 \
        || { echo "FEHLGESCHLAGEN: der Kern baut nicht"; tail -20 "$BUILDD/k.log"; exit 1; }
fi
echo "kernel $(stat -c%s "$BUILDD/k0.mb") Oktette"

[ -s "$BUILDD/crt.o" ] || as --64 -o "$BUILDD/crt.o" kernel/user/crt.s || exit 1
USERNEW=$(ls -t kernel/user/*.fi 2>/dev/null | head -1)
for p in $progs; do
    if [ -s "$BUILDD/$p.elf" ] && [ -z "${SSREBUILD:-}" ] \
       && [ "$BUILDD/$p.elf" -nt "kernel/user/$p.fi" ] \
       && [ -n "$USERNEW" ] && [ "$BUILDD/$p.elf" -nt "$USERNEW" ]; then
        continue
    fi
    vendor/firn/bin/firnc "kernel/user/$p.fi" -o "$BUILDD/$p.o" \
        > "$BUILDD/e-$p" 2>&1 \
        || { echo "FEHLGESCHLAGEN beim Uebersetzen von $p"; head -20 "$BUILDD/e-$p"; exit 1; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
        -o "$BUILDD/$p.elf" "$BUILDD/crt.o" "$BUILDD/$p.o" 2>"$BUILDD/ld.err" \
        || { echo "FEHLGESCHLAGEN beim Binden von $p"; cat "$BUILDD/ld.err"; exit 1; }
    strip --strip-all "$BUILDD/$p.elf"
done
echo "programme $(echo $progs | wc -w)"

# ----------------------------------------------------------- die Platte
D="$OUT/d"
rm -rf "$D"; mkdir -p "$D/heim/berichte" "$D/heim/bilder" "$D/aussen"

# DIE DATEIEN IM HEIMATVERZEICHNIS. Die Namen sind der Testfall:
#
#   Groesse.txt      -- mit Umlaut. "gro" muss ihn finden, obwohl das
#                       dritte Zeichen zwei Oktette ist.
#   GROESSE-ALT.txt  -- mit GROSSEM Umlaut. Er muss mit derselben
#                       Eingabe gefunden werden, und das geht nur, wenn
#                       die Faltung 0xC3 0x96 auf 0xC3 0xB6 zieht.
#   Bericht.txt      -- ein gewoehnlicher Name daneben.
printf 'Groesse in Zahlen\n' > "$D/heim/berichte/Größe.txt"
printf 'die aeltere Fassung\n' > "$D/heim/berichte/GRÖSSE-ALT.txt"
printf 'ein Bericht\n' > "$D/heim/berichte/Bericht.txt"
printf 'Notizen\n' > "$D/heim/notizen.txt"
printf 'Urlaub\n' > "$D/heim/bilder/strand.osym"
printf 'Editor-Beispiel\n' > "$D/heim/editor-beispiel.txt"
# DIE GEGENPROBE: derselbe Name, ausserhalb der Heimat.
printf 'darf nicht auftauchen\n' > "$D/aussen/Größe.txt"

printf '# taskbar.conf\nedge=bottom\nheight=28\nwidth=104\nautohide=0\nontop=1\nalign=left\n' \
    > "$D/taskbar.conf"
printf '# /etc/theme.conf\nscheme=%s\nmode=%s\naccent=\nshape=%s\nlight_start=07:00\ndark_start=19:00\n' \
    "$scheme" "$mode" "$shape" > "$D/theme.conf"
printf '# /etc/time.conf\noffset=120\n' > "$D/time.conf"
printf 'lang=%s\n' "$lang" > "$D/locale.conf"
# ROOTS HEIMAT IST /users/root, UND DAS IST DER GANZE FILTER. Die
# Schreibtischprogramme laufen unter uid 0; stuende hier wie sonst `/`,
# waere das Heimatverzeichnis die Wurzel und der Filter wirkungslos --
# er wuerde gemessen, ohne etwas auszusieben.
cat > "$D/passwd" <<'EOF'
root:x:0:0:root:/users/root:/bin/sh
justin:x:1000:1000:Justin:/users/justin:/bin/sh
EOF

ARGS=(build "$OUT/disk.img" 16384 /lib/
      "/lib/mono.ttf=$MONO" "/lib/sans.ttf=$SANS" "/lib/icons.ttf=$ICONF" /bin/)
for p in $progs; do ARGS+=("/bin/$p=$BUILDD/$p.elf"); done
ARGS+=("/bin/files@/bin/explorer")
ARGS+=(/etc/
       "/etc/theme.conf=$D/theme.conf@0644"
       "/etc/time.conf=$D/time.conf@0644"
       "/etc/locale.conf=$D/locale.conf@0644"
       "/etc/passwd=$D/passwd@0644"
       "/etc/taskbar.conf=$D/taskbar.conf@0644")
ARGS+=(/etc/schemas/)
for s in assets/schemes/*.scheme; do
    ARGS+=("/etc/schemas/$(basename "$s" .scheme)=$s@0644")
done
ARGS+=(/etc/shapes/)
for s in assets/shapes/*.shape; do
    ARGS+=("/etc/shapes/$(basename "$s" .shape)=$s@0644")
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
ARGS+=(/users/ /users/root/ /users/root/berichte/ /users/root/bilder/)
ARGS+=("/users/root/berichte/Größe.txt=$D/heim/berichte/Größe.txt@0644")
ARGS+=("/users/root/berichte/GRÖSSE-ALT.txt=$D/heim/berichte/GRÖSSE-ALT.txt@0644")
ARGS+=("/users/root/berichte/Bericht.txt=$D/heim/berichte/Bericht.txt@0644")
ARGS+=("/users/root/notizen.txt=$D/heim/notizen.txt@0644")
ARGS+=("/users/root/bilder/strand.osym=$D/heim/bilder/strand.osym@0644")
ARGS+=("/users/root/editor-beispiel.txt=$D/heim/editor-beispiel.txt@0644")
ARGS+=(/aussen/ "/aussen/Größe.txt=$D/aussen/Größe.txt@0644")
while read -r z; do ARGS+=("$z"); done < <(python3 tools/k15/bundle.py assets/apps "$OUT/buendel")
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$OUT/mkfs.log" 2>&1 \
    || { echo "FEHLGESCHLAGEN: mkfs"; tail -20 "$OUT/mkfs.log"; exit 1; }
echo "platte $(stat -c%s "$OUT/disk.img") Oktette"

# ------------------------------------------------------------ der Lauf
if [ -n "$script" ]; then
    timeout 300 qemu-system-x86_64 -kernel "$BUILDD/k0.mb" -m 256 \
        -append "osum nokbd nosched noproc nofs noring3 script=$script;exit" \
        -serial "file:$OUT/serial.txt" -display none -no-reboot \
        -drive "file=$OUT/disk.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$OUT/qemu.log" 2>&1
    echo "qemu beendet mit $?"
    [ "$keep" = yes ] || rm -f "$OUT/disk.img"
    grep -aE '^(sucht|sucher|locate)' "$OUT/serial.txt" 2>/dev/null | head -60
    exit 0
fi
SOCK="$OUT/mon.sock"; rm -f "$SOCK" "$OUT/serial.txt" "$OUT/bild.ppm"
QEMU=(qemu-system-x86_64 -kernel "$BUILDD/k0.mb" -m 512
    -append "gfx wm wig wigicons desk wmhold wiglong nokbd nosched noproc nofs $extra"
    -serial "file:$OUT/serial.txt" -display none -no-reboot -vga std
    -monitor "unix:$SOCK,server,nowait"
    -drive "file=$OUT/disk.img,format=raw,if=ide,index=0"
    -device isa-debug-exit,iobase=0xf4,iosize=0x04)
# `-accel kvm` NUR AUF ANSAGE, und die Zahl steht in docs/ROUNDSUPERSEARCH.md:
# fuer diesen Kern ist KVM beim Hochfahren LANGSAMER als die Emulation,
# weil jede serielle Ausgabe und jeder Torzugriff ein VM-Austritt ist.
if [ -n "${SSKVM:-}" ] && [ -e /dev/kvm ]; then QEMU+=(-accel kvm); fi
timeout 600 "${QEMU[@]}" > "$OUT/qemu.log" 2>&1 &
PID=$!
i=0
while [ $i -lt 3000 ]; do
    grep -qaE '^wm: hold' "$OUT/serial.txt" 2>/dev/null && break
    kill -0 "$PID" 2>/dev/null || break
    sleep 0.15; i=$((i+1))
done
echo "hochgefahren nach $((i * 15 / 100)) s"
if [ -n "$drive" ] && [ -s "$drive" ]; then
    python3 tools/wm/monitor.py "$SOCK" "$drive" 0.12 > "$OUT/mon.log" 2>&1
    sleep 1
fi
python3 tools/gfx/screenshot.py "$SOCK" "$OUT/bild.ppm" 30 > "$OUT/shot.log" 2>&1
kill "$PID" 2>/dev/null
wait "$PID" 2>/dev/null
rm -f "$SOCK"
if [ ! -s "$OUT/bild.ppm" ]; then
    echo "kein Bild; qemu sagte:"
    tail -3 "$OUT/qemu.log" | sed 's/^/    /'
    tail -2 "$OUT/shot.log" | sed 's/^/    /'
fi
[ "$keep" = yes ] || rm -f "$OUT/disk.img"
grep -aE '^(sucher|sucht|hk|taskbar: (work|geom)|settings: reiter|wm: hold)' \
    "$OUT/serial.txt" 2>/dev/null | head -80
exit 0
