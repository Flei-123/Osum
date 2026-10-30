#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/ahcilock/run.sh -- r2373: block I/O outside the fs lock must not mix AHCI commands.
#
#   bash tools/ahcilock/run.sh [<kib>]
#
# Guest on an ICH9 AHCI disk, four cores: `wrace` writes 4 files while the
# kernel word `ahcirace` makes cpu 1 save and read the hang slot from its timer
# interrupt (the freeze-logger path, no fs lock) every 30 ms.
# Checks: guest and host read every octet back, /proc/fsaudit finds no inode
# with a block pointer below data_start, the guard logged the unlocked I/O.
# Counter-proof: `noblkguard noahcilock` (old behaviour) must show damage.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
KIB=${1:-1024}
PROCS=4
OUT=${AHCILOCK_DIR:-$(mktemp -d)}
mkdir -p "$OUT"
[ -n "${AHCILOCK_KEEP:-}" ] || trap 'rm -rf "$OUT"' EXIT
export OUT
export OSUM_CPU=${OSUM_CPU:-Haswell}
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

for t in qemu-system-x86_64 python3; do
    command -v "$t" >/dev/null 2>&1 || { echo "AHCILOCK: skipped, $t missing"; exit 0; }
done

echo "== 1. build =="
bash vendor/firn/fetch-firnc.sh > "$OUT/firnc.log" 2>&1
if [ -n "${AHCILOCK_BUILT:-}" ] && [ -s "$AHCILOCK_BUILT/quelle.img" ]; then
    cp -f "$AHCILOCK_BUILT/quelle.img" "$AHCILOCK_BUILT/k.mb" "$OUT/"
    ok "reused build $AHCILOCK_BUILT"
elif bash tools/install/build.sh "$OUT" > "$OUT/build.log" 2>&1; then
    ok "image built"
else
    bad "tools/install/build.sh"; tail -20 "$OUT/build.log"
    echo "AHCILOCK: $pass passed, $fail failed"; exit 1
fi

guest() {
    cp -f "$OUT/quelle.img" "$OUT/ziel.img"
    OSUM_SMP=4 OTA_DRIVE=ahci OSUM_EXTRA="r3alle ahcirace $2" OUT="$OUT" \
        bash tools/install/oneshot.sh "$1" roh \
        "wrace run /w1 $PROCS $KIB;cat /proc/fsaudit;exit" 1200 > /dev/null 2>&1
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' -e 's/\r//g' "$OUT/$1.txt" 2>/dev/null
    cp -f "$OUT/ziel.img" "$OUT/$1.img"
}

host_check() {
    python3 tools/ahcilock/check.py "$OUT/$1.img" /w1 "$PROCS" "$KIB" > "$OUT/$1.host" 2>&1
}

echo "== 2. guarded run: wrace x $KIB KiB with the hang slot racing on cpu 1 =="
guest g ""
L="$OUT/g.txt"
saves=$(grep -ao 'blkrace: saves [0-9]* [0-9]*' "$L" | tail -1 | awk '{print $3}')
[ "${saves:-0}" -gt 0 ] && ok "the racer ran ($(grep -ao 'blkrace: saves [0-9]* [0-9]*' "$L" | tail -1))" \
    || bad "the racer never ran (no blkrace line)"
grep -aq "blk: io without fs lock" "$L" && ok "the guard saw the unlocked I/O" \
    || bad "no 'blk: io without fs lock' line"
grep -aq "wrace: ok files=$PROCS" "$L" && ok "guest reads every octet back" \
    || bad "guest: $(grep -a 'wrace:' "$L" | head -2 | tr '\n' '|')"
host_check g && ok "host reads every file and the inode table is sane ($(tail -1 "$OUT/g.host"))" \
    || bad "host: $(tr '\n' '|' < "$OUT/g.host" | head -c 300)"
grep -aq "^scan_bad 0" "$L" && ok "/proc/fsaudit: no bad inode in the first stage" \
    || bad "/proc/fsaudit: $(grep -a '^scan_bad\|^bad ' "$L" | head -3 | tr '\n' '|')"
grep -aq "^data_start [0-9]" "$L" && ok "/proc/fsaudit prints the geometry" || bad "/proc/fsaudit has no geometry"

echo "== 3. counter-proof: noblkguard noahcilock =="
guest n "noblkguard noahcilock"
L="$OUT/n.txt"
dmg=""
grep -aq "wrace: ok files=$PROCS" "$L" || dmg="$dmg guest"
host_check n || dmg="$dmg host"
grep -aq "^scan_bad 0" "$L" || dmg="$dmg fsaudit"
grep -aq "blk: io without fs lock" "$L" && bad "counter-proof still guarded" || true
if [ -n "$dmg" ]; then
    ok "without the locks the race damages data:$dmg"
else
    bad "counter-proof shows no damage (the race is not reproduced)"
fi

echo
echo "  AHCILOCK: $pass passed, $fail failed"
[ "$fail" = 0 ]
