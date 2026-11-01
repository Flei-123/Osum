#!/usr/bin/env bash
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
        timeout 2400 bash tools/audio/measure.sh /lang44.wav "$smp" "$q" \
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
