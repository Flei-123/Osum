#!/bin/bash
set -u
cd "$(dirname "$0")/../.."
FIXED_IMG=${FIXED_IMG:?FIXED_IMG = stick image built with HANGSLOT_PREBUILD=1}
BASE_IMG=${BASE_IMG:?BASE_IMG = stick image built with HANGSLOT_PREBUILD=0}
WRITE_IOPS=${WRITE_IOPS:-12}
MIN_SAVED_WRITES=${MIN_SAVED_WRITES:-12}
BOOT_SECS=${BOOT_SECS:-150}
OVMF_CODE=/usr/share/OVMF/OVMF_CODE_4M.fd
OVMF_VARS=/usr/share/OVMF/OVMF_VARS_4M.fd
[ -f "$OVMF_CODE" ] && [ -f "$OVMF_VARS" ] || { echo "DELLSTICK: OVMF firmware missing"; exit 1; }
pass=0; fail=0
ok()  { echo "  OK    $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; fail=$((fail+1)); }
D=$(mktemp -d /root/abbilder/dellstick.XXXXXX)
[ -n "${KEEP:-}" ] || trap 'rm -rf "$D"' EXIT
KVM=(); [ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)

boot() {
    local name=$1 img=$2
    cp --reflink=auto "$img" "$D/$name.img"
    cp "$OVMF_VARS" "$D/$name.vars"
    timeout "$BOOT_SECS" qemu-system-x86_64 -machine q35 "${KVM[@]}" -smp 4 -m 2048 \
        -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
        -drive if=pflash,format=raw,file="$D/$name.vars" \
        -drive "file=$D/$name.img,format=raw,if=none,id=stick,throttling.iops-write=$WRITE_IOPS" \
        -device qemu-xhci -device usb-storage,drive=stick,bootindex=0 \
        -display none -serial "file:$D/$name.ser" -monitor "unix:$D/$name.mon,server,nowait" -no-reboot > /dev/null 2>&1 &
    local pid=$! t=0 writes=-1
    while [ $t -lt "$BOOT_SECS" ] && kill -0 $pid 2>/dev/null; do
        if [ "$writes" -lt 0 ] && grep -aq "hangslot: ready\|hang: detected" "$D/$name.ser" 2>/dev/null; then
            writes=$(echo "info blockstats" | socat - "UNIX-CONNECT:$D/$name.mon" 2>/dev/null | grep -a -o "stick: rd_bytes=[0-9]* wr_bytes=[0-9]* rd_operations=[0-9]* wr_operations=[0-9]*" | grep -o "wr_operations=[0-9]*" | head -1 | cut -d= -f2)
            writes=${writes:-0}
        fi
        grep -aq "glogin: first up=\|hang: resetting" "$D/$name.ser" 2>/dev/null && break
        sleep 1; t=$((t+1))
    done
    kill $pid 2>/dev/null; wait $pid 2>/dev/null
    echo "  $name: $t s, device writes at hangslot ready: $writes"
    eval "${name}_writes=$writes"
}

echo "DELLSTICK: fixed image, writes throttled to $WRITE_IOPS iops"
boot fixed "$FIXED_IMG"
grep -aq "hangslot: ready" "$D/fixed.ser" && ok "fixed: hangslot ready" || bad "fixed: hangslot ready"
grep -aq "glogin: first up=" "$D/fixed.ser" && ok "fixed: login screen reached" || bad "fixed: login screen reached"
grep -aq "hang: detected" "$D/fixed.ser" && bad "fixed: no hang report" || ok "fixed: no hang report"

echo "DELLSTICK: counter-proof, image without prebuilt /var/crash/hangslot"
boot base "$BASE_IMG"
if [ "$base_writes" -ge 0 ] && [ "$fixed_writes" -ge 0 ] && [ $((base_writes - fixed_writes)) -ge "$MIN_SAVED_WRITES" ]; then
    ok "prebuilt slot saves $((base_writes - fixed_writes)) device writes at boot"
else
    bad "prebuilt slot saves at least $MIN_SAVED_WRITES device writes (fixed $fixed_writes, base $base_writes)"
fi

echo "DELLSTICK: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
