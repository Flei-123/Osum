#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/pin/run.sh -- r253 stage 1: the local, device-bound PIN (kernel/user/pin.fi, /bin/pinctl).
#
#   /root/jarvis/bin/heavy bash tools/pin/run.sh
#
# Two guest boots on ONE disk (script mode, KVM). Boot A: set, format rules, right PIN, wrong PIN, 5 wrong tries -> delay (the
# RIGHT PIN is refused during the delay), no plaintext in /etc/pin. Boot B (a fresh boot, same disk): the delay is STILL there
# (counter persisted), the password-login hook (`pwok`) clears it, 10 wrong tries disable the PIN until `pwok`, and without the
# device key the record verifies nothing (device bound).
# COUNTER-PROOFS inside the run: the right PIN is refused while locked (not merely "wrong"), a missing key never verifies.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
export OSUM_RTC="base=2026-10-11T11:00:00,clock=vm"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
B=tools/alltag/build.sh
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1

python3 - "$TMPD" <<'PY'
import sys
d = sys.argv[1]
open(d + "/passwd", "w").write("root:x:0:0:root:/root:/bin/sh\njustin:x:1000:1000:Justin:/users/justin:/bin/sh\n")
PY
PINA=482915
A='pinctl status root;pinctl set root 1234;pinctl set root 1111;pinctl set root 12;pinctl set root 12ab56;pinctl set root '$PINA';pinctl status root;pinctl check root 000999;pinctl check root '$PINA';pinctl check root 000999;pinctl check root 000998;pinctl check root 000997;pinctl check root 000996;pinctl check root 000995;pinctl check root '$PINA';pinctl status root;echo ---FILE;cat /etc/pin;echo ---END;pinctl remove justin;pinctl status justin;exit'
echo "== boot A: set / rules / wrong tries / delay =="
OSUM_ACCEL=kvm bash $B "$TMPD/a" script="$A" progs="pinctl sh echo cat rm ls" passwdfile="$TMPD/passwd" bloecke=16384 keep=yes > "$TMPD/a.log" 2>&1
SA="$TMPD/a/serial.txt"
if [ ! -s "$SA" ]; then bad "boot A: no serial output"; tail -5 "$TMPD/a.log"; echo "PIN: $pass passed, $fail failed"; exit 1; fi
grep -a "^pinctl:" "$SA" | sed 's/^/        /'
line() { grep -a "^pinctl: $1" "$2" | sed -n "${3}p"; }
# order of the lines in boot A
mapfile -t L < <(grep -a "^pinctl:" "$SA")
chk() { # index regex message
    if [[ "${L[$1]:-}" =~ $2 ]]; then ok "$3"; else bad "$3  (got: ${L[$1]:-none})"; fi
}
chk 0 'status rc=3' "no PIN yet: status = none (3)"
chk 1 'set rc=6' "1234 refused (run)"
chk 2 'set rc=6' "1111 refused (same digit)"
chk 3 'set rc=6' "2 digits refused (too short)"
chk 4 'set rc=6' "12ab56 refused (not digits)"
chk 5 'set rc=0' "a good PIN is set"
chk 6 'status rc=0' "status: usable"
chk 7 'check rc=1 fails=1' "wrong PIN: rc=1, counter 1"
chk 8 'check rc=0 fails=0' "right PIN: rc=0, counter back to 0"
chk 9 'check rc=1 fails=1' "wrong again: counter 1"
chk 10 'check rc=1 fails=2' "wrong: counter 2"
chk 11 'check rc=1 fails=3' "wrong: counter 3"
chk 12 'check rc=1 fails=4' "wrong: counter 4"
chk 13 'check rc=1 fails=5' "5th wrong: counter 5 (delay starts)"
chk 14 'check rc=2 fails=5 wait=([1-9][0-9]*)' "COUNTER-PROOF: the RIGHT PIN is refused during the delay (rc=2, wait > 0)"
chk 15 'status rc=2 fails=5 wait=([1-9]|[1-5][0-9]|60)$' "status: locked, wait <= 60 s"
FL=$(awk '/---FILE/{f=1;next}/---END/{f=0}f' "$SA" | grep -a '^root:' | head -1)
if [[ "$FL" =~ ^root:\$osum1\$[0-9]+\$[0-9a-f]+\$[0-9a-f]{64}:5:[0-9]+:[0-9]+ ]]; then ok "/etc/pin line is root:\$osum1\$...:5:until:seen"; else bad "/etc/pin line malformed: $FL"; fi
if [[ "$FL" == *"$PINA"* ]]; then bad "the PIN stands in /etc/pin in clear"; else ok "no plaintext PIN in /etc/pin"; fi
chk 16 'remove rc=0' "remove of a user without PIN is fine"
chk 17 'status rc=3' "other user: no PIN"

B2='pinctl status root;pinctl check root '$PINA';pinctl pwok root;pinctl status root;pinctl check root '$PINA';pinctl force root 9 0;pinctl check root 000111;pinctl status root;pinctl check root '$PINA';pinctl pwok root;pinctl check root '$PINA';rm /device/pinkey;pinctl check root '$PINA';pinctl set root 735190;pinctl check root 735190;pinctl has root;pinctl has justin;pinctl change root 000111 482916;pinctl change root 735190 12;pinctl change root 735190 482916;pinctl check root 735190;pinctl check root 482916;pinctl rmchk root 000111;pinctl rmchk root 482916;pinctl status root;pinctl has root;pinctl change root 000000 590813;pinctl status root;exit'
echo "== boot B: a fresh boot on the same disk =="
cp "$TMPD/a/disk.img" "$TMPD/disk-a.img"
OSUM_ACCEL=kvm bash $B "$TMPD/b" script="$B2" progs="pinctl sh echo cat rm ls" passwdfile="$TMPD/passwd" bloecke=16384 platte="$TMPD/disk-a.img" > "$TMPD/b.log" 2>&1
SB="$TMPD/b/serial.txt"
if [ ! -s "$SB" ]; then bad "boot B: no serial output"; tail -5 "$TMPD/b.log"; echo "PIN: $pass passed, $fail failed"; exit 1; fi
grep -a "^pinctl:" "$SB" | sed 's/^/        /'
mapfile -t L < <(grep -a "^pinctl:" "$SB")
chk 0 'status rc=2 fails=5' "after the reboot the delay is STILL there (counter persisted)"
chk 1 'check rc=2 ' "after the reboot the right PIN is still refused during the delay"
chk 2 'pwok rc=0' "password login hook: ok"
chk 3 'status rc=0 fails=0' "pwok cleared counter and delay"
chk 4 'check rc=0' "the right PIN works again"
chk 5 'force rc=0' "test hook: counter 9"
chk 6 'check rc=1 fails=10' "10th wrong try: counter 10"
chk 7 'status rc=4' "10 wrong tries: PIN disabled (rc=4)"
chk 8 'check rc=4' "COUNTER-PROOF: the right PIN is refused while disabled"
chk 9 'pwok rc=0' "password login re-enables the PIN"
chk 10 'check rc=0' "the right PIN works after re-enable"
if [[ "${L[11]:-}" =~ check\ rc=[1-5] ]] && [[ ! "${L[11]:-}" =~ rc=0 ]]; then ok "DEVICE BOUND: without /device/pinkey the old record verifies nothing (${L[11]})"; else bad "device key missing but PIN accepted: ${L[11]:-none}"; fi
chk 12 'set rc=0' "a new PIN makes a new device key"
chk 13 'check rc=0' "the new PIN works with the new key"
# r805 stage 2: the old PIN is required to change / remove
chk 14 'has rc=0' "has: a user with a PIN"
chk 15 'has rc=3' "has: a user without a PIN"
chk 16 'change rc=1 fails=1' "change with a WRONG old PIN is refused (counts as a try)"
chk 17 'change rc=6' "change to a bad-format new PIN is refused (format, no old check needed)"
chk 18 'change rc=0 fails=0' "change with the right old PIN works"
chk 19 'check rc=1' "COUNTER-PROOF: the replaced PIN no longer verifies"
chk 20 'check rc=0' "the new PIN verifies"
chk 21 'rmchk rc=1' "remove with a WRONG old PIN is refused"
chk 22 'rmchk rc=0' "remove with the right old PIN works"
chk 23 'status rc=3' "after the checked remove: no PIN"
chk 24 'has rc=3' "has: no PIN any more"
chk 25 'change rc=0' "a user without a PIN may set a first one (no old PIN to ask for)"
chk 26 'status rc=0' "and it is usable"
echo "PIN: $pass passed, $fail failed"
[ "$fail" = 0 ]
