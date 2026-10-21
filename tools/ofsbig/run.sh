#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
ULD=kernel/user/user.ld
OLDREF=${OLDREF:-7c767dae}
BLOCKS=${OFSBIG_FILE_BLOCKS:-280000}
FSBLOCKS=${OFSBIG_FS_BLOCKS:-300000}
PROGS="sh ls cat echo rm df touch mkdir fsrquad fsck"
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() {
    local name=$1 value=$2 op=$3 want=$4
    if [ -z "$value" ]; then bad "$name: no number (expected $op $want)"; return; fi
    if [ "$value" -"$op" "$want" ] 2>/dev/null; then ok "$name: $value"; else bad "$name: $value, expected $op $want"; fi
}
val() { tr -d '\000' < "$1" 2>/dev/null | grep -a "^$2: $3 = " | head -1 | sed 's/.* = //'; }

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "fetch-firnc.sh failed"; exit 1; }
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "OFSBIG: skipped, qemu missing"; exit 0; }

echo "== 1. build =="
bash tools/build-kernel.sh "$TMPD/k.mb" >"$TMPD/build.txt" 2>&1 \
    && ok "kernel built" \
    || { bad "kernel build failed"; tail -8 "$TMPD/build.txt" | sed 's/^/        /'; echo "OFSBIG: $pass passed, $fail failed"; exit 1; }
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s"
SPEC="/bin/ /tmp/ /dev/ /proc/"
for p in $PROGS; do
    "$FIRNC" "kernel/user/$p.fi" -o "$TMPD/$p.o" >"$TMPD/e$p" 2>&1 || { bad "$p.fi does not compile"; head -6 "$TMPD/e$p" | sed 's/^/        /'; }
    ld -T "$ULD" --defsym=USER_ENTRY="_F0.u_start" -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null
    strip --strip-all "$TMPD/$p.elf" 2>/dev/null
    SPEC="$SPEC /bin/$p=$TMPD/$p.elf"
done
python3 -I - "$TMPD/big.bin" "$BLOCKS" <<'PY'
import sys
out, n = sys.argv[1], int(sys.argv[2])
with open(out, "wb") as f:
    for b in range(n):
        f.write(bytes([(b * 31 + (b >> 8)) & 255]) * 512)
PY
python3 tools/osum/mkfs.py build "$TMPD/big.img" "$FSBLOCKS" --v3 --inodes=256 --time=1780000000 $SPEC "/big.bin=$TMPD/big.bin" > "$TMPD/mk.txt" 2>&1 \
    && ok "mkfs wrote a $BLOCKS-block file ($((BLOCKS * 512)) bytes)" \
    || { bad "mkfs failed on the big file"; tail -3 "$TMPD/mk.txt" | sed 's/^/        /'; }
grep -qa 'maxfile=8726286336' "$TMPD/mk.txt" && ok "mkfs reports maxfile=8726286336" || bad "mkfs maxfile line missing"
cp --sparse=always "$TMPD/big.img" "$TMPD/live.img"

run_guest() {
    local kernel=$1 img=$2 app=$3 out=$4
    timeout 900 qemu-system-x86_64 ${KVM_ARGS:-} -kernel "$kernel" -m 512 -append "osum vfs nokbd $app" \
        -serial "file:$out" -display none -no-reboot \
        -drive "file=$img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
}
[ -w /dev/kvm ] && KVM_ARGS="-accel kvm -cpu host" || KVM_ARGS="-accel tcg"

echo "== 2. read a file that crosses the old 130 MiB limit =="
run_guest "$TMPD/k.mb" "$TMPD/live.img" "script=fsrquad sample /big.bin $BLOCKS;exit" "$TMPD/s.txt"
num "file opened" "$(val "$TMPD/s.txt" fsrquad open)" eq 1
num "sampled blocks" "$(val "$TMPD/s.txt" fsrquad samples)" ge 30000
num "sampled blocks with wrong content" "$(val "$TMPD/s.txt" fsrquad bad)" eq 0

echo "== 3. write, read back and free the quad levels =="
run_guest "$TMPD/k.mb" "$TMPD/live.img" "script=fsrquad;exit" "$TMPD/w.txt"
num "far writes accepted" "$(val "$TMPD/w.txt" fsrquad wrote)" eq 8
num "far reads match" "$(val "$TMPD/w.txt" fsrquad match)" eq 8
num "write past the last block refused" "$(val "$TMPD/w.txt" fsrquad over)" eq 0
b0=$(val "$TMPD/w.txt" fsrquad before)
b1=$(val "$TMPD/w.txt" fsrquad during)
b2=$(val "$TMPD/w.txt" fsrquad after)
num "blocks taken by the sparse file" "$((b0 - ${b1:-0}))" ge 20
num "free blocks after unlink minus before" "$((${b2:-0} - ${b0:-0}))" eq 0

echo "== 4. fsck in the guest and on the host =="
cp --sparse=always "$TMPD/big.img" "$TMPD/fsck.img"
run_guest "$TMPD/k.mb" "$TMPD/fsck.img" "script=fsck /dev/hda;exit" "$TMPD/f.txt"
num "guest fsck errors" "$(val "$TMPD/f.txt" fsck fehler)" eq 0
python3 tools/fsrobust/check.py struktur "$TMPD/live.img" > "$TMPD/h.txt" 2>&1
tail -2 "$TMPD/h.txt" | sed 's/^/        /'
python3 tools/fsrobust/check.py struktur "$TMPD/live.img" >/dev/null 2>&1 && ok "host check.py struktur after the write test" || bad "host check.py struktur"

echo "== 5. counter-proofs on the old code ($OLDREF) =="
mkdir -p "$TMPD/old"
git archive "$OLDREF" | tar -x -C "$TMPD/old"
cp -rn vendor/firn/. "$TMPD/old/vendor/firn/"
python3 "$TMPD/old/tools/osum/mkfs.py" build "$TMPD/oldbig.img" "$FSBLOCKS" --v3 --inodes=256 --time=1780000000 $SPEC "/big.bin=$TMPD/big.bin" > "$TMPD/oldmk.txt" 2>&1
[ $? -ne 0 ] && ok "the old mkfs refuses the big file" || bad "the old mkfs accepted the big file"
FIRNLIB="$TMPD/old/lib" bash -c "cd $TMPD/old && bash tools/build-kernel.sh $TMPD/old.mb" >"$TMPD/oldbuild.txt" 2>&1 || { bad "old kernel build failed"; tail -4 "$TMPD/oldbuild.txt" | sed 's/^/        /'; }
if [ -f "$TMPD/old.mb" ]; then
    cp --sparse=always "$TMPD/big.img" "$TMPD/oldlive.img"
    run_guest "$TMPD/old.mb" "$TMPD/oldlive.img" "script=fsrquad sample /big.bin $BLOCKS;exit" "$TMPD/os.txt"
    num "old kernel: wrong blocks in the same image" "$(val "$TMPD/os.txt" fsrquad bad)" gt 0
fi

echo
echo "OFSBIG: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
