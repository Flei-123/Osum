#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/keepalive/run.sh -- roadmap N-006: TCP keepalive (SO_KEEPALIVE, TCP_KEEPIDLE/KEEPINTVL/KEEPCNT).
#
#   /root/jarvis/bin/heavy bash tools/keepalive/run.sh          # KERNEL=<prebuilt.mb> skips the kernel build
#
# What is measured: a guest program (t_keepalive.c) holds one outgoing connection to a host echo server and one
# accepted connection (the host connects through a QEMU port forward), both idle. The host then switches the
# QEMU link OFF (HMP set_link), i.e. the peer vanishes without a FIN or RST. With keepalive set (idle 2 s,
# interval 1 s, count 3) both connections must die with ETIMEDOUT after about 5 s; the accepted one inherits the
# setting from its listener. Counter-check (mode nokeep): the same run without any option -- nothing may die.
# Run 1 = keepalive, run 2 = counter-check. A kernel with the old no-op setsockopt fails run 1.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
HERE=tools/keepalive
D=$(mktemp -d)
trap 'for p in $(jobs -p); do kill "$p" 2>/dev/null; done; rm -rf "$D"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$*"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$*"; }
QEMU=${QEMU_X86:-qemu-system-x86_64}
KVM=(); [ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)
TMO=${TMO:-120}
export FIRNLIB="$ROOT/lib"
for t in musl-gcc "$QEMU" python3 as ld; do command -v "$t" >/dev/null 2>&1 || { echo "KEEPALIVE: $t missing, skipped"; exit 0; }; done
LDREAL=$(readlink -f "${LDSO:-/lib/ld-musl-x86_64.so.1}" 2>/dev/null || true)
[ -r "$LDREAL" ] || LDREAL=/usr/lib/x86_64-linux-musl/libc.so
[ -r "$LDREAL" ] || { echo "KEEPALIVE: no musl libc.so, skipped"; exit 0; }
bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "vendor/firn/fetch-firnc.sh failed"; exit 1; }

echo "== 1. build: kernel, the guest program, the image =="
K=${KERNEL:-}
if [ -z "$K" ]; then
    K=$D/k.mb
    bash tools/build-kernel.sh "$K" --stufe 1 > "$D/kbuild.log" 2>&1 && [ -s "$K" ] && ok "kernel builds (stage 1)" || { bad "kernel does not build"; tail -5 "$D/kbuild.log"; echo "KEEPALIVE: $pass passed, $fail failed"; exit 1; }
fi
mkdir -p "$D/bin" "$D/p"
musl-gcc -O1 -Wall -o "$D/bin/t_keepalive" $HERE/t_keepalive.c 2> "$D/cc.err" && ok "t_keepalive builds" || { bad "t_keepalive does not build"; head -5 "$D/cc.err"; exit 1; }
as --64 -o "$D/crt.o" kernel/user/crt.s || exit 1
SPEC="/lib/ /bin/ /tmp/ /etc/ /var/ /dev/ /proc/ /root/ /run/"
for p in sh ls cat echo; do
    vendor/firn/bin/firnc1 kernel/user/$p.fi -o "$D/p/$p.o" > "$D/p/$p.log" 2>&1 \
      && ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F1.u_start" -o "$D/p/$p.elf" "$D/crt.o" "$D/p/$p.o" 2>>"$D/p/$p.log" \
      || { bad "user program $p does not build"; exit 1; }
    strip --strip-all "$D/p/$p.elf" 2>/dev/null
    SPEC="$SPEC /bin/$p=$D/p/$p.elf"
done
SPEC="$SPEC /lib/ld-musl-x86_64.so.1=$LDREAL /bin/t_keepalive=$D/bin/t_keepalive /etc/hosts=$D/hosts"
printf '127.0.0.1 localhost\n' > "$D/hosts"

freeport() { python3 -I -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])'; }

# run <mode>: boots the guest, plays the host side, leaves the serial log in $D/<mode>.ser
run() {
    local mode=$1 eport hport mon ser img qpid epid cpid
    eport=$(freeport); hport=$(freeport); mon=$D/mon-$mode.sock; ser=$D/$mode.ser; img=$D/$mode.img
    printf '%s %s\n' "$mode" "$eport" > "$D/ka.conf"
    python3 tools/osum/mkfs.py build "$img" 16384 --v3 --inodes=256 $SPEC /etc/ka.conf="$D/ka.conf" > "$D/mkfs-$mode.txt" 2>&1 || { bad "$mode: image does not build"; return 1; }
    python3 -I $HERE/echo.py "$eport" > "$D/echo-$mode.log" 2>&1 & epid=$!
    : > "$ser"
    timeout "$TMO" $QEMU "${KVM[@]}" -kernel "$K" -m 512 \
        -append "osum vfs nokbd nosched noproc nofs nic nip=10.0.2.15/24 ngw=10.0.2.2 script=/bin/t_keepalive;exit" \
        -serial "file:$ser" -display none -no-reboot -monitor "unix:$mon,server,nowait" \
        -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:$hport-:7001" -device virtio-net-pci,netdev=n0,id=nic0 \
        -drive "file=$img,format=raw,if=ide,index=0" -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 & qpid=$!
    # the host side, driven by what the guest prints
    python3 -I - "$ser" "$mon" "$hport" "$TMO" <<'PY' &
import os, socket, sys, time
ser, mon, hport, tmo = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
def text():
    try: return open(ser, "rb").read().decode("latin-1")
    except OSError: return ""
def wait(tag, until):
    while time.time() < until:
        if tag in text(): return True
        time.sleep(0.2)
    return False
end = time.time() + tmo
held = None
if wait("KA LISTEN", end):
    for _ in range(50):                       # the forward needs a moment
        try:
            held = socket.create_connection(("127.0.0.1", hport), timeout=5); break
        except OSError: time.sleep(0.2)
if wait("KA READY-CUT", end):
    m = socket.socket(socket.AF_UNIX); m.connect(mon); m.settimeout(2)
    try: m.recv(4096)
    except OSError: pass
    for name in ("n0", "nic0"):
        m.sendall(("set_link %s off\n" % name).encode()); time.sleep(0.3)
        try: m.recv(4096)
        except OSError: pass
wait("KA END", end)
PY
    cpid=$!
    wait "$cpid" 2>/dev/null
    kill "$qpid" "$epid" 2>/dev/null; wait "$qpid" "$epid" 2>/dev/null
    grep -a '^T ka\.' "$ser" | tr -d '\r' | awk '!seen[$2]++' > "$D/$mode.res"
    grep -aq '^KA END' "$ser" && ok "$mode: the guest program ran to the end" || bad "$mode: the guest program did not finish (see tail of the log below)"
    grep -aq '^KA END' "$ser" || tail -5 "$ser" | cut -c1-200
}

want() { # want <mode> <check> : PASS expected
    local line; line=$(grep -a "^T ka\.$2 " "$D/$1.res" | head -1)
    case "$line" in *" PASS"*) ok "$1: $2";; "") bad "$1: $2 -- never reported";; *) bad "$1: ${line#T }";; esac
}

echo "== 2. run 1: keepalive on =="
run ka
for c in started opt_default opt_range opt_range_kept opt_short listen opt_set_listener opt_set opt_get connect echo accept accept_inherit \
         quiet_link_up alive_after_idle no_error_link_up dies_out dies_in_time not_instant error_out error_accepted read_fails; do want ka $c; done

echo "== 3. run 2: counter-check, no option set =="
run nokeep
for c in started opt_default connect echo accept accept_default quiet_link_up alive_after_idle nokeep_stays_open nokeep_no_error; do want nokeep $c; done

echo "KEEPALIVE: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
