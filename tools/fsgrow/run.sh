#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
OLDREF=${OLDREF:-origin/main}
DEV_MIB=${FSGROW_DEV_MIB:-4096}
BASE_BLOCKS=${FSGROW_BASE_BLOCKS:-32768}
BASE_MAPS=${FSGROW_BASE_MAPS:-8}
BIG_MIB=${FSGROW_BIG_MIB:-200}
MANY=${FSGROW_MANY:-3000}
CUTS=${FSGROW_CUTS:-6}
DIRS=10
PER_DIR=$((MANY / DIRS))
MANY_SCRIPT=$(for d in $(seq 1 $DIRS); do printf "growfill many /m%s %s;" $d $PER_DIR; done)
MANY_SCRIPT=${MANY_SCRIPT%;}
MANYCHECK_SCRIPT=$(for d in $(seq 1 $DIRS); do printf "growfill manycheck /m%s %s;" $d $PER_DIR; done)
MANYCHECK_SCRIPT=${MANYCHECK_SCRIPT%;}
PROGS="sh ls cat echo rm df touch mkdir fsck ota growfill"
TMPD=${FSGROW_DIR:-$(mktemp -d)}
mkdir -p "$TMPD"
trap 'kill $(jobs -p) 2>/dev/null; [ -n "${FSGROW_KEEP:-}" ] || rm -rf "$TMPD"' EXIT
pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() {
    local name=$1 value=$2 op=$3 want=$4
    if [ -z "$value" ]; then bad "$name: no number (expected $op $want)"; return; fi
    if [ "$value" -"$op" "$want" ] 2>/dev/null; then ok "$name: $value"; else bad "$name: $value, expected $op $want"; fi
}
clean() { tr -d '\000' < "$1" 2>/dev/null; }
val() { clean "$1" | grep -a "^$2: $3 = " | tail -1 | sed 's/.* = //'; }
gval() { clean "$1" | grep -a "^grow: $2 " | tail -1 | sed "s/^grow: $2 //"; }
lval() { python3 -I tools/osum/mkfs.py list "$1" | head -1 | tr ' ' '\n' | grep "^$2=" | head -1 | cut -d= -f2 | cut -d/ -f"${3:-1}"; }
badsum() { clean "$1" | grep -a '^growfill: bad' | sed 's/growfill: bad = //' | awk '{s+=$1} END{print s+0}'; }
extend_to() { dd if=/dev/null of="$1" bs=1M seek="$2" count=0 status=none; }

command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "FSGROW: skipped, qemu missing"; exit 0; }
[ -w /dev/kvm ] && KVM_ARGS="-accel kvm -cpu host" || KVM_ARGS="-accel tcg"

build_tree() {
    local root=$1 out=$2
    mkdir -p "$out"
    (cd "$root" && FIRNLIB="$root/lib" bash tools/build-kernel.sh "$out/k.mb" >"$out/build.txt" 2>&1) || return 1
    as --64 -o "$out/crt.o" "$root/kernel/user/crt.s" 2>/dev/null || return 1
    local p spec="/bin/ /tmp/ /dev/ /proc/"
    for p in $PROGS; do
        [ -f "$root/kernel/user/$p.fi" ] || continue
        FIRNLIB="$root/lib" "$root/vendor/firn/bin/firnc" "$root/kernel/user/$p.fi" -o "$out/$p.o" >"$out/e$p" 2>&1 || { echo "compile $p failed"; head -5 "$out/e$p"; return 1; }
        ld -T "$root/kernel/user/user.ld" --defsym=USER_ENTRY="_F0.u_start" -o "$out/$p.elf" "$out/crt.o" "$out/$p.o" 2>/dev/null
        strip --strip-all "$out/$p.elf" 2>/dev/null
        spec="$spec /bin/$p=$out/$p.elf"
    done
    echo "$spec" > "$out/spec.txt"
}

run_guest() {
    local kernel=$1 img=$2 app=$3 out=$4
    timeout ${GUEST_TIMEOUT:-1500} qemu-system-x86_64 $KVM_ARGS -kernel "$kernel" -m 512 -append "osum vfs nokbd $app" \
        -serial "file:$out" -display none -no-reboot \
        -drive "file=$img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
}

run_cut() {
    local kernel=$1 img=$2 app=$3 out=$4 mark=$5 extra=$6
    : > "$out"
    timeout 900 qemu-system-x86_64 $KVM_ARGS -kernel "$kernel" -m 512 -append "osum vfs nokbd $app" \
        -serial "file:$out" -display none -no-reboot \
        -drive "file=$img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local pid=$!
    local n=0
    while kill -0 $pid 2>/dev/null && [ $n -lt 6000 ]; do
        if clean "$out" | grep -aq "$mark"; then
            [ "$extra" != "0" ] && sleep "$extra"
            pkill -9 -P $pid 2>/dev/null; kill -9 $pid 2>/dev/null
            break
        fi
        sleep 0.05
        n=$((n+1))
    done
    wait $pid 2>/dev/null
}

make_base() {
    local out=$1
    python3 -I tools/osum/mkfs.py build "$out" "$BASE_BLOCKS" --v3 --inodes=256 --time=1780000000 --karten=$BASE_MAPS $SPEC "/hello.txt=$TMPD/hello.txt" >"$TMPD/mk.txt" 2>&1 || return 1
    extend_to "$out" "$DEV_MIB"
}

echo "== 1. build =="
printf 'hello grow\n' > "$TMPD/hello.txt"
build_tree "$(pwd)" "$TMPD/new" && ok "kernel and programs built" || { bad "build failed"; tail -5 "$TMPD/new/build.txt" 2>/dev/null | sed 's/^/        /'; echo "FSGROW: $pass passed, $fail failed"; exit 1; }
SPEC=$(cat "$TMPD/new/spec.txt")
K=$TMPD/new/k.mb
make_base "$TMPD/base.img" && ok "base image ${BASE_BLOCKS} blocks, ${BASE_MAPS} map blocks, device ${DEV_MIB} MiB" || bad "mkfs base"

echo "== 2. grow status, grow, df, fsck =="
cp --sparse=always "$TMPD/base.img" "$TMPD/live.img"
run_guest "$K" "$TMPD/live.img" "script=ota system grow status;ota system grow;ota system grow status;df;cat /hello.txt;fsck /dev/hda;exit" "$TMPD/g.txt"
clean "$TMPD/g.txt" > "$TMPD/g.clean"
grep -a "grow:\|fsck: fehler\|hello grow" "$TMPD/g.clean" | head -24 | sed 's/^/        /'
first_state=$(grep -a '^grow: state ' "$TMPD/g.clean" | head -1 | sed 's/.* //')
last_state=$(grep -a '^grow: state ' "$TMPD/g.clean" | tail -1 | sed 's/.* //')
num "state before grow (1 = ready)" "$first_state" eq 1
num "state after grow (3 = done)" "$last_state" eq 3
grep -aq '^grow: done' "$TMPD/g.clean" && ok "grow reported done" || bad "grow did not report done"
num "fs blocks after grow" "$(grep -a '^grow: fs blocks ' "$TMPD/g.clean" | tail -1 | sed 's/.* //')" eq $((DEV_MIB * 2048))
num "ext inodes after grow" "$(grep -a '^grow: ext inodes ' "$TMPD/g.clean" | tail -1 | sed 's/.* //')" gt 1000
num "guest fsck errors after grow" "$(val "$TMPD/g.txt" fsck fehler)" eq 0
grep -aq 'hello grow' "$TMPD/g.clean" && ok "old file readable after grow" || bad "old file unreadable after grow"
num "host: ext flag after grow" "$(lval "$TMPD/live.img" ext)" eq 1
num "host: blocks after grow" "$(lval "$TMPD/live.img" blocks)" eq $((DEV_MIB * 2048))
free_grown=$(lval "$TMPD/live.img" free)
num "host: free blocks after grow" "$free_grown" gt $((DEV_MIB * 2048 * 9 / 10))
python3 tools/fsrobust/check.py struktur "$TMPD/live.img" >"$TMPD/h.txt" 2>&1 && ok "host check.py struktur after grow" || { bad "host check.py struktur after grow"; tail -4 "$TMPD/h.txt" | sed 's/^/        /'; }

[ -n "${FSGROW_STOP:-}" ] && [ "$FSGROW_STOP" -le 2 ] && { echo "FSGROW: $pass passed, $fail failed (stopped)"; exit 0; }
echo "== 3. write a ${BIG_MIB} MiB file and ${MANY} files, reboot, verify =="
t0=$(date +%s)
run_guest "$K" "$TMPD/live.img" "script=growfill big /big.bin $BIG_MIB;$MANY_SCRIPT;df;exit" "$TMPD/w.txt"
t1=$(date +%s)
num "big file bytes written" "$(clean "$TMPD/w.txt" | grep -a '^growfill: wrote' | head -1 | sed 's/.* //')" eq $((BIG_MIB * 1048576))
num "many files written" "$(clean "$TMPD/w.txt" | grep -a '^growfill: wrote' | tail -n +2 | sed 's/.* //' | awk '{s+=$1} END{print s+0}')" eq $MANY
echo "        write phase seconds: $((t1 - t0))"
run_guest "$K" "$TMPD/live.img" "script=growfill bigcheck /big.bin $BIG_MIB;$MANYCHECK_SCRIPT;df;fsck /dev/hda;exit" "$TMPD/r.txt"
clean "$TMPD/r.txt" | grep -a "growfill:\|fsck: \(fehler\|zugross\|blocks\|inodes\|dateien\)" | sed 's/^/        /'
num "big file bad chunks after reboot" "$(clean "$TMPD/r.txt" | grep -a '^growfill: bad' | head -1 | sed 's/.* //')" eq 0
num "many files bad after reboot" "$(clean "$TMPD/r.txt" | grep -a '^growfill: bad' | tail -n +2 | sed 's/.* //' | awk '{s+=$1} END{print s+0}')" eq 0
num "guest fsck errors after writes" "$(val "$TMPD/r.txt" fsck fehler)" eq 0
python3 tools/fsrobust/check.py struktur "$TMPD/live.img" >"$TMPD/h2.txt" 2>&1 && ok "host check.py struktur after writes" || { bad "host check.py struktur after writes"; tail -4 "$TMPD/h2.txt" | sed 's/^/        /'; }
num "host: used inodes" "$(lval "$TMPD/live.img" inodes 1)" ge $((MANY + 3))
num "host: /big.bin lies in the ext zone (first block >= old cover)" "$(python3 -I tools/osum/mkfs.py where "$TMPD/live.img" /big.bin 2>/dev/null | grep -o '[0-9]\+' | awk -v c=$BASE_BLOCKS 'NR>1 && $1>=c {n++} END{print n+0}')" ge 1

echo "== 4. power cuts during grow =="
cutfail=0
for i in $(seq 1 $CUTS); do
    cp --sparse=always "$TMPD/base.img" "$TMPD/cut.img"
    case $i in
        1) mark='permille 100'; delay=0 ;;
        2) mark='permille 500'; delay=0 ;;
        3) mark='permille 900'; delay=0 ;;
        *) mark='permille 900'; delay=0.0$((i * 2)) ;;
    esac
    run_cut "$K" "$TMPD/cut.img" "script=ota system grow;exit" "$TMPD/c$i.txt" "$mark" "$delay"
    xv=$(lval "$TMPD/cut.img" ext)
    python3 tools/fsrobust/check.py struktur "$TMPD/cut.img" >"$TMPD/ch$i.txt" 2>&1 || { bad "cut $i: host check after kill"; cutfail=1; tail -3 "$TMPD/ch$i.txt" | sed 's/^/        /'; }
    run_guest "$K" "$TMPD/cut.img" "script=ota system grow;ota system grow status;growfill big /after.bin 8;growfill bigcheck /after.bin 8;cat /hello.txt;fsck /dev/hda;exit" "$TMPD/cr$i.txt"
    st=$(gval "$TMPD/cr$i.txt" state | tail -1)
    fe=$(val "$TMPD/cr$i.txt" fsck fehler)
    bc=$(clean "$TMPD/cr$i.txt" | grep -a '^growfill: bad' | tail -1 | sed 's/.* //')
    grep -aq 'hello grow' "$TMPD/cr$i.txt" && hh=1 || hh=0
    echo "        cut $i: mark '$mark' +${delay}s, ext after kill=${xv:-0}, resumed state=$st fsck=$fe bad=$bc hello=$hh"
    { [ "$st" = "3" ] && [ "$fe" = "0" ] && [ "$bc" = "0" ] && [ "$hh" = "1" ]; } || cutfail=1
    python3 tools/fsrobust/check.py struktur "$TMPD/cut.img" >"$TMPD/cc$i.txt" 2>&1 || cutfail=1
    num "cut $i: host ext flag after resume" "$(lval "$TMPD/cut.img" ext)" eq 1
done
[ $cutfail -eq 0 ] && ok "all $CUTS power cuts resumed clean (state done, fsck 0, data ok)" || bad "a power cut left damage"

echo "== 5. old kernel on the grown image ($OLDREF) =="
OLDD=$TMPD/oldsrc
mkdir -p "$OLDD"
git archive "$OLDREF" | tar -x -C "$OLDD"
mkdir -p "$OLDD/vendor/firn"
cp -rn vendor/firn/. "$OLDD/vendor/firn/"
if build_tree "$OLDD" "$TMPD/old"; then
    ok "old kernel built"
    make_base "$TMPD/g0.img"
    run_guest "$K" "$TMPD/g0.img" "script=ota system grow;exit" "$TMPD/og.txt"
    run_guest "$TMPD/old/k.mb" "$TMPD/g0.img" "script=cat /hello.txt;echo oldwrite > /old.txt;cat /old.txt;ls /;fsck /dev/hda;exit" "$TMPD/o1.txt"
    clean "$TMPD/o1.txt" | grep -a "hello grow\|oldwrite\|fsck: fehler" | sed 's/^/        /'
    grep -aq 'hello grow' "$TMPD/o1.txt" && ok "old kernel reads the grown image" || bad "old kernel cannot read the grown image"
    grep -aq 'oldwrite' "$TMPD/o1.txt" && ok "old kernel writes on the grown image" || bad "old kernel cannot write on the grown image"
    num "old kernel fsck errors (grown, no ext data)" "$(val "$TMPD/o1.txt" fsck fehler)" eq 0
    run_guest "$K" "$TMPD/g0.img" "script=cat /old.txt;cat /hello.txt;growfill big /n.bin 8;growfill bigcheck /n.bin 8;fsck /dev/hda;exit" "$TMPD/o2.txt"
    grep -aq 'oldwrite' "$TMPD/o2.txt" && ok "new kernel keeps the file the old kernel wrote" || bad "new kernel lost the old kernel's file"
    num "new kernel fsck errors after the old kernel ran" "$(val "$TMPD/o2.txt" fsck fehler)" eq 0
    num "new kernel writes ext data after the old kernel ran (bad chunks)" "$(badsum "$TMPD/o2.txt")" eq 0
    cp --sparse=always "$TMPD/live.img" "$TMPD/oldlive.img"
    run_guest "$TMPD/old/k.mb" "$TMPD/oldlive.img" "script=cat /hello.txt;ls /;exit" "$TMPD/o3.txt"
    grep -aq 'hello grow' "$TMPD/o3.txt" && ok "old kernel boots a grown image with ext data (big file + $MANY files)" || bad "old kernel failed on a grown image with ext data"
    run_guest "$K" "$TMPD/oldlive.img" "script=growfill bigcheck /big.bin $BIG_MIB;$MANYCHECK_SCRIPT;fsck /dev/hda;exit" "$TMPD/o4.txt"
    num "ext data intact after the old kernel only read" "$(badsum "$TMPD/o4.txt")" eq 0
    num "fsck errors after the old kernel only read" "$(val "$TMPD/o4.txt" fsck fehler)" eq 0
else
    bad "old kernel build failed"
fi

echo "== 6. 60 GiB extrapolation =="
if [ "$DEV_MIB" -ge 1024 ]; then
    make_base "$TMPD/t.img"
    ts=$(date +%s.%N)
    run_guest "$K" "$TMPD/t.img" "script=ota system grow;exit" "$TMPD/t.txt"
    te=$(date +%s.%N)
    est=$(python3 -I - "$ts" "$te" "$DEV_MIB" "$BASE_MAPS" <<'PY'
import sys
ts, te, mib, maps = float(sys.argv[1]), float(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
def meta(span):
    bm = (span + 4095) // 4096
    n = min(131072, span // 256)
    n -= n % 2
    return bm + (n + 1) // 2
m = meta(mib * 2048 - maps * 4096)
m60 = meta(60 * 1024 * 2048 - maps * 4096)
secs = te - ts
print("%d MiB: %d meta blocks in %.1f s incl. boot; 60 GiB: %d meta blocks -> about %.0f s here (upper bound)" % (mib, m, secs, m60, secs * m60 / m))
PY
)
    echo "        $est"
    ok "grow duration measured"
fi

echo
echo "FSGROW: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
