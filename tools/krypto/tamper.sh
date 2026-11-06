#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/../lib/brand-env.sh"
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
. tools/lib/tmpdir.sh
ROOT=$(pwd)

TMPD=$(mktemp -d)
osum_tmp_guard "" "$TMPD"

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

PY=python3
for candidate in "${OSUM_KRYPTO_PY:-}" /root/.krypto-venv/bin/python python3; do
    [ -n "$candidate" ] || continue
    command -v "$candidate" >/dev/null 2>&1 || [ -x "$candidate" ] || continue
    if "$candidate" -c 'import argon2.low_level, cryptography' 2>/dev/null; then
        PY=$candidate; break
    fi
done
if ! "$PY" -c 'import argon2.low_level, cryptography' 2>/dev/null; then
    echo "TAMPER: FAILED -- argon2-cffi and/or cryptography are missing (no skip allowed)"
    exit 1
fi

echo "== 1. kernel with one flipped bit in the XTS sector ciphertext =="
cp -r lib "$TMPD/lib_tamper"
"$PY" -I - "$TMPD/lib_tamper/crypto/xts.fi" <<'PYEOF'
import sys
path = sys.argv[1]
text = open(path).read()
head = "fn sector_encrypt(key: u64, sector: u64, inp: u64, out: u64,\n    n: usize) -> bool {"
assert head in text
text = text.replace(head, head.replace("sector_encrypt", "sector_encrypt_raw", 1), 1)
text += """
fn sector_encrypt(key: u64, sector: u64, inp: u64, out: u64,
    n: usize) -> bool {
    if !sector_encrypt_raw(key, sector, inp, out, n) { return false }
    octets.store_byte(out, 0, octets.load_byte(out, 0) ^ (1 as u8))
    return true
}
"""
open(path, "w").write(text)
PYEOF
if KERNEL_FIRNLIB="$TMPD/lib_tamper" bash tools/build-kernel.sh "$TMPD/kt.mb" > "$TMPD/build.log" 2>&1; then
    ok "the tampered kernel builds"
else
    bad "the tampered kernel does not build"
    tail -8 "$TMPD/build.log" | sed 's/^/        /'
    echo "TAMPER: $pass passed, $fail failed"; exit 1
fi

echo "== 2. one boot: create, format, write four files =="
BLOCKS=8192
if bash tools/mkfsfi/mkfs.sh build "$TMPD/root.img" "$BLOCKS" /bin/ /proc/ /dev/ > "$TMPD/mkfs.log" 2>&1; then
    ok "the root disk is up"
else
    bad "mkfs fails"
fi
timeout 300 $QEMU_X86 -kernel "$TMPD/kt.mb" -m 512 \
    -append "osum nopwr kryptoneu kryptotest kryptobaum kryptopw=secret kryptot=1 kryptom=64 kryptop=1" \
    -serial "file:$TMPD/t1.txt" -display none -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    -drive "file=$TMPD/root.img,format=raw,if=ide,index=0" > /dev/null 2>&1
if grep -qaE 'neu=1' "$TMPD/t1.txt"; then
    ok "the kernel created the disk (the tamper does not stop the boot)"
else
    bad "the kernel did not report neu=1"
fi

echo "== 3. the gate predicates must turn red =="
"$PY" tools/krypto/gegen.py tree "$TMPD/root.img" secret > "$TMPD/tree.txt" 2>&1
sed 's/^/        /' "$TMPD/tree.txt" | head -6
good=$(grep -a -m1 'tree: good=' "$TMPD/tree.txt" | grep -oE 'good=[0-9]+' | cut -d= -f2)
if [ "${good:-0}" = 4 ]; then
    bad "CONTROL RUN: the host reads all four files from the tampered disk"
else
    ok "CONTROL RUN: the host does not read the files from the tampered disk (good=${good:-0} of 4)"
fi
selftest=$(grep -a -m1 -oE 'selbst=[0-9]+' "$TMPD/t1.txt" | cut -d= -f2)
tree_kernel=$(grep -a -m1 -oE 'baum=[0-9]+' "$TMPD/t1.txt" | cut -d= -f2)
echo "        kernel self-test=${selftest:-none} kernel tree=${tree_kernel:-none}"
if [ "${good:-0}" != 4 ] || [ "${selftest:-1}" != 1 ] || [ "${tree_kernel:-4}" != 4 ]; then
    ok "CONTROL RUN: at least one gate predicate is red for the tampered kernel"
else
    bad "CONTROL RUN: every gate predicate stays green for the tampered kernel"
fi

echo
echo "TAMPER: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
