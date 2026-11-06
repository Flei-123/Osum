#!/usr/bin/env bash
#
# Aufruf:  bash tools/geraetekey/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

TMPD=${OSUM_GK_TMP:-$(mktemp -d)}
mkdir -p "$TMPD"
KEEP=${OSUM_GK_KEEP:-}
. tools/lib/summary.sh; summary_begin GERAETEKEY
trap 'summary_guard; [ -n "$KEEP" ] || rm -rf "$TMPD"; summary_exit_status || exit 1' EXIT
trap 'exit 1' HUP INT TERM

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

if [ -f tools/lib/qemu.sh ]; then . tools/lib/qemu.sh; fi
QEMU=${QEMU_X86:-qemu-system-x86_64}

echo "== 0. build: kernel and programs, from the SAME tree =="
export BRIDGE_PROGS="sh ls cat echo chmod rm jsig jarvisctl"
if bash tools/bridge/build.sh "$TMPD/w0" 0 > "$TMPD/build.txt" 2>&1; then
    ok "Kern und Ring-3-Programme gebaut"
else
    bad "the build failed"
    tail -15 "$TMPD/build.txt" | sed 's/^/        /'
    summary_emit "$pass" "$fail" 0; exit 1
fi
K="$TMPD/w0/k.mb"
[ -f "$TMPD/w0/jsig.elf" ] && ok "/bin/jsig is present ($(stat -c%s "$TMPD/w0/jsig.elf") Oktette)" \
    || bad "jsig.elf fehlt"

cat > "$TMPD/rechte.conf" <<'CONF'
commands        = no
screenshot = no
sysinfo     = no
CONF
bash tools/mkfsfi/mkfs.sh build "$TMPD/platte.img" 16384 \
    /bin/ /etc/ /etc/jarvis/ /var/ /var/log/ /var/jarvis/ \
    "/bin/sh=$TMPD/w0/sh.elf" \
    "/bin/ls=$TMPD/w0/ls.elf" \
    "/bin/cat=$TMPD/w0/cat.elf" \
    "/bin/echo=$TMPD/w0/echo.elf" \
    "/bin/rm=$TMPD/w0/rm.elf" \
    "/bin/chmod=$TMPD/w0/chmod.elf" \
    "/bin/jsig=$TMPD/w0/jsig.elf" \
    "/bin/jarvisctl=$TMPD/w0/jarvisctl.elf" \
    "/etc/jarvis/permissions.conf=$TMPD/rechte.conf" \
    > "$TMPD/mkfs.txt" 2>&1 \
    && ok "the root is on the disk ($(stat -c%s "$TMPD/platte.img") Oktette)" \
    || { bad "mkfs"; tail -6 "$TMPD/mkfs.txt" | sed 's/^/        /'; }

start() { # <name> <skript>
    [ -n "${GK_WEGWERF:-}" ] && cp -f "$TMPD/frisch.img" "$TMPD/platte.img"
    timeout 180 $QEMU -kernel "$K" -m 256 \
        -append "osum nokbd nosched noproc nofs noring3 script=$2" \
        -serial "file:$TMPD/$1.txt" -display none -no-reboot \
        -drive "file=$TMPD/platte.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$TMPD/q-$1.log" 2>&1
    return 0
}

cp -f "$TMPD/platte.img" "$TMPD/frisch.img"
NACHRICHT=4f2d303039   # "O-009" in Hex

echo "== 1. run 1: create and sign the device key =="
start lauf1 "jsig init;jsig sign $NACHRICHT;exit"
PUB1=$(grep -aoE '^pub [0-9a-f]{64}' "$TMPD/lauf1.txt" | head -1 | awk '{print $2}')
SIG1=$(grep -aoE '^sig [0-9a-f]{128}' "$TMPD/lauf1.txt" | head -1 | awk '{print $2}')
if [ -n "$PUB1" ]; then
    ok "the Ed25519 pair is created (pub ${PUB1:0:16}...)"
else
    bad "jsig delivered no key"
    tail -8 "$TMPD/lauf1.txt" | sed 's/^/        /'
fi
if [ -n "$SIG1" ]; then
    ok "and a signature on it (${#SIG1} hex digits)"
else
    bad "keine Unterschrift"
    tail -8 "$TMPD/lauf1.txt" | sed 's/^/        /'
fi

echo "== 2. NEUSTART -- dieselbe Platte, neuer Kern =="
start lauf2 "jsig init;jsig verify $PUB1 $NACHRICHT $SIG1;exit"
PUB2=$(grep -aoE '^pub [0-9a-f]{64}' "$TMPD/lauf2.txt" | head -1 | awk '{print $2}')
if [ -n "$PUB1" ] && [ "$PUB2" = "$PUB1" ]; then
    ok "O-009: AFTER THE RESTART THE SAME public part -- no second pairing needed"
else
    bad "O-009: the key did not survive the restart (before ${PUB1:-?}, after ${PUB2:-?})"
    tail -8 "$TMPD/lauf2.txt" | sed 's/^/        /'
fi
if grep -qa '^yes$' "$TMPD/lauf2.txt"; then
    ok "O-009: a signature FROM BEFORE the restart still verifies"
else
    bad "O-009: the old signature does not verify after the restart"
    tail -8 "$TMPD/lauf2.txt" | sed 's/^/        /'
fi

echo "== 3. with foreign eyes: python-cryptography recomputes =="
if [ -n "$PUB1" ] && [ -n "$SIG1" ] && python3 -c 'import cryptography' 2>/dev/null; then
    python3 - "$PUB1" "$SIG1" "$NACHRICHT" > "$TMPD/fremd.txt" 2>&1 <<'PYFREMD'
import sys
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from cryptography.exceptions import InvalidSignature
pub = bytes.fromhex(sys.argv[1]); sig = bytes.fromhex(sys.argv[2])
msg = bytes.fromhex(sys.argv[3])
k = Ed25519PublicKey.from_public_bytes(pub)
try:
    k.verify(sig, msg); print("GUT")
except InvalidSignature:
    print("FALSCH")
try:
    k.verify(sig, msg + b"\x01"); print("GEGENPROBE-FALSCH")
except InvalidSignature:
    print("GEGENPROBE-GUT")
PYFREMD
    grep -qa '^GUT$' "$TMPD/fremd.txt" \
        && ok "a foreign tool recomputes the surviving signature" \
        || { bad "python-cryptography verwirft die Unterschrift"; sed 's/^/        /' "$TMPD/fremd.txt"|head -4; }
    grep -qa '^GEGENPROBE-GUT$' "$TMPD/fremd.txt" \
        && ok "CONTROL RUN: over a different message it fails" \
        || bad "the signature also fits a different message"
else
    echo "  [ -- ] python-cryptography missing: the foreign recomputation is skipped"
fi

echo "== 4. CONTROL RUN: reset -- and it MUST be gone =="
start lauf3 "rm /etc/jarvis/device.key;jsig init;exit"
PUB3=$(grep -aoE '^pub [0-9a-f]{64}' "$TMPD/lauf3.txt" | head -1 | awk '{print $2}')
if [ -n "$PUB3" ] && [ -n "$PUB1" ] && [ "$PUB3" != "$PUB1" ]; then
    ok "after the reset a DIFFERENT key appears (pub ${PUB3:0:16}...)"
else
    bad "after the deletion the same key came back (${PUB3:-?}) -- then jsig does not read it from the file"
    tail -8 "$TMPD/lauf3.txt" | sed 's/^/        /'
fi
start lauf4 "jsig verify $PUB3 $NACHRICHT $SIG1;exit"
if grep -qa '^no$' "$TMPD/lauf4.txt"; then
    ok "CONTROL RUN: the old signature does NOT fit the new key"
else
    bad "the old signature also fits the new key -- then jsig does not check"
    tail -6 "$TMPD/lauf4.txt" | sed 's/^/        /'
fi

echo "== 5. CONTROL RUN: a root that does NOT survive =="
if [ -z "${GK_WEGWERF:-}" ]; then
    GK_WEGWERF=1 OSUM_GK_TMP="$TMPD/gegen" OSUM_GK_KEEP=1 \
        bash "$0" > "$TMPD/gegen.txt" 2>&1
    if grep -qa 'der Schluessel hat den Neustart nicht ueberlebt' "$TMPD/gegen.txt"; then
        ok "with a throwaway root O-009 fails -- the acceptance really measures survival"
    else
        bad "even with a throwaway root everything stays green -- then this acceptance measures nothing"
        grep -a 'FAIL\|OK    O-009' "$TMPD/gegen.txt" | head -5 | sed 's/^/        /'
    fi
    rm -rf "$TMPD/gegen"
fi

summary_emit "$pass" "$fail" 10 || exit 1
[ "$fail" = 0 ] || exit 1
exit 0
