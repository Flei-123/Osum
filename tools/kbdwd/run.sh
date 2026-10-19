#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/kbdwd/run.sh -- W-INPUTHANG gate: the wm watchdog rescues a PS/2 keyboard byte whose IRQ 1 was lost ("input dead, still image").
#   [STICK_DIR=<dir with root.img>] bash tools/kbdwd/run.sh
# Cases (QEMU, direct kernel boot, keys through the monitor):
#   1. normal            -> 5 keys arrive, no rescue needed
#   2. nokirq            -> IRQ 1 unrouted (lost interrupt): 5 keys STILL arrive, via `kbd: irq lost, rescued byte`
#   3. nokirq nokbdpoll  -> COUNTER-PROOF (behaviour before this round): no key arrives
set -uo pipefail
cd "$(dirname "$0")/../.."
STICK_DIR=${STICK_DIR:-/root/abbilder/pe5}
[ -f "$STICK_DIR/root.img" ] || { echo "FAIL: $STICK_DIR/root.img missing (set STICK_DIR)"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
OK=0; BAD=0
ok() { OK=$((OK+1)); echo "  OK    $1"; }
bad() { BAD=$((BAD+1)); echo "  FAIL  $1"; }
./tools/build-kernel.sh "$W/osum.mb" --stufe 0 >/dev/null 2>&1 || { echo "FAIL: kernel build"; exit 1; }
KVM=(-accel tcg); [ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)
run() { # name extra-words
    local n=$1 extra=$2
    cp "$STICK_DIR/root.img" "$W/$n.img"
    timeout 150 qemu-system-x86_64 "${KVM[@]}" -m 512 -kernel "$W/osum.mb" \
        -append "gfx fbres=1024x768 wm wig desk wmshell wmdauer herz nosched noproc nofs lang=de uiscale=1 $extra" \
        -serial "file:$W/$n.ser" -display none -no-reboot \
        -device VGA,edid=on,xres=1024,yres=768,vgamem_mb=32 \
        -monitor "unix:$W/$n.mon,server,nowait" \
        -drive "file=$W/$n.img,format=raw,if=ide,index=0" >/dev/null 2>&1 &
    local qp=$!
    for _ in $(seq 1 60); do grep -qa 'wm: ' "$W/$n.ser" 2>/dev/null && break; sleep 1; done
    sleep 8
    for k in a b c d e; do printf 'sendkey %s\n' $k | timeout 5 socat - "unix-connect:$W/$n.mon" >/dev/null 2>&1; sleep 0.5; done
    sleep 4
    kill $qp 2>/dev/null; wait $qp 2>/dev/null
    rm -f "$W/$n.img"
}
run base ""
run lost "nokirq"
run cproof "nokirq nokbdpoll"
n_base=$(grep -ac '^key: ' "$W/base.ser"); n_lost=$(grep -ac '^key: ' "$W/lost.ser"); n_cp=$(grep -ac '^key: ' "$W/cproof.ser")
r_base=$(grep -ac 'irq lost' "$W/base.ser"); r_lost=$(grep -ac 'irq lost' "$W/lost.ser")
[ "$n_base" -ge 5 ] && ok "normal: $n_base keys arrive" || bad "normal: only $n_base of 5 keys"
[ "$r_base" -eq 0 ] && ok "normal: the watchdog needed no rescue" || bad "normal: $r_base rescues although IRQ 1 works"
[ "$n_lost" -ge 5 ] && ok "lost IRQ 1: $n_lost keys still arrive (watchdog)" || bad "lost IRQ 1: only $n_lost of 5 keys"
[ "$r_lost" -ge 5 ] && ok "lost IRQ 1: rescued bytes reported ($r_lost lines)" || bad "lost IRQ 1: no rescue lines"
[ "$n_cp" -eq 0 ] && ok "counter-proof (nokbdpoll): no key arrives (the failure is real)" || bad "counter-proof: $n_cp keys arrived without the watchdog"
echo "KBDWD: $OK passed, $BAD failed"
[ "$BAD" -eq 0 ]
