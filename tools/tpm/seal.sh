#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
CC="$(pwd)/vendor/firn/bin/firnc"
T=$(mktemp -d)
SWPID=""
cleanup() { [ -n "$SWPID" ] && kill "$SWPID" 2>/dev/null; rm -rf "$T"; rm -f tests/tpm/*.test; }
trap cleanup EXIT
start_sw() {
    mkdir -p "$T/st"
    swtpm socket --tpmstate "dir=$T/st" --server "type=unixio,path=$T/sock" --ctrl "type=unixio,path=$T/ctl" \
        --tpm2 --flags not-need-init,startup-clear --log "file=$T/sw.log" &
    SWPID=$!
    for _ in $(seq 50); do [ -S "$T/sock" ] && break; sleep 0.1; done
}
start_sw
export TPM_SOCK="$T/sock"
"$CC" --test tests/tpm/seal_sw.fi 2>&1 | tail -40
