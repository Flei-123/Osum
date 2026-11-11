#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
HERE="$PWD"
export FIRNLIB="$HERE/lib"
T=$(mktemp -d)
trap 'if [ -n "${WLANBULK_KEEP:-}" ]; then rm -rf "$WLANBULK_KEEP"; mkdir -p "$WLANBULK_KEEP"; cp "$T"/*.klar "$WLANBULK_KEEP"/ 2>/dev/null; fi; rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' present" || ok "$3"; }
count_ge() { local c; c=$(grep -ac -- "$2" "$1"); [ "$c" -ge "$3" ] && ok "$4 ($c)" || bad "$4 -- '$2' seen $c times, want >= $3"; }
field() { grep -aoE "$2=[0-9]+" "$1" | tail -1 | cut -d= -f2; }
command -v qemu-system-x86_64 >/dev/null || { echo "WLANBULK: skipped, no qemu"; exit 0; }
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
. tools/lib/firnenv.sh
SNAPS=${WLANBULK_SNAPS:-8}
SNAP_SEC=${WLANBULK_SNAP_SEC:-6}
BODY=1048576
WORDS_ALL=${WLANBULK_WORDS:-"iwlfhtest iwlfhbind nic fakebulk fakeloss fakedup fakereord fakeamsdu faketxlag fakeaddba"}

mkdir -p "$T/blobs" "$T/bin"
python3 -I tools/iwlfh/ref.py gen "$T/blobs" || { bad "reference generator"; exit 1; }
EXPECT=$(python3 -I -c "import hashlib;print(hashlib.sha256(bytes(((j*7+3)&255) for j in range($BODY))).hexdigest())")
FWPATH=/lib/firmware/intel/iwlwifi/iwlwifi-8265-36.ucode
bash tools/sync/build.sh "$T/bin" 0 sh echo cat sleep dhcp wget shasum > "$T/b.txt" 2>&1 \
    && ok "programs build" || { bad "programs build"; tail "$T/b.txt"; echo "WLANBULK: $pass ok, $fail fail"; exit 1; }
./tools/build-kernel.sh "$T/k.img" --stufe 0 > "$T/k.txt" 2>&1 \
    && ok "kernel builds" || { bad "kernel build"; tail -30 "$T/k.txt"; echo "WLANBULK: $pass ok, $fail fail"; exit 1; }

{
    echo 'echo ==START=='
    i=0
    while [ "$i" -lt "$SNAPS" ]; do echo "sleep $SNAP_SEC"; i=$((i+1)); done
    echo 'echo ==WAITED=='
    echo 'dhcp'
    echo 'cat /proc/wlan'
    echo 'echo ==PRE=='
    echo 'wget -q -O /big.bin http://192.168.77.1/big'
    echo 'echo ==WGET=='
    echo 'shasum /big.bin'
    echo 'echo ==SUM=='
    echo 'cat /proc/wlan'
    echo 'echo ==END=='
} > "$T/s.sh"
printf 'ssid OrientFake\npsk orient-fake-pw1\n' > "$T/good.conf"
printf 'nameserver 192.168.1.1\nfallback 1.1.1.1\n' > "$T/resolv.old"

image() {
    local n=$1
    bash tools/mkfsfi/mkfs.sh build "$T/$n.img" 40000 --v3 /bin/ /t/ /etc/ /proc/ /lib/ /lib/firmware/ /lib/firmware/intel/ /lib/firmware/intel/iwlwifi/ \
        /bin/sh="$T/bin/sh.elf" /bin/echo="$T/bin/echo.elf" /bin/cat="$T/bin/cat.elf" /bin/sleep="$T/bin/sleep.elf" /bin/dhcp="$T/bin/dhcp.elf" /bin/wget="$T/bin/wget.elf" /bin/shasum="$T/bin/shasum.elf" /etc/resolv.conf="$T/resolv.old" \
        "/t/s.sh=$T/s.sh" "$FWPATH=$T/blobs/v7.bin" "/etc/wlan.conf=$T/good.conf" > "$T/$n.mkfs" 2>&1 \
        || { tail -3 "$T/$n.mkfs"; return 1; }
}
run() {
    local n=$1 words=$2 limit=${3:-${WLANBULK_TIMEOUT:-1500}}
    timeout "$limit" qemu-system-x86_64 -accel "$ACC" -smp 1 -kernel "$T/k.img" -m 512 \
        -append "osum vfs $words script=sh /t/s.sh;exit" \
        -serial "file:$T/$n.txt" -display none -no-reboot -nic none \
        -drive "file=$T/$n.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$T/$n.txt" > "$T/$n.klar"
}
for n in a b c; do image $n || { bad "image $n"; exit 1; }; done

echo "-- running: full fault set, no-retransmit control, old TX behaviour control (parallel)"
only=${WLANBULK_ONLY:-abc}
case $only in *a*) run a "$WORDS_ALL" & ;; esac
case $only in *b*) run b "iwlfhtest iwlfhbind nic fakebulk fakeloss fakenoretx" "${WLANBULK_NEG_TIMEOUT:-420}" & ;; esac
case $only in *c*) run c "$WORDS_ALL wlnotxwait" & ;; esac
wait

f=$T/a.klar
awk '/==PRE==/{f=1} /==WGET==/{f=0} f' "$f" > "$T/a.w"
awk '/==WGET==/{f=1} /==SUM==/{f=0} f' "$f" > "$T/a.s"
awk '/==SUM==/{f=1} /==END==/{f=0} f' "$f" > "$T/a.p"
echo "-- A: 1 MiB download with loss, duplicates, reordering, A-MSDU, ADDBA, lagging TX responses"
has "$T/a.w" "octets $BODY" "download delivers all $BODY octets"
has "$T/a.w" 'status 200' "HTTP status 200"
has "$T/a.s" "$EXPECT" "sha256 of the body matches the generator"
count_ge "$f" 'fakeap: lost' 5 "AP dropped downlink segments"
count_ge "$f" 'fakeap: dup' 5 "AP duplicated downlink segments"
count_ge "$f" 'fakeap: held' 5 "AP reordered downlink segments"
count_ge "$f" 'fakeap: retx' 3 "AP went back after duplicate ACKs"
has "$f" 'fakeap: addba req' "AP sent an ADDBA request"
has "$f" 'fakeap: addba declined' "AP received the decline (status 37)"
has "$f" '==END==' "system keeps running"
am=$(field "$T/a.p" amsdu); tf=$(field "$T/a.p" txfull); ad=$(field "$T/a.p" addba)
[ "${am:-0}" -ge 100 ] && ok "A-MSDU frames split by the station ($am)" || bad "A-MSDU count ${am:-none}, want >= 100"
[ "${tf:-0}" -ge 1 ] && ok "full TX queue held frames back (txfull=$tf)" || bad "txfull=${tf:-none}, want >= 1"
[ "${ad:-0}" -ge 1 ] && ok "station declined the ADDBA request ($ad)" || bad "addba=${ad:-none}, want >= 1"

echo "-- B: control without AP retransmission: the loss must stall the download"
fb=$T/b.klar
count_ge "$fb" 'fakeap: lost' 1 "control: the AP really dropped a segment"
hasnot "$fb" "octets $BODY" "control: no complete download without retransmission"

echo "-- C: control with the old TX behaviour (wlnotxwait): frames are not held back"
fc=$T/c.klar
awk '/==SUM==/{f=1} /==END==/{f=0} f' "$fc" > "$T/c.p"
tc=$(field "$T/c.p" txfull)
[ "${tc:-x}" = "0" ] && ok "control: txfull stays 0 with wlnotxwait" || bad "control: txfull=${tc:-none}, want 0"

echo "WLANBULK: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
