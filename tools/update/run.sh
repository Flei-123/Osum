#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/update/run.sh -- RUNDE UPDATE: DIE KETTE, MIT DER SICH DIESES
# SYSTEM SELBST ERNEUERT -- UND DIE STELLE, AN DER SIE ABBRICHT.
#
# VIER ABSCHNITTE, und der wichtigste ist der letzte:
#
#   1. DIE RECHNUNG (auf dem Wirt, ohne QEMU). SHA-512 gegen FIPS 180-4
#      und Pythons `hashlib`, Ed25519 gegen die fuenf Vektoren aus dem
#      Text von RFC 8032, gegen die 1024 Vektoren der offiziellen
#      `sign.input` und gegen libsodium -- dazu die NEGATIVE Haelfte: ein
#      gekipptes Bit in Nachricht, R, S oder Schluessel, und ein S+L, das
#      dieselbe Signatur anders schreibt. (tools/update/vectors.py)
#
#   2. DIE SIGNATURPFLICHT AUF DEM GERAET. `/bin/opk` in QEMU, auf einer
#      echten Platte, gestartet ueber die EFI-Partition. Ein richtig
#      signiertes Paket wird installiert; ein UNSIGNIERTES, ein
#      VERDREHTES, eines aus einer Quelle mit veraendertem INDEX, eines
#      mit einem FREMDEN Schluessel und eines OHNE vertrauten Schluessel
#      werden abgelehnt -- und nach jeder Ablehnung wird nachgesehen,
#      dass wirklich NICHTS installiert wurde.
#
#   3. DER ERPROBUNGSZAEHLER. Ein Update, das sauber signiert ist und
#      trotzdem nicht hochkommt (`kernel/user/hallo3.fi` beendet sich mit
#      Code 1). Drei Starts, kein Erfolgsvermerk, und beim dritten faellt
#      der Kern VON SELBST auf die vorige Generation zurueck.
#      GEGENPROBE: dasselbe mit einem Update, das laeuft -- dann wird
#      bestaetigt und NIE zurueckgefallen.
#
#   4. DER GANZE ABLAUF am Stueck: pruefen, holen, Signatur, Generation,
#      Neustart, Erfolgsvermerk.
#
# Verwendung:  bash tools/update/run.sh  [--schnell]
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${OUT:-/tmp/update-run}
mkdir -p "$OUT"
export OUT
SCHNELL=${1:-}

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
gleich() { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', erwartet '$3'"; fi; }
hat() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hatnicht() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da und sollte nicht" || ok "$3"; }

lauf() { # name skript [limit]
    OUT="$OUT" bash tools/install/oneshot.sh "$1" platte "$2" "${3:-600}" \
        > /dev/null 2>&1
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' "$OUT/$1.txt" 2>/dev/null
    cat "$OUT/$1.rc" 2>/dev/null
}

# =====================================================================
echo "== 1. die Rechnung: SHA-512 und Ed25519 gegen ihre Normen =="
# =====================================================================
vendor/firn/bin/firnc tools/update/oracle.fi -o .probe/uoracle \
    2> "$OUT/oracle.err" \
    && ok "tools/update/oracle.fi baut gegen lib/crypto/ (dieselben Dateien wie der Kern)" \
    || { bad "tools/update/oracle.fi laesst sich nicht bauen"; head -20 "$OUT/oracle.err"; }

ARGV=()
[ "$SCHNELL" = "--schnell" ] && ARGV=(--quick)
if python3 tools/update/vectors.py "${ARGV[@]}" > "$OUT/vectors.log" 2>&1; then
    sed -n '/  sha512/,$p' "$OUT/vectors.log" | sed 's/^/        /'
    ok "$(tail -1 "$OUT/vectors.log" | sed 's/^ *//')"
else
    sed 's/^/        /' "$OUT/vectors.log" | tail -30
    bad "die Vektoren stimmen NICHT"
fi

# =====================================================================
echo
echo "== 2. das Abbild, die Platte und der erste Start =="
# =====================================================================
mkdir -p "$OUT"
bash tools/install/pakete.sh "$OUT" > "$OUT/pak.log" 2>&1 \
    && ok "zwei signierte Quellen gebaut" || { cat "$OUT/pak.log"; bad "pakete.sh"; }
bash tools/update/pakete.sh "$OUT" > "$OUT/pak3.log" 2>&1 \
    && ok "Fassung 3 (scheitert beim Start) und die boesen Dateien gebaut" \
    || { cat "$OUT/pak3.log"; bad "update/pakete.sh"; }

EX="/quelle3/ /boese/"
for f in "$OUT/quelle3"/*; do EX="$EX /quelle3/$(basename "$f")=$f"; done
for f in "$OUT/boese"/*;   do EX="$EX /boese/$(basename "$f")=$f"; done
EX="$EX /fremd.pub=$OUT/fremd.pub"
# DAS STARTSKRIPT. Die Kommandozeile des Laders trennt bei `;` und
# uebergibt jedes Stueck als EINEN Befehl -- ein `if` kaeme dort nie
# heil an. Also liegt der Startvorgang als richtiges Shell-Skript auf
# der Platte, so wie er auf einem Geraet auch laege:
#
#     opk richten                 die Sicht /apps aus der LAUFENDEN
#                                 Generation neu bauen (nach einem
#                                 Rueckfall zeigt sie sonst noch auf die
#                                 Generation, die nicht hochkam)
#     if /apps/hallo.osp/start    das Paket starten
#     then opk erprobung ok       und NUR WENN ES LAEUFT bestaetigen
#
# Auf einem ausgelieferten System stuenden diese drei Zeilen in
# `/etc/inittab` bzw. in dem Dienst, der den Start abschliesst.
printf 'opk richten\nif /apps/hallo.osp/start\nthen\nopk erprobung ok\nfi\nopk erprobung\n' \
    > "$OUT/start.sh"
EX="$EX /start.sh=$OUT/start.sh"
EXTRA="$EX" bash tools/install/build.sh "$OUT" > "$OUT/build.log" 2>&1 \
    && ok "Abbild gebaut ($(grep -c . "$OUT/build.log") Zeilen Protokoll)" \
    || { tail -20 "$OUT/build.log"; bad "build.sh"; }

rm -f "$OUT/ziel.img"
head -c $((256 * 1024 * 1024)) /dev/zero > "$OUT/ziel.img"
OUT="$OUT" bash tools/install/oneshot.sh inst iso "install /dev/hda --ja;exit" 900 \
    > /dev/null 2>&1
gleich "die Installation auf die leere Platte" "$(cat "$OUT/inst.rc")" "21"
hat "$OUT/inst.txt" "install: fertig" "der Installer meldet sich fertig"

rc=$(lauf erst "opk erprobung;exit")
gleich "der erste Start von der Platte" "$rc" "21"
hat "$OUT/erst.txt" "ab: keine erprobung" "ohne /system/ERPROBUNG sagt der Kern genau das und tut nichts"
cp -f "$OUT/ziel.img" "$OUT/leer.img"

# =====================================================================
echo
echo "== 3. die Signaturpflicht =="
# =====================================================================
h1=$(python3 -c "print(open('$OUT/quelle1/INDEX').read().split(chr(9))[2])" 2>/dev/null)
echo "        hallo 1.0.0 = ${h1:0:16}"

rc=$(lauf sig1 "opk installieren /quelle1/hallo-1.opk;opk liste;exit")
hat "$OUT/sig1.txt" "opk: Signatur geprüft" "das signierte Paket wird geprueft"
hat "$OUT/sig1.txt" "opk: installiert hallo" "und installiert"
hat "$OUT/sig1.txt" "${h1:0:12}" "die Liste nennt genau den Streuwert des Wirts"

# --- ohne Signaturdatei
cp -f "$OUT/leer.img" "$OUT/ziel.img"
rc=$(lauf sig2 "opk installieren /boese/ohnesig.opk;opk liste;opk generationen;exit")
hat "$OUT/sig2.txt" "KEINE SIGNATUR" "GEGENPROBE: ohne .sig wird abgelehnt, und zwar laut"
hatnicht "$OUT/sig2.txt" "opk: installiert" "und es wird NICHTS installiert"
hatnicht "$OUT/sig2.txt" "generation 0" "es entsteht auch keine Generation"

# --- verdrehtes Paket, richtige Signaturdatei des Originals
cp -f "$OUT/leer.img" "$OUT/ziel.img"
rc=$(lauf sig3 "opk installieren /boese/verdreht.opk;opk liste;exit")
hat "$OUT/sig3.txt" "SIGNATUR FALSCH" "GEGENPROBE: ein gekipptes Oktett bricht die Signatur"
hatnicht "$OUT/sig3.txt" "opk: installiert" "und es wird nichts installiert"
hatnicht "$OUT/sig3.txt" "Pruefsumme falsch" "die SIGNATUR schlaegt zuerst zu, nicht die Pruefsumme"

# --- Quelle mit veraendertem INDEX
cp -f "$OUT/leer.img" "$OUT/ziel.img"
rc=$(lauf sig4 "opk installieren /quelle1/hallo-1.opk;opk aktualisieren hallo --quelle /boese;opk liste;exit")
hat "$OUT/sig4.txt" "SIGNATUR DES INDEX FALSCH" "GEGENPROBE: ein veraenderter INDEX bricht die Quelle"
hat "$OUT/sig4.txt" "${h1:0:12}" "und die installierte Fassung bleibt die alte"

# --- fremder Schluessel
cp -f "$OUT/leer.img" "$OUT/ziel.img"
rc=$(lauf sig5 "cp /fremd.pub /system/schluessel.pub;opk installieren /quelle1/hallo-1.opk;opk liste;exit")
hat "$OUT/sig5.txt" "SIGNATUR FALSCH" "GEGENPROBE: richtig signiert, aber mit dem falschen Schluessel geprueft -> abgelehnt"
hatnicht "$OUT/sig5.txt" "opk: installiert" "und es wird nichts installiert"

# --- gar kein Schluessel
cp -f "$OUT/leer.img" "$OUT/ziel.img"
rc=$(lauf sig6 "rm /system/schluessel.pub;opk installieren /quelle1/hallo-1.opk;opk liste;exit")
hat "$OUT/sig6.txt" "kein vertrauter Schlüssel" "GEGENPROBE: ohne /system/schluessel.pub installiert opk gar nichts"
hatnicht "$OUT/sig6.txt" "opk: installiert" "und es wird nichts installiert"

# =====================================================================
echo
echo "== 4. der Erprobungszaehler: ein Update, das nicht hochkommt =="
# =====================================================================
#
# Der Startbefehl jedes Laufs ist DERSELBE und er ist das, was ein
# System beim Hochfahren taete: die Sicht `/apps` aus der laufenden
# Generation neu bauen, das Paket starten, und NUR WENN ES LAEUFT den
# Erfolgsvermerk setzen. Faellt das Paket um, bleibt der Vermerk aus --
# es gibt nichts, was der Testlauf dafuer extra tun muesste.
START='sh /start.sh;exit'

cp -f "$OUT/leer.img" "$OUT/ziel.img"
rc=$(lauf ab0 "opk installieren /quelle1/hallo-1.opk;$START")
hat "$OUT/ab0.txt" "paket-hallo fassung 1" "Ausgangslage: Fassung 1 laeuft"
hat "$OUT/ab0.txt" "opk: erprobung bestätigt" "und wird bestaetigt"
cp -f "$OUT/ziel.img" "$OUT/basis.img"

rc=$(lauf ab1 "opk aktualisieren hallo --quelle /quelle3;opk erprobung;exit")
hat "$OUT/ab1.txt" "opk: Signatur geprüft" "das kaputte Update ist SAUBER SIGNIERT"
hat "$OUT/ab1.txt" "opk: installiert hallo" "und wird installiert"
hat "$OUT/ab1.txt" "opk: in erprobung: 1 vor 0" "Generation 1 steht in Erprobung, Rueckfall waere 0"

rc=$(lauf ab2 "$START")
hat "$OUT/ab2.txt" "ab: gen=1 versuch=1 von 3" "Start 1: der Kern zaehlt"
hat "$OUT/ab2.txt" "SCHEITERT" "die neue Fassung meldet sich und faellt um"
hatnicht "$OUT/ab2.txt" "opk: erprobung bestätigt" "also KEIN Erfolgsvermerk"

rc=$(lauf ab3 "$START")
hat "$OUT/ab3.txt" "ab: gen=1 versuch=2 von 3" "Start 2: der Zaehler steht auf 2"
hatnicht "$OUT/ab3.txt" "opk: erprobung bestätigt" "immer noch kein Erfolgsvermerk"

rc=$(lauf ab4 "$START")
gleich "Start 3: die Maschine kommt hoch" "$rc" "21"
hat "$OUT/ab4.txt" "ab: ERPROBUNG gescheitert, zurueck auf 0" "DER PUNKT DER RUNDE: der Kern faellt VON SELBST zurueck"
hat "$OUT/ab4.txt" "paket-hallo fassung 1" "und die alte, laufende Fassung ist wieder da"
hatnicht "$OUT/ab4.txt" "SCHEITERT" "die kaputte Fassung laeuft nicht mehr"

rc=$(lauf ab5 "opk erprobung;/apps/hallo.osp/start;exit")
hat "$OUT/ab5.txt" "ab: gen=0 bestaetigt" "beim naechsten Start ist nichts mehr in Erprobung"
hat "$OUT/ab5.txt" "paket-hallo fassung 1" "und es bleibt bei der alten Fassung"

# --- DIE GEGENPROBE: dasselbe mit einem Update, das LAEUFT.
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf gab1 "opk aktualisieren hallo --quelle /quelle2;$START")
hat "$OUT/gab1.txt" "opk: in erprobung: 1 vor 0" "GEGENPROBE: auch das gute Update steht erst in Erprobung"
hat "$OUT/gab1.txt" "paket-hallo fassung 2" "es laeuft"
hat "$OUT/gab1.txt" "opk: erprobung bestätigt für 1" "und wird im selben Start bestaetigt"
rc=$(lauf gab2 "$START")
hat "$OUT/gab2.txt" "ab: gen=1 bestaetigt" "beim naechsten Start zaehlt der Kern nichts mehr hoch"
rc=$(lauf gab3 "$START")
rc=$(lauf gab4 "$START")
hat "$OUT/gab4.txt" "paket-hallo fassung 2" "und auch nach vier Starts laeuft noch die NEUE Fassung"
hatnicht "$OUT/gab4.txt" "zurueck auf" "es wird nie zurueckgefallen"

# =====================================================================
echo
echo "== 5. der ganze Ablauf am Stueck =="
# =====================================================================
cp -f "$OUT/basis.img" "$OUT/ziel.img"
rc=$(lauf fluss "opk liste;opk aktualisieren hallo --quelle /quelle2;opk erprobung;exit")
hat "$OUT/fluss.txt" "opk: installiert hallo" "holen -> Signatur -> Generation"
rc=$(lauf fluss2 "$START")
hat "$OUT/fluss2.txt" "paket-hallo fassung 2" "Neustart -> die neue Fassung laeuft"
hat "$OUT/fluss2.txt" "opk: erprobung bestätigt" "-> Erfolgsvermerk"

echo
echo "=================================================================="
echo "  $pass gruen, $fail rot"
echo "=================================================================="
[ "$fail" = 0 ] || exit 1
exit 0
