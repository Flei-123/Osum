#!/usr/bin/env bash
#
#   bash tools/explorer2/run.sh [arbeitsverzeichnis]
#
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${1:-$(mktemp -d)}
. tools/lib/tmpdir.sh
osum_tmp_guard "${1:-}" "$OUT"
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
    echo "EXPLORER-2: skipped, qemu-system-x86_64 is missing"; exit 0
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

echo "== 2. the catalog (de and en) =="
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
    || bad "catalog: only ${kde:-0} keys"
grep -q 'nur_de \[\]' "$OUT/katalog.txt" \
    && ok "every German key has an English one" \
    || { bad "Schluessel fehlen in en"; grep nur_de "$OUT/katalog.txt"; }
grep -q 'nur_en \[\]' "$OUT/katalog.txt" \
    && ok "every English key has a German one" \
    || { bad "Schluessel fehlen in de"; grep nur_en "$OUT/katalog.txt"; }

echo "== 3. Quelltext: Punkte 2, 11, 12 =="
if grep -qE '^\s*static mut t_(zur|vor|auf):' <(bash tools/structure/srcview.sh kernel/user/explorer.fi); then
    bad "item 12: the text characters < > ^ are still in the source"
else
    ok "item 12: the text characters < > ^ are gone"
fi
grep -qE 'fuiscene\.icon_button\([a-z]+, icons\.NAV_BACK' <(bash tools/structure/srcview.sh kernel/user/explorer.fi) \
    && ok "Punkt 12: die Werkzeugleiste ruft icon_button(NAV_BACK)" \
    || bad "item 12: no symbol buttons in the toolbar"

grep -qE 'io\.rename' kernel/user/expakt.fi \
    && ok "Punkt 2: umbenennen ruft io.rename" \
    || bad "item 2: no io.rename -- it still copies and deletes"
if grep -qE '^fn umbenennen\(' <(bash tools/structure/srcview.sh kernel/user/explorer.fi); then
    bad "item 2: the old function umbenennen() is still in explorer.fi"
else
    ok "item 2: the old function umbenennen() is gone"
fi
if grep -qE 'io\.(create|write_all|unlink)\(' <(bash tools/structure/srcview.sh kernel/user/explorer.fi); then
    bad "item 2: explorer.fi still touches files itself"
else
    ok "item 2: explorer.fi no longer touches any file itself"
fi

me=$(grep -oE '^const MAXENT: u64 = [0-9]+' kernel/user/expmodell.fi | grep -oE '[0-9]+$')
nb=$(grep -oE '^const NAMEB: u64 = [0-9]+' kernel/user/expmodell.fi | grep -oE '[0-9]+$')
hi=$(grep -oE '^const CAP: u64 = [0-9]+' lib/nav/stack.fi | grep -oE '[0-9]+$')
[ "${me:-0}" -ge 4096 ] && ok "Punkt 11: MAXENT = $me" || bad "Punkt 11: MAXENT = ${me:-0}"
[ "${nb:-0}" -ge 256 ]  && ok "Punkt 11: NAMEB = $nb"  || bad "Punkt 11: NAMEB = ${nb:-0}"
[ "${hi:-0}" -ge 32 ]   && ok "Punkt 11: Historie = $hi" || bad "Punkt 11: Historie = ${hi:-0}"
w4=$(grep -cE 'if welches == 4 \{' <(bash tools/structure/srcview.sh kernel/user/explorer.fi))
[ "$w4" -le 1 ] && ok "item 11: the duplicate branch is resolved ($w4 occurrences)" \
    || bad "Punkt 11: 'if welches == 4' steht $w4 mal da, der zweite ist tot"

grep -qE 'fn error_key' kernel/user/expakt.fi \
    && ok "item 8: there is a mapping error code -> catalog text" \
    || bad "item 8: no mapping error code -> text"

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
taste 9
warte 2
taste ret
warteauf explorer: rename rc=0 || 60
warte 4
# --- RUECKGAENGIG, Strg+Z (Punkt 9)
#
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
    echo "FAIL: no serial output"; tail -20 "$OUT/lauf.log"; exit 1
fi
grep -qa 'wm: hold' "$S" && ok "the window server got as far as 'wm: hold'" \
    || bad "the window server never got as far as 'wm: hold'"
hat "$S" 'explorer: ready' "der Dateimanager ist hochgekommen"

echo "== 5. the mandatory items on the serial line =="

hat "$S" 'explorer: zeit mtime=[0-9]+' "Punkt 5: die Zeiten werden gelesen"
with_n=$(letzte "$S" 'explorer: zeit mtime=[0-9]+ with_n=[0-9]+')
total_n=$(grep -aoE 'explorer: zeit [^ ]+ with_n=[0-9]+ total_n=[0-9]+' "$S" | tail -1 \
      | grep -oE 'total_n=[0-9]+' | grep -oE '[0-9]+')
if [ "${with_n:-0}" -gt 0 ] 2>/dev/null; then
    ok "item 5: $with_n of ${total_n:-?} entries carry a REAL time"
else
    bad "item 5: no entry has a time -- the column still shows '--'"
fi
hat "$S" 'tzoff=[0-9]+' "Punkt 5: der Ortszeitversatz aus /etc/time.conf"

# --- Punkt 11 zur Laufzeit.
hat "$S" 'explorer: modell n=[0-9]+ blob=[0-9]+ ueberlauf=0' \
    "Punkt 11: eingelesen ohne Ueberlauf"

orte=$(groesste "$S" 'explorer: orte n=[0-9]+')
[ "${orte:-0}" -ge 4 ] 2>/dev/null \
    && ok "item 6: $orte places in the sidebar" \
    || bad "item 6: only ${orte:-0} places in the sidebar"
hat "$S" 'explorer: krume n=[0-9]+' "Punkt 6: die Brosamenleiste ist gebaut"
hat "$S" 'explorer: krume n=[0-9]+ feld=1' \
    "Punkt 6: Strg+L macht aus der Leiste ein Textfeld"

# --- Punkt 3: die Mehrfachauswahl.
aus=$(groesste "$S" 'explorer: sel n=[0-9]+')
[ "${aus:-0}" -ge 2 ] 2>/dev/null \
    && ok "item 3: Ctrl+A selected $aus rows" \
    || bad "item 3: at most ${aus:-0} rows selected -- Ctrl+A does not work"

# --- Punkt 1: die Zwischenablage.
clipn=$(groesste "$S" 'explorer: clip n=[0-9]+')
[ "${clipn:-0}" -ge 1 ] 2>/dev/null \
    && ok "item 1: Ctrl+C put $clipn paths into the clipboard" \
    || bad "item 1: the clipboard stayed empty -- Ctrl+C does not work"
hat "$S" 'explorer: paste n=[0-9]+' "Punkt 1: Strg+V hat eingefuegt"

hat "$S" 'explorer: dlgrect' "Punkt 2: F2 macht den Umbenennen-Dialog auf"

# --- Punkt 4: Eigenschaften.
hat "$S" 'explorer: (props lines=[0-9]+|taste 288)' \
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
[ "$n" -ge 6 ] && ok "$n Aufnahmen entstanden" || bad "only $n shots"

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
