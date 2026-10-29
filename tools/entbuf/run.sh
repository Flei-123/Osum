#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
out=$(python3 -I tools/entbuf/check.py .)
echo "$out" | tail -3
echo "$out" | grep -q 'ENTBUF: .* 0 failed' && ok "tree is clean" || bad "tree is clean"
mutant() {
    local name=$1 file=$2 from=$3 to=$4
    rm -rf "$D/m"; mkdir -p "$D/m/kernel/fs" "$D/m/kernel/lib" "$D/m/kernel/block" "$D/m/kernel/bus" "$D/m/kernel/diag" "$D/m/kernel/sys"
    for f in kernel/fs/fs.fi kernel/fs/mnt.fi kernel/fs/ofs.fi kernel/lib/kstate.fi kernel/block/part.fi kernel/bus/drvstore.fi kernel/diag/hw.fi kernel/sys/sys.fi kernel/kmain.fi; do cp "$f" "$D/m/$f"; done
    python3 -I - "$D/m/$file" "$from" "$to" <<'PY'
import sys
path, old, new = sys.argv[1:4]
data = open(path, "rb").read()
assert old.encode() in data, old
open(path, "wb").write(data.replace(old.encode(), new.encode()))
PY
    python3 -I tools/entbuf/check.py "$D/m" > "$D/m.txt" 2>&1
    if grep -q 'ENTBUF: .* [1-9][0-9]* failed' "$D/m.txt"; then ok "control rejects: $name"; else bad "control missed: $name"; fi
}
mutant "64 byte drvstore buffer" kernel/bus/drvstore.fi 'static mut ent_buf: [u8; 264]' 'static mut ent_buf: [u8; 64]'
mutant "ofs scratch into sector buffer" kernel/fs/ofs.fi 'SCRATCH_OFF: u64 = 0x980' 'SCRATCH_OFF: u64 = 0xD00'
mutant "ofs scratch onto devfs scratch" kernel/fs/ofs.fi 'SCRATCH_OFF: u64 = 0x980' 'SCRATCH_OFF: u64 = 0x800'
mutant "missing cap argument" kernel/bus/drvstore.fi 'fs.entry_at(state, dir, i, (&ent_buf[0]) as u64, ENT_BYTES)' 'fs.entry_at(state, dir, i, (&ent_buf[0]) as u64)'
mutant "cap below entry size" kernel/bus/drvstore.fi 'const ENT_BYTES: u64 = 264' 'const ENT_BYTES: u64 = 32'
mutant "entry max too small" kernel/fs/fs.fi 'const ENTRY_MAX: u64 = 264' 'const ENTRY_MAX: u64 = 32'
mutant "no runtime guard" kernel/fs/fs.fi 'if dirent_size(state) > cap {' 'if dirent_size(state) > 4096 {'
mutant "name page overflow" kernel/sys/sys.fi 'NB_FSTYPE - NB_ENT)' '1024)'
mutant "mount accepts any entry size" kernel/fs/fs.fi 'dent < DIRENT || dent > ENTRY_MAX ||' 'dent < DIRENT || dent > BS ||'
mutant "mount refusal removed" kernel/fs/fs.fi 'if dent > ENTRY_MAX && dent <= BS {' 'if dent > 99999 && dent <= BS {'
echo "ENTBUF: $pass passed, $fail failed"
[ "$fail" = 0 ]
