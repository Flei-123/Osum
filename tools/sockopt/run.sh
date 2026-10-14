#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/sockopt/run.sh -- ROUND FV-W24: SO_RCVTIMEO / SO_SNDTIMEO IN THE KERNEL.
#
# `setsockopt` used to take every option and act on none, so a "timed" read
# blocked until data came. This gate boots the kernel in QEMU, runs
# /bin/sockt (kernel/user/sockt.fi) and checks, against CLOCK_MONOTONIC:
# the timeout fires after the asked time (-EAGAIN), getsockopt reads it
# back, send and receive are separate, bad input is refused, a non-blocking
# socket never waits, accept honours the timeout, 0/0 clears it.
set -uo pipefail
cd "$(dirname "$0")/../.."

export FIRNLIB="$(pwd)/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
FC1=${FIRNC1:-vendor/firn/bin/firnc1}
LDSCRIPT=kernel/kernel.ld
ULD=kernel/user/user.ld
PROGS="sh ls cat echo hello sockt"
BLOCKS=2048
OSUM_IP=10.0.2.15
OSUM_GW=10.0.2.2
FWPORT=${FWPORT:-45719}
QPID=""

TMPD=$(mktemp -d)
cleanup() {
    [ -n "$QPID" ] && kill "$QPID" 2>/dev/null
    rm -rf "$TMPD"
}
trap cleanup EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }

num() { # name wert op erwartet
    local name=$1 value=$2 op=$3 want=$4
    if [ -z "$value" ]; then bad "$name: keine Zahl gefunden (erwartet $op $want)"; return; fi
    if [ "$value" -"$op" "$want" ] 2>/dev/null; then ok "$name: $value"
    else bad "$name: $value, erwartet $op $want"; fi
}

between() { # name wert unten oben
    local name=$1 v=$2 lo=$3 hi=$4
    if [ -z "$v" ]; then bad "$name: keine Zahl gefunden"; return; fi
    if [ "$v" -ge "$lo" ] && [ "$v" -le "$hi" ]; then ok "$name: $v (erlaubt $lo..$hi)"
    else bad "$name: $v, erlaubt $lo..$hi"; fi
}

value_of()  { grep -a -m1 "^sockt: $2 = " "$1" 2>/dev/null | sed 's/.* = //'; }
value_n()   { grep -a "^sockt: $2 = " "$1" 2>/dev/null | sed -n "$3p" | sed 's/.* = //'; }

say() { # datei name erwartet beschreibung
    local got
    got=$(value_of "$1" "$2")
    if [ -z "$got" ]; then bad "$4 -- no line 'sockt: $2 ='"; return; fi
    if [ "$got" = "$3" ]; then ok "$4 ($2 = $got)"
    else bad "$4 -- $2 = $got, erwartet $3"; fi
}

number_in() { # datei name
    grep -aE "^const $2: u64 = [0-9]+" "$1" | head -1 \
        | sed -E 's/^const [A-Za-z0-9_]+: u64 = ([0-9]+).*/\1/'
}

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "vendor/firn/fetch-firnc.sh fehlgeschlagen"; exit 1; }
[ -x "$FIRNC" ] || { echo "firnc0 fehlt: $FIRNC"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "SOCKOPT: skipped, qemu-system-x86_64 fehlt"
    exit 0
fi

# RUNDE KVMFIX hat den Kernel unter KVM zum Laufen gebracht (zwei echte
# Hardwarefehler, siehe KVMFIX-STATUS.md). Wo /dev/kvm da ist, wird es
# benutzt -- und wo nicht, sagt es der Laeufer, statt still langsamer zu
# messen.
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    ACCEL="-accel kvm"; ACCELNAME="kvm"
else
    ACCEL="-accel tcg"; ACCELNAME="tcg (kein /dev/kvm)"
fi

# =====================================================================
echo "== 2. bauen: Kernel, libc, /bin/sockt =="
# =====================================================================
for f in boot isr switch smp hv; do
    as --64 -o "$TMPD/$f.o" "kernel/arch/x86_64/$f.s" 2>"$TMPD/as.err" \
        || bad "$f.s laesst sich nicht assemblieren"
done
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s"

build_stage() { # 0 = firnc0, 1 = firnc1
    local s=$1 cc p
    if [ "$s" = 0 ]; then cc="$FIRNC"; else cc="$FC1"; fi
    [ -x "$cc" ] || return 1
    "$cc" kernel/kmain.fi -o "$TMPD/k$s.o" >"$TMPD/e$s" 2>&1 \
        || { bad "firnc$s uebersetzt den Kernel nicht"; sed 's/^/        /' "$TMPD/e$s" | head -8; return 1; }
    "$cc" kernel/uprog.fi -o "$TMPD/u$s.o" >>"$TMPD/e$s" 2>&1 \
        || { bad "firnc$s uebersetzt uprog.fi nicht"; return 1; }
    ld -n -T "$LDSCRIPT" \
        --defsym=KERNEL_MAIN="_F$s.kernel_main" \
        --defsym=KERNEL_TRAP="_F$s.trap__entry" \
        --defsym=KERNEL_SYSCALL="_F$s.sys__entry" \
        --defsym=KERNEL_TASK_MAIN="_F$s.tasks__main" \
        --defsym=KERNEL_USER_START="_F$s.proc__user_start" \
        --defsym=KERNEL_AP_MAIN="_F$s.smp__ap_main" \
        --defsym=USER_MAIN="_F$s.u_enter" \
        -o "$TMPD/k$s.elf" "$TMPD/boot.o" "$TMPD/isr.o" "$TMPD/switch.o" \
        "$TMPD/smp.o" "$TMPD/hv.o" "$TMPD/k$s.o" "$TMPD/u$s.o" 2>"$TMPD/ld$s.err" \
        || { bad "firnc$s: ld ist am Kernel gescheitert"; return 1; }
    objcopy -O elf32-i386 "$TMPD/k$s.elf" "$TMPD/k$s.mb" 2>/dev/null
    for p in $PROGS; do
        "$cc" "kernel/user/$p.fi" -o "$TMPD/$p$s.o" >"$TMPD/e$p$s" 2>&1 \
            || { bad "firnc$s uebersetzt $p.fi nicht"; sed 's/^/        /' "$TMPD/e$p$s" | head -6; return 1; }
        ld -T "$ULD" --defsym=USER_ENTRY="_F$s.u_start" \
            -o "$TMPD/$p$s.elf" "$TMPD/crt.o" "$TMPD/$p$s.o" 2>/dev/null \
            || { bad "firnc$s: ld ist an $p gescheitert"; return 1; }
        strip --strip-all "$TMPD/$p$s.elf"
    done
    return 0
}
build_stage 0 || { echo "SOCKOPT: $pass passed, $fail failed"; exit 1; }
ok "firnc0: Kernel + $(echo $PROGS | wc -w) Programme"
if build_stage 1; then
    ok "firnc1: dasselbe, aus dem in Firn geschriebenen Uebersetzer"
else
    note "firnc1 hat nicht gebaut -- die Messungen unten laufen mit firnc0"
fi

undef=$(nm -u "$TMPD/sockt0.elf" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
[ -z "$undef" ] && ok "/bin/sockt has no undefined name" || bad "undefined names in sockt: $undef"

SPEC="/bin/"
for p in $PROGS; do SPEC="$SPEC /bin/$p=$TMPD/${p}0.elf"; done
python3 tools/osum/mkfs.py build "$TMPD/disk.img" $BLOCKS $SPEC > "$TMPD/mkfs.txt" 2>&1 \
    && ok "mkfs.py hat ein OFS-Abbild mit dem Userland dieser Runde gebaut" \
    || { bad "mkfs.py fehlgeschlagen"; sed 's/^/        /' "$TMPD/mkfs.txt"; }

run_disk() { # abbild anhang ausgabe
    local copy="$TMPD/live.img"
    cp "$TMPD/disk.img" "$copy"
    timeout 300 qemu-system-x86_64 $ACCEL -kernel "$1" -m 128 -append "$2" \
        -serial "file:$3" -display none -no-reboot \
        -drive "file=$copy,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    return $?
}

QUIET="nokbd nosched noproc nofs noring3"

echo "== 3. SO_RCVTIMEO / SO_SNDTIMEO in the running kernel ($ACCELNAME) =="
run_disk "$TMPD/k0.mb" "osum $QUIET nic nip=$OSUM_IP/24 ngw=$OSUM_GW script=sockt;exit" "$TMPD/run0.txt"
rc=$?
F="$TMPD/run0.txt"
[ "$rc" -eq 21 ] && ok "kernel ended the run itself (exit code 21)" \
                 || { bad "QEMU exit code $rc, expected 21"; tail -8 "$F" | tr -d '\000' | sed 's/^/        /'; }

say "$F" udp_ok 1 "UDP socket created"
say "$F" set_ret 0 "bind and setsockopt succeed (first set_ret = bind)"

# The lower bounds are 10 % under the nominal value on purpose: the guest clock (CLOCK_MONOTONIC,
# TSC-calibrated) is not exact on a loaded KVM host -- tools/poll/run.sh shows the same skew (poll(300) = 281).
# What is proven here: it waits in the order of the timeout (not 0, not the 30 s NET_ROUNDS bound).
echo "   -- receive timeout 200 ms"
say "$F" r1_get 200000 "getsockopt reads back 200 ms as a timeval (0 s, 200000 us)"
say "$F" r1_ret -11 "recvfrom on an empty socket returns -EAGAIN after the timeout"
between "and it really waited 200 ms (not 30 s, not 0)" "$(value_n "$F" r1_ms 1)" 180 280
say "$F" r1_ret -11 "the socket is still usable: second recvfrom times out too"
between "second wait is 200 ms as well" "$(value_n "$F" r1_ms 2)" 180 280

echo "   -- other values"
say "$F" r2_get 1500000 "1.5 s reads back"
say "$F" r2_ret -11 "1.5 s: -EAGAIN"
between "1.5 s wait" "$(value_of "$F" r2_ms)" 1350 1580
say "$F" r3_get 20000 "15 ms is rounded UP to the 10 ms tick: 20 ms"
say "$F" r3_ret -11 "15 ms: -EAGAIN"
between "15 ms wait (viewer value)" "$(value_of "$F" r3_ms)" 15 80

echo "   -- send timeout is separate, _NEW name, invalid input"
say "$F" snd_get 300000 "SO_SNDTIMEO reads back 300 ms"
say "$F" rcv_kept 20000 "and left the receive timeout alone"
say "$F" new_get 70000 "SO_RCVTIMEO_NEW (66) sets the same value"
say "$F" inv_us -22 "usec >= 1000000: -EINVAL"
say "$F" inv_len -22 "optlen < 16: -EINVAL"
say "$F" inv_ptr -14 "null value pointer: -EFAULT"
say "$F" inv_neg -22 "negative seconds: -EINVAL"
say "$F" reuse 0 "an option the kernel does not act on is still taken (curl, nc)"
say "$F" zero_get 0 "0/0 clears the timeout"

echo "   -- non-blocking and accept"
say "$F" nb_ret -11 "non-blocking socket: -EAGAIN"
between "and it does not wait for the timeout" "$(value_of "$F" nb_ms)" 0 60
say "$F" lst_ret 0 "listen works"
say "$F" acc_ret -11 "accept with SO_RCVTIMEO 100 ms: -EAGAIN"
between "accept waited 100 ms" "$(value_of "$F" acc_ms)" 90 180

grep -aq "kernel: done" "$F" && ok "kernel is still alive after all cases" \
                             || bad "'kernel: done' missing"
n=$(value_of "$F" lines)
num "lines printed by /bin/sockt" "${n:-0}" ge 30

echo
echo "SOCKOPT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
