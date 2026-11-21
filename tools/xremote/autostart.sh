#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
[ -w /dev/kvm ] && export OSUM_ACCEL=kvm
OUT=${XRAUTOSTART_OUT:-$(mktemp -d)}
BASE_TREE=""
cleanup() {
    [ -n "$BASE_TREE" ] && git -C "$ROOT" worktree remove --force "$BASE_TREE" >/dev/null 2>&1
    [ -z "${XRAUTOSTART_OUT:-}" ] && rm -rf "$OUT"
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
PROGS="glogin lock theme sh echo ls cat"
bash tools/xremote/build-daemon.sh "$OUT/xremoted.elf"
grep -v "^autostart=" pakete/xremote/INFO > "$OUT/INFO.noauto"

sign_in() {
    local tree=$1 name=$2 info=${3:-$ROOT/pakete/xremote/INFO}
    (
        cd "$tree" || exit 1
        export FIRNLIB="$tree/lib"
        eval bash tools/alltag/build.sh "$OUT/$name" kbd=yes uitrace=yes warten=14 bloecke=32768 \
            extra=\"wigapp=/bin/glogin wighalt=100\" progs=\"$PROGS\" \
            xdir=/apps xdir=/apps/xremote.osp xdir=/apps/xremote.osp/bin xfile=/apps/xremote.osp/INFO="$info" xfile=/apps/xremote.osp/bin/xremoted="$OUT/xremoted.elf" \
            xfile=/etc/shadow="$OUT/shadow" passwdfile="$OUT/passwd" $KEYS
    ) > "$OUT/$name.log" 2>&1
}

echo "== tree: $ROOT ($(git rev-parse --short HEAD)) =="
echo "== sign-in on an image whose inittab has no xremote line =="
sign_in "$ROOT" new
S=$OUT/new/serial.txt
has "$S" "glogin: signed in as justin" "signed in"
has "$S" "glogin: package services started=" "glogin starts the package service"
has "$S" "xremoted: started" "xremoted is running"
if [ -f "$S" ]; then
    FIRST=$(grep -an "glogin: package services started=" "$S" | head -1 | cut -d: -f1)
    SIGNED=$(grep -an "glogin: signed in as" "$S" | head -1 | cut -d: -f1)
    [ -n "$FIRST" ] && [ -n "$SIGNED" ] && [ "$FIRST" -lt "$SIGNED" ] && ok "xremoted starts at the sign-in screen, before the sign-in" || bad "xremoted start (line ${FIRST:-none}) not before sign-in (line ${SIGNED:-none})"
fi
if [ -f "$S" ]; then
    COUNT=$(grep -ac "glogin: package services started=" "$S")
    [ "$COUNT" -eq 1 ] && ok "started exactly once" || { bad "started $COUNT times"; grep -a "xremoted" "$S" | head -20; }
fi

BASE_REF=${XRAUTOSTART_BASE:-04b121db7^}
echo "== counter-proof: glogin before the autostart change ($BASE_REF) does not start it =="
BASE_TREE=$(mktemp -d)
rmdir "$BASE_TREE"
git worktree add -q --detach "$BASE_TREE" "$BASE_REF" || { bad "worktree for $BASE_REF"; BASE_TREE=""; }
if [ -n "$BASE_TREE" ]; then
    sign_in "$BASE_TREE" old
    S=$OUT/old/serial.txt
    has "$S" "glogin: signed in as justin" "old tree: signed in"
    hasnot "$S" "xremoted: started" "COUNTER-PROOF old tree: xremoted never starts"
fi

echo "== counter-proof: a bundle INFO without autostart= starts nothing =="
sign_in "$ROOT" noauto "$OUT/INFO.noauto"
S=$OUT/noauto/serial.txt
has "$S" "glogin: signed in as justin" "noauto: signed in"
hasnot "$S" "xremoted: started" "COUNTER-PROOF no autostart key: xremoted never starts"

echo
echo "XRAUTOSTART: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
