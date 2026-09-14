#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/dynlader/messung-wirt.sh -- RUNDE DYNLADER, SCHRITT 0: MESSEN.
#
# Bevor irgendetwas gebaut wird, wird gezaehlt, was ein dynamisch
# gelinktes musl-Programm auf einem ECHTEN Linux vom Kern verlangt.
# Das Ergebnis steht in docs/RUNDE-DYNLADER.md Abschnitt 1 und ist der
# Grund, aus dem diese Runde KEINE neuen Syscalls baut.
set -u
W=${1:-/tmp/dynlader-messung}
mkdir -p "$W"; cd "$W"
cat > hello.c <<'C'
#include <stdio.h>
int main(void){ printf("hallo dynamisch\n"); return 0; }
C
musl-gcc -O2 -o hello_dyn hello.c || { echo "musl-gcc fehlt"; exit 1; }
echo "== Typ =="
file hello_dyn
echo "== PT_INTERP =="
readelf -lW hello_dyn | grep -A1 INTERP
echo "== Syscalls zwischen execve und Ausgabe =="
strace -o tr.txt ./hello_dyn >/dev/null 2>&1
grep -vE '^\+\+\+|^---' tr.txt
echo "== verschiedene Nummern =="
grep -oE '^[a-z_0-9]+\(' tr.txt | tr -d '(' | sort -u | tr '\n' ' '; echo
