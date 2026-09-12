#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/bruecke/kette.sh -- RUNDE BRUECKE: DIE GANZE KETTE, ENDE ZU ENDE.
#
# ====================================================================
# WAS HIER GEMESSEN WIRD
# ====================================================================
#
#   Osum (QEMU)  --TLS-->  anschluss.py  --HTTPS-->  bruecke_server.py
#                                                          |
#   JARVIS  <--------- das Bild ---------------------------+
#
# Und zwar in dieser Richtung: ICH fordere ein Bildschirmfoto an,
# Osum macht es, und es landet auf dem Server. Das ist der Punkt, an
# dem die Runde steht oder faellt -- alles andere ist Verwaltung.
#
# DER NETZRAUM UND WARUM. Osum in QEMU haengt an einem
# AF_PACKET-Draht (`tools/net/bridge.c`), dessen Wirtsende KEINE
# Schnittstelle ist, fuer die der Linux-Stapel antwortet. Aus dem
# Netzraum heraus ist `127.0.0.1` das Loopback DES NETZRAUMS, nicht
# das des Wirts. Deshalb laeuft `anschluss.py` IM Netzraum -- genau
# wie `peer.py` es seit Runde BRIDGE tut. Der Brueckendienst
# bleibt beim Wirt; der Anschluss erreicht ihn ueber die Adresse des
# veth-Endes.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
W=${KETTE_W:-/tmp/bruecke-kette}
BRUECKE=${BRUECKE_DIR:-/root/bruecke}
# ZWEI PORTS AUS DERSELBEN ZAHL WAREN EINMAL DERSELBE PORT: der Dienst
# nahm `8700 + $$ % 200`, der Anschluss `8600 + $$ % 300` -- bei
# $$=511245 ergab beides 8745. Der zweite bekam EADDRINUSE, und der
# Laeufer suchte den Fehler in der Firewall. Die Bereiche muessen sich
# AUSSCHLIESSEN, verschiedene Moduli reichen nicht.
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
    # Die Firewallregel wieder wegnehmen -- sie gehoert diesem Lauf.
    if [ "${NFT_REGEL:-0}" = 1 ]; then
        H=$(nft -a list chain inet filter input 2>/dev/null | grep "ka-$$" | grep -oE "handle [0-9]+$" | awk '{print $2}' | tail -1)
        [ -n "$H" ] && nft delete rule inet filter input handle "$H" 2>/dev/null
    fi
}
trap cleanup EXIT

# ALTE RESTE WEG, BEVOR ES LOSGEHT. Ein abgebrochener Lauf laesst
# Netzraum, veth-Paar und Firewallregel stehen; der naechste bekommt
# dann eine ZWEITE Adresse 10.9.1.1 im selben Netz und misst, warum
# nichts durchkommt. Genau das ist hier zweimal passiert.
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

# Die Zertifikatskette. NICHT `openssl req -x509` -- Osums X.509-Leser
# nimmt die nicht an (gemessen in Runde BRIDGE-2, V_PARSE).
mkdir -p "$W/certs"
if [ ! -f "$W/certs/good.pem" ]; then
    python3 tools/hwnet/mkcerts.py "$W/certs" jarvis.test >"$W/certs.txt" 2>&1 || {
        echo "mkcerts.py fehlgeschlagen"; cat "$W/certs.txt"; exit 1; }
fi
# In den Wurzelspeicher gehoert die WURZEL, nicht das Serverzertifikat.
cp "$W/certs/ca.pem" "$W/roots.pem"
ok "Zertifikatskette aus tools/hwnet/mkcerts.py (jarvis.test, SAN 10.9.0.1)"

cat > "$W/rechte.conf" <<CONF
server         = $HOST_IP:$TLSPORT
servername     = jarvis.test
wurzeln        = /etc/ssl/roots.pem
befehle        = ja
befehl_erlaubt = /bin/echo
befehl_erlaubt = /bin/ls
lesen          = /var/jarvis/
schreiben      = /var/jarvis/
auflisten      = /var/jarvis/
bildschirmfoto = ja
systeminfo     = ja
eingabe        = ja
max_ausgabe    = 65536
max_datei      = 4194304
protokoll       = /var/log/jarvisd.log
arbeitsdatei    = /var/jarvis/ausgabe.txt
fotoscheindatei = /var/jarvis/fotoschein
CONF

bauen_img() {
    local SPEC="/bin/ /etc/ /etc/ssl/ /etc/jarvis/ /var/ /var/log/ /var/jarvis/"
    for p in sh ls cat echo chmod jsig jarvisctl; do
        SPEC="$SPEC /bin/$p=$W/$p.elf"
    done
    SPEC="$SPEC /bin/jarvisd=$W/jarvisd.elf"
    SPEC="$SPEC /etc/jarvis/rechte.conf=$W/rechte.conf"
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

# DER ANSCHLUSS LAEUFT IM NETZRAUM, der Brueckendienst beim Wirt --
# und dazwischen muss ein Weg sein.
#
# DER ERSTE ANLAUF NAHM DIE LAN-ADRESSE DES WIRTS (192.168.1.54) und
# scheiterte mit "Network is unreachable": der Netzraum hat NUR das
# veth-Paar, keine Route dorthin. Das Wirtsende `$V0` gehoert ausserdem
# `tools/net/bridge.c` (AF_PACKET) und traegt absichtlich keine
# Adresse -- es ist keine Schnittstelle, fuer die der Stapel antwortet.
#
# ALSO EIN ZWEITES veth-PAAR, nur fuer den Anschluss. Es hat mit Osums
# Draht nichts zu tun und stoert ihn nicht: eigene Adressen (10.9.1.x),
# beide Enden mit Adresse, und der Wirt antwortet darauf ganz normal.
# Das ist der Weg, den `echtserver.sh` sich gespart hat, indem es den
# ganzen Server in den Netzraum stellte -- hier geht das nicht, weil
# der Brueckendienst ein systemd-Dienst beim Wirt ist.
VA=ka-$$
VB=kb-$$
ip link add "$VA" type veth peer name "$VB"
ip link set "$VB" netns "$NS"
ip addr add 10.9.1.1/24 dev "$VA"
ip link set "$VA" up

# DIE FIREWALL. Dieser Wirt hat eine nftables-Kette mit `policy drop`,
# die nur ausgewaehlte Anschluesse durchlaesst -- gemessen: `ping`
# kam durch (ICMP steht in der Kette), TCP nicht (`curl` rc=28,
# Zeitablauf). Ohne diese Regel dreht der Laeufer in seiner
# Warteschleife, und der Fehler sieht wie ein langsamer Dienst aus.
#
# DIE REGEL IST SO ENG WIE MOEGLICH: nur dieses Interface, nur dieser
# Anschluss, und sie wird beim Aufraeumen WIEDER WEGGENOMMEN. Ein
# Pruefstand, der die Firewall des Wirts dauerhaft aufmacht, hat mehr
# kaputtgemacht als gemessen.
#
# `insert` UND NICHT `add`, und das ist der Unterschied zwischen einer
# Regel, die wirkt, und einer, die nur dasteht: `add` haengt hinten an,
# hinter den `counter ... comment "verworfen"` -- gemessen, die Regel
# stand mit `handle 24` in der Kette und der Verkehr wurde trotzdem
# verworfen. `insert` setzt sie an den Anfang.
# `grep -q` UND `pipefail` VERTRAGEN SICH NICHT, und das hat diesen
# Block dreimal still uebersprungen: `grep -q` hoert beim ersten
# Treffer auf, `nft` schreibt weiter, bekommt SIGPIPE -- und mit
# `set -o pipefail` ist der Rueckgabewert der Pipeline dann 141, also
# falsch. Gemessen: `nft ... | grep -q "policy drop"; echo $?` gab 141,
# und die Bedingung war nie wahr, obwohl die Kette `policy drop` hat.
# Deshalb erst in eine Variable, dann pruefen.
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

# DER DIENST HORCHT IM BETRIEB NUR AUF 127.0.0.1, und das bleibt auch
# so -- von aussen kommt man ausschliesslich durch die Weiterreichung
# in `orientstore/werkzeug/diagnose_server.py`. Fuer diesen Laeufer
# braucht der Netzraum aber einen Weg dorthin, also laeuft hier ein
# ZWEITER Dienst auf der Pruefadresse, mit EIGENER Wurzel.
#
# EIGENE WURZEL, und das ist kein Beiwerk: ein Pruefstand, der das
# Koppelbuch des Betriebs anfasst, koppelt im schlimmsten Fall Justins
# echten Rechner um. `--wurzel $W/dienst` haelt beides getrennt.
PW="$W/dienst"
mkdir -p "$PW"
python3 "$BRUECKE/bruecke_server.py" --port "$DIENST_PORT" \
    --bind 10.9.1.1 --wurzel "$PW" > "$W/dienst.log" 2>&1 & DIPID=$!
# WARTEN, BIS ER WIRKLICH ANTWORTET, und nicht `sleep 1`. Der erste
# Anlauf fragte nach einer Sekunde und bekam nichts -- der Dienst stand
# im Protokoll schon, hatte den Anschluss aber noch nicht offen. Eine
# feste Wartezeit ist bei so etwas immer entweder zu kurz oder zu lang.
# WIEDER OHNE `grep -q` IN EINER PIPELINE (siehe die Begruendung bei
# NFT_KETTE): mit `pipefail` gibt so eine Pipeline 141 statt 0, und die
# Schleife laeuft ihre vierzig Runden ab, obwohl der Dienst laengst
# antwortet. Das Ergebnis kommt deshalb in eine Variable.
for i in $(seq 1 40); do
    G=$(ip netns exec "$NS" curl -s --max-time 2 "$DIENST/bruecke/gesund" 2>/dev/null || true)
    case "$G" in *'"gesund"'*) break ;; esac
    sleep 0.25
done
VK=$(cat "$PW/verwalter.key" 2>/dev/null || echo "")
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
    # DIESELBE PLATTE UEBER ALLE LAEUFE, und das ist der Unterschied
    # zwischen einem Geraet und einem Wegwerfgeraet.
    #
    # Der erste Anlauf kopierte vor JEDEM Start `probe.img` frisch --
    # damit war auch `/etc/jarvis/geraet.key` jedes Mal neu, `jsig`
    # erzeugte einen neuen Ed25519-Schluessel, und der Server sagte
    # voellig zu Recht "Schluessel passt nicht zur Kopplung"
    # (gemessen: 15ae7b09f33f beim Koppeln, 72137258ee24 beim Foto).
    #
    # Das war KEIN Fehler der Bruecke, sondern einer des Pruefstands:
    # ein Rechner, der beim Neustart seine Identitaet verliert, DARF
    # nicht mehr hereinkommen. Also wird die Platte einmal angelegt und
    # danach behalten -- wie eine Platte in einem Rechner.
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
# Wie an einem echten Geraet: erst verbinden (Code kommt), dann
# bestaetigt der Mensch AM GERAET, dann gibt der Mensch am SERVER frei.
starte_osum kopplung "jarvisd -1 -t 25000;exit"
CODE=$(grep -aoE 'KOPPLUNGSCODE [0-9]+' "$W/s-kopplung.txt" | head -1 | awk '{print $2}')
if [ -n "$CODE" ]; then
    ok "Osum verbindet sich und zeigt den KOPPLUNGSCODE auf dem Schirm"
    note "Code $CODE"
else
    bad "kein Kopplungscode -- Osum kam nicht durch"
    grep -aE 'jarvisd:' "$W/s-kopplung.txt" | tail -6 | sed 's/^/        /'
    tail -6 "$W/anschluss.log" | sed 's/^/        /'
    echo "KETTE: $pass bestanden, $fail durchgefallen"; exit 1
fi

# DIE KENNUNG KOMMT VOM DIENST UND NICHT AUS DEM PROTOKOLL.
#
# Der erste Anlauf fischte sie mit `grep -oE 'osum-[0-9a-f]+'` aus dem
# Protokoll des Anschlusses und bekam `osum-b` -- der Ausdruck traf die
# Zeile "Osum verbunden von ...", nicht die Kennung. Danach hiess es
# "kein solches Geraet", und der Fehler sah aus wie ein Problem der
# Kopplung.
#
# Der Dienst WEISS, wie das Geraet heisst; er hat es gerade angelegt.
# Also wird er gefragt, statt seinen Namen aus Fliesstext zu raten.
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
# Der Auftrag liegt SCHON in der Schlange, wenn Osum sich meldet --
# so wie es auch im Betrieb ist: ich fordere an, das Geraet holt ab.
A=$(curl -s -X POST "http://10.9.1.1:$DIENST_PORT/bruecke/auftrag" \
    -H "X-Bruecke-Verwalter: $VK" -H 'Content-Type: application/json' \
    -d "{\"geraet\":\"$KENN\",\"art\":\"foto\"}")
AID=$(echo "$A" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))' 2>/dev/null)
note "Auftrag id=$AID eingereiht"

# `jarvisctl fotoschein` ist das zweite Schloss: die Rechteliste allein
# reicht nicht. Genau wie an einem echten Geraet.
starte_osum foto "jarvisctl koppeln $CODE;jarvisctl fotoschein 900;jarvisd -t 90000;exit" &
QWAIT=$!

# ZWEI WEGE, UND DER ZWEITE IST DER VERLAESSLICHE.
#
# `--max-time 3` GEGEN EINEN ENDPUNKT, DER 25 SEKUNDEN WARTET, ist ein
# Widerspruch: `/bruecke/holen` haelt die Anfrage bis WARTE_S offen,
# damit der Aufrufer das Bild bekommt und kein "noch nicht". Mit drei
# Sekunden bricht JEDER Versuch vorher ab -- gemessen, das Bild lag
# nach vier Sekunden auf der Platte und die Schleife drehte trotzdem
# ihre 120 Runden.
#
# Also wird zuerst die ABLAGE angesehen (der Dienst schreibt jedes
# Ergebnis dorthin, das ist billig und sofort sichtbar) und nur
# danach abgeholt -- mit einer Frist, die zur Gegenstelle passt.
for i in $(seq 1 120); do
    ABL=$(ls -1 "$PW/geraete/$KENN"/*.png 2>/dev/null | tail -1 || true)
    if [ -n "$ABL" ] && [ -s "$ABL" ]; then
        cp "$ABL" "$W/schuss.png"
        break
    fi
    curl -s --max-time 30 -H "X-Bruecke-Verwalter: $VK" \
        "http://10.9.1.1:$DIENST_PORT/bruecke/holen?geraet=$KENN&id=$AID" \
        -o "$W/schuss.png" 2>/dev/null
    # ZUM DRITTEN MAL `grep -q` IN EINER PIPELINE (siehe NFT_KETTE):
    # mit `pipefail` ist das Ergebnis 141 und nie 0, die Schleife bricht
    # nie ab, und das Bild sieht aus, als waere es nicht angekommen --
    # obwohl es laengst auf der Platte liegt. Hier ohne Pipeline.
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
# DIE ZWEITE QUELLE: der Dienst legt jedes Ergebnis auch auf die
# Platte. Steht es dort, ist das Bild angekommen -- auch wenn das
# Abholen daneben ging. Beides zu pruefen trennt "Osum hat kein Bild
# gemacht" von "der Laeufer hat es nicht abgeholt".
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
