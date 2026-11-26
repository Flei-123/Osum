#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/pidkill.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${OUT:-$(mktemp -d /root/abbilder/instahci.XXXXXX)}
[ -n "${KEEP:-}" ] || trap 'rm -rf "$OUT"' EXIT
mkdir -p "$OUT"
export OUT
export OTA_DRIVE=ahci

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }

run_case() {
    OUT="$OUT" bash tools/install/oneshot.sh "$1" iso "$2" "${3:-600}" > /dev/null 2>&1
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' "$OUT/$1.txt" 2>/dev/null
}

bash tools/install/build.sh "$OUT" > "$OUT/build.log" 2>&1 || {
    echo "AHCIINSTALL: build failed"; tail -20 "$OUT/build.log"; exit 1; }

rm -f "$OUT/ziel.img"
head -c $((256 * 1024 * 1024)) /dev/zero > "$OUT/ziel.img"
cp -f "$OUT/ziel.img" "$OUT/empty.img"

echo "== 1. disk list with the target on an AHCI controller only"
run_case list "install;exit" 300
has "$OUT/list.txt" "/dev/sda  sectors=524288" "install lists /dev/sda with its size"

echo "== 2. dry run changes nothing"
run_case dry "install /dev/sda;exit" 300
has "$OUT/dry.txt" "install: dry run" "dry run reported"
cmp -s "$OUT/ziel.img" "$OUT/empty.img" && ok "disk untouched without --ja" || bad "disk written without --ja"

echo "== 3. install onto /dev/sda"
run_case inst "install /dev/sda --ja;exit" 900
has "$OUT/inst.txt" "install: gpt ok" "GPT written"
has "$OUT/inst.txt" "install: fat32 ok" "FAT32 created"
has "$OUT/inst.txt" "install: done" "install finished"
if command -v sgdisk > /dev/null; then
    sgdisk -v "$OUT/ziel.img" > "$OUT/sgdisk.txt" 2>&1
    grep -q 'No problems found' "$OUT/sgdisk.txt" && ok "sgdisk -v: no problems" || bad "sgdisk -v complains"
fi
mdir -i "$OUT/ziel.img@@1048576" :: > "$OUT/esp.txt" 2>&1
grep -qi 'osum.mb' "$OUT/esp.txt" && ok "kernel is on the EFI partition" || bad "kernel missing on the EFI partition"

echo "AHCIINSTALL: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
