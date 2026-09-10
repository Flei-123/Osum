#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/bridge/echtserver.sh -- RUNDE BRIDGE-2: OSUM AM ECHTEN JARVIS.
#
# ====================================================================
# DAS IST DER ABSCHNITT, DEN RUNDE BRIDGE NICHT HATTE.
# ====================================================================
#
# `tools/bridge/run.sh` misst gegen `gegenstelle.py` -- einen
# TLS-Server in Python, der GENAU das Protokoll aus `jarvisd.fi`
# spricht. Das ist eine ehrliche Messung von OSUMS SEITE, und
# docs/BRIDGE.md sagt selbst, was damit NICHT gemessen ist: ob der
# ECHTE JARVIS-Server dieses Geraet annimmt.
#
# Hier laeuft der echte Server (`/root/jarvis/server.js`, Node) mit dem
# Adapter aus `lib/osumbridge.js`, und Osum meldet sich in QEMU bei ihm
# an. Gemessen wird, was der AUFTRAG verlangt:
#
#   1. das Geraet taucht in der Geraete-Registry auf -- derselben, aus
#      der `list_devices` und `remote_shell` schoepfen,
#   2. `remote_shell` fuehrt einen Befehl aus,
#   3. `remote_read` liest eine Datei,
#   4. `remote_write` schreibt eine, und das Zuruecklesen zeigt sie,
#   5. `computer(screenshot)` bringt ein PNG mit dem Schirm.
#
# DER SERVER LAEUFT MIT EIGENEM PORT UND EIGENEM data/ (JARVIS_ROOT),
# damit dieser Laeufer den laufenden Dienst nicht anfasst.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
JARVIS=${JARVIS_DIR:-/root/jarvis}
W=${ECHT_W:-/tmp/bridge2-echt}
mkdir -p "$W"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }

for t in qemu-system-x86_64 ip node python3 gcc openssl; do
    command -v "$t" >/dev/null 2>&1 || { echo "ECHT: uebersprungen, $t fehlt"; exit 0; }
done
[ -f "$JARVIS/server.js" ] || { echo "ECHT: uebersprungen, $JARVIS/server.js fehlt"; exit 0; }
[ -f "$JARVIS/lib/osumbridge.js" ] || { echo "ECHT: uebersprungen, der Adapter fehlt"; exit 0; }

NS=echt-$$
V0=e0-$$
V1=hw1
QPORT=$(( 17000 + ($$ % 300) * 2 ))
BPORT=$(( QPORT + 1 ))
OSUM_IP=10.9.0.2
HOST_IP=10.9.0.1
# EIN EIGENER PORT JE LAUF. 8443 fest war falsch: ein Laeufer, dessen
# Server noch haengt, blockiert den naechsten (gemessen: "Osum-Bruecke:
# listen EADDRINUSE"), und der naechste sucht den Fehler dann in Osum.
TLSPORT=$(( 8500 + $$ % 400 ))
HTTPPORT=$(( 18900 + $$ % 90 ))
SRVPID=""
BRPID=""

cleanup() {
    [ -n "$SRVPID" ] && kill "$SRVPID" 2>/dev/null
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null
    ip netns del "$NS" 2>/dev/null
    ip link del "$V0" 2>/dev/null
}
trap cleanup EXIT

ip netns del "$NS" 2>/dev/null
ip netns add "$NS" 2>/dev/null || { echo "ECHT: uebersprungen, keine Netzraeume"; exit 0; }
ip netns del "$NS" 2>/dev/null

# ------------------------------------------------- 1. das Zertifikat
#
# Es muss auf den NAMEN lauten, den Osums Rechteliste als `servername`
# fuehrt -- sonst lehnt der Helfer ab, und genau das soll er auch.
# DIESELBEN ZERTIFIKATE WIE DIE UEBRIGE ABNAHME, und das ist kein
# Zufall: ein mit `openssl req -x509` erzeugtes Zertifikat hat Osums
# X.509-Leser hier NICHT angenommen -- gemessen, `tls_verify_reason` 1
# (V_PARSE, "laesst sich nicht zerlegen"). `tools/hwnet/mkcerts.py`
# baut die Kette, gegen die dieses Projekt seit Runde HWNET misst:
# eine Wurzel und ein Serverzertifikat auf <name> mit SAN dNSName UND
# iPAddress 10.9.0.1.
#
# WICHTIG: in den Wurzelspeicher von Osum gehoert die WURZEL (ca.pem),
# nicht das Serverzertifikat. Der erste Anlauf hat good.pem dorthin
# gelegt -- damit prueft der Helfer ein Zertifikat gegen sich selbst.
mkdir -p "$W/certs"
if [ ! -f "$W/certs/good.pem" ]; then
    python3 tools/hwnet/mkcerts.py "$W/certs" jarvis.test >"$W/certs.txt" 2>&1 || {
        echo "ECHT: mkcerts.py fehlgeschlagen"; cat "$W/certs.txt"; exit 1; }
fi
cp "$W/certs/good.pem" "$W/certs/srv.pem"
cp "$W/certs/good.key" "$W/certs/srv.key"
ok "die Zertifikatskette kommt aus tools/hwnet/mkcerts.py (Name jarvis.test, SAN 10.9.0.1)"

# ------------------------------------------------- 2. Osums Abbild
if [ ! -f "$W/k.mb" ] || [ -n "${ECHT_BAU:-}" ]; then
    BRIDGE_PROGS="sh ls cat echo chmod sleep jsig jarvisctl" \
        bash tools/bridge/build.sh "$W" 0 >"$W/bau.txt" 2>&1 || {
        echo "ECHT: der Bau ist gescheitert"; tail -6 "$W/bau.txt"; exit 1; }
fi
K="$W/k.mb"
ok "$(tail -1 "$W/bau.txt")"

cat > "$W/rechte.conf" <<CONF
# Fuer diesen Pruefstand: der Server ist der echte JARVIS auf dem Wirt.
server         = $HOST_IP:$TLSPORT
servername     = jarvis.test
wurzeln        = /etc/ssl/roots.pem
befehle        = ja
befehl_erlaubt = /bin/ls
befehl_erlaubt = /bin/echo
befehl_erlaubt = /bin/cat
lesen          = /var/jarvis/
lesen          = /etc/jarvis/rechte.conf
schreiben      = /var/jarvis/
auflisten      = /var/jarvis/
auflisten      = /
bildschirmfoto = ja
systeminfo     = ja
max_ausgabe    = 65536
max_datei      = 8388608
protokoll       = /var/log/jarvisd.log
arbeitsdatei    = /var/jarvis/ausgabe.txt
fotoscheindatei = /var/jarvis/fotoschein
CONF
echo "hallo aus osum" > "$W/gruss.txt"

SPEC="/bin/ /etc/ /etc/ssl/ /etc/jarvis/ /var/ /var/log/ /var/jarvis/"
for p in sh ls cat echo chmod sleep jsig jarvisctl; do SPEC="$SPEC /bin/$p=$W/$p.elf"; done
SPEC="$SPEC /bin/jarvisd=$W/jarvisd.elf"
SPEC="$SPEC /etc/jarvis/rechte.conf=$W/rechte.conf"
SPEC="$SPEC /etc/ssl/roots.pem=$W/certs/ca.pem"
SPEC="$SPEC /var/jarvis/gruss.txt=$W/gruss.txt"
python3 tools/osum/mkfs.py build "$W/osum.img" 131072 $SPEC --v3 >"$W/mkfs.txt" 2>&1 || {
    echo "ECHT: mkfs gescheitert"; tail -4 "$W/mkfs.txt"; exit 1; }
cp "$W/osum.img" "$W/live.img"

# ------------------------------------------------- 3. der Draht
gcc -O2 -o "$W/bridge" tools/net/bridge.c 2>"$W/gcc.txt" || {
    echo "ECHT: tools/net/bridge.c baut nicht"; head -4 "$W/gcc.txt"; exit 1; }
ip netns add "$NS"
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

# KEIN WEITERLEITER MEHR, und das ist die Lehre aus zwei Fehlversuchen:
# der Server zieht gleich SELBST in den Netzraum (siehe Abschnitt 4).
#
# Was vorher schiefging und warum: ein Netzraum hat sein EIGENES
# Loopback, also war `127.0.0.1` aus ihm heraus nicht der Wirt
# ("Connection refused"). Und eine zweite Adresse am Wirtsende des
# veth-Paares half auch nicht ("timed out"): dieses Ende gehoert
# `tools/net/bridge.c`, das die Rahmen per AF_PACKET abholt -- es ist
# absichtlich KEINE Schnittstelle, fuer die der Linux-Stapel antwortet.
# `gegenstelle.py` macht es seit Runde BRIDGE richtig: sie laeuft IM
# Netzraum und lauscht dort auf 0.0.0.0.

# ------------------------------------------------- 4. der echte Server
D="$W/jarvisdata"
rm -rf "$D"; mkdir -p "$D/data" "$D/logs" "$D/memory" "$D/uploads" "$D/downloads" "$D/projects"
cp "$JARVIS/config.json" "$D/config.json"
cp "$W/certs/srv.pem" "$D/data/osum-cert.pem"
cp "$W/certs/srv.key" "$D/data/osum-key.pem"
node --input-type=module -e "
import { hashPassword } from '$JARVIS/lib/auth.js'
import fs from 'node:fs'
fs.writeFileSync('$D/data/users.json', JSON.stringify({users:{u_pruef:{
  id:'u_pruef', username:'osumpruef', passHash:hashPassword('Pr8fst4nd!xy'),
  email:'osum@test.invalid', deviceToken:'pruef', createdAt:Date.now(),
  settings:{}, admin:true}}}, null, 2))
" || { echo "ECHT: das Pruefkonto liess sich nicht anlegen"; exit 1; }

# DER SERVER LAEUFT IM NETZRAUM. Nur so ist er fuer Osum ueberhaupt
# erreichbar (siehe die Begruendung beim Draht oben). Sein HTTP-Teil
# lauscht dann ebenfalls dort -- die Werkzeuge unten sprechen ihn
# deshalb auch aus dem Netzraum heraus an (`ip netns exec`).
ip netns exec "$NS" env -C "$JARVIS" JARVIS_ROOT="$D" JARVIS_PORT="$HTTPPORT" \
    JARVIS_OSUM_PORT="$TLSPORT" JARVIS_OSUM_DIR="$D/data" \
    JARVIS_OSUM_PROBE=1 \
    node server.js > "$W/server.log" 2>&1 & SRVPID=$!

for i in $(seq 1 120); do
    grep -qa "Osum-Brücke lauscht" "$W/server.log" 2>/dev/null && break
    kill -0 $SRVPID 2>/dev/null || break
    sleep 0.5
done
if grep -qa "Osum-Brücke lauscht" "$W/server.log" 2>/dev/null; then
    ok "der ECHTE JARVIS-Server laeuft und lauscht auf dem Osum-Port"
else
    bad "der echte Server ist nicht hochgekommen"
    tail -8 "$W/server.log" 2>/dev/null | sed 's/^/        /'
    echo "ECHT: $pass bestanden, $fail durchgefallen"; exit 1
fi

# Anmelden und einen Kopplungscode holen -- so, wie Justin es im Cockpit tut.
KEKS=$(ip netns exec "$NS" curl -s -i -X POST "http://127.0.0.1:$HTTPPORT/api/login" \
    -H 'content-type: application/json' \
    -d '{"username":"osumpruef","password":"Pr8fst4nd!xy"}' \
    | grep -i '^set-cookie:' | head -1 | sed 's/^[Ss]et-[Cc]ookie: //' | cut -d';' -f1)
[ -n "$KEKS" ] && ok "am Cockpit angemeldet" || bad "die Anmeldung am Cockpit ist gescheitert"
CODE=$(ip netns exec "$NS" curl -s -X POST "http://127.0.0.1:$HTTPPORT/api/osum/pair" \
    -H 'content-type: application/json' -H "cookie: $KEKS" \
    -d '{"name":"Osum-QEMU"}' | python3 -c 'import json,sys; print(json.load(sys.stdin).get("code",""))')
if [ -n "$CODE" ]; then
    ok "das Cockpit gibt einen Kopplungscode heraus: $CODE"
else
    bad "kein Kopplungscode"
    echo "ECHT: $pass bestanden, $fail durchgefallen"; exit 1
fi

# ------------------------------------------------- 5. Osum meldet sich an
# DIE REIHENFOLGE IST DER GANZE WITZ DER KOPPLUNG.
#
# `jarvisctl koppeln` bestaetigt einen Code, den DER HELFER SCHON
# BEKOMMEN HAT: der Helfer legt ihn nach `/var/jarvis/kopplung`, und
# `jarvisctl` liest ihn dort und vergleicht. Wer zuerst bestaetigt,
# bekommt zu Recht "Es liegt keine Kopplungsanfrage vor" -- gemessen,
# `jarvisctl -> 1`, und der Server meldete "die Kopplung wurde am
# Geraet abgelehnt". Genau so soll es sein: ein Code, den niemand
# angefragt hat, wird nicht bestaetigt.
#
# ALSO IN DREI SCHRITTEN, wie an einem echten Geraet auch:
#   1. `jarvisd -1` verbindet sich, bekommt `kopplung-noetig <code>`,
#      schreibt ihn auf den Schirm und nach /var/jarvis/kopplung und
#      legt auf (niemand hat bestaetigt),
#   2. der Mensch tippt `jarvisctl koppeln <code>`,
#   3. `jarvisd` verbindet sich neu -- und jetzt geht es durch.
SKRIPT="jarvisd -1 -t 20000;jarvisctl koppeln $CODE;jarvisctl fotoschein 900;jarvisd -t 120000"
timeout 400 qemu-system-x86_64 -kernel "$K" -m 256 \
    -append "osum nokbd nosched noproc nofs noring3 gfx nocursor nic nip=$OSUM_IP/24 ngw=$HOST_IP nsvc=0 nwait=0 script=$SKRIPT" \
    -serial "file:$W/seriell.txt" -display none -no-reboot \
    -drive "file=$W/live.img,format=raw,if=ide,index=0" \
    -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
    -device "e1000,netdev=n0,mac=52:54:00:aa:bb:cc" -vga std \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$W/qemu.log" 2>&1 &
QPID=$!

# Warten, bis der Server das Geraet als verbunden fuehrt, und DANN die
# Werkzeuge benutzen -- genau so, wie JARVIS es tut.
VERB=""
for i in $(seq 1 240); do
    VERB=$(ip netns exec "$NS" curl -s "http://127.0.0.1:$HTTPPORT/api/osum/devices" -H "cookie: $KEKS" \
        | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin).get("devices",[])
    print("ja" if d and d[0].get("verbunden") else "")
except Exception: print("")' 2>/dev/null)
    [ "$VERB" = ja ] && break
    kill -0 $QPID 2>/dev/null || break
    sleep 0.5
done
if [ "$VERB" = ja ]; then
    ok "OSUM STEHT ALS GERAET AM ECHTEN SERVER -- gekoppelt und verbunden"
else
    bad "Osum ist am echten Server nicht als verbunden aufgetaucht"
    grep -aE 'jarvisd:|Osum' "$W/seriell.txt" "$W/server.log" 2>/dev/null | tail -8 | sed 's/^/        /'
fi

# Die Werkzeuge, ueber denselben Weg wie JARVIS: node ruft den Adapter.
if [ "$VERB" = ja ]; then
    ip netns exec "$NS" env JARVIS_DIR="$JARVIS" HTTPPORT="$HTTPPORT" \
        KEKS="$KEKS" W="$W" \
        node tools/bridge/werkzeuge.mjs > "$W/werkzeuge.txt" 2>&1
    while IFS= read -r z; do
        case "$z" in
            OK*)   ok "${z#OK }" ;;
            FAIL*) bad "${z#FAIL }" ;;
            *)     note "$z" ;;
        esac
    done < "$W/werkzeuge.txt"
fi

kill $QPID 2>/dev/null
wait $QPID 2>/dev/null
echo "ECHT: $pass bestanden, $fail durchgefallen"
[ "$fail" -eq 0 ]
