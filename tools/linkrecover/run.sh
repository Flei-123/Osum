#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$HERE"
CASES="${*:-flap stuck flap-noidlehouse stuck-nokickloop}"
OUTAGES="${LINKREC_OUTAGES:-8 25 60}"
LIMIT_S=${LINKREC_LIMIT_S:-30}
GW=192.168.42.129
LEASE=192.168.42.100
W=$(mktemp -d)
export USBTETHER_WORK="$W"
mkdir -p "$W/bin"
if [ -n "${LINKREC_PREBUILT:-}" ]; then
    cp "$LINKREC_PREBUILT"/bin/*.elf "$W/bin/"
    cp "$LINKREC_PREBUILT/k.img" "$W/k.img"
else
    bash tools/sync/build.sh "$W/bin" 0 sh sleep echo dhcp ping host cat > "$W/b.txt" 2>&1 || { tail "$W/b.txt"; exit 1; }
    ./tools/build-kernel.sh "$W/k.img" --stufe 0 > "$W/k.txt" 2>&1 || { tail "$W/k.txt"; exit 1; }
fi
source tools/usbredir/common.sh
trap 'cleanup_pids; rm -rf "$W"' EXIT
printf 'echo ==START==\ndhcp dauer t1=12 &\nsleep 900\necho ==END==\n' > "$T/s_flap.sh"
bash tools/mkfsfi/mkfs.sh build "$T/d.img" 8000 /bin/ /t/ /etc/ /proc/ \
    /bin/sh="$T/bin/sh.elf" /bin/sleep="$T/bin/sleep.elf" /bin/echo="$T/bin/echo.elf" \
    /bin/dhcp="$T/bin/dhcp.elf" /bin/ping="$T/bin/ping.elf" /bin/host="$T/bin/host.elf" /bin/cat="$T/bin/cat.elf" \
    /t/s_flap.sh="$T/s_flap.sh" > "$T/mkfs2.txt" 2>&1 || { tail "$T/mkfs2.txt"; exit 1; }

lease_count() { tr -cd '\11\12\15\40-\176' < "$T/$1.txt" | grep -ac "dhcp: ack ip=$LEASE"; }

wait_leases() {
    local n=$1 want=$2 limit=$3 t0
    t0=$(date +%s)
    while [ $(( $(date +%s) - t0 )) -lt "$limit" ]; do
        [ "$(lease_count "$n")" -ge "$want" ] && return 0
        sleep 0.5
    done
    return 1
}

flap_driver() {
    local n=$1 ctl="$T/$1.wire" want=1 outage t_on t_back
    : > "$T/$n.rec"
    wait_leases "$n" 1 120 || { echo "boot nolease" >> "$T/$n.rec"; return; }
    for outage in $OUTAGES; do
        echo off > "$ctl"
        sleep "$outage"
        want=$((want + 1))
        t_on=$(date +%s.%N)
        echo on > "$ctl"
        if wait_leases "$n" "$want" 75; then
            t_back=$(date +%s.%N)
            echo "$outage $(python3 -I -c 'import sys;print("%.1f" % (float(sys.argv[2]) - float(sys.argv[1])))' "$t_on" "$t_back")" >> "$T/$n.rec"
        else
            echo "$outage never" >> "$T/$n.rec"
            want=$((want - 1))
        fi
    done
}

recovered_all() {
    local n=$1 cycles bad_cycles
    cycles=$(echo $OUTAGES | wc -w)
    [ "$(grep -c '^[0-9]' "$T/$n.rec")" -eq "$cycles" ] || return 1
    bad_cycles=$(awk -v lim="$LIMIT_S" '$2 == "never" || $2 + 0 >= lim { c++ } END { print c + 0 }' "$T/$n.rec")
    [ "$bad_cycles" -eq 0 ]
}

report_rec() { echo "        $1: $(tr '\n' ';' < "$T/$1.rec")"; }

flap_case() {
    local n=$1 expect=$2 words=$3 gargs=$4
    RUN_DRIVER=flap_driver QTIMEOUT=600 QWAIT=2 XWORDS="nethotwait $words" \
        XQEMU="-netdev user,id=pn0 -device e1000,netdev=pn0,mac=52:54:00:aa:bb:01" \
        GARGS="--phy-boot down --wire-ctl $T/$n.wire --max-secs 590 $gargs" run "$n" ch336 boot s_flap.sh
    report_rec "$n"
    chk "$n" "bound to driver ch336" 'driver=ch336'
    chk "$n" "first lease over the cable" "dhcp: ack ip=$LEASE"
    if [ "$expect" = recover ]; then
        recovered_all "$n" && ok "$n: lease back over the cable within $LIMIT_S s after every link-up" \
            || bad "$n: no lease within $LIMIT_S s after link-up ($(tr '\n' ';' < "$T/$n.rec"))"
    else
        recovered_all "$n" && bad "$n: recovered although the fix is disabled" \
            || ok "$n: negative control stays down"
    fi
    panics "$n"
}

for c in $CASES; do
    case "$c" in
    flap) flap_case flap recover "" "" ;;
    stuck) flap_case stuck recover "" "--phy-stuck" ;;
    flap-noidlehouse) flap_case flapnh stay "noidlehouse" "" ;;
    stuck-nokickloop) flap_case stucknk stay "nokickloop" "--phy-stuck" ;;
    *) bad "unknown case $c" ;;
    esac
done
echo "LINKREC: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
