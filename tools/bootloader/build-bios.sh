#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:?usage: build-bios.sh <outdir>}
mkdir -p "$OUT"
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
[ -x vendor/firn/bin/firnc ] || bash vendor/firn/fetch-firnc.sh >/dev/null
mkdir "$W/src"
cp boot/common/* boot/bios/* "$W/src/"
FIRNLIB=$PWD/lib vendor/firn/bin/firnc -c "$W/src/main.fi" -o "$W/main.o" --profile=kernel
as --64 -I "$W/src" -o "$W/entry.o" "$W/src/entry.s"
as --64 -o "$W/stage0.o" "$W/src/stage0.s"
ld -m elf_x86_64 -Ttext 0x7C00 --oformat binary -e stage0_start -o "$W/stage0.bin" "$W/stage0.o"
ld -m elf_x86_64 -T "$W/src/link.ld" -o "$W/stage2.bin" "$W/entry.o" "$W/main.o"
[ "$(stat -c %s "$W/stage0.bin")" -eq 440 ] || { echo "stage0 size $(stat -c %s "$W/stage0.bin") != 440" >&2; exit 1; }
cp "$W/stage0.bin" "$OUT/osboot-stage0.bin"
cp "$W/stage2.bin" "$OUT/osboot-stage2.bin"
echo "osboot bios: stage0 440 bytes, stage2 $(stat -c %s "$OUT/osboot-stage2.bin") bytes"
