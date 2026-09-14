#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/operation/store.sh -- RUNDE MERGE-5: DIE UPDATE-KETTE GEGEN EINEN
# ECHTEN, OEFFENTLICH ERREICHBAREN AUSLIEFERUNGSPLATZ.
#
#   bash tools/operation/store.sh [ausgabeverzeichnis]
#
# WARUM ES DIESEN LAEUFER GIBT, und das ist der ganze Punkt:
#
# `docs/OTA.md` sagt in seinem eigenen Kopf: "ES GIBT KEINEN ECHTEN
# UPDATE-SERVER IM INTERNET, gegen den diese Runde messen koennte."
# `docs/RUNDE-BETRIEB.md` misst gegen `tools/ota/server.py` auf DEMSELBEN
# Wirt. Beides ist ehrlich aufgeschrieben, und beides laesst genau die
# Fragen offen, die erst ein fremder Server stellt:
#
#   1. Loest das Geraet einen NAMEN selbst auf -- mit einem Nameserver,
#      den ihm DHCP gegeben hat, und nicht mit einer Zeile, die jemand
#      von Hand hingeschrieben hat?
#   2. Haelt die Kettenpruefung gegen ein ECHTES Zertifikat? Die
#      Gegenstelle des Pruefstands legt eine Wurzel vor, die derselbe
#      Lauf zwei Minuten vorher selbst erzeugt hat -- eine Kette der
#      Laenge 1. Let's Encrypt liefert VIER Zertifikate und eine
#      Kettentiefe von 3, mit ECDSA P-256 und P-384 darin.
#   3. Traegt der Wurzelspeicher IM ABBILD die richtige Wurzel? Bis
#      hierher trug er die selbstgemachte.
#
# Seit dem 02.09.2026 gibt es diesen Platz: https://store.fleitec.com/
# (systemd-Dienst `orientstore`, statische Dateien aus /srv/store,
# Zertifikat von Let's Encrypt). Dieser Laeufer legt dort eine
# Auslieferung ab und laesst ein Osum in QEMU sie ueber ihren NAMEN
# holen.
#
# DIESER LAEUFER IST ABSICHTLICH NICHT IN test.sh ANGEMELDET.
# Er schreibt auf einen echten Server und braucht das offene Internet;
# eine Abnahme, die ohne fremde Infrastruktur nicht gruen werden kann,
# ist keine Abnahme. Was hier gemessen wird, steht mit Zahlen in
# docs/RUNDE-MERGE5.md, Abschnitt 4.
#
# WAS ER AM STORE AENDERT: er legt EINE Auslieferung unter /srv/store/osum
# ab und nimmt EINE Fassung in den Katalog auf (`werkzeug/store add`).
# Er entfernt nichts, er baut nichts um, und `store verify` laeuft
# danach durch.
#
# ---------------------------------------------------------------------
# DIE GEGENPROBE, UND SIE IST DER GRUND, WARUM DIE RUNDE AVX DAZUGEHOERT
#
# Derselbe Lauf wird zweimal gefahren, mit demselben Abbild, demselben
# Namen und demselben Server -- einmal normal und einmal mit dem
# Kernwort `nofpu`, also GENAU im Zustand vor der Runde AVX. Dann muss
# `/bin/fetch` mit `user fault: vector=6` sterben und `ota` mit
# "nicht zu holen: VERZEICHNIS" aufhoeren. Ohne diese zweite Haelfte
# waere "es geht" eine Beobachtung und kein Nachweis.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${1:-/tmp/m5-store}
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
    || { echo "STORE: uebersprungen, https://$NAME ist nicht erreichbar"; exit 0; }

lauf() { # name skript [limit] [zusatzwoerter]
    cp -f "$OUT/basis.img" "$OUT/ziel.img"
    OTA_NETZ="$NETZ ${4:-}" OUT="$OUT" bash tools/install/oneshot.sh \
        "$1" platte "$2" "${3:-600}" > /dev/null 2>&1
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' -e 's/\r//g' "$OUT/$1.txt" 2>/dev/null
    cat "$OUT/$1.rc" 2>/dev/null
}

# =====================================================================
echo "== 1. die Auslieferung: Pakete, Schluesselbund, zwei Fassungen =="
# =====================================================================
bash vendor/firn/fetch-firnc.sh > "$OUT/firnc.log" 2>&1 || {
    bad "fetch-firnc.sh"; exit 1; }
bash tools/install/pakete.sh "$OUT" > "$OUT/pak1.log" 2>&1 \
    && ok "zwei signierte Fassungen des Beispielpakets" \
    || { bad "install/pakete.sh"; tail -5 "$OUT/pak1.log"; exit 1; }

rm -f "$OUT/bund.json"
python3 tools/ota/schluesselbund.py "$OUT/bund.json" anlegen \
    --aus "$OUT/geheim.key" > "$OUT/bund.log" 2>&1 \
    && python3 tools/ota/schluesselbund.py "$OUT/bund.json" oeffentlich ersatz \
        -o "$OUT/ersatz.pub" >> "$OUT/bund.log" 2>&1 \
    && ok "Schluesselbund: Hauptschluessel verschluesselt, Ersatzschluessel daneben" \
    || { bad "schluesselbund.py"; cat "$OUT/bund.log"; exit 1; }

rm -rf "$OUT/aus" "$OUT/stand"; mkdir -p "$OUT/stand"
for f in 1 2; do
    rm -f "$OUT/stand"/*.opk
    cp "$OUT/quelle$f/hallo-$f.opk" "$OUT/stand/"
    python3 tools/ota/veroeffentlichen.py "$OUT/aus" --stand "$OUT/stand" \
        --bund "$OUT/bund.json" --notiz "MERGE-5 hallo-$f" \
        >> "$OUT/veroeff.log" 2>&1 || bad "veroeffentlichen.py Fassung $f"
done
[ -s "$OUT/aus/aktuell/VERZEICHNIS" ] \
    && ok "die Auslieferung steht: $(head -1 "$OUT/aus/aktuell/VERZEICHNIS"), Fassung $(sed -n 2p "$OUT/aus/aktuell/VERZEICHNIS" | cut -f2)" \
    || { bad "kein VERZEICHNIS"; exit 1; }

# =====================================================================
echo "== 2. auf den echten Server, ohne dort etwas wegzunehmen =="
# =====================================================================
if [ -d "$STORE_DIR" ] && [ -w "$STORE_DIR" ]; then
    # DIE REIHENFOLGE IST NICHT EGAL: erst die Nutzlast, dann das
    # VERZEICHNIS, zuletzt die Signatur -- sonst zeigt fuer die Dauer
    # der Uebertragung ein gueltig signiertes Verzeichnis auf Dateien,
    # die es noch nicht gibt.
    mkdir -p "$STORE_DIR/osum/aktuell"
    cp -aL "$OUT/aus/pakete" "$OUT/aus/v" "$STORE_DIR/osum/" 2>/dev/null
    # HIER STAND EINMAL EINE MUSTERLISTE (`for f in hallo-*.opk ...`), UND
    # SIE HAT DIE RUNDE EINEN LAUF GEKOSTET. Die Muster werden im
    # ARBEITSVERZEICHNIS aufgeloest und nicht in `$OUT/aus/aktuell` --
    # sie trafen also nichts, und das Paket samt seiner Signatur blieb
    # liegen. Auf dem Server stand danach ein VERZEICHNIS aus DIESEM
    # Lauf neben einer Paketsignatur aus dem VORIGEN, mit einem anderen
    # Schluessel. Das Geraet hat das gemerkt und abgelehnt:
    #
    #     opk: SIGNATUR FALSCH -- das Paket wird ABGELEHNT
    #     ota: opk hat nicht installiert, Code 1
    #
    # Also genau das richtige Verhalten -- der Fehler lag hier. Jetzt
    # wird ueber die WIRKLICH VORHANDENEN Dateien gegangen, und in der
    # Reihenfolge, die eine Auslieferung braucht: erst die Nutzlast und
    # alles Beiwerk, dann das VERZEICHNIS, ganz zuletzt seine Signatur.
    # Wer die Signatur vor der Nutzlast hochlaedt, hat fuer die Dauer
    # der Uebertragung eine gueltig signierte Zusage auf Dateien, die es
    # noch nicht gibt.
    find "$OUT/aus/aktuell" -maxdepth 1 -type f ! -name 'VERZEICHNIS*' \
        -exec cp -fL {} "$STORE_DIR/osum/aktuell/" \;
    cp -fL "$OUT/aus/aktuell/VERZEICHNIS"     "$STORE_DIR/osum/aktuell/"
    cp -fL "$OUT/aus/aktuell/VERZEICHNIS.sig" "$STORE_DIR/osum/aktuell/"
    cp -fL "$OUT/aus/register.json" "$OUT/aus/journal.txt" \
           "$OUT/aus/gesperrt.txt" "$STORE_DIR/osum/" 2>/dev/null
    N=$(find "$STORE_DIR/osum/aktuell" -maxdepth 1 -type f | wc -l)
    ok "die Auslieferung liegt unter $STORE_DIR/osum ($N Dateien unter aktuell/)"
    # UND SIE IST IN SICH STIMMIG. Eine Auslieferung, in der eine Datei
    # aus einem anderen Lauf stehengeblieben ist, ist keine.
    UNGL=0
    for q in "$OUT/aus/aktuell/"*; do
        cmp -s "$q" "$STORE_DIR/osum/aktuell/$(basename "$q")" || UNGL=$((UNGL+1))
    done
    gleich "und jede Datei dort ist die aus DIESEM Lauf (ungleiche)" "$UNGL" "0"
else
    ok "uebersprungen: $STORE_DIR ist hier nicht beschreibbar (fremder Wirt)"
fi

# Und die Fassung in den KATALOG des Speichers -- das ist der Weg, den
# ein Mensch geht, und er ist ein Befehl.
if [ -d "$STORE_REPO/bau/repo" ]; then
    cp -f "$STORE_REPO/bau/repo/index.json" "$OUT/kat-vorher.json" 2>/dev/null
    # `add` ist reines HINZUFUEGEN. Steht die Fassung schon im Katalog
    # (weil dieser Laeufer schon einmal lief), sagt das Werkzeug nein --
    # und das ist richtig so; ein zweiter Lauf darf einen Katalog nicht
    # umschreiben. Dann wird nur nachgesehen, dass sie WIRKLICH dasteht.
    ( cd "$STORE_REPO" && python3 werkzeug/store --repo bau/repo add \
        "$OUT/pak/hallo-2.opk" \
        --beschreibung "Beispielpaket der Runde MERGE-5 (OrientOS/Osum)." \
        >> "$OUT/store.log" 2>&1 ) && NEUZUGANG=1 || NEUZUGANG=0
    ( cd "$STORE_REPO" && python3 werkzeug/store --repo bau/repo publish \
        "$STORE_DIR" >> "$OUT/store.log" 2>&1 ) \
        && ok "der Katalog ist veroeffentlicht (store publish -> $STORE_DIR)" \
        || bad "store publish"
    # OB SIE NEU IST, WIRD AN DER REVISION ABGELESEN UND NICHT AM
    # BEENDIGUNGSCODE VON `add`. `add` sagt auch dann Ja, wenn es nichts
    # zu tun gab (dieselbe Datei, dieselbe Fassung, gleicher Streuwert)
    # -- der Katalog wird dann NICHT neu geschrieben und die Revision
    # bleibt stehen. Das ist richtiges Verhalten und darf hier nicht als
    # "neu aufgenommen" gemeldet werden.
    SHA=$(sha256sum "$OUT/pak/hallo-2.opk" | cut -d' ' -f1)
    RV=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['revision'])" \
         "$OUT/kat-vorher.json" 2>/dev/null)
    RN=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['revision'])" \
         "$STORE_DIR/index.json" 2>/dev/null)
    if grep -qa "$SHA" "$STORE_DIR/index.json" 2>/dev/null; then
        if [ "${RV:-0}" != "${RN:-0}" ]; then
            ok "die Fassung ist NEU aufgenommen -- Katalogrevision ${RV} -> ${RN}"
        else
            ok "die Fassung stand schon im Katalog (Revision ${RN} unveraendert) -- add hat nichts umgeschrieben"
        fi
    else
        bad "die Fassung steht nicht im veroeffentlichten Katalog"
    fi
    # UND NICHTS IST WEGGEKOMMEN. Der Katalog zaehlt vorher wie nachher
    # dieselben Pakete, und die Fassungszahlen sind nicht kleiner.
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
        ok "und nichts ist weggekommen: $(cat "$OUT/katvergleich.txt")"
    elif grep -qa "KEINE VORHER-AUFNAHME" "$OUT/katvergleich.txt"; then
        ok "(kein Vorher-Stand zum Vergleichen -- erster Lauf)"
    else
        bad "der Katalog hat verloren: $(cat "$OUT/katvergleich.txt")"
    fi
    ( cd "$STORE_REPO" && python3 werkzeug/store --repo bau/repo verify ) \
        > "$OUT/verify.log" 2>&1
    grep -qa "in Ordnung" "$OUT/verify.log" \
        && ok "und der Katalog prueft sich danach selbst durch (store verify)" \
        || { bad "store verify"; tail -5 "$OUT/verify.log"; }
fi

# Vom offenen Netz aus, mit einem fremden Werkzeug (curl), damit die
# Aussage nicht von diesem Repo abhaengt.
for f in VERZEICHNIS VERZEICHNIS.sig; do
    code=$(curl -sS -o "$OUT/netz-$f" -w '%{http_code}' --max-time 30 \
           "$BASIS_URL/aktuell/$f" 2>/dev/null)
    gleich "curl holt $f vom echten Server (HTTP)" "$code" "200"
done
cmp -s "$OUT/netz-VERZEICHNIS" "$OUT/aus/aktuell/VERZEICHNIS" \
    && ok "und es ist Oktett fuer Oktett das, was veroeffentlicht wurde" \
    || bad "das VERZEICHNIS vom Server ist ein anderes"

# =====================================================================
echo "== 3. das Abbild: echte Wurzeln, und eine QUELLE MIT NAMEN =="
# =====================================================================
python3 tools/hwnet/mkroots.py "$OUT/roots.pem" > "$OUT/roots.log" 2>&1 \
    && ok "Wurzelspeicher aus den Mozilla-Wurzeln des Wirts ($(stat -c%s "$OUT/roots.pem") Oktette, $(grep -c 'BEGIN CERT' "$OUT/roots.pem") Wurzeln)" \
    || bad "mkroots.py"
grep -qa 'ISRG Root X1' "$OUT/roots.log" || true

cat > "$OUT/ota.conf" <<EOF
quelle=$BASIS_URL/aktuell
abstand=3600
auto=nein
frist=15
EOF
ok "in /etc/ota.conf steht ein NAME und keine Adresse: $BASIS_URL/aktuell"
printf 'opk richten\nif /apps/hallo.osp/start\nthen\nota bestaetigen\nfi\nopk erprobung\n' \
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
grep -qa 'install: fertig' "$OUT/inst.txt" \
    && ok "und sagt es auch" || bad "'install: fertig' fehlt"
cp -f "$OUT/ziel.img" "$OUT/basis.img"

# =====================================================================
echo "== 4. DER LAUF: DHCP -> Nameserver -> Name -> signiertes Verzeichnis =="
# =====================================================================
rc=$(lauf s1 "dhcp;cat /etc/resolv.conf;host $NAME;ota suchen;exit" 420)
gleich "Beendigungscode" "$rc" "21"
hat "$OUT/s1.txt" "dhcp: /etc/resolv.conf geschrieben" \
    "DHCP-Option 6 gelesen und /etc/resolv.conf geschrieben (Runde BETRIEB)"
NS=$(grep -aoE '^nameserver [0-9.]+' "$OUT/s1.txt" | head -1 | awk '{print $2}')
[ -n "${NS:-}" ] && ok "der Nameserver kommt vom DHCP-Server: $NS" \
    || bad "keine nameserver-Zeile in /etc/resolv.conf"

# Der Name, aufgeloest VON OSUM -- und daneben derselbe Name, aufgeloest
# von `dig` auf dem Wirt. Zwei Aufloeser, eine Antwort, sonst ist es
# keine Messung.
IP_OSUM=$(grep -aoE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' "$OUT/s1.txt" | head -1)
IP_DIG=$(dig +short "$NAME" A | grep -E '^[0-9.]+$' | head -1)
gleich "/bin/host loest $NAME auf, und dig sagt dasselbe" \
       "${IP_OSUM:-keine}" "${IP_DIG:-keine}"

hat "$OUT/s1.txt" "fetch: verify OK" "die Zertifikatskette wurde GEPRUEFT"
CERTS=$(grep -aoE 'fetch: certs [0-9]+' "$OUT/s1.txt" | head -1 | awk '{print $3}')
TIEFE=$(grep -aoE 'fetch: depth [0-9]+' "$OUT/s1.txt" | head -1 | awk '{print $3}')
if [ "${CERTS:-0}" -ge 3 ] 2>/dev/null; then
    ok "und es ist eine ECHTE Kette: $CERTS Zertifikate, Tiefe $TIEFE"
else
    bad "nur $CERTS Zertifikate -- das ist keine echte Kette"
fi
hat "$OUT/s1.txt" "ota: fassung dort 2" "das signierte VERZEICHNIS ist gelesen"
hat "$OUT/s1.txt" "ota: NEUE FASSUNG verfügbar" "und es gibt etwas Neues"
hatnicht "$OUT/s1.txt" "ota: einspielen" "SUCHEN INSTALLIERT NICHTS"

# =====================================================================
echo "== 5. und wirklich einspielen, von diesem Server =="
# =====================================================================
rc=$(lauf s2 "dhcp;ota einspielen;ota zeigen;exit" 600)
gleich "Beendigungscode" "$rc" "21"
hat "$OUT/s2.txt" "ota: streuwert stimmt hallo-2.opk" \
    "der Streuwert des ueber das Netz geholten Pakets stimmt"
hat "$OUT/s2.txt" "opk: Signatur geprüft" \
    "opk prueft die Signatur ein ZWEITES Mal, mit eigenem Code"
hat "$OUT/s2.txt" "opk: installiert hallo" "installiert"
hat "$OUT/s2.txt" "ota: BEREIT ZUM NEUSTART" "und der Neustart wird nur ANGEBOTEN"
hat "$OUT/s2.txt" "ota: fassung hier 2" "der Fassungszaehler steht danach auf 2"

# =====================================================================
echo "== 6. DIE GEGENPROBE: derselbe Lauf im Zustand VOR der Runde AVX =="
# =====================================================================
rc=$(lauf s3 "dhcp;ota suchen;exit" 420 "nofpu")
hat "$OUT/s3.txt" "fpu: mode=0" "mit nofpu ist die Vektoreinheit nicht freigeschaltet"
hat "$OUT/s3.txt" "fetch: aufgeloest" "der NAME wird trotzdem noch aufgeloest (das ist BETRIEB)"
hat "$OUT/s3.txt" "vector=6" \
    "GEGENPROBE: und dann stirbt /bin/fetch an einem #UD -- genau wie docs/OTA.md es vorhersagt"
hat "$OUT/s3.txt" "ota: nicht zu holen: VERZEICHNIS" "ota bricht ehrlich ab"
gleich "und ota endet mit einem Fehler statt mit einem Erfolg" \
       "$(grep -aoE 'ota -> [0-9]+' "$OUT/s3.txt" | head -1 | awk '{print $3}')" "1"

echo
echo "STORE: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
