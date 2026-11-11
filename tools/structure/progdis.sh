#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
cd "$(dirname "$0")/../.."
src=$1
out=$2
export FIRNLIB="$PWD/lib"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
name=$(basename "$src" .fi)
. tools/lib/firnenv.sh
"$FIRNC" -c "$src" -o "$tmp/p.o"
ld -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start -o "$tmp/p.elf" "$tmp/p.o"
objdump -d -M intel --no-show-raw-insn "$tmp/p.elf" > "$out"
