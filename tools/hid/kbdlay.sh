#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/hid/kbdlay.sh -- keyboard layouts UK/FR/ES/IT/RU (host check, seconds).
#   1. kernel/drv/hid/kbdlay.fi is exactly what tools/hid/kbdgen.py generates from xkb
#   2. known keys of every layout, read back out of the generated Firn source
#   3. counter-proof: a damaged table is detected
set -uo pipefail
cd "$(dirname "$0")/../.."
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
python3 -I tools/hid/kbdgen.py --check && ok "kbdlay.fi is up to date with the xkb data" || bad "kbdlay.fi is stale (run tools/hid/kbdgen.py)"
python3 -I - <<'PY' && ok "known keys of all five layouts" || bad "known keys"
import re, sys
s = open("kernel/drv/hid/kbdlay.fi").read()
def fn(name):
    m = re.search(r"fn %s\(code: u64\) -> u64 \{(.*?)\n\}" % name, s, re.S)
    return {int(a, 16): int(b, 16) for a, b in re.findall(r"code == 0x([0-9A-F]+) \{\s*return 0x([0-9A-F]+)", m.group(1))}
want = [
  ("fr_plain", 0x10, "a"), ("fr_plain", 0x11, "z"), ("fr_plain", 0x1E, "q"), ("fr_plain", 0x32, "m" if False else ","),
  ("fr_plain", 0x27, "m"), ("fr_plain", 0x03, "é"), ("fr_plain", 0x56, "<"), ("fr_altgr", 0x03, "~"),
  ("fr_shift", 0x02, None),
  ("uk_shift", 0x03, '"'), ("uk_shift", 0x04, "£"), ("uk_plain", 0x2B, "#"), ("uk_shift", 0x28, "@"),
  ("es_plain", 0x27, "ñ"), ("es_altgr", 0x03, "@"), ("es_altgr", 0x12, "€"),
  ("it_plain", 0x28, "à"), ("it_plain", 0x1A, "è"), ("it_plain", 0x27, "ò"),
  ("ru_plain", 0x10, "й"), ("ru_plain", 0x11, "ц"), ("ru_shift", 0x10, "Й"), ("ru_plain", 0x1E, "ф"),
]
bad = 0
for name, sc, ch in want:
    if ch is None:
        continue
    got = fn(name).get(sc)
    if got != ord(ch):
        print("    %s 0x%02X: got %s want %r" % (name, sc, got, ch)); bad += 1
sys.exit(1 if bad else 0)
PY
cp kernel/drv/hid/kbdlay.fi /tmp/kbdlay-check.$$ 2>/dev/null
sed -i 's/return 0x00E9/return 0x0065/' kernel/drv/hid/kbdlay.fi
python3 -I tools/hid/kbdgen.py --check && bad "COUNTER-PROOF: damaged table not detected" || ok "COUNTER-PROOF: a damaged table is detected"
cp /tmp/kbdlay-check.$$ kernel/drv/hid/kbdlay.fi; rm -f /tmp/kbdlay-check.$$
python3 -I tools/hid/kbdgen.py --check && ok "table restored" || bad "table not restored"
echo "kbdlay: $pass/$fail OK/FAIL"
[ "$fail" = 0 ]
