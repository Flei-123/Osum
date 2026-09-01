#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/ota/run.sh -- RUNDE OTA: EIN UPDATE, DAS DAS GERAET SICH SELBST
# UEBER DAS NETZ HOLT -- UND DIE SECHS ARTEN, AUF DIE ES SCHIEFGEHEN
# DARF, OHNE DASS ETWAS KAPUTTGEHT.
#
# GEGEN WAS GEMESSEN WIRD, und das steht hier und nicht im Kleingedruckten:
# ES GIBT KEINEN ECHTEN UPDATE-SERVER IM INTERNET. Gemessen wird gegen
# `tools/ota/server.py` -- einen HTTPS-Dienst auf DEMSELBEN WIRT, mit
# echtem TLS 1.3 aus Pythons `ssl` (also OpenSSL, nicht dieses
# Repository), einem echten Zertifikat mit echter Kette, echtem
# `Content-Length`, echtem `Range`/`206` und echten Verbindungsabbruechen.
# Das Geraet spricht darueber eine echte e1000 und QEMUs Benutzernetz an,
# in dem 10.0.2.2 der Wirt ist. Was daran fehlt, um "im Internet" zu
# heissen, steht am Ende von `docs/OTA.md`.
#
# DIE ABSCHNITTE:
#
#   1. DER BAU. `/bin/ota` (profile kernel) und `/bin/fetch`
#      (--profile=app, die volle Firn-Bibliothek mit TLS 1.3) -- und ein
#      Abbild, in dem BEIDE liegen. Bis zu dieser Runde lag `fetch` in
#      keinem Abbild; `docs/UPDATE.md` nannte das als ersten Punkt seiner
#      Fehlliste.
#
#   2. DER GUTE WEG, ENDE ZU ENDE. Ein Geraet mit Fassung 1 sucht,
#      findet Fassung 2, holt sie, prueft sie, spielt sie ein, startet
#      neu, laeuft und bestaetigt. MIT MESSUNGEN: Oktette, Dauer,
#      Platzbedarf.
#
#   3. DIE ABLEHNUNGEN. Sechs Faelle, und nach jedem wird nachgesehen,
#      dass WIRKLICH NICHTS geschrieben wurde:
#        (a) falsch signiertes Paket
#        (a2) falsch signiertes VERZEICHNIS
#        (g) richtig signiertes VERZEICHNIS mit veraendertem Streuwert
#        (b) eine AELTERE Fassung -- der Rueckschrittsschutz
#        (c) mitten im Laden abgebrochen, danach wiederaufgenommen
#        (f) die Platte ist voll
#
#   4. (d) DAS UPDATE, DAS NICHT HOCHKOMMT. Zehn volle Durchlaeufe:
#      einspielen, neu starten, es kommt nicht hoch, der Kern faellt von
#      selbst zurueck, die Maschine laeuft wieder. Zehnmal, weil einmal
#      ein Zufall ist.
#
#   5. (e) DER STROMAUSFALL. Dreissigmal QEMU mit SIGKILL abgeschossen,
#      an dreissig verschiedenen Stellen des Einspielens. Danach muss die
#      Maschine JEDESMAL hochkommen und ENTWEDER die alte ODER die neue
#      Fassung haben -- nie etwas dazwischen.
#
# Verwendung:  bash tools/ota/run.sh [--kurz]
#   --kurz  drei statt zehn Rueckfaelle und zehn statt dreissig Schuesse.
#           Zum Iterieren waehrend der Arbeit; die Zahlen im Bericht
#           kommen aus dem VOLLEN Lauf.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
. tools/lib/qemu.sh

# WELCHER PROZESSOR -- UND WARUM NICHT `max`.
#
# GEMESSEN IN DIESER RUNDE, mit demselben `/bin/fetch` und demselben
# Kern, nur mit anderem `-cpu`:
#
#     qemu64        laeuft      SSE2
#     Nehalem       laeuft      SSE4.2
#     Westmere      laeuft      + AES-NI
#     SandyBridge   laeuft      + AVX
#     Haswell       laeuft      + AVX2, BMI2
#     max           #UD         + AVX-512, SHA-NI und alles Weitere
#
# Unter `-cpu max` stirbt `/bin/fetch` mit
# `user fault: vector=6 (#UD)` mitten im TLS-Aufbau. Die Ursache liegt
# NICHT in dieser Runde und nicht in `fetch`: Osum schaltet fuer Ring 3
# weder `CR4.OSXSAVE` noch `XCR0` frei, und der Kontextwechsel sichert
# keine Vektorregister. Firns Bibliothek fragt `cpuid` und nimmt den
# breitesten Weg, den die Maschine anbietet -- und der ist dann einer,
# den dieser Kern nicht tragen kann.
#
# Gemessen wird deshalb mit `Haswell`: ein echtes Prozessormodell, kein
# Notbehelf, und alles, was dieser Kern kann, ist darin an. DASS ES EINE
# GRENZE GIBT, WIRD NICHT VERSCHWIEGEN -- sie steht in `docs/OTA.md` in
# der Fehlliste, weil ein Rechner mit AVX-512 auf dem Tisch steht und
# nicht in QEMU.
export OSUM_CPU=${OSUM_CPU:-Haswell}
OUT=${OUT:-/tmp/ota-run}
mkdir -p "$OUT" .probe
export OUT
PORT=${OTA_PORT:-$(( 18000 + ($$ % 900) ))}
NETZ="nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0"
KURZ=${1:-}
RUNDEN=10
SCHUESSE=30
if [ "$KURZ" = "--kurz" ]; then RUNDEN=3; SCHUESSE=10; fi
if [ "$KURZ" = "--probe" ]; then RUNDEN=1; SCHUESSE=2; fi

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
gleich() { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', erwartet '$3'"; fi; }
hat() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hatnicht() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da und sollte nicht" || ok "$3"; }
zahl() { local n=$1 v=$2 o=$3 w=$4
    if [ -z "${v:-}" ]; then bad "$n: keine Zahl (erwartet $o $w)"; return; fi
    if [ "$v" -"$o" "$w" ] 2>/dev/null; then ok "$n: $v"; else bad "$n: $v, erwartet $o $w"; fi
}

SRVPID=""
dienst_aus() {
    if [ -n "$SRVPID" ]; then kill "$SRVPID" 2>/dev/null; wait "$SRVPID" 2>/dev/null; fi
    SRVPID=""
}
dienst() { # <wurzel> [weitere Schalter...]
    dienst_aus
    local w=$1; shift
    python3 tools/ota/server.py --wurzel "$w" --port "$PORT" \
        --cert "$OUT/certs/srv.pem" --key "$OUT/certs/srv.key" \
        --log "$OUT/srv.log" "$@" > "$OUT/srv.out" 2>&1 &
    SRVPID=$!
    local i
    for i in $(seq 1 40); do
        grep -qa "^START" "$OUT/srv.log" 2>/dev/null && return 0
        sleep 0.2
    done
    return 1
}
aufraeumen() { dienst_aus; }
trap aufraeumen EXIT

# Ein Lauf von der PLATTE, ueber OVMF, mit Netz. Gibt den
# Beendigungscode zurueck.
lauf() { # name skript [limit]
    : > "$OUT/srv.log"
    OTA_NETZ="$NETZ" OUT="$OUT" bash tools/install/oneshot.sh \
        "$1" platte "$2" "${3:-600}" > /dev/null 2>&1
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' "$OUT/$1.txt" 2>/dev/null
    cat "$OUT/$1.rc" 2>/dev/null
}

for t in qemu-system-x86_64 python3 curl mcopy; do
    command -v "$t" >/dev/null 2>&1 || { echo "OTA: uebersprungen, $t fehlt"; exit 0; }
done
python3 -c 'import cryptography' 2>/dev/null || {
    echo "OTA: uebersprungen, python3-cryptography fehlt"; exit 0; }

# =====================================================================
echo "== 1. der Bau: /bin/ota, /bin/fetch und ein Abbild, in dem beide liegen =="
# =====================================================================
bash vendor/firn/fetch-firnc.sh > "$OUT/firnc.log" 2>&1 \
    && ok "der festgenagelte Uebersetzer ($(cat vendor/firn/COMMIT | cut -c1-8))" \
    || { bad "fetch-firnc.sh"; tail -5 "$OUT/firnc.log"; }

vendor/firn/bin/firnc kernel/user/ota.fi -o "$OUT/ota-probe.o" \
    2> "$OUT/ota-cc.log" \
    && ok "kernel/user/ota.fi baut ($(grep -c . kernel/user/ota.fi) Zeilen, profile kernel, keine Halde)" \
    || { bad "ota.fi baut nicht"; head -20 "$OUT/ota-cc.log"; }

FIRNLIB="$ROOT/vendor/firn/lib" vendor/firn/bin/firnc -c --profile=app \
    -o "$OUT/fetch-probe.o" kernel/app/fetch.fi 2> "$OUT/fetch-cc.log" \
    && ok "kernel/app/fetch.fi baut mit Range/Wiederaufnahme ($(grep -c . kernel/app/fetch.fi) Zeilen)" \
    || { bad "fetch.fi baut nicht"; head -20 "$OUT/fetch-cc.log"; }

# Die Pakete und die Quellen.
bash tools/install/pakete.sh "$OUT" > "$OUT/pak1.log" 2>&1 \
    && ok "zwei signierte Quellen (Fassung 1 und 2)" \
    || { cat "$OUT/pak1.log"; bad "install/pakete.sh"; }
bash tools/update/pakete.sh "$OUT" > "$OUT/pak2.log" 2>&1 \
    && ok "Fassung 3 -- sauber signiert und kommt NICHT hoch" \
    || { cat "$OUT/pak2.log"; bad "update/pakete.sh"; }
python3 tools/ota/mkcerts.py "$OUT/certs" ota.test 10.0.2.2 \
    > "$OUT/certs.log" 2>&1 \
    && ok "die Zertifikate, gemacht mit Pythons cryptography und nicht mit diesem Repo" \
    || { cat "$OUT/certs.log"; bad "mkcerts.py"; }
bash tools/ota/pakete.sh "$OUT" > "$OUT/pak3.log" 2>&1 \
    && ok "sechs Quellen fuers Netz: $(grep -c '^   netz' "$OUT/pak3.log") Stueck" \
    || { cat "$OUT/pak3.log"; bad "ota/pakete.sh"; }
grep -qa "VERZEICHNIS  fassung" "$OUT/pak3.log" \
    && ok "jede Signatur wurde von einer FREMDEN Umsetzung nachgeprueft (libsodium/cryptography)" \
    || bad "verzeichnis.py hat nicht signiert"
grep -qa "KEINE zweite Meinung" "$OUT/pak3.log" \
    && bad "es gab keine zweite Meinung zur Signatur -- pynacl/cryptography fehlt" \
    || ok "die zweite Meinung war wirklich da"

VZG=$(stat -c%s "$OUT/netz2/VERZEICHNIS")
PKG=$(stat -c%s "$OUT/netz2/hallo-2.opk")
ok "ein VERZEICHNIS ist $VZG Oktett, ein Paket $PKG"

# Die Gegenstelle steht und spricht TLS 1.3 -- gemessen mit curl, also
# mit einem Programm, das dieses Repository nicht geschrieben hat.
dienst "$OUT/netz2" && ok "die Gegenstelle laeuft auf 127.0.0.1:$PORT" \
    || bad "die Gegenstelle startet nicht"
CV=$(curl -s --cacert "$OUT/certs/ca.pem" --resolve "ota.test:$PORT:127.0.0.1" \
     -o /dev/null -w '%{http_code} %{ssl_verify_result}' \
     "https://ota.test:$PORT/VERZEICHNIS" 2>/dev/null)
gleich "curl gegen die Gegenstelle (Code, Kettenpruefung)" "$CV" "200 0"
CT=$(curl -s --cacert "$OUT/certs/ca.pem" --resolve "ota.test:$PORT:127.0.0.1" \
     -w '%{http_version}' -o /dev/null "https://ota.test:$PORT/VERZEICHNIS" 2>/dev/null)
CR=$(curl -s --cacert "$OUT/certs/ca.pem" --resolve "ota.test:$PORT:127.0.0.1" \
     -r 100- -o /dev/null -w '%{http_code}' "https://ota.test:$PORT/hallo-2.opk" 2>/dev/null)
gleich "die Gegenstelle kann Range (206)" "$CR" "206"
dienst_aus

# ---------------------------------------------------------- das Abbild
# WIEDERAUFNAHME DES LAEUFERS SELBST. Bau und Installation dauern auf
# einem belegten Wirt zwanzig Minuten; wer nur an den hinteren
# Abschnitten arbeitet, setzt $OTA_BASIS=1 und benutzt die Platte, die
# schon dasteht. FUER EINE MESSUNG, DIE BERICHTET WIRD, IST DAS NICHT
# GEDACHT -- dann wird gebaut, und der Laeufer sagt es auch.
WIEDER=0
if [ "${OTA_BASIS:-0}" = 1 ] && [ -s "$OUT/basis.img" ]; then
    WIEDER=1
    echo "  ----  \$OTA_BASIS=1: Bau und Installation UEBERSPRUNGEN, es wird"
    echo "        die vorhandene Platte benutzt. Nur zum Iterieren."
fi

cat > "$OUT/ota.conf" <<EOF
quelle=https://10.0.2.2:$PORT
name=ota.test
abstand=3600
auto=nein
frist=15
EOF
# DAS STARTSKRIPT. Es ist das, was ein ausgeliefertes System beim
# Hochfahren taete, und es steht als Datei auf der Platte, weil die
# Kommandozeile des Laders bei `;` trennt und ein `if` dort nie heil
# ankaeme:
#
#   opk richten                 die Sicht /apps aus der LAUFENDEN
#                               Generation neu bauen (nach einem
#                               Rueckfall zeigt sie sonst noch auf die
#                               Generation, die nicht hochkam)
#   if /apps/hallo.osp/start    das Paket starten
#   then ota bestaetigen        und NUR WENN ES LAEUFT bestaetigen
printf 'opk richten\nif /apps/hallo.osp/start\nthen\nota bestaetigen\nfi\nopk erprobung\n' \
    > "$OUT/start.sh"
EX="/start.sh=$OUT/start.sh"
if [ "$WIEDER" = 0 ]; then
OTA_ROOTS="$OUT/certs/ca.pem" OTA_CONF="$OUT/ota.conf" EXTRA="$EX" \
    ZIEL_MIB="${OTA_ZIEL_MIB:-96}" bash tools/install/build.sh "$OUT" > "$OUT/build.log" 2>&1 \
    && ok "das Abbild ($(grep -a 'apps ' "$OUT/build.log" | tr -s ' '))" \
    || { tail -20 "$OUT/build.log"; bad "build.sh"; }
grep -qa "wurzeln " "$OUT/build.log" && ok "der Wurzelspeicher liegt im Abbild" \
    || bad "kein Wurzelspeicher im Abbild"
fi
FSZ=$(stat -c%s "$OUT/bin/fetch")
OSZ=$(stat -c%s "$OUT/bin/ota")
ok "/bin/fetch $FSZ Oktett (TLS 1.3, X.509, RSA, ECDSA), /bin/ota $OSZ Oktett"

# ---------------------------------------------------- die leere Platte
#
# 96 MiB und nicht 256. Der Grund ist Rechenzeit und kein Geschmack: der
# Installer laesst das Dateisystem auf die GANZE Platte wachsen und
# schreibt sie dabei durch eine emulierte IDE-Schnittstelle, und dieser
# Laeufer legt danach ueber hundert Kopien der Platte an -- jeder der
# dreissig Schuesse und jeder der zehn Rueckfaelle faengt bei derselben
# Ausgangslage an. Bei 256 MiB sind das dreissig Gigaoktett Kopiererei
# fuer nichts. Gemessen wird an der Platte nichts, was von ihrer Groesse
# abhinge -- ausser Fall (f), und der will sie ohnehin VOLL haben.
ZIEL_MIB=${OTA_ZIEL_MIB:-96}
if [ "$WIEDER" = 0 ]; then
rm -f "$OUT/ziel.img"
head -c $((ZIEL_MIB * 1024 * 1024)) /dev/zero > "$OUT/ziel.img"
OUT="$OUT" bash tools/install/oneshot.sh inst iso "install /dev/hda --ja;exit" 900 \
    > /dev/null 2>&1
gleich "die Installation auf die leere Platte" "$(cat "$OUT/inst.rc")" "21"
hat "$OUT/inst.txt" "install: fertig" "der Installer meldet sich fertig"

# Fassung 1 einspielen und bestaetigen -- das ist der Ausgangszustand
# jedes weiteren Falls.
rc=$(lauf basis0 "opk installieren /quelle1/hallo-1.opk;sh /start.sh;df;exit")
hat "$OUT/basis0.txt" "paket-hallo fassung 1" "Ausgangslage: Fassung 1 laeuft"
hat "$OUT/basis0.txt" "opk: erprobung bestaetigt" "und ist bestaetigt"
cp -f "$OUT/ziel.img" "$OUT/basis.img"
fi
BASISBL=$(sed -n 's/.*blocks total=\([0-9]*\) free=\([0-9]*\).*/\1 \2/p' \
          "$OUT/basis0.txt" | tail -1)

# =====================================================================
echo
echo "== 2. der gute Weg, Ende zu Ende: suchen, holen, pruefen, einspielen =="
# =====================================================================
dienst "$OUT/netz2" || bad "Gegenstelle"
cp -f "$OUT/basis.img" "$OUT/ziel.img"
T0=$(date +%s%N)
rc=$(lauf gut1 "ota zeigen;ota suchen;exit")
T1=$(date +%s%N)
gleich "die Maschine kommt hoch" "$rc" "21"
hat "$OUT/gut1.txt" "ota: fassung hier 0" "vorher steht hier Fassung 0 (frisch installiert)"
hat "$OUT/gut1.txt" "fetch: verify OK" "die Kette des Servers wurde GEPRUEFT und nicht geglaubt"
hat "$OUT/gut1.txt" "ota: fassung dort 2" "die Quelle bietet Fassung 2"
hat "$OUT/gut1.txt" "ota: NEUE FASSUNG verfuegbar" "und das wird gemeldet"
hat "$OUT/gut1.txt" "ota: paket hallo 2.0.0" "mit Namen und Fassung des Pakets"
hatnicht "$OUT/gut1.txt" "opk: installiert" "SUCHEN INSTALLIERT NICHTS"
grep -qa "GET /VERZEICHNIS" "$OUT/srv.log" 2>/dev/null || true
SUCHMS=$(( (T1 - T0) / 1000000 ))

cp -f "$OUT/basis.img" "$OUT/ziel.img"
dienst "$OUT/netz2" || bad "Gegenstelle"
T0=$(date +%s%N)
rc=$(lauf gut2 "ota einspielen;opk erprobung;exit")
T1=$(date +%s%N)
EINMS=$(( (T1 - T0) / 1000000 ))
cp -f "$OUT/srv.log" "$OUT/srv-gut.log" 2>/dev/null || true
gleich "einspielen: die Maschine kommt hoch" "$rc" "21"
hat "$OUT/gut2.txt" "ota: streuwert stimmt hallo-2.opk" "der Streuwert des GELADENEN Pakets stimmt"
hat "$OUT/gut2.txt" "opk: Signatur geprueft" "opk prueft die Signatur ein ZWEITES Mal, mit eigenem Code"
hat "$OUT/gut2.txt" "opk: installiert hallo" "und installiert"
hat "$OUT/gut2.txt" "opk: in erprobung: 1 vor 0" "die neue Generation steht in ERPROBUNG, Rueckfall waere 0"
hat "$OUT/gut2.txt" "ota: BEREIT ZUM NEUSTART" "und der Neustart wird ANGEBOTEN"
hatnicht "$OUT/gut2.txt" "power: init sagt ab" "ES WIRD NICHT VON SELBST NEU GESTARTET"
OKT=$(grep -a "^ota: platz" "$OUT/gut2.txt" | tail -1 | awk '{print $3}')

rc=$(lauf gut3 "sh /start.sh;ota zeigen;df;exit")
gleich "der Neustart" "$rc" "21"
hat "$OUT/gut3.txt" "ab: gen=1 versuch=1 von 3" "der Kern zaehlt den Erprobungsversuch"
hat "$OUT/gut3.txt" "paket-hallo fassung 2" "DIE NEUE FASSUNG LAEUFT"
hat "$OUT/gut3.txt" "opk: erprobung bestaetigt" "und wird bestaetigt"
hat "$OUT/gut3.txt" "ota: fassung hier 2" "der Fassungszaehler steht jetzt auf 2"
GENBL=$(sed -n 's/.*blocks total=\([0-9]*\) free=\([0-9]*\).*/\2/p' "$OUT/gut3.txt" | tail -1)

rc=$(lauf gut4 "sh /start.sh;exit")
hat "$OUT/gut4.txt" "ab: gen=1 bestaetigt" "beim naechsten Start ist nichts mehr in Erprobung"
hat "$OUT/gut4.txt" "paket-hallo fassung 2" "und es bleibt bei der neuen Fassung"
cp -f "$OUT/ziel.img" "$OUT/nach2.img"
dienst_aus

# =====================================================================
echo
echo "== 3. die Ablehnungen -- und nach jeder wird nachgesehen =="
# =====================================================================
H1=$(python3 -c "print(open('$OUT/netz1/INDEX').read().split(chr(9))[2])" 2>/dev/null)
echo "        hallo 1.0.0 im Store = ${H1:0:16}"

# ---- (a) falsch signiertes PAKET. Das VERZEICHNIS stimmt, `ota` hat
#      nichts zu beanstanden -- und `opk` faengt es.
dienst "$OUT/netzbadsig" || bad "Gegenstelle"
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf a1 "ota einspielen;opk liste;opk generationen;exit")
hat "$OUT/a1.txt" "ota: streuwert stimmt" "(a) das VERZEICHNIS stimmt -- ota laesst es durch"
hat "$OUT/a1.txt" "SIGNATUR FALSCH" "(a) und opk faengt die falsche PAKETSIGNATUR"
hatnicht "$OUT/a1.txt" "opk: installiert" "(a) es wird NICHTS installiert"
hat "$OUT/a1.txt" "${H1:0:12}" "(a) die laufende Fassung ist unveraendert"
hatnicht "$OUT/a1.txt" "generation 1" "(a) es entsteht KEINE zweite Generation"
hat "$OUT/a1.txt" "ota: fassung hier 0" "(a) und der Fassungszaehler steht noch auf 0"
dienst_aus

# ---- (a2) falsch signiertes VERZEICHNIS. Hier faellt es frueher: bevor
#      auch nur die Fassungsnummer geglaubt wird.
dienst "$OUT/netzfremd" || bad "Gegenstelle"
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf a2 "ota einspielen;opk liste;opk generationen;ota zeigen;exit")
hat "$OUT/a2.txt" "SIGNATUR DES VERZEICHNISSES FALSCH" "(a2) ein fremd signiertes VERZEICHNIS wird abgelehnt"
hatnicht "$OUT/a2.txt" "ota: fassung dort" "(a2) und nicht einmal die Fassungsnummer daraus wird gelesen"
hatnicht "$OUT/a2.txt" "opk: installiert" "(a2) es wird nichts installiert"
hatnicht "$OUT/a2.txt" "generation 1" "(a2) es entsteht keine Generation"
dienst_aus

# ---- (g) richtig signiertes VERZEICHNIS, veraenderter Streuwert
dienst "$OUT/netzman" || bad "Gegenstelle"
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf g1 "ota einspielen;opk liste;opk generationen;exit")
hat "$OUT/g1.txt" "ota: fassung dort 2" "(g) die Signatur ueber das VERZEICHNIS ist GUELTIG"
hat "$OUT/g1.txt" "STREUWERT STIMMT NICHT" "(g) und trotzdem wird abgelehnt -- die Kette wird an JEDEM Glied geprueft"
hatnicht "$OUT/g1.txt" "opk: installiert" "(g) es wird nichts installiert"
hatnicht "$OUT/g1.txt" "generation 1" "(g) es entsteht keine Generation"
dienst_aus

# ---- (b) RUECKSCHRITT: eine aeltere Fassung, alles richtig signiert
dienst "$OUT/netz1" || bad "Gegenstelle"
cp -f "$OUT/nach2.img" "$OUT/ziel.img"
rc=$(lauf b1 "ota einspielen;opk liste;ota zeigen;exit")
hat "$OUT/b1.txt" "ota: fassung hier 2" "(b) auf dem Geraet steht Fassung 2"
hat "$OUT/b1.txt" "ota: fassung dort 1" "(b) angeboten wird Fassung 1 -- richtig signiert"
hat "$OUT/b1.txt" "RUECKSCHRITT ABGELEHNT" "(b) DER RUECKSCHRITTSSCHUTZ GREIFT"
hatnicht "$OUT/b1.txt" "opk: installiert" "(b) es wird nichts installiert"
hatnicht "$OUT/b1.txt" "ota: streuwert stimmt" "(b) es wird nicht einmal ein Paket geholt"
dienst_aus

# ---- (b2) DIE GEGENPROBE zu (b): dieselbe Quelle, dieselbe Signatur,
#      aber ein Geraet, das noch bei 0 steht -- dann muss sie DURCHgehen.
dienst "$OUT/netz1" || bad "Gegenstelle"
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf b2 "ota suchen;exit")
hat "$OUT/b2.txt" "ota: NEUE FASSUNG verfuegbar" "(b) GEGENPROBE: dieselbe Quelle wird angenommen, wenn hier 0 steht"
hatnicht "$OUT/b2.txt" "RUECKSCHRITT ABGELEHNT" "(b) der Schutz schlaegt also nicht immer zu"
dienst_aus

# ---- (c) mitten im Laden abgebrochen -- HART, mit RST
#
# WAS HIER GEMESSEN WIRD UND WAS NICHT. Ein RST mitten in einem
# TLS-Datensatz ist der haerteste Abbruch, den es gibt: die Gegenstelle
# verschwindet ohne `close_notify` und ohne FIN. Die Zusage lautet NICHT
# "das Programm meldet einen Fehler" -- sie lautet "AM SYSTEM AENDERT
# SICH NICHTS". Deshalb wird DANACH ein ZWEITER Lauf gemacht, der
# nachsieht: die Maschine kommt hoch, die alte Fassung laeuft, es gibt
# keine zweite Generation und der Fassungszaehler steht, wo er stand.
# Ein Nachsehen im ABGEBROCHENEN Lauf waere schwaecher -- der darf
# untergehen, das ist ja der Fall.
dienst "$OUT/netz2" --abbruch "hallo-2.opk:9000" || bad "Gegenstelle"
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf c1 "ota einspielen;exit")
grep -qa "ABBRUCH hallo-2.opk" "$OUT/srv.log" \
    && ok "(c) die Gegenstelle hat die Verbindung wirklich abgerissen (RST nach 9000 Oktett)" \
    || bad "(c) die Gegenstelle hat gar nicht abgebrochen"
hatnicht "$OUT/c1.txt" "opk: installiert" "(c) im abgebrochenen Lauf wird nichts installiert"
dienst_aus
rc=$(lauf c1b "opk richten;/apps/hallo.osp/start;opk liste;opk generationen;ota zeigen;exit")
gleich "(c) DANACH kommt die Maschine hoch" "$rc" "21"
hat "$OUT/c1b.txt" "paket-hallo fassung 1" "(c) und die alte Fassung laeuft"
hat "$OUT/c1b.txt" "${H1:0:12}" "(c) der Store nennt genau den alten Streuwert"
hatnicht "$OUT/c1b.txt" "generation 1" "(c) es entstand keine zweite Generation"
hat "$OUT/c1b.txt" "ota: fassung hier 0" "(c) der Fassungszaehler ist unveraendert"

# ---- (c2) DIE WIEDERAUFNAHME.
#
# Hier bricht die Gegenstelle MILDE ab (`--kurz`): sie schreibt 20000
# Oktett und schliesst ordentlich. Damit bleibt ein Bruchstueck auf der
# Platte liegen -- der Fall, in dem eine Wiederaufnahme ueberhaupt etwas
# spart. (Beim harten RST bleibt oft gar nichts liegen, weil ein RST die
# Empfangswarteschlange mitnimmt; das ist gemessen und steht in
# docs/OTA.md.) Der zweite Lauf MUSS eine 206 bekommen.
dienst "$OUT/netz2" --kurz "hallo-2.opk:20000" || bad "Gegenstelle"
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf c2a "ota einspielen;exit")
hatnicht "$OUT/c2a.txt" "opk: installiert" "(c) der erste Versuch scheitert"
grep -qa "^KURZ hallo-2.opk" "$OUT/srv.log" \
    && ok "(c) die Gegenstelle hat den Rumpf wirklich abgeschnitten" \
    || bad "(c) die Gegenstelle hat nicht abgeschnitten"
dienst_aus
dienst "$OUT/netz2" || bad "Gegenstelle"
rc=$(lauf c2b "ota einspielen;opk liste;exit")
hat "$OUT/c2b.txt" "ota: bruchstueck, weiter ab" "(c) der zweite Versuch findet das Bruchstueck und setzt dort an"
hat "$OUT/c2b.txt" "ota: streuwert stimmt hallo-2.opk" "(c) und bekommt das Paket vollstaendig"
hat "$OUT/c2b.txt" "opk: installiert hallo" "(c) es wird eingespielt"
grep -qa "^206 hallo-2.opk" "$OUT/srv.log" \
    && ok "(c) WIEDERAUFGENOMMEN: die Gegenstelle hat 206 Partial Content geliefert" \
    || bad "(c) keine 206 -- es wurde nicht wiederaufgenommen"
dienst_aus

# ---- (f) der Platz reicht nicht
#
# WIE DIE PLATTE ZU KLEIN WIRD, und warum nicht andersherum. Versucht
# wurde zuerst, sie von innen vollzuschreiben: `cat` mit sieben
# Argumenten, dreimal verkettet. GEMESSEN auf diesem Wirt unter Last:
# 4,6 Megaoktett in ueber vier Minuten, durch OFS mit Journal und
# emulierte IDE. Fuenfzig Megaoktett so zu schreiben dauert laenger als
# der ganze uebrige Lauf.
#
# Gemessen wird deshalb der andere Weg zur selben Stelle: ein UPDATE, das
# nicht hinpasst (ein Paket von zwanzig Megaoktett aus /dev/urandom,
# richtig signiert, mit richtigem Streuwert). Fuer den Code ist das
# derselbe Zweig -- `ota` fragt den Kern nach den freien Bloecken und
# haelt sie gegen den Bedarf; ob die Bloecke fehlen, weil die Platte voll
# ist oder weil das Paket gross ist, steht nirgends im Vergleich.
#
# UND DIE PRUEFUNG KOMMT VOR DEM LADEN. Die Laengen stehen im SIGNIERTEN
# Verzeichnis; ein Geraet an einer schmalen Leitung soll nicht erst
# zwanzig Megaoktett holen und dann erfahren, dass sie nicht hinpassen.
# Der Laeufer misst genau das: die Gegenstelle darf das Paket NICHT
# einmal ausgeliefert haben.
dienst "$OUT/netzvoll" || bad "Gegenstelle"
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf f1 "df;ota einspielen;opk liste;opk generationen;ota zeigen;exit" 900)
gleich "(f) die Maschine kommt hoch" "$rc" "21"
hat "$OUT/f1.txt" "ZU WENIG PLATZ" "(f) es reicht nicht, und ota bricht SAUBER ab"
hatnicht "$OUT/f1.txt" "opk: installiert" "(f) es wird nichts installiert"
hatnicht "$OUT/f1.txt" "generation 1" "(f) es entsteht keine Generation"
hat "$OUT/f1.txt" "${H1:0:12}" "(f) die laufende Fassung ist unveraendert"
hat "$OUT/f1.txt" "ota: fassung hier 0" "(f) der Fassungszaehler ist unveraendert"
grep -qa "gross-1.opk" "$OUT/srv.log" \
    && bad "(f) das Paket wurde geholt, obwohl der Platz vorher schon nicht reichte" \
    || ok "(f) und das Paket wurde NICHT EINMAL GEHOLT -- geprueft wurde vorher"
dienst_aus

# ---- (f) DIE GEGENPROBE: dieselbe Maschine, ein Update, das hinpasst.
dienst "$OUT/netz2" || bad "Gegenstelle"
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf f2 "ota einspielen;exit")
hat "$OUT/f2.txt" "opk: installiert hallo" "(f) GEGENPROBE: das kleine Update geht auf derselben Platte durch"
hatnicht "$OUT/f2.txt" "ZU WENIG PLATZ" "(f) der Platzwaechter schlaegt also nicht immer zu"
dienst_aus

# ---- die Einstellungsseite und das Umstellen im Betrieb
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf ein1 "ota einstellungen;ota einstellen abstand 900;ota einstellen auto ja;ota einstellungen;exit")
hat "$OUT/ein1.txt" "ota: die Einstellungen (/etc/ota.conf)" "die Einstellungsseite zeigt, wie das Geraet eingestellt ist"
hat "$OUT/ein1.txt" "quelle   https://10.0.2.2:$PORT" "mit der Quelle"
hat "$OUT/ein1.txt" "ota: gesetzt abstand ist jetzt 900" "und sie laesst sich umstellen"
hat "$OUT/ein1.txt" "abstand  900" "die neue Zahl steht danach wirklich da"
hat "$OUT/ein1.txt" "auto     ja" "und der Schalter fuer die automatische Suche auch"
rc=$(lauf ein2 "ota einstellen unsinn 5;ota dienst;exit" 200)
hat "$OUT/ein2.txt" "ota: das ist kein Schluessel" "ein unbekannter Schluessel wird abgelehnt"
hat "$OUT/ein2.txt" "ota: dienst, abstand 900" "und der Dienst nimmt den eingestellten Abstand"
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf ein3 "ota dienst;exit")
hat "$OUT/ein3.txt" "automatische Suche ist AUSgeschaltet" "GEGENPROBE: mit auto=nein sucht der Dienst gar nicht"

# =====================================================================
echo
echo "== 4. (d) das Update, das NICHT hochkommt -- $RUNDEN volle Durchlaeufe =="
# =====================================================================
#
# JEDER DURCHLAUF IST DER GANZE WEG: die Gegenstelle bietet Fassung 3 an
# (sauber signiert, installiert sich einwandfrei, und das Programm darin
# beendet sich mit Code 1). Das Geraet holt sie, spielt sie ein, startet
# neu -- und kommt nicht hoch. Drei Starts spaeter hat der Kern von
# selbst auf die alte Generation zurueckgeschaltet, und die Maschine
# laeuft wieder mit Fassung 1.
dgut=0
for r in $(seq 1 "$RUNDEN"); do
    dienst "$OUT/netz3" || bad "Gegenstelle"
    cp -f "$OUT/basis.img" "$OUT/ziel.img"
    rc=$(lauf "d$r-ein" "ota einspielen;exit")
    dienst_aus
    e1=$(grep -ca "opk: installiert hallo" "$OUT/d$r-ein.txt")
    rc=$(lauf "d$r-s1" "sh /start.sh;exit")
    rc=$(lauf "d$r-s2" "sh /start.sh;exit")
    T0=$(date +%s%N)
    rc3=$(lauf "d$r-s3" "sh /start.sh;exit")
    T1=$(date +%s%N)
    zurueck=$(grep -ca "ab: ERPROBUNG gescheitert, zurueck auf 0" "$OUT/d$r-s3.txt")
    alt=$(grep -ca "paket-hallo fassung 1" "$OUT/d$r-s3.txt")
    kaputt=$(grep -ca "SCHEITERT" "$OUT/d$r-s3.txt")
    if [ "$e1" -ge 1 ] && [ "$rc3" = 21 ] && [ "$zurueck" -ge 1 ] \
       && [ "$alt" -ge 1 ] && [ "$kaputt" = 0 ]; then
        dgut=$((dgut+1))
    else
        bad "(d) Durchlauf $r: eingespielt=$e1 rc=$rc3 zurueck=$zurueck alt=$alt kaputt=$kaputt"
    fi
    RUECKMS=$(( (T1 - T0) / 1000000 ))
done
zahl "(d) Durchlaeufe, in denen das Geraet sich SELBST gerettet hat" "$dgut" eq "$RUNDEN"

# DIE GEGENPROBE zu (d): dasselbe mit einem Update, das LAEUFT. Ohne sie
# waere "es faellt zurueck" auch dann gruen, wenn es IMMER zurueckfiele.
dienst "$OUT/netz2" || bad "Gegenstelle"
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf dgeg1 "ota einspielen;sh /start.sh;exit")
dienst_aus
hat "$OUT/dgeg1.txt" "paket-hallo fassung 2" "(d) GEGENPROBE: das gute Update laeuft"
rc=$(lauf dgeg2 "sh /start.sh;exit")
rc=$(lauf dgeg3 "sh /start.sh;exit")
rc=$(lauf dgeg4 "sh /start.sh;exit")
hat "$OUT/dgeg4.txt" "paket-hallo fassung 2" "(d) GEGENPROBE: auch nach vier Starts laeuft noch die NEUE Fassung"
hatnicht "$OUT/dgeg4.txt" "zurueck auf" "(d) GEGENPROBE: es wird NIE zurueckgefallen"

# ---- DER WACHHUND: eine Generation, die hochkommt und HAENGT
#
# Der Zaehler in `kernel/ab.fi` faengt, was nicht hochkommt -- aber nur,
# wenn die Maschine noch einmal startet. Eine Generation, die haengt,
# startet nie wieder von selbst. Das ist der Wachhund: er wartet die
# Frist ab und startet neu.
# Die Fassung 3 kommt aus dem NETZ und nicht von der Platte: `/quelle3`
# liegt gar nicht im Abbild -- im Abbild liegen nur `/quelle1` und
# `/quelle2` (tools/install/build.sh). Der Wachhund wird also an genau
# dem Weg gemessen, um den es in dieser Runde geht.
dienst "$OUT/netz3" || bad "Gegenstelle"
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf wach1 "ota einspielen;ota wachhund 5;exit" 300)
dienst_aus
hat "$OUT/wach1.txt" "opk: in erprobung" "der Wachhund: es steht etwas in Erprobung"
hat "$OUT/wach1.txt" "WACHHUND: keine Bestaetigung" "die Frist laeuft ab, ohne dass jemand bestaetigt"
hat "$OUT/wach1.txt" "WACHHUND: Neustart" "und der Wachhund startet die Maschine neu"
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf wach2 "ota wachhund 5;exit" 300)
hat "$OUT/wach2.txt" "ota: nichts in erprobung" "GEGENPROBE: ohne Erprobung tut der Wachhund NICHTS"
hatnicht "$OUT/wach2.txt" "WACHHUND: Neustart" "und startet vor allem nicht neu"

# =====================================================================
echo
echo "== 5. (e) der Stromausfall: $SCHUESSE Schuesse mitten ins Einspielen =="
# =====================================================================
#
# QEMU wird mit SIGKILL abgeschossen -- nicht `-no-reboot`, nicht ein
# Ausgang, sondern der Stecker.
#
# WO DIE SCHUESSE LIEGEN, UND WARUM DAS NICHT GERATEN WIRD: im ersten
# vollen Lauf standen sie fest zwischen 1 und 16 Sekunden, weil "so etwa
# zwanzig Sekunden" geschaetzt war. Gemessen (tools/ota/zeitprobe.sh,
# jede serielle Zeile gestempelt) faengt das Netz aber erst nach rund
# zehn Sekunden an und geschrieben wird erst kurz vor der
# sechsundzwanzigsten. Ergebnis: alle dreissig Schuesse trafen die
# Firmware, dreissig von dreissig endeten auf "alt", KEIN EINZIGER auf
# "neu" -- dreissig gruene Haken, die nichts belegten.
#
# Deshalb wird das Fenster JETZT GEMESSEN und nicht gesetzt: die Probe
# laeuft einmal sauber durch und liefert T_NETZ, T_LADEN, T_SCHREIB und
# T_FERTIG. Die eine Haelfte der Schuesse verteilt sich gleichmaessig
# ueber den ganzen Vorgang, die andere DICHT ueber die Schreibphase
# (vom gepruefsten Paket bis kurz hinter "bereit zum Neustart") -- genau
# dort, wo ein Stromausfall wehtun kann.
#
# DIE ZUSAGE: die Maschine kommt danach hoch, und sie hat ENTWEDER die
# alte ODER die neue Fassung. Nie etwas dazwischen, nie eine Generation
# ohne Store-Eintrag, nie ein halbes AKTUELL. UND: das Fenster muss
# BEIDE Seiten treffen -- kommt kein einziges "neu" heraus, ist der Test
# wertlos und faellt durch.
dienst "$OUT/netz2" || bad "Gegenstelle"
OUT="$OUT" bash tools/ota/zeitprobe.sh "$OUT/zeitmarken" > "$OUT/zeitprobe.log" 2>&1
dienst_aus
T_NETZ=0; T_LADEN=0; T_SCHREIB=0; T_FERTIG=0; T_ENDE=0
. "$OUT/zeitmarken" 2>/dev/null || true
zahl "(e) die Zeitprobe hat den ganzen Einspielvorgang gesehen" "$T_FERTIG" gt 0
echo "        gemessen: netz $T_NETZ ms, paket geprueft $T_LADEN ms, geschrieben $T_SCHREIB ms, bereit $T_FERTIG ms"
E_MAX=$(( T_ENDE + 1000 ))
[ "$E_MAX" -gt 2000 ] || E_MAX=27000
E_S0=$T_LADEN
[ "$E_S0" -gt 0 ] || E_S0=14000
E_S1=$T_SCHREIB
[ "$E_S1" -gt "$E_S0" ] || E_S1=$(( E_S0 + 9000 ))
# Das dritte Fenster liegt HINTER dem Umschalten. Es reicht bewusst ueber
# das Ende des gemessenen Laufs hinaus: der naechste Lauf ist nie exakt
# gleich schnell (gemessen 22,8 s und 25,8 s auf demselben Wirt), und ein
# Schuss, der zu frueh kommt, faellt einfach in die Schreibphase zurueck.
E_F=$T_FERTIG
[ "$E_F" -gt "$E_S1" ] || E_F=$(( E_S1 + 100 ))
# Grosszuegig hinter das Ende hinaus: derselbe Lauf brauchte auf diesem
# Wirt einmal 22,8 s und einmal 25,8 s. Ein Fenster, das nur knapp hinter
# der gemessenen Marke endet, faellt bei einem langsamen Lauf wieder in
# die Schreibphase zurueck -- und dann misst der Abschnitt wieder nichts.
E_S2=$(( T_ENDE + 6000 ))
[ "$E_S2" -gt "$E_F" ] || E_S2=$(( E_F + 6000 ))
alt_n=0
neu_n=0
tot_n=0
getroffen=0
verfehlt=0
i=0
while [ "$i" -lt "$SCHUESSE" ]; do
    i=$((i+1))
    dienst "$OUT/netz2" || bad "Gegenstelle"
    cp -f "$OUT/basis.img" "$OUT/ziel.img"
    # DER ZEITPUNKT KOMMT AUS DER MASCHINE, NICHT AUS DER UHR.
    # Der erste Anlauf hat die Schusszeiten aus einem Messlauf
    # hochgerechnet -- und auf einem belasteten Wirt lag der spaeteste
    # Schuss (27,2 s) noch vor dem Laden. Dreissig Mal "alt", kein
    # einziges "neu": nichts belegt. Jetzt wartet jeder Schuss auf eine
    # MARKE, die die Maschine selbst gedruckt hat, und zieht den Stecker
    # einen Versatz spaeter. Drei Phasen im Wechsel:
    #   1. das Netz steht, das Paket ist noch nicht geprueft
    #   2. das Paket ist geprueft -- jetzt wird geschrieben
    #   3. HINTER dem Umschalten: "bereit zum Neustart" steht schon da
    if [ $(( i % 3 )) = 1 ]; then
        MARKE="ota: quelle"; VERSATZ=$(( 100 + i * 60 )); PHASE=netz
    elif [ $(( i % 3 )) = 2 ]; then
        MARKE="ota: streuwert stimmt"; VERSATZ=$(( 50 + i * 120 )); PHASE=schreiben
    else
        MARKE="ota: BEREIT ZUM NEUSTART"; VERSATZ=$(( 20 + i * 10 )); PHASE=danach
    fi
    OVMF=$(ls /usr/share/OVMF/OVMF_CODE.fd /usr/share/ovmf/OVMF.fd 2>/dev/null | head -1)
    cp -f /usr/share/OVMF/OVMF_VARS.fd "$OUT/e.vars.fd" 2>/dev/null || true
    {
        echo "timeout: 0"; echo "verbose: yes"; echo
        echo "/OrientOS"; echo "    protocol: multiboot1"
        echo "    path: boot():/osum.mb"
        echo "    cmdline: osum vfs nokbd nosched noproc nofs noring3 $NETZ script=ota einspielen;exit"
    } > "$OUT/e.conf"
    mcopy -o -i "$OUT/ziel.img@@1048576" "$OUT/e.conf" ::/limine.conf 2>/dev/null
    : > "$OUT/e$i.txt"
    $QEMU_X86 -machine pc -cpu "$OSUM_CPU" -m 512 -display none -no-reboot \
        -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF" \
        -drive "if=pflash,format=raw,unit=1,file=$OUT/e.vars.fd" \
        -serial "file:$OUT/e$i.txt" \
        -drive "file=$OUT/ziel.img,format=raw,if=ide,index=0" \
        -netdev user,id=otan0 -device e1000,netdev=otan0,mac=52:54:00:0a:0b:0c \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1 &
    QP=$!
    # Auf die Marke der Maschine warten, Versatz abwarten, DANN DEN
    # STECKER ZIEHEN. Wird die Marke innerhalb der Frist nie gedruckt,
    # kehrt das Skript mit 3 zurueck: der Schuss zaehlt dann als
    # "Phase verfehlt" und wird unten offen ausgewiesen.
    if python3 tools/ota/warte_marke.py "$OUT/e$i.txt" "$MARKE" "$VERSATZ" 600; then
        getroffen=$((getroffen+1))
    else
        verfehlt=$((verfehlt+1))
        echo "        (e) Schuss $i: Marke '$MARKE' kam nicht innerhalb der Frist"
    fi
    kill -9 "$QP" 2>/dev/null
    wait "$QP" 2>/dev/null
    dienst_aus
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' "$OUT/e$i.txt" 2>/dev/null
    # ---- und jetzt: kommt sie hoch, und was hat sie?
    rc=$(lauf "en$i" "opk richten;/apps/hallo.osp/start;opk liste;exit" 400)
    if [ "$rc" != 21 ]; then
        tot_n=$((tot_n+1))
        bad "(e) Schuss $i in Phase $PHASE: die Maschine kommt NICHT mehr hoch (rc=$rc)"
    elif grep -qa "paket-hallo fassung 2" "$OUT/en$i.txt"; then
        neu_n=$((neu_n+1))
    elif grep -qa "paket-hallo fassung 1" "$OUT/en$i.txt"; then
        alt_n=$((alt_n+1))
    else
        tot_n=$((tot_n+1))
        bad "(e) Schuss $i in Phase $PHASE: WEDER die alte NOCH die neue Fassung laeuft"
    fi
done
zahl "(e) Schuesse, nach denen die Maschine ENTWEDER alt ODER neu ist" \
     "$((alt_n + neu_n))" eq "$SCHUESSE"
zahl "(e) davon: nichts dazwischen und kein Ziegelstein" "$tot_n" eq 0
# Der Test, der den Test prueft: ein Fenster, das nur die Firmware
# trifft, wuerde dreissig makellose "alt" liefern und nichts belegen.
zahl "(e) Schuesse, die WIRKLICH nach dem Umschalten lagen (sonst misst das nichts)" \
     "$neu_n" gt 0
zahl "(e) und Schuesse, die davor lagen" "$alt_n" gt 0
zahl "(e) Schuesse, die ihre Phase wirklich getroffen haben" "$getroffen" eq "$SCHUESSE"
echo "        alt=$alt_n  neu=$neu_n  kaputt=$tot_n  Phase getroffen=$getroffen verfehlt=$verfehlt"
echo "        (Schuesse an Marken der Maschine ausgerichtet: 'ota: quelle' / 'ota: streuwert stimmt' / 'ota: BEREIT ZUM NEUSTART')"

# =====================================================================
echo
echo "== 6. die Messungen =="
# =====================================================================
STORE=$(grep -a "blocks total=" "$OUT/gut3.txt" | tail -1)
printf '   %-52s %s\n' "ein VERZEICHNIS (signierter Katalog, 1 Paket)" "$VZG Oktett"
printf '   %-52s %s\n' "ein Paket (hallo 2.0.0, .opk)" "$PKG Oktett"
printf '   %-52s %s\n' "ein Update auf der Leitung (VERZEICHNIS+sig+INDEX+sig+opk+sig)" \
    "$(du -sb "$OUT/netz2" | cut -f1) Oktett"
printf '   %-52s %s\n' "davon wirklich uebertragen (aus dem Protokoll der Gegenstelle)" \
    "$(awk '/^(200|206) /{s+=$6} END{print s+0}' "$OUT/srv-gut.log" 2>/dev/null) Oktett (der gute Lauf)"
printf '   %-52s %s\n' "von 'ota suchen' bis zur Antwort (ganzer Start)" "$SUCHMS ms"
printf '   %-52s %s\n' "von 'ota einspielen' bis 'bereit zum Neustart'" "$EINMS ms (Wanduhr, mit Rahmen)"
printf '   %-52s %s\n' "davon in der Maschine: Firmware->Netz / ->Paket geprueft" "$T_NETZ ms / $T_LADEN ms"
printf '   %-52s %s\n' "in der Maschine: ->geschrieben / ->bereit zum Neustart" "$T_SCHREIB ms / $T_FERTIG ms"
printf '   %-52s %s\n' "Rueckfall: der Start, in dem der Kern zurueckschaltet" "$RUECKMS ms"
printf '   %-52s %s\n' "/bin/fetch (TLS 1.3, X.509, RSA, ECDSA, Ed25519 nein)" "$FSZ Oktett"
printf '   %-52s %s\n' "/bin/ota" "$OSZ Oktett"
printf '   %-52s %s\n' "Bloecke frei -- nach Fassung 1 / nach Fassung 2" \
    "$(echo "$BASISBL" | awk '{print $2}') / $GENBL"
printf '   %-52s %s\n' "Zeilen: kernel/user/ota.fi" "$(grep -c . kernel/user/ota.fi)"
printf '   %-52s %s\n' "Zeilen: tools/ota/ (server, verzeichnis, mkcerts, pakete, run)" \
    "$(cat tools/ota/*.py tools/ota/*.sh | grep -c .)"

echo
echo "=================================================================="
echo "  $pass gruen, $fail rot"
echo "=================================================================="
[ "$fail" = 0 ] || exit 1
exit 0
