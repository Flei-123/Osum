#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/cryptinst/run.sh -- K-019 gate: install an ENCRYPTED root, reboot, unlock.
#   1. install /dev/hda --ja --crypt <pw>   (KVM, image from tools/install/build.sh)
#   2. host: the root partition holds the OSUMCRYPT header and the plain marker text is NOT on the disk
#   3. boot (roh) with kryptopw=<pw>   -> "crypt: unlocked"
#   4. boot (roh) with a wrong kryptopw -> "crypt: locked", no unlock
# Run: OUT=$(mktemp -d) bash tools/cryptinst/run.sh   (heavy: use /root/jarvis/bin/heavy)
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${OUT:-$(mktemp -d)}
export OUT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  OK    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }
bash tools/install/build.sh "$OUT" > "$OUT/bauen.log" 2>&1 || { echo "build failed"; tail -5 "$OUT/bauen.log"; exit 1; }
PW=geheim123
bash tools/install/oneshot.sh inst iso "install /dev/hda --ja --crypt $PW;exit" 900 > /dev/null 2>&1
grep -aq "install: encrypted" "$OUT/inst.txt" && ok "installer reports encryption" || bad "installer reports encryption"
grep -aq "install: done" "$OUT/inst.txt" && ok "installation finished" || bad "installation finished"
# host view: header magic somewhere in the root partition, no plaintext OFS magic / known strings
python3 - "$OUT/ziel.img" <<'PY' && ok "host: OSUMCRYPT header present, '/etc/passwd' text absent" || bad "host view of the disk"
import sys
d=open(sys.argv[1],'rb').read()
assert b'OSUMCRYPT' in d
assert b'root:' not in d[70000*512:]
PY
OSUM_EXTRA="kryptopw=$PW" bash tools/install/oneshot.sh up1 roh "exit" 240 > /dev/null 2>&1
grep -aq "crypt: unlocked" "$OUT/up1.txt" && ok "correct passphrase unlocks" || bad "correct passphrase unlocks"
OSUM_EXTRA="kryptopw=falsch" bash tools/install/oneshot.sh up2 roh "exit" 240 > /dev/null 2>&1
grep -aq "crypt: locked" "$OUT/up2.txt" && ok "wrong passphrase rejected" || bad "wrong passphrase rejected"
grep -aq "crypt: unlocked" "$OUT/up2.txt" && bad "wrong passphrase must not unlock" || ok "no unlock with wrong passphrase"
echo "CRYPTINST: $pass ok, $fail fail"
rm -rf "$OUT"
[ "$fail" = 0 ]
