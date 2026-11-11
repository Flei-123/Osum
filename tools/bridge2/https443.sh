#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
W=${HTTPS_W:-/tmp/bruecke-https443}
rm -rf "$W"; mkdir -p "$W"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }

command -v qemu-system-x86_64 >/dev/null || { echo "kein qemu"; exit 0; }

echo "== 1. bauen =="
. tools/lib/firnenv.sh
./tools/build-kernel.sh "$W/k0.mb" > "$W/k.log" 2>&1 || {
    echo "the kernel does not build"; tail -20 "$W/k.log"; exit 1; }
note "kernel $(stat -c%s "$W/k0.mb") Oktette"

as --64 -o "$W/crt.o" kernel/user/crt.s 2>"$W/as.err" || {
    echo "crt.s"; cat "$W/as.err"; exit 1; }
for p in sh ls cat echo jsig jarvisctl dhcp host ping; do
    "$FIRNC" "kernel/user/$p.fi" -o "$W/$p.o" \
        > "$W/e-$p" 2>&1 || { echo "$p baut nicht"; head -20 "$W/e-$p"; exit 1; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
        -o "$W/$p.elf" "$W/crt.o" "$W/$p.o" 2>"$W/ld-$p" || {
        echo "$p bindet nicht"; cat "$W/ld-$p"; exit 1; }
    strip --strip-all "$W/$p.elf"
done
FIRNLIB="$ROOT/lib" "$FIRNC" -c --profile=app \
    -o "$W/jarvisd.o" kernel/app/jarvisd.fi > "$W/e-jarvisd" 2>&1 || {
    echo "jarvisd baut nicht"; head -30 "$W/e-jarvisd"; exit 1; }
ld -T kernel/user/user.ld -o "$W/jarvisd.elf" "$W/jarvisd.o" \
    2>"$W/ld-jarvisd" || { echo "jarvisd bindet nicht"; cat "$W/ld-jarvisd"; exit 1; }
strip --strip-all "$W/jarvisd.elf"
ok "jarvisd gebaut ($(stat -c%s "$W/jarvisd.elf") Oktette)"

cat > "$W/rechte.conf" <<'CONF'
transport            = https
servername     = store.fleitec.com
path           = /bruecke/draht
roots        = /etc/ssl/roots.pem
commands        = no
screenshot = yes
sysinfo     = yes
input        = no
max_output    = 65536
max_file      = 4194304
log       = /var/log/jarvisd.log
work_file    = /var/jarvis/output.txt
permit_file = /var/jarvis/screenshot-permit
CONF

for c in /etc/ssl/certs/ca-certificates.crt \
         /etc/pki/tls/certs/ca-bundle.crt; do
    [ -r "$c" ] && { cp "$c" "$W/roots.pem"; break; }
done
[ -s "$W/roots.pem" ] || { echo "no root storage on the host"; exit 1; }
note "wurzeln $(stat -c%s "$W/roots.pem") Oktette"

printf 'nameserver 10.0.2.3\n' > "$W/resolv.conf"

SPEC="/bin/ /etc/ /etc/ssl/ /etc/jarvis/ /var/ /var/log/ /var/jarvis/"
for p in sh ls cat echo jsig jarvisctl dhcp host ping jarvisd; do
    SPEC="$SPEC /bin/$p=$W/$p.elf"
done
SPEC="$SPEC /etc/jarvis/permissions.conf=$W/rechte.conf"
SPEC="$SPEC /etc/ssl/roots.pem=$W/roots.pem"
SPEC="$SPEC /etc/resolv.conf=$W/resolv.conf"
bash tools/mkfsfi/mkfs.sh build "$W/probe.img" 32768 $SPEC \
    > "$W/mkfs.txt" 2>&1 || { echo "mkfs"; tail -5 "$W/mkfs.txt"; exit 1; }
ok "Platte gebaut"

echo "== 2. Osum boots and talks to store.fleitec.com =="
timeout 300 qemu-system-x86_64 -kernel "$W/k0.mb" -m 512 \
    -append "osum nokbd nosched noproc nofs modfs nic nip=169.254.10.1/16 nsvc=0 nwait=0 dhcp script=dhcp;jarvisd -1 -t 50000" \
    -serial "file:$W/serial.txt" -display none -no-reboot \
    -drive "file=$W/probe.img,format=raw,if=ide,index=0" \
    -netdev user,id=n0 -device e1000,netdev=n0 \
    > "$W/qemu.log" 2>&1 &
QPID=$!
i=0
while [ $i -lt 900 ]; do
    grep -qa 'jarvisd:' "$W/serial.txt" 2>/dev/null && break
    kill -0 "$QPID" 2>/dev/null || break
    sleep 0.2; i=$((i+1))
done
sleep 60
kill "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null

echo "== 3. what was on the wire =="
grep -a 'jarvisd:' "$W/serial.txt" | head -20 | sed 's/^/        /'

grep -qa 'jarvisd:.*[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+' "$W/serial.txt" \
    && ok "the name store.fleitec.com is resolved" \
    || bad "the name does not resolve"
grep -qa 'Handschlag ist gescheitert' "$W/serial.txt" \
    && bad "the TLS handshake failed" \
    || ok "the handshake with the REAL certificate is up"
grep -qa 'der Server antwortet' "$W/serial.txt" \
    && bad "the server did not answer 200" \
    || ok "der Server antwortet 200"
grep -qa 'PAIRING CODE' "$W/serial.txt" \
    && ok "the device arrived at the service and shows a code" \
    || bad "the device did NOT arrive"
HEX=$(grep -a 'PAIRING CODE' "$W/serial.txt" | tail -1 | awk '{print $NF}')
if [ -n "$HEX" ]; then
    note "Code auf dem Bildschirm: $(python3 -c "import sys;print(bytes.fromhex(sys.argv[1]).decode())" "$HEX" 2>/dev/null)"
fi

echo "== 4. and what the service says about it =="
journalctl -u bruecke --since '-3 min' --no-pager 2>/dev/null \
    | grep -iE 'KOPPLUNG NOETIG|ANGEMELDET|ABGELEHNT' | tail -5 | sed 's/^/        /'
journalctl -u bruecke --since '-3 min' --no-pager 2>/dev/null \
    | grep -qi 'KOPPLUNG NOETIG' \
    && ok "the service issued a PAIRING CODE" \
    || bad "nothing in the log of the service"

echo "== 5. pair, then jobs over 443 (puls loop) =="
CODE=""
[ -n "$HEX" ] && CODE=$(python3 -c "import sys;print(bytes.fromhex(sys.argv[1]).decode())" "$HEX" 2>/dev/null)
KENN=$(journalctl -u bruecke --since '-5 min' --no-pager 2>/dev/null | grep "Code $CODE" | tail -1 | grep -o 'osum-[0-9a-f]*')
VKEY=$(cat /srv/bruecke/verwalter.key 2>/dev/null)
if [ -n "$CODE" ] && [ -n "$KENN" ] && [ -n "$VKEY" ]; then
    VH="X-Bruecke-Verwalter: $VKEY"
    curl -s -H "$VH" -H 'Content-Type: application/json' \
        -d "{\"geraet\":\"$KENN\",\"code\":\"$CODE\",\"was\":\"frei\"}" \
        http://127.0.0.1:8090/bruecke/koppeln | grep -q '"gekoppelt": true' \
        && ok "server approved the pairing" || bad "server did not approve the pairing"
    timeout 200 qemu-system-x86_64 -kernel "$W/k0.mb" -m 512 \
        -append "osum nokbd nosched noproc nofs modfs nic nip=169.254.10.1/16 nsvc=0 nwait=0 dhcp script=dhcp;jarvisctl pair $HEX;jarvisd -v -t 120000" \
        -serial "file:$W/serial2.txt" -display none -no-reboot \
        -drive "file=$W/probe.img,format=raw,if=ide,index=0" \
        -netdev user,id=n0 -device e1000,netdev=n0 > "$W/qemu2.log" 2>&1 &
    Q2=$!
    for i in $(seq 60); do
        journalctl -u bruecke --since '-2 min' --no-pager | grep -q "ANGEMELDET.*$KENN" && break
        sleep 2
    done
    for i in 1 2 3; do
        curl -s -H "$VH" -H 'Content-Type: application/json' \
            -d "{\"geraet\":\"$KENN\",\"art\":\"system\"}" \
            http://127.0.0.1:8090/bruecke/auftrag > /dev/null
    done
    sleep 20
    got=0
    for i in 1 2 3; do
        curl -s -m5 -H "$VH" "http://127.0.0.1:8090/bruecke/holen?geraet=$KENN&id=$i" \
            | grep -q 'laufzeit_ms' && got=$((got+1))
    done
    [ "$got" -eq 3 ] && ok "3 of 3 jobs answered over 443" \
        || bad "only $got of 3 jobs answered over 443"
    kill "$Q2" 2>/dev/null; wait "$Q2" 2>/dev/null
    curl -s -H "$VH" -H 'Content-Type: application/json' \
        -d "{\"geraet\":\"$KENN\",\"was\":\"sperren\"}" \
        http://127.0.0.1:8090/bruecke/koppeln > /dev/null
else
    bad "no code/device for the job test"
fi

echo
echo "HTTPS443: $pass bestanden, $fail durchgefallen"
[ "$fail" -eq 0 ]
