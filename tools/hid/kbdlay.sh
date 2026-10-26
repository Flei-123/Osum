#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/hid/kbdlay.sh -- keyboard layout data (host check, seconds).
#   1. kbdnames.fi, kbdlay.fi, kbdcomb.fi are exactly what tools/hid/kbdgen.py generates from the xkb data
#   2. known keys of the layouts, read back through the kernel modules (tools/keymap/host.fi)
#   3. counter-proof: damaged data is detected
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
T=$(mktemp -d); trap 'cp "$T/kbdlay.keep" kernel/drv/hid/kbdlay.fi 2>/dev/null; rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
python3 -I tools/hid/kbdgen.py --check && ok "generated data is up to date with the xkb data" || bad "generated data is stale (run tools/hid/kbdgen.py)"
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
mkdir -p "$T/lib"
ln -s "$ROOT/kernel/drv" "$T/lib/drv"
ln -s "$ROOT/lib/keymap" "$T/lib/keymap"
FIRNLIB="$T/lib" vendor/firn/bin/firnc --profile=app tools/keymap/host.fi -o "$T/host" > "$T/host.build" 2>&1 && "$T/host" > "$T/dump.txt" \
    && ok "host build and dump" || { bad "host build"; grep -v '^warning' "$T/host.build" | head; }
python3 -I - "$T/dump.txt" <<'PY' && ok "known keys of the layouts" || bad "known keys"
import os, sys
sys.path.insert(0, "tools/hid")
import kbdgen
names = [n for n, _x, _v in kbdgen.LAYOUTS]
table = {}
for line in open(sys.argv[1]):
    p = line.split()
    if p and p[0] == "L":
        lay, code, level, entry, ch = map(int, p[1:6])
        table[(names[lay], code, level)] = ch
want = [
    ("us", 0x10, 0, "q"), ("us", 0x10, 1, "Q"), ("us", 0x39, 0, " "), ("us", 0x29, 1, "~"),
    ("de", 0x15, 0, "z"), ("de", 0x2C, 0, "y"), ("de", 0x10, 2, "@"), ("de", 0x12, 2, "€"), ("de", 0x0C, 0, "ß"),
    ("de", 0x1A, 0, "ü"), ("de", 0x27, 1, "Ö"), ("de", 0x08, 2, "{"), ("de", 0x56, 2, "|"), ("de", 0x0C, 4, "ẞ"),
    ("fr", 0x10, 0, "a"), ("fr", 0x11, 0, "z"), ("fr", 0x1E, 0, "q"), ("fr", 0x27, 0, "m"), ("fr", 0x03, 0, "é"),
    ("fr", 0x56, 0, "<"), ("fr", 0x03, 2, "~"),
    ("uk", 0x03, 1, '"'), ("uk", 0x04, 1, "£"), ("uk", 0x2B, 0, "#"), ("uk", 0x28, 1, "@"),
    ("es", 0x27, 0, "ñ"), ("es", 0x03, 2, "@"), ("es", 0x12, 2, "€"),
    ("it", 0x28, 0, "à"), ("it", 0x1A, 0, "è"), ("it", 0x27, 0, "ò"),
    ("ru", 0x10, 0, "й"), ("ru", 0x11, 0, "ц"), ("ru", 0x10, 1, "Й"), ("ru", 0x1E, 0, "ф"),
    ("de-at", 0x10, 2, "@"), ("ch-de", 0x15, 0, "z"), ("ch-de", 0x1A, 0, "ü"), ("ch-fr", 0x1A, 0, "è"),
    ("pt-br", 0x73, 0, "/"), ("pt-br", 0x73, 1, "?"), ("pl", 0x1E, 2, "ą"), ("tr", 0x17, 0, "ı"), ("tr", 0x28, 1, "İ"),
    ("nl", 0x03, 1, '"'), ("se", 0x28, 0, "ä"), ("us-intl", 0x12, 2, "é"), ("pt", 0x1A, 0, "+"),
]
bad = 0
for name, code, level, want_ch in want:
    got = table.get((name, code, level))
    if got != ord(want_ch):
        print("    %s 0x%02X level %d: got %s want %r" % (name, code, level, got, want_ch)); bad += 1
sys.exit(1 if bad else 0)
PY
cp kernel/drv/hid/kbdlay.fi "$T/kbdlay.keep"
python3 -I - <<'PY'
import re
p = "kernel/drv/hid/kbdlay.fi"
s = open(p).read()
i = s.index("static mut SYMS")
m = re.compile(r"\d+").search(s, s.index("\n", i))
open(p, "w").write(s[:m.start()] + str(int(m.group()) + 7) + s[m.end():])
PY
python3 -I tools/hid/kbdgen.py --check && bad "COUNTER-PROOF: damaged table not detected" || ok "COUNTER-PROOF: a damaged table is detected"
cp "$T/kbdlay.keep" kernel/drv/hid/kbdlay.fi
python3 -I tools/hid/kbdgen.py --check && ok "table restored" || bad "table not restored"
echo "kbdlay: $pass/$fail OK/FAIL"
[ "$fail" = 0 ]
