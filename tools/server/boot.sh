#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
T=$(mktemp -d /tmp/srvboot.XXXXXX)
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "OK    $1"; }
bad() { fail=$((fail + 1)); echo "FAIL  $1"; }
has() { grep -qa -- "$2" "$1" && ok "$3" || bad "$3"; }
hasnot() { grep -qa -- "$2" "$1" && bad "$3" || ok "$3"; }

bash tools/server/build.sh "$T/b" > "$T/build.txt" 2>&1 && ok "server build" || { bad "server build"; tail -5 "$T/build.txt"; echo "SERVER-BOOT: $pass passed, $((fail+1)) failed"; exit 1; }
B="$T/b"
for p in init svc sshd dhcp ctr ota backup sntp host dnswt reboot shutdown; do
    [ -f "$B/bin/$p" ] || bad "program $p missing in the server image"
done
[ -f "$B/bin/init" ] && [ -f "$B/bin/sshd" ] && [ -f "$B/bin/ctr" ] && ok "image carries init svc sshd dhcp ctr ota backup sntp"

cat > "$T/probe.sh" <<'PROBE'
echo ==BEGIN==
svc status
echo --PROC--
cat /proc/meminfo
echo --HOST--
cat /etc/hostname
echo --RUN--
ls /run
echo --LOG--
ls /var/log
echo ==END==
shutdown
PROBE

image() {
    local out=$1 inittab=$2
    local spec=""
    for p in $(ls "$B/bin"); do spec="$spec /bin/$p=$B/bin/$p@755:0:0"; done
    [ "$inittab" = yes ] && spec="$spec /etc/inittab=$B/inittab@644:0:0"
    python3 tools/osum/mkfs.py build "$out" 20480 --v3 /bin/ /etc/ /run/ /var/ /var/log/@755:0:0 /proc/ /tmp/ /t/ $spec \
        /etc/ziel=$B/ziel@644:0:0 /etc/hostname=$B/hostname@644:0:0 /t/probe.sh=$T/probe.sh@644:0:0 > "$T/mkfs.txt" 2>&1
}

boot() {
    local img=$1 log=$2
    timeout 120 qemu-system-x86_64 -accel kvm -cpu host -kernel "$B/k.mb" -m 256 \
        -append "osum console=ttyS0 vfs script=sh /t/probe.sh" -serial "file:$log" -display none \
        -drive "file=$img,format=raw,if=ide" -device isa-debug-exit,iobase=0xf4,iosize=0x04 -no-reboot > /dev/null 2>&1
    echo $?
}

image "$T/a.img" yes && ok "server disk with /etc/inittab, /etc/ziel, /etc/hostname, /proc, /run, /var/log" || bad "mkfs.py failed"
rc=$(boot "$T/a.img" "$T/a.txt")
[ "$rc" = 0 ] && ok "machine powers off through ACPI (qemu exit 0)" || bad "qemu exit $rc"
A="$T/a.txt"
has "$A" "osum: pid1 init" "kernel starts /bin/init"
has "$A" "init: ziel=konsole" "target konsole from /etc/ziel"
has "$A" "init: dienste=4" "init reads /etc/inittab: 4 services"
has "$A" "^dhcp running" "svc status: dhcp running"
has "$A" "^sh running" "svc status: console shell running"
has "$A" "^sshd waiting" "svc status: sshd waits for the network (no NIC in this run)"
has "$A" "MemTotal:" "/proc/meminfo readable"
has "$A" "^osum-server" "hostname file"
has "$A" "svc.state" "/run exists and holds svc.state"
has "$A" "ofsver=3" "root is OFS v3"
hasnot "$A" "inittab fehlt" "no missing-inittab message"

image "$T/n.img" no && ok "counter-proof image without /etc/inittab" || bad "mkfs.py failed (no inittab)"
boot "$T/n.img" "$T/n.txt" > /dev/null
has "$T/n.txt" "init: /etc/inittab fehlt" "counter-proof: init says the inittab is missing"
hasnot "$T/n.txt" "init: dienste=" "counter-proof: no services start without inittab"
hasnot "$T/n.txt" "^sshd " "counter-proof: sshd is not supervised without inittab"

echo "SERVER-BOOT: $pass passed, $fail failed"
[ "$fail" = 0 ]
