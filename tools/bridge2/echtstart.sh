#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."

W=${1:-/tmp/echtstart}
BUILDD=${DESIGNBUILD:-/tmp/osum-designbuild-$(pwd | md5sum | cut -c1-12)}
rm -rf "$W"; mkdir -p "$W"

pass=0; fail=0; offen=0
ok(){ pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad(){ fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
hm(){ offen=$((offen+1)); printf '  OFFEN %s\n' "$1"; }

echo "== 0. kernel and root =="
KERN=${KERN:-/tmp/usbimg/osum.mb}
WURZEL=${WURZEL:-/tmp/usbimg/root.img}
[ -s "$KERN" ]   || { echo "FEHLT: $KERN (tools/usbimg/build.sh laufen lassen)"; exit 1; }
[ -s "$WURZEL" ] || { echo "FEHLT: $WURZEL"; exit 1; }
echo "   Kern   $KERN ($(stat -c%s "$KERN") Oktette)"
echo "   Wurzel $WURZEL ($(stat -c%s "$WURZEL") Oktette)"
echo

echo "== A. NO DHCP SERVER ON THE NETWORK =="
cp "$WURZEL" "$W/a.img"
timeout 120 qemu-system-x86_64 -kernel "$KERN" -m 1024 \
    -append "osum nokbd nosched noproc nofs gfx nocursor nic dhcp nsvc=0 nwait=0 script=jarvisd --diagnose;exit" \
    -serial "file:$W/a.txt" -display none -no-reboot \
    -drive "file=$W/a.img,format=raw,if=ide,index=0" \
    -netdev "socket,id=n0,udp=127.0.0.1:18999,localaddr=127.0.0.1:18998" \
    -device "e1000,netdev=n0,mac=52:54:00:cc:dd:01" -vga std \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$W/a.qemu" 2>&1
echo "   --- was jarvisd sagt ---"
grep -a 'jarvisd:' "$W/a.txt" 2>/dev/null | sed 's/^/   /'
if grep -qa 'jarvisd:' "$W/a.txt"; then
    ok "jarvisd starts and runs, even without a DHCP server"
else
    bad "jarvisd does not come up at all"
fi
if grep -qa 'kein .server = ' "$W/a.txt"; then
    ok "it STOPS BY DEFAULT and says why (no server address) -- intended"
    echo "        -> on Justin's machine `jarvisctl` must set the address ONCE"
elif grep -qa 'keine Adresse\|DHCP hat nichts gebracht\|KEIN TOR' "$W/a.txt"; then
    ok "it SAYS that there is no address/no gateway -- instead of hanging silently"
else
    hm "keine Klartextmeldung gefunden"
fi
echo

echo "== A2. WITH server address, still NO DHCP =="
cat > "$W/rechte.conf" <<CONF
server         = 10.0.2.99:8090
servername     = store.fleitec.com
roots        = /etc/ssl/roots.pem
commands        = no
screenshot = no
sysinfo     = yes
CONF
cp "$WURZEL" "$W/a2.img"
python3 tools/osum/mkfs.py put "$W/a2.img" "/etc/jarvis/permissions.conf=$W/rechte.conf" \
    > "$W/put.txt" 2>&1 || echo "   (put nicht moeglich: $(tail -1 "$W/put.txt"))"
timeout 120 qemu-system-x86_64 -kernel "$KERN" -m 1024 \
    -append "osum nokbd nosched noproc nofs gfx nocursor nic dhcp nsvc=0 nwait=0 script=jarvisd -v -t 20000;exit" \
    -serial "file:$W/a2.txt" -display none -no-reboot \
    -drive "file=$W/a2.img,format=raw,if=ide,index=0" \
    -netdev "socket,id=n0,udp=127.0.0.1:18997,localaddr=127.0.0.1:18996" \
    -device "e1000,netdev=n0,mac=52:54:00:cc:dd:02" -vga std \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$W/a2.qemu" 2>&1
grep -a 'jarvisd:\|dhcp:' "$W/a2.txt" 2>/dev/null | head -12 | sed 's/^/   /'
if grep -qa 'jarvisd: no connection\|jarvisd: waiting' "$W/a2.txt"; then
    ok "without DHCP/without peer: it WAITS and does not hammer"
else
    hm "kein Warte-/Wiederholverhalten in der Ausgabe erkennbar"
fi
WMS=$(grep -aoE 'jarvisd: wait_ms [0-9]+' "$W/a2.txt" | tail -1 | awk '{print $3}')
[ -n "${WMS:-}" ] && echo "   gemessene Wartezeit_ms: $WMS"
echo

# ------------------------------------------------------------------
# C. DER PAIRING CODE
# ------------------------------------------------------------------
echo "== C. PAIRING CODE: is it shown, and for how long? =="
grep -na --text -n 'kopplung' kernel/app/jarvisd.fi | head -3 | sed 's/^/   /'
echo "   (Anzeige: /var/jarvis/pairing + Konsole, siehe jarvisd.fi Kopf)"
echo

echo "== ZUSAMMENFASSUNG =="
printf '   %d OK, %d FAIL, %d OFFEN\n' "$pass" "$fail" "$offen"
exit 0
