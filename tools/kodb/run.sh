#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/marke-env.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
ULD=kernel/user/user.ld
PROGS="sh ls cat echo sleep svc init"
BLOCKS=8192
ODBC="python3 -I $ROOT/tools/odbc/odbc.py"
TMPD=$(mktemp -d)
QPID=""
cleanup() { [ -n "$QPID" ] && kill "$QPID" 2>/dev/null; rm -rf "$TMPD"; }
trap cleanup EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { if grep -q -- "$2" "$3"; then ok "$1"; else bad "$1 (missing '$2')"; head -5 "$3" | sed 's/^/        /'; fi; }

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "fetch-firnc.sh failed"; exit 1; }
command -v qemu-system-x86_64 >/dev/null || { echo "kodb: skipped, no qemu"; exit 0; }
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then ACCEL="-accel kvm"; else ACCEL="-accel tcg"; fi

B=${KODB_KEEP:-$TMPD/b}
mkdir -p "$B"
echo "== 1. build =="
as --64 -o "$B/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s"
[ -f "$B/k0.mb" ] || ./tools/build-kernel.sh "$B/k0.mb" --stufe 0 >"$B/e" 2>&1 \
    || { bad "kernel does not compile"; tail -8 "$B/e"; echo "kodb: $pass passed, $fail failed"; exit 1; }
for p in $PROGS; do
    [ -f "$B/$p.elf" ] && continue
    "$FIRNC" "kernel/user/$p.fi" -o "$B/$p.o" >"$B/e$p" 2>&1 || { bad "$p.fi does not compile"; head -6 "$B/e$p"; exit 1; }
    ld -T "$ULD" --defsym=USER_ENTRY="_F0.u_start" -o "$B/$p.elf" "$B/crt.o" "$B/$p.o" 2>/dev/null || { bad "ld $p"; exit 1; }
    strip --strip-all "$B/$p.elf"
done
ok "built"

TOKEN=$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')
BADTOKEN=$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')
printf '%s' "$TOKEN" > "$TMPD/token"
printf '%s' "$BADTOKEN" > "$TMPD/badtoken"
printf 'root:x:0:0:root:/:/bin/sh\n' > "$TMPD/passwd"
printf 'vic:respawn:/bin/victim 600\nende:ctrl:/bin/sleep 600\n' > "$TMPD/inittab"
printf 'none /dev devfs\nnone /proc proc\n' > "$TMPD/fstab"
printf 'kodb-file-line-1\nkodb-file-line-2\n' > "$TMPD/note.txt"
SPEC=""
for p in $PROGS; do
    case $p in
        init) SPEC="$SPEC /sbin/init=$B/$p.elf@755:0:0" ;;
        *)    SPEC="$SPEC /bin/$p=$B/$p.elf" ;;
    esac
done
SPEC="$SPEC /bin/victim=$B/sleep.elf"
python3 tools/osum/mkfs.py build "$TMPD/disk.img" $BLOCKS /bin/ /sbin/ /etc/ /dev/ /proc/ /run/@755:0:0 /tmp/@777:0:0 /var/ /var/log/ \
    $SPEC /etc/passwd=$TMPD/passwd@644:0:0 /etc/inittab=$TMPD/inittab@644:0:0 /etc/fstab=$TMPD/fstab@644:0:0 \
    /etc/odb.token=$TMPD/token@600:0:0 /var/log/note.txt=$TMPD/note.txt@644:0:0 >"$TMPD/mkfs.txt" 2>&1 \
    || { bad "mkfs.py failed"; head -5 "$TMPD/mkfs.txt"; exit 1; }
ok "image"
[ -n "${KODB_KEEP:-}" ] && cp "$TMPD/disk.img" "$TMPD/token" "$KODB_KEEP/"
[ -n "${KODB_BUILD_ONLY:-}" ] && { echo "kodb: build only"; exit 0; }

PORT=$((20000 + RANDOM % 20000))
start_qemu() {
    local words=$1
    timeout 600 qemu-system-x86_64 $ACCEL -kernel "$B/k0.mb" -m 512 -smp 2 \
        -append "osum vfs nokbd nic nip=10.0.2.15/24 ngw=10.0.2.2 $words" -display none \
        -drive "file=$TMPD/disk.img,format=raw,if=ide,index=0" \
        -serial "file:$TMPD/com1.log" \
        -netdev "user,id=n0,hostfwd=udp:127.0.0.1:$PORT-10.0.2.15:6970" \
        -device "virtio-net-pci,netdev=n0,mac=52:54:00:5b:1d:02" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    QPID=$!
}
stop_qemu() { [ -n "$QPID" ] && kill "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null; QPID=""; }
od() { timeout "${KODB_T:-40}" $ODBC --net "127.0.0.1:$PORT" --token-file "$TMPD/token" "$@"; }

echo "== 2. kernel ODB over LAN =="
start_qemu "kodb"
up=0
for i in $(seq 1 60); do
    if timeout 5 $ODBC --net "127.0.0.1:$PORT" --timeout 2 ping >/dev/null 2>&1; then up=1; break; fi
    sleep 2
done
if [ $up = 1 ]; then ok "ping answered"; else bad "no answer"; tr -d '\000' < "$TMPD/com1.log" | tail -12 | sed 's/^/        /'; echo "kodb: $pass passed, $fail failed"; exit 1; fi
od info >"$TMPD/info.txt" 2>&1; has "info (authenticated)" "^tasks=" "$TMPD/info.txt"
has "info names locks field" "^locks=" "$TMPD/info.txt"
od ps --full >"$TMPD/ps.txt" 2>&1; has "ps full shows the hung victim" "sleep" "$TMPD/ps.txt"
grep -qE "until=|futex|wait4|poll|stop|sigpend" "$TMPD/ps.txt" && ok "ps full has wait reasons" || { bad "ps full: no wait reason"; head -8 "$TMPD/ps.txt"; }
od stacks >"$TMPD/stacks.txt" 2>&1
[ "$(wc -l < "$TMPD/stacks.txt")" -ge 3 ] && ok "stacks returns kernel stacks ($(wc -l < "$TMPD/stacks.txt") lines)" || { bad "stacks too short"; head -5 "$TMPD/stacks.txt"; }
od logs -n 50 >"$TMPD/logs.txt" 2>&1; has "logs contain the kodb line" "kodb" "$TMPD/logs.txt"
od ls /var/log >"$TMPD/ls.txt" 2>&1; has "ls /var/log lists note.txt" "note.txt" "$TMPD/ls.txt"
od cat /var/log/note.txt >"$TMPD/cat.txt" 2>&1
cmp -s "$TMPD/cat.txt" "$TMPD/note.txt" && ok "cat is byte-identical" || { bad "cat differs"; head -3 "$TMPD/cat.txt"; }
$ODBC --net "127.0.0.1:$PORT" --token-file "$TMPD/badtoken" --timeout 5 info >/dev/null 2>&1; rc=$?
[ "$rc" != 0 ] && ok "wrong token refused (exit $rc)" || bad "wrong token accepted"
$ODBC --net "127.0.0.1:$PORT" --timeout 5 info >/dev/null 2>&1; rc=$?
[ "$rc" != 0 ] && ok "no token refused (exit $rc)" || bad "no token accepted"
od info >/dev/null 2>&1; rc=$?
[ "$rc" != 0 ] && ok "right token refused right after a failure (lockout, exit $rc)" || bad "no lockout after a failed auth"
sleep 4
od info >/dev/null 2>&1 && ok "right token works after the lockout" || bad "right token refused after the lockout"
stop_qemu

echo "== 3. control: boot without kodb =="
: > "$TMPD/com1.log"
start_qemu ""
sleep 40
$ODBC --net "127.0.0.1:$PORT" --timeout 3 ping >/dev/null 2>&1; rc=$?
[ "$rc" != 0 ] && ok "no kodb word: no answer (exit $rc)" || bad "kernel answered without the kodb word"
stop_qemu

echo "kodb: $pass passed, $fail failed"
[ "$fail" = 0 ]
