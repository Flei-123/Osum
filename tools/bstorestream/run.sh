#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
. tools/lib/firnenv.sh
BLOCKS=${BSTORE_BLOCKS:-196608}
BIG_BYTES=${BSTORE_BIG_BYTES:-6291456}

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
is()  { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', expected '$3'"; fi; }
field() { sed -n "/^==$1==/,/^==/p" "$TMPD/run.txt" | grep -a "^$2: " | tail -1 | sed "s/^$2: //"; }

[ -x "$FIRNC" ] || { echo "missing compiler: $FIRNC"; exit 1; }
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "bstorestream: skipped, qemu-system-x86_64 missing"; exit 0; }

if [ "${BSTORE_OLD:-}" = "1" ]; then
    mkdir -p "$TMPD/oldtree"
    git archive "${BSTORE_OLD_REV:-3d1de1197}" kernel | tar -x -C "$TMPD/oldtree"
    cp "$TMPD/oldtree/kernel/user/bstore.fi" "$TMPD/bstore.fi.old"
    cp kernel/user/bstore.fi "$TMPD/bstore.fi.new"
    cp "$TMPD/bstore.fi.old" kernel/user/bstore.fi
    trap 'cp "$TMPD/bstore.fi.new" kernel/user/bstore.fi; rm -rf "$TMPD"' EXIT
fi

echo "== 1. build =="
PROGS="sh ls cat echo backup"
bash tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/b0.txt" 2>&1 \
    && ok "kernel builds" || { bad "kernel build failed"; tail -5 "$TMPD/b0.txt"; }
bash tools/vault/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/bprog.txt" 2>&1 \
    && ok "programs build" || { bad "program build failed"; head -10 "$TMPD/bprog.txt"; }
if [ "${BSTORE_OLD:-}" = "1" ]; then
    cp "$TMPD/bstore.fi.new" kernel/user/bstore.fi
fi
[ -f "$TMPD/k0.img" ] && [ -f "$TMPD/bin/backup.elf" ] || { echo "bstorestream: $pass passed, $((fail+1)) failed"; exit 1; }

echo "== 2. data =="
mkdir -p "$TMPD/src" "$TMPD/rest"
python3 - "$TMPD/src" "$BIG_BYTES" <<'PY'
import random
import sys
out = sys.argv[1]
size = int(sys.argv[2])
rng = random.Random(20261101)
big = rng.randbytes(size)
open(out + "/big.bin", "wb").write(big)
open(out + "/dup.bin", "wb").write(big[:1048576])
open(out + "/tail.bin", "wb").write(big[:size - 100])
open(out + "/small.txt", "wb").write(b"hello stream\n")
open(out + "/empty.bin", "wb").write(b"")
PY
cat > "$TMPD/t_run.sh" <<'EOS'
echo ==RUN1==
backup save /d /store s1
echo ==RUN2==
backup save /d /store s2
echo ==VERIFY==
backup verify /store s1
echo ==RESTORE==
backup restore /store s1 /out
echo ==GET==
backup get /store s1 /big.bin /got.bin
echo ==LIST==
backup list /store
echo ==END==
EOS
cat > "$TMPD/t_bad.sh" <<'EOS'
echo ==VERIFY==
backup verify /store s1
echo ==END==
EOS
bash tools/mkfsfi/mkfs.sh build "$TMPD/disk.img" $BLOCKS /bin/ /t/ /d/ /store/ /out/ /proc/ /dev/ \
    /bin/sh="$TMPD/bin/sh.elf" /bin/cat="$TMPD/bin/cat.elf" /bin/echo="$TMPD/bin/echo.elf" \
    /bin/ls="$TMPD/bin/ls.elf" /bin/backup="$TMPD/bin/backup.elf" \
    /d/big.bin="$TMPD/src/big.bin" /d/dup.bin="$TMPD/src/dup.bin" /d/tail.bin="$TMPD/src/tail.bin" \
    /d/small.txt="$TMPD/src/small.txt" /d/empty.bin= \
    /t/run.sh="$TMPD/t_run.sh" /t/bad.sh="$TMPD/t_bad.sh" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "image holds a $BIG_BYTES octet file" || { bad "mkfs failed"; tail -3 "$TMPD/mkfs.txt"; }

guest() {
    local name=$1 script=$2
    timeout "${BSTORE_TIMEOUT:-1500}" $QEMU_X86 -kernel "$TMPD/k0.img" -m 256 \
        -append "osum vfs nokbd script=sh $script;exit" -serial "file:$TMPD/$name.txt" -display none \
        -no-reboot -drive "file=$TMPD/disk.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    echo $?
}

echo "== 3. guest run: save twice, verify, restore, get =="
rc=$(guest run /t/run.sh)
cp "$TMPD/run.txt" "$TMPD/run.keep" 2>/dev/null
is "guest exits cleanly" "$rc" "21"

chunks=$(( (BIG_BYTES + 4095) / 4096 ))
is "run 1 files" "$(field RUN1 files)" "5"
tail_chunks=$(( (BIG_BYTES - 100 + 4095) / 4096 ))
is "run 1 stores the distinct chunks only" "$(field RUN1 'new chunks')" "$(( chunks + 2 ))"
is "run 1 sees every chunk reference" "$(field RUN1 chunks)" "$(( chunks + 256 + tail_chunks + 1 ))"
is "run 2 writes no new chunk" "$(field RUN2 'new chunks')" "0"
is "verify checks every chunk reference" "$(field VERIFY 'chunks checked')" "$(( chunks + 256 + tail_chunks + 1 ))"
is "verify finds nothing corrupt" "$(field VERIFY corrupt)" "0"
is "verify finds nothing missing" "$(field VERIFY missing)" "0"
is "restore brings back 5 files" "$(field RESTORE 'restored files')" "5"
grep -qa "too many chunks" "$TMPD/run.txt" && bad "store reports too many chunks" || ok "no chunk limit error"
grep -qa "line is too long" "$TMPD/run.txt" && bad "snapshot line too long reported" || ok "no line length error"

echo "== 4. host checks of the snapshot and the restored files =="
python3 tools/bstorestream/oracle.py "$TMPD/disk.img" /store/S-s1 "$TMPD/src" > "$TMPD/oracle.txt" 2>&1
sed 's/^/        /' "$TMPD/oracle.txt" | head -8
is "snapshot header" "$(grep -a '^header=' "$TMPD/oracle.txt")" "header=backup2"
is "snapshot has its end line" "$(grep -a '^ended=' "$TMPD/oracle.txt")" "ended=1"
cont=$(grep -a '^continuation_lines=' "$TMPD/oracle.txt" | sed 's/.*=//')
[ "${cont:-0}" -ge $(( chunks / 256 - 1 )) ] && ok "big file continues over $cont lines" || bad "too few continuation lines: $cont"
longest=$(grep -a '^longest_line=' "$TMPD/oracle.txt" | sed 's/.*=//')
[ "${longest:-999999}" -le 20000 ] && ok "longest snapshot line $longest octets" || bad "longest line $longest"
is "every hash list equals the SHA-256 chunk names of the source" "$(grep -a '^entries_match=' "$TMPD/oracle.txt")" "entries_match=5/5"

python3 - "$TMPD/disk.img" "$TMPD/src" > "$TMPD/compare.txt" 2>&1 <<'PY'
import os, subprocess, sys
img, src = sys.argv[1], sys.argv[2]
def cat(p):
    r = subprocess.run(["bash", "tools/mkfsfi/mkfs.sh", "cat", img, p], capture_output=True)
    return r.stdout if r.returncode == 0 else None
same = 0
pairs = [("/out/" + n, os.path.join(src, n)) for n in os.listdir(src)] + [("/got.bin", os.path.join(src, "big.bin"))]
for guest, host in pairs:
    if cat(guest) == open(host, "rb").read():
        same += 1
    else:
        print("DIFFERENT", guest)
print("compared=%d same=%d" % (len(pairs), same))
PY
sed 's/^/        /' "$TMPD/compare.txt" | grep -v '^        compared=' | head -5
is "restored tree and get are octet for octet the source" "$(grep -a '^compared=' "$TMPD/compare.txt")" "compared=6 same=6"

echo "== 5. counter-proof: one flipped octet in the pack =="
python3 tools/vault/corrupt.py "$TMPD/disk.img" /store/PACK 3000000 > "$TMPD/flip.txt" 2>&1 \
    && ok "pack octet flipped on the host" || bad "corrupt.py failed"
mv "$TMPD/run.txt" "$TMPD/run1.txt"
rc=$(guest run /t/bad.sh)
is "guest exits cleanly" "$rc" "21"
is "verify notices the flipped octet in both files that name the chunk" "$(field VERIFY corrupt)" "2"

echo "bstorestream: $pass passed, $fail failed"
[ "$fail" = 0 ]
