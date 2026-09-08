#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/vsync/run.sh -- DIE ABNAHME DER RUNDE VSYNC.
#
# Zwei Zusagen, und beide werden hier gemessen und nicht behauptet:
#
#   1. KEIN REISSEN. Beim Bewegen und Neuzeichnen darf auf dem Schirm
#      nie eine halbe Bildseite stehen.
#   2. FENSTER BEWEGEN SICH. Oeffnen und Schliessen skalieren und
#      mischen ueber MOTION_DEF = 120 ms, statt zu springen.
#
# WARUM DIE ZERREISSPROBE SO AUSSIEHT, WIE SIE AUSSIEHT.
#
# Reissen ist unter QEMU nicht zu fotografieren: `screendump` liest die
# Bildflaeche in EINEM Zug, waehrend niemand schreibt, und ein halb
# uebertragenes Bild sieht darin aus wie ein ganzes. GEMESSEN: eine
# Bildserie waehrend eines Zuges fand mit ausdruecklich ABGESCHALTETER
# Bildgrenze (`nopresent`) NULL zerrissene Bilder. Eine Messung, die
# auch dann gruen bleibt, wenn die Zusage abgeschaltet ist, misst nichts.
#
# Also wird die Frage dort gestellt, wo sie beantwortbar ist: im Kern.
# Der Server faerbt im Signaturbetrieb (`wmsig`) einen Streifen oben und
# einen unten an jedem Fenster mit einer Farbe, die aus der Bildnummer
# faellt. Ein ZWEITER KERN liest waehrenddessen den VORDERPUFFER --
# genau das, was ein Bildschirm tut -- und vergleicht die beiden
# Signaturen. Verschieden heisst: halb uebertragen, also Reissen.
#
# Und gemessen wird am STEHENDEN Fenster (`wmruhe`), das trotzdem in
# jedem Takt neu gemalt wird. Ein GEZOGENES Fenster waere das falsche
# Ziel: der Ableser rechnet seine zwei Punkte aus dem Ort des Fensters,
# und waehrend eines Zuges aendert der sich zwischen den Ablesungen --
# was er dann findet, ist eine Eigenschaft der Messung und nicht des
# Bildes (gemessen: 97 Prozent "Risse", waehrend dasselbe Bild im
# Stehen null ergab).
#
# Die drei Stufen, und jede beantwortet eine eigene Frage:
#
#   nopresent noflip   ohne alles          -> es MUSS reissen
#   vsync noflip       nur sammeln         -> es reisst WEITER
#   vsync flip         Seitenumschaltung   -> NULL
#
# Die mittlere Zeile ist die wichtigste der Runde: das Sammeln allein
# senkt nur die Zahl der Gelegenheiten, es beseitigt das Reissen NICHT.
# Erst der Seitenwechsel tut es, und nur der.
set -u

cd "$(dirname "$0")/../.." || exit 1
. tools/lib/qemu.sh

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok() { echo "    ok  -- $1"; pass=$((pass + 1)); }
bad() { echo "    NICHT -- $1"; fail=$((fail + 1)); }
zahl() { grep -aoE "$2" "$1" 2>/dev/null | tail -1 | grep -oE '[0-9]+' | tail -1; }

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || {
    echo "vendor/firn/fetch-firnc.sh fehlgeschlagen"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "VSYNC: skipped, qemu-system-x86_64 ist nicht da"
    exit 0
fi

echo "== 1. bauen =="
if bash tools/build-kernel.sh "$TMPD/k.mb" > "$TMPD/b.log" 2>&1; then
    ok "Kernel gebaut ($(stat -c%s "$TMPD/k.mb") Oktette)"
else
    bad "der Kernel laesst sich nicht bauen"
    sed 's/^/        /' "$TMPD/b.log" | head -12
    echo "VSYNC: $pass passed, $fail failed"; exit 1
fi
K="$TMPD/k.mb"

# Das Abbild mit den Schriften -- ohne sie gibt es keine Fenster.
python3 tools/osum/mkfs.py build "$TMPD/disk.img" 4096 /lib/ \
    /lib/mono.ttf=assets/osum-mono.ttf /lib/sans.ttf=assets/osum-sans.ttf \
    > "$TMPD/mkfs.txt" 2>&1 \
    && ok "Abbild mit beiden Schriften gebaut" \
    || { bad "mkfs.py fehlgeschlagen"; sed 's/^/        /' "$TMPD/mkfs.txt"; }

GRUND="nokbd noproc nofs"

# Ein Lauf mit zwei Kernen: einer malt, einer liest ab.
ruhe() { # extra ausgabe [sekunden]
    local extra=$1 aus=$2 sek=${3:-6}
    cp -f "$TMPD/disk.img" "$TMPD/live.img"
    timeout 150 $QEMU_X86 -smp 2 -kernel "$K" -m 256 \
        -append "gfx wm wmhold wmsig wmruhe wighalt=$sek $extra $GRUND" \
        -serial "file:$aus" -display none -no-reboot \
        -vga std -global VGA.edid=off \
        -drive "file=$TMPD/live.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    return 0
}

echo "== 2. die Zerreissprobe: drei Stufen =="
ruhe "nopresent noflip" "$TMPD/r0.txt"
R0=$(zahl "$TMPD/r0.txt" 'risse=[0-9]+')
L0=$(zahl "$TMPD/r0.txt" 'liest=[0-9]+')
ruhe "vsync noflip" "$TMPD/r1.txt"
R1=$(zahl "$TMPD/r1.txt" 'risse=[0-9]+')
L1=$(zahl "$TMPD/r1.txt" 'liest=[0-9]+')
C1=$(zahl "$TMPD/r1.txt" 'comp=[0-9]+')
P1=$(zahl "$TMPD/r1.txt" 'pres=[0-9]+')
ruhe "vsync flip" "$TMPD/r2.txt"
R2=$(zahl "$TMPD/r2.txt" 'risse=[0-9]+')
L2=$(zahl "$TMPD/r2.txt" 'liest=[0-9]+')
F2=$(zahl "$TMPD/r2.txt" 'flips=[0-9]+')
FL=$(zahl "$TMPD/r2.txt" 'flip=[0-9]+')

echo "        ohne alles      liest=${L0:-?}  risse=${R0:-?}"
echo "        nur sammeln     liest=${L1:-?}  risse=${R1:-?}  comp=${C1:-?} pres=${P1:-?}"
echo "        + Seitenwechsel liest=${L2:-?}  risse=${R2:-?}  flips=${F2:-?}"

# Die Gegenprobe MUSS anschlagen -- sonst misst der Ableser nichts.
[ "${R0:-0}" -gt 0 ] 2>/dev/null \
    && ok "ohne Bildgrenze reisst es ($R0 zerrissene Ablesungen) -- die Probe kann anschlagen" \
    || bad "ohne Bildgrenze KEIN Riss gefunden -- die Zerreissprobe misst nichts"

[ "${L2:-0}" -gt 50000 ] 2>/dev/null \
    && ok "der Ableser hat dicht gelesen ($L2 Ablesungen)" \
    || bad "zu wenige Ablesungen ($L2) -- die Probe traefe die Uebertragung nicht"

# Das Sammeln allein reicht NICHT. Das ist ein BEFUND und keine Panne;
# er steht hier als Zusage, damit niemand die Seitenumschaltung fuer
# entbehrlich haelt.
[ "${R1:-0}" -gt 0 ] 2>/dev/null \
    && ok "Sammeln allein beseitigt das Reissen NICHT ($R1) -- der Seitenwechsel ist noetig" \
    || echo "    hinweis -- Sammeln allein ergab risse=$R1 (auf dieser Maschine)"

# Und die eigentliche Zusage.
if [ "${FL:-0}" = "1" ]; then
    [ "${R2:-1}" -eq 0 ] 2>/dev/null \
        && ok "MIT Seitenwechsel: 0 Risse in $L2 Ablesungen" \
        || bad "mit Seitenwechsel immer noch $R2 Risse"
else
    bad "die Seitenumschaltung kam nicht zustande (flip=$FL)"
fi

echo "== 3. die Bildzeit bleibt unter 16 ms =="
for RES in 1280x800 1920x1080; do
    cp -f "$TMPD/disk.img" "$TMPD/live.img"
    timeout 150 $QEMU_X86 -kernel "$K" -m 512 \
        -append "gfx wm wmhold vsync flip fbres=$RES wighalt=3 $GRUND" \
        -serial "file:$TMPD/res.txt" -display none -no-reboot \
        -vga std -global VGA.edid=off \
        -drive "file=$TMPD/live.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    US=$(grep -a 'wmbench2: compose full=' "$TMPD/res.txt" \
        | tail -1 | grep -oE 'full=[0-9]+' | grep -oE '[0-9]+')
    FLP=$(zahl "$TMPD/res.txt" 'flip=[0-9]+')
    if [ -n "$US" ] && [ "$US" -lt 16000 ] 2>/dev/null; then
        ok "$RES: ein Vollbild in ${US} us (Budget 16000), flip=$FLP"
    else
        bad "$RES: Vollbild ${US:-?} us"
    fi
done

echo "== 4. die Fensterbewegung =="
# Ein Fenster geht auf und wieder zu, und die Zwischenwerte werden
# gezaehlt. `noanim` ist die Gegenprobe: derselbe Endzustand, aber
# ohne ein einziges Zwischenbild.
lauf_anim() { # extra ausgabe
    cp -f "$TMPD/disk.img" "$TMPD/live.img"
    timeout 150 $QEMU_X86 -kernel "$K" -m 256 \
        -append "gfx wm wmhold wmanim vsync flip wighalt=6 $1 $GRUND" \
        -serial "file:$2" -display none -no-reboot \
        -vga std -global VGA.edid=off \
        -drive "file=$TMPD/live.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
}
lauf_anim "" "$TMPD/a1.txt"
A1=$(zahl "$TMPD/a1.txt" 'anim=[0-9]+')
FR1=$(zahl "$TMPD/a1.txt" 'frames=[0-9]+')
lauf_anim "noanim" "$TMPD/a0.txt"
A0=$(zahl "$TMPD/a0.txt" 'anim=[0-9]+')
FR0=$(zahl "$TMPD/a0.txt" 'frames=[0-9]+')
W0=$(grep -a 'wm: wins n=' "$TMPD/a0.txt" | tail -1)

echo "        mit Bewegung  anim=${A1:-?} frames=${FR1:-?}"
echo "        ohne (noanim) anim=${A0:-?} frames=${FR0:-?}"

[ "${A1:-0}" -ge 2 ] 2>/dev/null \
    && ok "zwei Bewegungen gelaufen (Oeffnen und Schliessen)" \
    || bad "es gab keine zwei Bewegungen (anim=$A1)"
# Bei 120 ms und TICK_HZ=100 sind ~12 Zwischenbilder je Bewegung zu
# erwarten. Unter 10 waere ein Sprung mit Anlauf.
[ "${FR1:-0}" -ge 10 ] 2>/dev/null \
    && ok "$FR1 Zwischenbilder -- die Bewegung hat wirklich Stufen" \
    || bad "nur ${FR1:-0} Zwischenbilder -- das ist ein Sprung"
[ "${FR0:-1}" -eq 0 ] 2>/dev/null \
    && ok "GEGENPROBE noanim: kein einziges Zwischenbild" \
    || bad "mit noanim gab es trotzdem $FR0 Zwischenbilder"
echo "$W0" | grep -q 'n=1' \
    && ok "GEGENPROBE noanim: derselbe Endzustand ($W0)" \
    || bad "mit noanim endet es anders: $W0"

echo "== 5. die Sparsamkeit der Runde UHRWERK bleibt =="
# Ohne Eingabe darf der Server NICHT mehr zeichnen als vorher. Die
# Bildgrenze sammelt; sie darf nichts zusaetzlich anstossen.
cp -f "$TMPD/disk.img" "$TMPD/live.img"
timeout 150 $QEMU_X86 -kernel "$K" -m 256 \
    -append "gfx wm wmhold wighalt=10 $GRUND" \
    -serial "file:$TMPD/u.txt" -display none -no-reboot \
    -vga std -global VGA.edid=off \
    -drive "file=$TMPD/live.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
UC=$(zahl "$TMPD/u.txt" 'comp=[0-9]+')
UH=$(zahl "$TMPD/u.txt" 'halt=[0-9]+')
UP=$(grep -a 'wm: composites=' "$TMPD/u.txt" | tail -1)
if [ -n "$UC" ] && [ -n "$UH" ] && [ "$UH" -gt 0 ] 2>/dev/null; then
    RATE=$((UC / UH))
    [ "$RATE" -le 20 ] \
        && ok "ohne Eingabe ${RATE} Zeichnungen je Sekunde ($UC in ${UH}s) -- sparsam wie vorher" \
        || bad "ohne Eingabe ${RATE}/s -- die Sparsamkeit ist dahin"
else
    bad "die Rate liess sich nicht ablesen"
fi
echo "        $UP"

echo "== 6. die Gegenprobe: ohne die Woerter aendert sich nichts =="
# Derselbe Kernel OHNE `vsync` muss sich verhalten wie vor der Runde:
# sofort uebertragen, kein Sammeln, keine Bewegung.
V0=$(zahl "$TMPD/u.txt" 'vsync=[0-9]+')
P0=$(zahl "$TMPD/u.txt" 'pres=[0-9]+')
[ "${V0:-1}" -eq 0 ] 2>/dev/null && [ "${P0:-1}" -eq 0 ] 2>/dev/null \
    && ok "ohne das Wort vsync: keine Bildgrenze, keine Uebertragung ueber sie (vsync=$V0 pres=$P0)" \
    || bad "ohne das Wort war die Bildgrenze trotzdem an (vsync=$V0 pres=$P0)"

echo "VSYNC: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
