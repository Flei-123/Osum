#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/../lib/brand-env.sh"
#
#   bash tools/operation/store.sh [ausgabeverzeichnis]
#
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${1:-/tmp/m5-store}
. "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/tools/lib/lock.sh" && osum_sperre "$OUT"   # A-024
mkdir -p "$OUT"
export OUT
export OSUM_CPU=${OSUM_CPU:-max}
export OSUM_SIGN_PASS=${OSUM_SIGN_PASS:-merge5-haupt-4711}
export OSUM_ERSATZ_PASS=${OSUM_ERSATZ_PASS:-merge5-ersatz-0815}

NAME=${STORE_NAME:-store.fleitec.com}
BASIS_URL=${STORE_URL:-https://$NAME/osum}
STORE_DIR=${STORE_DIR:-/srv/store}
STORE_REPO=${STORE_REPO:-/root/orientstore}
NETZ="nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0"

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
hat() { grep -qaF "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 -- '$2' fehlt"; }
hatnicht() { grep -qaF "$2" "$1" 2>/dev/null && bad "$3 -- '$2' steht da" || ok "$3"; }
gleich() { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', erwartet '$3'"; fi; }

for t in qemu-system-x86_64 python3 curl dig; do
    command -v "$t" >/dev/null 2>&1 || { echo "STORE: uebersprungen, $t fehlt"; exit 0; }
done
curl -sS -o /dev/null --max-time 20 "https://$NAME/index.json" 2>/dev/null \
    || { echo "STORE: skipped, https://$NAME is not reachable"; exit 0; }

lauf() { # name skript [limit] [zusatzwoerter]
    cp -f "$OUT/basis.img" "$OUT/ziel.img"
    OTA_NETZ="$NETZ ${4:-}" OUT="$OUT" bash tools/install/oneshot.sh \
        "$1" platte "$2" "${3:-600}" > /dev/null 2>&1
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' -e 's/\r//g' "$OUT/$1.txt" 2>/dev/null
    cat "$OUT/$1.rc" 2>/dev/null
}

# =====================================================================
echo "== 1. the delivery: packages, key ring, two versions =="
# =====================================================================
bash vendor/firn/fetch-firnc.sh > "$OUT/firnc.log" 2>&1 || {
    bad "fetch-firnc.sh"; exit 1; }
bash tools/install/pakete.sh "$OUT" > "$OUT/pak1.log" 2>&1 \
    && ok "two signed versions of the sample package" \
    || { bad "install/pakete.sh"; tail -5 "$OUT/pak1.log"; exit 1; }

rm -f "$OUT/bund.json"
python3 tools/ota/keyring.py "$OUT/bund.json" anlegen \
    --aus "$OUT/geheim.key" > "$OUT/bund.log" 2>&1 \
    && python3 tools/ota/keyring.py "$OUT/bund.json" oeffentlich ersatz \
        -o "$OUT/ersatz.pub" >> "$OUT/bund.log" 2>&1 \
    && ok "Schluesselbund: Hauptschluessel verschluesselt, Ersatzschluessel daneben" \
    || { bad "keyring.py"; cat "$OUT/bund.log"; exit 1; }

rm -rf "$OUT/aus" "$OUT/stand"; mkdir -p "$OUT/stand"
for f in 1 2; do
    rm -f "$OUT/stand"/*.opk
    cp "$OUT/quelle$f/hallo-$f.opk" "$OUT/stand/"
    python3 tools/ota/publish.py "$OUT/aus" --stand "$OUT/stand" \
        --bund "$OUT/bund.json" --notiz "MERGE-5 hallo-$f" \
        >> "$OUT/veroeff.log" 2>&1 || bad "publish.py Fassung $f"
done
[ -s "$OUT/aus/aktuell/VERZEICHNIS" ] \
    && ok "the delivery is ready: $(head -1 "$OUT/aus/aktuell/VERZEICHNIS"), Fassung $(sed -n 2p "$OUT/aus/aktuell/VERZEICHNIS" | cut -f2)" \
    || { bad "kein VERZEICHNIS"; exit 1; }

# =====================================================================
echo "== 2. onto the real server, without removing anything there =="
# =====================================================================
if [ -d "$STORE_DIR" ] && [ -w "$STORE_DIR" ]; then
    mkdir -p "$STORE_DIR/osum/aktuell"
    cp -aL "$OUT/aus/pakete" "$OUT/aus/v" "$STORE_DIR/osum/" 2>/dev/null
    #
    find "$OUT/aus/aktuell" -maxdepth 1 -type f ! -name 'VERZEICHNIS*' \
        -exec cp -fL {} "$STORE_DIR/osum/aktuell/" \;
    cp -fL "$OUT/aus/aktuell/VERZEICHNIS"     "$STORE_DIR/osum/aktuell/"
    cp -fL "$OUT/aus/aktuell/VERZEICHNIS.sig" "$STORE_DIR/osum/aktuell/"
    cp -fL "$OUT/aus/register.json" "$OUT/aus/journal.txt" \
           "$OUT/aus/gesperrt.txt" "$STORE_DIR/osum/" 2>/dev/null
    N=$(find "$STORE_DIR/osum/aktuell" -maxdepth 1 -type f | wc -l)
    ok "the delivery is at $STORE_DIR/osum ($N files under aktuell/)"
    UNGL=0
    for q in "$OUT/aus/aktuell/"*; do
        cmp -s "$q" "$STORE_DIR/osum/aktuell/$(basename "$q")" || UNGL=$((UNGL+1))
    done
    gleich "und jede Datei dort ist die aus DIESEM Lauf (ungleiche)" "$UNGL" "0"
else
    ok "skipped: $STORE_DIR is not writable here (foreign host)"
fi

if [ -d "$STORE_REPO/bau/repo" ]; then
    cp -f "$STORE_REPO/bau/repo/index.json" "$OUT/kat-vorher.json" 2>/dev/null
    ( cd "$STORE_REPO" && python3 werkzeug/store --repo bau/repo add \
        "$OUT/pak/hallo-2.opk" \
        --beschreibung "Beispielpaket der Runde MERGE-5 (${MARKE_PRODUKT}/Osum)." \
        >> "$OUT/store.log" 2>&1 ) && NEUZUGANG=1 || NEUZUGANG=0
    ( cd "$STORE_REPO" && python3 werkzeug/store --repo bau/repo publish \
        "$STORE_DIR" >> "$OUT/store.log" 2>&1 ) \
        && ok "the catalog is published (store publish -> $STORE_DIR)" \
        || bad "store publish"
    SHA=$(sha256sum "$OUT/pak/hallo-2.opk" | cut -d' ' -f1)
    RV=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['revision'])" \
         "$OUT/kat-vorher.json" 2>/dev/null)
    RN=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['revision'])" \
         "$STORE_DIR/index.json" 2>/dev/null)
    if grep -qa "$SHA" "$STORE_DIR/index.json" 2>/dev/null; then
        if [ "${RV:-0}" != "${RN:-0}" ]; then
            ok "the version is NEWLY added -- catalog revision ${RV} -> ${RN}"
        else
            ok "the version was already in the catalog (revision ${RN} unchanged) -- add rewrote nothing"
        fi
    else
        bad "the version is not in the published catalog"
    fi
    python3 - "$STORE_DIR/index.json" "$OUT/kat-vorher.json" <<'PYEOF' \
        > "$OUT/katvergleich.txt" 2>&1
import json, sys, os
neu = json.load(open(sys.argv[1]))
if not os.path.exists(sys.argv[2]):
    print("KEINE VORHER-AUFNAHME"); raise SystemExit(0)
alt = json.load(open(sys.argv[2]))
fehlt = [k for k in alt["pakete"] if k not in neu["pakete"]]
kleiner = [k for k in alt["pakete"] if k in neu["pakete"]
           and len(neu["pakete"][k]["fassungen"]) < len(alt["pakete"][k]["fassungen"])]
print("entfernt=%d geschrumpft=%d rev=%s->%s"
      % (len(fehlt), len(kleiner), alt["revision"], neu["revision"]))
PYEOF
    if grep -qa "entfernt=0 geschrumpft=0" "$OUT/katvergleich.txt"; then
        ok "and nothing was lost: $(cat "$OUT/katvergleich.txt")"
    elif grep -qa "KEINE VORHER-AUFNAHME" "$OUT/katvergleich.txt"; then
        ok "(no earlier state to compare -- first run)"
    else
        bad "the catalog lost: $(cat "$OUT/katvergleich.txt")"
    fi
    ( cd "$STORE_REPO" && python3 werkzeug/store --repo bau/repo verify ) \
        > "$OUT/verify.log" 2>&1
    grep -qa "in Ordnung" "$OUT/verify.log" \
        && ok "and the catalog verifies itself afterwards (store verify)" \
        || { bad "store verify"; tail -5 "$OUT/verify.log"; }
fi

for f in VERZEICHNIS VERZEICHNIS.sig; do
    code=$(curl -sS -o "$OUT/netz-$f" -w '%{http_code}' --max-time 30 \
           "$BASIS_URL/aktuell/$f" 2>/dev/null)
    gleich "curl holt $f vom echten Server (HTTP)" "$code" "200"
done
cmp -s "$OUT/netz-VERZEICHNIS" "$OUT/aus/aktuell/VERZEICHNIS" \
    && ok "and it is byte for byte what was published" \
    || bad "the DIRECTORY from the server is a different one"

# =====================================================================
echo "== 3. the image: real roots, and a SOURCE WITH A NAME =="
# =====================================================================
python3 tools/hwnet/mkroots.py "$OUT/roots.pem" > "$OUT/roots.log" 2>&1 \
    && ok "root store from the host's Mozilla roots ($(stat -c%s "$OUT/roots.pem") Oktette, $(grep -c 'BEGIN CERT' "$OUT/roots.pem") Wurzeln)" \
    || bad "mkroots.py"
grep -qa 'ISRG Root X1' "$OUT/roots.log" || true

cat > "$OUT/ota.conf" <<EOF
source=$BASIS_URL/aktuell
abstand=3600
auto=nein
frist=15
EOF
ok "/etc/ota.conf holds a NAME and no address: $BASIS_URL/aktuell"
printf 'opk rebuild\nif /apps/hallo.osp/start\nthen\nota confirm\nfi\nopk trial\n' \
    > "$OUT/start.sh"
OTA_ROOTS="$OUT/roots.pem" OTA_CONF="$OUT/ota.conf" \
    EXTRA="/start.sh=$OUT/start.sh" OTA_ERSATZ="$OUT/ersatz.pub" ZIEL_MIB=96 \
    bash tools/install/build.sh "$OUT" > "$OUT/build.log" 2>&1 \
    && ok "Abbild gebaut ($(grep -a 'wurzeln' "$OUT/build.log" | tail -1 | tr -s ' '))" \
    || { bad "install/build.sh"; tail -20 "$OUT/build.log"; exit 1; }

rm -f "$OUT/ziel.img"
head -c $((96 * 1024 * 1024)) /dev/zero > "$OUT/ziel.img"
OUT="$OUT" bash tools/install/oneshot.sh inst iso \
    "install /dev/hda --ja;exit" 900 > /dev/null 2>&1
gleich "der Installer ist durchgelaufen" "$(cat "$OUT/inst.rc" 2>/dev/null)" "21"
grep -qa 'install: done' "$OUT/inst.txt" \
    && ok "and says so" || bad "'install: done' fehlt"
cp -f "$OUT/ziel.img" "$OUT/basis.img"

# =====================================================================
echo "== 4. THE RUN: DHCP -> name server -> name -> signed directory =="
# =====================================================================
rc=$(lauf s1 "dhcp;cat /etc/resolv.conf;host $NAME;ota search;exit" 420)
gleich "Beendigungscode" "$rc" "21"
hat "$OUT/s1.txt" "dhcp: /etc/resolv.conf geschrieben" \
    "DHCP-Option 6 gelesen und /etc/resolv.conf geschrieben (Runde BETRIEB)"
NS=$(grep -aoE '^nameserver [0-9.]+' "$OUT/s1.txt" | head -1 | awk '{print $2}')
[ -n "${NS:-}" ] && ok "der Nameserver kommt vom DHCP-Server: $NS" \
    || bad "no nameserver line in /etc/resolv.conf"

IP_OSUM=$(grep -aoE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' "$OUT/s1.txt" | head -1)
IP_DIG=$(dig +short "$NAME" A | grep -E '^[0-9.]+$' | head -1)
gleich "/bin/host loest $NAME auf, und dig sagt dasselbe" \
       "${IP_OSUM:-keine}" "${IP_DIG:-keine}"

hat "$OUT/s1.txt" "fetch: verify OK" "die Zertifikatskette wurde GEPRUEFT"
CERTS=$(grep -aoE 'fetch: certs [0-9]+' "$OUT/s1.txt" | head -1 | awk '{print $3}')
TIEFE=$(grep -aoE 'fetch: depth [0-9]+' "$OUT/s1.txt" | head -1 | awk '{print $3}')
if [ "${CERTS:-0}" -ge 3 ] 2>/dev/null; then
    ok "and it is a REAL chain: $CERTS certificates, depth $TIEFE"
else
    bad "only $CERTS certificates -- that is no real chain"
fi
hat "$OUT/s1.txt" "ota: version there 2" "das signierte VERZEICHNIS ist gelesen"
hat "$OUT/s1.txt" "ota: NEW VERSION available" "und es gibt etwas Neues"
hatnicht "$OUT/s1.txt" "ota: applying" "SUCHEN INSTALLIERT NICHTS"

# =====================================================================
echo "== 5. and really install, from this server =="
# =====================================================================
rc=$(lauf s2 "dhcp;ota apply;ota show;exit" 600)
gleich "Beendigungscode" "$rc" "21"
hat "$OUT/s2.txt" "ota: hash ok hallo-2.opk" \
    "der Streuwert des ueber das Netz geholten Pakets stimmt"
hat "$OUT/s2.txt" "opk: signature checked" \
    "opk prueft die Signatur ein ZWEITES Mal, mit eigenem Code"
hat "$OUT/s2.txt" "opk: installed hallo" "installiert"
hat "$OUT/s2.txt" "ota: READY FOR RESTART" "und der Neustart wird nur ANGEBOTEN"
hat "$OUT/s2.txt" "ota: version here 2" "der Fassungszaehler steht danach auf 2"

# =====================================================================
echo "== 6. THE CONTROL: the same run in the state BEFORE the AVX round =="
# =====================================================================
rc=$(lauf s3 "dhcp;ota search;exit" 420 "nofpu")
hat "$OUT/s3.txt" "fpu: mode=0" "mit nofpu ist die Vektoreinheit nicht freigeschaltet"
hat "$OUT/s3.txt" "fetch: aufgeloest" "der NAME wird trotzdem noch aufgeloest (das ist BETRIEB)"
hat "$OUT/s3.txt" "vector=6" \
    "GEGENPROBE: und dann stirbt /bin/fetch an einem #UD -- genau wie docs/OTA.md es vorhersagt"
hat "$OUT/s3.txt" "ota: cannot fetch: VERZEICHNIS" "ota bricht ehrlich ab"
gleich "und ota endet mit einem Fehler statt mit einem Erfolg" \
       "$(grep -aoE 'ota -> [0-9]+' "$OUT/s3.txt" | head -1 | awk '{print $3}')" "1"

echo
echo "STORE: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
