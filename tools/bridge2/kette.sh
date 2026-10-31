#!/usr/bin/env bash
#
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
W=${KETTE_W:-/tmp/bruecke-kette}
BRUECKE=${BRUECKE_DIR:-/root/bruecke}
DIENST_PORT=${DIENST_PORT:-$(( 8700 + $$ % 100 ))}
mkdir -p "$W"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }

for t in qemu-system-x86_64 ip python3 gcc curl; do
    command -v "$t" >/dev/null 2>&1 || { echo "KETTE: uebersprungen, $t fehlt"; exit 0; }
done
[ -f "$BRUECKE/anschluss.py" ] || { echo "KETTE: uebersprungen, $BRUECKE/anschluss.py fehlt"; exit 0; }

NS=kette-$$
V0=k0-$$
V1=kh1
QPORT=$(( 19000 + ($$ % 300) * 2 ))
BPORT=$(( QPORT + 1 ))
OSUM_IP=10.9.0.2
HOST_IP=10.9.0.1
TLSPORT=$(( 8900 + $$ % 100 ))
ANPID=""
BRPID=""
DIPID=""
NFT_REGEL=0

cleanup() {
    [ -n "$ANPID" ] && kill "$ANPID" 2>/dev/null
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null
    ip netns del "$NS" 2>/dev/null
    ip link del "$V0" 2>/dev/null
    ip link del "ka-$$" 2>/dev/null
    [ -n "${DIPID:-}" ] && kill "$DIPID" 2>/dev/null
    if [ "${NFT_REGEL:-0}" = 1 ]; then
        H=$(nft -a list chain inet filter input 2>/dev/null | grep "ka-$$" | grep -oE "handle [0-9]+$" | awk '{print $2}' | tail -1)
        [ -n "$H" ] && nft delete rule inet filter input handle "$H" 2>/dev/null
    fi
}
trap cleanup EXIT

for n in $(ip netns list 2>/dev/null | awk '{print $1}' | grep -E '^kette-' || true); do
    ip netns del "$n" 2>/dev/null || true
done
for i in $(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | cut -d@ -f1 | grep -E '^(ka|k0)-' || true); do
    ip link del "$i" 2>/dev/null || true
done

echo "== 1. bauen =="
if [ ! -f "$W/k.mb" ] || [ -n "${KETTE_BAU:-}" ]; then
    bash tools/bridge/build.sh "$W" 0 >"$W/bau.txt" 2>&1 || {
        echo "der Bau ist gescheitert"; tail -6 "$W/bau.txt"; exit 1; }
fi
ok "Kern und Programme gebaut"

mkdir -p "$W/certs"
if [ ! -f "$W/certs/good.pem" ]; then
    python3 tools/hwnet/mkcerts.py "$W/certs" jarvis.test >"$W/certs.txt" 2>&1 || {
        echo "mkcerts.py fehlgeschlagen"; cat "$W/certs.txt"; exit 1; }
fi
cp "$W/certs/ca.pem" "$W/roots.pem"
ok "Zertifikatskette aus tools/hwnet/mkcerts.py (jarvis.test, SAN 10.9.0.1)"

cat > "$W/rechte.conf" <<CONF
server         = $HOST_IP:$TLSPORT
servername     = jarvis.test
roots        = /etc/ssl/roots.pem
commands        = yes
command_allowed = /bin/echo
command_allowed = /bin/ls
read          = /var/jarvis/
write      = /var/jarvis/
list      = /var/jarvis/
screenshot = yes
sysinfo     = yes
input        = yes
max_output    = 65536
max_file      = 4194304
log       = /var/log/jarvisd.log
work_file    = /var/jarvis/output.txt
permit_file = /var/jarvis/screenshot-permit
CONF

bauen_img() {
    local SPEC="/bin/ /etc/ /etc/ssl/ /etc/jarvis/ /var/ /var/log/ /var/jarvis/"
    for p in sh ls cat echo chmod jsig jarvisctl; do
        SPEC="$SPEC /bin/$p=$W/$p.elf"
    done
    SPEC="$SPEC /bin/jarvisd=$W/jarvisd.elf"
    SPEC="$SPEC /etc/jarvis/permissions.conf=$W/rechte.conf"
    SPEC="$SPEC /etc/ssl/roots.pem=$W/roots.pem"
    python3 tools/osum/mkfs.py build "$W/probe.img" 16384 $SPEC \
        > "$W/mkfs.txt" 2>&1
}
bauen_img || { echo "mkfs gescheitert"; tail -4 "$W/mkfs.txt"; exit 1; }
rm -f "$W/live.img"        # ein neuer Lauf, ein neues Geraet

echo "== 2. der Draht und der Anschluss =="
gcc -O2 -o "$W/bridge" tools/net/bridge.c 2>"$W/gcc.txt" || {
    echo "tools/net/bridge.c baut nicht"; head -4 "$W/gcc.txt"; exit 1; }
ip netns del "$NS" 2>/dev/null
ip netns add "$NS" 2>/dev/null || { echo "KETTE: uebersprungen, keine Netzraeume"; exit 0; }
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
ok "Netzraum und Draht stehen (Osum $OSUM_IP, Wirt $HOST_IP)"

VA=ka-$$
VB=kb-$$
ip link add "$VA" type veth peer name "$VB"
ip link set "$VB" netns "$NS"
ip addr add 10.9.1.1/24 dev "$VA"
ip link set "$VA" up

NFT_KETTE=$(nft list ruleset 2>/dev/null || true)
if command -v nft >/dev/null 2>&1 && [[ "$NFT_KETTE" == *"policy drop"* ]]; then
    if nft insert rule inet filter input iifname "$VA" tcp dport "$DIENST_PORT" accept 2>/dev/null; then
        NFT_REGEL=1
        note "Firewall: $VA:$DIENST_PORT vorruebergehend freigegeben"
    fi
fi
ip netns exec "$NS" ip addr add 10.9.1.2/24 dev "$VB"
ip netns exec "$NS" ip link set "$VB" up
DIENST="http://10.9.1.1:$DIENST_PORT"

PW="$W/dienst"
mkdir -p "$PW"
python3 "$BRUECKE/bridge_server.py" --port "$DIENST_PORT" \
    --bind 10.9.1.1 --wurzel "$PW" > "$W/dienst.log" 2>&1 & DIPID=$!
for i in $(seq 1 40); do
    G=$(ip netns exec "$NS" curl -s --max-time 2 "$DIENST/bruecke/gesund" 2>/dev/null || true)
    case "$G" in *'"gesund"'*) break ;; esac
    sleep 0.25
done
VK=$(cat "$PW/admin.key" 2>/dev/null || cat "$PW/verwalter.key" 2>/dev/null || echo "")
G=$(ip netns exec "$NS" curl -s --max-time 5 "$DIENST/bruecke/gesund" 2>/dev/null || true)
GUT=0
case "$G" in *'"gesund"'*) GUT=1 ;; esac
if [ -n "$VK" ] && [ "$GUT" = 1 ]; then
    ok "der Netzraum erreicht den Brueckendienst unter $DIENST"
    note "eigene Wurzel $PW -- das Koppelbuch des Betriebs bleibt unberuehrt"
else
    bad "der Netzraum erreicht den Brueckendienst NICHT"
    tail -4 "$W/dienst.log" | sed 's/^/        /'
fi

ip netns exec "$NS" python3 "$BRUECKE/anschluss.py" --port "$TLSPORT" \
    --bind 0.0.0.0 --cert "$W/certs/good.pem" --key "$W/certs/good.key" \
    --dienst "$DIENST" > "$W/anschluss.log" 2>&1 & ANPID=$!
sleep 1
if kill -0 "$ANPID" 2>/dev/null; then
    ok "der Anschluss horcht im Netzraum auf $HOST_IP:$TLSPORT"
else
    bad "der Anschluss ist nicht gestartet"
    tail -5 "$W/anschluss.log" | sed 's/^/        /'
    echo "KETTE: $pass bestanden, $fail durchgefallen"; exit 1
fi

starte_osum() {
    # starte_osum <name> <skript>
    #
    if [ ! -f "$W/live.img" ]; then
        cp "$W/probe.img" "$W/live.img"
    fi
    timeout 300 qemu-system-x86_64 -kernel "$W/k.mb" -m 256 \
        -append "osum nokbd nosched noproc nofs noring3 gfx nocursor fbres=1280x800 nic nip=$OSUM_IP/24 ngw=$HOST_IP nsvc=0 nwait=0 script=$2" \
        -serial "file:$W/s-$1.txt" -display none -no-reboot \
        -drive "file=$W/live.img,format=raw,if=ide,index=0" \
        -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
        -device "e1000,netdev=n0,mac=52:54:00:bb:cc:dd" -vga std \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$W/q-$1.log" 2>&1
}

echo "== 3. die Kopplung, in der richtigen Reihenfolge =="
starte_osum kopplung "jarvisd -1 -t 25000;exit"
CODE=$(grep -aoE 'PAIRING CODE [0-9]+' "$W/s-kopplung.txt" | head -1 | awk '{print $3}')
if [ -n "$CODE" ]; then
    ok "Osum verbindet sich und zeigt den PAIRING CODE auf dem Schirm"
    note "Code $CODE"
else
    bad "kein Kopplungscode -- Osum kam nicht durch"
    grep -aE 'jarvisd:' "$W/s-kopplung.txt" | tail -6 | sed 's/^/        /'
    tail -6 "$W/anschluss.log" | sed 's/^/        /'
    echo "KETTE: $pass bestanden, $fail durchgefallen"; exit 1
fi

KENN=$(curl -s -H "X-Bruecke-Verwalter: $VK" \
    "http://10.9.1.1:$DIENST_PORT/bruecke/geraete" | python3 -c '
import json, sys
try:
    g = json.load(sys.stdin).get("geraete", [])
    print(g[-1]["kennung"] if g else "")
except Exception:
    print("")' 2>/dev/null)
if [ -n "$KENN" ]; then
    ok "der Dienst fuehrt das Geraet als $KENN"
else
    bad "der Dienst kennt kein Geraet -- die Anmeldung kam nicht an"
    tail -8 "$W/anschluss.log" | sed 's/^/        /'
fi

A=$(curl -s -X POST "http://10.9.1.1:$DIENST_PORT/bruecke/koppeln" \
    -H "X-Bruecke-Verwalter: $VK" -H 'Content-Type: application/json' \
    -d "{\"geraet\":\"$KENN\",\"code\":\"$CODE\",\"was\":\"frei\"}")
if echo "$A" | grep -q '"gekoppelt": *true'; then
    ok "JARVIS gibt die Kopplung frei"
else
    bad "die Freigabe ging nicht -- $A"
fi

echo "== 4. DAS BILDSCHIRMFOTO, ueber die ganze Kette =="
A=$(curl -s -X POST "http://10.9.1.1:$DIENST_PORT/bruecke/auftrag" \
    -H "X-Bruecke-Verwalter: $VK" -H 'Content-Type: application/json' \
    -d "{\"geraet\":\"$KENN\",\"art\":\"foto\"}")
AID=$(echo "$A" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))' 2>/dev/null)
note "Auftrag id=$AID eingereiht"

starte_osum foto "jarvisctl pair $CODE;jarvisctl screenshot 900;jarvisd -t 90000;exit" &
QWAIT=$!

for i in $(seq 1 120); do
    ABL=$(ls -1 "$PW/geraete/$KENN"/*.png 2>/dev/null | tail -1 || true)
    if [ -n "$ABL" ] && [ -s "$ABL" ]; then
        cp "$ABL" "$W/schuss.png"
        break
    fi
    curl -s --max-time 30 -H "X-Bruecke-Verwalter: $VK" \
        "http://10.9.1.1:$DIENST_PORT/bruecke/holen?geraet=$KENN&id=$AID" \
        -o "$W/schuss.png" 2>/dev/null
    if [ -s "$W/schuss.png" ]; then
        case "$(head -c8 "$W/schuss.png" | tr -d '\0')" in *PNG*) break ;; esac
    fi
    sleep 1
done
wait $QWAIT 2>/dev/null

IST_PNG=0
if [ -s "$W/schuss.png" ]; then
    case "$(head -c8 "$W/schuss.png" | tr -d '\0')" in *PNG*) IST_PNG=1 ;; esac
fi
ABLAGE=$(ls -1 "$PW/geraete/$KENN"/*.png 2>/dev/null | tail -1 || true)
if [ "$IST_PNG" = 0 ] && [ -n "$ABLAGE" ]; then
    cp "$ABLAGE" "$W/schuss.png"
    IST_PNG=1
    note "abgeholt aus der Ablage des Dienstes: $ABLAGE"
fi
if [ "$IST_PNG" = 1 ]; then
    MASS=$(python3 - "$W/schuss.png" <<'PYEOF'
import struct, sys
d = open(sys.argv[1], "rb").read()
w, h = struct.unpack(">II", d[16:24])
print("%dx%d, %d Oktette" % (w, h, len(d)))
PYEOF
)
    ok "DAS BILD IST DA -- $MASS"
    note "liegt in $W/schuss.png und unter $PW/geraete/$KENN/"
else
    bad "kein Bildschirmfoto ueber die Kette"
    grep -aE 'jarvisd:|foto' "$W/s-foto.txt" 2>/dev/null | tail -8 | sed 's/^/        /'
    tail -10 "$W/anschluss.log" | sed 's/^/        /'
fi

echo
echo "KETTE: $pass bestanden, $fail durchgefallen"
[ "$fail" -eq 0 ] || exit 1
