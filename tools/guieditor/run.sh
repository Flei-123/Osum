#!/usr/bin/env bash
#
#   bash tools/guieditor/run.sh [arbeitsverzeichnis]
#
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${1:-$(mktemp -d)}
. tools/lib/tmpdir.sh
osum_tmp_guard "${1:-}" "$OUT"
mkdir -p "$OUT"
SHOTS=${GUIEDITOR_SHOTS:-$ROOT/.editor-shots}
mkdir -p "$SHOTS"
export ALLTAGBUILD=${ALLTAGBUILD:-$OUT/build}

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { # name wert vergleich soll
    if [ "$2" "$3" "$4" ] 2>/dev/null; then ok "$1: $2"; else bad "$1: $2, erwartet $3 $4"; fi
}

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "GUI-EDITOR: skipped, qemu-system-x86_64 is not there"; exit 0
fi
python3 -c "import PIL" 2>/dev/null || {
    echo "GUI-EDITOR: uebersprungen, Pillow fehlt"; exit 0; }

KLEIN="$OUT/probe.fi"
GROSS="$OUT/gross.fi"
ZWEI="$OUT/zwei.sh"
cat > "$KLEIN" <<'EOF'
// probe.fi -- eine Testdatei fuer den Editor
fn gruss(name: u64) -> u64 {
    let x: u64 = 42
    var total: u64 = 0
    while total < x {
        total = total + 1   // zaehlen
    }
    return total
}
const TEXT: u64 = 0x1234
// Ende der Probe
EOF
cat > "$ZWEI" <<'EOF'
#!/bin/sh
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

echo "== 1. build: the library, the program and the bundle =="
. tools/lib/firnenv.sh
if "$FIRNC" --profile=app -c kernel/user/nedit.fi \
        -o "$OUT/nedit.o" > "$OUT/e-nedit" 2>&1; then
    ok "kernel/user/nedit.fi uebersetzt"
else
    bad "kernel/user/nedit.fi uebersetzt"; head -12 "$OUT/e-nedit"
fi
rm -f "$OUT/nedit.o"
[ -f assets/apps/editor.osp/INFO ] && ok "the bundle assets/apps/editor.osp is there" \
    || bad "the bundle assets/apps/editor.osp is missing"
if python3 tools/k15/icon.py assets/apps/editor.osp/symbol.txt \
        "$OUT/sym.bin" > /dev/null 2>&1; then
    ok "its icon can be converted into an image"
else
    bad "its icon can be converted into an image"
fi
grep -qa '^import wlib$' kernel/user/edit.fi \
    && bad "kernel/user/edit.fi suddenly pulls in wlib -- that is the TERMINAL editor" \
    || ok "kernel/user/edit.fi is still a terminal program (no wlib)"
grep -qa '^/bin/nedit' assets/apps/editor.osp/start.txt \
    && ok "assets/apps/editor.osp (the merged Editor) starts /bin/nedit" \
    || bad "assets/apps/editor.osp does not start /bin/nedit"
if [ ! -e assets/apps/nedit.osp ] || grep -qx 'menu=hidden' assets/apps/nedit.osp/INFO; then
    ok "no second Editor+ start menu entry (nedit.osp is hidden)"
else
    bad "assets/apps/nedit.osp is back: two Editor entries in the start menu"
fi

echo "== 2. the library does not paint past fUi =="
if bash tools/check-ui.sh > "$OUT/checkui.txt" 2>&1; then
    ok "tools/check-ui.sh: bestanden"
else
    bad "tools/check-ui.sh: gescheitert"; sed -n '1,12p' "$OUT/checkui.txt"
fi

echo "== 3. a file with 5000 lines =="
lauf gross /gross.fi "$GROSS" ",rollnur=2000,messen=5000"
S="$OUT/gross/serial.txt"
zeilen=$(grep -aoE 'nedit: tab [0-9]+ lines [0-9]+' "$S" | head -1 | grep -oE '[0-9]+$')
num "die Datei ist ganz da (Zeilen)" "${zeilen:-0}" -eq 5001
tipp=$(grep -aoE 'tippen n[0-9]+ ticks [0-9]+ us_je [0-9]+' "$S" | head -1 | grep -oE '[0-9]+$')
roll=$(grep -aoE 'rollen n[0-9]+ ticks [0-9]+ us_je [0-9]+' "$S" | head -1 | grep -oE '[0-9]+$')
echo "        gemessen: tippen ${tipp:-?} us/Taste, rollen ${roll:-?} us/Taste (5001 Zeilen)"

echo "== 4. the same with TWELVE lines -- the comparison is the statement =="
lauf klein /probe.fi "$KLEIN" ",rollnur=2000,messen=5000"
S2="$OUT/klein/serial.txt"
tipp2=$(grep -aoE 'tippen n[0-9]+ ticks [0-9]+ us_je [0-9]+' "$S2" | head -1 | grep -oE '[0-9]+$')
roll2=$(grep -aoE 'rollen n[0-9]+ ticks [0-9]+ us_je [0-9]+' "$S2" | head -1 | grep -oE '[0-9]+$')
echo "        gemessen: tippen ${tipp2:-?} us/Taste, rollen ${roll2:-?} us/Taste (12 Zeilen)"
if [ -n "${tipp:-}" ] && [ -n "${tipp2:-}" ]; then
    if [ "$tipp2" -eq 0 ]; then tipp2=1; fi
    v=$(( tipp * 100 / tipp2 ))
    if [ "$v" -le 300 ]; then
        ok "Typing at 5001 lines costs no more than three times 12 lines ($v %)"
    else
        bad "Typing at 5001 lines costs ${v} times (in percent) 12 lines"
    fi
    num "Tippen je Taste unter 2000 us" "$tipp" -lt 2000
else
    bad "the measurement lines are missing on the wire"
fi
num "Rollen je Taste unter 2000 us (ohne Anstrich)" "${roll:-999999}" -lt 2000

echo "== 5. two files in two tabs =="
d="$OUT/reiter"
bash tools/alltag/build.sh "$d" \
    progs="desktop taskbar nedit sh echo ls cat" accel="${OSUM_ACCEL:-kvm}" \
    shot=yes desk=no kbd=yes warten=5 bloecke=32768 \
    "xfile=/probe.fi=$KLEIN" "xfile=/zwei.sh=$ZWEI" \
    extra="wigapp=/bin/nedit,/probe.fi,/zwei.sh" > "$d.log" 2>&1
S3="$d/serial.txt"
rt=$(grep -aoE 'nedit: tab [0-9]+' "$S3" | head -1 | grep -oE '[0-9]+$')
num "zwei Reiter offen" "${rt:-0}" -eq 2
[ -s "$d/desktop.png" ] && cp "$d/desktop.png" "$SHOTS/ab-reiter.png"
[ -s "$SHOTS/ab-reiter.png" ] && ok "Image: two tabs" || bad "Image: two tabs missing"

echo "== 6. selection, search, replace -- one image each =="
for z in 1 2 3; do
    d="$OUT/zeig$z"
    bash tools/alltag/build.sh "$d" \
        progs="desktop taskbar nedit sh echo ls cat" accel="${OSUM_ACCEL:-kvm}" \
        shot=yes desk=no kbd=yes warten=4 bloecke=32768 \
        "xfile=/probe.fi=$KLEIN" \
        extra="wigapp=/bin/nedit,/probe.fi,show=$z" > "$d.log" 2>&1
    [ -s "$d/desktop.png" ] && cp "$d/desktop.png" "$SHOTS/ab-zeig$z.png"
done
z1=$(grep -aoE 'nedit: tab [0-9]+ lines [0-9]+ line [0-9]+ col [0-9]+' \
     "$OUT/zeig1/serial.txt" | tail -1)
z2=$(grep -aoE 'line [0-9]+ col [0-9]+' "$OUT/zeig2/serial.txt" | tail -1)
z3=$(grep -aoE 'modif [0-9]+' "$OUT/zeig3/serial.txt" | tail -1 | grep -oE '[0-9]+$')
echo "        selection ends at: $z1"
echo "        search hit is at: $z2"
num "nach dem Ersetzen ist die Datei veraendert" "${z3:-0}" -eq 1

python3 - "$SHOTS/ab-zeig2.png" > "$OUT/farben.txt" 2>&1 <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
aus = im.crop((115, 170, 1020, 430))
zaehl = {}
for p in aus.getdata():
    zaehl[p] = zaehl.get(p, 0) + 1
farben = [c for c, n in zaehl.items() if n > 120 and sum(c) < 600]
print("farben=%d" % len(farben))
for c in sorted(farben, key=lambda c: -zaehl[c])[:8]:
    print("  %s %d" % (str(c), zaehl[c]))
PY
nf=$(grep -aoE '^farben=[0-9]+' "$OUT/farben.txt" | grep -oE '[0-9]+')
num "der Text hat mehr als eine Farbe (Syntaxhervorhebung)" "${nf:-0}" -ge 3
sed -n '2,6p' "$OUT/farben.txt" | sed 's/^/        /'

echo "== 7. save: the bytes really are on the disk =="
#
d="$OUT/sichern"
bash tools/alltag/build.sh "$d" \
    progs="desktop taskbar nedit sh echo ls cat" accel="${OSUM_ACCEL:-kvm}" \
    shot=no desk=no kbd=yes warten=5 bloecke=32768 keep=yes \
    "xfile=/probe.fi=$KLEIN" \
    extra="wigapp=/bin/nedit,/probe.fi,show=5" > "$d.log" 2>&1
grep -qa 'nedit: saved' "$d/serial.txt" \
    && ok "the editor reports that it saved" \
    || bad "the editor reports no save"
mod=$(grep -aoE 'modif [0-9]+' "$d/serial.txt" | tail -1 | grep -oE '[0-9]+$')
num "nach dem Sichern ist das Aenderungszeichen weg" "${mod:-1}" -eq 0
d2="$OUT/nachlesen"
bash tools/alltag/build.sh "$d2" \
    progs="desktop taskbar nedit sh echo ls cat" accel="${OSUM_ACCEL:-kvm}" \
    shot=no platte="$d/disk.img" script="cat /probe.fi" > "$d2.log" 2>&1
if grep -qa 'var TOTAL: u64 = 0' "$d2/serial.txt"; then
    ok "a SECOND machine reads the changed line from the same disk"
else
    bad "the changed line is not on the disk"
    grep -a -A3 'probe.fi --' "$d2/serial.txt" | head -5 | sed 's/^/        /'
fi
grep -qa 'const TEXT: u64 = 0x1234' "$d2/serial.txt" \
    && ok "the rest of the file is unchanged" \
    || bad "the rest of the file was damaged"

echo
echo "GUI-EDITOR: $pass bestanden, $fail gescheitert"
echo "Bilder: $SHOTS"
[ "$fail" -eq 0 ] || exit 1
exit 0
