#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
ACC=$([ -e /dev/kvm ] && echo kvm || echo tcg)
finish() { echo "NMI-MANUAL: $pass passed, $fail failed"; [ "$fail" = 0 ]; exit $?; }
. tools/lib/firnenv.sh
mkdir -p "$D/bin"
bash tools/sync/build.sh "$D/bin" 0 sh sleep echo > "$D/b.txt" 2>&1 && ok "programs build" || { bad "programs"; finish; }
K="${KERNEL:-}"
if [ -z "$K" ]; then
    K="$D/k.mb"
    ./tools/build-kernel.sh "$K" --stufe 0 > "$D/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel"; finish; }
fi
BASE_K="${BASE_KERNEL:-}"
{ for i in $(seq 1 40); do echo "sleep 2"; echo "echo tick"; done; } > "$D/s.sh"
bash tools/mkfsfi/mkfs.sh build "$D/base.img" 20000 /lib/ \
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
    /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ \
    "/bin/sh=$D/bin/sh.elf" "/bin/sleep=$D/bin/sleep.elf" "/bin/echo=$D/bin/echo.elf" \
    "/t/s.sh=$D/s.sh" > "$D/mkfs.txt" 2>&1 || tail -3 "$D/mkfs.txt"
runvm() {
    local name=$1 kernel=$2 cpu=$3 smp=$4 words=${5:-}
    cp "$D/base.img" "$D/d-$name.img"
    (timeout -s KILL 60 qemu-system-x86_64 -accel "$ACC" -machine q35 -cpu "$cpu" -smp "$smp" -m 1024 -kernel "$kernel" \
        -append "smpfrueh osum vfs $words script=sh /t/s.sh;exit" \
        -serial "file:$D/o-$name.txt" -display none -monitor "unix:$D/m-$name.sock,server,nowait" \
        -drive "file=$D/d-$name.img,format=raw,if=ide,index=0" </dev/null >/dev/null 2>&1) &
    local pid=$!
    sleep 14
    python3 - "$D/m-$name.sock" <<'EOF'
import socket, sys, time
s = socket.socket(socket.AF_UNIX)
s.connect(sys.argv[1])
time.sleep(0.5)
s.sendall(b"nmi\n")
time.sleep(0.5)
s.close()
EOF
    sleep 8
    kill -KILL "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    tr -cd '\11\12\15\40-\176' < "$D/o-$name.txt" > "$D/$name.klar"
    rm -f "$D/d-$name.img" "$D/o-$name.txt"
}
runvm nopmu "$K" qemu64 2 nopmu &
runvm pmu "$K" "Skylake-Client,pmu=on" 2 &
[ -n "$BASE_K" ] && runvm base "$BASE_K" qemu64 2 &
wait
grep -q "hang: detected reason=manual" "$D/nopmu.klar" && ok "no pmu: injected nmi triggers a manual dump" || bad "no pmu: no manual dump"
grep -q "cpu " "$D/nopmu.klar" && ok "no pmu: dump lines present" || bad "no pmu: dump lines missing"
grep -q "hang: detected reason=manual" "$D/pmu.klar" && bad "pmu: injected nmi must stay a stray" || ok "pmu: injected nmi stays a stray"
if [ -n "$BASE_K" ]; then
    grep -q "hang: detected reason=manual" "$D/base.klar" && bad "control kernel dumped" || ok "control kernel: no dump"
fi
grep -q "tick" "$D/nopmu.klar" && ok "no pmu: guest keeps running after the dump" || bad "no pmu: guest stopped"
[ -n "${NMI_KEEP:-}" ] && { mkdir -p "$NMI_KEEP"; cp "$D"/*.klar "$NMI_KEEP/"; }
finish
