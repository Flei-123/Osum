#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/bridge2/echt.sh -- RUNDE BRUECKE: DER WEG VON AUSSEN, ueber HTTPS.
#
# ====================================================================
# WAS DIESER LAEUFER BEWEIST, UND WAS `echtserver.sh` NICHT BEWIES
# ====================================================================
#
# `tools/bridge/echtserver.sh` (Runde BRIDGE-2) stellt einen JARVIS in
# einen NETZRAUM auf demselben Rechner und laesst Osum sich dort
# anmelden. Das ist ein ehrlicher Nachweis fuer das PROTOKOLL -- aber
# nicht fuer den WEG. Im Netzraum ist der Server einen Hop entfernt,
# hat eine feste 10.9.0.1 und ein selbstgemachtes Zertifikat.
#
# Justins Rechner steht hinter einem fremden Router, in einem anderen
# Heimnetz, und muss durch: NAT, die Router-Firewall, das ECHTE
# Zertifikat von store.fleitec.com und den openresty davor. Nichts
# davon kommt in einem Netzraum vor. Dieser Laeufer misst genau das --
# er spricht mit derselben oeffentlichen Adresse, die auch das Geraet
# in Justins Wohnzimmer anspricht.
#
# WAS ER NICHT MISST: den Osum-Client. Dafuer ist
# `tools/bridge2/qemu.sh` da. Die beiden zusammen decken den ganzen
# Weg ab; getrennt, weil ein Laeufer, der beides misst, bei einem
# Fehler nicht sagen kann, auf welcher Seite er lag.
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
[ -r "$SCHLUESSEL" ] || { echo "BRUECKE: uebersprungen, $SCHLUESSEL nicht lesbar"; exit 0; }
VK=$(cat "$SCHLUESSEL")

# Eine Kennung je Lauf. Ohne sie traegt der zweite Lauf die Kopplung
# des ersten und misst damit etwas anderes als der erste.
KENN="pruefstand-$$"

echo "== 1. der Dienst ist von AUSSEN erreichbar =="
G=$(curl -s --max-time 10 "$ZIEL/bruecke/gesund")
if echo "$G" | grep -q '"gesund": *true'; then
    ok "GET $ZIEL/bruecke/gesund antwortet -- durch das echte Zertifikat"
    note "$G"
else
    bad "der Brueckendienst ist ueber HTTPS nicht erreichbar"
    note "Antwort: $G"
    echo "BRUECKE: $pass bestanden, $fail durchgefallen"; exit 1
fi

echo "== 2. ohne Verwalterschluessel geht gar nichts =="
A=$(curl -s --max-time 10 "$ZIEL/bruecke/geraete")
if echo "$A" | grep -q 'kein Verwalterschluessel'; then
    ok "GET /bruecke/geraete ohne Schluessel: abgewiesen"
else
    bad "die Geraeteliste war ohne Schluessel lesbar -- $A"
fi
A=$(curl -s --max-time 10 -X POST "$ZIEL/bruecke/auftrag" \
    -H 'Content-Type: application/json' \
    -d "{\"geraet\":\"$KENN\",\"art\":\"befehl\",\"ziel\":\"/bin/ls\"}")
if echo "$A" | grep -q 'kein Verwalterschluessel'; then
    ok "POST /bruecke/auftrag ohne Schluessel: abgewiesen"
else
    bad "ein Auftrag ging ohne Schluessel durch -- $A"
fi

echo "== 3. die Anmeldung: ohne Freigabe kommt niemand herein =="
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
    ok "ein unbekanntes Geraet bekommt einen KOPPLUNGSCODE und sonst nichts"
    note "Code $CODE -- den zeigt das Geraet auf SEINEM Bildschirm"
else
    bad "die Erstanmeldung hat keinen Kopplungscode gebracht -- $A"
fi

A=$(curl -s --max-time 10 -X POST "$ZIEL/bruecke/warten" \
    -H 'Content-Type: application/json' \
    -d "{\"kennung\":\"$KENN\",\"marke\":\"egal\"}")
if echo "$A" | grep -q 'nicht gekoppelt'; then
    ok "GEGENPROBE: ein ungekoppeltes Geraet bekommt keine Arbeit"
else
    bad "ein ungekoppeltes Geraet bekam eine Antwort -- $A"
fi

echo "== 4. ein FALSCHER Code koppelt nicht =="
A=$(curl -s --max-time 10 -X POST "$ZIEL/bruecke/koppeln" \
    -H "X-Bruecke-Verwalter: $VK" -H 'Content-Type: application/json' \
    -d "{\"geraet\":\"$KENN\",\"code\":\"000000\",\"was\":\"frei\"}")
if echo "$A" | grep -q 'Code stimmt nicht'; then
    ok "ein Code, den niemand angefragt hat, wird abgelehnt"
else
    bad "ein falscher Code hat gekoppelt -- $A"
fi

echo "== 5. mit dem richtigen Code, und dann der Beweis des Schluessels =="
A=$(curl -s --max-time 10 -X POST "$ZIEL/bruecke/koppeln" \
    -H "X-Bruecke-Verwalter: $VK" -H 'Content-Type: application/json' \
    -d "{\"geraet\":\"$KENN\",\"code\":\"$CODE\",\"was\":\"frei\"}")
if echo "$A" | grep -q '"gekoppelt": *true'; then
    ok "mit dem richtigen Code ist die Kopplung durch"
else
    bad "die Kopplung ging nicht -- $A"
fi

A=$(curl -s --max-time 10 -X POST "$ZIEL/bruecke/anmelden" \
    -H 'Content-Type: application/json' \
    -d "{\"kennung\":\"$KENN\",\"pubkey\":\"$PUB\"}")
FORD=$(echo "$A" | jget forderung)
if [ -n "$FORD" ]; then
    ok "das gekoppelte Geraet bekommt eine ZUFALLSFORDERUNG"
else
    bad "keine Forderung -- $A"
fi

FALSCH=$(python3 -c 'print("aa"*64)')
A=$(curl -s --max-time 10 -X POST "$ZIEL/bruecke/anmelden" \
    -H 'Content-Type: application/json' \
    -d "{\"kennung\":\"$KENN\",\"pubkey\":\"$PUB\",\"forderung\":\"$FORD\",\"unterschrift\":\"$FALSCH\"}")
if echo "$A" | grep -q 'Unterschrift falsch'; then
    ok "SICHERHEITSNACHWEIS: eine FALSCHE Unterschrift wird ABGELEHNT"
else
    bad "eine falsche Unterschrift kam durch -- $A"
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
    ok "die RICHTIGE Unterschrift bringt eine Sitzungsmarke"
else
    bad "die richtige Unterschrift wurde nicht angenommen -- $A"
fi

echo "== 6. ein FREMDER Schluessel auf denselben Namen =="
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
    ok "SICHERHEITSNACHWEIS: ein FREMDER Schluessel auf denselben Namen wird ABGELEHNT"
else
    bad "ein fremder Schluessel wurde angenommen -- $A"
fi

echo "== 7. Auftrag hin, Bild her =="
A=$(curl -s --max-time 10 -X POST "$ZIEL/bruecke/auftrag" \
    -H "X-Bruecke-Verwalter: $VK" -H 'Content-Type: application/json' \
    -d "{\"geraet\":\"$KENN\",\"art\":\"foto\"}")
AID=$(echo "$A" | jget id)
if [ -n "$AID" ]; then
    ok "JARVIS legt einen Foto-Auftrag in die Schlange (id=$AID)"
else
    bad "der Auftrag ging nicht ein -- $A"
fi

T0=$(date +%s%N)
A=$(curl -s --max-time 40 -X POST "$ZIEL/bruecke/warten" \
    -H 'Content-Type: application/json' \
    -d "{\"kennung\":\"$KENN\",\"marke\":\"$MARKE\"}")
MS=$(( ($(date +%s%N) - T0) / 1000000 ))
if echo "$A" | grep -q '"art": *"foto"'; then
    ok "das Geraet bekommt den Auftrag beim Warten -- nach ${MS} ms"
else
    bad "der Auftrag kam beim Geraet nicht an -- $A"
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
    ok "das Geraet laedt das Bild hoch, der Server nimmt es an"
    note "$A"
else
    bad "das Ergebnis wurde nicht angenommen -- $A"
fi

curl -s --max-time 20 -H "X-Bruecke-Verwalter: $VK" \
    "$ZIEL/bruecke/holen?geraet=$KENN&id=$AID" -o "$W/geholt.png"
if [ -s "$W/geholt.png" ] && cmp -s "$W/probe.png" "$W/geholt.png"; then
    ok "JARVIS holt das Bild ab -- Oktett fuer Oktett dasselbe ($(stat -c%s "$W/geholt.png") Oktette)"
else
    bad "das abgeholte Bild stimmt nicht mit dem hochgeladenen ueberein"
fi

echo "== 8. das lange Polling wartet wirklich =="
T0=$(date +%s%N)
A=$(curl -s --max-time 45 -X POST "$ZIEL/bruecke/warten" \
    -H 'Content-Type: application/json' \
    -d "{\"kennung\":\"$KENN\",\"marke\":\"$MARKE\"}")
MS=$(( ($(date +%s%N) - T0) / 1000000 ))
if echo "$A" | grep -q '"auftrag": *null' && [ "$MS" -gt 20000 ]; then
    ok "ohne Arbeit haelt der Server die Anfrage ${MS} ms offen und sagt dann null"
    note "das ist das lange Polling -- kein Hammern im Sekundentakt"
else
    bad "das lange Polling hat nicht gewartet (${MS} ms) -- $A"
fi

echo "== 9. die Sperre =="
A=$(curl -s --max-time 10 -X POST "$ZIEL/bruecke/koppeln" \
    -H "X-Bruecke-Verwalter: $VK" -H 'Content-Type: application/json' \
    -d "{\"geraet\":\"$KENN\",\"was\":\"sperren\"}")
if echo "$A" | grep -q '"gesperrt": *true'; then
    ok "ein Geraet laesst sich sperren"
else
    bad "das Sperren ging nicht -- $A"
fi
A=$(curl -s --max-time 10 -X POST "$ZIEL/bruecke/anmelden" \
    -H 'Content-Type: application/json' \
    -d "{\"kennung\":\"$KENN\",\"pubkey\":\"$PUB\"}")
if echo "$A" | grep -q 'gesperrt'; then
    ok "SICHERHEITSNACHWEIS: ein GESPERRTES Geraet kommt nicht mehr herein"
else
    bad "ein gesperrtes Geraet konnte sich anmelden -- $A"
fi

echo
echo "BRUECKE: $pass bestanden, $fail durchgefallen"
[ "$fail" -eq 0 ] || exit 1
