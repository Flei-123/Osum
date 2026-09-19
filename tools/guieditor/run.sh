#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/guieditor/run.sh -- DIE ABNAHME DER RUNDE GUI-EDITOR.
#
#   bash tools/guieditor/run.sh [arbeitsverzeichnis]
#
# WAS DIESE RUNDE ZUGESAGT HAT, UND WOMIT ES HIER BELEGT WIRD.
#
# Die Messlatte des Auftrags nennt fuenf Dinge, und jedes bekommt hier
# eine Zahl oder ein Bild -- kein Abschnitt sagt "sieht gut aus":
#
#   1. Eine 5000-Zeilen-Datei laesst sich fluessig oeffnen, scrollen
#      und bearbeiten  ->  Abschnitt 3 und 4, in Mikrosekunden.
#   2. Tippen fuehlt sich nicht traege an (miss die Zeit je
#      Tastendruck)  ->  Abschnitt 4, GEGEN eine kleine Datei
#      gemessen, denn nur der Vergleich sagt, ob die Dateigroesse
#      ueberhaupt etwas kostet.
#   3. Zwei Dateien gleichzeitig in Reitern  ->  Abschnitt 5.
#   4. Suchen/Ersetzen am Bild nachweisbar  ->  Abschnitt 6.
#   5. Syntaxfarben sichtbar  ->  Abschnitt 6, am Bild gezaehlt.
#
# WARUM DIE ZEITEN AUS DEM PROGRAMM KOMMEN UND NICHT VON AUSSEN: ein
# Tastendruck ueber den QEMU-Monitor laeuft durch PS/2, Kern,
# Fensterserver und Ereignisschlange. Was davon auf das TEXTFELD
# entfaellt, ist in der Gesamtzeit nicht zu sehen. `/bin/nedit` hat
# deshalb `messen=N`, `rollen=N` und `rollnur=N`: sie speisen die
# Tasten durch GENAU den Weg ein, den eine echte Taste nimmt
# (`wlib.feed_key` -> `on_key` -> `ta_key`), und nehmen davor und
# danach die Uhr (I_TICKS, 100 Hz -- deshalb ein Buendel und geteilt).
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${1:-$(mktemp -d)}
mkdir -p "$OUT"
SHOTS=${GUIEDITOR_SHOTS:-$ROOT/.editor-shots}
mkdir -p "$SHOTS"
export ALLTAGBUILD=${ALLTAGBUILD:-/tmp/osum-guieditor-build}

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { # name wert vergleich soll
    if [ "$2" "$3" "$4" ] 2>/dev/null; then ok "$1: $2"; else bad "$1: $2, erwartet $3 $4"; fi
}

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "GUI-EDITOR: uebersprungen, qemu-system-x86_64 ist nicht da"; exit 0
fi
python3 -c "import PIL" 2>/dev/null || {
    echo "GUI-EDITOR: uebersprungen, Pillow fehlt"; exit 0; }

# Die zwei Proben. Sie werden HIER gebaut und nicht eingecheckt: eine
# Datei mit 5000 Zeilen im Baum waere 260 KiB Ballast fuer eine Zahl,
# die sich in drei Zeilen Python wieder herstellen laesst.
KLEIN="$OUT/probe.fi"
GROSS="$OUT/gross.fi"
ZWEI="$OUT/zwei.sh"
cat > "$KLEIN" <<'EOF'
// probe.fi -- eine Testdatei fuer den Editor
fn gruss(name: u64) -> u64 {
    let x: u64 = 42
    var summe: u64 = 0
    while summe < x {
        summe = summe + 1   // zaehlen
    }
    return summe
}
const TEXT: u64 = 0x1234
// Ende der Probe
EOF
cat > "$ZWEI" <<'EOF'
#!/bin/sh
# zwei.sh -- die zweite Datei fuer den Reitertest
echo "Hallo Welt"
for i in 1 2 3; do
    echo "Zeile $i"   # eine Schleife
done
if test -f /probe.fi; then
    echo "probe da"
fi
exit 0
EOF
python3 - "$GROSS" <<'PY'
import sys
with open(sys.argv[1], "w") as f:
    f.write("// gross.fi -- 5000 Zeilen fuer die Messung\n")
    for i in range(1, 5000):
        f.write("fn f%d() -> u64 { let x: u64 = %d  // Zeile %d\n" % (i, i, i))
PY

# lauf <name> <datei-auf-der-platte> <hostpfad> <extra-worte> [bild]
lauf() {
    local name=$1 gast=$2 host=$3 extra=$4 bild=${5:-nein}
    local d="$OUT/$name"
    bash tools/alltag/build.sh "$d" \
        progs="desktop taskbar nedit sh echo ls cat" \
        accel="${OSUM_ACCEL:-kvm}" shot="$([ "$bild" = nein ] && echo no || echo yes)" \
        desk=no kbd=yes warten=5 bloecke=32768 \
        "xfile=$gast=$host" \
        extra="wigapp=/bin/nedit,$gast$extra" > "$d.log" 2>&1
    return $?
}

echo "== 1. bauen: die Bibliothek, das Programm und das Buendel =="
if vendor/firn/bin/firnc --profile=app -c kernel/user/nedit.fi \
        -o "$OUT/nedit.o" > "$OUT/e-nedit" 2>&1; then
    ok "kernel/user/nedit.fi uebersetzt"
else
    bad "kernel/user/nedit.fi uebersetzt"; head -12 "$OUT/e-nedit"
fi
rm -f "$OUT/nedit.o"
[ -f assets/apps/nedit.osp/INFO ] && ok "das Buendel assets/apps/nedit.osp ist da" \
    || bad "das Buendel assets/apps/nedit.osp fehlt"
if python3 tools/k15/icon.py assets/apps/nedit.osp/symbol.txt \
        "$OUT/sym.bin" > /dev/null 2>&1; then
    ok "sein Symbol laesst sich in ein Bild wandeln"
else
    bad "sein Symbol laesst sich in ein Bild wandeln"
fi
# DER ALTE EDITOR BLEIBT. Der Auftrag sagt es ausdruecklich, und ohne
# diese zwei Zusagen waere "ersetzt" von "danebengestellt" nicht zu
# unterscheiden.
grep -qa '^import wlib$' kernel/user/edit.fi \
    && bad "kernel/user/edit.fi zieht auf einmal wlib herein -- das ist der TERMINAL-Editor" \
    || ok "kernel/user/edit.fi ist unveraendert ein Terminalprogramm (kein wlib)"
grep -qa '/bin/edit' assets/apps/editor.osp/start.txt \
    && ok "assets/apps/editor.osp zeigt weiter auf /bin/edit" \
    || bad "assets/apps/editor.osp zeigt nicht mehr auf /bin/edit"

echo "== 2. die Bibliothek malt nicht an fUi vorbei =="
if bash tools/check-ui.sh > "$OUT/checkui.txt" 2>&1; then
    ok "tools/check-ui.sh: bestanden"
else
    bad "tools/check-ui.sh: gescheitert"; sed -n '1,12p' "$OUT/checkui.txt"
fi

echo "== 3. eine Datei mit 5000 Zeilen =="
lauf gross /gross.fi "$GROSS" ",rollnur=2000,messen=5000"
S="$OUT/gross/serial.txt"
zeilen=$(grep -aoE 'nedit: reiter [0-9]+ zeilen [0-9]+' "$S" | head -1 | grep -oE '[0-9]+$')
num "die Datei ist ganz da (Zeilen)" "${zeilen:-0}" -eq 5001
tipp=$(grep -aoE 'tippen n[0-9]+ ticks [0-9]+ us_je [0-9]+' "$S" | head -1 | grep -oE '[0-9]+$')
roll=$(grep -aoE 'rollen n[0-9]+ ticks [0-9]+ us_je [0-9]+' "$S" | head -1 | grep -oE '[0-9]+$')
echo "        gemessen: tippen ${tipp:-?} us/Taste, rollen ${roll:-?} us/Taste (5001 Zeilen)"

echo "== 4. dasselbe mit ZWOELF Zeilen -- der Vergleich ist die Aussage =="
lauf klein /probe.fi "$KLEIN" ",rollnur=2000,messen=5000"
S2="$OUT/klein/serial.txt"
tipp2=$(grep -aoE 'tippen n[0-9]+ ticks [0-9]+ us_je [0-9]+' "$S2" | head -1 | grep -oE '[0-9]+$')
roll2=$(grep -aoE 'rollen n[0-9]+ ticks [0-9]+ us_je [0-9]+' "$S2" | head -1 | grep -oE '[0-9]+$')
echo "        gemessen: tippen ${tipp2:-?} us/Taste, rollen ${roll2:-?} us/Taste (12 Zeilen)"
# DIE ZUSAGE IST NICHT "schnell", SONDERN "UNABHAENGIG VON DER
# DATEIGROESSE". Eine feste Schranke waere eine Aussage ueber den
# Wirt; das Verhaeltnis ist eine Aussage ueber den Entwurf.
if [ -n "${tipp:-}" ] && [ -n "${tipp2:-}" ]; then
    if [ "$tipp2" -eq 0 ]; then tipp2=1; fi
    v=$(( tipp * 100 / tipp2 ))
    if [ "$v" -le 300 ]; then
        ok "Tippen kostet bei 5001 Zeilen nicht mehr als das Dreifache von 12 Zeilen ($v %)"
    else
        bad "Tippen kostet bei 5001 Zeilen das ${v}-fache (in Prozent) von 12 Zeilen"
    fi
    num "Tippen je Taste unter 2000 us" "$tipp" -lt 2000
else
    bad "die Messzeilen fehlen auf der Leitung"
fi
num "Rollen je Taste unter 2000 us (ohne Anstrich)" "${roll:-999999}" -lt 2000

echo "== 5. zwei Dateien in zwei Reitern =="
d="$OUT/reiter"
bash tools/alltag/build.sh "$d" \
    progs="desktop taskbar nedit sh echo ls cat" accel="${OSUM_ACCEL:-kvm}" \
    shot=yes desk=no kbd=yes warten=5 bloecke=32768 \
    "xfile=/probe.fi=$KLEIN" "xfile=/zwei.sh=$ZWEI" \
    extra="wigapp=/bin/nedit,/probe.fi,/zwei.sh" > "$d.log" 2>&1
S3="$d/serial.txt"
rt=$(grep -aoE 'nedit: reiter [0-9]+' "$S3" | head -1 | grep -oE '[0-9]+$')
num "zwei Reiter offen" "${rt:-0}" -eq 2
[ -s "$d/desktop.png" ] && cp "$d/desktop.png" "$SHOTS/ab-reiter.png"
[ -s "$SHOTS/ab-reiter.png" ] && ok "Bild: zwei Reiter" || bad "Bild: zwei Reiter fehlt"

echo "== 6. Auswahl, Suchen, Ersetzen -- je ein Bild =="
for z in 1 2 3; do
    d="$OUT/zeig$z"
    bash tools/alltag/build.sh "$d" \
        progs="desktop taskbar nedit sh echo ls cat" accel="${OSUM_ACCEL:-kvm}" \
        shot=yes desk=no kbd=yes warten=4 bloecke=32768 \
        "xfile=/probe.fi=$KLEIN" \
        extra="wigapp=/bin/nedit,/probe.fi,zeig=$z" > "$d.log" 2>&1
    [ -s "$d/desktop.png" ] && cp "$d/desktop.png" "$SHOTS/ab-zeig$z.png"
done
# Der Zustand steht auf der Leitung, das Bild daneben.
z1=$(grep -aoE 'nedit: reiter [0-9]+ zeilen [0-9]+ zeile [0-9]+ spalte [0-9]+' \
     "$OUT/zeig1/serial.txt" | tail -1)
z2=$(grep -aoE 'zeile [0-9]+ spalte [0-9]+' "$OUT/zeig2/serial.txt" | tail -1)
z3=$(grep -aoE 'modif [0-9]+' "$OUT/zeig3/serial.txt" | tail -1 | grep -oE '[0-9]+$')
echo "        Auswahl endet bei: $z1"
echo "        Suchtreffer steht bei: $z2"
num "nach dem Ersetzen ist die Datei veraendert" "${z3:-0}" -eq 1

# DIE FARBEN WERDEN GEZAEHLT UND NICHT ANGESEHEN. Ein Bild mit
# Syntaxfarben hat im Textbereich mehr als eine Vordergrundfarbe; eines
# ohne hat genau eine. Gezaehlt wird in dem Rechteck, in dem der Text
# steht.
python3 - "$SHOTS/ab-zeig2.png" > "$OUT/farben.txt" 2>&1 <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
# der Textbereich des Fensters (aus der Geometrie dieser Runde)
aus = im.crop((115, 170, 1020, 430))
zaehl = {}
for p in aus.getdata():
    zaehl[p] = zaehl.get(p, 0) + 1
# Alles, was oft genug vorkommt, um Schrift und nicht Kantenglaettung
# zu sein, und dunkler als der Hintergrund ist.
farben = [c for c, n in zaehl.items() if n > 120 and sum(c) < 600]
print("farben=%d" % len(farben))
for c in sorted(farben, key=lambda c: -zaehl[c])[:8]:
    print("  %s %d" % (str(c), zaehl[c]))
PY
nf=$(grep -aoE '^farben=[0-9]+' "$OUT/farben.txt" | grep -oE '[0-9]+')
num "der Text hat mehr als eine Farbe (Syntaxhervorhebung)" "${nf:-0}" -ge 3
sed -n '2,6p' "$OUT/farben.txt" | sed 's/^/        /'

echo "== 7. Sichern: die Oktette liegen wirklich auf der Platte =="
# DIE EINZIGE ZUSAGE, DIE ZWEI MASCHINEN BRAUCHT.
#
# Dass der Editor "gesichert" auf die Leitung schreibt, ist seine
# eigene Aussage ueber sich selbst. Gemessen ist sie erst, wenn eine
# ZWEITE Maschine dieselbe Platte aufmacht und die geaenderten Oktette
# darin findet -- deshalb `platte=` und `script=cat`.
d="$OUT/sichern"
bash tools/alltag/build.sh "$d" \
    progs="desktop taskbar nedit sh echo ls cat" accel="${OSUM_ACCEL:-kvm}" \
    shot=no desk=no kbd=yes warten=5 bloecke=32768 keep=yes \
    "xfile=/probe.fi=$KLEIN" \
    extra="wigapp=/bin/nedit,/probe.fi,zeig=5" > "$d.log" 2>&1
grep -qa 'nedit: gesichert' "$d/serial.txt" \
    && ok "der Editor meldet, dass er gesichert hat" \
    || bad "der Editor meldet kein Sichern"
mod=$(grep -aoE 'modif [0-9]+' "$d/serial.txt" | tail -1 | grep -oE '[0-9]+$')
num "nach dem Sichern ist das Aenderungszeichen weg" "${mod:-1}" -eq 0
d2="$OUT/nachlesen"
bash tools/alltag/build.sh "$d2" \
    progs="desktop taskbar nedit sh echo ls cat" accel="${OSUM_ACCEL:-kvm}" \
    shot=no platte="$d/disk.img" script="cat /probe.fi" > "$d2.log" 2>&1
if grep -qa 'var TOTAL: u64 = 0' "$d2/serial.txt"; then
    ok "eine ZWEITE Maschine liest die geaenderte Zeile von derselben Platte"
else
    bad "die geaenderte Zeile steht nicht auf der Platte"
    grep -a -A3 'probe.fi --' "$d2/serial.txt" | head -5 | sed 's/^/        /'
fi
# Und der Rest der Datei ist unversehrt -- ein Sichern, das die
# Aenderung schreibt und daneben etwas zerstoert, waere schlimmer als
# keines.
grep -qa 'const TEXT: u64 = 0x1234' "$d2/serial.txt" \
    && ok "der Rest der Datei ist unveraendert" \
    || bad "der Rest der Datei hat gelitten"

echo
echo "GUI-EDITOR: $pass bestanden, $fail gescheitert"
echo "Bilder: $SHOTS"
[ "$fail" -eq 0 ] || exit 1
exit 0
