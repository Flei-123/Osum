#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$HERE"
export FIRNLIB="$HERE/lib"
T=$(mktemp -d); trap 'kill $QPID 2>/dev/null; rm -rf "$T"' EXIT
QPID=""
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
command -v qemu-system-x86_64 >/dev/null || { echo "DBGSRV-QEMU: skipped, no qemu"; exit 0; }
command -v curl >/dev/null || { echo "DBGSRV-QEMU: skipped, no curl"; exit 0; }
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1

TOKEN=$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')
WRONG=$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')
P1=$((47000 + ($$ % 400) * 2)); P2=$((P1 + 1))
PROGS="init sh sleep echo dhcp dbgsrv lspci log wlanctl cat"

bash tools/sync/build.sh "$T/bin" 0 $PROGS > "$T/b.txt" 2>&1 || { tail "$T/b.txt"; echo "DBGSRV-QEMU: build failed"; exit 1; }
bash tools/build-kernel.sh "$T/k.mb" --stufe 0 > "$T/k.txt" 2>&1 || { tail "$T/k.txt"; echo "DBGSRV-QEMU: kernel build failed"; exit 1; }

printf '%s\n' "$TOKEN" > "$T/token"
cat > "$T/inittab" <<'TAB'
dhcp:*:once:/bin/dhcp
dbgsrv:*:respawn:/bin/dbgsrv:netz
pub:*:respawn:/bin/dbgsrv -p 8766 -X:netz,log=/var/log/dbgsrv.log
notoken:*:once:/bin/dbgsrv -k /etc/nope:netz
TAB
printf 'konsole\n' > "$T/ziel"
printf 'jarvisd-test-line\n' > "$T/jlog"
SPEC=""
for p in $PROGS; do SPEC="$SPEC /bin/$p=$T/bin/$p.elf@755:0:0"; done
python3 tools/osum/mkfs.py build "$T/d.img" 20480 --v3 /bin/ /etc/ /run/ /var/ /var/log/@755:0:0 /proc/ /tmp/ \
    $SPEC /etc/inittab="$T/inittab"@644:0:0 /etc/ziel="$T/ziel"@644:0:0 \
    /var/log/jarvisd.log="$T/jlog"@644:0:0 /etc/dbgsrv.token="$T/token"@600:0:0 > "$T/mkfs.txt" 2>&1 || { tail "$T/mkfs.txt"; echo "DBGSRV-QEMU: mkfs failed"; exit 1; }

ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
timeout 400 qemu-system-x86_64 -accel $ACC -kernel "$T/k.mb" -m 256 \
    -append "osum console=ttyS0 vfs usb usbpoll nic nip=169.254.10.1/16 nwait=0" \
    -serial "file:$T/ser.txt" -display none -no-reboot \
    -drive "file=$T/d.img,format=raw,if=ide" \
    -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:$P1-:8765,hostfwd=tcp:127.0.0.1:$P2-:8766" \
    -device qemu-xhci,id=x0 -device usb-net,netdev=n0,mac=52:54:00:12:34:77 \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$T/qemu.out" 2>&1 &
QPID=$!
S="$T/ser.txt"
klar() { [ -f "$S" ] || return 0; tr -cd '\11\12\15\40-\176' < "$S"; }
waitfor() { local i=0; while [ $i -lt $2 ]; do klar | grep -aq -- "$1" && return 0; kill -0 $QPID 2>/dev/null || return 1; sleep 1; i=$((i+1)); done; return 1; }

if waitfor 'dbgsrv: listening on 8765' 200; then ok "dbgsrv listens after DHCP over the USB function"; else bad "dbgsrv never listened"; head -5 "$T/qemu.out"; klar | tail -30; fi
waitfor 'dbgsrv: address is http://10.0.2.15:8765/' 60; klar | grep -aq 'dhcp: ack ip=10.0.2.15' && ok "DHCP lease on usb-net" || bad "no DHCP lease"
klar | grep -aq 'dbgsrv: address is http://10.0.2.15:8765/' && ok "address announced on the console" || bad "address line missing"

U="http://127.0.0.1:$P1"
get() { curl -s -m 20 -D "$T/h.txt" -o "$T/o.txt" "$@"; echo $?; }
code() { head -1 "$T/h.txt" | tr -d '\r'; }

rc=$(get "$U/wlan"); [ "$(code)" = "HTTP/1.0 401 Unauthorized" ] && ok "no token -> 401" || bad "no token: $(code) rc=$rc"
rc=$(get -H "X-Token: $WRONG" "$U/wlan"); [ "$(code)" = "HTTP/1.0 401 Unauthorized" ] && ! grep -q 'state' "$T/o.txt" && ok "wrong token -> 401, no data" || bad "wrong token: $(code)"
rc=$(get -H "X-Token: ${TOKEN%?}" "$U/wlan"); [ "$(code)" = "HTTP/1.0 401 Unauthorized" ] && ok "token prefix -> 401" || bad "token prefix: $(code)"
rc=$(get "$U/wlan?t=$WRONG"); [ "$(code)" = "HTTP/1.0 401 Unauthorized" ] && ok "wrong query token -> 401" || bad "wrong query token: $(code)"
rc=$(get -H "X-Token: $TOKEN" "$U/wlan"); [ "$(code)" = "HTTP/1.0 200 OK" ] && [ -s "$T/o.txt" ] && ok "GET /wlan with X-Token -> 200 + body" || bad "/wlan: $(code) $(wc -c < "$T/o.txt")"
rc=$(get -H "Authorization: Bearer $TOKEN" "$U/drivers"); [ "$(code)" = "HTTP/1.0 200 OK" ] && grep -q 'usb-net' "$T/o.txt" && ok "GET /drivers with Bearer lists usb-net" || bad "/drivers: $(code)"
rc=$(get "$U/net?t=$TOKEN"); [ "$(code)" = "HTTP/1.0 200 OK" ] && [ -s "$T/o.txt" ] && ok "GET /net with query token" || bad "/net: $(code)"
for r in lspci lspci/v dmesg klog pci usb version uptime wlanctl/status wlanctl/dump wlanpoll wlanirq usbnet time wlanctl/knobs ; do
    rc=$(get -H "X-Token: $TOKEN" "$U/$r")
    if [ "$(code)" = "HTTP/1.0 200 OK" ] && [ -s "$T/o.txt" ] && ! grep -q 'cannot read\|cannot run' "$T/o.txt"; then ok "GET /$r -> 200 + body ($(wc -c < "$T/o.txt") B)"; else bad "/$r: $(code) $(head -c 80 "$T/o.txt")"; fi
done
rc=$(get -H "X-Token: $TOKEN" "$U/usbsum"); [ "$(code)" = "HTTP/1.0 200 OK" ] && ok "GET /usbsum answers 200 (file may be absent on this kernel)" || bad "/usbsum: $(code)"
rc=$(get -H "X-Token: $TOKEN" "$U/time"); grep -q '^rtc 20[0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9:]* mode=\(local\|utc\) frame=' "$T/o.txt" && grep -q ' rule=.* base=[+-][0-9]* dst=[01]$' "$T/o.txt" && grep -q '^utc 20[0-9][0-9]-.* local 20[0-9][0-9]-.* off=[+-][0-9]* conv=[0-9]* moved=[0-9]*' "$T/o.txt" && ok "/time (= /proc/clock) shows RTC, mode, zone and epoch lines" || bad "/time content: $(head -c 200 "$T/o.txt")"
rc=$(get -H "X-Token: $TOKEN" "$U/wlanctl/knobs"); grep -q '^iwlnoipoll=off$' "$T/o.txt" && ! grep -q '=on' "$T/o.txt" && ok "/wlanctl/knobs lists the whitelist, all off at boot" || bad "/wlanctl/knobs: $(head -c 200 "$T/o.txt")"
rc=$(get -H "X-Token: $TOKEN" "$U/wlanctl/reload"); [ "$(code)" = "HTTP/1.0 404 Not Found" ] && ok "GET /wlanctl/reload is not a route -> 404" || bad "GET reload: $(code)"
post() { curl -s -m 30 -X POST -D "$T/h.txt" -o "$T/o.txt" "$@"; echo $?; }
knobs() { curl -s -m 20 -H "X-Token: $TOKEN" "$U/wlanctl/knobs"; }
R="$U/wlanctl/reload"
rc=$(post "$R?param=iwlnoipoll&value=on"); [ "$(code)" = "HTTP/1.0 401 Unauthorized" ] && ok "POST without token -> 401" || bad "POST no token: $(code)"
rc=$(post -H "X-Token: $WRONG" "$R?param=iwlnoipoll&value=on"); [ "$(code)" = "HTTP/1.0 401 Unauthorized" ] && ok "POST with wrong token -> 401" || bad "POST wrong token: $(code)"
rc=$(post "$R?param=iwlnoipoll&value=on&t=$TOKEN"); [ "$(code)" = "HTTP/1.0 401 Unauthorized" ] && ok "POST with the token only in the query -> 401" || bad "POST query token: $(code)"
knobs | grep -q '=on' && bad "a refused POST changed a knob" || ok "refused POSTs changed nothing"
rc=$(post -H "X-Token: $TOKEN" "$R?param=bogus&value=on"); [ "$(code)" = "HTTP/1.0 400 Bad Request" ] && ok "POST unknown param -> 400" || bad "POST unknown param: $(code)"
rc=$(post -H "X-Token: $TOKEN" "$R?param=iwlnoipoll&value=7"); [ "$(code)" = "HTTP/1.0 400 Bad Request" ] && ok "POST unknown value -> 400" || bad "POST unknown value: $(code)"
rc=$(post -H "X-Token: $TOKEN" "$R?param=iwlnoipoll&value=on;id"); [ "$(code)" = "HTTP/1.0 400 Bad Request" ] && ok "POST with trailing shell text -> 400" || bad "POST injection: $(code)"
rc=$(post -H "X-Token: $TOKEN" "$R"); [ "$(code)" = "HTTP/1.0 400 Bad Request" ] && ok "POST without parameters -> 400" || bad "POST bare: $(code)"
knobs | grep -q '=on' && bad "a rejected POST changed a knob" || ok "rejected POSTs changed nothing"
rc=$(post -H "X-Token: $TOKEN" "$U/wlan?param=none"); [ "$(code)" = "HTTP/1.0 405 Method Not Allowed" ] && ok "POST to a read-only route -> 405" || bad "POST /wlan: $(code)"
rc=$(post -H "X-Token: $TOKEN" "$U/etc/passwd"); [ "$(code)" = "HTTP/1.0 405 Method Not Allowed" ] && ok "POST to an unknown path -> 405" || bad "POST /etc/passwd: $(code)"
rc=$(post -H "X-Token: $TOKEN" "$R?param=iwlnoipoll&value=on"); [ "$(code)" = "HTTP/1.0 200 OK" ] && grep -q 'knob=iwlnoipoll value=1' "$T/o.txt" && ok "POST whitelisted knob on -> 200 + reload requested" || bad "POST knob on: $(code) $(head -c 120 "$T/o.txt")"
knobs | grep -q '^iwlnoipoll=on$' && ok "the knob is on afterwards" || bad "knob did not switch on"
knobs | grep -c '=on' | grep -q '^1$' && ok "only that knob is on" || bad "other knobs changed"
sleep 3
rc=$(post -H "X-Token: $TOKEN" "$R?param=iwlnoipoll&value=off"); [ "$(code)" = "HTTP/1.0 200 OK" ] && ok "POST whitelisted knob off -> 200" || bad "POST knob off: $(code)"
knobs | grep -q '^iwlnoipoll=off$' && ok "the knob is off again (counter-proof of the switch)" || bad "knob did not switch off"
rc=$(post -H "X-Token: $TOKEN" "$R?param=none"); [ "$(code)" = "HTTP/1.0 200 OK" ] && ok "POST plain reload -> 200" || bad "POST plain: $(code)"
rm -f "$T/o.txt"; rc=$(curl -s -m 15 -X POST -o "$T/o.txt" -H "X-Token: $TOKEN" "http://127.0.0.1:$P2/wlanctl/reload?param=none"; echo $?)
[ "$rc" != 0 ] && [ ! -s "$T/o.txt" ] && ok "POST from a public-address peer is dropped even with the right token" || bad "public-peer POST answered (rc=$rc)"
rc=$(get -H "X-Token: $TOKEN" "$U/lspci"); grep -q '00:' "$T/o.txt" && ok "/lspci shows bus addresses" || bad "/lspci content"
rc=$(get -H "X-Token: $TOKEN" "$U/"); grep -q '^/wlan$' "$T/o.txt" && grep -q '^/dmesg$' "$T/o.txt" && ok "/ lists the endpoints" || bad "index content"
rc=$(get -H "X-Token: $TOKEN" "$U/etc/passwd"); [ "$(code)" = "HTTP/1.0 404 Not Found" ] && ok "unknown path -> 404" || bad "/etc/passwd: $(code)"
rc=$(get --path-as-is -H "X-Token: $TOKEN" "$U/../etc/shadow"); [ "$(code)" = "HTTP/1.0 404 Not Found" ] && ok "path traversal -> 404" || bad "traversal: $(code)"
rc=$(get -X POST -d x=1 -H "X-Token: $TOKEN" "$U/wlan"); [ "$(code)" = "HTTP/1.0 405 Method Not Allowed" ] && ok "POST -> 405" || bad "POST: $(code)"
rc=$(get -X PUT -d x=1 -H "X-Token: $TOKEN" "$U/wlan"); [ "$(code)" = "HTTP/1.0 405 Method Not Allowed" ] && ok "PUT -> 405" || bad "PUT: $(code)"
rc=$(get -X DELETE -H "X-Token: $TOKEN" "$U/wlan"); [ "$(code)" = "HTTP/1.0 405 Method Not Allowed" ] && ok "DELETE -> 405" || bad "DELETE: $(code)"

rm -f "$T/o.txt"; rc=$(curl -s -m 15 -o "$T/o.txt" -H "X-Token: $TOKEN" "http://127.0.0.1:$P2/wlan"; echo $?)
[ "$rc" != 0 ] && [ ! -s "$T/o.txt" ] && ok "public-address peer is dropped even with the right token (curl rc=$rc)" || bad "public-peer instance answered (rc=$rc)"
rc=$(get -H "X-Token: $TOKEN" "$U/dbgsrvlog"); grep -q 'refused non-local 10.0.2.2' "$T/o.txt" && ok "refusal logged with the peer address (read through /dbgsrvlog)" || bad "refusal not logged: $(head -c 100 "$T/o.txt")"
grep -q -- "$TOKEN" "$T/o.txt" && bad "token leaked into /dbgsrvlog" || ok "token not in /dbgsrvlog"
rc=$(get -H "X-Token: $TOKEN" "$U/svclog"); grep -q 'jarvisd-test-line' "$T/o.txt" && ok "GET /svclog returns the service log file" || bad "/svclog content"
klar | grep -aq 'dbgsrv: no token, refusing to start' && ok "tokenless instance says so and exits" || bad "no-token message missing"
klar | grep -aq 'dbgsrv: 401 bad token 10.0.2.2' && ok "bad tokens logged with the peer address" || bad "401 not logged"
klar | grep -aq -- "$TOKEN" && bad "token leaked to the console log" || ok "token never appears in the console log"

[ "$fail" = 0 ] || { echo "---- serial tail"; klar | tail -60; }
echo "DBGSRV-QEMU: $pass ok, $fail fail"
[ "$fail" = 0 ]
