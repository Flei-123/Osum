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
bash tools/build-kernel.sh "$T/k.mb" --gui off > "$T/k.txt" 2>&1 || { tail "$T/k.txt"; echo "DBGSRV-QEMU: kernel build failed"; exit 1; }

printf '%s\n' "$TOKEN" > "$T/token"
cat > "$T/inittab" <<'TAB'
dhcp:*:once:/bin/dhcp
dbgsrv:*:respawn:/bin/dbgsrv:netz
pub:*:respawn:/bin/dbgsrv -p 8766 -X:netz
notoken:*:once:/bin/dbgsrv -p 8767 -k /etc/missing.token:netz
TAB
printf 'konsole\n' > "$T/ziel"
SPEC=""
for p in $PROGS; do SPEC="$SPEC /bin/$p=$T/bin/$p.elf@755:0:0"; done
python3 tools/osum/mkfs.py build "$T/d.img" 20480 --v3 /bin/ /etc/ /run/ /var/ /var/log/@755:0:0 /proc/ /tmp/ \
    $SPEC /etc/inittab="$T/inittab"@644:0:0 /etc/ziel="$T/ziel"@644:0:0 \
    /etc/dbgsrv.token="$T/token"@600:0:0 > "$T/mkfs.txt" 2>&1 || { tail "$T/mkfs.txt"; echo "DBGSRV-QEMU: mkfs failed"; exit 1; }

ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
timeout 400 qemu-system-x86_64 -accel $ACC -kernel "$T/k.mb" -m 256 \
    -append "osum console=ttyS0 vfs usb usbpoll nic nip=169.254.10.1/16 nwait=0" \
    -serial "file:$T/ser.txt" -display none -no-reboot \
    -drive "file=$T/d.img,format=raw,if=ide" \
    -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:$P1-:8765,hostfwd=tcp:127.0.0.1:$P2-:8766,hostfwd=tcp:127.0.0.1:$((P2+1))-:8767" \
    -device qemu-xhci,id=x0 -device usb-net,netdev=n0,mac=52:54:00:12:34:77 \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
QPID=$!
S="$T/ser.txt"
klar() { tr -cd '\11\12\15\40-\176' < "$S"; }
waitfor() { local i=0; while [ $i -lt $2 ]; do klar | grep -aq -- "$1" && return 0; kill -0 $QPID 2>/dev/null || return 1; sleep 1; i=$((i+1)); done; return 1; }

if waitfor 'dbgsrv: listening on 8765' 200; then ok "dbgsrv listens after DHCP over the USB function"; else bad "dbgsrv never listened"; klar | tail -30; fi
klar | grep -aq 'dhcp: ack ip=10.0.2.15' && ok "DHCP lease on usb-net" || bad "no DHCP lease"
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
for r in lspci lspci/v dmesg klog pci usb version uptime wlanctl/status wlanctl/dump svclog dbgsrvlog; do
    rc=$(get -H "X-Token: $TOKEN" "$U/$r")
    if [ "$(code)" = "HTTP/1.0 200 OK" ] && [ -s "$T/o.txt" ] && ! grep -q 'cannot read\|cannot run' "$T/o.txt"; then ok "GET /$r -> 200 + body ($(wc -c < "$T/o.txt") B)"; else bad "/$r: $(code) $(head -c 80 "$T/o.txt")"; fi
done
rc=$(get -H "X-Token: $TOKEN" "$U/lspci"); grep -q '00:' "$T/o.txt" && ok "/lspci shows bus addresses" || bad "/lspci content"
rc=$(get -H "X-Token: $TOKEN" "$U/"); grep -q '^/wlan$' "$T/o.txt" && grep -q '^/dmesg$' "$T/o.txt" && ok "/ lists the endpoints" || bad "index content"
rc=$(get -H "X-Token: $TOKEN" "$U/etc/passwd"); [ "$(code)" = "HTTP/1.0 404 Not Found" ] && ok "unknown path -> 404" || bad "/etc/passwd: $(code)"
rc=$(get --path-as-is -H "X-Token: $TOKEN" "$U/../etc/shadow"); [ "$(code)" = "HTTP/1.0 404 Not Found" ] && ok "path traversal -> 404" || bad "traversal: $(code)"
rc=$(get -X POST -d x=1 -H "X-Token: $TOKEN" "$U/wlan"); [ "$(code)" = "HTTP/1.0 405 Method Not Allowed" ] && ok "POST -> 405" || bad "POST: $(code)"
rc=$(get -X PUT -d x=1 -H "X-Token: $TOKEN" "$U/wlan"); [ "$(code)" = "HTTP/1.0 405 Method Not Allowed" ] && ok "PUT -> 405" || bad "PUT: $(code)"
rc=$(get -X DELETE -H "X-Token: $TOKEN" "$U/wlan"); [ "$(code)" = "HTTP/1.0 405 Method Not Allowed" ] && ok "DELETE -> 405" || bad "DELETE: $(code)"

rc=$(curl -s -m 15 -o "$T/o.txt" -H "X-Token: $TOKEN" "http://127.0.0.1:$P2/wlan"; echo $?)
[ "$rc" != 0 ] && [ ! -s "$T/o.txt" ] && ok "public-address peer is dropped even with the right token (curl rc=$rc)" || bad "public-peer instance answered (rc=$rc)"
klar | grep -aq 'dbgsrv: refused non-local 10.0.2.2' && ok "refusal logged with the peer address" || bad "refusal not logged"
rc=$(curl -s -m 8 -o "$T/o.txt" -H "X-Token: $TOKEN" "http://127.0.0.1:$((P2+1))/wlan"; echo $?)
[ ! -s "$T/o.txt" ] && ok "instance without token file serves nothing (curl rc=$rc)" || bad "tokenless instance answered"
klar | grep -aq 'dbgsrv: no token, refusing to start' && ok "tokenless instance says so and exits" || bad "no-token message missing"
klar | grep -aq 'dbgsrv: 401 bad token 10.0.2.2' && ok "bad tokens logged with the peer address" || bad "401 not logged"
klar | grep -aq -- "$TOKEN" && bad "token leaked to the console log" || ok "token never appears in the console log"
rc=$(get -H "X-Token: $TOKEN" "$U/dbgsrvlog"); grep -q -- "$TOKEN" "$T/o.txt" && bad "token leaked into /dbgsrvlog" || ok "token not in /dbgsrvlog"

echo "DBGSRV-QEMU: $pass ok, $fail fail"
[ "$fail" = 0 ]
