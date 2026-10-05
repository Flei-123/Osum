#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/loginscene/run.sh -- r373: THE SIGN-IN SCREEN IS A SCENE TREE OF fUi.
#
#   bash tools/loginscene/run.sh [<out dir>]
#
# glogin (kernel/user/glogin.fi) on a small disk with one account `justin`
# (uid 1000, password geheim12). Measures, from the guest's trace lines:
#   tree     "fUi Szenenbaum", the rectangles of the host's tree: ONE password
#            field, four buttons (Anmelden, Anderer Benutzer, network, power),
#            the clock at the bottom right; 4-pixel grid >= 92 %
#   chain    Tab chain Kennwort -> Auge -> Anmelden -> Anderer Benutzer ->
#            Netzwerk -> Ein/Aus -> Kennwort (host focus, `wlib: focus` lines)
#   caret    the caret blinks (`wlib: caret` lines)
#   eye      Tab, Enter on the eye shows the text (`wlib: eye ... shown=1`)
#   login    wrong password: refused and the screen stays; right one: signed in
#            as justin, uid 1000
#   other    "Anderer Benutzer": name field comes out, typing a name and the
#            password signs that user in
#   quick    network / power icons open their panel, nothing is switched off
#   counter  only wrong passwords: nobody is signed in
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
# KVM when the machine has it (the password check, PBKDF2, is slow under TCG)
[ -w /dev/kvm ] && export OSUM_ACCEL=kvm
OUT=${1:-$(mktemp -d)}
[ -n "${1:-}" ] || trap 'rm -rf "$OUT"' EXIT
mkdir -p "$OUT"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
hat()    { grep -qaF "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 -- '$2' missing"; }
hatnicht() { grep -qaF "$2" "$1" 2>/dev/null && bad "$3 -- '$2' present" || ok "$3"; }
num() { if [ -z "${2:-}" ]; then bad "$1: no number"; elif [ "$2" -"$3" "$4" ] 2>/dev/null; then ok "$1: $2"; else bad "$1: $2, expected $3 $4"; fi; }
B=tools/alltag/build.sh
PROGS="glogin theme sh echo ls cat"

echo on > "$OUT/uiblink"
python3 - "$OUT" <<'PY'
import binascii, hashlib, sys
d = sys.argv[1]
it, salt = 1024, bytes(range(8))
dk = hashlib.pbkdf2_hmac("sha256", b"geheim12", salt, it, 32)
rec = "$osum1$%d$%s$%s" % (it, binascii.hexlify(salt).decode(), binascii.hexlify(dk).decode())
open(d + "/shadow", "w").write("justin:%s:1000:0:99999:7:::\nroot:%s:0:0:99999:7:::\n" % (rec, rec))
open(d + "/passwd", "w").write("root:x:0:0:root:/root:/bin/sh\njustin:x:1000:1000:Justin:/users/justin:/bin/sh\n")
PY
keys() { local m=""; for c in "$@"; do
    case "$c" in warte*) m="$m mon=warte\\ ${c#warte }";; *) m="$m mon=sendkey\\ $c mon=warte\\ ${KEYGAP:-1}";; esac; done; echo "$m"; }
run() { # name wait-seconds keys...
    local nm=$1 w=$2; shift 2
    eval bash "$B" "$OUT/$nm" kbd=yes uitrace=yes warten=$w bloecke=32768 \
        extra=\"wigapp=/bin/glogin wighalt=${HALT:-100}\" progs=\"$PROGS\" xfile=/etc/shadow="$OUT/shadow" xfile=/etc/uiblink="$OUT/uiblink" \
        passwdfile="$OUT/passwd" $(keys "$@") > "$OUT/$nm.log" 2>&1
}
foc() { grep -aoE 'focus id=[0-9]+ kind=[0-9]+' "$1" | sed 's/focus id=//; s/ kind=.*//' | tr '\n' ' '; }

echo "== tree + grid =="
run g1 12
S=$OUT/g1/serial.txt
hat "$S" "glogin: fUi Szenenbaum" "the sign-in screen is a scene tree"
hat "$S" "glogin: bereit n=1" "and it is ready (one account)"
num "password fields" "$(grep -aoE 'glogin: rect id=[0-9]+ kind=4 ' "$S" | sort -u | wc -l)" eq 1
num "buttons (Anmelden, Anderer Benutzer, network, power)" "$(grep -aoE 'glogin: rect id=[0-9]+ kind=2 ' "$S" | sort -u | wc -l)" eq 4
CLOCK=$(grep -aoE 'glogin: rect id=10 kind=1 x=[0-9]+ y=[0-9]+' "$S" | head -1)
echo "$CLOCK" | awk -F'[ =]' '{ exit !($8 > 900 && $10 > 650) }' && ok "the clock is at the bottom right ($CLOCK)" || bad "clock position: '$CLOCK'"
R=$(python3 tools/design/messen.py "$OUT/g1" 2>/dev/null | grep -a 'raster/4' | grep -aoE '\([0-9]+%\)' | tr -dc '0-9')
[ -n "$R" ] && [ "$R" -ge 92 ] && ok "4-pixel grid: $R %" || bad "4-pixel grid: '${R}' %"
C=$(grep -ac 'wlib: caret vis=' "$S")
num "caret phase changes in the quiet run" "$C" ge 3

echo "== Tab chain =="
run g2 10 tab tab tab tab tab tab
F=$(foc "$OUT/g2/serial.txt" | tr -s ' ' | sed 's/^0 //')
# the focus line is written twice at the start (the second one is the
# "say again"), then once per Tab
echo "        focus order: $F"
case "$F" in
    "7 7 16 8 9 11 12 7 "*|"7 16 8 9 11 12 7 "*) ok "Tab chain: Kennwort, Auge, Anmelden, Anderer Benutzer, Netzwerk, Ein/Aus, Kennwort";;
    *) bad "Tab chain: '$F'";;
esac

echo "== the eye =="
run g3 10 tab ret
hat "$OUT/g3/serial.txt" "eye id=7 shown=1 len=0" "Tab+Enter on the eye shows the text"
hatnicht "$OUT/g3/serial.txt" "glogin: angemeldet" "and does not sign anybody in"

echo "== wrong password, then the right one =="
run g4 10 x y z ret "warte 4" g e h e i m 1 2 ret
S=$OUT/g4/serial.txt
hat "$S" "glogin: abgewiesen, name=justin" "wrong password: refused"
hat "$S" "glogin: angemeldet als justin" "right password: signed in as justin"
hat "$S" "glogin: uid=1000" "and the session runs as uid 1000"

echo "== counter-proof: only wrong passwords =="
run g5 10 x y z ret "warte 4" a b c ret
S=$OUT/g5/serial.txt
hat "$S" "glogin: abgewiesen" "wrong passwords are refused"
hatnicht "$S" "glogin: angemeldet" "COUNTER-PROOF: nobody is signed in"

echo "== another user =="
run g6 10 tab tab tab ret j u s t i n ret g e h e i m 1 2 ret
S=$OUT/g6/serial.txt
hat "$S" "glogin: anderer benutzer" "Anderer Benutzer: the name field comes out"
hat "$S" "glogin: angemeldet als justin" "name typed, password typed: signed in"

echo "== quick access =="
run g7 10 tab tab tab tab ret ret
S=$OUT/g7/serial.txt
hat "$S" "glogin: schnell=1" "the network icon opens the network text"
hat "$S" "glogin: schnell=0" "a second Enter closes it again"
hatnicht "$S" "glogin: energie" "COUNTER-PROOF: nothing was switched off"

echo; echo "LOGINSCENE: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
