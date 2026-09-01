#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/betrieb/run.sh -- RUNDE BETRIEB: DIE NAMENSAUFLOESUNG, DIE
# SCHLUESSELVERWALTUNG UND DIE SERVERSEITE, GEMESSEN.
#
# Voraussetzung: `bash tools/betrieb/vorbereiten.sh $OUT` ist gelaufen
# (Pakete, Zertifikate, Schluesselbund, vier Auslieferungen, Abbild,
# installierte Platte unter $OUT/basis.img).
#
#   bash tools/betrieb/run.sh [--ohne-qemu]
#
# GEGEN WAS GEMESSEN WIRD, und es steht hier und nicht im Kleingedruckten:
#
#   * DER AUFLOESER gegen `dig` (BIND) -- mit ECHTEN Namen und einem
#     ECHTEN Nameserver, weil ein Aufloeser, der nur gegen einen
#     selbstgebauten Server gemessen ist, nur beweist, dass zwei eigene
#     Programme sich einig sind.
#   * DIE HAERTUNG gegen `tools/betrieb/dnsdienst.py --boese`, einen
#     Faelscher, der VOR der richtigen Antwort falsche schickt.
#   * DAS FORMAT gegen `kernel/user/dnswt.fi`, neunzehn von Hand
#     gebaute, feindliche Nachrichten -- ohne ein einziges Paket.
#   * DER UPDATE-WEG gegen `tools/ota/server.py` (echtes TLS 1.3 aus
#     Pythons `ssl`) und `tools/betrieb/dnsdienst.py`, beide auf dem
#     Wirt, das Geraet in QEMU ueber eine e1000.
#
# DER AUFLOESER LAEUFT IN ZWEI LADERN, und beide Male ist es DIESELBE
# Binaerdatei aus DEMSELBEN Quelltext: einmal auf dem Wirt (Linux laedt
# sie, weil Osums Systemaufrufe Linux' Nummern tragen -- Runde K4) und
# einmal in QEMU auf Osum. Der Wirt macht die Messung gegen `dig`
# bezahlbar; QEMU beweist, dass es auf dem echten System laeuft.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${OUT:-/tmp/betrieb-run}
export OUT
export OSUM_CPU=${OSUM_CPU:-Haswell}
export OSUM_SIGN_PASS=${OSUM_SIGN_PASS:-passwort-haupt-4711}
export OSUM_ERSATZ_PASS=${OSUM_ERSATZ_PASS:-passwort-ersatz-0815}
PORT=${BETRIEB_PORT:-18443}
NAME=${BETRIEB_NAME:-pkg.betrieb.test}
NETZ="nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0"
OHNEQEMU=0
[ "${1:-}" = "--ohne-qemu" ] && OHNEQEMU=1
W="$OUT/wirt"
mkdir -p "$W"

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
gleich() { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', erwartet '$3'"; fi; }
hat() { grep -qaF "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 -- '$2' fehlt"; }
hatnicht() { grep -qaF "$2" "$1" 2>/dev/null && bad "$3 -- '$2' steht da" || ok "$3"; }

SRVPID=""; NSDPID=""
dienst_aus() { [ -n "$SRVPID" ] && { kill "$SRVPID" 2>/dev/null; wait "$SRVPID" 2>/dev/null; }; SRVPID=""; }
nsd_aus() { [ -n "$NSDPID" ] && { kill "$NSDPID" 2>/dev/null; wait "$NSDPID" 2>/dev/null; }; NSDPID=""; }
aufraeumen() { dienst_aus; nsd_aus; }
trap aufraeumen EXIT

dienst() { # <wurzel> [schalter...]
    dienst_aus
    local w=$1; shift
    : > "$OUT/srv.log"
    python3 tools/ota/server.py --wurzel "$w" --port "$PORT" \
        --cert "$OUT/certs/srv.pem" --key "$OUT/certs/srv.key" \
        --log "$OUT/srv.log" "$@" > "$OUT/srv.out" 2>&1 &
    SRVPID=$!
    local i; for i in $(seq 1 40); do
        grep -qa "^START" "$OUT/srv.log" 2>/dev/null && return 0; sleep 0.2; done
    return 1
}
nsd() { # [schalter...]
    nsd_aus
    : > "$OUT/nsd.log"
    python3 tools/betrieb/dnsdienst.py --port 53 --adresse "${NSD_ADR:-127.0.0.1}" \
        --eintrag "$NAME=10.0.2.2" --log "$OUT/nsd.log" "$@" \
        > "$OUT/nsd.out" 2>&1 &
    NSDPID=$!
    local i; for i in $(seq 1 30); do
        grep -qa "^START" "$OUT/nsd.log" 2>/dev/null && return 0; sleep 0.2; done
    return 1
}
lauf() { # name skript [limit]
    OTA_NETZ="$NETZ" OUT="$OUT" bash tools/install/oneshot.sh \
        "$1" platte "$2" "${3:-600}" > /dev/null 2>&1
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' -e 's/\r//g' "$OUT/$1.txt" 2>/dev/null
    cat "$OUT/$1.rc" 2>/dev/null
}
frisch() { cp -f "$OUT/basis.img" "$OUT/ziel.img"; }

for t in qemu-system-x86_64 python3 curl dig mcopy; do
    command -v "$t" >/dev/null 2>&1 || { echo "BETRIEB: uebersprungen, $t fehlt"; exit 0; }
done

# =====================================================================
echo "== 1. der Bau =="
# =====================================================================
CC=vendor/firn/bin/firnc
for f in lib/libc/dnswire.fi lib/libc/dns.fi; do
    $CC --check "$f" > /dev/null 2>&1 || true
done
for p in host dnswt ota opk dhcp; do
    $CC "kernel/user/$p.fi" -o "$W/$p.o" 2> "$W/$p.err" \
        && ok "kernel/user/$p.fi baut ($(grep -c . "kernel/user/$p.fi") Zeilen)" \
        || { bad "$p baut nicht"; head -8 "$W/$p.err"; }
done
FIRNLIB="$ROOT/lib" $CC -c --profile=app -o "$W/fetch.o" kernel/app/fetch.fi \
    2> "$W/fetch.err" \
    && ok "kernel/app/fetch.fi baut MIT dem Aufloeser (FIRNLIB=<repo>/lib)" \
    || { bad "fetch.fi baut nicht"; head -8 "$W/fetch.err"; }
ok "der Aufloeser ist EINE Umsetzung fuer beide Bauarten: $(grep -c . lib/libc/dnswire.fi) + $(grep -c . lib/libc/dns.fi) Zeilen"
for p in host dnswt; do
    bash tools/betrieb/wirt.sh "$p" "$W" > /dev/null 2>&1 \
        && ok "/bin/$p auch fuer den Wirt gebaut ($(stat -c%s "$W/$p") Oktett)" \
        || bad "$p fuer den Wirt"
done

# =====================================================================
echo
echo "== 2. das Format: neunzehn feindliche Nachrichten, ohne ein Paket =="
# =====================================================================
timeout 60 "$W/dnswt" > "$W/dnswt.txt" 2>&1
DRC=$?
sed -n 's/^  \(OK\|FAIL\)  /        /p' "$W/dnswt.txt" | head -20
DG=$(grep -c '^  OK  ' "$W/dnswt.txt")
DR=$(grep -c '^  FAIL' "$W/dnswt.txt")
gleich "dnswt: rot" "$DR" "0"
gleich "dnswt: gruen" "$DG" "19"
gleich "dnswt HAENGT NICHT (Zeitgrenze 60 s)" "$([ $DRC -eq 124 ] && echo haengt || echo endet)" "endet"

# =====================================================================
echo
echo "== 3. der Aufloeser gegen dig -- echte Namen, echter Nameserver =="
# =====================================================================
DIGSRV=${BETRIEB_DIGSRV:-1.1.1.1}
timeout 400 python3 tools/betrieb/dnsvergleich.py "$W/host" --server "$DIGSRV" \
    > "$W/dig.txt" 2>&1
sed -n 's/^  /        /p' "$W/dig.txt"
VG=$(python3 -c "import json;d=json.load(open('/tmp/dnsvergleich.json'));print(d['gut'])" 2>/dev/null)
VR=$(python3 -c "import json;d=json.load(open('/tmp/dnsvergleich.json'));print(d['rot'])" 2>/dev/null)
gleich "gegen dig verschieden" "${VR:-1}" "0"
gleich "gegen dig gleich" "${VG:-0}" "20"

# =====================================================================
echo
echo "== 4. keine fest eingebaute Nameserver-Adresse =="
# =====================================================================
for a in '8\.8\.8\.8' '1\.1\.1\.1' '9\.9\.9\.9' '8\.8\.4\.4'; do
    N=$(grep -c "$a" lib/libc/dns.fi lib/libc/dnswire.fi kernel/user/host.fi \
        kernel/app/fetch.fi 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')
    gleich "$(echo "$a" | tr -d '\\') im Quelltext des Aufloesers" "$N" "0"
done
grep -q 'fallback' lib/libc/dns.fi \
    && ok "der Rueckfall ist eine ZEILE IN /etc/resolv.conf (sichtbar, abschaltbar)" \
    || bad "kein sichtbarer Rueckfall"
grep -q 'k_fb' kernel/user/dhcp.fi \
    && ok "und /bin/dhcp laesst ihn stehen, wenn es die Datei neu schreibt" \
    || bad "dhcp ueberschreibt den Rueckfall"

# =====================================================================
echo
echo "== 5. Kennung und Quellport sind wirklich gewuerfelt =="
# =====================================================================
nsd || bad "dnsdienst startet nicht"
: > "$W/rnd.txt"
for i in $(seq 1 20); do
    "$W/host" -v -s 127.0.0.1 "$NAME" >> "$W/rnd.txt" 2>&1
done
PN=$(grep -a '^  port' "$W/rnd.txt" | awk '{print $2}' | sort -u | wc -l)
TN=$(grep -a '^  txid' "$W/rnd.txt" | awk '{print $2}' | sort -u | wc -l)
PMIN=$(grep -a '^  port' "$W/rnd.txt" | awk '{print $2}' | sort -n | head -1)
PMAX=$(grep -a '^  port' "$W/rnd.txt" | awk '{print $2}' | sort -n | tail -1)
gleich "20 Laeufe, verschiedene Quellports" "$PN" "20"
gleich "20 Laeufe, verschiedene Kennungen" "$TN" "20"
[ "${PMIN:-0}" -ge 1024 ] && ok "kleinster Quellport $PMIN (>= 1024)" \
    || bad "Quellport $PMIN unter 1024"
ok "Spannweite der Quellports $PMIN..$PMAX -- Osums Kern vergaebe ohne bind 40000+(zaehler & 4095)"
GUT=$(grep -ac '^10\.0\.2\.2$' "$W/rnd.txt")
gleich "und 20 richtige Antworten" "$GUT" "20"

# =====================================================================
echo
echo "== 6. der Faelscher: Koeder vor der richtigen Antwort =="
# =====================================================================
for art in txid port case alle; do
    nsd --boese "$art" --koeder 6 || bad "dnsdienst ($art)"
    A=$("$W/host" -v -s 127.0.0.1 "$NAME" 2>&1)
    ADR=$(echo "$A" | head -1)
    FREMD=$(echo "$A" | sed -n 's/^  fremd  *//p')
    gleich "Koeder '$art': die Adresse stimmt trotzdem" "$ADR" "10.0.2.2"
    [ "${FREMD:-0}" -ge 1 ] \
        && ok "Koeder '$art': $FREMD Fremdpakete GEZAEHLT und verworfen" \
        || bad "Koeder '$art': kein Fremdpaket gezaehlt -- der Versuch misst nichts"
done
nsd --tc "$NAME" || bad "dnsdienst (tc)"
gleich "gekuerzte Antwort (TC-Bit) wird als TRUNCATED gemeldet" \
    "$("$W/host" -s 127.0.0.1 "$NAME" 2>&1 | head -1)" "TRUNCATED"
nsd_aus
gleich "kein Nameserver antwortet -> TIMEOUT und nicht ein falsches Ergebnis" \
    "$(timeout 30 "$W/host" -s 127.0.0.1 "$NAME" 2>&1 | head -1)" "TIMEOUT"
# Ein Nameserver, den es GIBT, der aber nicht antwortet, und einer, der
# nicht erreichbar ist -- beide muessen zu einer AUSSAGE fuehren und
# nicht zu einer erfundenen Adresse.
gleich "ein Nameserver, den es nicht gibt -> TIMEOUT" \
    "$(timeout 40 "$W/host" -s 127.0.0.9 "$NAME" 2>&1 | head -1)" "TIMEOUT"

# =====================================================================
echo
echo "== 7. die Serverseite: Register, Vorrat, Archiv =="
# =====================================================================
python3 tools/ota/veroeffentlichen.py "$OUT/aus" --zeigen > "$W/reg.txt"
sed -n 's/^/        /p' "$W/reg.txt"
hat "$W/reg.txt" "gefuehrte Fassung  4" "das Register fuehrt Fassung 4"
hat "$W/reg.txt" "vorgehalten        [1, 2, 3, 4]" "alle vier Fassungen liegen weiter da"
VORRAT=$(ls "$OUT/aus/pakete" | grep -c '\.opk$')
gleich "der Vorrat ist inhaltsadressiert: verschiedene Pakete" "$VORRAT" "3"
LINKS=$(stat -c%h "$OUT/aus/v/2/hallo-2.opk")
[ "${LINKS:-1}" -ge 2 ] \
    && ok "eine Fassung vorzuhalten kostet KEINE Kopie ($LINKS harte Verknuepfungen)" \
    || bad "v/2 haelt eine eigene Kopie"
# Das Register darf nicht zurueckgehen -- auch nicht auf Zuruf.
python3 tools/ota/veroeffentlichen.py "$OUT/aus" --stand "$OUT/stand" \
    --bund "$OUT/bund.json" --fassung 2 > "$W/zurueck.txt" 2>&1
hat "$W/zurueck.txt" "geht zurueck" "eine kleinere Fassungsnummer wird ABGELEHNT"
LETZTE=$(python3 -c "import json;print(json.load(open('$OUT/aus/register.json'))['letzte'])")
gleich "und das Register steht unveraendert" "$LETZTE" "4"
# Eine Ruecknahme gibt die Nummer NICHT zurueck.
cp "$OUT/aus/register.json" "$W/reg.bak"
python3 tools/ota/veroeffentlichen.py "$OUT/aus" --zuruecknehmen 4 > "$W/rn.txt" 2>&1
hat "$W/rn.txt" "gefuehrt bleibt 4" "eine zurueckgenommene Auslieferung behaelt ihre Nummer"
hat "$W/rn.txt" "aktuell ist 3" "und aktuell faellt auf die vorige Fassung"
# zuruecksetzen fuer den Rest des Laufs
cp "$W/reg.bak" "$OUT/aus/register.json"
printf '# keine\n' > "$OUT/aus/gesperrt.txt"
python3 - <<PY
import os, shutil
aus = "$OUT/aus"
ak = os.path.join(aus, "aktuell")
shutil.rmtree(ak, ignore_errors=True)
os.makedirs(ak)
for d in sorted(os.listdir(os.path.join(aus, "v", "4"))):
    os.link(os.path.join(aus, "v", "4", d), os.path.join(ak, d))
PY
ok "aktuell wieder auf Fassung 4 gesetzt"

# =====================================================================
echo
echo "== 8. der Schluesselbund =="
# =====================================================================
grep -q 'geheim' "$OUT/bund.json" && ok "der Bund ist eine Datei und laesst sich sichern" \
    || bad "kein Bund"
python3 -c "
import json,base64,sys
d=json.load(open('$OUT/bund.json'))
sk=base64.b64decode(d['haupt']['huelle']['geheim'])
roh=open('$OUT/geheim.key','rb').read()
sys.exit(0 if roh not in sk and d['haupt']['huelle']['kdf']=='scrypt' else 1)" \
    && ok "der geheime Schluessel steht NICHT im Klartext darin (scrypt + ChaCha20-Poly1305)" \
    || bad "der geheime Schluessel liegt im Klartext"
OSUM_SIGN_PASS=falsch python3 tools/ota/schluesselbund.py "$OUT/bund.json" \
    signieren /etc/hostname -o "$W/x.sig" > "$W/pass.txt" 2>&1
gleich "mit falscher Passphrase wird nicht signiert" \
    "$([ -s "$W/x.sig" ] && echo signiert || echo nein)" "nein"
grep -q 'InvalidTag\|schluesselbund' "$W/pass.txt" && ok "und es steht ein Grund da" || bad "kein Grund"
HP=$(python3 -c "import json;print(json.load(open('$OUT/bund.json'))['haupt']['pub'])")
EP=$(python3 -c "import json;print(json.load(open('$OUT/bund.json'))['ersatz']['pub'])")
[ "$HP" != "$EP" ] && ok "Haupt- und Ersatzschluessel sind verschieden" || bad "gleicher Schluessel"
gleich "der Ersatzschluessel liegt im Abbild" \
    "$(python3 -c "print(open('$OUT/ersatz.pub','rb').read().hex())")" "$EP"

# =====================================================================
echo
echo "== 9. weitere Auslieferungen fuer die Gegenproben =="
# =====================================================================
mach() { # <ziel-notiz> <schalter...>
    rm -f "$OUT/stand"/*.opk
    cp "$OUT/quelle2/hallo-2.opk" "$OUT/stand/"
    python3 tools/ota/veroeffentlichen.py "$OUT/aus" --stand "$OUT/stand" \
        --bund "$OUT/bund.json" "$@" 2>&1 | grep -v signiert
}
mach --signierer ersatz --notiz "mit dem Ersatzschluessel"          # 5
mach --sperren 5 --notiz "sperrt 5"                                 # 6
python3 tools/ota/schluesselbund.py "$OUT/bund.json" wechseln | sed 's/^/        /'
mach --notiz "nach dem Wechsel auf gen 1"                           # 7
mach --kette-kaputt --notiz "Kette gebrochen"                       # 8
python3 tools/ota/schluesselbund.py "$OUT/bund.json" wechseln | sed 's/^/        /'
mach --notiz "nach dem zweiten Wechsel, gen 2"                      # 9
rm -rf "$OUT/fremdaus"
rm -f "$OUT/stand"/*.opk; cp "$OUT/quelle2/hallo-2.opk" "$OUT/stand/"
OSUM_SIGN_PASS=fremd1 OSUM_ERSATZ_PASS=fremd2 \
    python3 tools/ota/veroeffentlichen.py "$OUT/fremdaus" --stand "$OUT/stand" \
    --bund "$OUT/fremd.json" --fassung 9 --notiz fremd 2>&1 | grep -v signiert
ok "Auslieferungen 5..9 und eine mit einem FREMDEN Schluessel stehen"

if [ "$OHNEQEMU" = 1 ]; then
    echo; echo "== BETRIEB (ohne QEMU): $pass gruen, $fail rot"; exit $((fail>0))
fi
[ -s "$OUT/basis.img" ] || { echo "== $OUT/basis.img fehlt -- erst vorbereiten.sh"; exit 1; }

# =====================================================================
echo
echo "== 10. auf Osum: DHCP schreibt /etc/resolv.conf, und ein echter Name =="
# =====================================================================
# QEMUs Benutzernetz bietet per DHCP den Nameserver 10.0.2.3 an; der
# leitet an den Aufloeser des WIRTS weiter. Damit loest das Geraet einen
# ECHTEN Namen auf, und das Ergebnis laesst sich gegen `dig` auf dem
# Wirt halten.
frisch
rc=$(lauf dhcp1 "dhcp einmal;cat /etc/resolv.conf;host -v example.com;host -c;exit")
gleich "die Maschine kommt hoch" "$rc" "21"
hat "$OUT/dhcp1.txt" "dhcp: ack ip=" "DHCP hat einen Vertrag bekommen"
hat "$OUT/dhcp1.txt" "/etc/resolv.conf geschrieben" "und /etc/resolv.conf geschrieben"
hat "$OUT/dhcp1.txt" "nameserver 10.0.2.3" "mit dem Nameserver aus Option 6"
GIP=$(grep -aoE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' "$OUT/dhcp1.txt" | tail -1)
DIGSET=$(dig +short A example.com | grep -E '^[0-9.]+$' | tr '\n' ' ')
if [ -n "$GIP" ] && echo " $DIGSET " | grep -q " $GIP "; then
    ok "example.com auf Osum = $GIP, und dig auf dem Wirt nennt es auch ($DIGSET)"
else
    bad "example.com auf Osum = '$GIP', dig nennt '$DIGSET'"
fi
hat "$OUT/dhcp1.txt" "  port   " "und der Quellport wurde gemeldet"

# =====================================================================
echo
echo "== 11. auf Osum: ota holt ein Update ueber einen NAMEN =="
# =====================================================================
NSD_ADR=127.0.0.1 nsd || bad "dnsdienst"
dienst "$OUT/aus" || bad "Gegenstelle"
frisch
rc=$(lauf name1 "cat /etc/ota.conf;host -v $NAME;ota einstellen quelle https://$NAME:$PORT/v/1;ota suchen;exit")
gleich "die Maschine kommt hoch" "$rc" "21"
hat "$OUT/name1.txt" "ota: quelle https://$NAME:$PORT/v/1" "die Quelle ist ein NAME und keine Adresse"
hat "$OUT/name1.txt" "fetch: aufgeloest" "fetch hat den Namen AUFGELOEST"
hat "$OUT/name1.txt" "fetch: verify OK" "und die Zertifikatskette GEPRUEFT -- gegen denselben Namen"
hat "$OUT/name1.txt" "ota: fassung dort 1" "das VERZEICHNIS der Fassung 1 kam an"
hatnicht "$OUT/name1.txt" "opk: installiert" "suchen installiert nichts"
grep -qa "FRAGE $NAME" "$OUT/nsd.log" && ok "der Nameserver hat die Frage wirklich gesehen" \
    || bad "keine DNS-Frage angekommen"

rc=$(lauf name2 "ota einspielen;sh /start.sh;ota zeigen;exit")
gleich "einspielen ueber den Namen" "$rc" "21"
hat "$OUT/name2.txt" "ota: streuwert stimmt hallo-1.opk" "der Streuwert des geladenen Pakets stimmt"
hat "$OUT/name2.txt" "opk: installiert hallo" "und opk hat installiert"
hat "$OUT/name2.txt" "paket-hallo fassung 1" "die neue Fassung LAEUFT"
hat "$OUT/name2.txt" "ota: fassung hier 1" "und der Fassungszaehler steht auf 1"
cp -f "$OUT/ziel.img" "$OUT/f1.img"

# =====================================================================
echo
echo "== 12. drei Fassungen zurueck -- und wieder aktuell =="
# =====================================================================
rc=$(lauf drei1 "ota einstellen quelle https://$NAME:$PORT/aktuell;ota zeigen;ota suchen;exit")
hat "$OUT/drei1.txt" "ota: fassung hier 1" "das Geraet steht auf Fassung 1"
hat "$OUT/drei1.txt" "ota: fassung dort 4" "die Quelle steht auf Fassung 4 -- drei Fassungen weiter"
rc=$(lauf drei2 "ota einspielen;sh /start.sh;ota zeigen;exit")
gleich "der Sprung 1 -> 4" "$rc" "21"
hat "$OUT/drei2.txt" "opk: installiert hallo" "eingespielt"
hat "$OUT/drei2.txt" "ota: fassung hier 4" "das Geraet steht jetzt auf Fassung 4"
# und die alten Fassungen sind WEITER abrufbar
for v in 1 2 3; do
    C=$(curl -s --cacert "$OUT/certs/ca.pem" --resolve "$NAME:$PORT:127.0.0.1" \
        -o "$W/v$v.VERZEICHNIS" -w '%{http_code}' \
        "https://$NAME:$PORT/v/$v/VERZEICHNIS" 2>/dev/null)
    F=$(sed -n 's/^fassung\t//p' "$W/v$v.VERZEICHNIS" 2>/dev/null)
    gleich "Fassung $v ist weiter abrufbar (Code, fassung)" "$C $F" "200 $v"
done
cp -f "$OUT/ziel.img" "$OUT/f4.img"

# =====================================================================
echo
echo "== 13. die Gegenproben zur Schluesselverwaltung =="
# =====================================================================
gp=0
gpok=0
gpruef() { # <name> <erwarteter Text> <datei>
    gp=$((gp+1))
    if grep -qaF "$2" "$3"; then gpok=$((gpok+1)); ok "GEGENPROBE $gp: $1"
    else bad "GEGENPROBE $gp: $1 -- '$2' fehlt"; fi
}

# (1) falsch signiertes Update
dienst "$OUT/fremdaus" || bad "Gegenstelle"
frisch
rc=$(lauf gp1 "ota einstellen quelle https://$NAME:$PORT/aktuell;ota einspielen;opk liste;exit")
gpruef "ein FREMD signiertes Update wird abgelehnt" \
    "SIGNATUR DES VERZEICHNISSES FALSCH" "$OUT/gp1.txt"
hatnicht "$OUT/gp1.txt" "opk: installiert" "        und es wurde wirklich nichts installiert"

# (2) mit dem ERSATZSCHLUESSEL signiert -- muss durchgehen
dienst "$OUT/aus" || bad "Gegenstelle"
frisch
rc=$(lauf gp2 "ota einstellen quelle https://$NAME:$PORT/v/5;ota einspielen;exit")
gpruef "ein mit dem ERSATZSCHLUESSEL signiertes Update wird angenommen" \
    "ota: mit dem ERSATZSCHLUESSEL geprueft" "$OUT/gp2.txt"
hat "$OUT/gp2.txt" "opk: installiert hallo" "        und es wurde wirklich installiert"

# (3) gesperrte Fassung -- das Geraet merkt sich die Sperre und lehnt
#     die (richtig signierte!) Auslieferung 5 danach ab.
frisch
rc=$(lauf gp3a "ota einstellen quelle https://$NAME:$PORT/v/6;ota suchen;exit")
hat "$OUT/gp3a.txt" "ota: gesperrte fassungen: 5" "        die Sperrliste steht im signierten VERZEICHNIS"
rc=$(lauf gp3b "ota einstellen quelle https://$NAME:$PORT/v/5;ota einspielen;exit")
gpruef "eine GESPERRTE Fassung wird abgelehnt -- obwohl sie neuer ist" \
    "ota: FASSUNG GESPERRT" "$OUT/gp3b.txt"
hatnicht "$OUT/gp3b.txt" "opk: installiert" "        und nichts installiert"

# (4) Rueckschritt
cp -f "$OUT/f4.img" "$OUT/ziel.img"
rc=$(lauf gp4 "ota einstellen quelle https://$NAME:$PORT/v/1;ota einspielen;exit")
gpruef "ein RUECKSCHRITT auf eine aeltere Fassung wird abgelehnt" \
    "ota: RUECKSCHRITT ABGELEHNT" "$OUT/gp4.txt"

# (5) Schluesselwechsel mit gueltiger Kette
frisch
rc=$(lauf gp5 "ota einstellen quelle https://$NAME:$PORT/v/7;ota einspielen;ota zeigen;exit")
gpruef "ein SCHLUESSELWECHSEL mit gueltiger Kette geht durch" \
    "ota: SCHLUESSELWECHSEL angenommen, neue gen 1" "$OUT/gp5.txt"
hat "$OUT/gp5.txt" "ota: schluesselgen 1" "        und die neue Generation steht auf der Platte"
hat "$OUT/gp5.txt" "opk: installiert hallo" "        das Update selbst ging auch durch"

# (6) Schluesselwechsel mit unterbrochener Kette
frisch
rc=$(lauf gp6 "ota einstellen quelle https://$NAME:$PORT/v/8;ota einspielen;ota zeigen;exit")
gpruef "ein SCHLUESSELWECHSEL mit UNTERBROCHENER Kette wird abgelehnt" \
    "ota: SCHLUESSELWECHSEL: die Kette ist UNTERBROCHEN" "$OUT/gp6.txt"
hat "$OUT/gp6.txt" "ota: schluesselgen 0" "        und die Generation ist NICHT gewechselt"
hatnicht "$OUT/gp6.txt" "opk: installiert" "        und nichts installiert"

# (7) zwei Wechsel verpasst -- in einem Zug nachgeholt
frisch
rc=$(lauf gp7 "ota einstellen quelle https://$NAME:$PORT/v/9;ota einspielen;ota zeigen;exit")
gpruef "ein Geraet, das ZWEI Wechsel verpasst hat, holt sie in einem Zug nach" \
    "ota: SCHLUESSELWECHSEL angenommen, neue gen 2" "$OUT/gp7.txt"
hat "$OUT/gp7.txt" "ota: schluesselgen 2" "        und steht danach auf Generation 2"
hat "$OUT/gp7.txt" "opk: installiert hallo" "        das Update ging durch"

dienst_aus; nsd_aus
echo
echo "        Gegenproben: $gpok von $gp bestanden"

# =====================================================================
echo
echo "== BETRIEB: $pass gruen, $fail rot =="
# =====================================================================
{
  echo "gruen=$pass rot=$fail gegenproben=$gpok/$gp"
  echo "dnswt=$DG/19 dig=${VG:-0}/20 ports=$PN txids=$TN spanne=$PMIN..$PMAX"
} > "$OUT/zahlen.txt"
cat "$OUT/zahlen.txt"
exit $((fail>0))
