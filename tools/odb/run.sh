#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/odb/run.sh -- gate for the ODB debug agent (kernel/user/odbd.fi) driven by the REAL host client
# (tools/odbc), over a QEMU chardev socket on COM2 (docs/ODB.md).
#
# Fast image like tools/sshd/run.sh: kernel + a handful of programs + mkfs.py disk, inittab starts odbd.
# What is proven (each with a control):
#   1. hello/auth + info          control: wrong token is refused (exit 4), no token is refused
#   2. exec (stdout, exit code)   control: unknown program -> nonzero
#   3. push/pull (sha256 + crc)   control: host-side sha256 of the pulled file equals the original
#   4. ps / kill                  control: pid gone after kill
#   5. logs
#   6. reboot, agent comes back
#   7. agent off                  image without the inittab line / conf enable=0: no answer
#   8. latency / throughput numbers (tools/odbc/bench.py against the real odbd)
#
#   bash tools/odb/run.sh                  all of it
#   ODB_KEEP=<dir> bash tools/odb/run.sh   keep the build (kernel, programs) in <dir> for reuse
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
LDSCRIPT=kernel/kernel.ld
ULD=kernel/user/user.ld
PROGS="sh ls cat echo id whoami sleep wc true false seq svc init ps kill reboot shutdown cp rm mkdir mount odbd"
BLOCKS=8192
ODBC="python3 -I $ROOT/tools/odbc/odbc.py"

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
is() { if [ "$2" = "$3" ]; then ok "$1 ($2)"; else bad "$1: '$2', expected '$3'"; fi; }

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "fetch-firnc.sh failed"; exit 1; }
[ -x "$FIRNC" ] || { echo "firnc missing"; exit 1; }
command -v qemu-system-x86_64 >/dev/null || { echo "ODB: skipped, no qemu"; exit 0; }
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then ACCEL="-accel kvm"; else ACCEL="-accel tcg"; fi

# ---------------------------------------------------------------- build
B=${ODB_KEEP:-$TMPD/b}
mkdir -p "$B"
echo "== 1. build: kernel + $(echo $PROGS | wc -w) programs =="
if [ ! -f "$B/k0.mb" ]; then
    for f in boot isr switch smp hv; do
        as --64 -o "$B/$f.o" "kernel/arch/x86_64/$f.s" 2>/dev/null || bad "$f.s does not assemble"
    done
    as --64 -o "$B/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s"
    "$FIRNC" kernel/kmain.fi -o "$B/k.o" >"$B/e" 2>&1 && "$FIRNC" kernel/uprog.fi -o "$B/u.o" >>"$B/e" 2>&1 \
        || { bad "kernel does not compile"; head -8 "$B/e"; echo "ODB: $pass passed, $fail failed"; exit 1; }
    ld -n -T "$LDSCRIPT" --defsym=KERNEL_MAIN="_F0.kernel_main" --defsym=KERNEL_TRAP="_F0.trap__entry" \
        --defsym=KERNEL_SYSCALL="_F0.sys__entry" --defsym=KERNEL_TASK_MAIN="_F0.tasks__main" \
        --defsym=KERNEL_USER_START="_F0.proc__user_start" --defsym=KERNEL_AP_MAIN="_F0.smp__ap_main" \
        --defsym=USER_MAIN="_F0.u_enter" -o "$B/k.elf" "$B/boot.o" "$B/isr.o" "$B/switch.o" "$B/smp.o" "$B/hv.o" \
        "$B/k.o" "$B/u.o" 2>"$B/ld.err" || { bad "ld kernel"; head -5 "$B/ld.err"; exit 1; }
    objcopy -O elf32-i386 "$B/k.elf" "$B/k0.mb" 2>/dev/null
fi
for p in $PROGS; do
    [ -f "$B/$p.elf" ] && continue
    "$FIRNC" "kernel/user/$p.fi" -o "$B/$p.o" >"$B/e$p" 2>&1 \
        || { bad "$p.fi does not compile"; head -6 "$B/e$p" | sed 's/^/        /'; echo "ODB: $pass passed, $fail failed"; exit 1; }
    ld -T "$ULD" --defsym=USER_ENTRY="_F0.u_start" -o "$B/$p.elf" "$B/crt.o" "$B/$p.o" 2>/dev/null || { bad "ld $p"; exit 1; }
    strip --strip-all "$B/$p.elf"
done
ok "built (kernel $(stat -c%s "$B/k0.mb") octets, odbd $(stat -c%s "$B/odbd.elf") octets)"

# ---------------------------------------------------------------- images
TOKEN=$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')
BADTOKEN=$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')
printf '%s' "$TOKEN" > "$TMPD/token"
printf '%s' "$BADTOKEN" > "$TMPD/badtoken"
printf 'root:x:0:0:root:/:/bin/sh\n' > "$TMPD/passwd"
printf 'odbd:respawn:/sbin/odbd\nende:ctrl:/bin/sleep 600\n' > "$TMPD/inittab_on"
printf 'ende:ctrl:/bin/sleep 600\n' > "$TMPD/inittab_off"
printf 'enable=1\n' > "$TMPD/conf_on"
printf 'none /dev devfs\nnone /proc proc\n' > "$TMPD/fstab"
head -c 300000 /dev/urandom > "$TMPD/blob.bin"
BLOBSUM=$(sha256sum "$TMPD/blob.bin" | cut -d' ' -f1)
printf 'line one\nline two\n' > "$TMPD/data.txt"

SPEC=""
for p in $PROGS; do
    case $p in
        init) SPEC="$SPEC /sbin/init=$B/$p.elf@755:0:0" ;;
        odbd) SPEC="$SPEC /sbin/odbd=$B/$p.elf@755:0:0" ;;
        *)    SPEC="$SPEC /bin/$p=$B/$p.elf" ;;
    esac
done
DIRS="/bin/ /sbin/ /etc/ /dev/ /proc/ /run/@755:0:0 /d/ /tmp/@777:0:0"
mkimg() { # out inittab [extra spec...]
    local out=$1 it=$2; shift 2
    python3 tools/osum/mkfs.py build "$out" $BLOCKS $DIRS $SPEC \
        /etc/passwd=$TMPD/passwd@644:0:0 /etc/inittab=$it@644:0:0 \
        /etc/fstab=$TMPD/fstab@644:0:0 /etc/odb.token=$TMPD/token@600:0:0 /etc/odb.conf=$TMPD/conf_on@644:0:0 \
        /d/data.txt=$TMPD/data.txt@644:0:0 "$@" >"$TMPD/mkfs.txt" 2>&1 \
        || { bad "mkfs.py failed"; sed 's/^/        /' "$TMPD/mkfs.txt" | head -5; return 1; }
}
mkimg "$TMPD/on.img" "$TMPD/inittab_on" && mkimg "$TMPD/off.img" "$TMPD/inittab_off" || { echo "ODB: $pass passed, $fail failed"; exit 1; }
ok "images: agent on / agent off"

# ---------------------------------------------------------------- qemu
SOCK="$TMPD/odb.sock"
start_qemu() { # image comlog [extra qemu args]
    local img=$1 log=$2; shift 2
    rm -f "$SOCK"
    timeout 1200 qemu-system-x86_64 $ACCEL -kernel "$B/k0.mb" -m 512 -smp 2 \
        -append "osum vfs nokbd" -display none "$@" \
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

echo "== 2. boot, hello/auth, info ($ACCEL) =="
cp "$TMPD/on.img" "$TMPD/live.img"
T0=$(date +%s%N)
start_qemu "$TMPD/live.img" "$TMPD/com1.log" || { bad "qemu did not start"; exit 1; }
if ODB_T=90 od wait 80 >"$TMPD/wait.txt" 2>&1; then
    ok "agent answers after $(( ($(date +%s%N)-T0)/1000000 )) ms"
else
    bad "agent did not answer"; head -5 "$TMPD/wait.txt"; tr -d '\000' < "$TMPD/com1.log" | tail -15 | sed 's/^/        /'
    echo "ODB: $pass passed, $fail failed"; exit 1
fi
if [ -n "${ODB_HOLD:-}" ]; then   # dev mode: keep the guest up for manual odbc sessions
    echo "HOLD: odbc --port unix:$SOCK --token-file $TMPD/token ... (${ODB_HOLD}s)"
    echo "unix:$SOCK $TMPD/token" > "$B/hold.txt"; cp "$TMPD/token" "$B/hold.token"
    sleep "$ODB_HOLD"; exit 0
fi
od info >"$TMPD/info.txt" 2>&1; rc=$?
is "info exit code" "$rc" "0"
grep -qi "orientos\|osum" "$TMPD/info.txt" && ok "info names the os" || { bad "info: no os name"; head -8 "$TMPD/info.txt"; }
note "$(head -6 "$TMPD/info.txt" | tr '\n' ' ')"
$ODBC --port "unix:$SOCK" --token-file "$TMPD/badtoken" info >/dev/null 2>&1; is "wrong token refused (exit)" "$?" "4"
$ODBC --port "unix:$SOCK" info >/dev/null 2>&1; rc=$?
[ "$rc" != 0 ] && ok "no token refused (exit $rc)" || bad "no token accepted"
od info >/dev/null 2>&1; is "right token still works after refusals" "$?" "0"

echo "== 3. exec =="
out=$(od exec echo hello odb 2>&1); is "exec echo" "$out" "hello odb"
od exec /bin/false >/dev/null 2>&1; rc=$?; [ "$rc" != 0 ] && ok "false -> exit $rc" || bad "false returned 0"
out=$(od exec 'exit 7' 2>&1); rc=$?; is "exit code 7 passes through" "$rc" "7"
od exec /bin/nonexistent-prog >/dev/null 2>&1; rc=$?; [ "$rc" != 0 ] && ok "unknown program -> exit $rc" || bad "unknown program returned 0"
out=$(od exec cat /d/data.txt 2>&1); is "cat data file" "$(echo "$out" | head -1)" "line one"

echo "== 4. push / pull =="
od push "$TMPD/blob.bin" /tmp/blob.bin >"$TMPD/push.txt" 2>&1; is "push exit" "$?" "0"
note "$(tail -1 "$TMPD/push.txt")"
od pull /tmp/blob.bin "$TMPD/back.bin" >"$TMPD/pull.txt" 2>&1; is "pull exit" "$?" "0"
note "$(tail -1 "$TMPD/pull.txt")"
is "pulled sha256 == original" "$(sha256sum "$TMPD/back.bin" 2>/dev/null | cut -d' ' -f1)" "$BLOBSUM"

echo "== 5. ps / kill =="
( ODB_T=40 od exec /bin/sleep 300 >/dev/null 2>&1 & )
sleep 3
od ps >"$TMPD/ps.txt" 2>&1; is "ps exit" "$?" "0"
PID=$(awk '/sleep/ {print $1; exit}' "$TMPD/ps.txt")
if [ -n "$PID" ]; then
    ok "sleep visible in ps (pid $PID)"
    od kill "$PID" >/dev/null 2>&1; is "kill exit" "$?" "0"
    sleep 1
    od ps 2>&1 | awk -v p="$PID" '$1==p' | grep -q sleep && bad "pid $PID still there" || ok "pid $PID gone"
else
    bad "no sleep in ps"; head -12 "$TMPD/ps.txt" | sed 's/^/        /'
fi

echo "== 6. logs =="
out=$(od logs -n 20 2>&1); rc=$?
is "logs exit" "$rc" "0"
[ -n "$out" ] && ok "logs not empty ($(echo "$out" | wc -l) lines)" || bad "logs empty"

echo "== 7. numbers (bench.py against the real odbd) =="
timeout 120 python3 -I tools/odbc/bench.py --port "unix:$SOCK" --token-file "$TMPD/token" --mib 1 >"$TMPD/bench.txt" 2>&1 \
    && ok "bench ran" || bad "bench failed"
tail -8 "$TMPD/bench.txt" | sed 's/^/        /'

echo "== 8. reboot =="
ODB_T=30 od reboot >/dev/null 2>&1; note "reboot exit $?"
sleep 3
if ODB_T=90 od wait 80 >/dev/null 2>&1; then ok "agent back after guest reboot"; else bad "agent not back after guest reboot"; fi
stop_qemu

echo "== 9. agent off =="
cp "$TMPD/off.img" "$TMPD/live.img"
start_qemu "$TMPD/live.img" "$TMPD/com1c.log" || bad "qemu (off)"
ODB_T=25 od wait 15 >/dev/null 2>&1; rc=$?
[ "$rc" != 0 ] && ok "image without odbd: no answer (exit $rc)" || bad "answer from an image without odbd"
stop_qemu

echo "ODB: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
