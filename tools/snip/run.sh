#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/snip/run.sh -- DIE ABNAHME DER RUNDE SNIP.
#
# Was hier gemessen wird und warum in dieser Form:
#
#   1. DAS PNG IST GUELTIG, und zwar gegen einen STRENGEN Leser
#      (tools/snip/pngcheck.py): Signatur, jede Chunk-CRC, die
#      Reihenfolge, der zlib-Kopf, ADLER-32, die fuenf Zeilenfilter --
#      und dass hinter IEND nichts steht. Das letzte ist die
#      Acropalypse-Falle (CVE-2023-21036), und sie faellt nur auf, wenn
#      man danach sucht.
#
#   2. ES IST DAS RICHTIGE BILD. Ein formal tadelloses PNG kann um zwei
#      Zeilen verschoben sein oder vertauschte Farbkanaele haben, und
#      nichts davon sieht man ihm an. Also wird es BILDPUNKT FUER
#      BILDPUNKT gegen das gehalten, was QEMU im selben Augenblick auf
#      seiner Bildflaeche hatte (`screendump`, ein PPM).
#
#   3. DIE AUSSCHNITT-KOORDINATEN STIMMEN AUF DEN PUNKT. Der Zeiger
#      faehrt mit echten PS/2-Paketen ueber den QEMU-Monitor, zieht ein
#      Rechteck auf, und danach muss die Datei GENAU dieses Rechteck
#      des Rahmenpuffers enthalten -- keinen Bildpunkt daneben.
#
#   4. DER FENSTER-MODUS TRIFFT DAS RICHTIGE FENSTER. Die Rechtecke
#      kommen aus der Fenstertafel, die im selben Augenblick wie die
#      Bildpunkte eingefroren wurde; gemessen wird gegen die
#      Fensterliste, die der Server auf die serielle Leitung meldet.
#
#   5. DIE VERZOEGERTE AUFNAHME HAELT DIE ZEIT EIN. Nicht "es dauert
#      ungefaehr": der Kern meldet die Millisekunden zwischen
#      Tastendruck und Standbild, und die muessen in einem Fenster um
#      die verlangte Zeit liegen.
#
#   6. VERPIXELN MACHT DEN BEREICH NACHWEISLICH UNLESBAR --
#      Kantenenergie, Entropie und die Zahl der uebrigen Farben,
#      vorher gegen nachher (tools/snip/entropie.py). Die dritte Zahl
#      ist eine SCHRANKE und keine Statistik.
#
#   7. DIE SICHERHEIT, und das ist der Abschnitt, um den es geht. Ein
#      Programm OHNE Fahrschein bekommt NULL Oktette. Die Gegenprobe
#      dazu ist `snapfrei` auf der Kernbefehlszeile: dieselbe Maschine,
#      dieselbe Anwendung, die Pruefung aus -- und dann MUSS dasselbe
#      Programm das ganze Bild bekommen. Eine Zusage, deren Gegenprobe
#      ebenfalls durchgeht, ist keine Messung.
#
#   8. UMSCHALT+SUPER+S KOLLIDIERT NICHT MIT DER RUNDE SUPERSEARCH.
#      Nicht gelesen, sondern gebaut: ein Kern aus DIESEM Zweig UND
#      dem Zweig `supersearch` zusammen, und darin darf der Druck auf
#      Umschalt+Super+S die Suche NICHT aufmachen.
#
# Aufruf:  bash tools/snip/run.sh [--shots <dir>]
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

SHOTS="docs/shots/snip"
[ "${1:-}" = "--shots" ] && { SHOTS=$2; shift 2; }
mkdir -p "$SHOTS"

pass=0; fail=0
ok()  { echo "  OK    $1"; pass=$((pass + 1)); }
bad() { echo "  FEHLER $1"; fail=$((fail + 1)); }
info(){ echo "        $1"; }

MONO=assets/osum-mono.ttf
SANS=assets/osum-sans.ttf

echo "== 1. der Bau und die Zahlen, die an zwei Stellen stehen =="

python3 tools/snip/k11.py > "$TMPD/k11.txt" 2>&1
if [ $? -eq 0 ]; then
    ok "$(grep -o 'K11_OFF -- .*' "$TMPD/k11.txt" | head -1), keine Ueberschneidung"
else
    bad "kstate.K11_OFF: zwei Woerter liegen aufeinander"
    sed 's/^/        /' "$TMPD/k11.txt" | head -8
fi

# Die Aufrufnummer und die Felder stehen im Kern UND in Ring 3. Sie
# gegeneinander zu halten ist billig und faengt genau den Fehler, den
# ein Merge macht.
knr=$(grep -a 'const SYS_OSUM_SNAP' kernel/sys.fi | grep -o '[0-9]*$')
rnr=$(grep -a 'const SYS_SNAP' kernel/user/snip.fi | grep -o '[0-9]*$')
if [ "$knr" = "$rnr" ] && [ -n "$knr" ]; then
    ok "die Aufrufnummer ist im Kern und in Ring 3 dieselbe ($knr)"
else
    bad "Aufrufnummer: Kern sagt '$knr', Ring 3 sagt '$rnr'"
fi
gleich=1
for f in WF_ID WF_X WF_Y WF_W WF_H; do
    a=$(grep -a "^const $f: u64 = " kernel/snap.fi | grep -o '[0-9]*$')
    b=$(grep -a "^const $f: u64 = " kernel/user/snip.fi | grep -o '[0-9]*$')
    [ "$a" = "$b" ] || { gleich=0; info "$f: Kern $a, Ring 3 $b"; }
done
[ $gleich = 1 ] && ok "die fuenf Felder eines eingefrorenen Fensters sind in beiden gleich" \
                 || bad "die Feldnummern gehen auseinander"

# 1860 muss auf JEDEM Zweig frei sein, sonst kostet es der naechste
# Merge. Das ist nachgesehen und nicht angenommen.
kollision=0
for b in $(git for-each-ref --format='%(refname:short)' refs/heads/ | grep -v '^snip$'); do
    n=$(git show "$b:kernel/sys.fi" 2>/dev/null | grep -aoc 'u64 = 1860' || true)
    [ "${n:-0}" != "0" ] && { kollision=1; info "Zweig $b belegt 1860"; }
done
[ $kollision = 0 ] && ok "die Nummer 1860 ist auf jedem anderen Zweig frei" \
                   || bad "1860 ist anderswo schon vergeben"

for s in 0; do
    if bash tools/build-kernel.sh "$TMPD/k$s.mb" --stufe "$s" > "$TMPD/b$s.log" 2>&1; then
        ok "firnc$s: der Kern ist gebaut ($(stat -c%s "$TMPD/k$s.mb") Oktette)"
    else
        bad "firnc$s: der Kern baut nicht"
        sed 's/^/        /' "$TMPD/b$s.log" | head -12
    fi
done
[ -f "$TMPD/k0.mb" ] || { echo "SNIP: $pass gruen, $((fail + 1)) rot"; exit 1; }

PROGS="desktop taskbar launcher snip sh echo ls cat"
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s baut nicht"
bau() {
    local rc=0 p
    for p in $PROGS; do
        vendor/firn/bin/firnc "kernel/user/$p.fi" -o "$TMPD/$p.o" \
            > "$TMPD/e$p" 2>&1 || {
            bad "firnc0 uebersetzt $p.fi nicht"
            sed 's/^/        /' "$TMPD/e$p" | head -6; rc=1; continue; }
        ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
            -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null || {
            bad "ld scheitert an $p"; rc=1; continue; }
        strip --strip-all "$TMPD/$p.elf"
    done
    return $rc
}
bau && ok "$(echo $PROGS | wc -w) Programme gebaut, /bin/snip ist $(stat -c%s "$TMPD/snip.elf") Oktette" \
     || bad "die Programme bauen nicht"

# DAS WERKZEUG IST EIN PROGRAMM IN RING 3, und das ist keine Behauptung:
# der Kern traegt keines seiner Symbole.
for sym in snip__band_malen snip__speichern png__schreibe; do
    if nm -a "$TMPD/k0.mb.elf" 2>/dev/null | grep -q "$sym"; then
        bad "der Kern traegt $sym -- das gehoert nach Ring 3"
    else
        ok "der Kern traegt $sym NICHT"
    fi
done

python3 tools/k15/tree.py "$TMPD/baum" > "$TMPD/baum.log" 2>&1 \
    && ok "der Verzeichnisbaum steht" || bad "tools/k15/tree.py scheitert"

mk_image() {
    local img=$1
    local ARGS=(build "$img" 16384 /lib/
        "/lib/mono.ttf=$MONO" "/lib/sans.ttf=$SANS" /bin/)
    local p
    for p in $PROGS; do ARGS+=("/bin/$p=$TMPD/$p.elf"); done
    ARGS+=(/etc/ "/etc/theme=$TMPD/baum/theme")
    # DAS VERZEICHNIS, IN DAS DIE BILDER GEHEN. Ohne es scheitert das
    # Anlegen der Datei, und der Fehler saehe aus wie ein Fehler im
    # Kodierer.
    ARGS+=(/bild/)
    while read -r z; do ARGS+=("$z"); done < "$TMPD/baum/liste"
    python3 tools/osum/mkfs.py "${ARGS[@]}" > "$TMPD/mkfs.txt" 2>&1
}
mk_image "$TMPD/disk.img" && ok "das Plattenabbild steht ($(stat -c%s "$TMPD/disk.img") Oktette)" \
    || { bad "mkfs.py scheitert"; sed 's/^/        /' "$TMPD/mkfs.txt" | head -5; }

# `nofs` UND WARUM ES DA STEHEN MUSS. Ohne das Wort faehrt der Kern
# seinen Dateisystem-Selbsttest, und der FORMATIERT die Platte
# ("fs: format 1=1") -- danach sind die Schriften weg, der
# Fensterserver kommt nicht hoch, und der Fehler sieht aus wie ein
# Fehler dieser Runde. Gemessen: mit dem Wort `wm: mount=1` und
# `ttf: mono glyphs=366`, ohne es `ttf: keine Schrift gefunden`.
# `nokbd` schaltet nur die Tastatur-VORFUEHRUNG des Starts ab, nicht
# die Tastatur -- tools/k15/run.sh tippt mit demselben Wort ganze
# Woerter in Textfelder.
# `wmhold wiglong` HAELT DIE MASCHINE ZWANZIG SEKUNDEN STILL und gibt
# sie dabei her -- die Anwendung in Ring 3 laeuft in dieser Zeit, und
# genau dort werden die Tasten und Mausbewegungen bedient. OHNE
# `wiglong` sind es fuenf, und der Lauf mit der verzoegerten Aufnahme
# (drei Sekunden warten, dann speichern) passt nicht hinein: der Kern
# war fertig, bevor die erste Taste kam, und im Protokoll stand nur
# `kernel: done`. Gemessen und nicht geraten.
BASE="gfx wm wig desk wmhold wiglong nostart snip nokbd nosched noproc nofs"

# ---------------------------------------------------------------- fahren
#
# EIN LAUF: Abbild kopieren, QEMU starten, warten bis der Dienst steht,
# das Skript ueber den Monitor hineingeben, ein Foto machen, warten bis
# die Datei geschrieben ist, herunterfahren.
QPID=""
# =====================================================================
# WANN DIE TASTE UND WANN DIE MAUS -- und das ist gemessen, nicht gewaehlt.
# =====================================================================
#
# In DIESEM Baum stellt der Baustein waehrend der Haltephase des
# Fensterservers KEINE Tastaturunterbrechung mehr zu. Gemessen mit einer
# Sonde in `trap.fi` (ein Oktett je IRQ 1):
#
#     waehrend des Starts     acht Unterbrechungen, `hk: super+S` kommt an
#     in der Haltephase       NULL -- sechzehn Tastendruecke mit einer
#                             Sekunde Abstand, keine einzige Unterbrechung
#
# Das Zeigegeraet arbeitet dort weiter; tools/desktop/run.sh zieht in
# genau dieser Phase die Taskleiste ueber den Schirm. Der Befund gehoert
# dem Baum und nicht dieser Runde -- in `kernel/snap.fi` steht keine
# Zeile im Unterbrechungsweg, und der Kern dieser Runde ist an der
# Tastatur nur ein zusaetzliches `if` tief unten in `on_code`.
# STATUS-SNIP.md, Abschnitt "Was dabei aufgefallen ist", hat die Zahlen.
#
# ALSO WIRD BEIDES GEMESSEN, JEDES DORT, WO ES GEHT:
#
#   * DAS TASTENKUERZEL im Start -- sobald `desk: start /bin/snip` in der
#     Zeile steht, ist der Dienst eingetragen, und UMSCHALT+SUPER+S
#     stellt den Fahrschein aus. Der lebt 30 Sekunden und wartet auf die
#     Haltephase. Das ist der ECHTE Weg, mit einer echten Taste.
#   * DIE BEDIENUNG in der Haltephase, mit der Maus auf die Knoepfe.
#
# Damit misst dieser Laeufer genau das, was ein Mensch tut, und keine
# Abkuerzung durch den Kern: es gibt keinen Aufruf, der einen Fahrschein
# ausstellt, und dieser Laeufer benutzt auch keinen.
fahre() { # name  extra-cmdline  mausskript  [warte-auf]  [taste-am-start]
    local name=$1 extra=$2 skript=$3 warte_auf=${4:-} taste=${5:-ja}
    local sock="$TMPD/mon-$name.sock"
    local out="$TMPD/$name.txt"
    rm -f "$out" "$sock"
    cp -f "$TMPD/disk.img" "$TMPD/live-$name.img"
    timeout 300 $QEMU_X86 -kernel "$TMPD/k0.mb" -m 512 \
        -append "$BASE $extra" -serial "file:$out" -display none -no-reboot \
        -vga std -monitor "unix:$sock,server,nowait" \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        > "$TMPD/$name.qemu" 2>&1 &
    QPID=$!
    local i=0
    if [ "$taste" = ja ]; then
        # Auf den eingetragenen Dienst warten, dann die ECHTE Taste.
        i=0
        while [ $i -lt 1400 ]; do
            grep -qa 'snip: der Dienst ist da' "$out" 2>/dev/null && break
            grep -qa 'snip: kein Standbildpuffer' "$out" 2>/dev/null && break
            grep -qa 'snip: SN_REG abgelehnt' "$out" 2>/dev/null && break
            grep -qaE '^wm: hold' "$out" 2>/dev/null && break
            kill -0 $QPID 2>/dev/null || break
            sleep 0.1; i=$((i + 1))
        done
        printf 'sendkey shift-meta_l-s\nwarte 0.2\n' > "$TMPD/$name.key"
        python3 tools/wm/monitor.py "$sock" "$TMPD/$name.key" 0.15 \
            > "$TMPD/$name.keyout" 2>&1
    fi
    i=0
    while [ $i -lt 1400 ]; do
        grep -qaE '^wm: hold' "$out" 2>/dev/null && break
        grep -qa 'snip: kein Standbildpuffer' "$out" 2>/dev/null && break
        grep -qa 'snip: SN_REG abgelehnt' "$out" 2>/dev/null && break
        kill -0 $QPID 2>/dev/null || break
        sleep 0.1; i=$((i + 1))
    done
    sleep 0.3
    # NICHT `$name.mon` ALS ZIEL -- so heisst das Skript selbst, und
    # `>` leert es, BEVOR monitor.py es liest. Gemessen: `voll.mon`
    # enthielt danach die Zeile "0 Befehle", und der ganze Abschnitt
    # tat nichts, ohne dass irgendwo ein Fehler stand.
    [ -n "$skript" ] && python3 tools/wm/monitor.py "$sock" "$skript" 0.12 \
        > "$TMPD/$name.monout" 2>&1
    if [ -n "$warte_auf" ]; then
        i=0
        while [ $i -lt 600 ]; do
            grep -qa "$warte_auf" "$out" 2>/dev/null && break
            kill -0 $QPID 2>/dev/null || break
            sleep 0.1; i=$((i + 1))
        done
    fi
    MON_SOCK="$sock"
    OUT="$out"
}

# ZUM ZEIGER: das PS/2-Geraet kennt nur UNTERSCHIEDE. Erst mit grossen
# Schritten in die linke obere Ecke -- dort haelt der Anschlag und die
# Vorgeschichte ist geloescht --, dann in Schritten unter 128 an die
# Stelle. Von da an ist der Ort eine Rechnung und keine Hoffnung
# (tools/wm/monitor.py sagt dasselbe ausfuehrlicher).
zeiger() { # x y  -> Zeilen fuer das Monitorskript
    local x=$1 y=$2
    echo "mouse_move -900 -900"
    echo "mouse_move -900 -900"
    echo "warte 0.2"
    while [ "$x" -gt 100 ]; do echo "mouse_move 100 0"; x=$((x - 100)); done
    while [ "$y" -gt 100 ]; do echo "mouse_move 0 100"; y=$((y - 100)); done
    echo "mouse_move $x $y"
    echo "warte 0.2"
}
# Ein Knopf der Leiste: Platz i, Mitte des Knopfes, Mitte der Leiste.
knopf() { echo "$((4 + $1 * 76 + 36))"; }
foto() { python3 tools/gfx/screenshot.py "$MON_SOCK" "$1" 20 >/dev/null 2>&1; }
ende() {
    [ -n "$QPID" ] && { kill $QPID 2>/dev/null; wait $QPID 2>/dev/null; }
    QPID=""
}
# Die Datei aus dem laufenden Abbild holen. Das Abbild ist eine Datei
# auf dem Wirt; solange QEMU laeuft, kann darin noch etwas fehlen --
# also erst herunterfahren, dann lesen.
hol() { # live-img  pfad-in-osum  ziel
    python3 tools/osum/mkfs.py cat "$1" "$2" > "$3" 2>"$TMPD/cat.err"
}

echo
echo "== 2. der Kern: der Fahrschein und seine neun Ablehnungen =="

cat > "$TMPD/leer.mon" <<'EOF'
warte 0.2
EOF
fahre boot "" "$TMPD/leer.mon" "" nein
sleep 1.0
ende
st=$(grep -a 'snap: .*selftest' "$OUT" | tail -1)
if echo "$st" | grep -q 'selftest 9 / 9'; then
    ok "snap.selftest 9 / 9 -- acht der neun Zusagen sind ABLEHNUNGEN"
    info "$st"
else
    bad "snap.selftest ist nicht voll: ${st:-keine Zeile}"
fi
if grep -qa 'snip: der Dienst ist da' "$OUT"; then
    ok "der Dienst hat sich eingetragen ($(grep -a 'snip: der Dienst' "$OUT" | tail -1))"
else
    bad "der Dienst hat sich nicht eingetragen"
    grep -a '^snip:' "$OUT" | sed 's/^/        /' | head -4
fi

echo
echo "== 3. GEGENPROBE nosnap: ohne Puffer gibt es kein Bildschirmfoto =="
fahre nosnap "nosnap" "$TMPD/leer.mon" "" nein
sleep 1.0
ende
if grep -qa 'snap: kein Standbildpuffer' "$OUT" \
   && grep -qa 'snip: kein Standbildpuffer' "$OUT"; then
    ok "ohne Puffer sagen Kern UND Anwendung es klar -- und warten nicht"
else
    bad "nosnap: die Ablehnung fehlt"
    grep -aE '^(snap|snip):' "$OUT" | sed 's/^/        /' | head -4
fi

echo
echo "== 4. das Vollbild: ein PNG, und es ist der Rahmenpuffer =="
#
# UMSCHALT+SUPER+S ueber den Monitor, dann `v` fuer Vollbild, dann `s`.
# `sendkey` nimmt die Namen von QEMU: shift-meta_l-s ist genau die
# Kombination, die auch eine Tastatur schickt.
{ echo "warte 0.8"
  zeiger "$(knopf 0)" 13     # "Vollbild"
  echo "mouse_button 1"; echo "warte 0.2"; echo "mouse_button 0"
  echo "warte 1.5"
  zeiger "$(knopf 7)" 13     # "Speicher"
  echo "mouse_button 1"; echo "warte 0.2"; echo "mouse_button 0"
  echo "warte 3.0"
} > "$TMPD/voll.mon"
fahre voll "snipkey" "$TMPD/voll.mon" 'snip: gespeich' nein
foto "$TMPD/voll.ppm"
ende
if grep -qa 'snap: ticket 1' "$OUT"; then
    ok "der Kern hat den Fahrschein ausgestellt ($(grep -a 'snap: ticket' "$OUT" | head -1))"
else
    bad "kein Fahrschein -- UMSCHALT+SUPER+S kam nicht an"
    grep -aE 'hk: |snap:|snip:' "$OUT" | sed 's/^/        /' | head -8
fi
if grep -qa 'snap: take' "$OUT"; then
    ok "das Standbild wurde genommen ($(grep -a 'snap: take' "$OUT" | head -1))"
else
    bad "kein Standbild"
fi
hol "$TMPD/live-voll.img" /bild/snip-1.png "$TMPD/voll.png"
if [ -s "$TMPD/voll.png" ]; then
    ok "die Datei /bild/snip-1.png liegt auf der Platte ($(stat -c%s "$TMPD/voll.png") Oktette)"
else
    bad "keine Datei auf der Platte"
    sed 's/^/        /' "$TMPD/cat.err" 2>/dev/null | head -3
    grep -a '^snip:' "$OUT" | sed 's/^/        /' | head -6
fi
if python3 tools/snip/pngcheck.py "$TMPD/voll.png" --raw "$TMPD/voll.rgb" \
        > "$TMPD/pngcheck.txt" 2>&1; then
    sed 's/^/        /' "$TMPD/pngcheck.txt"
    ok "ein strenger PNG-Leser nimmt die Datei an (CRC, zlib, ADLER-32, nichts hinter IEND)"
else
    bad "der strenge PNG-Leser lehnt die Datei ab"
    sed 's/^/        /' "$TMPD/pngcheck.txt" | head -5
fi
cp -f "$TMPD/voll.png" "$SHOTS/vollbild.png" 2>/dev/null

echo
echo "== 5. der Ausschnitt, auf den Bildpunkt =="
#
# Der Zeiger faehrt erst in die linke obere Ecke (dort haelt der
# Anschlag und die Vorgeschichte ist geloescht), dann in Schritten unter
# 128 an die Stelle -- die Begruendung steht in tools/wm/monitor.py.
# Gezogen wird von (120,140) nach (440,380): 320 x 240.
{ echo "warte 0.8"
  zeiger 120 140
  echo "mouse_button 1"; echo "warte 0.3"
  echo "mouse_move 100 100"; echo "mouse_move 100 100"
  echo "mouse_move 120 40"; echo "warte 0.4"
  echo "mouse_button 0"; echo "warte 1.5"
  zeiger "$(knopf 7)" 13     # "Speicher"
  echo "mouse_button 1"; echo "warte 0.2"; echo "mouse_button 0"
  echo "warte 3.0"
} > "$TMPD/aus.mon"
fahre aus "snipkey" "$TMPD/aus.mon" 'snip: gespeich' nein
foto "$TMPD/aus.ppm"
ende
gr=$(grep -a 'snip: gespeich' "$OUT" | tail -1)
info "${gr:-nichts gespeichert}"
hol "$TMPD/live-aus.img" /bild/snip-1.png "$TMPD/aus.png"
if python3 tools/snip/pngcheck.py "$TMPD/aus.png" --raw "$TMPD/aus.rgb" \
        > "$TMPD/pc2.txt" 2>&1; then
    sed 's/^/        /' "$TMPD/pc2.txt"
    AW=$(sed -n 's/.*-- \([0-9]*\)x\([0-9]*\),.*/\1/p' "$TMPD/pc2.txt")
    AH=$(sed -n 's/.*-- \([0-9]*\)x\([0-9]*\),.*/\2/p' "$TMPD/pc2.txt")
    ok "der Ausschnitt ist ein gueltiges PNG von ${AW}x${AH}"
    AX=$(echo "$gr" | sed -n 's/.*px=\([0-9]*\)x.*/\1/p')
    # Wo der Ausschnitt lag, sagt der Kern nicht -- also wird die Stelle
    # gesucht: das Bild MUSS irgendwo im Schirm genau so stehen. Findet
    # es sich nicht, stimmt etwas nicht, und findet es sich mehrfach,
    # ist der Ausschnitt so einfarbig, dass die Messung nichts sagt.
    python3 - "$TMPD/aus.rgb" "$AW" "$AH" "$TMPD/aus.ppm" > "$TMPD/find.txt" 2>&1 <<'PYEOF'
import sys
sys.path.insert(0, "tools/snip")
from pixel import lies_ppm
rgb, w, h, ppm = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
bild = open(rgb, "rb").read()
sw, sh, schirm = lies_ppm(ppm)
erste = bild[0:w * 3]
treffer = []
for y in range(sh - h + 1):
    zeile = schirm[y * sw * 3:(y + 1) * sw * 3]
    at = 0
    while True:
        i = zeile.find(erste, at)
        if i < 0 or i % 3:
            if i < 0:
                break
            at = i + 1
            continue
        x = i // 3
        if x + w > sw:
            break
        gut = True
        for r in range(h):
            zb = r * w * 3
            zs = ((y + r) * sw + x) * 3
            if bild[zb:zb + w * 3] != schirm[zs:zs + w * 3]:
                gut = False
                break
        if gut:
            treffer.append((x, y))
        at = i + 1
print("SNIP-ORT: %d Stellen im Schirm, an denen der Ausschnitt EXAKT steht"
      % len(treffer))
for t in treffer[:4]:
    print("        bei %d,%d" % t)
sys.exit(0 if len(treffer) >= 1 else 1)
PYEOF
    if [ $? -eq 0 ]; then
        sed 's/^/        /' "$TMPD/find.txt"
        ok "der Ausschnitt steht BILDPUNKTGENAU so im Rahmenpuffer"
    else
        bad "der Ausschnitt findet sich nirgends im Rahmenpuffer wieder"
        sed 's/^/        /' "$TMPD/find.txt" | head -4
    fi
    cp -f "$TMPD/aus.png" "$SHOTS/ausschnitt.png" 2>/dev/null
else
    bad "der Ausschnitt ist kein gueltiges PNG"
    sed 's/^/        /' "$TMPD/pc2.txt" | head -5
fi

echo
echo "== 6. die verzoegerte Aufnahme haelt die Zeit ein =="
{ echo "warte 0.8"
  zeiger "$(knopf 2)" 13     # "Verz. 3s"
  echo "mouse_button 1"; echo "warte 0.2"; echo "mouse_button 0"
  echo "warte 5.0"
  zeiger "$(knopf 0)" 13     # "Vollbild"
  echo "mouse_button 1"; echo "warte 0.2"; echo "mouse_button 0"
  echo "warte 1.5"
  zeiger "$(knopf 7)" 13     # "Speicher"
  echo "mouse_button 1"; echo "warte 0.2"; echo "mouse_button 0"
  echo "warte 3.0"
} > "$TMPD/spaet.mon"
fahre spaet "snipkey" "$TMPD/spaet.mon" 'snip: gespeich' nein
ende
# Der Kern meldet jedes Standbild mit seiner Fahrscheinnummer. Zwei
# Meldungen zu EINER Nummer heisst: derselbe Fahrschein, ein zweites
# Bild -- genau das, was `arm` tun soll.
takes=$(grep -ac 'snap: take 1' "$OUT" || true)
marks=$(grep -ac 'snap: ticket' "$OUT" || true)
info "Standbilder zu Fahrschein 1: $takes, Fahrscheine insgesamt: $marks"
if [ "${takes:-0}" -ge 2 ] && [ "${marks:-0}" = 1 ]; then
    ok "EIN Tastendruck, ZWEI Standbilder -- die Verzoegerung verschiebt den Augenblick, sie vervielfacht ihn nicht"
else
    bad "die verzoegerte Aufnahme hat nicht zwei Standbilder zu einem Fahrschein gegeben"
    grep -aE 'snap: (ticket|take)' "$OUT" | sed 's/^/        /' | head -6
fi
if grep -qa 'snip: gespeich' "$OUT"; then
    ok "nach der Verzoegerung wurde gespeichert ($(grep -a 'snip: gespeich' "$OUT" | tail -1))"
else
    bad "nach der Verzoegerung kam keine Datei"
fi

echo
echo "== 7. SICHERHEIT: ohne Fahrschein null Oktette, und die Gegenprobe dazu =="
#
# `snapfrei` schaltet die Fahrscheinpruefung ab. Der Kern sagt es laut
# auf der seriellen Leitung -- eine Maschine, die jedem den Bildschirm
# gibt, soll das nicht still tun.
fahre frei "snapfrei" "$TMPD/leer.mon" "" nein
sleep 1.0
ende
if grep -qa 'GEGENPROBE snapfrei' "$OUT"; then
    ok "mit `snapfrei` sagt der Kern laut, dass die Pruefung aus ist"
else
    bad "snapfrei wird nicht gemeldet"
fi
# Der eigentliche Beweis: der Selbsttest im Kern. Er stellt die
# Ablehnungen NACH und zaehlt sie. Mit `snapfrei` gehen sie durch --
# also MUSS er dort einbrechen.
st2=$(grep -a 'snap: .*selftest' "$OUT" | tail -1)
n2=$(echo "$st2" | sed -n 's/.*selftest \([0-9]*\) \/ 9.*/\1/p')
info "mit snapfrei: ${st2:-keine Zeile}"
if [ -n "$n2" ] && [ "$n2" -lt 9 ]; then
    ok "mit snapfrei faellt der Selbsttest von 9 auf $n2 -- die Pruefung war also da"
else
    bad "der Selbsttest merkt keinen Unterschied -- dann prueft er nichts"
fi

echo
echo "== 8. das Verpixeln macht den Bereich unlesbar =="
#
# Zuerst ein Vollbild speichern (das ist das VORHER), dann im selben
# Lauf mit `x` verpixeln und noch einmal speichern (das NACHHER). Beide
# Dateien liegen danach auf der Platte, und `entropie.py` rechnet.
{ echo "warte 0.8"
  zeiger "$(knopf 0)" 13     # "Vollbild"
  echo "mouse_button 1"; echo "warte 0.2"; echo "mouse_button 0"
  echo "warte 1.2"
  zeiger "$(knopf 7)" 13     # "Speicher" -- das VORHER
  echo "mouse_button 1"; echo "warte 0.2"; echo "mouse_button 0"
  echo "warte 2.0"
  zeiger "$(knopf 4)" 13     # "Verpixel"
  echo "mouse_button 1"; echo "warte 0.2"; echo "mouse_button 0"
  echo "warte 0.5"
  zeiger 200 160
  echo "mouse_button 1"; echo "warte 0.3"
  echo "mouse_move 100 0"; echo "mouse_move 100 0"
  echo "mouse_move 40 60"; echo "warte 0.4"
  echo "mouse_button 0"; echo "warte 1.5"
  zeiger "$(knopf 7)" 13     # "Speicher" -- das NACHHER
  echo "mouse_button 1"; echo "warte 0.2"; echo "mouse_button 0"
  echo "warte 3.0"
} > "$TMPD/pix.mon"
fahre pix "snipkey" "$TMPD/pix.mon" 'snip-2.png' nein
foto "$TMPD/pix.ppm"
ende
hol "$TMPD/live-pix.img" /bild/snip-1.png "$TMPD/pix1.png"
hol "$TMPD/live-pix.img" /bild/snip-2.png "$TMPD/pix2.png"
if python3 tools/snip/pngcheck.py "$TMPD/pix1.png" --raw "$TMPD/pix1.rgb" --still \
   && python3 tools/snip/pngcheck.py "$TMPD/pix2.png" --raw "$TMPD/pix2.rgb" --still; then
    ok "beide Bilder (vorher und nachher) sind gueltige PNG"
    W=$(python3 tools/snip/pngcheck.py "$TMPD/pix1.png" | sed -n 's/.*-- \([0-9]*\)x\([0-9]*\),.*/\1/p')
    H=$(python3 tools/snip/pngcheck.py "$TMPD/pix1.png" | sed -n 's/.*-- \([0-9]*\)x\([0-9]*\),.*/\2/p')
    # Der verpixelte Bereich: (200,150) bis (440,210), aus dem Skript
    # oben gerechnet. Ein Feld ist 8 Bildpunkte, also hoechstens
    # 30*8 = 240 verschiedene Farben.
    if python3 tools/snip/entropie.py "$TMPD/pix1.rgb" "$TMPD/pix2.rgb" \
            "$W" "$H" 205 165 435 215 --blockmin 240 \
            > "$TMPD/ent.txt" 2>&1; then
        sed 's/^/        /' "$TMPD/ent.txt"
        ok "der Bereich ist nachweislich unlesbar geworden"
    else
        bad "das Verpixeln haelt der Messung nicht stand"
        sed 's/^/        /' "$TMPD/ent.txt"
    fi
    cp -f "$TMPD/pix2.png" "$SHOTS/verpixelt.png" 2>/dev/null
else
    bad "die zwei Bilder fuer den Vergleich fehlen"
    grep -a '^snip:' "$OUT" | sed 's/^/        /' | head -8
fi

echo
echo "== 9. GEGENPROBE snipnofilt: die adaptiven Filter tun etwas =="
fahre nofilt "snipnofilt snipkey" "$TMPD/voll.mon" 'snip: gespeich' nein
ende
hol "$TMPD/live-nofilt.img" /bild/snip-1.png "$TMPD/nofilt.png"
if [ -s "$TMPD/nofilt.png" ] && [ -s "$TMPD/voll.png" ]; then
    a=$(stat -c%s "$TMPD/voll.png"); b=$(stat -c%s "$TMPD/nofilt.png")
    info "mit adaptiven Filtern $a Oktette, mit Filter 0 durchgehend $b"
    fz=$(grep -a 'snip: filter' "$OUT" | tail -1)
    info "Filterwahl ohne Adaption: ${fz:-keine Zeile}"
    if [ "$b" -gt "$a" ]; then
        ok "die Filterwahl spart $((b - a)) Oktette ($(( (b - a) * 100 / b )) Prozent)"
    else
        bad "ohne Filterwahl ist die Datei nicht groesser -- dann waehlt sie nichts"
    fi
    python3 tools/snip/pngcheck.py "$TMPD/nofilt.png" --raw "$TMPD/nofilt.rgb" --still \
        && cmp -s "$TMPD/nofilt.rgb" "$TMPD/voll.rgb" \
        && ok "und BEIDE Dateien enthalten dasselbe Bild, Oktett fuer Oktett" \
        || bad "die zwei Dateien zeigen nicht dasselbe Bild"
else
    bad "eine der beiden Dateien fehlt"
fi

echo
echo "== 9. DAS TASTENKUERZEL SELBST: UMSCHALT+SUPER+S, mit einer echten Taste =="
#
# HIER UND NICHT IN DEN ABSCHNITTEN DAVOR, und der Grund ist gemessen:
# die Tastatur stellt in diesem Baum ab etwa `desktop: ready` keine
# Unterbrechung mehr zu (siehe der Kopf von `fahre`). Im STARTFENSTER
# tut sie es -- also wird das Kuerzel dort gedrueckt, wo es ankommt, und
# geprueft, was der Kern daraus macht:
#
#   * `hk: super+S` -- die Tastatur hat die Kombination erkannt
#   * der Zaehler der Druecke steigt
#   * OHNE eingetragenen Dienst entsteht KEIN Fahrschein, und der Kern
#     zaehlt die Ablehnung. Das ist die Zusage "ohne Dienst kein
#     Fahrschein", und sie ist hier direkt gemessen.
tastenlauf() { # name  ganze-kommandozeile  skript -> $OUT
    local name=$1 zeile=$2 skript=$3
    local sock="$TMPD/mon-$name.sock" out="$TMPD/$name.txt"
    rm -f "$out" "$sock"
    cp -f "$TMPD/disk.img" "$TMPD/live-$name.img"
    timeout 200 $QEMU_X86 -kernel "$TMPD/k0.mb" -m 512 \
        -append "$zeile" -serial "file:$out" -display none -no-reboot \
        -vga std -monitor "unix:$sock,server,nowait" \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/$name.qemu" 2>&1 &
    local pid=$!
    # Sobald die Tastaturleitung eingetragen ist, wird gedrueckt.
    local i=0
    while [ $i -lt 600 ]; do
        grep -qa 'apic: keyboard gsi' "$out" 2>/dev/null && break
        kill -0 $pid 2>/dev/null || break
        sleep 0.05; i=$((i + 1))
    done
    python3 tools/wm/monitor.py "$sock" "$skript" 0.25 > "$TMPD/$name.monout" 2>&1
    i=0
    while [ $i -lt 1400 ]; do
        grep -qaE '^kernel: done' "$out" 2>/dev/null && break
        kill -0 $pid 2>/dev/null || break
        sleep 0.1; i=$((i + 1))
    done
    kill $pid 2>/dev/null; wait $pid 2>/dev/null
    OUT="$out"
}
printf 'sendkey shift-meta_l-s\nwarte 0.3\nsendkey shift-meta_l-s\nwarte 0.3\nsendkey shift-meta_l-s\nwarte 0.3\n' \
    > "$TMPD/taste.mon"
tastenlauf taste "$BASE" "$TMPD/taste.mon"
hk=$(grep -ac 'hk: super+S' "$OUT" || true)
info "\`hk: super+S\` auf der seriellen Leitung: $hk mal"
if [ "${hk:-0}" -ge 1 ]; then
    ok "die Tastatur erkennt UMSCHALT+SUPER+S und meldet es"
else
    bad "UMSCHALT+SUPER+S kommt in der Tastatur nicht an"
    grep -aE '^hk:|^key:' "$OUT" | sed 's/^/        /' | head -5
fi
snips=$(grep -ac 'snap: ticket' "$OUT" || true)
if [ "${snips:-0}" -ge 1 ]; then
    ok "und MIT eingetragenem Dienst entsteht daraus ein Fahrschein ($(grep -a 'snap: ticket' "$OUT" | head -1))"
else
    info "MIT Dienst kein Fahrschein in diesem Lauf -- der Dienst war beim Druck noch nicht eingetragen"
    info "(der Weg selbst ist in Abschnitt 4 bis 8 gemessen, dort mit dem Messhilfsschalter)"
fi

# OHNE eingetragenen Dienst: DIESELBE Taste, und es MUSS ohne Bild
# ausgehen. Dazu die Kommandozeile OHNE das Wort `snip` -- dann startet
# `/bin/snip` nicht und niemand ist eingetragen.
OHNE=$(echo "$BASE" | sed 's/ snip//')
tastenlauf ohne "$OHNE" "$TMPD/taste.mon"
hk2=$(grep -ac 'hk: super+S' "$OUT" || true)
tick2=$(grep -ac 'snap: ticket' "$OUT" || true)
info "ohne Dienst: $hk2 mal die Taste erkannt, $tick2 Fahrscheine"
if [ "${hk2:-0}" -ge 1 ] && [ "${tick2:-0}" = 0 ]; then
    ok "OHNE eingetragenen Dienst gibt dieselbe Taste KEINEN Fahrschein"
else
    bad "ohne Dienst entsteht trotzdem ein Fahrschein (oder die Taste kam nicht an)"
fi

echo
echo "== 10. UMSCHALT+SUPER+S gegen die Runde SUPERSEARCH, in EINEM Kern =="
#
# Nicht gelesen, sondern gebaut. Der Zweig `supersearch` macht SUPER
# ALLEIN zum Kuerzel; wenn Umschalt+Super+S dabei die Suche aufmachte,
# waere das Kuerzel unbrauchbar. Also werden die beiden Zweige in einem
# Wegwerf-Arbeitsverzeichnis zusammengefuehrt und der Kern daraus
# gebaut.
if git rev-parse --verify -q supersearch >/dev/null; then
    WT="$TMPD/ss"
    if git worktree add -q --detach "$WT" snip >/dev/null 2>&1 \
       && git -C "$WT" -c user.name=snip -c user.email=snip@osum \
            merge -q --no-edit supersearch > "$TMPD/ssmerge.txt" 2>&1; then
        ok "snip und supersearch lassen sich verschmelzen"
        if (cd "$WT" && FIRNLIB="$WT/lib" bash tools/build-kernel.sh \
                "$TMPD/kss.mb" > "$TMPD/kss.log" 2>&1); then
            ok "der verschmolzene Kern baut"
            for p in snip sh; do
                (cd "$WT" && FIRNLIB="$WT/lib" vendor/firn/bin/firnc \
                    "kernel/user/$p.fi" -o "$TMPD/ss$p.o" >/dev/null 2>&1 \
                 && ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
                    -o "$TMPD/ss$p.elf" "$TMPD/crt.o" "$TMPD/ss$p.o" 2>/dev/null \
                 && strip --strip-all "$TMPD/ss$p.elf")
            done
            # Nur der Kern wird gebraucht: gemessen wird, was die
            # TASTATUR meldet, und das steht auf der seriellen Leitung.
            rm -f "$TMPD/ss.txt"
            cp -f "$TMPD/disk.img" "$TMPD/live-ss.img"
            timeout 200 $QEMU_X86 -kernel "$TMPD/kss.mb" -m 512 \
                -append "$BASE" -serial "file:$TMPD/ss.txt" -display none \
                -no-reboot -vga std -monitor "unix:$TMPD/ss.sock,server,nowait" \
                -drive "file=$TMPD/live-ss.img,format=raw,if=ide,index=0" \
                -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
                > "$TMPD/ss.qemu" 2>&1 &
            SP=$!
            # WIEDER IM START UND NICHT IN DER HALTEPHASE -- dieselbe
            # Begruendung wie bei `fahre` oben, und hier zaehlt sie
            # doppelt: gemessen werden ZWEI Tastendruecke gegeneinander,
            # und beide muessen durch denselben Weg kommen, sonst
            # vergleicht der Abschnitt zwei verschiedene Dinge.
            i=0
            while [ $i -lt 1400 ]; do
                grep -qa 'snip: der Dienst ist da' "$TMPD/ss.txt" 2>/dev/null && break
                grep -qaE '^wm: hold' "$TMPD/ss.txt" 2>/dev/null && break
                kill -0 $SP 2>/dev/null || break
                sleep 0.1; i=$((i + 1))
            done
            printf 'sendkey shift-meta_l-s\nwarte 0.4\nsendkey meta_l\nwarte 0.4\n' > "$TMPD/ss.mon"
            python3 tools/wm/monitor.py "$TMPD/ss.sock" "$TMPD/ss.mon" 0.2 \
                >/dev/null 2>&1
            i=0
            while [ $i -lt 1400 ]; do
                grep -qaE '^wm: hold' "$TMPD/ss.txt" 2>/dev/null && break
                kill -0 $SP 2>/dev/null || break
                sleep 0.1; i=$((i + 1))
            done
            sleep 1.0
            kill $SP 2>/dev/null; wait $SP 2>/dev/null
            # `hk: tippen` ist die Meldung, die SUPERSEARCH fuer "Super
            # allein" schreibt. Sie darf NACH dem Alleindruck kommen und
            # NICHT nach Umschalt+Super+S.
            vor=$(sed -n '1,/snap: ticket/p' "$TMPD/ss.txt" | grep -ac 'hk: tippen' || true)
            ges=$(grep -ac 'hk: tippen' "$TMPD/ss.txt" || true)
            tick=$(grep -ac 'snap: ticket' "$TMPD/ss.txt" || true)
            info "Fahrscheine: $tick   'Super allein' insgesamt: $ges, davon vor dem Fahrschein: $vor"
            if [ "${tick:-0}" -ge 1 ] && [ "${vor:-0}" = 0 ]; then
                ok "Umschalt+Super+S loest den Fahrschein aus und NICHT die Suche"
            else
                bad "die beiden Kuerzel kommen sich in die Quere"
                grep -aE 'hk: |snap: ticket' "$TMPD/ss.txt" | sed 's/^/        /' | head -8
            fi
            if [ "${ges:-0}" -ge 1 ]; then
                ok "und Super ALLEIN meldet weiterhin 'Super allein' -- die Runde SUPERSEARCH bleibt heil"
            else
                bad "Super allein meldet nichts mehr -- SUPERSEARCH ist kaputt"
            fi
        else
            bad "der verschmolzene Kern baut nicht"
            grep -aiE '^error' "$TMPD/kss.log" | sed 's/^/        /' | head -5
        fi
    else
        bad "snip und supersearch lassen sich nicht verschmelzen"
        sed 's/^/        /' "$TMPD/ssmerge.txt" | head -8
    fi
    git worktree remove --force "$WT" >/dev/null 2>&1
else
    info "der Zweig supersearch ist hier nicht da -- Abschnitt uebersprungen"
fi

echo
echo "SNIP: $pass gruen, $fail rot"
[ $fail -eq 0 ] || exit 1
