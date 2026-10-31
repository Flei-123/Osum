#!/usr/bin/env bash
#
#   bash tools/explorer2/run.sh [arbeitsverzeichnis]
#
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${1:-$(mktemp -d)}
mkdir -p "$OUT"
SHOTS=${EXPLORER2_SHOTS:-$ROOT/.explorer2-shots}
mkdir -p "$SHOTS"
RES=${RES:-1280x800}

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
hat() { grep -qaE "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 -- fehlt: $2"; }
letzte() { grep -aoE "$2" "$1" 2>/dev/null | tail -1 | grep -oE '[0-9]+$'; }
groesste() { grep -aoE "$2" "$1" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1; }

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "EXPLORER-2: uebersprungen, qemu-system-x86_64 ist nicht da"; exit 0
fi
python3 -c "import PIL" 2>/dev/null || {
    echo "EXPLORER-2: uebersprungen, Pillow fehlt"; exit 0; }

# ------------------------------------------------------------ 1. bauen
echo "== 1. bauen =="
export DESIGNBUILD=${DESIGNBUILD:-/tmp/osum-explorer2-build}
bash tools/design/capture.sh "$OUT/bau" nurbau=ja res="$RES" \
    > "$OUT/bau.log" 2>&1 \
    || { echo "FEHLGESCHLAGEN: der Bau"; tail -20 "$OUT/bau.log"; exit 1; }
ok "Kern und Programme uebersetzen"

for m in expmodell exporte expakt expdlg fileop; do
    stub="kernel/user/zz_chk_$m.fi"
    printf 'profile app\nimport %s\nfn main() -> i32 {\n    return 0\n}\n' "$m" > "$stub"
    if vendor/firn/bin/firnc -c --profile=app "$stub" -o "$OUT/$m.o" \
            > "$OUT/e-$m" 2>&1; then
        ok "Baustein $m uebersetzt einzeln"
    else
        bad "Baustein $m uebersetzt einzeln"; head -10 "$OUT/e-$m"
    fi
    rm -f "$stub"
done

echo "== 2. der Katalog (de und en) =="
python3 - "$ROOT" "$OUT" <<'PY'
import re, sys, os
root, out = sys.argv[1], sys.argv[2]
def keys(p):
    return set(re.findall(r"^(explorer\.[A-Za-z0-9_.]+)\s*=",
                          open(p, encoding="utf-8").read(), re.M))
de = keys(os.path.join(root, "locale/de/messages"))
en = keys(os.path.join(root, "locale/en/messages"))
open(os.path.join(out, "katalog.txt"), "w").write(
    "de %d\nen %d\nnur_de %s\nnur_en %s\n"
    % (len(de), len(en), sorted(de - en), sorted(en - de)))
PY
kde=$(grep -oE '^de [0-9]+' "$OUT/katalog.txt" | grep -oE '[0-9]+')
[ "${kde:-0}" -ge 60 ] && ok "Katalog: $kde Schluessel explorer.*" \
    || bad "Katalog: nur ${kde:-0} Schluessel"
grep -q 'nur_de \[\]' "$OUT/katalog.txt" \
    && ok "jeder deutsche Schluessel hat einen englischen" \
    || { bad "Schluessel fehlen in en"; grep nur_de "$OUT/katalog.txt"; }
grep -q 'nur_en \[\]' "$OUT/katalog.txt" \
    && ok "jeder englische Schluessel hat einen deutschen" \
    || { bad "Schluessel fehlen in de"; grep nur_en "$OUT/katalog.txt"; }

echo "== 3. Quelltext: Punkte 2, 11, 12 =="
if grep -qE '^\s*static mut t_(zur|vor|auf):' kernel/user/explorer.fi; then
    bad "Punkt 12: die Textzeichen < > ^ stehen noch im Quelltext"
else
    ok "Punkt 12: die Textzeichen < > ^ sind weg"
fi
grep -qE 'fuiscene\.icon_button\([a-z]+, icons\.NAV_BACK' kernel/user/explorer.fi \
    && ok "Punkt 12: die Werkzeugleiste ruft icon_button(NAV_BACK)" \
    || bad "Punkt 12: keine Symbolknoepfe in der Werkzeugleiste"

grep -qE 'io\.rename' kernel/user/expakt.fi \
    && ok "Punkt 2: umbenennen ruft io.rename" \
    || bad "Punkt 2: kein io.rename -- es wird noch kopiert und geloescht"
if grep -qE '^fn umbenennen\(' kernel/user/explorer.fi; then
    bad "Punkt 2: die alte Funktion umbenennen() steht noch in explorer.fi"
else
    ok "Punkt 2: die alte Funktion umbenennen() ist weg"
fi
if grep -qE 'io\.(create|write_all|unlink)\(' kernel/user/explorer.fi; then
    bad "Punkt 2: explorer.fi fasst Dateien noch selbst an"
else
    ok "Punkt 2: explorer.fi fasst keine Datei mehr selbst an"
fi

me=$(grep -oE '^const MAXENT: u64 = [0-9]+' kernel/user/expmodell.fi | grep -oE '[0-9]+$')
nb=$(grep -oE '^const NAMEB: u64 = [0-9]+' kernel/user/expmodell.fi | grep -oE '[0-9]+$')
hi=$(grep -oE '^const CAP: u64 = [0-9]+' lib/nav/stack.fi | grep -oE '[0-9]+$')
[ "${me:-0}" -ge 4096 ] && ok "Punkt 11: MAXENT = $me" || bad "Punkt 11: MAXENT = ${me:-0}"
[ "${nb:-0}" -ge 256 ]  && ok "Punkt 11: NAMEB = $nb"  || bad "Punkt 11: NAMEB = ${nb:-0}"
[ "${hi:-0}" -ge 32 ]   && ok "Punkt 11: Historie = $hi" || bad "Punkt 11: Historie = ${hi:-0}"
w4=$(grep -cE 'if welches == 4 \{' kernel/user/explorer.fi)
[ "$w4" -le 1 ] && ok "Punkt 11: der doppelte Zweig ist aufgeloest ($w4 Vorkommen)" \
    || bad "Punkt 11: 'if welches == 4' steht $w4 mal da, der zweite ist tot"

grep -qE 'fn error_key' kernel/user/expakt.fi \
    && ok "Punkt 8: es gibt eine Zuordnung Fehlercode -> Katalogtext" \
    || bad "Punkt 8: keine Zuordnung Fehlercode -> Text"

# ------------------------------------------------------------ 4. der Lauf
echo "== 4. der Lauf =="
cat > "$OUT/dreh.txt" <<'DREH'
warteauf explorer: ready || 240
warte 8
foto 10-grund
# --- ALLES AUSWAEHLEN (Punkt 3)
klickauf ftab
warte 2
taste ctrl-a
warte 3
foto 11-auswahl
# --- KOPIEREN (Punkt 1)
taste ctrl-c
warte 3
# --- IN DEN UNTERORDNER `bilder` (Zeile 0 der Tabelle, sie steht oben,
#     weil Verzeichnisse immer zuerst sortiert werden) und DORT
#     einfuegen. Im SELBEN Ordner waere Strg+V zu Recht -EINVAL:
#     `expakt.in_sich` legt keinen Ordner in sich selbst.
doppelauf ftabzeile0
warteauf explorer: cd /data/bilder || 60
warte 4
taste ctrl-v
warte 8
foto 12-eingefuegt
# --- DAS KONTEXTMENUE
rklickauf ftab
warteauf explorer: menurect || 60
warte 4
foto 13-kontextmenue
taste esc
warte 3
# --- EIGENSCHAFTEN, Alt+Eingabe (Punkt 4)
klickauf ftab
warte 2
taste alt-ret
warte 5
foto 14-eigenschaften
taste esc
warte 3
# --- VERSTECKTE DATEIEN, Strg+H (Punkt 7)
taste ctrl-h
warte 4
foto 15-versteckt
taste ctrl-h
warte 3
# --- DIE PFADLEISTE ALS TEXTFELD, Strg+L (Punkt 6)
taste ctrl-l
warte 4
foto 16-pfadfeld
taste ctrl-l
warte 3
# --- NEU LADEN, F5 (Punkt 7)
taste f5
warte 4
# --- UMBENENNEN, F2 (Punkt 2)
klickauf ftab
warte 2
taste f2
warte 5
foto 17-umbenennen
# Der Dialog steht mit dem alten Namen im Feld und dem Text markiert;
# ein angehaengtes `9` macht daraus einen anderen Namen, die
# Eingabetaste fuehrt es aus. ERST DANN hat Strg+Z etwas zu tun.
taste 9
warte 2
taste ret
warteauf explorer: rename rc=0 || 60
warte 4
# --- RUECKGAENGIG, Strg+Z (Punkt 9)
#
# GEMESSEN: `sendkey ctrl-z` kam im Gast als `^Y` an. Die Platte ist
# auf die deutsche Belegung gestellt (`/etc/locale.conf` lang=de), und
# dort sind Y und Z vertauscht -- das ist das Z, das QWERTZ seinen
# Namen gibt (kernel/kbd.fi::de_plain). QEMUs `sendkey` benennt die
# Taste nach ihrer AMERIKANISCHEN Beschriftung, also ist die Taste,
# die im Gast ein Z gibt, fuer QEMU das `y`.
taste ctrl-y
warte 4
foto 18-ende
DREH

# uitrace=yes: the explorer says what it does only under /etc/uitrace (the
# lines below are that report); without it the run was blind (FUI-ALL F-8).
# lang=de: the German key layout (Y and Z swapped) is what `ctrl-y` below relies on
bash tools/design/capture.sh "$OUT/lauf" res="$RES" uitrace=yes lang=de \
    extra='nostart wigapp=/bin/explorer' drehbuch="$OUT/dreh.txt" \
    > "$OUT/lauf.log" 2>&1
S="$OUT/lauf/serial.txt"
if [ ! -s "$S" ]; then
    echo "FEHLGESCHLAGEN: keine serielle Ausgabe"; tail -20 "$OUT/lauf.log"; exit 1
fi
grep -qa 'wm: hold' "$S" && ok "der Fensterserver kam bis 'wm: hold'" \
    || bad "der Fensterserver kam nie bis 'wm: hold'"
hat "$S" 'explorer: ready' "der Dateimanager ist hochgekommen"

echo "== 5. die Pflichtpunkte an der seriellen Leitung =="

hat "$S" 'explorer: zeit mtime=[0-9]+' "Punkt 5: die Zeiten werden gelesen"
mit=$(letzte "$S" 'explorer: zeit mtime=[0-9]+ mit=[0-9]+')
von=$(grep -aoE 'explorer: zeit [^ ]+ mit=[0-9]+ von=[0-9]+' "$S" | tail -1 \
      | grep -oE 'von=[0-9]+' | grep -oE '[0-9]+')
if [ "${mit:-0}" -gt 0 ] 2>/dev/null; then
    ok "Punkt 5: $mit von ${von:-?} Eintraegen tragen eine ECHTE Zeit"
else
    bad "Punkt 5: kein Eintrag hat eine Zeit -- die Spalte zeigt weiter '--'"
fi
hat "$S" 'tzoff=[0-9]+' "Punkt 5: der Ortszeitversatz aus /etc/time.conf"

# --- Punkt 11 zur Laufzeit.
hat "$S" 'explorer: modell n=[0-9]+ blob=[0-9]+ ueberlauf=0' \
    "Punkt 11: eingelesen ohne Ueberlauf"

orte=$(groesste "$S" 'explorer: orte n=[0-9]+')
[ "${orte:-0}" -ge 4 ] 2>/dev/null \
    && ok "Punkt 6: $orte Orte in der Seitenleiste" \
    || bad "Punkt 6: nur ${orte:-0} Orte in der Seitenleiste"
hat "$S" 'explorer: krume n=[0-9]+' "Punkt 6: die Brosamenleiste ist gebaut"
hat "$S" 'explorer: krume n=[0-9]+ feld=1' \
    "Punkt 6: Strg+L macht aus der Leiste ein Textfeld"

# --- Punkt 3: die Mehrfachauswahl.
aus=$(groesste "$S" 'explorer: sel n=[0-9]+')
[ "${aus:-0}" -ge 2 ] 2>/dev/null \
    && ok "Punkt 3: Strg+A hat $aus Zeilen markiert" \
    || bad "Punkt 3: hoechstens ${aus:-0} Zeilen markiert -- Strg+A greift nicht"

# --- Punkt 1: die Zwischenablage.
clipn=$(groesste "$S" 'explorer: clip n=[0-9]+')
[ "${clipn:-0}" -ge 1 ] 2>/dev/null \
    && ok "Punkt 1: Strg+C legte $clipn Pfade in die Ablage" \
    || bad "Punkt 1: die Ablage blieb leer -- Strg+C greift nicht"
hat "$S" 'explorer: paste n=[0-9]+' "Punkt 1: Strg+V hat eingefuegt"

hat "$S" 'explorer: dlgrect' "Punkt 2: F2 macht den Umbenennen-Dialog auf"

# --- Punkt 4: Eigenschaften.
hat "$S" 'explorer: (props zeilen=[0-9]+|taste 288)' \
    "Punkt 4: Alt+Eingabe oeffnet die Eigenschaften"

# --- Punkt 7: die Kuerzel.
hat "$S" 'explorer: taste ' "Punkt 7: die Kuerzel kommen im Programm an"
hat "$S" 'explorer: taste 304 an=[01]' \
    "Punkt 7: Strg+H schaltet versteckte Dateien"
hat "$S" 'explorer: taste 273' "Punkt 7: F2 kommt an"
hat "$S" 'explorer: taste 276' "Punkt 7: F5 kommt an"

# --- Punkt 9: rueckgaengig.
hat "$S" 'explorer: (undo|taste 26)' "Punkt 9: Strg+Z meldet sich"

hat "$S" 'explorer: openwith n=[0-9]+' "Punkt 10: die Programmliste ist gelesen"

# ---------------------------------------------- 6. die Bilder, gemessen
echo "== 6. die Bilder =="
python3 - "$OUT/lauf" <<'PY'
import glob, os, sys
from PIL import Image
for p in sorted(glob.glob(os.path.join(sys.argv[1], "*.ppm"))):
    Image.open(p).convert("RGB").save(p[:-4] + ".png")
PY
n=0
for f in "$OUT/lauf"/*.png; do
    [ -e "$f" ] || continue
    n=$((n+1)); cp "$f" "$SHOTS/"
done
[ "$n" -ge 6 ] && ok "$n Aufnahmen entstanden" || bad "nur $n Aufnahmen"

for f in "$OUT/lauf"/*.png; do
    [ -e "$f" ] || continue
    b=$(basename "$f" .png)
    r=$(python3 tools/alltag/shotcheck.py "$f" "$S" --winat=400,200 2>&1 | head -1)
    cut=$(echo "$r" | grep -oE 'cut [0-9]+' | grep -oE '[0-9]+')
    #
    if [ "${cut:-9}" = "0" ]; then
        ok "Bild $b: nichts abgeschnitten"
    else
        bad "Bild $b: cut=${cut:-?}"
    fi
done

echo
echo "======================================================="
echo "EXPLORER-2: $pass gut, $fail schlecht"
echo "Bilder:   $SHOTS"
echo "Leitung:  $S"
[ "$fail" -eq 0 ] || exit 1
exit 0
