#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."

APPS=${APPS:-"calc explorer taskmgr mail fvviewer charmap cliphist disks storage trashbin nedit welcome powermon netmon runbox"}
LUMA_LIMIT=${LUMA_LIMIT:-55}
ABSENT=${ABSENT:-"Abbrechen,Datei,Hilfe,Löschen,Beenden,Bearbeiten,Ansicht,Speichern,Schließen,Öffnen,Rechner,Fehler,Verbinden,Konto,Nachricht,Ordner,Prozesse,Papierkorb,Sprache,Zurück"}
KEEP=${KEEP:-/tmp/darkaudit}
BASE_PROGS="desktop taskbar settings launcher theme explorer taskmgr sh echo ls cat sleep ps kill top"
mkdir -p "$KEEP"
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

shoot() {
    local name=$1 app=$2 mode=$3 lang=$4 extra=${5:-}
    local progs="$BASE_PROGS"
    case " $progs " in *" $app "*) ;; *) progs="$progs $app" ;; esac
    rm -rf "$TMPD/$name"
    bash tools/toolbench/build.sh "$TMPD/$name" app=/bin/$app mode=$mode lang=$lang \
        wait=10 last=120 shot=s progs="$progs" $extra > "$TMPD/$name.log" 2>&1
    if [ -s "$TMPD/$name/s.ppm" ]; then
        python3 -c "from PIL import Image; Image.open('$TMPD/$name/s.ppm').save('$KEEP/$name.png')"
        return 0
    fi
    return 1
}

audit() {
    local app=$1
    if ! shoot "$app-dark-en" "$app" dark en; then
        bad "$app: no screenshot ($(tail -1 "$TMPD/$app-dark-en.log" | cut -c1-100))"
        return
    fi
    local ppm="$TMPD/$app-dark-en/s.ppm"
    if python3 tools/i18naudit/check.py luma "$ppm" "$LUMA_LIMIT" dark > "$TMPD/l.txt"; then
        ok "$app dark: $(tr -s ' ' < "$TMPD/l.txt" | sed 's/^ *//')"
    else
        bad "$app dark: $(tr -s ' ' < "$TMPD/l.txt" | sed 's/^ *//')"
    fi
    if python3 tools/i18naudit/check.py ocr "$ppm" "" "$ABSENT" > "$TMPD/o.txt"; then
        ok "$app en: no German word on screen"
    else
        bad "$app en: $(tr '\n' ' ' < "$TMPD/o.txt" | sed 's/^ *//')"
    fi
}

counter() {
    shoot calc-light-de calc light de || { bad "counter: no screenshot"; return; }
    local ppm="$TMPD/calc-light-de/s.ppm"
    if python3 tools/i18naudit/check.py luma "$ppm" "$LUMA_LIMIT" dark > /dev/null; then
        bad "counter-proof: light calc passed the dark luma gate"
    else
        ok "counter-proof: light calc fails the dark luma gate"
    fi
    if python3 tools/i18naudit/check.py ocr "$ppm" "" "$ABSENT" > /dev/null; then
        bad "counter-proof: German calc passed the no-German OCR gate"
    else
        ok "counter-proof: German calc fails the no-German OCR gate"
    fi
}

for a in $APPS; do audit "$a"; done
[ "${COUNTER:-1}" = 1 ] && counter
echo "darkaudit: $pass ok, $fail fail"
[ "$fail" = 0 ]
