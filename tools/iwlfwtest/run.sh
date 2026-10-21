#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/iwlfwtest/run.sh -- gate for the kernel firmware stage of the Intel WLAN driver (r1502).
#
#   bash tools/iwlfwtest/run.sh
#
# MEASURES (QEMU, no Intel WLAN device; kernel word `iwlfwtest` fakes an AX201 identity):
#   * the candidate file /lib/firmware/intel/iwlwifi/iwlwifi-QuZ-a0-hr-b0-77.ucode is read through the VFS
#   * `iwl: fw file=<path> size=<n>` carries the real file size
#   * `iwl: fw rc= ver= lmac= umac= paging=` equals the independent Python parse (tools/wlan/iwlfw_ref.py)
# CONTROL RUNS:
#   * file missing -> `iwl: fw no file`, no file/rc line
#   * corrupt blob (bad_magic) -> negative rc, no lmac/umac line
#   * without the word -> no `iwl: fw` line at all (no device, nothing to look up)
set -uo pipefail
cd "$(dirname "$0")/../.."
HERE="$PWD"
export FIRNLIB="$HERE/lib"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' present" || ok "$3"; }
command -v qemu-system-x86_64 >/dev/null || { echo "IWLFWTEST: skipped, no qemu"; exit 0; }
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1

mkdir -p "$T/blobs" "$T/bin"
python3 -I tools/wlan/iwlfw_ref.py gen "$T/blobs"
GOOD="$T/blobs/good.bin"
SIZE=$(stat -c %s "$GOOD")
EXP=$(python3 -I - "$GOOD" <<'PY'
import subprocess, sys
out = subprocess.run([sys.executable, '-I', 'tools/wlan/iwlfw_ref.py', 'parse', sys.argv[1]], capture_output=True, text=True).stdout.split('\n')
ver = [l for l in out if l.startswith('SUM')][0].split('ver=')[1].split()[0]
cnt = {0: 0, 1: 0, 2: 0}
for l in out:
    p = l.split()
    if p and p[0] == 'SEC' and p[1] == '0':
        cnt[int(p[3].split('=')[1])] += 1
print('ver=%s lmac=%d umac=%d paging=%d' % (ver, cnt[0], cnt[1], cnt[2]))
PY
)
echo "expected from Python: size=$SIZE $EXP"

bash tools/sync/build.sh "$T/bin" 0 sh echo > "$T/b.txt" 2>&1 \
    && ok "programs build" || { bad "programs build"; tail "$T/b.txt"; echo "IWLFWTEST: $pass ok, $fail fail"; exit 1; }
./tools/build-kernel.sh "$T/k.img" --stufe 0 > "$T/k.txt" 2>&1 \
    && ok "kernel builds" || { bad "kernel build"; tail -30 "$T/k.txt"; echo "IWLFWTEST: $pass ok, $fail fail"; exit 1; }
printf 'echo ==START==\necho ==END==\n' > "$T/s.sh"

image() { # name [blob]
    local n=$1 blob=${2:-}
    local extra=()
    [ -n "$blob" ] && extra=("/lib/firmware/intel/iwlwifi/iwlwifi-QuZ-a0-hr-b0-77.ucode=$blob")
    python3 tools/osum/mkfs.py build "$T/$n.img" 20000 --v3 /bin/ /t/ /etc/ /lib/ /lib/firmware/ /lib/firmware/intel/ /lib/firmware/intel/iwlwifi/ \
        /bin/sh="$T/bin/sh.elf" /bin/echo="$T/bin/echo.elf" "/t/s.sh=$T/s.sh" "${extra[@]}" > "$T/$n.mkfs" 2>&1 \
        || { tail -3 "$T/$n.mkfs"; return 1; }
}
run() { # name image words
    local n=$1 img=$2 words=$3
    timeout 150 qemu-system-x86_64 -accel "$ACC" -smp 1 -kernel "$T/k.img" -m 512 \
        -append "osum vfs $words script=sh /t/s.sh;exit" \
        -serial "file:$T/$n.txt" -display none -no-reboot \
        -drive "file=$T/$img.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$T/$n.txt" > "$T/$n.klar"
}

image good "$GOOD" || { bad "image good"; exit 1; }
image none || { bad "image none"; exit 1; }
image badm "$T/blobs/bad_magic.bin" || { bad "image badm"; exit 1; }

echo "-- A: synthetic ucode, word iwlfwtest"
run a good iwlfwtest
A="$T/a.klar"
has "$A" 'iwl: fw test' "test stage announced"
has "$A" 'iwl: fw file=/lib/firmware/intel/iwlwifi/iwlwifi-QuZ-a0-hr-b0-77.ucode size='"$SIZE" "file read through the VFS, size == $SIZE"
grep -aE "iwl: fw rc=[0-9]+ $EXP\$" "$A" >/dev/null && ok "parse line == Python reference ($EXP)" || { bad "parse line differs from Python ($EXP)"; grep -a 'iwl: fw' "$A" | head -5; }
hasnot "$A" 'iwl: fw no file' "no 'no file' line when the file exists"
hasnot "$A" 'iwl: boot' "no device write without iwlboot"

echo "-- B: file missing"
run b none iwlfwtest
B="$T/b.klar"
has "$B" 'iwl: fw test' "test stage announced"
has "$B" 'iwl: fw no file' "missing file reported"
hasnot "$B" 'iwl: fw file=' "no file line without a file"

echo "-- C: corrupt blob"
run c badm iwlfwtest
C="$T/c.klar"
has "$C" 'iwl: fw file=' "corrupt file is still found"
grep -aqE 'iwl: fw rc=-[0-9]+' "$C" && ok "parse refuses it (negative rc)" || bad "no negative rc"
hasnot "$C" 'lmac=' "no section summary for a refused blob"

echo "-- D: no word"
run d good ""
hasnot "$T/d.klar" 'iwl: fw' "nothing happens without the word and without a device"

echo "IWLFWTEST: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
