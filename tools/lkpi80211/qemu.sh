#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there" || ok "$3"; }
hasre() { grep -qaE -- "$2" "$1" && ok "$3" || bad "$3 -- /$2/ missing"; }
command -v qemu-system-x86_64 >/dev/null || { echo "LKPI80211-QEMU: skipped, no qemu"; exit 0; }
. tools/lib/tmpdir.sh
D=$(mktemp -d); osum_tmp_guard "" "$D"
. tools/lib/firnenv.sh
. compat/linuxkpi/flags.sh
lkpi_fetch_headers wifi "$D/hdr" && export LKPI_INC || { echo "LKPI80211-QEMU: header fetch failed"; exit 1; }
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
keep() {
    [ -n "${LKPI80211_OUT:-}" ] || return 0
    mkdir -p "$LKPI80211_OUT" && cp "$D"/*.klar "$LKPI80211_OUT"/ 2>/dev/null
    return 0
}
fin() { keep; echo "LKPI80211-QEMU: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }
SHIM=compat/linuxkpi/shim
PROGS="sh cat echo drvctl sleep ping"
SSID_PSK_GOOD='ssid OrientFake\npsk orient-fake-pw1\n'
SSID_PSK_BAD='ssid OrientFake\npsk wrong-passphrase\n'

bash compat/linuxkpi/wifimod.sh "$D/m" > "$D/mod.txt" 2>&1 && ok "wifi shim and fake radio build, closure ok, modules signed" || { bad "module build"; tail -5 "$D/mod.txt"; fin; }
PK_OK=$(bash compat/linuxkpi/wifipack.sh "$D/m/linuxkpiwifi.omod" "$D/m/wififake_drv.omod" "$D/pk-ok" 2> "$D/pack-ok.txt")
mutant_pack() {
    local name=$1 file=$2 expr=$3 m="$D/mu-$1"
    rm -rf "$m"; cp -r "$SHIM" "$m"
    sed -i "$expr" "$m/$file"
    cmp -s "$m/$file" "$SHIM/$file" && { bad "mutant $name did not apply"; return 1; }
    bash compat/linuxkpi/wifimod.sh "$D/mo-$name" "$m" > "$D/mod-$name.txt" 2>&1 || { bad "mutant $name does not build"; tail -3 "$D/mod-$name.txt"; return 1; }
    bash compat/linuxkpi/wifipack.sh "$D/mo-$name/linuxkpiwifi.omod" "$D/mo-$name/wififake_drv.omod" "$D/pk-$name" 2> "$D/pack-$name.txt"
}
PK_NOBSSID=$(mutant_pack nobssid src/wifi_glue.c '/memcpy(w->bssid/d')
PK_NOSTA=$(mutant_pack nosta src/wifi_glue.c '/memcpy(w->sta.sta.addr/d')
[ -d "$PK_OK" ] && [ -d "$PK_NOBSSID" ] && [ -d "$PK_NOSTA" ] && ok "store packages built (good, no-bssid mutant, no-sta-addr mutant)" || { bad "packages"; fin; }

mkdir -p "$D/bin"
bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/p.txt" 2>&1 && ok "programs build" || { bad "programs"; head -10 "$D/p.txt"; fin; }
if [ -n "${LKPI80211_KERNEL:-}" ]; then cp "$LKPI80211_KERNEL" "$D/k0.img"; ok "kernel supplied"; else
    ./tools/build-kernel.sh "$D/k0.img" --stufe 0 > "$D/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel"; tail -5 "$D/k.txt"; fin; }
fi

{
    echo 'echo ==START=='
    for i in 1 2 3 4 5 6 7 8; do echo 'sleep 6'; done
    echo 'echo ==WAITED=='
    echo 'cat /proc/drivers'
    echo 'cat /proc/wlan'
    echo 'ping -c 3 192.168.77.1'
    echo 'echo ==PING=='
    echo 'cat /proc/wlan'
    echo 'echo ==END=='
} > "$D/s.sh"
printf 'tiers=native+compat\n' > "$D/conf-both"
printf 'tiers=native\n' > "$D/conf-native"
printf "$SSID_PSK_GOOD" > "$D/good.conf"
printf "$SSID_PSK_BAD" > "$D/bad.conf"

mkimg() {
    local name=$1 drvconf=$2 wconf=$3 pkg=$4 files="" f
    if [ -n "$pkg" ]; then
        files="/lib/drivers/ /lib/drivers/$(basename "$pkg")/"
        for f in $(ls "$pkg"); do files="$files /lib/drivers/$(basename "$pkg")/$f=$pkg/$f"; done
    fi
    bash tools/mkfsfi/mkfs.sh build "$D/d-$name.img" 20000 /lib/ \
        /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ \
        $(for p in $PROGS; do echo "/bin/$p=$D/bin/$p.elf"; done) \
        "/t/s.sh=$D/s.sh" "/etc/drvstore.conf=$drvconf" "/etc/wlan.conf=$wconf" $files > "$D/mkfs-$name.txt" 2>&1 || tail -3 "$D/mkfs-$name.txt"
}
runvm() {
    local name=$1
    timeout 300 qemu-system-x86_64 -accel "$ACC" -smp 1 -kernel "$D/k0.img" -m 512 \
        -append "osum vfs nic script=sh /t/s.sh;exit" \
        -serial "file:$D/o-$name.txt" -display none -no-reboot -nic none -device edu \
        -drive "file=$D/d-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$D/o-$name.txt" > "$D/$name.klar"
}
mkimg ok "$D/conf-both" "$D/good.conf" "$PK_OK"
mkimg badpsk "$D/conf-both" "$D/bad.conf" "$PK_OK"
mkimg nobssid "$D/conf-both" "$D/good.conf" "$PK_NOBSSID"
mkimg nosta "$D/conf-both" "$D/good.conf" "$PK_NOSTA"
mkimg native "$D/conf-native" "$D/good.conf" "$PK_OK"
mkimg nopkg "$D/conf-both" "$D/good.conf" ""
for v in ${LKPI80211_SCEN:-ok badpsk nobssid nosta native nopkg}; do runvm $v & done
wait

for v in ok badpsk nobssid nosta native nopkg; do
    has "$D/$v.klar" "==END==" "$v: script ran to the end"
    hasnot "$D/$v.klar" "EXCEPTION" "$v: no kernel exception"
done
PING='octets from 192\.168\.77\.1'
has "$D/ok.klar" "lkpi: wifi fake radio registered" "ok: fake mac80211 radio registered through the shim"
hasre "$D/ok.klar" '^drvstore: bind lkpi-wififake -> [0-9a-f]{2}:[0-9a-f]{2}\.[0-9a-f] 1234:11e8 ok' "ok: store bound lkpi-wififake"
has "$D/ok.klar" "fakeap: auth" "ok: auth frame went stack -> shim -> fake radio -> AP"
has "$D/ok.klar" "fakeap: assoc" "ok: association reached the AP"
has "$D/ok.klar" "fakeap: m2 ok" "ok: WPA2 message 2 verified by the AP"
has "$D/ok.klar" "fakeap: m4 ok" "ok: WPA2 handshake complete"
has "$D/ok.klar" "auto=up rc=0" "ok: own stack reports the link up"
has "$D/ok.klar" "fakeap: icmp" "ok: ICMP echo reached the AP through the shim"
awk '/==WAITED==/{f=1} /==PING==/{f=0} f' "$D/ok.klar" > "$D/ok.ping"
grep -aqE "$PING" "$D/ok.ping" && ok "ok: ping to the gateway answered" || { bad "ok: ping to the gateway not answered"; head -12 "$D/ok.ping"; }
hasnot "$D/ok.klar" "fakeap: m2 badmic" "ok: no bad MIC"
has "$D/badpsk.klar" "lkpi: wifi fake radio registered" "badpsk: radio registered"
has "$D/badpsk.klar" "fakeap: m2 badmic" "badpsk: AP rejects the wrong passphrase"
hasnot "$D/badpsk.klar" "fakeap: m4 ok" "badpsk: no handshake completion"
hasnot "$D/badpsk.klar" "auto=up rc=0" "badpsk: link never comes up"
awk '/==WAITED==/{f=1} /==PING==/{f=0} f' "$D/badpsk.klar" | grep -aqE "$PING" && bad "badpsk: ping answered with a wrong passphrase" || ok "badpsk: no ping reply"
for v in nobssid nosta; do
    has "$D/$v.klar" "lkpi: wifi fake radio registered" "$v: radio registered"
    hasnot "$D/$v.klar" "fakeap: m4 ok" "$v: no handshake without the stack-side address"
    hasnot "$D/$v.klar" "auto=up rc=0" "$v: link never comes up"
done
hasnot "$D/nobssid.klar" "fakeap: auth" "nobssid: radio filters frames to an unknown BSSID"
has "$D/native.klar" "drvstore: pkg lkpi-wififake rejected" "native: compat package refused by tier policy"
for v in native nopkg; do
    hasnot "$D/$v.klar" "lkpi: wifi fake radio registered" "$v: radio never registered"
    hasnot "$D/$v.klar" "fakeap:" "$v: AP never contacted"
    hasnot "$D/$v.klar" "auto=up rc=0" "$v: no link"
done
fin
