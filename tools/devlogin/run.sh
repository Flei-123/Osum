#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/devlogin/run.sh -- dev-mode sign-in at the glogin screen without typing (jarvisd -i login).
#
#   bash tools/devlogin/run.sh <build dir of an ODB=1 dev image> [<build dir of the old main image>]
#
#   A  dev mode on: `jarvisd -i login justin` signs in (glogin: dev login as justin, signed in, desktop up)
#   B  typed wrong password + Enter reaches glogin (glogin: rejected) -- Enter itself works
#   C  counter-proofs: root refused, emergency stop refuses, a hand-written request without the
#      dev-mode marker is ignored, an unknown account is ignored; none of them signs in
#   D  old main image: the same call is refused (unknown input kind) and nothing signs in
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
BUILD=${1:?build dir}
OLD=${2:-}
TOKEN=${ODB_TOKEN_FILE:-/root/abbilder/odb.token}
TMPD=$(mktemp -d)
trap 'for d in "$TMPD"/*/; do bash "$ROOT/tools/odbc/qemu.sh" stop "$d" >/dev/null 2>&1; done; rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
ODBC="python3 -I $ROOT/tools/odbc/odbc.py"

img_of() { ls "$1"/*-usb.img | head -1; }

boot() {
    local name=$1 build=$2
    local d="$TMPD/$name"; mkdir -p "$d"
    cp --reflink=auto "$(img_of "$build")" "$d/disk.img"
    bash "$ROOT/tools/odbc/qemu.sh" start "$d/disk.img" "$d" 2 1536 > "$d/start.txt" 2>&1 || return 1
    $ODBC --port "unix:$d/odb.sock" --token-file "$TOKEN" wait 240 > "$d/wait.txt" 2>&1 || return 1
    local i=0
    while [ $i -lt 120 ] && ! grep -aq 'glogin: ready' "$d/com1.log" 2>/dev/null; do sleep 1; i=$((i+1)); done
    sleep 5
}

ex() { local d=$1; shift; $ODBC --port "unix:$d/odb.sock" --token-file "$TOKEN" --timeout 60 exec "$@" 2>&1; }

signed_in() { grep -aq 'glogin: signed in as' "$1/com1.log"; }

scenario_main() {
    local d="$TMPD/main"
    ex "$d" "/bin/jarvisd -i type wrongpassword" > "$d/type.txt"
    ex "$d" "/bin/jarvisd -i 'scan 28 156'" > "$d/enter.txt"
    sleep 4
    grep -aq 'glogin: rejected' "$d/com1.log" && echo B_OK > "$d/B" || echo B_BAD > "$d/B"
    ex "$d" "/bin/jarvisd -i login root" > "$d/root.txt"
    sleep 4
    signed_in "$d" && echo root_in > "$d/C1" || echo root_out > "$d/C1"
    ex "$d" "/bin/jarvisd -i login no-such-user" > "$d/nouser.txt"
    sleep 4
    signed_in "$d" && echo nouser_in > "$d/C2" || echo nouser_out > "$d/C2"
    ex "$d" "/bin/sh -c 'echo > /var/jarvis/dev-off'" > "$d/stop.txt"
    ex "$d" "/bin/jarvisd -i login justin" > "$d/stoplogin.txt"
    ex "$d" "/bin/sh -c 'echo justin > /var/jarvis/devlogin'" > "$d/hand.txt"
    sleep 25
    signed_in "$d" && echo stop_in > "$d/C3" || echo stop_out > "$d/C3"
}

scenario_positive() {
    local d="$TMPD/pos"
    ex "$d" "/bin/jarvisd -i login justin" > "$d/login.txt"
    local i=0
    while [ $i -lt 90 ] && ! signed_in "$d"; do sleep 1; i=$((i+1)); done
    sleep 8
    ex "$d" "/bin/ps" > "$d/ps.txt"
}

scenario_old() {
    local d="$TMPD/old"
    ex "$d" "/bin/jarvisd -i login justin" > "$d/login.txt"
    sleep 20
}

boot main "$BUILD" && boot pos "$BUILD" || { bad "boot"; tail -5 "$TMPD"/*/start.txt; }
[ -n "$OLD" ] && boot old "$OLD"
scenario_main &
scenario_positive &
[ -n "$OLD" ] && scenario_old &
wait

d="$TMPD/pos"
grep -aq 'dev login as justin' "$d/com1.log" && ok "A: glogin took the dev-mode request" || bad "A: no 'dev login as' line ($(cat "$d/login.txt" | tail -2 | tr '\n' ' '))"
signed_in "$d" && ok "A: signed in without typing" || bad "A: not signed in"
grep -aq 'desktop' "$d/ps.txt" && ok "A: desktop process is up" || bad "A: no desktop"

d="$TMPD/main"
[ "$(cat "$d/B" 2>/dev/null)" = B_OK ] && ok "B: typed password + Enter reaches glogin (rejected)" || bad "B: no 'glogin: rejected' ($(cat "$d/enter.txt" | tail -2 | tr '\n' ' '))"
[ "$(cat "$d/C1" 2>/dev/null)" = root_out ] && ok "C: root is not signed in" || bad "C: root request signed in"
[ "$(cat "$d/C2" 2>/dev/null)" = nouser_out ] && ok "C: unknown account is not signed in" || bad "C: unknown account signed in"
grep -aq 'login needs dev mode' "$d/stoplogin.txt" && ok "C: emergency stop refuses the login job" || bad "C: stop did not refuse ($(tail -2 "$d/stoplogin.txt" | tr '\n' ' '))"
[ "$(cat "$d/C3" 2>/dev/null)" = stop_out ] && ok "C: hand-written request without the dev marker is ignored" || bad "C: request without marker signed in"

if [ -n "$OLD" ]; then
    d="$TMPD/old"
    grep -aq 'unknown input kind' "$d/login.txt" && ok "D: old main refuses the login job" || bad "D: old main did not refuse ($(tail -2 "$d/login.txt" | tr '\n' ' '))"
    signed_in "$d" && bad "D: old main signed in" || ok "D: old main stays at the sign-in screen"
fi

echo; echo "DEVLOGIN: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
