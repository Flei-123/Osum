#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
[ -w /dev/kvm ] && export OSUM_ACCEL=kvm
OUT=$(mktemp -d)
BASE_TREE=""
cleanup() {
    [ -n "$BASE_TREE" ] && git -C "$ROOT" worktree remove --force "$BASE_TREE" >/dev/null 2>&1
    rm -rf "$OUT"
}
trap cleanup EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has()    { grep -qaF "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF "$2" "$1" 2>/dev/null && bad "$3 -- '$2' present" || ok "$3"; }

python3 - "$OUT" <<'PY'
import binascii, hashlib, sys
d = sys.argv[1]
it, salt = 1024, bytes(range(8))
dk = hashlib.pbkdf2_hmac("sha256", b"geheim12", salt, it, 32)
rec = "$osum1$%d$%s$%s" % (it, binascii.hexlify(salt).decode(), binascii.hexlify(dk).decode())
open(d + "/shadow", "w").write("justin:%s:1000:0:99999:7:::\nroot:%s:0:0:99999:7:::\n" % (rec, rec))
open(d + "/passwd", "w").write("root:x:0:0:root:/root:/bin/sh\njustin:x:1000:1000:Justin:/users/justin:/bin/sh\n")
PY

KEYS=""
for c in g e h e i m 1 2 ret; do KEYS="$KEYS mon=sendkey\\ $c mon=warte\\ 1"; done
PROGS="glogin lock theme sh echo ls cat xremoted"

sign_in() {
    local tree=$1 name=$2
    (
        cd "$tree" || exit 1
        export FIRNLIB="$tree/lib"
        eval bash tools/alltag/build.sh "$OUT/$name" kbd=yes uitrace=yes warten=14 bloecke=32768 \
            extra=\"wigapp=/bin/glogin wighalt=100\" progs=\"$PROGS\" \
            xfile=/etc/shadow="$OUT/shadow" passwdfile="$OUT/passwd" $KEYS
    ) > "$OUT/$name.log" 2>&1
}

echo "== tree: $ROOT ($(git rev-parse --short HEAD)) =="
echo "== sign-in on an image whose inittab has no xremote line =="
sign_in "$ROOT" new
S=$OUT/new/serial.txt
has "$S" "glogin: signed in as justin" "signed in"
has "$S" "glogin: xremoted pid=" "glogin starts xremoted at sign-in"
has "$S" "xremoted: started" "xremoted is running"
if [ -f "$S" ]; then
    COUNT=$(grep -ac "glogin: xremoted pid=" "$S")
    [ "$COUNT" -eq 1 ] && ok "started exactly once" || bad "started $COUNT times"
fi

echo "== counter-proof: origin/main glogin does not start it =="
BASE_TREE=$(mktemp -d)
rmdir "$BASE_TREE"
git worktree add -q --detach "$BASE_TREE" origin/main || { bad "worktree for origin/main"; BASE_TREE=""; }
if [ -n "$BASE_TREE" ]; then
    sign_in "$BASE_TREE" old
    S=$OUT/old/serial.txt
    has "$S" "glogin: signed in as justin" "old tree: signed in"
    hasnot "$S" "xremoted: started" "COUNTER-PROOF old tree: xremoted never starts"
fi

echo
echo "XRAUTOSTART: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
