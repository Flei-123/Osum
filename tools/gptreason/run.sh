#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
for t in sgdisk python3 qemu-system-x86_64; do
    command -v "$t" >/dev/null 2>&1 || { echo "GPTREASON: $t missing"; exit 1; }
done
OUT=$(mktemp -d); export OUT
trap 'rm -rf "$OUT"' EXIT
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
RUN_LIMIT=${RUN_LIMIT:-600}

echo "== 1. build kernel and dualcli =="
if PROGS="sh ls cat echo sync dualcli" APPS="" ZIEL_MIB=64 bash tools/install/build.sh "$OUT" > "$OUT/build.log" 2>&1 && [ -x "$OUT/bin/dualcli" ]; then
    ok "kernel and dualcli build"
else
    bad "build failed"; tail -15 "$OUT/build.log" | sed 's/^/        /'
    echo "GPTREASON: $pass passed, $fail failed"; exit 1
fi

echo "== 2. foreign disks with one broken GPT field each =="
python3 -I - "$OUT/base.img" <<'PY'
import sys
f = open(sys.argv[1], 'wb'); f.seek(64 * 1048576 - 1); f.write(b'\0'); f.close()
PY
sgdisk -o "$OUT/base.img" >/dev/null 2>&1
sgdisk -n 1:2048:34815 -t 1:EF00 -c 1:"EFI System Partition" "$OUT/base.img" >/dev/null 2>&1
sgdisk -n 2:34816:100000 -t 2:0700 -c 2:"Basic data partition" "$OUT/base.img" >/dev/null 2>&1
sgdisk -v "$OUT/base.img" | grep -q 'No problems found' && ok "base disk has a valid GPT" || bad "base disk GPT"

run_qemu() {
    ZWEITE_PLATTE="$2" bash tools/install/oneshot.sh "$1" iso "dualcli /dev/hdb;exit" "$RUN_LIMIT" >/dev/null 2>&1
}
lines() { tr -d '\000' < "$1" 2>/dev/null | grep -a '^dual:' | head -8 | sed 's/^/        /'; }

cp "$OUT/base.img" "$OUT/clean.img"
run_qemu clean "$OUT/clean.img"
lines "$OUT/clean.txt"
grep -aq '^dual: tafel=2' "$OUT/clean.txt" && ok "clean disk: table read, 2 partitions" || bad "clean disk not read"
grep -aq '^dual: gpt ' "$OUT/clean.txt" && bad "clean disk reports a GPT problem" || ok "clean disk: no GPT problem reported"

for c in hsize hcrc esize count tcrc; do
    cp "$OUT/base.img" "$OUT/$c.img"
    want=$(python3 -I tools/gptreason/mkcase.py "$OUT/$c.img" "$c")
    sum=$(sha256sum < "$OUT/$c.img" | cut -d' ' -f1)
    run_qemu "$c" "$OUT/$c.img"
    lines "$OUT/$c.txt"
    if tr -d '\000' < "$OUT/$c.txt" | grep -aqxF "$want"; then ok "$c: exact reason and values: $want"; else bad "$c: expected '$want'"; fi
    if grep -aq 'dual: gpt kaputt' "$OUT/$c.txt"; then bad "$c: generic message still used"; else ok "$c: no generic message"; fi
    [ "$(sha256sum < "$OUT/$c.img" | cut -d' ' -f1)" = "$sum" ] && ok "$c: disk byte-identical after the probe" || bad "$c: disk changed"
done

echo "== 3. counter-proofs for the oracle =="
cp "$OUT/base.img" "$OUT/probe.img"
other=$(python3 -I tools/gptreason/mkcase.py "$OUT/probe.img" hcrc | head -1)
if tr -d '\000' < "$OUT/tcrc.txt" | grep -aqxF "$other"; then bad "tcrc run matches the hcrc line"; else ok "different fields give different lines"; fi
if tr -d '\000' < "$OUT/hcrc.txt" | grep -aqxF 'dual: gpt header crc bad got=1 want=2'; then bad "oracle accepts a wrong value"; else ok "wrong expected values are rejected"; fi

echo "GPTREASON: $pass passed, $fail failed"
[ "$fail" = 0 ]
