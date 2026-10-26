#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:?image build directory}
PROG=${2:-taskbar}
DST=${3:-$OUT/$PROG.sym.elf}
STUFE=${STUFE:-0}
ld --gc-sections -T kernel/user/user.ld --defsym=USER_ENTRY="_F$STUFE.u_start" -o "$DST" "$OUT/$PROG.o" || exit 1
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
objcopy -O binary -j .text "$DST" "$T/a.bin"
objcopy -O binary -j .text "$OUT/$PROG.elf" "$T/b.bin"
cmp -s "$T/a.bin" "$T/b.bin" && echo "ok: $DST matches $OUT/$PROG.elf" || { echo "FAIL: .text differs from $OUT/$PROG.elf"; exit 1; }
