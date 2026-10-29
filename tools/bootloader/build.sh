#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:?usage: build.sh <BOOTX64.EFI>}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
[ -x vendor/firn/bin/firnc ] || bash vendor/firn/fetch-firnc.sh >/dev/null
FIRNLIB=$PWD/lib vendor/firn/bin/firnc -c boot/uefi/main.fi -o "$W/main.o" --profile=kernel
as --64 -o "$W/entry.o" boot/uefi/entry.s
ld -m i386pep --subsystem 10 -e efi_main --image-base 0x10000000 -s -o "$OUT" "$W/entry.o" "$W/main.o"
echo "osboot: built $OUT ($(stat -c %s "$OUT") bytes)"
