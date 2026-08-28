#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/paint/run.sh -- RUNDE PAINT: DIE MISCHUNG, DIE KANTE, DER
# SCHATTEN UND DAS SYMBOL -- JEDES MIT SEINEM PREIS.
#
# DIE REGEL DIESER RUNDE, und sie ist die von Runde LOOK mit einer
# Zeile mehr:
#
#     Eine Aussage ueber den Bildschirm ist eine Aussage ueber
#     Bildpunkte, und sie ist nur etwas wert, wenn die Bildpunkte
#     gezaehlt wurden -- UND WENN DANEBENSTEHT, WAS SIE GEKOSTET HABEN.
#     "Sieht besser aus" zaehlt nicht. Takte oder Bildpunkte je Sekunde.
#
# Die Abschnitte:
#
#   1. DIE RECHNUNG. src-over gegen die exakte Rechnung, alle 16 777 216
#      Tripel (a, src, dst). Und die fuenf Fundstellen im Baum
#      gegeneinander -- eine Formel, die an fuenf Stellen steht, steht
#      an vier Stellen falsch, sobald jemand eine davon anfasst.
#   2. DIE KOSTEN. `paintbench` im Kern (Takte je Bildpunkt, opak gegen
#      gemischt, 800x600 und 1024x768) und DIESELBE Rechnung nativ auf
#      dem Wirt. Ohne die zweite Zahl haelt man den Faktor des
#      Emulators fuer den Faktor der Rechnung.
#   3. DIE ZUSAGEN IM KERN. `fb.selftest3`, vierzehn Stueck, auf dem
#      Rahmenpuffer, in den auch gemalt wird.
#   4. DIE KANTENGLAETTUNG DER GLYPHEN. Deckungsstufen je Zeichen und
#      je Kante, und die 4x4-Naeherung gegen 32x32 als Referenz.
#   5. ZWEI RUNDEN AUF DERSELBEN ADRESSE. `tools/paint/scalars.py`
#      rechnet die Skalare jeder Kerneldatei paarweise gegeneinander.
#   6. DIE NUMMERN AN DREI STELLEN. WM_FORM, WM_APP und die
#      Steckplatznummern stehen in kernel/wm.fi, kernel/sys.fi und
#      kernel/user/wlibc.fi. Eine Nummernvergabe, die nicht geprueft
#      wird, laeuft auseinander -- Runde LOOK hat genau so einen Fehler
#      gefunden (SYS_KBD 1780 gegen 1703).
#   7. DAS BILD. Ein Lauf auf `modern` und einer auf `classic`, und aus
#      den Bildpunkten gelesen: der Verlauf des Schattens, die Stufen
#      der Ecke, die Tinte der Symbole in den Knoepfen.
#
# Gegenproben: `classic` MUSS ohne Schatten und mit harter Ecke malen --
# ohne diesen Abschnitt beweist ein gruener Abschnitt 7 nichts, weil
# eine Messung, die immer gruen ist, nichts misst.
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"

PASS=0
FAIL=0
ok()  { echo "  OK    $*"; PASS=$((PASS+1)); }
bad() { echo "  FAIL  $*"; FAIL=$((FAIL+1)); }

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

echo "== 1. die Rechnung: src-over gegen die exakte Rechnung =="
if out=$(python3 tools/paint/blendcheck.py --schnell --quellen 2>&1); then
    echo "$out" | sed 's/^/     /'
    n=$(echo "$out" | grep -c '^  OK')
    PASS=$((PASS+n))
else
    echo "$out" | sed 's/^/     /'
    bad "blendcheck.py ist fehlgeschlagen"
fi

echo "== 2. die Kosten: im Kern und nativ =="
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "PAINT: uebersprungen, qemu-system-x86_64 ist nicht da"
    exit 0
fi
if ! bash tools/build-kernel.sh "$TMPD/k0.mb" > "$TMPD/k.log" 2>&1; then
    bad "der Kernel baut nicht"; sed 's/^/        /' "$TMPD/k.log" | tail -20
    echo "PAINT: $PASS bestanden, $FAIL fehlgeschlagen"; exit 1
fi
ok "der Kernel baut ($(stat -c%s "$TMPD/k0.mb") Oktette)"

lauf() { # zeile ausgabe
    timeout 300 qemu-system-x86_64 -kernel "$TMPD/k0.mb" -m 256 \
        -append "$1" -serial "file:$2" -display none -no-reboot -vga std \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
}
GRUND="nokbd nosched noproc nofs noring3"
lauf "gfx $GRUND" "$TMPD/std.txt"
lauf "gfx fbbig $GRUND" "$TMPD/big.txt"

for f in std big; do
    z=$(grep -a 'paintbench:' "$TMPD/$f.txt" | head -1)
    if [ -n "$z" ]; then
        echo "     $z"
        fa=$(echo "$z" | sed -n 's/.*fill_a=\([0-9]*\) cyc.*/\1/p')
        fi_=$(echo "$z" | sed -n 's/.*fill=\([0-9]*\) cyc.*/\1/p')
        bl=$(echo "$z" | sed -n 's/.* blends=\([0-9]*\).*/\1/p')
        wh=$(echo "$z" | sed -n 's/.*paintbench: \([0-9]*\)x\([0-9]*\).*/\1 \2/p')
        set -- $wh
        px=$(( $1 * $2 ))
        # DIE ZUSAGE UEBER DIE MESSUNG SELBST: es wurden so viele
        # Bildpunkte gemischt, wie die Flaeche hat, mal der Rundenzahl.
        # Waere die Zahl kleiner, haette die Schleife Zeilen
        # uebersprungen und die Zeit waere zu gut.
        if [ "$bl" = "$(( px * 4 ))" ]; then
            ok "$1x$2: $bl gemischte Bildpunkte = $px * 4 Durchgaenge"
        else
            bad "$1x$2: $bl gemischte Bildpunkte, erwartet $(( px * 4 ))"
        fi
        if [ -n "$fa" ] && [ -n "$fi_" ] && [ "$fa" -gt "$fi_" ]; then
            ok "$1x$2: gemischt kostet mehr als opak ($fa gegen $fi_ Takte)"
        else
            bad "$1x$2: die Messung ist nicht plausibel ($fa gegen $fi_)"
        fi
    else
        bad "$f: paintbench hat nichts gemeldet"
    fi
done

if cc -O2 -o "$TMPD/native" tools/paint/native.c 2>"$TMPD/cc.err"; then
    "$TMPD/native" | sed 's/^/     /'
    ok "dieselbe Rechnung nativ gemessen -- der Faktor der Rechnung, "\
"nicht der des Emulators"
else
    bad "tools/paint/native.c uebersetzt nicht"
    sed 's/^/        /' "$TMPD/cc.err" | head -5
fi

echo "== 3. die vierzehn Zusagen im Kern =="
z=$(grep -a 'paint: selftest' "$TMPD/std.txt" | head -1)
echo "     ${z:-(nichts gemeldet)}"
if echo "$z" | grep -q 'gezaehlt=14 of 14'; then
    ok "fb.selftest3: 14 von 14"
else
    bad "fb.selftest3 haelt nicht alle vierzehn Zusagen"
fi
if echo "$z" | grep -q '  ok$'; then
    ok "und der Zaehler der gemischten Bildpunkte stimmt"
else
    bad "der Zaehler der gemischten Bildpunkte stimmt nicht"
fi

echo "== 4. die Kantenglaettung der Glyphen =="
if out=$(python3 tools/paint/aacheck.py 2>&1); then
    echo "$out" | tail -12 | sed 's/^/     /'
    n=$(echo "$out" | grep -c '^  OK')
    PASS=$((PASS+n))
else
    echo "$out" | tail -14 | sed 's/^/     /'
    m=$(echo "$out" | grep -c '^  FAIL')
    n=$(echo "$out" | grep -c '^  OK')
    PASS=$((PASS+n)); FAIL=$((FAIL+m))
fi

echo "== 5. zwei Runden auf derselben Adresse =="
if out=$(python3 tools/paint/scalars.py 2>&1); then
    echo "$out" | tail -2 | sed 's/^/     /'
    ok "keine zwei Skalare einer Kerneldatei liegen aufeinander"
else
    echo "$out" | tail -15 | sed 's/^/     /'
    bad "Skalare ueberschneiden sich"
fi

echo "== 6. dieselben Nummern an drei Stellen =="
# WM_FORM und WM_APP
for n in 2115 2116; do
    grep -qE "= $n( |$)" kernel/sys.fi && ok "Aufrufnummer $n steht in kernel/sys.fi" \
        || bad "Aufrufnummer $n fehlt"
done
grep -q 'const WM_MAXNR: u64 = 2116' kernel/sys.fi \
    && ok "und 2116 ist die hoechste des Fensterservers" \
    || bad "WM_MAXNR passt nicht zu den Aufrufen"
for f in kernel/wm.fi kernel/sys.fi kernel/user/wlibc.fi; do
    a=$(grep -cE '(FM|WF)_RADIUS: u64 = 0' "$f")
    b=$(grep -cE '(FM|WF)_SHADOW_C: u64 = 3' "$f")
    if [ "$a" = 1 ] && [ "$b" = 1 ]; then
        ok "$f numeriert die Formsteckplaetze 0..3 gleich"
    else
        bad "$f numeriert die Formsteckplaetze anders"
    fi
done
sa=$(grep -c 'const WL_BYTES: u64 = 128' kernel/sys.fi)
sb=$(grep -c 'const WL_BYTES: u64 = 128' kernel/user/wlibc.fi)
if [ "$sa" = 1 ] && [ "$sb" = 1 ]; then
    ok "der Satz von WM_LIST ist auf beiden Seiten 128 Oktette lang"
else
    bad "WL_BYTES laeuft zwischen Kern und Bibliothek auseinander"
fi
ka=$(grep -c 'const APP_LEN: u64 = 24' kernel/wm.fi)
kb=$(grep -c 'const APP_LEN: u64 = 24' kernel/user/wlibc.fi)
if [ "$ka" = 1 ] && [ "$kb" = 1 ]; then
    ok "und der Buendelname ist auf beiden Seiten 24 Oktette lang"
else
    bad "APP_LEN laeuft auseinander"
fi

echo "== 7. das Bild: modern gegen classic =="
SH="$TMPD/shots"
if ! LOOKBUILD="$TMPD/build" bash tools/look/shot.sh "$SH/modern" \
        shape=modern scheme=day mode=light > "$TMPD/m.log" 2>&1; then
    bad "der Lauf auf shape=modern ist fehlgeschlagen"
    tail -5 "$TMPD/m.log" | sed 's/^/        /'
else
    ok "shape=modern gebootet und fotografiert"
    if ! LOOKBUILD="$TMPD/build" bash tools/look/shot.sh "$SH/classic" \
            shape=classic scheme=day mode=light > "$TMPD/c.log" 2>&1; then
        bad "der Lauf auf shape=classic ist fehlgeschlagen"
    else
        ok "shape=classic gebootet und fotografiert"
    fi
    # Das Rechteck des Fensters aus dem eigenen Bericht des Servers --
    # nicht aus dem Gedaechtnis. Runde LOOK hat sich das teuer erkauft.
    R=$(grep -a 'wm: win nr=' "$TMPD/m.log" | grep -a 'deco=1' \
        | grep -av 'Terminal' | head -1)
    X=$(echo "$R" | sed -n 's/.* x=\(-\?[0-9]*\) .*/\1/p')
    Y=$(echo "$R" | sed -n 's/.* y=\(-\?[0-9]*\) .*/\1/p')
    OW=$(echo "$R" | sed -n 's/.* ow=\([0-9]*\) .*/\1/p')
    OH=$(echo "$R" | sed -n 's/.* oh=\([0-9]*\) .*/\1/p')
    echo "     das gemessene Fenster: x=$X y=$Y ow=$OW oh=$OH"
    if [ -n "$X" ] && [ -s "$SH/modern/desktop.ppm" ]; then
        if out=$(python3 tools/paint/shadow.py schatten \
                "$SH/modern/desktop.ppm" "$X" "$Y" "$OW" "$OH" 2>&1); then
            echo "$out" | sed 's/^/     /'
            PASS=$((PASS+$(echo "$out" | grep -c '^  OK')))
        else
            echo "$out" | sed 's/^/     /'
            FAIL=$((FAIL+$(echo "$out" | grep -c '^  FAIL')))
        fi
        if out=$(python3 tools/paint/shadow.py ecke \
                "$SH/modern/desktop.ppm" "$X" "$Y" --r 8 2>&1); then
            echo "$out" | tail -3 | sed 's/^/     /'; PASS=$((PASS+1))
        else
            echo "$out" | tail -3 | sed 's/^/     /'; FAIL=$((FAIL+1))
        fi
        # DIE GEGENPROBE. `classic` sagt Radius 0 und Schatten 0, also
        # MUSS dort eine harte Kante stehen. Faellt diese Zusage NICHT
        # durch, misst die vorige nichts.
        if python3 tools/paint/shadow.py ecke "$SH/classic/desktop.ppm" \
                "$X" "$Y" --r 8 >/dev/null 2>&1; then
            bad "GEGENPROBE: classic hat eine geglaettete Ecke -- dann "\
"misst die Messung auf modern nichts"
        else
            ok "GEGENPROBE classic: die Ecke ist hart, wie shape=classic sagt"
        fi
    else
        bad "kein Bild und kein gemeldetes Fenster"
    fi
    # DIE SYMBOLE IN DEN KNOEPFEN, aus dem Bericht der Leiste.
    ns=$(grep -ac 'taskbar: sym btn=' "$TMPD/m.log")
    if [ "$ns" -gt 0 ]; then
        grep -a 'taskbar: sym btn=' "$TMPD/m.log" | sort -u | sed 's/^/     /'
        leer=$(grep -a 'taskbar: sym btn=' "$TMPD/m.log" | grep -c 'ink=0')
        if [ "$leer" = 0 ]; then
            ok "$ns Symbole in Taskleisten-Knoepfen, jedes mit Tinte"
        else
            bad "$leer Symbole ohne einen einzigen eingefaerbten Bildpunkt"
        fi
    else
        bad "die Taskleiste meldet kein einziges Programmsymbol"
    fi
    # UND DASS DAS PROTOKOLL WIRKLICH GESETZT WURDE.
    if grep -aq 'form n=4' "$TMPD/m.log"; then
        ok "die Taskleiste hat alle vier Formwerte an den Server gegeben"
    else
        bad "form_push hat nicht alle vier Werte durchgebracht"
    fi
fi

echo
echo "PAINT: $PASS bestanden, $FAIL fehlgeschlagen"
[ "$FAIL" -eq 0 ]
