#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
. tools/lib/qemu.sh

BASE_REF=${BASE_REF:-9df701771}
RUN_LIMIT=${RUN_LIMIT:-600}
MKDISK="tools/standbylayout/mkdisk.py"
pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

for t in sgdisk python3 qemu-system-x86_64; do
    command -v "$t" >/dev/null 2>&1 || { echo "STANDBYLAYOUT: $t missing"; exit 1; }
done
OUT=$(mktemp -d "${TMPDIR:-/tmp}/standbylayout.XXXXXX")
export OUT
trap 'rm -rf "$OUT"' EXIT
. tools/lib/firnenv.sh

sha() { sha256sum < "$1" | cut -d' ' -f1; }
text() { tr -d '\000' < "$1" 2>/dev/null; }

cli_run() {
    ZWEITE_PLATTE="$2" bash tools/install/oneshot.sh "$1" iso "dualcli /dev/hdb $3;exit" "$RUN_LIMIT" >/dev/null 2>&1
}

kernel_run() {
    local name=$1 kernel=$2 image=$3
    timeout 300 $QEMU_X86 -kernel "$kernel" -m 512 -append "osum suspmess acpiev" \
        -serial "file:$OUT/$name.txt" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        -drive "file=$image,format=raw,if=ide,index=0" >/dev/null 2>&1
}

echo "== 1. build kernel and dualcli =="
if PROGS="sh ls cat echo sync dualcli" APPS="" ZIEL_MIB=64 bash tools/install/build.sh "$OUT" > "$OUT/build.log" 2>&1 && [ -x "$OUT/bin/dualcli" ]; then
    ok "kernel and dualcli build"
else
    bad "build failed"; tail -15 "$OUT/build.log" | sed 's/^/        /'
    echo "STANDBYLAYOUT: $pass passed, $fail failed"; exit 1
fi
if bash tools/build-kernel.sh "$OUT/k.elf" > "$OUT/kbuild.log" 2>&1; then
    ok "direct-boot kernel builds"
else
    bad "direct-boot kernel build failed"; tail -10 "$OUT/kbuild.log" | sed 's/^/        /'
    echo "STANDBYLAYOUT: $pass passed, $fail failed"; exit 1
fi

echo "== 2. disks: new layout and three old layouts =="
for c in new oldfit oldfull foreign; do
    python3 -I "$MKDISK" make "$OUT/$c.img" "$c" >/dev/null
    sgdisk -v "$OUT/$c.img" 2>&1 | grep -q 'No problems found' && ok "$c: valid GPT" || bad "$c: GPT not valid"
done
[ "$(python3 -I "$MKDISK" state "$OUT/new.img")" = ok ] && ok "oracle: new layout is ok" || bad "oracle: new layout"
[ "$(python3 -I "$MKDISK" state "$OUT/oldfit.img")" = trimmable ] && ok "oracle: old layout with small filesystem is trimmable" || bad "oracle: oldfit"
[ "$(python3 -I "$MKDISK" state "$OUT/oldfull.img")" = overlap ] && ok "oracle: old layout with full filesystem overlaps" || bad "oracle: oldfull"

echo "== 3. dualcli --standby: detect, dry run leaves the disk alone =="
for c in new oldfit oldfull foreign; do
    before=$(sha "$OUT/$c.img")
    cli_run "d_$c" "$OUT/$c.img" "--standby"
    text "$OUT/d_$c.txt" | grep -a '^dual: standby' | sed 's/^/        /'
    [ "$(sha "$OUT/$c.img")" = "$before" ] && ok "$c: dry run leaves the disk byte-identical" || bad "$c: dry run changed the disk"
done
want() { echo "dual: standby part 2 state=$1 end=$2 limit=126942"; }
for c in new oldfit oldfull; do
    state=$(python3 -I "$MKDISK" state "$OUT/$c.img")
    end=$(python3 -I "$MKDISK" end "$OUT/$c.img")
    text "$OUT/d_$c.txt" | grep -aqxF "$(want "$state" "$end")" && ok "$c: reports state=$state end=$end" || bad "$c: expected '$(want "$state" "$end")'"
done
text "$OUT/d_foreign.txt" | grep -aq '^dual: standby part' && bad "foreign partition is reported" || ok "foreign partition is not touched or reported"

echo "== 4. dualcli --standby --yes: migrate only where safe =="
sb_before=$(dd if="$OUT/oldfit.img" bs=512 skip=34816 count=1 2>/dev/null | sha256sum | cut -d' ' -f1)
cp "$OUT/oldfit.img" "$OUT/noname.img"
before=$(sha "$OUT/noname.img")
cli_run m_noname "$OUT/noname.img" "--standby --yes"
[ "$(sha "$OUT/noname.img")" = "$before" ] && ok "oldfit without --name: refused, disk byte-identical" || bad "oldfit without --name: disk changed"
cli_run m_oldfit "$OUT/oldfit.img" "--standby --yes --name hdb"
text "$OUT/m_oldfit.txt" | grep -a '^dual: standby' | sed 's/^/        /'
text "$OUT/m_oldfit.txt" | grep -aqx 'dual: standby trimmed 2' && ok "oldfit: trimmed" || bad "oldfit: no trim line"
[ "$(python3 -I "$MKDISK" end "$OUT/oldfit.img")" = 126942 ] && ok "oldfit: GPT entry now ends at the last data block" || bad "oldfit: entry end wrong"
sgdisk -v "$OUT/oldfit.img" 2>&1 | grep -q 'No problems found' && ok "oldfit: primary and backup GPT consistent, CRCs valid" || bad "oldfit: GPT damaged"
sb_after=$(dd if="$OUT/oldfit.img" bs=512 skip=34816 count=1 2>/dev/null | sha256sum | cut -d' ' -f1)
[ "$sb_before" = "$sb_after" ] && ok "oldfit: filesystem superblock untouched" || bad "oldfit: superblock changed"
cli_run m_oldfit2 "$OUT/oldfit.img" "--standby"
text "$OUT/m_oldfit2.txt" | grep -aqxF "$(want ok 126942)" && ok "oldfit: second run reports ok" || bad "oldfit: second run not ok"

before=$(sha "$OUT/oldfull.img")
cli_run m_oldfull "$OUT/oldfull.img" "--standby --yes --name hdb"
text "$OUT/m_oldfull.txt" | grep -a '^dual: standby' | sed 's/^/        /'
[ "$(sha "$OUT/oldfull.img")" = "$before" ] && ok "oldfull: refused, disk byte-identical" || bad "oldfull: disk changed although the filesystem reaches the reserve"
text "$OUT/m_oldfull.txt" | grep -aq 'dual: standby trimmed' && bad "oldfull: claims a trim" || ok "oldfull: no trim claimed"

before=$(sha "$OUT/foreign.img")
cli_run m_foreign "$OUT/foreign.img" "--standby --yes --name hdb"
[ "$(sha "$OUT/foreign.img")" = "$before" ] && ok "foreign: not modified" || bad "foreign: modified"

echo "== 5. kernel: standby refuses a disk whose partitions reach the image area =="
python3 -I "$MKDISK" make "$OUT/kold.img" oldfull >/dev/null
python3 -I "$MKDISK" make "$OUT/knew.img" new >/dev/null
kernel_run k_old "$OUT/k.elf" "$OUT/kold.img"
kernel_run k_new "$OUT/k.elf" "$OUT/knew.img"
grep -a 'why=' "$OUT/k_old.txt" | head -2 | sed 's/^/        /'
grep -aq 'why=old disk layout' "$OUT/k_old.txt" && ok "old layout: kernel reports why=old disk layout" || bad "old layout: kernel does not refuse"
grep -aq 'why=old disk layout' "$OUT/k_new.txt" && bad "new layout: kernel refuses" || ok "new layout: kernel does not refuse"
grep -aq 'why=ok' "$OUT/k_new.txt" && ok "new layout: why=ok" || bad "new layout: why not ok"

echo "== 6. counter-proof: build before the change =="
OLD="$OUT/old"
mkdir -p "$OLD"
git archive "$BASE_REF" | tar -x -C "$OLD"
if (cd "$OLD" && firnenv_prepare_old_tree . >/dev/null 2>&1; bash tools/build-kernel.sh "$OUT/k_base.elf" > "$OUT/base_build.log" 2>&1); then
    kernel_run k_base "$OUT/k_base.elf" "$OUT/kold.img"
    grep -a 'why=' "$OUT/k_base.txt" | head -2 | sed 's/^/        /'
    grep -aq 'why=old disk layout' "$OUT/k_base.txt" && bad "old build also refuses: gate cannot tell" || ok "old build does not refuse the old layout: gate sees the difference"
else
    bad "old build failed"; tail -5 "$OUT/base_build.log" | sed 's/^/        /'
fi

echo "STANDBYLAYOUT: $pass passed, $fail failed"
[ "$fail" = 0 ]
