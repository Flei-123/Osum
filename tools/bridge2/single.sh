#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/bridge2/single.sh -- jarvisd runs ONCE: a second start does not make a second service.
#
#   bash tools/bridge2/single.sh [<workdir>]
#
# The kernel starts /bin/jarvisd at boot (boot word `jarvis`, kgui.desk_start). Somebody who then types
# `jarvisd` in a terminal used to get a SECOND supervisor with its own worker and a second sign-in on the
# same device key. Now a start without flags looks for another live task called `jarvisd` and ends.
#
# Guest script: `jarvisd &`, wait, `jarvisd` again, wait, `ps`. Measured from the serial line:
#   1. exactly one "supervisor started"            (the first one)
#   2. one "already running"                       (the second one refused itself)
#   3. COUNTER-PROOF: the same script with the jarvisd of the base commit (git HEAD) starts TWO supervisors
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
if [ -n "${1:-}" ]; then W=$1; mkdir -p "$W"; else W=$(mktemp -d); CLEAN=1; fi
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
[ -w /dev/kvm ] && ACC=(-accel kvm -cpu host) || ACC=()

echo "== 1. build =="
bash vendor/firn/fetch-firnc.sh > "$W/fetch.log" 2>&1
./tools/build-kernel.sh "$W/k0.mb" > "$W/k.log" 2>&1 || { echo "kernel does not build"; tail -15 "$W/k.log"; exit 1; }
as --64 -o "$W/crt.o" kernel/user/crt.s 2>"$W/as.err" || { cat "$W/as.err"; exit 1; }
for p in sh ls cat echo sleep ps; do
    vendor/firn/bin/firnc "kernel/user/$p.fi" -o "$W/$p.o" > "$W/e-$p" 2>&1 || { echo "$p does not build"; head -20 "$W/e-$p"; exit 1; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" -o "$W/$p.elf" "$W/crt.o" "$W/$p.o" 2>"$W/ld-$p" || exit 1
    strip --strip-all "$W/$p.elf"
done
buildj() { # <source> <out elf>
    FIRNLIB="$ROOT/lib" vendor/firn/bin/firnc -c --profile=app -o "$W/j.o" "$1" > "$W/e-j" 2>&1 || { echo "jarvisd does not build"; head -20 "$W/e-j"; exit 1; }
    ld -T kernel/user/user.ld -o "$2" "$W/j.o" 2> "$W/ld-j" || exit 1
    strip --strip-all "$2"
}
buildj kernel/app/jarvisd.fi "$W/jarvisd-new.elf"
# the base: the jarvisd BEFORE this change (f30c2b78 = main of 08.10.2026), or $BASE_REF
git show "${BASE_REF:-f30c2b78}:kernel/app/jarvisd.fi" > kernel/app/jarvisd_base.fi || exit 1
trap 'rm -f kernel/app/jarvisd_base.fi; [ -n "${CLEAN:-}" ] && rm -rf "$W"' EXIT
buildj kernel/app/jarvisd_base.fi "$W/jarvisd-base.elf"

cat > "$W/rechte.conf" <<'CONF'
transport            = https
servername     = store.fleitec.com
path           = /bruecke/draht
roots        = /etc/ssl/roots.pem
commands        = no
screenshot = no
sysinfo     = yes
input        = no
max_output    = 65536
max_file      = 4194304
log       = /var/log/jarvisd.log
work_file    = /var/jarvis/output.txt
permit_file = /var/jarvis/screenshot-permit
CONF
printf 'x\n' > "$W/roots.pem"
printf 'nameserver 10.0.2.3\n' > "$W/resolv.conf"
cat > "$W/g.sh" <<'EOS'
jarvisd &
sleep 6
echo ==SECOND==
jarvisd
sleep 3
echo ==DONE==
EOS

run() { # <label> <jarvisd elf>
    local nm=$1 elf=$2
    local SPEC="/bin/ /etc/ /etc/ssl/ /etc/jarvis/ /var/ /var/log/ /var/jarvis/ /t/"
    for p in sh ls cat echo sleep ps; do SPEC="$SPEC /bin/$p=$W/$p.elf"; done
    SPEC="$SPEC /bin/jarvisd=$elf /etc/jarvis/permissions.conf=$W/rechte.conf /etc/ssl/roots.pem=$W/roots.pem /etc/resolv.conf=$W/resolv.conf /t/g.sh=$W/g.sh"
    python3 tools/osum/mkfs.py build "$W/$nm.img" 32768 $SPEC > "$W/mkfs-$nm.txt" 2>&1 || { echo "mkfs"; tail -5 "$W/mkfs-$nm.txt"; exit 1; }
    timeout 120 qemu-system-x86_64 "${ACC[@]}" -kernel "$W/k0.mb" -m 512 \
        -append "osum nokbd nosched noproc nofs modfs script=sh /t/g.sh;exit" \
        -serial "file:$W/$nm.txt" -display none -no-reboot \
        -drive "file=$W/$nm.img,format=raw,if=ide,index=0" > "$W/$nm.qemu" 2>&1
    rm -f "$W/$nm.img"
}
echo "== 2. the fix: the second start refuses itself =="
run new "$W/jarvisd-new.elf"
n=$(grep -ac 'jarvisd: supervisor started' "$W/new.txt"); [ "$n" = 1 ] && ok "one supervisor started: $n" || bad "supervisors started: $n, expected 1"
n=$(grep -ac 'jarvisd: already running' "$W/new.txt"); [ "$n" = 1 ] && ok "the second start said 'already running': $n" || bad "'already running' lines: $n, expected 1"
grep -qa '==DONE==' "$W/new.txt" && ok "the script reached its end" || bad "the script did not finish"
echo "== 3. COUNTER-PROOF: the jarvisd of the base commit =="
run base "$W/jarvisd-base.elf"
n=$(grep -ac 'jarvisd: supervisor started' "$W/base.txt"); [ "$n" -ge 2 ] && ok "the base starts $n supervisors (this is what the fix removes)" || bad "COUNTER-PROOF: the base started only $n supervisor(s)"
n=$(grep -ac 'jarvisd: already running' "$W/base.txt"); [ "$n" = 0 ] && ok "the base never says 'already running'" || bad "the base says 'already running'"

echo; echo "BRIDGE-SINGLE: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
