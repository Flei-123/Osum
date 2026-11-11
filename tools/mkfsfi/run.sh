#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

. tools/lib/firnenv.sh
HOSTOUT="$TMPD/host" bash tools/k11/hostbuild.sh mkfs || { bad "mkfs.fi compile"; exit 1; }
FI="$TMPD/host/mkfs"
PY="python3 $ROOT/tools/osum/mkfs.py"
python3 tools/mkfsfi/brandmap.py "$TMPD/brand.map" || exit 1

W="$TMPD/w"
mkdir -p "$W/assets/x" "$W/plain"
printf 'hello {{PRODUCT}} and {{SLUG}} {{x}} {{{{WEB}} {{VENDOR}}\n' > "$W/plain/a.txt"
printf 'hi {{PRODUCT}} at {{WEB}}\n' > "$W/assets/x/b.txt"
printf 'x\0{{PRODUCT}}' > "$W/plain/bin.dat"
printf 'abc' > "$W/plain/c.txt"
head -c 3000000 /dev/urandom > "$W/plain/big.dat"
printf 'bad {{NOPE}}\n' > "$W/assets/x/bad.txt"
cd "$W"

SPEC="/bin/ /bin/a=plain/a.txt@644:1000:100 /etc/ /etc/b=assets/x/b.txt /etc/e= /etc/c=plain/c.txt@600 /etc/c2@/bin/a /d/ /d/e/ /d/e/f=plain/bin.dat /d/e/g=plain/c.txt@755:5 /m/@700:1:2"
SPEC3="$SPEC /lnk->/bin/a /d/e/lnk2->../f"

same() {
    local name=$1 blocks=$2
    shift 2
    $PY build "$TMPD/py.img" "$blocks" "$@" > "$TMPD/py.out" 2> "$TMPD/py.err"
    local prc=$?
    $FI build "$TMPD/fi.img" "$blocks" --brand="$TMPD/brand.map" "$@" > "$TMPD/fi.out" 2> "$TMPD/fi.err"
    local frc=$?
    if [ $prc -ne 0 ] || [ $frc -ne 0 ]; then bad "$name: exit codes python=$prc firn=$frc"; head -2 "$TMPD/fi.err"; return; fi
    local a b
    a=$(sed "s#$TMPD/py.img#IMG#" "$TMPD/py.out")
    b=$(sed "s#$TMPD/fi.img#IMG#" "$TMPD/fi.out")
    if cmp -s "$TMPD/py.img" "$TMPD/fi.img" && [ "$a" = "$b" ]; then
        ok "$name: image sha256 $(sha256sum < "$TMPD/fi.img" | cut -c1-12) and summary line identical"
    else
        bad "$name: image or summary differs"
        cmp "$TMPD/py.img" "$TMPD/fi.img" | head -1
        [ "$a" = "$b" ] || { echo "$a"; echo "$b"; }
    fi
    cp "$TMPD/py.img" "$TMPD/last.img"
}

same "v2 build" 4000 $SPEC
cp "$TMPD/last.img" "$TMPD/v2.img"
same "v3 build with symlinks" 4000 --v3 $SPEC3
cp "$TMPD/last.img" "$TMPD/v3.img"
same "v1 build" 4000 --v1 /bin/ /bin/a=plain/a.txt /bin/c=plain/c.txt
same "options time reserve journal inodes karten" 6000 --time=1234567 --reserve=50 --journal --inodes=300 --karten=3 $SPEC
same "v2 file too big upgrades to v3" 12000 /bin/ /bin/big=plain/big.dat /bin/c=plain/c.txt
grep -q "building format 3" "$TMPD/fi.err" && ok "upgrade note on stderr" || bad "upgrade note missing"
same "non strict path keeps unknown tokens" 4000 /a=plain/a.txt

for img in v2 v3; do
    n=0
    for cmd in list meta; do
        if [ "$($PY $cmd "$TMPD/$img.img" 2>&1)" = "$($FI $cmd "$TMPD/$img.img" 2>&1)" ]; then n=$((n+1)); fi
    done
    for p in /bin/a /d/e/f /etc/c; do
        for cmd in meta times where; do
            if [ "$($PY $cmd "$TMPD/$img.img" $p 2>&1)" = "$($FI $cmd "$TMPD/$img.img" $p 2>&1)" ]; then n=$((n+1)); fi
        done
        if [ "$($PY cat "$TMPD/$img.img" $p | sha256sum)" = "$($FI cat "$TMPD/$img.img" $p | sha256sum)" ]; then n=$((n+1)); fi
    done
    if [ $n -eq 14 ]; then ok "$img image: list, meta, times, where, cat equal python (14 of 14)"; else bad "$img image: only $n of 14 inspection outputs equal"; fi
done

$FI build "$TMPD/x.img" 4000 --brand="$TMPD/brand.map" /a=assets/x/bad.txt > /dev/null 2> "$TMPD/bad.err"
rc=$?
if [ $rc -ne 0 ] && grep -q "unknown placeholder {{NOPE}}" "$TMPD/bad.err"; then ok "unknown placeholder under assets/ is an error"; else bad "unknown placeholder accepted (rc=$rc)"; fi
$FI build "$TMPD/x.img" 4000 /a=plain/c.txt /a=plain/c.txt > /dev/null 2> "$TMPD/dup.err"
[ $? -ne 0 ] && ok "duplicate name is refused" || bad "duplicate name accepted"
$FI build "$TMPD/x.img" 4000 /lnk->/x > /dev/null 2> "$TMPD/lnk.err"
[ $? -ne 0 ] && ok "symlink below format 3 is refused" || bad "symlink accepted in format 2"

$FI build "$TMPD/n.img" 4000 $SPEC > /dev/null 2>&1
$PY build "$TMPD/p.img" 4000 $SPEC > /dev/null 2>&1
if cmp -s "$TMPD/n.img" "$TMPD/p.img"; then bad "counter-proof: build without brand map still equal"; else ok "counter-proof: build without brand map differs from python"; fi
cp "$TMPD/p.img" "$TMPD/q.img"
printf '\xff' | dd of="$TMPD/q.img" bs=1 seek=40000 conv=notrunc 2>/dev/null
$FI build "$TMPD/n.img" 4000 --brand="$TMPD/brand.map" $SPEC > /dev/null 2>&1
if cmp -s "$TMPD/n.img" "$TMPD/q.img"; then bad "counter-proof: manipulated image compares equal"; else ok "counter-proof: manipulated image is detected"; fi

echo "mkfsfi: $pass ok, $fail fail"
[ $fail -eq 0 ]
