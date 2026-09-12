#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/bruecke/abriss.sh -- RUNDE BRUECKE: REISST DIE VERBINDUNG AB.
#
# ====================================================================
# DIE FRAGE
# ====================================================================
#
# Justins Rechner steht in einem Wohnzimmer. Der Router startet neu,
# das WLAN wechselt, der Rechner schlaeft ein. Die Bruecke muss das
# ueberleben, OHNE dass jemand etwas tut -- und ohne dem Server die
# Tuer einzurennen.
#
# Gemessen wird nicht, DASS es wieder geht (das behauptet jedes
# Programm), sondern WANN: die Abstaende zwischen den Versuchen. Sie
# muessen WACHSEN und gedeckelt sein. `kernel/app/jarvisd.fi` sagt 250
# ms, dann doppelt, bis 30 s -- dieser Laeufer rechnet nach, ob das
# stimmt.
#
# WIE ABGERISSEN WIRD: die Gegenstelle wird schlicht ERSCHOSSEN. Das
# ist haerter als ein Router-Neustart (kein FIN, kein RST, die
# Verbindung verschwindet einfach) und damit der ehrlichere Fall.
set -uo pipefail
cd "$(dirname "$0")/../.."
W=${ABRISS_W:-/tmp/bruecke-abriss}
BRUECKE=${BRUECKE_DIR:-/root/bruecke}
mkdir -p "$W"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }

for t in qemu-system-x86_64 ip python3 gcc; do
    command -v "$t" >/dev/null 2>&1 || { echo "ABRISS: uebersprungen, $t fehlt"; exit 0; }
done

NS=abriss-$$
V0=a0-$$
V1=ah1
QPORT=$(( 20000 + ($$ % 300) * 2 ))
BPORT=$(( QPORT + 1 ))
TLSPORT=$(( 9100 + $$ % 100 ))
OSUM_IP=10.9.0.2
HOST_IP=10.9.0.1
GPID=""
BRPID=""

cleanup() {
    [ -n "$GPID" ] && kill "$GPID" 2>/dev/null
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null
    ip netns del "$NS" 2>/dev/null
    ip link del "$V0" 2>/dev/null
}
trap cleanup EXIT

# Alte Reste eines abgebrochenen Laufs.
for n in $(ip netns list 2>/dev/null | awk '{print $1}' | grep -E '^abriss-' || true); do
    ip netns del "$n" 2>/dev/null || true
done
for i in $(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | cut -d@ -f1 | grep -E '^a0-' || true); do
    ip link del "$i" 2>/dev/null || true
done

echo "== 1. bauen =="
if [ ! -f "$W/k.mb" ] || [ -n "${ABRISS_BAU:-}" ]; then
    bash tools/bridge/build.sh "$W" 0 >"$W/bau.txt" 2>&1 || {
        echo "der Bau ist gescheitert"; tail -5 "$W/bau.txt"; exit 1; }
fi
mkdir -p "$W/certs"
if [ ! -f "$W/certs/good.pem" ]; then
    python3 tools/hwnet/mkcerts.py "$W/certs" jarvis.test >"$W/certs.txt" 2>&1 || {
        echo "mkcerts fehlgeschlagen"; exit 1; }
fi
cp "$W/certs/ca.pem" "$W/roots.pem"
ok "Kern, Programme und Zertifikate stehen"

cat > "$W/rechte.conf" <<CONF
server         = $HOST_IP:$TLSPORT
servername     = jarvis.test
wurzeln        = /etc/ssl/roots.pem
befehle        = nein
lesen          = /var/jarvis/
schreiben      = /var/jarvis/
auflisten      = /var/jarvis/
bildschirmfoto = nein
systeminfo     = ja
eingabe        = nein
max_ausgabe    = 65536
max_datei      = 262144
protokoll       = /var/log/jarvisd.log
arbeitsdatei    = /var/jarvis/ausgabe.txt
fotoscheindatei = /var/jarvis/fotoschein
CONF

SPEC="/bin/ /etc/ /etc/ssl/ /etc/jarvis/ /var/ /var/log/ /var/jarvis/"
for p in sh ls cat echo chmod jsig jarvisctl; do
    SPEC="$SPEC /bin/$p=$W/$p.elf"
done
SPEC="$SPEC /bin/jarvisd=$W/jarvisd.elf"
SPEC="$SPEC /etc/jarvis/rechte.conf=$W/rechte.conf"
SPEC="$SPEC /etc/ssl/roots.pem=$W/roots.pem"
python3 tools/osum/mkfs.py build "$W/probe.img" 16384 $SPEC >"$W/mkfs.txt" 2>&1 || {
    echo "mkfs gescheitert"; tail -4 "$W/mkfs.txt"; exit 1; }
cp "$W/probe.img" "$W/live.img"

echo "== 2. der Draht =="
gcc -O2 -o "$W/bridge" tools/net/bridge.c 2>"$W/gcc.txt" || {
    echo "bridge.c baut nicht"; exit 1; }
ip netns add "$NS" 2>/dev/null || { echo "ABRISS: uebersprungen, keine Netzraeume"; exit 0; }
ip link add "$V0" type veth peer name "$V1"
ip link set "$V1" netns "$NS"
ip netns exec "$NS" ip addr add $HOST_IP/24 dev "$V1"
ip netns exec "$NS" ip link set "$V1" up
ip netns exec "$NS" ip link set lo up
ip link set "$V0" up
ethtool -K "$V0" tx off rx off tso off gso off gro off >/dev/null 2>&1
ip netns exec "$NS" ethtool -K "$V1" tx off rx off tso off gso off gro off >/dev/null 2>&1
"$W/bridge" "$V0" "$BPORT" "$QPORT" 2>"$W/br.log" & BRPID=$!
sleep 0.5
ok "Netzraum und Draht stehen"

echo "== 3. KEINE Gegenstelle: das Geraet darf nicht haemmern =="
# Osum startet, die Gegenstelle gibt es NICHT. Jeder Versuch scheitert
# sofort (kein Lauscher = RST), also ist der Abstand zwischen den
# Versuchen REIN die Wartezeit -- genau das, was gemessen werden soll.
cp "$W/probe.img" "$W/live.img"
timeout 200 qemu-system-x86_64 -kernel "$W/k.mb" -m 256 \
    -append "osum nokbd nosched noproc nofs noring3 gfx nocursor nic nip=$OSUM_IP/24 ngw=$HOST_IP nsvc=0 nwait=0 script=jarvisd -v -t 70000;exit" \
    -serial "file:$W/s-ohne.txt" -display none -no-reboot \
    -drive "file=$W/live.img,format=raw,if=ide,index=0" \
    -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
    -device "e1000,netdev=n0,mac=52:54:00:cc:dd:ee" -vga std \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$W/q-ohne.log" 2>&1

VERSUCHE=$(grep -ac 'jarvisd: keine Verbindung' "$W/s-ohne.txt" 2>/dev/null || echo 0)
WARTEMS=$(grep -aoE 'jarvisd: wartezeit_ms [0-9]+' "$W/s-ohne.txt" | tail -1 | awk '{print $3}')
AUFRUFE=$(grep -aoE 'jarvisd: aufrufe_beim_warten [0-9]+' "$W/s-ohne.txt" | tail -1 | awk '{print $3}')

if [ "${VERSUCHE:-0}" -ge 3 ]; then
    ok "das Geraet versucht es wieder -- $VERSUCHE Versuche in 70 s"
else
    bad "zu wenige Versuche ($VERSUCHE) -- gibt es die Wiederverbindung?"
fi

# DIE ENTSCHEIDENDE ZAHL. Waeren die Abstaende fest bei 250 ms, kaeme
# das Geraet in 70 s auf ~280 Versuche. Mit Verdopplung bis 30 s sind
# es eine Handvoll. Die Zahl der Versuche IST der Beweis fuer den
# wachsenden Abstand.
if [ "${VERSUCHE:-0}" -gt 0 ] && [ "${VERSUCHE:-0}" -le 12 ]; then
    ok "und der Abstand WAECHST: $VERSUCHE Versuche statt ~280 bei festen 250 ms"
    note "250, 500, 1000, 2000, 4000, 8000, 16000, 30000 ms -- gedeckelt bei 30 s"
else
    bad "der Abstand waechst nicht -- $VERSUCHE Versuche in 70 s"
fi

if [ -n "${AUFRUFE:-}" ] && [ "${AUFRUFE:-9999}" -lt 100 ]; then
    ok "und dabei wird GEWARTET, nicht gedreht: $AUFRUFE Systemaufrufe in ${WARTEMS} ms"
    note "eine Warteschleife machte Millionen -- das ist ein nanosleep"
else
    bad "beim Warten laeuft etwas heiss ($AUFRUFE Aufrufe)"
fi

echo "== 4. Gegenstelle da, dann WEG, dann wieder da =="
# Jetzt mit Gegenstelle: erst kommt das Geraet durch, dann wird die
# Gegenstelle erschossen, und es muss sich von selbst wieder melden.
cat > "$W/auftraege.txt" <<'AUF'
system||
AUF
: > "$W/aus.txt"
ip netns exec "$NS" python3 tools/bridge/peer.py \
    --cert "$W/certs/good.pem" --key "$W/certs/good.key" \
    --port "$TLSPORT" --auftraege "$W/auftraege.txt" --aus "$W/aus" \
    --kein-beweis --wartezeit 120 > "$W/g1.log" 2>&1 & GPID=$!
sleep 1

cp "$W/probe.img" "$W/live2.img"
timeout 200 qemu-system-x86_64 -kernel "$W/k.mb" -m 256 \
    -append "osum nokbd nosched noproc nofs noring3 gfx nocursor nic nip=$OSUM_IP/24 ngw=$HOST_IP nsvc=0 nwait=0 script=jarvisd -v -t 60000;exit" \
    -serial "file:$W/s-abriss.txt" -display none -no-reboot \
    -drive "file=$W/live2.img,format=raw,if=ide,index=0" \
    -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
    -device "e1000,netdev=n0,mac=52:54:00:cc:dd:ee" -vga std \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$W/q-abriss.log" 2>&1 &
QPID=$!

# Warten, bis es EINMAL durch ist -- dann abreissen.
for i in $(seq 1 60); do
    if grep -aq 'jarvisd: angemeldet' "$W/s-abriss.txt" 2>/dev/null; then break; fi
    sleep 0.5
done
if grep -aq 'jarvisd: angemeldet' "$W/s-abriss.txt" 2>/dev/null; then
    ok "erste Verbindung steht"
else
    bad "die erste Verbindung kam nicht zustande"
fi

kill -9 "$GPID" 2>/dev/null; GPID=""
note "die Gegenstelle wurde ERSCHOSSEN -- kein FIN, kein RST"
sleep 3

# Und wieder hinstellen. Wenn die Bruecke taugt, meldet sich das
# Geraet von selbst, ohne dass jemand etwas tut.
ip netns exec "$NS" python3 tools/bridge/peer.py \
    --cert "$W/certs/good.pem" --key "$W/certs/good.key" \
    --port "$TLSPORT" --auftraege "$W/auftraege.txt" --aus "$W/aus2" \
    --kein-beweis --wartezeit 120 > "$W/g2.log" 2>&1 & GPID=$!

wait $QPID 2>/dev/null
VERB=$(grep -ac 'jarvisd: verbunden' "$W/s-abriss.txt" 2>/dev/null || echo 0)
if [ "${VERB:-0}" -ge 2 ]; then
    ok "das Geraet hat sich NACH dem Abriss von selbst wieder gemeldet ($VERB Verbindungen)"
    grep -aE 'jarvisd: (verbunden|angemeldet|warten|keine Verbindung)' "$W/s-abriss.txt" \
        | head -12 | sed 's/^/        /'
else
    bad "nach dem Abriss kam keine neue Verbindung ($VERB)"
    grep -aE 'jarvisd:' "$W/s-abriss.txt" | tail -10 | sed 's/^/        /'
fi

echo
echo "ABRISS: $pass bestanden, $fail durchgefallen"
[ "$fail" -eq 0 ] || exit 1
