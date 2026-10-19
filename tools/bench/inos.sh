#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/bench/inos.sh -- gate for the in-OS benchmark tool (kernel/user/bench.fi + /proc/bench).
#
# Fast image like tools/odb/run.sh: kernel + a few programs + bench, odbd on COM2. The host runs
# `odbc exec bench --json`, takes the `BENCHJSON {...}` line and checks it (tools/bench/check_inos.py):
#   1. schema 1, commit is 8 hex, every required key present and a number
#   2. plausibility (ranges that only a broken measurement misses)
#   3. counter-proof A: the checker rejects doctored JSON (missing key, zero, string, schema, huge)
#   4. counter-proof B: the same bench binary on a kernel WITHOUT /proc/bench -> checker red
#
#   bash tools/bench/inos.sh                    all of it
#   BENCH_KEEP=<dir> bash tools/bench/inos.sh   keep kernels/programs in <dir> for reuse
#   BENCH_OLD_REF=<git ref>                     kernel source for counter-proof B (default: parent of the commit
#                                               that added kernel/user/bench.fi)
#   BENCH_JSON_OUT=<file>                       keep the BENCHJSON of the real run
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
PROGS="sh ls cat echo id whoami sleep wc true false seq svc init ps kill reboot shutdown cp rm mkdir mount odbd bench"
BLOCKS=16384
ODBC="python3 -I $ROOT/tools/odbc/odbc.py"
CHECK="python3 -I $ROOT/tools/bench/check_inos.py --allow-unknown-commit"

TMPD=$(mktemp -d)
QPID=""
cleanup() {
    [ -n "$QPID" ] && kill "$QPID" 2>/dev/null
    rm -rf "$TMPD"
}
trap cleanup EXIT

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }
finish() { echo "BENCH-INOS: $pass passed, $fail failed"; [ "$fail" = 0 ]; exit $?; }

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "fetch-firnc.sh failed"; exit 1; }
[ -x "$FIRNC" ] || { echo "firnc missing"; exit 1; }
command -v qemu-system-x86_64 >/dev/null || { echo "BENCH-INOS: skipped, no qemu"; exit 0; }
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then ACCEL="-accel kvm"; else ACCEL="-accel tcg"; fi

# ---------------------------------------------------------------- build
B=${BENCH_KEEP:-$TMPD/b}
mkdir -p "$B"

build_kernel() { # srcroot out.mb
    local src=$1 out=$2 w
    w=$(mktemp -d "$TMPD/bk.XXXXXX")
    ( cd "$src" || exit 1
      for f in boot isr switch smp hv; do as --64 -o "$w/$f.o" "kernel/arch/x86_64/$f.s" 2>/dev/null || exit 1; done
      FIRNLIB="$src/lib" "$ROOT/$FIRNC" kernel/kmain.fi -o "$w/k.o" >"$w/e" 2>&1 \
          && FIRNLIB="$src/lib" "$ROOT/$FIRNC" kernel/uprog.fi -o "$w/u.o" >>"$w/e" 2>&1 || { head -8 "$w/e"; exit 1; }
      ld -n -T kernel/kernel.ld --defsym=KERNEL_MAIN="_F0.kernel_main" --defsym=KERNEL_TRAP="_F0.trap__entry" \
          --defsym=KERNEL_SYSCALL="_F0.sys__entry" --defsym=KERNEL_TASK_MAIN="_F0.tasks__main" \
          --defsym=KERNEL_USER_START="_F0.proc__user_start" --defsym=KERNEL_AP_MAIN="_F0.smp__ap_main" \
          --defsym=USER_MAIN="_F0.u_enter" -o "$w/k.elf" "$w/boot.o" "$w/isr.o" "$w/switch.o" "$w/smp.o" "$w/hv.o" \
          "$w/k.o" "$w/u.o" 2>"$w/ld.err" || { head -5 "$w/ld.err"; exit 1; }
      objcopy -O elf32-i386 "$w/k.elf" "$out" 2>/dev/null )
}

echo "== 1. build: kernel + $(echo $PROGS | wc -w) programs =="
if [ ! -f "$B/k0.mb" ]; then
    build_kernel "$ROOT" "$B/k0.mb" || { bad "kernel does not compile"; finish; }
fi
as --64 -o "$B/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s"
for p in $PROGS; do
    [ -f "$B/$p.elf" ] && continue
    "$FIRNC" "kernel/user/$p.fi" -o "$B/$p.o" >"$B/e$p" 2>&1 \
        || { bad "$p.fi does not compile"; head -6 "$B/e$p" | sed 's/^/        /'; finish; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" -o "$B/$p.elf" "$B/crt.o" "$B/$p.o" 2>/dev/null || { bad "ld $p"; finish; }
    strip --strip-all "$B/$p.elf"
done
ok "built (kernel $(stat -c%s "$B/k0.mb") octets, bench $(stat -c%s "$B/bench.elf") octets)"

# kernel without /proc/bench (counter-proof B)
if [ ! -f "$B/kold.mb" ]; then
    OLDREF=${BENCH_OLD_REF:-}
    if [ -z "$OLDREF" ]; then
        addc=$(git log --format=%H --max-count=1 --diff-filter=A -- kernel/user/bench.fi 2>/dev/null)
        [ -n "$addc" ] && OLDREF=$(git rev-parse "$addc^" 2>/dev/null)
    fi
    if [ -n "$OLDREF" ]; then
        mkdir -p "$TMPD/old"
        git archive "$OLDREF" kernel lib 2>/dev/null | tar -x -C "$TMPD/old" 2>/dev/null
        build_kernel "$TMPD/old" "$B/kold.mb" >"$TMPD/old.err" 2>&1 || { bad "old kernel does not compile"; head -5 "$TMPD/old.err"; }
    fi
fi

# ---------------------------------------------------------------- image
TOKEN=$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')
printf '%s' "$TOKEN" > "$TMPD/token"
printf 'root:x:0:0:root:/:/bin/sh\n' > "$TMPD/passwd"
printf 'odbd:respawn:/sbin/odbd\nende:ctrl:/bin/sleep 600\n' > "$TMPD/inittab"
printf 'enable=1\n' > "$TMPD/conf_on"
printf 'none /dev devfs\nnone /proc proc\n' > "$TMPD/fstab"
SPEC=""
for p in $PROGS; do
    case $p in
        init) SPEC="$SPEC /sbin/init=$B/$p.elf@755:0:0" ;;
        odbd) SPEC="$SPEC /sbin/odbd=$B/$p.elf@755:0:0" ;;
        *)    SPEC="$SPEC /bin/$p=$B/$p.elf" ;;
    esac
done
DIRS="/bin/ /sbin/ /etc/ /dev/ /proc/ /run/@755:0:0 /d/ /tmp/@777:0:0 /var/ /var/crash/"
python3 tools/osum/mkfs.py build "$TMPD/on.img" $BLOCKS $DIRS $SPEC \
    /etc/passwd=$TMPD/passwd@644:0:0 /etc/inittab=$TMPD/inittab@644:0:0 \
    /etc/fstab=$TMPD/fstab@644:0:0 /etc/odb.token=$TMPD/token@600:0:0 /etc/odb.conf=$TMPD/conf_on@644:0:0 \
    >"$TMPD/mkfs.txt" 2>&1 || { bad "mkfs.py failed"; head -5 "$TMPD/mkfs.txt"; finish; }

# ---------------------------------------------------------------- qemu
SOCK="$TMPD/odb.sock"
start_qemu() { # kernel image comlog
    local k=$1 img=$2 log=$3
    rm -f "$SOCK"
    timeout 900 qemu-system-x86_64 $ACCEL -kernel "$k" -m 512 -smp 2 \
        -append "osum vfs nokbd" -display none \
        -drive "file=$img,format=raw,if=ide,index=0" \
        -serial "file:$log" \
        -chardev "socket,id=odb,path=$SOCK,server=on,wait=off" -serial chardev:odb \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    QPID=$!
    local i=0
    while [ $i -lt 50 ] && [ ! -S "$SOCK" ]; do sleep 0.1; i=$((i+1)); done
    [ -S "$SOCK" ]
}
stop_qemu() { [ -n "$QPID" ] && kill "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null; QPID=""; }
od() { timeout "${ODB_T:-60}" $ODBC --port "unix:$SOCK" --token-file "$TMPD/token" "$@"; }

# run_bench kernel tag -> $TMPD/<tag>.json holds the BENCHJSON payload; rc 0 = line received, 1 = setup failure, 2 = no line
run_bench() {
    local k=$1 tag=$2
    cp "$TMPD/on.img" "$TMPD/$tag.img"
    start_qemu "$k" "$TMPD/$tag.img" "$TMPD/$tag.com1" || { bad "$tag: qemu did not start"; return 1; }
    if ! ODB_T=90 od wait 80 >"$TMPD/$tag.wait" 2>&1; then
        bad "$tag: agent did not answer"; tr -d '\000' < "$TMPD/$tag.com1" | tail -10 | sed 's/^/        /'
        stop_qemu; return 1
    fi
    if [ -n "${BENCH_HOLD:-}" ]; then   # dev mode: keep the guest up for manual odbc sessions
        echo "HOLD: odbc --port unix:$SOCK --token-file $TMPD/token ... (${BENCH_HOLD}s)"
        sleep "$BENCH_HOLD"
    fi
    ODB_T=240 od exec "bench --json" >"$TMPD/$tag.out" 2>&1
    stop_qemu
    grep -a '^BENCHJSON ' "$TMPD/$tag.out" | tail -1 | sed 's/^BENCHJSON //' > "$TMPD/$tag.json"
    [ -s "$TMPD/$tag.json" ] || return 2
    return 0
}

echo "== 2. bench on the real kernel ($ACCEL) =="
run_bench "$B/k0.mb" new; rc=$?
if [ "$rc" = 0 ]; then
    ok "BENCHJSON line received ($(wc -c < "$TMPD/new.json") octets)"
    $CHECK "$TMPD/new.json" >"$TMPD/new.chk" 2>&1; rc=$?
    sed 's/^/        /' "$TMPD/new.chk" | head -60
    [ "$rc" = 0 ] && ok "required keys + plausibility" || bad "checker red on the real kernel"
    [ -n "${BENCH_JSON_OUT:-}" ] && cp "$TMPD/new.json" "$BENCH_JSON_OUT"
elif [ "$rc" = 2 ]; then
    bad "no BENCHJSON line"; tail -c 800 "$TMPD/new.out" | sed 's/^/        /'
fi

echo "== 3. counter-proof A: checker rejects doctored JSON =="
if [ -s "$TMPD/new.json" ]; then
    python3 -I - "$TMPD/new.json" "$TMPD" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1])); t = sys.argv[2]
def w(name, f):
    x = json.loads(json.dumps(d)); f(x); json.dump(x, open(t + "/bad_" + name + ".json", "w"))
w("nokey", lambda x: x["results"].pop("boot.init_ms", None))
w("zero", lambda x: x["results"].__setitem__("syscall.getpid_ns", 0))
w("str", lambda x: x["results"].__setitem__("mem.total_kib", "many"))
w("schema", lambda x: x.__setitem__("schema", 2))
w("huge", lambda x: x["results"].__setitem__("cpu.int_mops", 1e12))
PYEOF
    for c in nokey zero str schema huge; do
        if $CHECK "$TMPD/bad_$c.json" >/dev/null 2>&1; then bad "checker accepted doctored '$c'"; else ok "checker rejects doctored '$c'"; fi
    done
else
    bad "no JSON to doctor"
fi

echo "== 4. counter-proof B: kernel without /proc/bench =="
if [ -f "$B/kold.mb" ]; then
    run_bench "$B/kold.mb" old; rc=$?
    if [ "$rc" = 0 ]; then
        if $CHECK "$TMPD/old.json" >"$TMPD/old.chk" 2>&1; then bad "checker green on a kernel without /proc/bench"
        else ok "checker red on the old kernel ($(grep -c . "$TMPD/old.chk") problem lines)"; fi
    elif [ "$rc" = 2 ]; then
        ok "old kernel: no BENCHJSON at all (bench refuses without /proc/bench)"
    fi
else
    bad "no old kernel for counter-proof B (set BENCH_OLD_REF)"
fi
finish
