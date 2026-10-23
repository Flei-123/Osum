#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/safe/run.sh -- W-SAFE2 gate: safe mode word, boot-state fallback (CMOS), loop guard, panic-N.txt, /proc/safe.
#
#   /root/jarvis/bin/heavy bash tools/safe/run.sh
#
# A  `safe` strips network / driver words (e1000 attached: no net lines); counter-proof `nosafefilter` brings the lines back.
# B  `safeauto` + forced kernel panic + `absturzneustart`: ONE QEMU process reboots; boot 2 reports "previous boot did not finish"
#    and runs in safe mode, boot 4 (3 failed boots) gives up without reset; /var/jarvis/panic-N.txt on the disk.
# B2 counter-proof: same command line without `safeauto` -> no fallback line, no loop guard.
# The desktop part (good-boot mark, hang watchdog, no false positive) is tools/safe/desktop.sh.
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { if [ "$2" -"$3" "$4" ] 2>/dev/null; then ok "$1: $2"; else bad "$1: $2 (want $3 $4)"; fi; }
ACCEL=""
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then ACCEL="-accel kvm -cpu host"; fi
K0=${SAFE_KERNEL:-}
if [ -z "$K0" ]; then
    bash tools/build-kernel.sh "$TMPD/k0.mb" > "$TMPD/build.log" 2>&1 || { bad "kernel build"; tail -5 "$TMPD/build.log"; exit 1; }
    K0="$TMPD/k0.mb"
fi
ULD=kernel/user/user.ld
as --64 -o "$TMPD/crt.o" kernel/user/crt.s || bad "crt.s"
PROGS="sh ls cat echo krach"
quelle() { case $1 in krach) echo noise ;; *) echo "$1" ;; esac; }
for p in $PROGS; do
    q=$(quelle "$p")
    "$FIRNC" "kernel/user/$q.fi" -o "$TMPD/$p.o" > "$TMPD/e$p" 2>&1 || { bad "$q.fi compile"; head -5 "$TMPD/e$p"; }
    ld -T "$ULD" --defsym=USER_ENTRY="_F0.u_start" -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null || bad "$p link"
done
SPEC="/bin/"
for p in $PROGS; do SPEC="$SPEC /bin/$p=$TMPD/$p.elf"; done
mkdisk() { python3 tools/osum/mkfs.py build "$1" 4096 $SPEC /proc/ /dev/ /mnt/ /var/ /var/crash/ > "$TMPD/mkfs.txt" 2>&1 || { bad "mkfs $1"; head -3 "$TMPD/mkfs.txt"; }; }
BASE="osum nokbd vfs"

run() { # <serial> <seconds> <disk> <cmdline> [qemu args...]
    local ser=$1 secs=$2 disk=$3 cl=$4
    shift 4
    rm -f "$ser"
    timeout "$secs" qemu-system-x86_64 $ACCEL -kernel "$K0" -m 256 -append "$cl" -serial "file:$ser" -display none \
        -drive "file=$disk,format=raw,if=ide,index=0" "$@" -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
}
runq() { run "$@" -no-reboot; }

echo "== A. safe word strips network / driver words =="
mkdisk "$TMPD/dA.img"
NETW="nic nip=10.0.2.15/24 nsvc=0 nwait=0 dhcp"
NETDEV="-netdev user,id=n0 -device e1000,netdev=n0"
runq "$TMPD/a0.txt" 120 "$TMPD/dA.img" "$BASE $NETW script=cat /proc/safe;exit" $NETDEV
runq "$TMPD/a1.txt" 120 "$TMPD/dA.img" "$BASE safe $NETW script=cat /proc/safe;exit" $NETDEV
runq "$TMPD/a2.txt" 120 "$TMPD/dA.img" "$BASE safe nosafefilter $NETW script=cat /proc/safe;exit" $NETDEV
nl() { grep -aciE 'e1000|netsvc|dhcp' "$1"; }
n0=$(nl "$TMPD/a0.txt"); n1=$(nl "$TMPD/a1.txt"); n2=$(nl "$TMPD/a2.txt")
num "A baseline: network lines present" "$n0" gt 0
num "A safe: network lines" "$n1" eq 0
num "A counter-proof nosafefilter: network lines back" "$n2" gt 0
grep -aq '^safe=1' "$TMPD/a1.txt" && ok "A /proc/safe says safe=1" || bad "A /proc/safe safe=1 missing"
grep -aq '^safe=0' "$TMPD/a0.txt" && ok "A baseline /proc/safe says safe=0" || bad "A baseline /proc/safe safe=0 missing"
grep -aq 'safe: SAFE MODE (command line)' "$TMPD/a1.txt" && ok "A SAFE MODE line on serial" || bad "A SAFE MODE line missing"
if [ -n "${SAFE_OUT:-}" ]; then mkdir -p "$SAFE_OUT"; cp "$TMPD"/a?.txt "$SAFE_OUT/" 2>/dev/null; fi

echo "== B. forced panic chain in ONE qemu: fallback, filter, loop guard =="
mkdisk "$TMPD/dB.img"
PANIC="krach safeauto absturzneustart script=krach kern;exit"
run "$TMPD/b.txt" 170 "$TMPD/dB.img" "$BASE $NETW $PANIC" $NETDEV
nb=$(grep -ac 'safe: previous boot did not finish' "$TMPD/b.txt")
num "B boots that saw a failed predecessor" "$nb" ge 3
nf=$(grep -ac 'safe: SAFE MODE (automatic fallback)' "$TMPD/b.txt")
num "B automatic fallback boots" "$nf" ge 3
grep -aq 'safe: previous boot did not finish, fails so far 1' "$TMPD/b.txt" && ok "B boot 2: fails so far 1" || bad "B fails=1 line missing"
grep -aq 'safe: previous boot did not finish, fails so far 3' "$TMPD/b.txt" && ok "B boot 4: fails so far 3" || bad "B fails=3 line missing"
ng=$(grep -ac '^\*\*\* no reset: failed boots in a row' "$TMPD/b.txt")
num "B loop guard: gave up without reset" "$ng" ge 1
nr=$(grep -ac '^\*\*\* reset in 20 s' "$TMPD/b.txt")
num "B resets before giving up (max 3)" "$nr" eq 3
nex=$(grep -ac '^\*\*\* EXCEPTION' "$TMPD/b.txt")
num "B panics" "$nex" eq 4
fb=$(awk '/safe: previous boot did not finish/{f=1} f&&/e1000|netsvc|dhcp/{n++} END{print n+0}' "$TMPD/b.txt")
num "B network lines after the first fallback" "$fb" eq 0
if [ -n "${SAFE_OUT:-}" ]; then cp "$TMPD/b.txt" "$SAFE_OUT/" 2>/dev/null; fi
runq "$TMPD/b2.txt" 90 "$TMPD/dB.img" "$BASE script=ls /var/jarvis;cat /var/jarvis/panic-1.txt;exit"
grep -aq 'panic-1.txt' "$TMPD/b2.txt" && ok "B /var/jarvis/panic-1.txt on the disk" || bad "B panic-1.txt missing"
grep -aq 'panic-4.txt' "$TMPD/b2.txt" && ok "B /var/jarvis/panic-4.txt on the disk" || bad "B panic-4.txt missing"
grep -aq 'ABSTURZBERICHT' "$TMPD/b2.txt" && ok "B panic-1.txt holds the report" || bad "B report text missing"
grep -aq 'safe-state: fails=' "$TMPD/b2.txt" && ok "B panic-1.txt carries the safe-state line" || bad "B safe-state line missing"
if [ -n "${SAFE_OUT:-}" ]; then cp "$TMPD/b2.txt" "$SAFE_OUT/" 2>/dev/null; fi

echo "== B2. counter-proof: no safeauto -> no fallback, no loop guard =="
mkdisk "$TMPD/dB2.img"
run "$TMPD/c.txt" 75 "$TMPD/dB2.img" "$BASE $NETW krach absturzneustart script=krach kern;exit" $NETDEV
num "B2 safe lines without safeauto" "$(grep -ac '^safe: ' "$TMPD/c.txt")" eq 0
num "B2 panics happened (reset loop)" "$(grep -ac '^\*\*\* EXCEPTION' "$TMPD/c.txt")" ge 2
num "B2 no loop guard without safeauto" "$(grep -ac 'no reset: failed boots' "$TMPD/c.txt")" eq 0
if [ -n "${SAFE_OUT:-}" ]; then cp "$TMPD/c.txt" "$SAFE_OUT/" 2>/dev/null; fi
echo; echo "SAFE: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
