#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/appload/run.sh -- W-AR6 r918: THE PER-APP COUNTERS UNDER REAL LOAD (QEMU), read from /proc/apps and `apprights list`.
#
#   /root/jarvis/bin/heavy bash tools/appload/run.sh
#
# AR-3 only tested the format of /proc/apps. Here an app (a child labelled `app:<name>`, see `apprights burn`) really works:
#   cpuapp   busy loop 0.4 s            -> cpu_ticks > 0
#   netapp   ping -c 3 10.0.2.2 (granted net) -> tx > 0, rx > 0, wakeups > 0 (QEMU user net, DHCP first)
#   blocked  same ping, NOT granted net  -> tx = rx = 0 (counter-probe: the counters follow the work, not the name)
#   idle     never ran                   -> all four counters 0 (counter-probe)
#   stopme / keepme  two spinners; `apprights stop stopme` kills the first and only the first
# Also checks `apprights list` (mask, ceiling, counters, data=0) against the same table.
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
mkdir -p "$TMPD/bin"
PROGS="sh cat echo apprights dhcp ping sleep ps"
bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1 \
    && ok "programs build" || { bad "build"; head -20 "$TMPD/b.txt"; echo "APPLOAD: $pass passed, $fail failed"; exit 1; }
./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1 \
    && ok "kernel builds" || { bad "kernel"; tail -15 "$TMPD/k.txt"; echo "APPLOAD: $pass passed, $fail failed"; exit 1; }

mkdir -p "$TMPD/bd"
APPS="cpuapp netapp blocked idle stopme keepme"
for a in cpuapp idle stopme keepme; do printf 'name=%s\nperm=notify\n' "$a" > "$TMPD/bd/$a.info"; done
for a in netapp blocked; do printf 'name=%s\nperm=net\nnet=real\n' "$a" > "$TMPD/bd/$a.info"; done
cat > "$TMPD/s1.sh" <<'EOS'
echo ==LOAD==
apprights load
apprights set netapp net
dhcp
echo ==BURN==
apprights burn cpu cpuapp
apprights burn net netapp
apprights burn net blocked
echo ==PROC==
cat /proc/apps
echo ==LIST==
apprights list
echo ==STOP==
apprights burn spin stopme &
apprights burn spin keepme &
sleep 1
apprights stop other
apprights stop stopme
apprights stop stopme
apprights stop keepme
echo ==END==
EOS
ARGS=(/lib/ "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf"
      /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ /apps/ /data/)
for a in $APPS; do ARGS+=("/apps/$a.osp/" "/apps/$a.osp/INFO=$TMPD/bd/$a.info"); done
for p in $PROGS; do ARGS+=("/bin/$p=$TMPD/bin/$p.elf"); done
ARGS+=("/t/s1.sh=$TMPD/s1.sh")
python3 tools/osum/mkfs.py build "$TMPD/d.img" 20000 "${ARGS[@]}" > "$TMPD/mkfs.txt" 2>&1 || { bad "mkfs"; tail -3 "$TMPD/mkfs.txt"; }
timeout 240 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 -kernel "$TMPD/k0.img" -m 512 \
    -append "osum vfs nic nip=169.254.10.1/16 nsvc=0 nwait=0 script=sh /t/s1.sh;exit" \
    -serial "file:$TMPD/raw" -display none -no-reboot \
    -netdev user,id=n0 -device e1000,netdev=n0 \
    -drive "file=$TMPD/d.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
tr -cd '\11\12\15\40-\176' < "$TMPD/raw" > "$TMPD/o.txt"
part() { awk -v a="==$1==" -v b="==$2==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$TMPD/o.txt"; }
part PROC LIST > "$TMPD/proc.txt"; part LIST STOP > "$TMPD/list.txt"; part STOP END > "$TMPD/stop.txt"
col() { # col <file> <app> <field>   (name cpu wakeups tx rx)
    awk -v n="$2" -v f="$3" '$1==n{print $f; exit}' "$1" | tr -d '\r'
}
num() { case "$1" in ''|*[!0-9]*) echo 0 ;; *) echo "$1" ;; esac; }
head -3 "$TMPD/proc.txt" | sed 's/^/        /'
grep -a "dhcp\|lease\|bound" "$TMPD/o.txt" | head -3 | sed 's/^/        /'

cpu_c=$(num "$(col "$TMPD/proc.txt" cpuapp 2)"); [ "$cpu_c" -gt 0 ] && ok "cpuapp: cpu_ticks = $cpu_c (> 0 after a busy loop)" || bad "cpuapp cpu_ticks = $cpu_c"
net_c=$(num "$(col "$TMPD/proc.txt" netapp 2)"); net_w=$(num "$(col "$TMPD/proc.txt" netapp 3)")
net_t=$(num "$(col "$TMPD/proc.txt" netapp 4)"); net_r=$(num "$(col "$TMPD/proc.txt" netapp 5)")
[ "$net_t" -gt 0 ] && ok "netapp: tx = $net_t (> 0 after ping)" || bad "netapp tx = $net_t"
[ "$net_r" -gt 0 ] && ok "netapp: rx = $net_r (> 0 after ping)" || bad "netapp rx = $net_r"
[ "$net_w" -gt 0 ] && ok "netapp: wakeups = $net_w (> 0)" || bad "netapp wakeups = $net_w"
[ "$net_c" -gt 0 ] && ok "netapp: cpu_ticks = $net_c (> 0)" || bad "netapp cpu_ticks = $net_c"
bl_t=$(num "$(col "$TMPD/proc.txt" blocked 4)"); bl_r=$(num "$(col "$TMPD/proc.txt" blocked 5)")
[ "$bl_t" = 0 ] && [ "$bl_r" = 0 ] && ok "COUNTER-PROBE: blocked (net declared, not granted) counts tx=0 rx=0" || bad "blocked tx=$bl_t rx=$bl_r"
id_s=$(awk '$1=="idle"{print $2+$3+$4+$5; exit}' "$TMPD/proc.txt" | tr -d '\r')
[ "${id_s:-x}" = 0 ] && ok "COUNTER-PROBE: idle (never ran) has all four counters 0" || bad "idle counters sum '$id_s'"
cpu_n=$(num "$(col "$TMPD/proc.txt" cpuapp 4)")
[ "$cpu_n" = 0 ] && ok "COUNTER-PROBE: cpuapp (no network) has tx=0" || bad "cpuapp tx = $cpu_n"
# apprights list: same numbers + mask/ceil/data
ln=$(grep -a '^app netapp ' "$TMPD/list.txt" | head -1 | tr -d '\r')
echo "        list: $ln"
set -- $ln
[ "${3:-x}" = 4 ] && ok "list: netapp mask 4 (net)" || bad "list: netapp mask '${3:-}'"
[ "${4:-x}" = 4 ] && ok "list: netapp ceiling 4 (perm=net)" || bad "list: netapp ceiling '${4:-}'"
[ "${5:-0}" -gt 0 ] && ok "list: cpu counter present (${5:-})" || bad "list: cpu '${5:-}'"
[ "${9:-x}" = "data=0" ] && ok "list: data=0 (no /data/netapp)" || bad "list: data '${9:-}'"
lb=$(grep -a '^app blocked ' "$TMPD/list.txt" | head -1 | tr -d '\r'); set -- $lb
[ "${3:-x}" = 0 ] && ok "list: blocked mask 0 (declared, not granted)" || bad "list: blocked mask '${3:-}'"
[ "$(grep -ac '^app ' "$TMPD/list.txt")" = 6 ] && ok "list: 6 apps" || bad "list: $(grep -ac '^app ' "$TMPD/list.txt") apps"
# force stop
mapfile -t ST < <(grep -a '^apprights: stop ' "$TMPD/stop.txt" | tr -d '\r' | awk '{print $3}')
[ "${ST[0]:-x}" = 0 ] && ok "stop other (no such app): 0 tasks killed" || bad "stop other: '${ST[0]:-}'"
[ "${ST[1]:-0}" -ge 1 ] && ok "stop stopme: ${ST[1]} task(s) killed" || bad "stop stopme: '${ST[1]:-}'"
[ "${ST[2]:-x}" = 0 ] && ok "stop stopme again: 0 (the app is dead)" || bad "stop stopme again: '${ST[2]:-}'"
[ "${ST[3]:-0}" -ge 1 ] && ok "COUNTER-PROBE: keepme was alive until its own stop (${ST[3]} killed)" || bad "stop keepme: '${ST[3]:-}'"
echo "APPLOAD: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
