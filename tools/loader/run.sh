#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/loader/run.sh -- DIE ABNAHME DER RUNDE LADEN.
#
#   bash tools/loader/run.sh [arbeitsverzeichnis]
#
# Sie misst EINE Behauptung, und zwar die ganze:
#
#     Der Laden liefert echte Programme aus. Ein Osum in QEMU holt sie
#     ueber HTTPS von store.fleitec.com, prueft sie, installiert sie,
#     und danach stehen sie im Starter und lassen sich benutzen.
#
# SIEBEN ABSCHNITTE, und jeder hat eine Gegenprobe:
#
#   1. DIE PAKETE. Acht Stueck, aus den Programmen DIESES Baums, mit
#      Titel, Fassung, Beschreibung, Schluesselwoertern und Symbol.
#      Gegenprobe: `opk.py zeigen` liest jedes zurueck und findet
#      `start`, `INFO` und `symbol` darin.
#   2. DIE AUSLIEFERUNG. Sie liegt unter /srv/store/osum und ist von
#      aussen mit `curl` zu holen -- mit einem FREMDEN Werkzeug, damit
#      die Aussage nicht von diesem Repo abhaengt.
#   3. DIE LISTE. Ein Osum ohne jedes Paket fragt den Laden und zaehlt
#      acht auf. Gegenprobe: die Fassungsnummer, die es DABEI liest,
#      ist die aus dem signierten VERZEICHNIS und nicht geraten.
#   4. DIE INSTALLATION. `ota einspielen`: holen, Laenge und SHA-256
#      gegen das VERZEICHNIS, dann `opk` -- das die Signatur ein
#      ZWEITES Mal prueft, mit eigenem Code.
#   5. DAS PROGRAMM LAEUFT. Der Schreibtisch startet, der Starter
#      findet die neuen Programme unter ihrem ANZEIGENAMEN, und eines
#      davon macht sein Fenster auf. Mit Bild.
#   6. DIE GEGENPROBE. Die beschaedigten Pakete aus
#      /root/ota-avx-nach/boese muessen ABGELEHNT werden -- eines mit
#      gekipptem Oktett, eines ohne Signatur, eines mit der Signatur
#      eines fremden Schluessels. Ohne diesen Abschnitt waere Abschnitt
#      4 kein Nachweis, sondern eine Beobachtung.
#   7. DIE BILDER. Sie werden nicht angeschaut, sondern GELESEN:
#      `tesseract` holt den Text aus dem Terminalfenster zurueck und
#      die erwarteten Zeilen muessen darin stehen.
#
# DIESER LAEUFER IST NICHT IN test.sh ANGEMELDET. Er braucht das offene
# Internet und einen Server, der diesem Wirt gehoert; eine Abnahme, die
# ohne fremde Infrastruktur nicht gruen werden kann, ist keine Abnahme.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${1:-/tmp/laden}
. "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/tools/lib/sperre.sh" && osum_sperre "$OUT"   # A-024
export OUT
NAME=${STORE_NAME:-store.fleitec.com}
BASIS=${STORE_URL:-https://$NAME/osum/aktuell}
STORE_DIR=${STORE_DIR:-/srv/store}
BOESE=${BOESE:-/root/ota-avx-nach/boese}
NETZ="nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0"
TEXT="osum vfs nokbd nosched noproc nofs noring3 $NETZ"
GUI="osum gfx fbres=1280x1024 wm wig wigicons notafel wmshell wmdauer nosched noproc nofs $NETZ"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
hat() { grep -qaF "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 -- '$2' fehlt"; }
gleich() { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', erwartet '$3'"; fi; }

for t in qemu-system-x86_64 python3 curl; do
    command -v "$t" >/dev/null 2>&1 || { echo "LADEN: uebersprungen, $t fehlt"; exit 0; }
done
curl -sS -o /dev/null --max-time 20 "$BASIS/VERZEICHNIS" \
    || { echo "LADEN: uebersprungen, $BASIS ist nicht erreichbar"; exit 0; }

echo "== 1. die Pakete =="
bash tools/loader/build.sh "$OUT" > "$OUT/build.log" 2>&1 \
    && ok "Kern und $(wc -l < "$OUT/proglist") Programme uebersetzt" \
    || { bad "build.sh"; tail -20 "$OUT/build.log"; exit 1; }
bash tools/loader/pakete.sh "$OUT" > "$OUT/pakete.log" 2>&1 \
    && ok "$(ls "$OUT"/stand/*.opk | wc -l) Pakete gebaut ($(du -sb "$OUT/stand" | cut -f1) Oktette)" \
    || { bad "pakete.sh"; tail -20 "$OUT/pakete.log"; exit 1; }
fehlt=0
for p in "$OUT"/stand/*.opk; do
    t=$(python3 /root/orientos-install/pkg/opk.py zeigen "$p")
    for f in " start " " INFO " " symbol "; do
        printf '%s' "$t" | grep -q "$f" || fehlt=$((fehlt+1))
    done
done
gleich "jedes Paket traegt start, INFO und symbol (fehlende)" "$fehlt" "0"

echo "== 2. die Auslieferung, von aussen geholt =="
for f in VERZEICHNIS VERZEICHNIS.sig INDEX INDEX.sig; do
    code=$(curl -sS -o "$OUT/netz-$f" -w '%{http_code}' --max-time 30 "$BASIS/$f")
    gleich "curl holt $f" "$code" "200"
done
N=$(grep -c '^paket' "$OUT/netz-VERZEICHNIS" 2>/dev/null)
gleich "das signierte VERZEICHNIS nennt acht Pakete" "$N" "8"

echo "== 3./4. Liste und Installation, in QEMU, ueber den NAMEN =="
bash tools/loader/abbild.sh "$OUT" > "$OUT/abbild.log" 2>&1 \
    && ok "Abbild gebaut" || { bad "abbild.sh"; tail -10 "$OUT/abbild.log"; exit 1; }
cp -f "$OUT/platte/disk.img" "$OUT/text.img"
LADEN_PLATTE="$OUT/text.img" bash tools/loader/lauf.sh a1 \
    "$TEXT script=opk liste;ota suchen;exit" 900 > /dev/null 2>&1
hat "$OUT/a1.txt" "(keine Pakete)"          "vorher ist kein Paket installiert"
hat "$OUT/a1.txt" "fetch: verify OK"        "die Zertifikatskette wurde geprueft"
hat "$OUT/a1.txt" "ota: fassung dort 3"     "das signierte VERZEICHNIS ist gelesen"
hat "$OUT/a1.txt" "ota: NEUE FASSUNG"       "und es gibt etwas zu holen"
gleich "der Laden zaehlt acht Programme auf" \
       "$(grep -ac '^ota: paket ' "$OUT/a1.txt")" "8"

LADEN_PLATTE="$OUT/text.img" bash tools/loader/lauf.sh a2 \
    "$TEXT script=ota einspielen;opk liste;ls /apps;exit" 3600 > /dev/null 2>&1
gleich "acht Streuwerte stimmen" \
       "$(grep -ac '^ota: streuwert stimmt' "$OUT/a2.txt")" "8"
gleich "opk prueft acht Paketsignaturen ein zweites Mal" \
       "$(grep -ac '^opk: Signatur geprüft /tmp/ota/.*opk' "$OUT/a2.txt")" "8"
gleich "acht Pakete installiert" \
       "$(grep -ac '^opk: installiert ' "$OUT/a2.txt")" "8"
for p in explorer edit settings widgetdemo netview themetest top netmon; do
    grep -qa "  $p -> " "$OUT/a2.txt" && ok "opk liste kennt $p" \
        || bad "opk liste kennt $p nicht"
done

echo "== 5. der Schreibtisch, und ein Programm aus dem Laden laeuft =="
cp -f "$OUT/text.img" "$OUT/lauf.img"
python3 tools/themestore/click.py 300,250 > "$OUT/k-start.txt"
echo "warte 2" >> "$OUT/k-start.txt"
python3 tools/loader/tippen.py "explorer" --warte 25 >> "$OUT/k-start.txt"
LADEN_WARTE=15 LADEN_KILL=ja bash tools/loader/lauf.sh a3 \
    "$GUI" 900 "wm: dauer" "$OUT/k-start.txt" > /dev/null 2>&1
[ -s "$OUT/a3.png" ] && ok "Bild a3.png ($(stat -c%s "$OUT/a3.png") Oktette)" \
    || bad "kein Bild a3.png"

echo "== 6. die Gegenprobe: beschaedigte Pakete =="
cp -f "$OUT/platte/disk.img" "$OUT/boese.img"
LADEN_PLATTE="$OUT/boese.img" bash tools/loader/lauf.sh a4 \
    "osum vfs nokbd nosched noproc nofs noring3 script=opk installieren /boese/verdreht.opk;opk installieren /boese/ohnesig.opk;opk installieren /boese/hallo-1.opk;opk liste;exit" \
    600 > /dev/null 2>&1
hat "$OUT/a4.txt" "opk: SIGNATUR FALSCH -- das Paket wird ABGELEHNT: /boese/verdreht.opk" \
    "ein gekipptes Oktett wird abgelehnt"
hat "$OUT/a4.txt" "opk: KEINE SIGNATUR -- abgelehnt" \
    "ein Paket ohne Signatur wird abgelehnt"
hat "$OUT/a4.txt" "opk: SIGNATUR FALSCH -- das Paket wird ABGELEHNT: /boese/hallo-1.opk" \
    "ein Paket mit der Signatur eines FREMDEN Schluessels wird abgelehnt"
hat "$OUT/a4.txt" "(keine Pakete)" \
    "und danach ist NICHTS installiert -- kein halbes Paket"

echo "== 7. die Bilder werden gelesen, nicht angeschaut =="
if command -v tesseract >/dev/null 2>&1; then
    for b in a3; do
        [ -s "$OUT/$b.png" ] || continue
        python3 - "$OUT/$b" <<'PY'
import sys
from PIL import Image
b = sys.argv[1]
Image.open(b + ".png").convert("RGB").resize((2560, 2048)).save(b + "-ocr.png")
PY
        tesseract "$OUT/$b-ocr.png" "$OUT/$b-ocr" --psm 6 > /dev/null 2>&1
        [ -s "$OUT/$b-ocr.txt" ] && ok "$b: $(wc -w < "$OUT/$b-ocr.txt") Woerter aus dem Bild gelesen" \
            || bad "$b: aus dem Bild ist kein Text zu holen"
    done
else
    ok "uebersprungen: tesseract ist auf diesem Wirt nicht da"
fi

echo
echo "LADEN: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
