#!/usr/bin/env bash
# tests/theme/build.sh -- Kernel, Programme und ein Plattenabbild fuer
# Runde THEME.
#
#   bash tests/theme/build.sh [ausgabeverzeichnis] [uebersetzer]
#
# Das Abbild traegt zusaetzlich zu dem, was Runde K15 gebaut hat:
#
#   /etc/schemas/{day,paper,night,midnight,contrast}
#       die fuenf mitgelieferten Schemata, Oktett fuer Oktett die
#       Dateien aus assets/schemes/ -- NICHT hier neu getippt, sonst
#       misst der Testlaeufer eine zweite Fassung.
#   /etc/theme.conf
#       die Voreinstellung. `mode=auto` ist Absicht: die Automatik ist
#       der Fall, der schiefgehen kann, also ist sie der Fall, in dem
#       die Maschine startet.
#   /etc/time.conf
#       der Zeitzonenversatz, den die Automatik braucht.
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
OUT=${1:-/tmp/theme}
CC=${2:-vendor/firn/bin/firnc}
mkdir -p "$OUT"

# Die Programme, die dieser Lauf braucht -- und nicht mehr. Ein
# OFS-Abbild fasst 4096 Bloecke zu 512 Oktetten, also zwei Megaoktett
# (`tools/osum/mkfs.py`), und /bin/themetest bindet seit dem Zusatz
# `gui` die ganze Widget-Bibliothek ein. `wigdemo`, `edit` und `suchen`
# haben in dieser Runde nichts zu tun und passten sonst nicht mit drauf.
PROGS="themetest explorer starter leiste schreibtisch einstellungen sh echo ls cat"

bash tools/build-kernel.sh "$OUT/k.mb" > "$OUT/k.log" 2>&1 || {
    echo "== der Kern laesst sich nicht bauen"; tail -20 "$OUT/k.log"; exit 1; }
echo "   kern      $(stat -c%s "$OUT/k.mb") Oktette"

as --64 -o "$OUT/crt.o" kernel/user/crt.s || exit 1
rc=0
for p in $PROGS; do
    if ! "$CC" "kernel/user/$p.fi" -o "$OUT/$p.o" > "$OUT/$p.err" 2>&1; then
        echo "== $p: der Uebersetzer sagt nein"
        head -25 "$OUT/$p.err"
        rc=1
        continue
    fi
    if ! ld -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start \
            -o "$OUT/$p.elf" "$OUT/crt.o" "$OUT/$p.o" 2> "$OUT/$p.lderr"; then
        echo "== $p: der Binder sagt nein"
        head -12 "$OUT/$p.lderr"
        rc=1
        continue
    fi
    strip --strip-all "$OUT/$p.elf"
    printf '   %-14s %7d Oktette\n' "$p" "$(stat -c%s "$OUT/$p.elf")"
done
[ "$rc" = 0 ] || exit 1

# Die Liste der Programme HIER hinlegen und nicht in image.sh raten:
# `ls *.elf` findet auch die Reste eines frueheren Laufs, und das
# Abbild ist mit zwei Megaoktett so knapp, dass drei alte Programme es
# ueberlaufen lassen -- was mkfs.py dann als "the disk is full"
# meldet, ohne zu sagen, wessen Platte.
printf '%s\n' "$PROGS" > "$OUT/progs.txt"

python3 tools/k15/baum.py "$OUT/baum" > /dev/null || exit 1

# /etc/theme.conf und /etc/time.conf werden HIER erzeugt und nicht
# eingecheckt: sie sind der ZUSTAND einer Maschine, keine Quelle.
cat > "$OUT/theme.conf" <<'EOF'
# /etc/theme.conf -- welches Schema, welcher Modus, welche Akzentfarbe.
#
# Das Schema liegt unter /etc/schemas/ und liefert die ROHEN Rampen.
# Der Modus entscheidet, welche der Bindungen der semantischen Ebene
# darauf gelegt wird: light, dark, oder auto nach der Tageszeit.
# Ist accent leer, gilt die Akzentfarbe des Schemas.
scheme=day
mode=auto
accent=
light_start=07:00
dark_start=19:00
EOF
cat > "$OUT/time.conf" <<'EOF'
# Minuten, um die die ANZEIGE gegen UTC verschoben wird. Die
# Hardware-Uhr laeuft auf UTC und dieser Kernel kann sie nicht stellen.
offset=120
EOF

ARGS=(build "$OUT/disk.img" 4096 /lib/
      "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf"
      /bin/)
for p in $PROGS; do ARGS+=("/bin/$p=$OUT/$p.elf"); done
ARGS+=("/bin/files@/bin/explorer")
ARGS+=(/etc/ "/etc/theme.conf=$OUT/theme.conf@0644"
       "/etc/time.conf=$OUT/time.conf@0644")
ARGS+=(/etc/schemas/)
for s in assets/schemes/*.scheme; do
    ARGS+=("/etc/schemas/$(basename "$s" .scheme)=$s@0644")
done
# DIE ANWENDUNGSBUENDEL, aber nur die, deren Programm auf diesem
# Abbild wirklich liegt. `editor.prog` zeigt auf /bin/edit und
# `widgets.prog` auf /bin/wigdemo, und beide sind hier nicht dabei --
# mkfs.py bricht sonst mit "gibt es nicht" ab, und zwar zu Recht.
rm -rf "$OUT/apps"
cp -a assets/apps "$OUT/apps"
rm -rf "$OUT/apps/editor.prog" "$OUT/apps/widgets.prog"
while read -r zeile; do ARGS+=("$zeile"); done \
    < <(python3 tools/k15/buendel.py "$OUT/apps" "$OUT/buendel")
while read -r pfad; do ARGS+=("$pfad"); done < "$OUT/baum/liste"
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$OUT/mkfs.log" 2>&1 || {
    echo "== mkfs.py fehlgeschlagen"; tail -20 "$OUT/mkfs.log"; exit 1; }
echo "   abbild    $(stat -c%s "$OUT/disk.img") Oktette"
exit 0
