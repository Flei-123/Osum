#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tests/theme/image.sh -- EIN Plattenabbild mit EINER Themen-Einstellung.
#
#   bash tests/theme/image.sh <bauverzeichnis> <schema> <modus> <akzent> <ziel.img>
#
# `tests/theme/build.sh` baut Kernel und Programme; dieses Skript packt
# sie noch einmal auf eine Platte, aber mit einem anderen
# /etc/theme.conf. Der Grund, warum es getrennt ist: die Programme
# bauen dauert, das Abbild packen nicht -- und fuer die Bildschirmfotos
# dieser Runde werden fuenf Abbilder gebraucht, die sich in genau drei
# Zeilen unterscheiden.
#
# <akzent> darf leer sein; dann gilt die Akzentfarbe des Schemas.
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=$1
SCHEME=$2
MODE=$3
ACCENT=${4:-}
IMG=$5

PROGS=$(cat "$OUT/progs.txt" 2>/dev/null)
[ -n "$PROGS" ] || { echo "image.sh: $OUT/progs.txt fehlt -- erst build.sh"; exit 1; }

cat > "$OUT/theme.conf" <<EOF
# /etc/theme.conf -- welches Schema, welcher Modus, welche Akzentfarbe.
scheme=$SCHEME
mode=$MODE
accent=$ACCENT
light_start=07:00
dark_start=19:00
EOF

# 8192 blocks (4 MiB) held these programs with 4 per cent to spare
# after round LOOK. That is not spare room, that is a countdown.
#
# RUNDE KLEINKRAM (14.09.2026): 16384 -> 32768 Bloecke (8 -> 16 MiB).
# DIESELBE Zeile wie in tests/theme/build.sh, und sie ist bei der
# Runde BAUFEHLER dort nachgezogen worden und HIER NICHT. Folge: die
# zehn Programme bauen, das Abbild von build.sh entsteht -- aber jedes
# der sieben Foto-Abbilder dieses Skripts scheitert mit "mkfs: the
# disk is full", und Abschnitt 9 meldet siebenmal "das Abbild liess
# sich nicht bauen" plus sechsmal "<farbe> steht NICHT im Bild".
# GEMESSEN: die .elf-Dateien dieses Laeufers wiegen zusammen 15108360
# Oktette, 16384 Bloecke zu 512 Oktetten fassen 8388608.
# EIN BLOCK IST 512 OKTETTE (tools/osum/mkfs.py, `BS = 512`).
ARGS=(build "$IMG" 32768 /lib/
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
# RUNDE GLYPHE: `nur=` -- siehe tests/theme/build.sh.
while read -r zeile; do ARGS+=("$zeile"); done \
    < <(python3 tools/k15/bundle.py "$OUT/apps" "$OUT/buendel" "nur=$PROGS")
while read -r pfad; do ARGS+=("$pfad"); done < "$OUT/baum/liste"
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$OUT/mkfs-$SCHEME-$MODE.log" 2>&1 || {
    echo "== mkfs.py fehlgeschlagen"; tail -20 "$OUT/mkfs-$SCHEME-$MODE.log"
    exit 1; }
echo "   $IMG  scheme=$SCHEME mode=$MODE accent=${ACCENT:-<schema>}"
exit 0
