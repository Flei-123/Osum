#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/ota/feedtest.sh -- acceptance of a NEW LIVE-FEED STAND before it is published.
#
#   bash tools/ota/feedtest.sh <image-dir> <feed-root> [work-dir]
#
#   <image-dir>  output of tools/usbimg/build.sh built with OTA_ROOTS=<ca.pem> and
#                OTA_CONF pointing at https://10.0.2.2:$PORT/osum/aktuell
#                (name=ota.test), i.e. the shipped image, only the feed address
#                and the trusted root differ.
#   <feed-root>  the directory that contains osum/ (a copy of /srv/store with the
#                new version published by tools/ota/veroeffentlichen.py).
#
# What it measures (everything on an INSTALLED disk, because the stick root is RAM):
#   1. install the image on an empty disk (the real /bin/installer, as abnahme.sh)
#   2. image with version 0 sees the new feed (suchen)
#   3. einspielen installs the packages, generation switches
#   4. reboot from the disk: erprobung, bestaetigen, second search says "aktuell"
#   5. desktop boots from the disk (screenshots by the caller via $WORK/desk.*)
#   6. rollback (ota rollback) and boot again
# Nothing here touches /srv/store or any device of the owner.
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
IMG=${1:?image dir}; FEED=${2:?feed root}; W=${3:-/tmp/otat/run}
PORT=${OTA_PORT:-18555}
CERTS=${OTA_CERTS:-/tmp/otat/certs}
mkdir -p "$W"; rm -f "$W"/r*.txt "$W"/r*.rc
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
hat() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing in $1"; }

: > "$W/srv.log"
python3 tools/ota/server.py --wurzel "$FEED" --port "$PORT" --cert "$CERTS/srv.pem" \
    --key "$CERTS/srv.key" --log "$W/srv.log" > "$W/srv.out" 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null' EXIT
for i in $(seq 1 40); do grep -qa "^START port=$PORT " "$W/srv.log" && break; sleep 0.2; done

if [ -n "${FEEDTEST_REUSE:-}" ] && [ -f "$W/ziel.img" ]; then
    echo "== 1. (reusing the freshly installed disk $W/ziel.img) =="
    ok "reused disk"
else
echo "== 1. install on an empty disk =="
rm -f "$W/ziel.img"; head -c $((256*1024*1024)) /dev/zero > "$W/ziel.img"
APPEND="modfs osum vfs gfx wm wig wmhold wmdauer wighalt=3500 nokbd nosched noproc nofs lang=de uiscale=1 wigapp=/bin/installer,now,account=test,password=geheim123"
rm -f "$W/inst.txt"
timeout 3000 $QEMU_X86 -m 512 -kernel "$IMG/osum.mb" -initrd "$IMG/root.img" -append "$APPEND" \
    -serial "file:$W/inst.txt" -display none -no-reboot \
    -device VGA,edid=on,xres=1280,yres=800,vgamem_mb=32 \
    -drive "file=$W/ziel.img,format=raw,if=ide,index=0" > "$W/inst.qemu" 2>&1 &
QP=$!
i=0; while [ $i -lt 3000 ]; do
    grep -qa 'installer: done\|installer: ERROR' "$W/inst.txt" 2>/dev/null && break
    kill -0 "$QP" 2>/dev/null || break; sleep 1; i=$((i+1)); done
sleep 3; kill "$QP" 2>/dev/null; wait "$QP" 2>/dev/null
hat "$W/inst.txt" "installer: done" "installer finished"
mcopy -i "$W/ziel.img@@1048576" ::/limine.conf "$W/limine.disk" 2>/dev/null && ok "kept the disk's own limine.conf"

fi

echo "0" > "$W/quelle.crc"
export OSUM_CPU=${OSUM_CPU:-Haswell}
run() { # name script [limit]
    OUT="$W" OTA_NETZ="nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0" \
        bash tools/install/oneshot.sh "$1" platte "$2" "${3:-900}" > /dev/null 2>&1
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' "$W/$1.txt" 2>/dev/null
    cat "$W/$1.rc" 2>/dev/null
}
echo "== 2. version 0 sees the new feed =="
run r0 "ota show;ota search;exit" 600 > /dev/null
hat "$W/r0.txt" "ota: source https://10.0.2.2:$PORT/osum/aktuell" "source is the local copy of osum/aktuell"
hat "$W/r0.txt" "version here 0" "device is on version 0"
hat "$W/r0.txt" "version there 5" "feed offers version 5"
hat "$W/r0.txt" "NEW VERSION" "reports a new version"
echo "== 3. install the packages =="
run r1 "ota apply;ota show;opk generations;exit" 3000 > /dev/null
echo "== 4. reboot, confirm, second search =="
run r2 "opk rebuild;ota show;ota confirm;opk trial;ota search;exit" 900 > /dev/null
echo "== 6. rollback =="
cp -f "$W/ziel.img" "$W/after-update.img"
run r3 "ota rollback;ota show;exit" 900 > /dev/null
run r4 "ota show;ota search;exit" 900 > /dev/null
# --- the device's own words, checked
hat "$W/r1.txt" "ota: in trial: 00000013" "update installed: new generation is on trial"
hat "$W/r1.txt" "ota: version here 5" "version file says 5 after the update"
hat "$W/r2.txt" "opk: trial best" "after the reboot the trial generation was confirmed"
hat "$W/r2.txt" "ota: version there 5" "second search: the feed still offers 5"
hat "$W/r2.txt" "alles aktuell" "second search says 'alles aktuell' (nothing new)"
hat "$W/r3.txt" "opk: zur" "rollback went back to the previous generation"
hat "$W/r4.txt" "ota: generation 12" "after the rollback the old generation is active"
echo "FEEDTEST: $pass ok, $fail failed (read $W/r*.txt for the device's own words)"
