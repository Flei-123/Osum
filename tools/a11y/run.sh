#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/a11y/run.sh -- DER BEWEIS, DASS OSUM EINEN BEDIENELEMENT-BAUM HAT
# UND DASS ER NICHT FUER JEDEN OFFEN IST.
#
# WARUM DIESE RUNDE JETZT KOMMT UND NICHT SPAETER. Ein
# Barrierefreiheitsbaum, der nachtraeglich gebaut wird, muss in JEDES
# Programm einzeln eingebaut werden -- das ist die Geschichte von X11
# (AT-SPI kam sechzehn Jahre nach dem Protokoll) und von Windows vor UI
# Automation. In Osum liegt der Fensterserver im Kernel
# (`kernel/wm.fi`) und ALLE Programme benutzen dieselbe Widget-Schicht
# (`kernel/user/wlib.fi`). Der Baum entsteht deshalb GENAU EINMAL, und
# ein Programm, das ein gewoehnliches Bedienelement benutzt, ist ohne
# eine Zeile eigener Arbeit zugaenglich.
#
# WAS HIER GEMESSEN WIRD, UND WARUM SO:
#
#   1. DER BAUM WIRD IM KERNEL GELESEN, NICHT IM PROGRAMM. `kmain`
#      schreibt jeden Knoten der ABLAGE auf die serielle Leitung
#      (`ax: node ...`). Ein Laeufer, der glaubt, was die Anwendung
#      ueber sich selbst sagt, misst die Anwendung; einer, der die
#      Ablage liest, misst das Protokoll.
#   2. DIE STELLEN WERDEN IM BILDSCHIRMFOTO NACHGERECHNET. Der Baum
#      sagt, wo ein Knopf liegt; `tools/a11y/schnitt.py` sieht nach, ob
#      dort wirklich Tinte steht -- und ob rechts davon noch Luft ist.
#   3. DAS PASSWORTFELD WIRD VON BEIDEN SEITEN GEPRUEFT. Der Inhalt
#      steht GENAU EINMAL im Mitschnitt, naemlich dort, wo die Anwendung
#      ihn selbst hinschreibt. Kommt er ein zweites Mal vor -- in einem
#      Knoten, in einer Leserzeile --, faellt der Lauf.
#   4. DAS RECHT HAT EINE GEGENPROBE. Derselbe Leser, zweimal: mit
#      `a11ygrant` liest er den Baum, ohne bekommt er -EPERM bei JEDEM
#      Knoten. Ohne diese zweite Zahl waere "der Baum ist nicht offen"
#      eine Behauptung.
#   5. TASTATUR HEISST DURCHTABBEN UND ZAEHLEN. Die Bibliothek fuehrt
#      eine Spur jedes Fokuswechsels; der Laeufer zaehlt die
#      VERSCHIEDENEN erreichten Bedienelemente und haelt sie gegen die
#      Zahl der fokussierbaren. Die beiden Zahlen muessen gleich sein.
#   6. SKALIERUNG WIRD GEMESSEN, NICHT ANGESEHEN. Je Bedienelement
#      meldet die Anwendung die BREITE IHRES TEXTES in der aktuellen
#      Schrift und den Platz, den sie dafuer hat. Bei 100, 125 und 150
#      Prozent muss der Platz reichen -- fuer jedes einzelne.
#
# Verwendung:  bash tools/a11y/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

num() { # name wert op erwartet
    local name=$1 wert=$2 op=$3 want=$4
    if [ -z "$wert" ]; then bad "$name: keine Zahl gefunden (erwartet $op $want)"; return; fi
    if [ "$wert" -"$op" "$want" ] 2>/dev/null; then ok "$name: $wert"
    else bad "$name: $wert, erwartet $op $want"; fi
}
gleich() { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$3' statt '$2'"; fi; }
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da und sollte nicht" || ok "$3"; }
feld() { grep -aoE "$2" "$1" | tail -1 | grep -oE '[0-9]+' | tail -1; }

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "vendor/firn/fetch-firnc.sh fehlgeschlagen"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "A11Y: uebersprungen, qemu-system-x86_64 ist nicht da"
    exit 0
fi

SHOTS=${A11YSHOTS:-docs/shots/a11y}
mkdir -p "$SHOTS"
png() { python3 - "$1" "$SHOTS/$2.png" <<'PYX' 2>/dev/null
import sys
from PIL import Image
Image.open(sys.argv[1]).save(sys.argv[2])
PYX
}

BORDER=2
TITLE=22
GRUND="wmhold wiglong nokbd nosched noproc nofs"

# --------------------------------------------------------------- Laeufe

lauf() { # name kommandozeile [monitordatei]
    local name=$1 zeile=$2 mon=${3:-}
    local sock="$TMPD/mon-$name.sock"
    local aus="$TMPD/$name.txt" ppm="$TMPD/$name.ppm"
    rm -f "$aus" "$ppm" "$sock"
    cp -f "$TMPD/disk.img" "$TMPD/live-$name.img"
    timeout 240 $QEMU_X86 -kernel "$TMPD/k0.mb" -m 256 \
        -append "$zeile" -serial "file:$aus" -display none -no-reboot \
        -vga std -monitor "unix:$sock,server,nowait" \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local pid=$!
    local i=0
    while [ $i -lt 1400 ]; do
        grep -qaE '^wm: hold' "$aus" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.15
        i=$((i + 1))
    done
    if [ -n "$mon" ]; then
        python3 tools/wm/monitor.py "$sock" "$mon" > "$TMPD/$name.monlog" 2>&1
    fi
    python3 tools/gfx/screenshot.py "$sock" "$ppm" 25 > "$TMPD/$name.shot" 2>&1
    wait "$pid"
    rm -f "$sock"
    return 0
}

echo "== 1. bauen: der Kern aus beiden Uebersetzern, die Programme, das Abbild =="
for s in 0 1; do
    if bash tools/build-kernel.sh "$TMPD/k$s.mb" --stufe "$s" > "$TMPD/b$s.log" 2>&1; then
        ok "firnc$s: Kernel gebaut ($(stat -c%s "$TMPD/k$s.mb") Oktette)"
    else
        bad "firnc$s: der Kernel laesst sich nicht bauen"
        sed 's/^/        /' "$TMPD/b$s.log" | head -12
    fi
done
[ -f "$TMPD/k0.mb" ] || { echo "A11Y: $pass passed, $((fail + 1)) failed"; exit 1; }

PROGS="a11ydemo axlesen widgetdemo explorer launcher sh echo ls cat"
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null \
    || bad "crt.s laesst sich nicht assemblieren"
baue() { # stufe
    local s=$1 cc p rc=0
    if [ "$s" = 0 ]; then cc=vendor/firn/bin/firnc; else cc=vendor/firn/bin/firnc1; fi
    for p in $PROGS; do
        "$cc" "kernel/user/$p.fi" -o "$TMPD/$p$s.o" > "$TMPD/e$p$s" 2>&1 || {
            bad "firnc$s uebersetzt $p.fi nicht"
            sed 's/^/        /' "$TMPD/e$p$s" | head -8
            rc=1
            continue
        }
        ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F$s.u_start" \
            -o "$TMPD/$p$s.elf" "$TMPD/crt.o" "$TMPD/$p$s.o" \
            2>"$TMPD/ld$s.err" || { bad "firnc$s: ld scheitert an $p"; rc=1; continue; }
        strip --strip-all "$TMPD/$p$s.elf"
    done
    return $rc
}
baue 0 && ok "firnc0: $(echo $PROGS | wc -w) Programme gebaut" \
    || bad "firnc0: die Programme dieser Runde lassen sich nicht bauen"
baue 1 && ok "firnc1: dieselben aus dem Uebersetzer, der in Firn geschrieben ist" \
    || bad "firnc1: die Programme dieser Runde lassen sich nicht bauen"

# DIE BIBLIOTHEK BLEIBT IN RING 3. Der Baum entsteht in `wlib.ax_flush`,
# und diese Zusage aus Runde K15 darf diese Runde nicht aufweichen: ein
# Kernel, der weiss, wie ein Knopf heisst, ist keiner mehr. Er kennt
# ROLLEN und NAMEN, weil Ring 3 sie ihm SCHICKT.
for sym in wlib__ax_flush wlib__button wlibc__text_at; do
    if nm -a "$TMPD/k0.mb.elf" 2>/dev/null | grep -q "$sym"; then
        bad "der Kernel traegt $sym -- die Widget-Schicht gehoert nach Ring 3"
    else
        ok "der Kernel traegt $sym NICHT (der Baum entsteht in Ring 3)"
    fi
done

python3 tools/k15/tree.py "$TMPD/baum" > "$TMPD/baum.log" 2>&1 \
    && ok "der Verzeichnisbaum ist gebaut" \
    || bad "tools/k15/tree.py fehlgeschlagen"
ARGS=(build "$TMPD/disk.img" 4096 /lib/
      "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf"
      /bin/)
for p in $PROGS; do ARGS+=("/bin/$p=$TMPD/${p}0.elf"); done
ARGS+=("/bin/files@/bin/explorer")
# DIE ALTE UEBERSCHREIBUNGSDATEI KOMMT MIT AUFS ABBILD, und zwar mit
# ABSICHT: sie nennt zwoelf dunkle Flaechenfarben. Der hohe Kontrast
# muss sie schlagen -- ein Schalter, den eine Datei aus Runde K15
# aushebelt, waere keiner.
ARGS+=(/etc/ "/etc/theme=$TMPD/baum/theme" /etc/schemas/)
for s in assets/schemes/*.scheme; do
    ARGS+=("/etc/schemas/$(basename "$s" .scheme)=$s")
done
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "mkfs.py baut ein Abbild mit den Programmen, den Schriften und den Schemata" \
    || { bad "mkfs.py fehlgeschlagen"; sed 's/^/        /' "$TMPD/mkfs.txt" | head -6; }

echo "== 2. die Speicherkarte, die Aufrufnummern und die Packung =="
kart=$(python3 tools/kernel/memmap.py kernel 2>&1)
if [ $? -eq 0 ]; then ok "die Speicherkarte von kdata: $kart"
else bad "die Speicherkarte von kdata kollidiert"; echo "$kart" | sed 's/^/        /'; fi
if python3 tools/kernel/memmap.py kernel -v 2>/dev/null | grep -q " AX  *kstate.fi:"; then
    ok "der Bereich AX steht in der Karte"
else
    bad "der Bereich AX steht NICHT in der Karte"
fi
wo=$(python3 tools/kernel/memmap.py kernel -v 2>/dev/null | grep ' AX ' \
     | grep -oE '0x[0-9A-Fa-f]+' | head -2 | tr '\n' ' ')
gleich "der Bereich liegt im zugeteilten Vorrat" "0x7A000 0x80000 " "$wo"
for n in 1960 1961 1962 1963 1964 1965; do
    grep -qE "= $n( |$)" kernel/sys.fi && ok "die Aufrufnummer $n steht in kernel/sys.fi" \
        || bad "die Aufrufnummer $n fehlt"
done
grep -q 'const AX_MAXNR: u64 = 1965' kernel/sys.fi \
    && ok "und 1965 ist die hoechste" || bad "AX_MAXNR passt nicht zu den Aufrufen"
p=$(python3 tools/a11y/felder.py 2>&1)
if [ $? -eq 0 ]; then ok "die Packung eines Knotens ist in Ring 0 und Ring 3 dieselbe: $p"
else bad "die Packung laeuft auseinander"; echo "$p" | sed 's/^/        /'; fi

echo "== 3. der Baum: was die Ablage im Kernel wirklich traegt =="
lauf basis "gfx wm wig wigapp=/bin/a11ydemo a11y a11yread a11ygrant $GRUND"
B="$TMPD/basis.txt"
png "$TMPD/basis.ppm" "baum"
num "der Selbsttest der Schicht" "$(feld "$B" 'ax: selftest [0-9]+')" eq 9
num "Knoten in der Ablage" "$(feld "$B" 'ax: nodes=[0-9]+')" eq 13
num "Eintragungen" "$(feld "$B" 'pushes=[0-9]+')" ge 1
# DIE ROLLEN. Sie stehen in der ABLAGE und nicht im Programm -- das ist
# der Unterschied zwischen einem Protokoll und einer Behauptung.
has "$B" "ax: node 0  role=1" "Knoten 0 ist ein FENSTER (Rolle 1)"
has "$B" "name=A11Y Bedienelemente" "und traegt den Fenstertitel als Namen"
has "$B" "role=10" "eine MENUELEISTE steht im Baum (Rolle 10)"
has "$B" "role=9" "ein REITER steht im Baum (Rolle 9)"
has "$B" "role=2" "eine BESCHRIFTUNG steht im Baum (Rolle 2)"
has "$B" "role=5" "ein TEXTFELD steht im Baum (Rolle 5)"
has "$B" "role=6" "ein PASSWORTFELD steht im Baum (Rolle 6)"
has "$B" "role=3" "ein KNOPF steht im Baum (Rolle 3)"
has "$B" "role=4" "ein KONTROLLKAESTCHEN steht im Baum (Rolle 4)"
has "$B" "role=11" "ein AUSWAHLFELD steht im Baum (Rolle 11)"
has "$B" "role=7" "eine LISTE steht im Baum (Rolle 7)"
# DIE NAMEN. Sie kommen aus dem sichtbaren Text, ohne dass die Anwendung
# sie irgendwo noch einmal hingeschrieben haette.
for w in "name=Speichern" "name=Abbrechen" "name=Hohen Kontrast" \
         "name=Barrierefreiheit" "name=Loeschen" "name=Mehr davon"; do
    has "$B" "$w" "der zugaengliche Name entsteht von selbst: ${w#name=}"
done
# DER ZUSTAND: genau EIN Knoten hat den Fokus.
fok=$(grep -ac 'ax: node .*state=[0-9]*[4567]  win' "$B" 2>/dev/null || true)
n_fokus=$(grep -aoE 'ax: node [0-9]+  role=[0-9]+  state=[0-9]+' "$B" \
          | grep -oE 'state=[0-9]+$' | sed 's/state=//' \
          | awk '{ if (and($1,4)) n++ } END { print n+0 }' 2>/dev/null)
if [ -z "$n_fokus" ]; then
    n_fokus=$(grep -aoE 'ax: node [0-9]+  role=[0-9]+  state=[0-9]+' "$B" \
              | grep -oE 'state=[0-9]+$' | sed 's/state=//' \
              | python3 -c "import sys;print(sum(1 for l in sys.stdin if int(l)&4))")
fi
gleich "genau EIN Bedienelement hat den Fokus" "1" "$n_fokus"
gleich "der Baum ist eingeschaltet" "1" "$(feld "$B" 'on=[0-9]+')"

echo "== 3b. die Stellen aus dem Baum, im Bildschirmfoto nachgerechnet =="
# Der Baum sagt Fensterkoordinaten; das Fenster sagt seine Ecke. Beides
# zusammen ist die Stelle auf dem Schirm -- und dort muss Tinte stehen.
winx=$(grep -aoE 'ax: node 0 .* x=[0-9]+' "$B" | tail -1 | grep -oE 'x=[0-9]+' | sed 's/x=//')
winy=$(grep -aoE 'ax: node 0 .* x=[0-9]+  y=[0-9]+' "$B" | tail -1 | grep -oE 'y=[0-9]+' | sed 's/y=//')
knoten_feld() { # nr feld
    grep -aoE "^ax: node $1  .*" "$B" | tail -1 | grep -oE "  $2=[0-9]+" \
        | tail -1 | sed "s/.*=//"
}
schnitt_ok=0
for nr in 6 7 8 10 11; do
    nx=$(knoten_feld $nr x); ny=$(knoten_feld $nr y)
    nw=$(knoten_feld $nr w); nh=$(knoten_feld $nr h)
    [ -z "$nx" ] && { bad "Knoten $nr hat keine Stelle"; continue; }
    sx=$((winx + BORDER + nx)); sy=$((winy + TITLE + ny))
    # DER RAHMEN EINES KNOPFES IST SELBST TINTE AN DER KANTE. Gemessen
    # wird deshalb der INNENraum: vier Bildpunkte hinein, und was dann
    # noch rechts an die Kante stoesst, ist ein abgeschnittener
    # Buchstabe. Die erste Fassung mass das ganze Rechteck und meldete
    # bei jedem Knopf `rechts=0` -- der Rahmen.
    aus=$(python3 tools/a11y/schnitt.py "$TMPD/basis.ppm" \
          $((sx + 4)) $((sy + 4)) $((nw - 8)) $((nh - 8)) 2>&1)
    tinte=$(echo "$aus" | grep -oE 'tinte=[0-9]+' | sed 's/tinte=//')
    rechts=$(echo "$aus" | grep -oE 'rechts=[0-9]+' | sed 's/rechts=//')
    if [ "${tinte:-0}" -gt 20 ] && [ "${rechts:-0}" -ge 1 ]; then
        ok "Knoten $nr liegt wirklich bei ($sx,$sy) ${nw}x${nh}: $aus"
    else
        bad "Knoten $nr: an ($sx,$sy) steht nicht, was der Baum sagt -- $aus"
        schnitt_ok=1
    fi
done

echo "== 4. das Passwortfeld gibt seinen Inhalt NICHT heraus =="
# Das Geheimnis steht GENAU EINMAL im Mitschnitt: dort, wo die Anwendung
# es selbst hinschreibt. Jedes weitere Vorkommen waere ein Leck.
mal=$(grep -aoc 'GEHEIMNIS7' "$B" 2>/dev/null || echo 0)
gleich "das Geheimnis kommt im ganzen Mitschnitt genau einmal vor" "1" "$mal"
if grep -a 'GEHEIMNIS7' "$B" | grep -qa 'a11ydemo: secret'; then
    ok "und zwar dort, wo die Anwendung es selbst meldet"
else
    bad "das eine Vorkommen ist NICHT die Selbstmeldung der Anwendung"
fi
if grep -a 'ax: node' "$B" | grep -qa 'GEHEIMNIS'; then
    bad "ein Knoten der Ablage traegt den Inhalt des Passwortfeldes"
else
    ok "kein Knoten der Ablage traegt den Inhalt des Passwortfeldes"
fi
if grep -a 'axlesen: node' "$B" | grep -qa 'GEHEIMNIS'; then
    bad "der Leser bekommt den Inhalt des Passwortfeldes"
else
    ok "der Leser bekommt den Inhalt des Passwortfeldes NICHT"
fi
has "$B" "role=6  state=67" "das Feld meldet Rolle 6 und den Zustand 'geschuetzt' (Bit 64)"
pwv=$(grep -aoE 'ax: node [0-9]+  role=6 .*value=[0-9]+' "$B" | tail -1 \
      | grep -oE 'value=[0-9]+' | sed 's/value=//')
gleich "und seinen Wert als NULL" "0" "$pwv"
has "$B" "role=6  state=67  win=0  parent=0" "es haengt am Fensterknoten (Eltern-Kind-Beziehung)"
pwname=$(grep -aoE 'ax: node [0-9]+  role=6 .*name=.*' "$B" | tail -1 | sed 's/.*name=//')
gleich "sein Name ist der, den das Programm gesetzt hat" "Kennwort" "$pwname"
gleich "die Ablage hat ein geschuetztes Feld gesehen" "1" "$(feld "$B" 'secrets=[0-9]+')"
gleich "und KEIN Wert ist je bei ihr angekommen (leaks)" "0" "$(feld "$B" 'leaks=[0-9]+')"

echo "== 5. das Recht: mit Freigabe lesen, ohne Freigabe nicht =="
has "$B" "axlesen: start may=1" "mit a11ygrant darf der Leser"
has "$B" "axlesen: gelesen n=13  denied=0" "und liest alle dreizehn Knoten"
num "Lesevorgaenge in der Ablage" "$(feld "$B" 'reads=[0-9]+')" eq 13
lauf ohne "gfx wm wig wigapp=/bin/a11ydemo a11y a11yread $GRUND"
O="$TMPD/ohne.txt"
has "$O" "axlesen: start may=0" "GEGENPROBE: ohne a11ygrant darf er NICHT"
has "$O" "axlesen: DENIED rc=1" "und bekommt -EPERM (1)"
has "$O" "axlesen: gelesen n=0" "er liest KEINEN einzigen Knoten"
num "abgewiesene Versuche in der Ablage" "$(feld "$O" 'denied=[0-9]+')" ge 13
if grep -qa 'axlesen: node' "$O"; then
    bad "ohne Freigabe steht trotzdem ein Knoten in der Ausgabe des Lesers"
else
    ok "ohne Freigabe steht in seiner Ausgabe kein einziger Knoten"
fi

echo "== 5b. die Gegenprobe zum Baum selbst =="
lauf notree "gfx wm wig wigapp=/bin/a11ydemo a11y a11ynotree a11yread a11ygrant $GRUND"
N="$TMPD/notree.txt"
gleich "mit a11ynotree ist die Schicht aus" "0" "$(feld "$N" 'on=[0-9]+')"
gleich "und die Ablage bleibt leer" "0" "$(feld "$N" 'ax: nodes=[0-9]+')"
has "$N" "axlesen: start may=1  count=0" "der Leser darf -- und findet nichts"
has "$N" "a11ydemo: ready" "die Anwendung laeuft trotzdem unveraendert weiter"

echo "== 6. die Tastatur: durchtabben und zaehlen =="
for i in $(seq 1 14); do echo "sendkey tab"; done > "$TMPD/tab.mon"
lauf tabs "gfx wm wig wigapp=/bin/a11ydemo a11y $GRUND" "$TMPD/tab.mon"
T="$TMPD/tabs.txt"
png "$TMPD/tabs.ppm" "tastatur-fokus"
sp=$(python3 tools/a11y/spur.py "$T" 2>&1)
erreicht=$(echo "$sp" | grep -oE 'erreicht=[0-9]+' | sed 's/.*=//')
fokus=$(echo "$sp" | grep -oE 'fokus=[0-9]+' | sed 's/.*=//')
gleich "erreichte Bedienelemente == fokussierbare Bedienelemente" "$fokus" "$erreicht"
num "und es sind mehr als acht" "$erreicht" ge 9
# DIE MENUELEISTE. Sie war das einzige Bedienelement dieser Bibliothek,
# das per Maus ging und per Tastatur nicht.
if python3 - "$T" <<'PYX'
import re, sys
letzte = None
for z in open(sys.argv[1], 'rb').read().split(b'\n'):
    if b'a11ydemo: spur' in z:
        letzte = z.decode('latin-1')
m = re.search(r"\[([^\]]*)\]", letzte or "")
sys.exit(0 if m and '0' in m.group(1).split() else 1)
PYX
then ok "die Menueleiste (Nummer 0) wird per Tabulator erreicht"
else bad "die Menueleiste wird per Tabulator NICHT erreicht"; fi

for i in 1 2 3 4 5; do echo "sendkey tab"; done > "$TMPD/back.mon"
for i in 1 2 3; do echo "sendkey shift-tab"; done >> "$TMPD/back.mon"
lauf back "gfx wm wig wigapp=/bin/a11ydemo a11y $GRUND" "$TMPD/back.mon"
if python3 - "$TMPD/back.txt" <<'PYX'
import re, sys
letzte = None
for z in open(sys.argv[1], 'rb').read().split(b'\n'):
    if b'a11ydemo: spur' in z:
        letzte = z.decode('latin-1')
m = re.search(r"\[([^\]]*)\]", letzte or "")
if not m:
    sys.exit(1)
f = [int(v) for v in m.group(1).split()]
# Die letzten drei Schritte muessen RUECKWAERTS gehen.
sys.exit(0 if len(f) >= 4 and f[-1] < f[-2] < f[-3] else 1)
PYX
then ok "Umschalt-Tab geht rueckwaerts durch die Bedienelemente"
else bad "Umschalt-Tab geht nicht rueckwaerts"; fi
has "$TMPD/back.txt" "key: " "die Tastatur meldet Fluchtfolgen"

echo "== 7. die Skalierung: 100, 125 und 150 Prozent, gemessen =="
for s in 100 125 150; do
    if [ "$s" = 100 ]; then
        lauf "skal$s" "gfx wm wig wigapp=/bin/a11ydemo a11y $GRUND"
    else
        lauf "skal$s" "gfx wm wig wigapp=/bin/a11ydemo a11y a11yscale=$s $GRUND"
    fi
    S="$TMPD/skal$s.txt"
    png "$TMPD/skal$s.ppm" "skalierung-$s"
    gleich "bei $s Prozent meldet die Schicht die Skalierung" "$s" "$(feld "$S" 'scale=[0-9]+')"
    erw=$((15 * s / 100))
    gleich "  die Schrift ist $erw Bildpunkte" "$erw" "$(feld "$S" 'a11ydemo: scale=[0-9]+ px=[0-9]+')"
    # DIE MESSUNG: fuer JEDES Bedienelement Platz >= Textbreite.
    eng=$(python3 - "$S" <<'PYX'
import re, sys
schlimm = []
for z in open(sys.argv[1], 'rb').read().split(b'\n'):
    z = z.decode('latin-1')
    m = re.search(r"a11ydemo: fit id=(\d+) kind=(\d+) text=(\d+) platz=(\d+)", z)
    if m:
        i, k, t, p = (int(v) for v in m.groups())
        if t > p:
            schlimm.append("id=%d kind=%d text=%d platz=%d" % (i, k, t, p))
print(len(schlimm))
for s in schlimm[:6]:
    print("    " + s)
PYX
)
    n_eng=$(echo "$eng" | head -1)
    if [ "${n_eng:-99}" = 0 ]; then
        ok "  KEINE Beschriftung ist zu breit fuer ihren Platz (gemessen, alle Elemente)"
    else
        bad "  $n_eng Beschriftungen passen nicht"
        echo "$eng" | tail -n +2
    fi
    # Und dasselbe im BILD: rechts von der Tinte muss Luft sein.
    winx=$(grep -aoE 'ax: node 0 .* x=[0-9]+' "$S" | tail -1 | grep -oE 'x=[0-9]+' | sed 's/x=//')
    winy=$(grep -aoE 'ax: node 0 .* x=[0-9]+  y=[0-9]+' "$S" | tail -1 | grep -oE 'y=[0-9]+' | sed 's/y=//')
    kf() { grep -aoE "^ax: node $1  .*" "$S" | tail -1 | grep -oE "  $2=[0-9]+" | tail -1 | sed "s/.*=//"; }
    schlecht=0
    for nr in 6 7 10 11; do
        nx=$(kf $nr x); ny=$(kf $nr y); nw=$(kf $nr w); nh=$(kf $nr h)
        [ -z "$nx" ] && { schlecht=1; continue; }
        aus=$(python3 tools/a11y/schnitt.py "$TMPD/skal$s.ppm" \
              $((winx + BORDER + nx + 4)) $((winy + TITLE + ny + 4)) \
              $((nw - 8)) $((nh - 8)) 2>&1)
        r=$(echo "$aus" | grep -oE 'rechts=[0-9]+' | sed 's/.*=//')
        t=$(echo "$aus" | grep -oE 'tinte=[0-9]+' | sed 's/.*=//')
        if [ "${t:-0}" -lt 20 ] || [ "${r:-0}" -lt 1 ]; then
            bad "  Knopf $nr bei $s Prozent: $aus"
            schlecht=1
        fi
    done
    [ "$schlecht" = 0 ] && ok "  und im BILD hat jede Beschriftung rechts noch Luft"
done

echo "== 8. die Bildschirmlupe =="
lauf lupe "gfx wm wig wigapp=/bin/a11ydemo a11y a11ymag $GRUND"
L="$TMPD/lupe.txt"
png "$TMPD/lupe.ppm" "lupe"
mx=$(grep -aoE 'ax: mag x=[0-9]+' "$L" | tail -1 | grep -oE '[0-9]+')
my=$(grep -aoE 'ax: mag .* y=[0-9]+' "$L" | tail -1 | grep -oE ' y=[0-9]+' | head -1 | grep -oE '[0-9]+')
mw=$(grep -aoE 'ax: mag .* w=[0-9]+' "$L" | tail -1 | grep -oE ' w=[0-9]+' | grep -oE '[0-9]+')
mh=$(grep -aoE 'ax: mag .* h=[0-9]+' "$L" | tail -1 | grep -oE ' h=[0-9]+' | grep -oE '[0-9]+')
msx=$(grep -aoE 'ax: mag .* sx=[0-9]+' "$L" | tail -1 | grep -oE 'sx=[0-9]+' | grep -oE '[0-9]+')
msy=$(grep -aoE 'ax: mag .* sy=[0-9]+' "$L" | tail -1 | grep -oE 'sy=[0-9]+' | grep -oE '[0-9]+')
mf=$(grep -aoE 'ax: mag .* f=[0-9]+' "$L" | tail -1 | grep -oE ' f=[0-9]+' | grep -oE '[0-9]+')
num "die Lupe hat wirklich gemalt (Bilder)" "$(feld "$L" 'frames=[0-9]+')" ge 1
gleich "die Vergroesserung ist zweifach" "2" "$mf"
aus=$(python3 tools/a11y/lupe.py "$TMPD/lupe.ppm" "$mx" "$my" "$mw" "$mh" "$msx" "$msy" "$mf" 2>&1)
if [ $? -eq 0 ]; then ok "die Tafel zeigt BILDPUNKTGENAU den Ausschnitt um den Zeiger: $aus"
else bad "die Lupe zeigt etwas anderes als den Ausschnitt"; echo "$aus" | sed 's/^/        /'; fi
gleich "GEGENPROBE: ohne a11ymag wird die Tafel nicht gemalt" "0" "$(feld "$B" 'frames=[0-9]+')"

echo "== 9. hoher Kontrast =="
lauf hoch "gfx wm wig wigapp=/bin/a11ydemo a11y a11yhigh $GRUND"
H="$TMPD/hoch.txt"
png "$TMPD/hoch.ppm" "hoher-kontrast"
gleich "die Schicht meldet hohen Kontrast" "1" "$(feld "$H" 'high=[0-9]+')"
hfg=$(grep -aoE 'a11ydemo: theme fg=[0-9]+' "$H" | tail -1 | grep -oE '[0-9]+$')
hbg=$(grep -aoE 'a11ydemo: theme .*bg=[0-9]+' "$H" | tail -1 | grep -oE 'bg=[0-9]+' | grep -oE '[0-9]+')
nfg=$(grep -aoE 'a11ydemo: theme fg=[0-9]+' "$B" | tail -1 | grep -oE '[0-9]+$')
nbg=$(grep -aoE 'a11ydemo: theme .*bg=[0-9]+' "$B" | tail -1 | grep -oE 'bg=[0-9]+' | grep -oE '[0-9]+')
kh=$(python3 tools/a11y/kontrast.py "$hfg" "$hbg")
kn=$(python3 tools/a11y/kontrast.py "$nfg" "$nbg")
if python3 -c "import sys; sys.exit(0 if float('$kh') >= 7.0 else 1)"; then
    ok "Schrift auf Flaeche: $kh zu 1 -- ueber der Schwelle 7 (WCAG AAA); gewoehnlich $kn zu 1"
else
    bad "hoher Kontrast erreicht nur $kh zu 1 (verlangt 7)"
fi
if python3 -c "import sys; sys.exit(0 if float('$kh') > float('$kn') else 1)"; then
    ok "und er ist messbar hoeher als das gewoehnliche Schema"
else
    bad "der hohe Kontrast ist nicht hoeher als das gewoehnliche Schema"
fi
# DIE ALTE UEBERSCHREIBUNGSDATEI DARF IHN NICHT AUSHEBELN. Sie liegt auf
# dem Abbild und nennt dunkle Flaechen; ohne die zwei Sperren in
# `wlibc.fi` kam daraus schwarze Schrift auf dunklem Grund.
gleich "GEGENPROBE: ohne a11yhigh gilt das gewoehnliche Schema" "0" "$(feld "$B" 'high=[0-9]+')"

echo "== 10. die Einrastfunktion =="
{ for i in 1 2 3 4 5; do echo "sendkey tab"; done
  echo "warte 0.4"; echo "sendkey shift"; echo "warte 0.4"
  echo "sendkey tab"; echo "warte 0.4"; echo "sendkey tab"; } > "$TMPD/stick.mon"
lauf stickan "gfx wm wig wigapp=/bin/a11ydemo a11y a11ysticky $GRUND" "$TMPD/stick.mon"
lauf stickaus "gfx wm wig wigapp=/bin/a11ydemo a11y $GRUND" "$TMPD/stick.mon"
gleich "mit a11ysticky ist die Einrastfunktion an" "1" \
    "$(grep -aoE 'ax: kbd sticky=[0-9]+' "$TMPD/stickan.txt" | tail -1 | grep -oE '[0-9]+$')"
num "und ein Modifikator ist wirklich eingerastet" \
    "$(grep -aoE 'sticks=[0-9]+' "$TMPD/stickan.txt" | tail -1 | grep -oE '[0-9]+')" ge 1
gleich "GEGENPROBE: ohne das Wort rastet nichts ein" "0" \
    "$(grep -aoE 'sticks=[0-9]+' "$TMPD/stickaus.txt" | tail -1 | grep -oE '[0-9]+')"
richtung() { # datei -> "zurueck" oder "vor"
    python3 - "$1" <<'PYX'
import re, sys
letzte = None
for z in open(sys.argv[1], 'rb').read().split(b'\n'):
    if b'a11ydemo: spur' in z:
        letzte = z.decode('latin-1')
m = re.search(r"\[([^\]]*)\]", letzte or "")
f = [int(v) for v in m.group(1).split()] if m else []
if len(f) >= 2 and f[-1] < f[-2]:
    print("zurueck")
elif len(f) >= 2:
    print("vor")
else:
    print("nichts")
PYX
}
# NACH `shift` ALLEIN wirkt der naechste Tabulator wie Umschalt-Tab --
# der Fokus geht ZURUECK. Ohne die Einrastfunktion geht er weiter vor.
gleich "nach 'Umschalt' allein geht der naechste Tabulator zurueck" \
    "zurueck" "$(python3 - "$TMPD/stickan.txt" <<'PYX'
import re, sys
letzte = None
for z in open(sys.argv[1], 'rb').read().split(b'\n'):
    if b'a11ydemo: spur' in z:
        letzte = z.decode('latin-1')
m = re.search(r"\[([^\]]*)\]", letzte or "")
f = [int(v) for v in m.group(1).split()] if m else []
# Fuenf Tabulatoren, dann Umschalt allein, dann zwei Tabulatoren:
# der SECHSTE Schritt muss rueckwaerts gehen.
print("zurueck" if len(f) >= 6 and f[5] < f[4] else "vor")
PYX
)"
gleich "GEGENPROBE: ohne Einrasten geht er weiter vorwaerts" \
    "vor" "$(python3 - "$TMPD/stickaus.txt" <<'PYX'
import re, sys
letzte = None
for z in open(sys.argv[1], 'rb').read().split(b'\n'):
    if b'a11ydemo: spur' in z:
        letzte = z.decode('latin-1')
m = re.search(r"\[([^\]]*)\]", letzte or "")
f = [int(v) for v in m.group(1).split()] if m else []
print("zurueck" if len(f) >= 6 and f[5] < f[4] else "vor")
PYX
)"

echo "== 11. die Runde K15 laeuft unveraendert weiter =="
# DER BAUM DARF DIE BESTEHENDE OBERFLAECHE NICHT VERAENDERN. Bei 100
# Prozent ist jede Skalierungsrechnung die Identitaet; die Anordnung der
# Runde K15 muss deshalb BILDPUNKTGLEICH dieselbe sein.
lauf k15 "gfx wm wig $GRUND"
K="$TMPD/k15.txt"
gleich "widgetdemo: die Menueleiste liegt, wo sie lag" \
    "widgetdemo: rect id=0 kind=8 x=12 y=12 w=456 h=22 " \
    "$(grep -aoE 'widgetdemo: rect id=0 .*' "$K" | tail -1)"
gleich "widgetdemo: der erste Knopf liegt, wo er lag" \
    "widgetdemo: rect id=5 kind=2 x=12 y=196 w=100 h=28 " \
    "$(grep -aoE 'widgetdemo: rect id=5 .*' "$K" | tail -1)"
gleich "widgetdemo: die Liste liegt, wo sie lag" \
    "widgetdemo: rect id=11 kind=5 x=12 y=272 w=456 h=112 " \
    "$(grep -aoE 'widgetdemo: rect id=11 .*' "$K" | tail -1)"
num "und der Selbsttest der Naht ist unveraendert" \
    "$(feld "$K" 'wig: selftest [0-9]+')" eq 7
gleich "ohne das Wort a11y bleibt die Schicht aus" "0" "$(feld "$K" 'on=[0-9]+')"
gleich "und die Ablage leer" "0" "$(feld "$K" 'ax: nodes=[0-9]+')"

echo
echo "A11Y: $pass passed, $fail failed  (accel: $OSUM_QEMU_ACCEL)"
[ "$fail" = 0 ] || exit 1
exit 0
