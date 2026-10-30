#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/authdb/run.sh [<outdir>]  -- r2365: unreadable account files are their own verdict
#   AUTHDB_TREE=<other worktree> runs the same cases against that tree (counter-proof: old glogin/lock)
#   AUTHDB_EXPECT=old flips the asserts to what the old code does (wrong password / opens without password)
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
TREE=${AUTHDB_TREE:-$ROOT}
EXPECT=${AUTHDB_EXPECT:-new}
export FIRNLIB="$TREE/lib"
[ -w /dev/kvm ] && export OSUM_ACCEL=kvm
OUT=${1:-$(mktemp -d)}
[ -n "${1:-}" ] || trap 'rm -rf "$OUT"' EXIT
mkdir -p "$OUT"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has()    { grep -qaF "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF "$2" "$1" 2>/dev/null && bad "$3 -- '$2' present" || ok "$3"; }
B="$TREE/tools/alltag/build.sh"
PROGS="glogin lock theme sh echo ls cat"

python3 - "$OUT" <<'PY'
import binascii, hashlib, sys
d = sys.argv[1]
it, salt = 1024, bytes(range(8))
dk = hashlib.pbkdf2_hmac("sha256", b"geheim12", salt, it, 32)
rec = "$osum1$%d$%s$%s" % (it, binascii.hexlify(salt).decode(), binascii.hexlify(dk).decode())
open(d + "/shadow", "w").write("justin:%s:1000:0:99999:7:::\nroot:%s:0:0:99999:7:::\n" % (rec, rec))
open(d + "/passwd", "w").write("root:x:0:0:root:/root:/bin/sh\njustin:x:1000:1000:Justin:/users/justin:/bin/sh\n")
open(d + "/empty", "w").write("")
PY
keys() { local m=""; for c in "$@"; do
    case "$c" in warte*) m="$m mon=warte\\ ${c#warte }";; *) m="$m mon=sendkey\\ $c mon=warte\\ 1";; esac; done; echo "$m"; }
run() {
    local nm=$1 app=$2 db=$3; shift 3
    local dbarg
    case "$db" in
        ok) dbarg="xfile=/etc/shadow=$OUT/shadow" ;;
        dir) dbarg="xdir=/etc/shadow" ;;
        empty) dbarg="xfile=/etc/shadow=$OUT/empty" ;;
    esac
    eval bash "$B" "$OUT/$nm" kbd=yes uitrace=yes warten=14 bloecke=32768 \
        extra=\"wigapp=/bin/$app wighalt=100\" progs=\"$PROGS\" $dbarg \
        passwdfile="$OUT/passwd" $(keys "$@") > "$OUT/$nm.log" 2>&1
}
only() { [ -z "${AUTHDB_ONLY:-}" ] || case " $AUTHDB_ONLY " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

echo "== tree: $TREE ($(git -C "$TREE" rev-parse --short HEAD)), expect $EXPECT =="

if only l0; then
echo "== control: readable shadow, lock opens with the right password =="
run l0 lock ok g e h e i m 1 2 ret
has "$OUT/l0/serial.txt" "sperre: aufgesperrt" "lock opens with the right password"
fi

if only l1; then
echo "== lock: /etc/shadow is a directory, a wrong password is typed =="
run l1 lock dir x y z ret "warte 3"
S=$OUT/l1/serial.txt
if [ "$EXPECT" = new ]; then
    has "$S" "account files unreadable" "lock reports the account files as unreadable"
    hasnot "$S" "sperre: aufgesperrt" "lock stays shut without a password check"
else
    has "$S" "sperre: aufgesperrt" "COUNTER-PROOF old lock: opens without a password"
fi
fi

if only l2; then
echo "== lock: /etc/shadow is empty =="
run l2 lock empty x y z ret "warte 3"
S=$OUT/l2/serial.txt
if [ "$EXPECT" = new ]; then
    has "$S" "account files unreadable" "empty shadow: reported as unreadable"
    hasnot "$S" "sperre: aufgesperrt" "empty shadow: lock stays shut"
else
    has "$S" "sperre: aufgesperrt" "COUNTER-PROOF old lock: empty shadow opens"
fi
fi

if only g1; then
echo "== sign-in: /etc/shadow is a directory, the right password is typed =="
run g1 glogin dir g e h e i m 1 2 ret "warte 3"
S=$OUT/g1/serial.txt
hasnot "$S" "glogin: angemeldet" "nobody is signed in"
if [ "$EXPECT" = new ]; then
    has "$S" "account files unreadable" "sign-in reports the account files as unreadable"
    hasnot "$S" "glogin: abgewiesen" "and does not call it a wrong password"
else
    has "$S" "glogin: abgewiesen" "COUNTER-PROOF old glogin: calls it a wrong password"
fi
fi

if only g2; then
echo "== sign-in: readable shadow still signs in =="
run g2 glogin ok g e h e i m 1 2 ret
has "$OUT/g2/serial.txt" "glogin: angemeldet als justin" "right password: signed in"
fi

echo
echo "AUTHDB: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
