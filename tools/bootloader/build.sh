#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:?usage: build.sh <BOOTX64.EFI> [source-root]}
SRC=${2:-.}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
. tools/lib/firnenv.sh
mkdir "$W/src"
cp "$SRC"/boot/common/* "$SRC"/boot/uefi/* "$W/src/"
FIRNLIB=$PWD/lib "$FIRNC" -c "$W/src/main.fi" -o "$W/main.o" --profile=kernel
as --64 -I "$W/src" -o "$W/entry.o" "$W/src/entry.s"
ld -m i386pep --subsystem 10 -e efi_main --image-base 0x10000000 -s -o "$OUT" "$W/entry.o" "$W/main.o"
echo "osboot: built $OUT ($(stat -c %s "$OUT") bytes)"
