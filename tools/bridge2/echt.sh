#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
W=${BRUECKE_W:-/tmp/bruecke-echt}
ZIEL=${BRUECKE_ZIEL:-https://store.fleitec.com}
SCHLUESSEL=${BRUECKE_KEY:-/srv/bruecke/verwalter.key}
rm -rf "$W"; mkdir -p "$W"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }
jget(){ python3 -c "import json,sys
try: print(json.load(sys.stdin).get('$1',''))
except Exception: print('')"; }

for t in curl python3; do
    command -v "$t" >/dev/null 2>&1 || { echo "BRUECKE: uebersprungen, $t fehlt"; exit 0; }
done
python3 -c 'import cryptography' 2>/dev/null || {
    echo "BRUECKE: uebersprungen, python-cryptography fehlt"; exit 0; }
[ -r "$SCHLUESSEL" ] || { echo "BRIDGE: skipped, $SCHLUESSEL not readable"; exit 0; }
VK=$(cat "$SCHLUESSEL")

KENN="pruefstand-$$"

echo "== 1. the service is reachable from OUTSIDE =="
G=$(curl -s --max-time 10 "$ZIEL/bruecke/gesund")
if echo "$G" | grep -q '"gesund": *true'; then
    ok "GET $ZIEL/bruecke/gesund answers -- through the real certificate"
    note "$G"
else
    bad "the bridge service is not reachable over HTTPS"
    note "Antwort: $G"
    echo "BRUECKE: $pass bestanden, $fail durchgefallen"; exit 1
fi

echo "== 2. nothing works without the admin key =="
A=$(curl -s --max-time 10 "$ZIEL/bruecke/geraete")
if echo "$A" | grep -q 'kein Verwalterschluessel'; then
    ok "GET /bruecke/geraete without key: rejected"
else
    bad "the device list was readable without a key -- $A"
fi
A=$(curl -s --max-time 10 -X POST "$ZIEL/bruecke/auftrag" \
    -H 'Content-Type: application/json' \
    -d "{\"geraet\":\"$KENN\",\"art\":\"befehl\",\"ziel\":\"/bin/ls\"}")
if echo "$A" | grep -q 'kein Verwalterschluessel'; then
    ok "POST /bruecke/auftrag without key: rejected"
else
    bad "a job went through without a key -- $A"
fi

echo "== 3. the login: nobody gets in without approval =="
python3 - "$W" <<'PYEOF'
import sys, os
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization
w = sys.argv[1]
k = Ed25519PrivateKey.generate()
raw = k.private_bytes(encoding=serialization.Encoding.Raw,
                      format=serialization.PrivateFormat.Raw,
                      encryption_algorithm=serialization.NoEncryption())
pub = k.public_key().public_bytes(encoding=serialization.Encoding.Raw,
                                  format=serialization.PublicFormat.Raw)
open(os.path.join(w, "geraet.key"), "wb").write(raw)
open(os.path.join(w, "geraet.pub"), "w").write(pub.hex())
PYEOF
PUB=$(cat "$W/geraet.pub")
note "oeffentlicher Geraeteschluessel ${PUB:0:16}..."

A=$(curl -s --max-time 10 -X POST "$ZIEL/bruecke/anmelden" \
    -H 'Content-Type: application/json' \
    -d "{\"kennung\":\"$KENN\",\"pubkey\":\"$PUB\",\"info\":{\"rechner\":\"pruefstand\",\"aufloesung\":\"1280x800\"}}")
CODE=$(echo "$A" | jget code)
if echo "$A" | grep -q 'kopplung-noetig' && [ -n "$CODE" ]; then
    ok "an unknown device gets a PAIRING CODE and nothing else"
    note "Code $CODE -- den zeigt das Geraet auf SEINEM Bildschirm"
else
    bad "the first login brought no pairing code -- $A"
fi

A=$(curl -s --max-time 10 -X POST "$ZIEL/bruecke/warten" \
    -H 'Content-Type: application/json' \
    -d "{\"kennung\":\"$KENN\",\"marke\":\"egal\"}")
if echo "$A" | grep -q 'nicht gekoppelt'; then
    ok "CONTROL: an unpaired device gets no work"
else
    bad "an unpaired device got an answer -- $A"
fi

echo "== 4. a WRONG code does not pair =="
A=$(curl -s --max-time 10 -X POST "$ZIEL/bruecke/koppeln" \
    -H "X-Bruecke-Verwalter: $VK" -H 'Content-Type: application/json' \
    -d "{\"geraet\":\"$KENN\",\"code\":\"000000\",\"was\":\"frei\"}")
if echo "$A" | grep -q 'Code stimmt nicht'; then
    ok "a code nobody asked for is rejected"
else
    bad "a wrong code paired -- $A"
fi

echo "== 5. with the right code, then the proof of the key =="
A=$(curl -s --max-time 10 -X POST "$ZIEL/bruecke/koppeln" \
    -H "X-Bruecke-Verwalter: $VK" -H 'Content-Type: application/json' \
    -d "{\"geraet\":\"$KENN\",\"code\":\"$CODE\",\"was\":\"frei\"}")
if echo "$A" | grep -q '"gekoppelt": *true'; then
    ok "with the right code the pairing is done"
else
    bad "the pairing failed -- $A"
fi

A=$(curl -s --max-time 10 -X POST "$ZIEL/bruecke/anmelden" \
    -H 'Content-Type: application/json' \
    -d "{\"kennung\":\"$KENN\",\"pubkey\":\"$PUB\"}")
FORD=$(echo "$A" | jget forderung)
if [ -n "$FORD" ]; then
    ok "the paired device gets a RANDOM CHALLENGE"
else
    bad "keine Forderung -- $A"
fi

FALSCH=$(python3 -c 'print("aa"*64)')
A=$(curl -s --max-time 10 -X POST "$ZIEL/bruecke/anmelden" \
    -H 'Content-Type: application/json' \
    -d "{\"kennung\":\"$KENN\",\"pubkey\":\"$PUB\",\"forderung\":\"$FORD\",\"unterschrift\":\"$FALSCH\"}")
if echo "$A" | grep -q 'Unterschrift falsch'; then
    ok "SECURITY PROOF: a WRONG signature is REJECTED"
else
    bad "a wrong signature got through -- $A"
fi

A=$(curl -s --max-time 10 -X POST "$ZIEL/bruecke/anmelden" \
    -H 'Content-Type: application/json' \
    -d "{\"kennung\":\"$KENN\",\"pubkey\":\"$PUB\"}")
FORD=$(echo "$A" | jget forderung)
SIG=$(python3 - "$W/geraet.key" "$KENN" "$FORD" <<'PYEOF'
import sys
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
k = Ed25519PrivateKey.from_private_bytes(open(sys.argv[1], "rb").read())
print(k.sign(("bruecke:" + sys.argv[2] + ":" + sys.argv[3]).encode()).hex())
PYEOF
)
A=$(curl -s --max-time 10 -X POST "$ZIEL/bruecke/anmelden" \
    -H 'Content-Type: application/json' \
    -d "{\"kennung\":\"$KENN\",\"pubkey\":\"$PUB\",\"forderung\":\"$FORD\",\"unterschrift\":\"$SIG\",\"info\":{\"rechner\":\"pruefstand\",\"aufloesung\":\"1280x800\"}}")
MARKE=$(echo "$A" | jget marke)
if [ -n "$MARKE" ]; then
    ok "the RIGHT signature brings a session token"
else
    bad "the right signature was not accepted -- $A"
fi

echo "== 6. a FOREIGN key under the same name =="
python3 - "$W" <<'PYEOF'
import sys, os
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization
k = Ed25519PrivateKey.generate()
pub = k.public_key().public_bytes(encoding=serialization.Encoding.Raw,
                                  format=serialization.PublicFormat.Raw)
open(os.path.join(sys.argv[1], "fremd.pub"), "w").write(pub.hex())
PYEOF
FPUB=$(cat "$W/fremd.pub")
A=$(curl -s --max-time 10 -X POST "$ZIEL/bruecke/anmelden" \
    -H 'Content-Type: application/json' \
    -d "{\"kennung\":\"$KENN\",\"pubkey\":\"$FPUB\"}")
if echo "$A" | grep -q 'Schluessel passt nicht'; then
    ok "SECURITY PROOF: a FOREIGN key under the same name is REJECTED"
else
    bad "a foreign key was accepted -- $A"
fi

echo "== 7. Auftrag hin, Bild her =="
A=$(curl -s --max-time 10 -X POST "$ZIEL/bruecke/auftrag" \
    -H "X-Bruecke-Verwalter: $VK" -H 'Content-Type: application/json' \
    -d "{\"geraet\":\"$KENN\",\"art\":\"foto\"}")
AID=$(echo "$A" | jget id)
if [ -n "$AID" ]; then
    ok "JARVIS puts a photo job in the queue (id=$AID)"
else
    bad "the job was not accepted -- $A"
fi

T0=$(date +%s%N)
A=$(curl -s --max-time 40 -X POST "$ZIEL/bruecke/warten" \
    -H 'Content-Type: application/json' \
    -d "{\"kennung\":\"$KENN\",\"marke\":\"$MARKE\"}")
MS=$(( ($(date +%s%N) - T0) / 1000000 ))
if echo "$A" | grep -q '"art": *"foto"'; then
    ok "the device gets the job while waiting -- after ${MS} ms"
else
    bad "the job did not reach the device -- $A"
fi

python3 - "$W" <<'PYEOF'
import sys, os, zlib, struct
w = sys.argv[1]
bd, ht = 64, 48
roh = b""
for y in range(ht):
    roh += b"\x00" + b"".join(bytes([(x * 4) % 256, (y * 5) % 256, 128])
                              for x in range(bd))
def stueck(typ, daten):
    return (struct.pack(">I", len(daten)) + typ + daten
            + struct.pack(">I", zlib.crc32(typ + daten) & 0xFFFFFFFF))
png = (b"\x89PNG\r\n\x1a\n"
       + stueck(b"IHDR", struct.pack(">IIBBBBB", bd, ht, 8, 2, 0, 0, 0))
       + stueck(b"IDAT", zlib.compress(roh, 9))
       + stueck(b"IEND", b""))
open(os.path.join(w, "probe.png"), "wb").write(png)
PYEOF

A=$(curl -s --max-time 20 -X POST "$ZIEL/bruecke/ergebnis" \
    -H "X-Bruecke-Geraet: $KENN" -H "X-Bruecke-Marke: $MARKE" \
    -H "X-Bruecke-Id: $AID" -H "X-Bruecke-Status: ok" \
    -H "X-Bruecke-Typ: image/png" \
    --data-binary "@$W/probe.png")
if echo "$A" | grep -q '"angenommen": *true'; then
    ok "the device uploads the image, the server accepts it"
    note "$A"
else
    bad "the result was not accepted -- $A"
fi

curl -s --max-time 20 -H "X-Bruecke-Verwalter: $VK" \
    "$ZIEL/bruecke/holen?geraet=$KENN&id=$AID" -o "$W/geholt.png"
if [ -s "$W/geholt.png" ] && cmp -s "$W/probe.png" "$W/geholt.png"; then
    ok "JARVIS fetches the image -- byte for byte the same ($(stat -c%s "$W/geholt.png") Oktette)"
else
    bad "the fetched image does not match the uploaded one"
fi

echo "== 8. the long poll really waits =="
T0=$(date +%s%N)
A=$(curl -s --max-time 45 -X POST "$ZIEL/bruecke/warten" \
    -H 'Content-Type: application/json' \
    -d "{\"kennung\":\"$KENN\",\"marke\":\"$MARKE\"}")
MS=$(( ($(date +%s%N) - T0) / 1000000 ))
if echo "$A" | grep -q '"auftrag": *null' && [ "$MS" -gt 20000 ]; then
    ok "without work the server keeps the request open ${MS} ms and then says null"
    note "das ist das lange Polling -- kein Hammern im Sekundentakt"
else
    bad "the long poll did not wait (${MS} ms) -- $A"
fi

echo "== 9. die Sperre =="
A=$(curl -s --max-time 10 -X POST "$ZIEL/bruecke/koppeln" \
    -H "X-Bruecke-Verwalter: $VK" -H 'Content-Type: application/json' \
    -d "{\"geraet\":\"$KENN\",\"was\":\"sperren\"}")
if echo "$A" | grep -q '"gesperrt": *true'; then
    ok "a device can be blocked"
else
    bad "blocking failed -- $A"
fi
A=$(curl -s --max-time 10 -X POST "$ZIEL/bruecke/anmelden" \
    -H 'Content-Type: application/json' \
    -d "{\"kennung\":\"$KENN\",\"pubkey\":\"$PUB\"}")
if echo "$A" | grep -q 'gesperrt'; then
    ok "SECURITY PROOF: a BLOCKED device can no longer log in"
else
    bad "a blocked device could log in -- $A"
fi

echo
echo "BRUECKE: $pass bestanden, $fail durchgefallen"
[ "$fail" -eq 0 ] || exit 1
