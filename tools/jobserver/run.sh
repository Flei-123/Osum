#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT_DIR=${JOBSERVER_ROOT:-/root/fxhp/lm}
SPEC=${SPEC:-$ROOT_DIR/run/spec.txt}
OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT
export SMP=${SMP:-1} SPEC BLOCKS=2400000 INODES=20000 TMO=${TMO:-200} DONE=FX-END DRIVE=ahci KARGS="osum vfs nokbd nosched noproc nofs"
bash tools/linuxapps/run.sh "$ROOT_DIR" tools/jobserver/guest.sh "$OUT/out" > "$OUT/run.log" 2>&1
fail=0
for name in make_j1 make_j2_pipe make_j4 make_j2_fifo; do
    line=$(grep -a "^AT $name " "$OUT/out/ser.clean" | head -1)
    if [ -z "$line" ] || ! echo "$line" | grep -q "rc=0"; then echo "FAIL $name: ${line:-missing}"; fail=$((fail + 1)); else echo "OK   $name: $line"; fi
done
echo "jobserver: $fail failed"
[ "$fail" = 0 ]
