#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/audio/acceptance.sh -- DIE 60-SEKUNDEN-ABNAHME DER RUNDE TON-2.
#
#   bash tools/audio/acceptance.sh [ausgabeverzeichnis]
#
# ZWOELF LAEUFE: -smp 1 und -smp 4, Quelle ide und ram, je DREI Mal.
#
# WARUM DREI UND NICHT EINER. Der Aussetzerzaehler des Treibers
# (`hda.fi`, S_UNDER) wird nur fortgeschrieben, wenn jemand die
# Position abfragt, und schwankte ueber EINE Sekunde bei voellig
# gleichem Code zwischen eins und fuenf. Eine einzelne Zahl ist damit
# Rauschen. Drei Laeufe zeigen, ob eine Null eine Eigenschaft ist oder
# ein Zufall.
#
# WARUM SECHZIG SEKUNDEN. Ein Aussetzer ist selten; ueber eine Sekunde
# gemessen sagt seine Zahl nichts. Sechzig Sekunden gehen in diesem
# Dateisystem nicht als EINE Datei (ein Inode fasst 2134016 Oktette =
# 12,1 s bei 44100 Hz stereo), deshalb spielt `/bin/play -w 6` die
# Zehn-Sekunden-Datei sechsmal an EINEM offenen Strom.
#
# DIE ZAHL, DIE ZAEHLT, IST `gaps` -- echte Nullstrecken in dem, was
# das Geraet ausgegeben hat. Alles andere ist Buchhaltung des Kerns
# ueber sich selbst.
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-/root/ton2-abnahme}
mkdir -p "$OUT"
LAEUFE=${TON_LAEUFE:-3}

printf '%-6s %-4s %-3s %10s %10s %8s %9s %7s %7s\n' \
    smp quelle nr gespielt syscalls schuebe wartete aussetz gaps > "$OUT/tabelle.txt"
for smp in 1 4; do
  for q in ide ram; do
    for i in $(seq 1 "$LAEUFE"); do
      d="$OUT/$smp-$q-$i"
      TON_PLAYOPT="-w 6" TON_KEEP=1 TON_TMPD="$d" \
        timeout 2400 bash tools/audio/mess.sh /lang44.wav "$smp" "$q" \
        > "$OUT/$smp-$q-$i.log" 2>&1
      g() { grep -oaE "$2: *[0-9]+" "$OUT/$smp-$q-$i.log" | tail -1 | grep -oE '[0-9]+$'; }
      gp=$(grep -oaE 'gaps=[0-9]+' "$OUT/$smp-$q-$i.log" | tail -1 | grep -oE '[0-9]+$')
      printf '%-6s %-4s %-3s %10s %10s %8s %9s %7s %7s\n' \
        "$smp" "$q" "$i" "$(g x gespielt)" \
        "$(grep -oaE 'syscalls=[0-9]+' "$OUT/$smp-$q-$i.log" | tail -1 | grep -oE '[0-9]+$')" \
        "$(g x schuebe)" "$(g x wartete)" "$(g x aussetzer)" "${gp:-?}" \
        >> "$OUT/tabelle.txt"
      rm -rf "$d"
    done
  done
done
cat "$OUT/tabelle.txt"
