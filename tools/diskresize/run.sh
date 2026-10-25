#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
FIRNC=$(pwd)/vendor/firn/bin/firnc
for t in sgdisk sfdisk python3; do command -v $t >/dev/null || { echo "DISKRESIZE: $t missing"; exit 1; }; done

fuzz() {
    local lib=$1 out=$2
    mkdir -p "$out/g" "$out/m"
    FIRNLIB=$lib "$FIRNC" -o "$out/gptfuzz" tools/diskresize/gptfuzz.fi > "$out/cg.log" 2>&1 || return 1
    FIRNLIB=$lib "$FIRNC" -o "$out/mbrfuzz" tools/diskresize/mbrfuzz.fi > "$out/cm.log" 2>&1 || return 1
    ( cd "$out/g" && "$out/gptfuzz" > out.txt 2>&1 ) && ( cd "$out/m" && "$out/mbrfuzz" > out.txt 2>&1 )
}

echo "== 1. gptw.repair/resize and mbrw.resize: crash fuzz + refusals against sgdisk / sfdisk =="
if fuzz "$(pwd)/lib" "$D/real"; then
    python3 -I tools/diskresize/check.py "$D/real/g" "$D/real/m" > "$D/check.txt" 2>&1; rc=$?
    grep -a FAIL "$D/check.txt" | head -8
    [ "$rc" -eq 0 ] && ok "$(tail -1 "$D/check.txt")" || bad "$(tail -1 "$D/check.txt")"
else
    bad "the fuzz programs do not build or run"; head -10 "$D/real/cg.log" "$D/real/cm.log" 2>/dev/null
    echo "DISKRESIZE: $pass passed, $fail failed"; exit 1
fi

echo "== 2. mutations of the library must turn the check red =="
mutate() {
    local name=$1 file=$2 from=$3 to=$4
    rm -rf "$D/lib-$name"; cp -r lib "$D/lib-$name"
    python3 -I - "$D/lib-$name/$file" "$from" "$to" <<'PY'
import sys
p, a, b = sys.argv[1:4]
s = open(p).read()
if a not in s:
    sys.exit(3)
open(p, "w").write(s.replace(a, b, 1))
PY
    [ $? -eq 0 ] || { bad "mutation $name: pattern not found"; return; }
    if fuzz "$D/lib-$name" "$D/mut-$name"; then
        python3 -I tools/diskresize/check.py "$D/mut-$name/g" "$D/mut-$name/m" > "$D/mut-$name.txt" 2>&1
        [ $? -ne 0 ] && ok "mutation $name is caught ($(tail -1 "$D/mut-$name.txt"))" || bad "mutation $name was NOT caught"
    else
        ok "mutation $name is caught (the fuzz program crashes)"
    fi
}
mutate wrong-array-lba disks/gptw.fi "mirror_header(hdr, bhdr, 1, total - 1, 2)" "mirror_header(hdr, bhdr, 1, total - 1, 3)"
mutate wrong-backup-alt disks/gptw.fi "mirror_header(bhdr, hdr, total - 1, 1, at)" "mirror_header(bhdr, hdr, total - 1, 2, at)"
mutate primary-wins disks/gptw.fi "if rp == E_OK && bytes.le32(hdr + 88) == bytes.le32(bhdr + 88) && bytes.le32(hdr + 80) == bytes.le32(bhdr + 80) {" "if rp == E_OK {"
mutate no-overlap-check disks/gptw.fi "if i != target && slot_live(e) && start <= bytes.le64(e + 40) && last >= bytes.le64(e + 32) {" "if false {"
mutate no-range-check disks/gptw.fi "if sectors == 0 || start + sectors - 1 > bytes.le64(hdr + 48) {" "if sectors == 0 {"
mutate no-crc-in-side-read disks/gptw.fi "if table.crc32(a, nent * ENT_SIZE) != bytes.le32(h + 88) {" "if false {"
mutate mbr-no-overlap disks/mbrw.fi "if start <= l && last >= s {" "if false {"
mutate mbr-no-ext-guard disks/mbrw.fi "if is_extended(bytes.ld8(t, 4)) {" "if false {"
mutate mbr-no-chs disks/mbrw.fi "    put_chs(t + 5, last)
" ""
echo "DISKRESIZE: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
