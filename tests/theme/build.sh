#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
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
# RUNDE MERGE: 8192 Bloecke statt 4096. Die zehn Programme dieses
# Abbilds sind auf 2 236 160 Oktette gewachsen -- jedes bindet ulib,
# tools, wlib und die libc, und die sind mit jeder Runde groesser
# geworden -- und passten nicht mehr in die zwei Megaoktett, die vor
# Runde OFS3 die Obergrenze einer OFS-Platte waren. `mkfs.py` sagte
# "the disk is full", und das war die ganze Ursache dafuer, dass
# tests/theme/run.sh als Abschnitt umfiel.
# OFS-Abbild fasst 8192 Bloecke zu 512 Oktetten, also vier Megaoktett
# (`tools/osum/mkfs.py`), und /bin/themetest bindet seit dem Zusatz
# `gui` die ganze Widget-Bibliothek ein. `widgetdemo`, `edit` und `suchen`
# haben in dieser Runde nichts zu tun und passten sonst nicht mit drauf.
PROGS="themetest explorer launcher taskbar desktop settings sh echo ls cat"

bash tools/build-kernel.sh "$OUT/k.mb" > "$OUT/k.log" 2>&1 || {
    echo "== der Kern laesst sich nicht bauen"; tail -20 "$OUT/k.log"; exit 1; }
echo "   kern      $(stat -c%s "$OUT/k.mb") Oktette"

as --64 -o "$OUT/crt.o" kernel/user/crt.s || exit 1
rc=0
for p in $PROGS; do
    # RUNDE GRUNDLINIE (A-016): das Profil steht in der Wurzeldatei und
    # wird GELESEN. Wer `profile app` sagt, braucht --profile=app und -c
    # und KEIN crt.o (Firns Anlauf bringt sein eigenes `_start` mit).
    UPROF=""; UCRT="$OUT/crt.o"
    grep -qa '^profile app' "kernel/user/$p.fi" && { UPROF=--profile=app; UCRT=""; }
    if ! "$CC" $UPROF -c "kernel/user/$p.fi" -o "$OUT/$p.o" > "$OUT/$p.err" 2>&1; then
        echo "== $p: der Uebersetzer sagt nein"
        head -25 "$OUT/$p.err"
        rc=1
        continue
    fi
    if ! ld -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start \
            -o "$OUT/$p.elf" $UCRT "$OUT/$p.o" 2> "$OUT/$p.lderr"; then
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

python3 tools/k15/tree.py "$OUT/baum" > /dev/null || exit 1

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

# 8192 blocks (4 MiB) held these programs with 4 per cent to spare
# after round LOOK. That is not spare room, that is a countdown.
#
# RUNDE BAUFEHLER (14.09.2026): 16384 -> 32768 Bloecke (8 -> 16 MiB).
# Derselbe abgelaufene Countdown wie in tools/look/shot.sh. Sechs der
# dreizehn Programme tragen `profile app`, und seit Runde GRUNDLINIE
# werden sie auch so gebaut -- /bin/explorer ist damit 1623040 statt
# 907360 Oktette. Im Protokoll dieses Laeufers steht "mkfs: the disk is
# full", und der Abschnitt meldet nur noch
# "tests/theme/build.sh fehlgeschlagen".
# EIN BLOCK IST 512 OKTETTE (tools/osum/mkfs.py, `BS = 512`).
ARGS=(build "$OUT/disk.img" 32768 /lib/
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
# Abbild wirklich liegt. `editor.osp` zeigt auf /bin/edit und
# `widgets.osp` auf /bin/widgetdemo, und beide sind hier nicht dabei --
# mkfs.py bricht sonst mit "gibt es nicht" ab, und zwar zu Recht.
rm -rf "$OUT/apps"
cp -a assets/apps "$OUT/apps"
rm -rf "$OUT/apps/editor.osp" "$OUT/apps/widgets.osp"
# RUNDE GLYPHE: `nur=` STATT EINER LISTE VON HAND.
#
# Die zwei `rm -rf` daruber sind der Stand von damals: zwei Buendel, die
# man kannte. Die Runde WERKZEUGE hat `taskmgr.osp` dazugelegt, und
# damit brach dieser Laeufer im ERSTEN Schritt ab --
# `mkfs: '/bin/taskmgr' gibt es nicht`, also gar kein Abbild und kein
# einziger gruener Punkt. `nur=` fragt statt zu raten: was nicht unter
# /bin liegt, kommt auch nicht ins Abbild. Der naechste neue
# Buendelname bricht damit nichts mehr.
while read -r zeile; do ARGS+=("$zeile"); done \
    < <(python3 tools/k15/bundle.py "$OUT/apps" "$OUT/buendel" "nur=$PROGS")
while read -r pfad; do ARGS+=("$pfad"); done < "$OUT/baum/liste"
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$OUT/mkfs.log" 2>&1 || {
    echo "== mkfs.py fehlgeschlagen"; tail -20 "$OUT/mkfs.log"; exit 1; }
echo "   abbild    $(stat -c%s "$OUT/disk.img") Oktette"
exit 0
