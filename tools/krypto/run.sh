#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/../lib/brand-env.sh"
#
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
. tools/lib/firnenv.sh

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

num() { # name value op want
    if [ -z "${2:-}" ]; then bad "$1: no number found (expected $3 $4)"; return; fi
    if [ "$2" -"$3" "$4" ] 2>/dev/null; then ok "$1: $2"
    else bad "$1: $2, expected $3 $4"; fi
}
same() { # name want got
    if [ "$2" = "$3" ]; then ok "$1"
    else
        bad "$1"
        printf '        want: %s\n' "$(printf '%s' "$2" | head -c 200)"
        printf '        got : %s\n' "$(printf '%s' "$3" | head -c 200)"
    fi
}
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
has_not() { grep -qaF "$2" "$1" && bad "$3 -- '$2' present" || ok "$3"; }

kvalue() { # file name
    case "$2" in
        null|sum) grep -a -m1 -oE "$2=[0-9]+" "$1" 2>/dev/null | head -1 | cut -d= -f2 ;;
        *) grep -a "krypto:" "$1" 2>/dev/null | grep -m1 -oE "(^|[ :])$2=[0-9]+" | head -1 | cut -d= -f2 ;;
    esac
}
ksays() { # file name want description
    local got; got=$(kvalue "$1" "$2")
    if [ -z "$got" ]; then bad "$4 -- no line '$2='"; return; fi
    if [ "$got" = "$3" ]; then ok "$4 ($2=$got)"
    else bad "$4 -- $2=$got, expected $3"; fi
}

echo "== 0. preconditions =="
command -v qemu-system-x86_64 >/dev/null 2>&1 || {
    echo "KRYPTO: FAILED, qemu-system-x86_64 is missing (a skip would be a silent green)"; exit 1; }
command -v python3 >/dev/null 2>&1 || {
    echo "KRYPTO: FAILED, python3 is missing (a skip would be a silent green)"; exit 1; }

PY=python3
for candidate in "${OSUM_KRYPTO_PY:-}" /root/.krypto-venv/bin/python python3; do
    [ -n "$candidate" ] || continue
    command -v "$candidate" >/dev/null 2>&1 || [ -x "$candidate" ] || continue
    if "$candidate" -c 'import argon2.low_level, cryptography' 2>/dev/null; then
        PY=$candidate; break
    fi
done
if ! "$PY" -c 'import argon2.low_level, cryptography' 2>/dev/null; then
    echo "KRYPTO: FAILED -- argon2-cffi and/or cryptography are missing."
    echo "  Without an INDEPENDENT implementation this acceptance would be a"
    echo "  soliloquy. Remedy:"
    echo "    python3 -m venv /root/.krypto-venv"
    echo "    /root/.krypto-venv/bin/pip install argon2-cffi cryptography"
    exit 1
fi
ok "the foreign tool is there ($PY: argon2-cffi, cryptography)"
if command -v argon2 >/dev/null 2>&1; then
    ok "plus the argon2 command of the distribution (second foreign implementation)"
fi

echo "== 1. the kdata memory map =="
if python3 tools/kernel/memmap.py kernel > "$TMPD/map.txt" 2>&1; then
    ok "the map: $(tail -1 "$TMPD/map.txt")"
else
    bad "tools/kernel/memmap.py reports collisions"
    sed 's/^/        /' "$TMPD/map.txt" | head -10
fi
has "$TMPD/map.txt" "0 collisions" "no two ranges overlap"

v=$(grep -aE "^const CRYPT_OFF: u64 = 0x[0-9A-Fa-f]+" kernel/lib/kstate.fi \
    | head -1 | grep -oE '0x[0-9A-Fa-f]+')
if [ "$(( v ))" = "$(( 0x113000 ))" ]; then
    ok "CRYPT_OFF = $v -- exactly the assigned address"
else
    bad "CRYPT_OFF = ${v:-missing}, assigned was 0x113000"
fi
m=$(grep -aE "^const CRYPT_MAX: u64 = 0x[0-9A-Fa-f]+" kernel/lib/kstate.fi \
    | head -1 | grep -oE '0x[0-9A-Fa-f]+')
if [ "$(( v + m ))" -le "$(( 0x118000 ))" ]; then
    ok "and ends at $(printf '0x%X' $(( v + m ))), so not beyond 0x118000"
else
    bad "the range extends beyond 0x118000"
fi

mkdir -p "$TMPD/kcopy"
( cd kernel && find . -name '*.fi' -exec cp --parents {} "$TMPD/kcopy/" \; )
sed -i 's/^const CRYPT_OFF: u64 = 0x113000$/const CRYPT_OFF: u64 = 0x108000/' \
    "$TMPD/kcopy/lib/kstate.fi"
if python3 tools/kernel/memmap.py "$TMPD/kcopy" > "$TMPD/map2.txt" 2>&1; then
    bad "CONTROL RUN: CRYPT_OFF placed on WMP_OFF and the checker stays silent"
else
    ok "CONTROL RUN: CRYPT_OFF placed on WMP_OFF -- the map checker raises the alarm"
fi

echo "== 2. build =="
if bash tools/build-kernel.sh "$TMPD/k0.mb" > "$TMPD/build.log" 2>&1; then
    ok "the kernel builds ($(stat -c %s "$TMPD/k0.mb") bytes)"
else
    bad "the kernel cannot be built"
    sed 's/^/        /' "$TMPD/build.log" | tail -12
    echo "KRYPTO: $pass passed, $fail failed"; exit 1
fi

mkdir -p .probe
if $FIRNC tools/krypto/orakel.fi -o .probe/koracle 2> "$TMPD/oracle.err"; then
    ok "tools/krypto/orakel.fi builds against lib/crypto/ (the same files as the kernel)"
else
    bad "tools/krypto/orakel.fi cannot be built"
    sed 's/^/        /' "$TMPD/oracle.err" | head -20
    echo "KRYPTO: $pass passed, $fail failed"; exit 1
fi
if [ "$(echo 'nonsense' | ./.probe/koracle)" = "FAIL" ]; then
    ok "the oracle rejects nonsense (says FAIL)"
else
    bad "the oracle does not say FAIL about 'nonsense'"
fi

echo "== 3. the computation against the standards and against OpenSSL =="
if [ "${OSUM_KRYPTO_FAST:-0}" = 1 ]; then
    echo "  (skipped, OSUM_KRYPTO_FAST=1)"
else
    "$PY" tools/krypto/gegen.py vectors ./.probe/koracle \
        > "$TMPD/vec.txt" 2>&1
    for group in blake2b argon2 argon2keyed xts negative; do
        z=$(grep -a -m1 "^$group " "$TMPD/vec.txt")
        g=$(echo "$z" | grep -oE '[0-9]+/[0-9]+' | cut -d/ -f1)
        n=$(echo "$z" | grep -oE '[0-9]+/[0-9]+' | cut -d/ -f2)
        if [ -n "$g" ] && [ "$g" = "$n" ]; then
            ok "$group: $g/$n against the foreign implementation"
        else
            bad "$group: ${g:-?}/${n:-?}"
            grep -a "$group" "$TMPD/vec.txt" | head -3 | sed 's/^/        /'
        fi
    done
fi

if command -v argon2 >/dev/null 2>&1; then
    soll=$(printf 'password' | argon2 somesaltsomesalt -id -t 3 -m 5 -p 4 \
        -l 32 -v 13 -r 2>/dev/null)
    ist=$(echo "argon2id 70617373776f7264 736f6d6573616c74736f6d6573616c74 3 32 4 32" \
        | ./.probe/koracle)
    same "Argon2id t=3 m=32 p=4 against the argon2 command" "$soll" "$ist"
fi

echo "== 4. create, write, REBOOT, unlock, recompute =="
BLOCKS=8192
bash tools/mkfsfi/mkfs.sh build "$TMPD/root.img" "$BLOCKS" \
    /bin/ /proc/ /dev/ > "$TMPD/mkfs.log" 2>&1 \
    && ok "the root disk is up" \
    || bad "mkfs fails"

KP="kryptot=1 kryptom=64 kryptop=1"

run_vm() { # name image cmdline [time limit]
    local name=$1 img=$2 app=$3 limit=${4:-300}
    timeout "$limit" $QEMU_X86 -kernel "$TMPD/k0.mb" -m 512 \
        -append "$app" -serial "file:$TMPD/$name.txt" -display none \
        -no-reboot -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        -drive "file=$img,format=raw,if=ide,index=0" > /dev/null 2>&1
    return 0
}

cp --sparse=always "$TMPD/root.img" "$TMPD/a.img"
run_vm a1 "$TMPD/a.img" "osum nopwr kryptonew kryptotest kryptotree kryptopw=secret $KP"
ksays "$TMPD/a1.txt" "new"      1 "the disk is created"
ksays "$TMPD/a1.txt" "selftest"   1 "the self-test of the computation"
ksays "$TMPD/a1.txt" "fsformat" 1 "the file system on it"
ksays "$TMPD/a1.txt" "header"   1 "the header is still there after formatting"
ksays "$TMPD/a1.txt" "mount"    1 "mounted"
ksays "$TMPD/a1.txt" "tree"     4 "four files written"

run_vm a2 "$TMPD/a.img" "osum nopwr kryptoopen kryptoverify kryptopw=secret $KP"
ksays "$TMPD/a2.txt" "open"    1 "opened with the passphrase after the reboot"
ksays "$TMPD/a2.txt" "fails" 0 "without a failed attempt"
ksays "$TMPD/a2.txt" "mount"  1 "and mounted"

python3 - "$TMPD/soll.txt" <<'PYEOF'
import hashlib, sys
laengen = [100, 700, 5000, 40000]
with open(sys.argv[1], "w") as f:
    for i, n in enumerate(laengen):
        b = bytes(((i * 37 + k * 7 + 3) & 255) for k in range(n))
        f.write("k%d %s\n" % (i, hashlib.sha256(b).hexdigest()))
PYEOF
gut=0
while read -r nm soll; do
    ist=$(grep -a -m1 "krypto: sha ${nm#k} = " "$TMPD/a2.txt" | sed 's/.*= //' \
        | tr -d '\r\000')
    if [ "$ist" = "$soll" ]; then gut=$((gut+1)); fi
done < "$TMPD/soll.txt"
num "SHA-256 of the files match (against hashlib on the host)" "$gut" eq 4

# ------------------------------------------------- 5. die Gegenproben

echo "== 5. the control runs =="
cp --sparse=always "$TMPD/a.img" "$TMPD/b.img"
run_vm b1 "$TMPD/b.img" "osum nopwr kryptoopen kryptowrong kryptoverify kryptopw=secret $KP"
ksays "$TMPD/b1.txt" "open"    0 "the WRONG passphrase does not open"
ksays "$TMPD/b1.txt" "fails" 1 "and is counted"
ksays "$TMPD/b1.txt" "mount"  0 "nothing can be mounted without the key"

cp --sparse=always "$TMPD/a.img" "$TMPD/c.img"
python3 - "$TMPD/c.img" <<'PYEOF'
import sys

with open(sys.argv[1], "r+b") as f:
    f.seek(0x140)
    f.write(b"\xff" * 16)
PYEOF
run_vm c1 "$TMPD/c.img" "osum nopwr kryptoopen kryptoverify kryptopw=secret $KP"
ksays "$TMPD/c1.txt" "open"    0 "a damaged header is rejected"
ksays "$TMPD/c1.txt" "fails" 1 "cleanly, not with garbage"
zb=$(grep -a -m1 'krypto: open=' "$TMPD/b1.txt" | tr -d '\r\000')
zc=$(grep -a -m1 'krypto: open=' "$TMPD/c1.txt" | tr -d '\r\000')
same "wrong passphrase and broken header give the SAME line" "$zb" "$zc"

cp --sparse=always "$TMPD/a.img" "$TMPD/d.img"
run_vm d1 "$TMPD/d.img" "osum nopwr kryptoraw kryptoverify"
ksays "$TMPD/d1.txt" "raw"   1 "the header is found"
ksays "$TMPD/d1.txt" "mount" 0 "but without a passphrase nothing mounts"

echo "== 6. the raw device: what can be seen without a passphrase? =="
"$PY" tools/krypto/gegen.py raw "$TMPD/a.img" > "$TMPD/raw.txt" 2>&1
sed 's/^/        /' "$TMPD/raw.txt"
for s in "OFS superblock" "OFS magic reversed" "NTFS" "FAT"; do
    w=$(grep -a -m1 "raw: sig $s = " "$TMPD/raw.txt" | sed 's/.*= //')
    num "no $s signature in the data area" "${w:-99}" eq 0
done
below7=$(grep -a -m1 'below7=' "$TMPD/raw.txt" | grep -oE 'below7=[0-9]+' | cut -d= -f2)
num "no written sector with entropy below 7.0 bits/byte" "${below7:-99}" eq 0
txt=$(grep -a -m1 'text_runs16=' "$TMPD/raw.txt" | cut -d= -f2)
num "no readable string of 16 or more characters" "${txt:-99}" eq 0

echo "== 7. change the passphrase without touching the data =="
cp --sparse=always "$TMPD/root.img" "$TMPD/e.img"
run_vm e1 "$TMPD/e.img" "osum nopwr kryptonew kryptotree kryptopw=alt $KP"
ksays "$TMPD/e1.txt" "tree" 4 "the tree stands (passphrase 'alt')"
run_vm e2 "$TMPD/e.img" "osum nopwr kryptoopen kryptochange kryptokill kryptopw=alt kryptopw2=neu $KP"
ksays "$TMPD/e2.txt" "change" 1 "slot 1 gets the new passphrase"
ksays "$TMPD/e2.txt" "kill"    1 "slot 0 is erased"
ksays "$TMPD/e2.txt" "slots" 1 "afterwards exactly one slot is used"
run_vm e3 "$TMPD/e.img" "osum nopwr kryptoopen kryptoverify kryptopw=alt $KP"
ksays "$TMPD/e3.txt" "open" 0 "the OLD passphrase opens nothing any more"
run_vm e4 "$TMPD/e.img" "osum nopwr kryptoopen kryptoverify kryptopw=neu $KP"
ksays "$TMPD/e4.txt" "open"   1 "the NEW one opens the same disk"
ksays "$TMPD/e4.txt" "slot" 1 "via slot 1"
ksays "$TMPD/e4.txt" "mount" 1 "mounted"
gut=0
while read -r nm soll; do
    ist=$(grep -a -m1 "krypto: sha ${nm#k} = " "$TMPD/e4.txt" | sed 's/.*= //' \
        | tr -d '\r\000')
    if [ "$ist" = "$soll" ]; then gut=$((gut+1)); fi
done < "$TMPD/soll.txt"
num "the data is unchanged after the change (no sector re-encrypted)" \
    "$gut" eq 4
python3 - "$TMPD/e.img" > "$TMPD/slot0.txt" <<'PYEOF'
import sys
d = open(sys.argv[1], "rb").read(4096)
sl = d[0x100:0x200]
print("null=%d" % (1 if sl == b"\0" * 256 else 0))
PYEOF
ksays "$TMPD/slot0.txt" "null" 1 "the erased slot is zeroed, not just reported empty"

echo "== 8. the control run with foreign eyes, BOTH directions =="

"$PY" tools/krypto/gegen.py read "$TMPD/a.img" secret > "$TMPD/g1.txt" 2>&1
sed 's/^/        /' "$TMPD/g1.txt"
ksays "$TMPD/g1.txt" "sum" 1 "the host considers the header checksum correct"
auf=$(grep -a -m1 '^unlocked: ' "$TMPD/g1.txt" | awk '{print $2}')
num "the host opens the key slot with Argon2id+XTS" "${auf:-0}" eq 1
has "$TMPD/g1.txt" "SFO-MUSO" \
    "and finds the OFS superblock below it (the sector arithmetic is right)"

"$PY" tools/krypto/gegen.py tree "$TMPD/a.img" secret > "$TMPD/g2.txt" 2>&1
sed 's/^/        /' "$TMPD/g2.txt"
g=$(grep -a -m1 'tree: good=' "$TMPD/g2.txt" | grep -oE 'good=[0-9]+' | cut -d= -f2)
num "the host reads ALL four files from the ciphertext" "${g:-0}" eq 4

"$PY" tools/krypto/gegen.py write "$TMPD/f.img" fremdpw 1 64 1 "$BLOCKS" \
    > "$TMPD/g3.txt" 2>&1
has "$TMPD/g3.txt" "wrote:" "the host creates its own carrier"
run_vm f1 "$TMPD/f.img" "osum nopwr kryptoopen kryptofs kryptotree kryptopw=fremdpw $KP"
ksays "$TMPD/f1.txt" "open"      1 "${MARKE_PRODUKT} opens the FOREIGN header"
ksays "$TMPD/f1.txt" "fsformat" 1 "and creates its file system on it"
ksays "$TMPD/f1.txt" "tree"     4 "and writes the four files"
"$PY" tools/krypto/gegen.py tree "$TMPD/f.img" fremdpw > "$TMPD/g4.txt" 2>&1
sed 's/^/        /' "$TMPD/g4.txt"
g=$(grep -a -m1 'tree: good=' "$TMPD/g4.txt" | grep -oE 'good=[0-9]+' | cut -d= -f2)
num "the host reads back what ${MARKE_PRODUKT} wrote to ITS carrier" \
    "${g:-0}" eq 4

if "$PY" tools/krypto/gegen.py read "$TMPD/a.img" falschefalsche \
        > "$TMPD/g5.txt" 2>&1; then
    bad "CONTROL RUN: the host opens with the wrong passphrase"
else
    ok "CONTROL RUN: the host does not open with the wrong passphrase either"
fi

echo "== 8b. control run in the kernel: a flipped ciphertext bit must turn the gate red =="
if bash tools/krypto/tamper.sh > "$TMPD/tamper.txt" 2>&1; then
    ok "$(grep -a '^TAMPER:' "$TMPD/tamper.txt" | tail -1)"
else
    bad "kernel tamper control run"
    tail -8 "$TMPD/tamper.txt" | sed 's/^/        /'
fi

echo "== 9. the user interface =="
if bash tools/check-ui.sh > "$TMPD/ui.txt" 2>&1; then
    ok "check-ui.sh PASSED"
else
    bad "check-ui.sh fails"
    tail -5 "$TMPD/ui.txt" | sed 's/^/        /'
fi

echo
echo "KRYPTO: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
