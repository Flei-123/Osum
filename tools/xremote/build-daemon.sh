#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:?usage: build-daemon.sh <out.elf> [source.fi]}
SRC=${2:-kernel/user/xremoted.fi}
export FIRNLIB="$PWD/lib"
. tools/lib/firnenv.sh
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
as --64 -o "$T/crt.o" kernel/user/crt.s
"$FIRNC" "$SRC" -o "$T/xremoted.o"
ld -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start -o "$OUT" "$T/crt.o" "$T/xremoted.o"
strip --strip-all "$OUT"
