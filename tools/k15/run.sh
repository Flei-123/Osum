#!/usr/bin/env bash
# tools/k15/run.sh -- DER BEWEIS, DASS OSUM WIDGETS HAT UND EINEN
# DATEIMANAGER.
#
# Runde K10 gab Osum eine Oberflaeche: ein Zeigegeraet, einen
# Fensterserver, einen TrueType-Rasterer. Zwischen dem Rechteck, das
# eine Anwendung dort bekommt, und einer Anwendung fehlte alles --
# Knoepfe, Textfelder, Listen, Menues, Dialoge, eine Ereignisschleife,
# eine Anordnung. Runde K15 baut das, und zwar IN RING 3
# (`kernel/user/wig.fi` und `kernel/user/wigc.fi`); im Kernel stehen
# sieben Aufrufe, die kein Widget kennen (`kernel/wig.fi`).
#
# WAS HIER GEMESSEN WIRD, UND WARUM SO:
#
#   1. DIE ANORDNUNG WIRD GEGEN SICH SELBST GERECHNET. Die Anwendung
#      meldet jedes Rechteck, das sie ausgerechnet hat, BEVOR sie malt.
#      `tools/k15/anordnung.py` prueft, dass keines aus dem Fenster
#      ragt, dass sich keine zwei ueberschneiden und dass die
#      Reihenfolge stimmt. Ein Bildschirmfoto sieht das nicht: zwei
#      Knoepfe uebereinander sehen aus wie einer.
#   2. DER TEXT WIRD JE ZEICHEN GEPRUEFT. Das ist die Lehre aus Runde
#      K7B, und sie steht in der Aufgabe dieser Runde noch einmal: dort
#      schien Text zu 87 Prozent zu stimmen, waehrend JEDER Buchstabe
#      fehlte -- die 87 Prozent waren schwarzer Hintergrund. Also wird
#      hier keine Flaeche gezaehlt, sondern je Zeichen die gesetzten
#      Bildpunkte gegen eine zweite, unabhaengige Rasterung desselben
#      Umrisses (`tools/ttf/raster.py` ueber `tools/gfx/schau.py`) --
#      und ein Zeichen ohne Tinte im Bild laesst die Zusage fallen.
#      Die Stelle und die beiden Farben sagt die ANWENDUNG; nachgerechnet
#      wird im BILD.
#   3. DIE OBERFLAECHE WIRD WIRKLICH BEDIENT. Ueber den QEMU-Monitor
#      gehen echte Mausbewegungen, echte Klicks und echte Tastendruecke
#      in die laufende Maschine (`tools/wm/monitor.py`), und danach wird
#      der SCHIRM gemessen -- nicht der innere Zustand der Bibliothek.
#   4. JEDE ZUSAGE HAT EINE GEGENPROBE. Dieselbe Anwendung mit
#      abgeschalteter Eigenschaft, und die Messung MUSS einbrechen:
#      `nohit` (keine Trefferpruefung), `noclip` (keine Zwischenablage),
#      `nodirty` (keine Bereichsverfolgung), `nofocus`, `nomouse`, und
#      der Lauf ganz ohne das Wort `wig`.
#   5. DER DATEIMANAGER WIRD GEGEN DIE PLATTE GERECHNET.
#      `tools/k15/baum.py` legt den Baum an UND schreibt auf, was
#      darin steht; was `/bin/files` zeigt, wird Zeichen fuer Zeichen
#      dagegen gehalten. Und was er AENDERT, wird nicht im Bild
#      geglaubt, sondern im Plattenabbild nachgesehen (`mkfs.py list`).
#
# Verwendung:  bash tools/k15/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
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
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da und sollte nicht" || ok "$3"; }
gleich() { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$3' statt '$2'"; fi; }

schau() { local name=$1; shift
    local aus rc
    aus=$(python3 tools/gfx/schau.py "$@" 2>&1); rc=$?
    if [ "$rc" -eq 0 ]; then ok "$name ($aus)"; else bad "$name -- $aus"; fi
}
schau_nicht() { local name=$1; shift
    local aus rc
    aus=$(python3 tools/gfx/schau.py "$@" 2>&1); rc=$?
    if [ "$rc" -ne 0 ]; then ok "$name"; else bad "$name -- ging durch: $aus"; fi
}
zahl()  { grep -aoE "$2" "$1" | head -1 | grep -oE '[0-9]+' | tail -1; }
zahl2() { grep -aoE "$2" "$1" | tail -1 | grep -oE '[0-9]+' | tail -1; }
# EIN FELD AUS EINER GEMELDETEN ZEILE. Ueber `tools/k15/wert.py` und
# nicht ueber `grep -oE '.*fg=[0-9]+'`: `.*` ist gierig, und `selfg`
# endet auf `fg`. Genau daran sind in der ersten Fassung dieses Laeufers
# vier Zusagen gescheitert -- gegen WEISS gerechnet statt gegen die
# Textfarbe, und die Meldung sah aus wie ein Zeichenfehler.
feld() { python3 tools/k15/wert.py "$1" "$2" "$3" 2>/dev/null; }
frgb() { python3 tools/k15/wert.py "$1" "$2" "$3" rgb 2>/dev/null; }
rgb() { python3 -c "v=int('${1:-0}');print((v>>16)&255,(v>>8)&255,v&255)"; }
# Das Rechteck eines Widgets, wie die Anwendung es gemeldet hat.
rect() { grep -aoE "^$2: rect id=$3 .*" "$1" | tail -1 | grep -oE "$4=[0-9]+" | sed 's/.*=//'; }

bash vendor/firn/hole-firnc.sh >/dev/null || { echo "vendor/firn/hole-firnc.sh fehlgeschlagen"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "K15: uebersprungen, qemu-system-x86_64 ist nicht da"
    exit 0
fi
DEJAVU=${DEJAVU:-/usr/share/fonts/truetype/dejavu}

MONO=assets/osum-mono.ttf
SANS=assets/osum-sans.ttf
GRUND="nokbd nosched noproc nofs"
BORDER=2
TITLE=22

# --------------------------------------------------------------- Laeufe

RC=0
foto() { # name kommandozeile [monitordatei] [marke]
    local name=$1 zeile=$2 mon=${3:-} marke=${4:-'^wm: hold'}
    local sock="$TMPD/mon-$name.sock"
    local aus="$TMPD/$name.txt" ppm="$TMPD/$name.ppm"
    rm -f "$aus" "$ppm" "$sock"
    cp -f "$TMPD/disk.img" "$TMPD/live-$name.img"
    timeout 240 qemu-system-x86_64 -kernel "$TMPD/k0.mb" -m 256 \
        -append "$zeile" -serial "file:$aus" -display none -no-reboot \
        -vga std -monitor "unix:$sock,server,nowait" \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local pid=$!
    local i=0
    while [ $i -lt 1400 ]; do
        grep -qaE "$marke" "$aus" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.15
        i=$((i + 1))
    done
    if [ -n "$mon" ]; then
        python3 tools/wm/monitor.py "$sock" "$mon" > "$TMPD/$name.monlog" 2>&1
    fi
    python3 tools/gfx/schuss.py "$sock" "$ppm" 25 > "$TMPD/$name.shot" 2>&1
    wait "$pid"
    RC=$?
    rm -f "$sock"
    return 0
}

# Der Weg des Zeigers: erst in die linke obere Ecke (der Anschlag
# loescht die Vorgeschichte), dann in Schritten unter 128 an die Stelle.
# DIESELBE BEGRUENDUNG WIE IN RUNDE K10, und sie gilt weiter: ein
# PS/2-Paket traegt neun Bit je Achse, und ein verlorenes Paket macht
# aus einer Rechnung eine Hoffnung.
zeiger() { # datei x y
    local f=$1 x=$2 y=$3 i
    for i in 1 2 3 4 5 6; do echo "mouse_move -120 -120" >> "$f"; done
    local dx=$x dy=$y
    while [ "$dx" -gt 0 ] || [ "$dy" -gt 0 ]; do
        local sx=$dx sy=$dy
        [ "$sx" -gt 120 ] && sx=120
        [ "$sy" -gt 120 ] && sy=120
        echo "mouse_move $sx $sy" >> "$f"
        dx=$((dx - sx)); dy=$((dy - sy))
    done
}

echo "== 1. bauen: der Kern, die Bibliothek und die Programme, aus beiden Uebersetzern =="
for s in 0 1; do
    if bash tools/build-kernel.sh "$TMPD/k$s.mb" --stufe "$s" > "$TMPD/b$s.log" 2>&1; then
        ok "firnc$s: Kernel gebaut ($(stat -c%s "$TMPD/k$s.mb") Oktette)"
    else
        bad "firnc$s: der Kernel laesst sich nicht bauen"
        sed 's/^/        /' "$TMPD/b$s.log" | head -12
    fi
done
[ -f "$TMPD/k0.mb" ] || { echo "K15: $pass passed, $((fail + 1)) failed"; exit 1; }

PROGS="wigdemo files sh echo ls cat"
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
baue 0 && ok "firnc0: $(echo $PROGS | wc -w) Programme gebaut, davon /bin/files mit $(stat -c%s "$TMPD/files0.elf") Oktetten" \
    || bad "firnc0: die Programme dieser Runde lassen sich nicht bauen"
baue 1 && ok "firnc1: dieselben aus dem Uebersetzer, der in Firn geschrieben ist" \
    || bad "firnc1: die Programme dieser Runde lassen sich nicht bauen"
# DIE BIBLIOTHEK IST EINE BIBLIOTHEK: sie hat kein `u_start`, sie wird
# EINGEBUNDEN. Das ist die Zusage "in Ring 3, nicht im Kernel" in ihrer
# pruefbaren Form -- und dazu, dass der Kernel sie NICHT enthaelt.
if nm "$TMPD/files0.elf" 2>/dev/null | grep -q . ; then :; fi
for sym in wig__button wig__step wigc__text_at; do
    if nm -a "$TMPD/k0.mb.elf" 2>/dev/null | grep -q "$sym"; then
        bad "der Kernel traegt $sym -- die Bibliothek gehoert nach Ring 3"
    else
        ok "der Kernel traegt $sym NICHT (die Bibliothek liegt in Ring 3)"
    fi
done
wigzeilen=$(cat kernel/user/wig.fi kernel/user/wigc.fi | wc -l)
kernzeilen=$(wc -l < kernel/wig.fi)
num "Zeilen der Bibliothek in Ring 3" "$wigzeilen" gt 1500
num "Zeilen der Naht im Kernel -- so wenig Kernel wie moeglich" "$kernzeilen" lt 600

# Das Abbild: die Schriften, die Programme, das Farbschema, der Baum.
python3 tools/k15/baum.py "$TMPD/baum" > "$TMPD/baum.log" 2>&1 \
    && ok "der Verzeichnisbaum fuer den Dateimanager ist gebaut ($(head -1 "$TMPD/baum.log"))" \
    || bad "tools/k15/baum.py fehlgeschlagen"
ARGS=(build "$TMPD/disk.img" 4096 /lib/
      "/lib/mono.ttf=$MONO" "/lib/sans.ttf=$SANS" /bin/)
for p in $PROGS; do ARGS+=("/bin/$p=$TMPD/${p}0.elf"); done
ARGS+=(/etc/ "/etc/theme=$TMPD/baum/theme")
while read -r z; do ARGS+=("$z"); done < "$TMPD/baum/liste"
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "mkfs.py baut ein Abbild mit den Schriften, den Programmen und /etc/theme" \
    || { bad "mkfs.py fehlgeschlagen"; sed 's/^/        /' "$TMPD/mkfs.txt" | head -6; }

echo "== 2. die Speicherkarte: drei Seiten, und nur die drei =="
kart=$(python3 tools/kernel/karte.py kernel 2>&1)
if [ $? -eq 0 ]; then ok "die Speicherkarte von kdata: $kart"
else bad "die Speicherkarte von kdata kollidiert"; echo "$kart" | sed 's/^/        /'; fi
if python3 tools/kernel/karte.py kernel -v 2>/dev/null | grep -q " WIG  *kstate.fi:"; then
    ok "der Bereich WIG steht in der Karte"
else
    bad "der Bereich WIG steht NICHT in der Karte"
fi
# DER VORRAT, DER DIESER RUNDE GEHOERT. Drei Runden liefen gleichzeitig;
# genau daran waeren drei Merges beinahe gescheitert. Also wird
# nachgerechnet, dass diese Runde in ihrem Vorrat geblieben ist.
wo=$(python3 tools/kernel/karte.py kernel -v 2>/dev/null | grep ' WIG ' | grep -oE '0x[0-9A-Fa-f]+' | head -2 | tr '\n' ' ')
gleich "der Bereich liegt im zugeteilten Vorrat" "0x46000 0x49000 " "$wo"
for n in 1800 1806; do
    grep -q "= $n$" kernel/sys.fi && ok "die Aufrufnummer $n steht in kernel/sys.fi" \
        || bad "die Aufrufnummer $n fehlt"
done
if grep -qE 'WIG_(BASE|MAXNR)' kernel/sys.fi && \
   ! grep -qE 'const WIG_[A-Z]+: u64 = (19[0-9][0-9]|17[0-9][0-9])' kernel/sys.fi; then
    ok "alle Aufrufe dieser Runde liegen zwischen 1800 und 1899"
else
    bad "eine Aufrufnummer dieser Runde liegt ausserhalb von 1800..1899"
fi
# Gegenprobe zum Kartenpruefer: legt man WIG auf die Seiten des
# Fensterservers, MUSS er anschlagen.
GG="$TMPD/kernel-gg"; mkdir -p "$GG"; cp kernel/*.fi "$GG/"
sed -i 's/^const WIG_OFF: u64 = 0x46000/const WIG_OFF: u64 = 0x1E000/' "$GG/kstate.fi"
gg=$(python3 tools/kernel/karte.py "$GG" 2>&1)
if [ $? -ne 0 ] && printf '%s' "$gg" | grep -q 'KOLLISION'; then
    ok "mit WIG_OFF auf 0x1E000 findet der Pruefer die Kollision mit WM"
else
    bad "der Kollisionspruefer findet die neue Kollision NICHT: $gg"
fi

echo "== 3. die Anwendung steht da: Anordnung, Rechtecke, Reihenfolge =="
foto ruhe "gfx wm wig wmhold wiglong $GRUND"
num "der Kern beendet sich sauber" "$RC" eq 21
has "$TMPD/ruhe.txt" "wm: hold" "der Kern haelt fuer das Foto still"
ws=$(zahl "$TMPD/ruhe.txt" 'wig: selftest [0-9]+')
num "die Zusagen der Naht ueber sich selbst" "$ws" eq 7
has "$TMPD/ruhe.txt" "k15: start /bin/wigdemo" "die Anwendung kommt VON DER PLATTE"
has "$TMPD/ruhe.txt" "wigdemo: ready" "sie hat ihr Fenster angelegt und gemalt"
WX=60; WY=60
BW=$(feld "$TMPD/ruhe.txt" "wigdemo: geom" w)
BH=$(feld "$TMPD/ruhe.txt" "wigdemo: geom" h)
num "das Fenster ist so breit, wie die Anwendung es bestellt hat" "$BW" eq 480
num "und so hoch" "$BH" eq 400
CX=$((WX + BORDER)); CY=$((WY + TITLE))
aus=$(python3 tools/k15/anordnung.py "$TMPD/ruhe.txt" wigdemo "$BW" "$BH" 12 2>&1)
if [ $? -eq 0 ]; then ok "die Anordnung: $aus"
else bad "die Anordnung stimmt nicht"; echo "$aus" | sed 's/^/        /' | head -8; fi
# Und die Gegenprobe zum Pruefer selbst: ein Rechteck, das aus dem
# Fenster ragt, MUSS auffallen -- sonst prueft er nichts.
sed 's/^wigdemo: rect id=11 .*/wigdemo: rect id=11 kind=5 x=12 y=372 w=456 h=112 /' \
    "$TMPD/ruhe.txt" > "$TMPD/ruhe-gg.txt"
if python3 tools/k15/anordnung.py "$TMPD/ruhe-gg.txt" wigdemo "$BW" "$BH" 12 >/dev/null 2>&1; then
    bad "der Anordnungspruefer laesst ein Rechteck durch, das aus dem Fenster ragt"
else
    ok "ein Rechteck, das aus dem Fenster ragt, faellt dem Pruefer auf"
fi

echo "== 4. der Text -- JE ZEICHEN gegen die zweite Rasterung =="
# Die Stelle und die beiden Farben sagt die ANWENDUNG. Nachgerechnet
# wird im Bild, Zeichen fuer Zeichen, mit der Deckkraft aus dem
# Rasterer -- nicht Flaeche gegen Flaeche. Das ist die Lehre aus K7B.
pruef_text() { # marke erwarteter-text
    local marke=$1 soll=$2
    local zeile x base fg bg text
    zeile=$(grep -a "^wigdemo: text $marke " "$TMPD/ruhe.txt" | tail -1)
    if [ -z "$zeile" ]; then bad "die Anwendung meldet die Textstelle '$marke' nicht"; return; fi
    x=$(printf '%s' "$zeile" | grep -oE 'x=[0-9]+' | head -1 | sed 's/.*=//')
    base=$(printf '%s' "$zeile" | grep -oE 'base=[0-9]+' | sed 's/.*=//')
    fg=$(printf '%s' "$zeile" | grep -oE 'fg=[0-9]+' | sed 's/.*=//')
    bg=$(printf '%s' "$zeile" | grep -oE 'bg=[0-9]+' | sed 's/.*=//')
    text=${zeile#*t=}
    gleich "die Anwendung meldet den Text '$marke'" "$soll" "$text"
    schau "'$soll' steht bildpunktgenau im Fenster ($marke)" \
        ttext "$TMPD/ruhe.ppm" "$SANS" 15 $((CX + x)) $((CY + base)) \
        $(rgb "$fg") $(rgb "$bg") "$soll"
}
pruef_text kopf "OSUM K15 WIDGETS"
pruef_text knopf "Knopf"
pruef_text e1 "Kopiermich"
# Die Liste: fuenf Zeilen, jede an ihrer eigenen Grundlinie, und die
# erste in der AUSWAHLFARBE -- zwei verschiedene Farbpaare in einem
# Widget, und beide muessen aufgehen.
RX=$(feld "$TMPD/ruhe.txt" "wigdemo: rows" x)
RB=$(feld "$TMPD/ruhe.txt" "wigdemo: rows" base)
ZH=$(feld "$TMPD/ruhe.txt" "wigdemo: rows" zh)
RFG=$(frgb "$TMPD/ruhe.txt" "wigdemo: rows" fg)
RBG=$(frgb "$TMPD/ruhe.txt" "wigdemo: rows" bg)
RSEL=$(frgb "$TMPD/ruhe.txt" "wigdemo: rows" sel)
RSFG=$(frgb "$TMPD/ruhe.txt" "wigdemo: rows" selfg)
num "die Zeilenhoehe der Liste" "$ZH" eq 20
schau "Zeile 0 der Liste, in der AUSWAHLFARBE" \
    ttext "$TMPD/ruhe.ppm" "$SANS" 15 $((CX + RX)) $((CY + RB)) \
    $RSFG $RSEL "alpha"
i=1
for wort in beta gamma delta epsilon; do
    schau "Zeile $i der Liste" \
        ttext "$TMPD/ruhe.ppm" "$SANS" 15 $((CX + RX)) $((CY + RB + i * ZH)) \
        $RFG $RBG "$wort"
    i=$((i + 1))
done
# DREI GEGENPROBEN ZUM PRUEFER SELBST.
schau_nicht "derselbe Pruefer geht mit dem FALSCHEN Text NICHT auf" \
    ttext "$TMPD/ruhe.ppm" "$SANS" 15 $((CX + RX)) $((CY + RB + ZH)) \
    $RFG $RBG "gamma"
schau_nicht "und an einer Stelle, an der kein Text steht, auch nicht" \
    ttext "$TMPD/ruhe.ppm" "$SANS" 15 $((CX + RX)) $((CY + RB + 8 * ZH)) \
    $RFG $RBG "alpha"
schau_nicht "und mit der falschen Hintergrundfarbe auch nicht" \
    ttext "$TMPD/ruhe.ppm" "$SANS" 15 $((CX + RX)) $((CY + RB + ZH)) \
    $RFG 0 0 0 "beta"
# IST ES WIRKLICH KANTENGEGLAETTET? Eine Rasterung ohne Glaettung haette
# keine einzige Zwischenstufe und ginge durch alles oben hindurch.
schau "der Text der Bibliothek ist wirklich kantengeglaettet" \
    glatt "$TMPD/ruhe.ppm" $((CX + RX)) $((CY + RB - 14)) 120 60 \
    $RFG $RBG 100

echo "== 5. die Widgets stehen da, wo die Anordnung sie hingelegt hat =="
# Der Fokusring: ein Rahmen von einem Bildpunkt um GENAU das Widget mit
# dem Eingabefokus -- und einen Bildpunkt daneben ist er nicht.
FX=$(rect "$TMPD/ruhe.txt" wigdemo 1 x); FY=$(rect "$TMPD/ruhe.txt" wigdemo 1 y)
FW=$(rect "$TMPD/ruhe.txt" wigdemo 1 w); FH=$(rect "$TMPD/ruhe.txt" wigdemo 1 h)
schau "der Fokusring liegt bildpunktgenau um die Reiter" \
    rechteck "$TMPD/ruhe.ppm" $((CX + FX)) $((CY + FY)) "$FW" "$FH" 255 192 32
BX=$(rect "$TMPD/ruhe.txt" wigdemo 5 x); BY=$(rect "$TMPD/ruhe.txt" wigdemo 5 y)
BBW=$(rect "$TMPD/ruhe.txt" wigdemo 5 w); BBH=$(rect "$TMPD/ruhe.txt" wigdemo 5 h)
schau_nicht "und um den Knopf, der ihn NICHT hat, liegt keiner" \
    rechteck "$TMPD/ruhe.ppm" $((CX + BX)) $((CY + BY)) "$BBW" "$BBH" 255 192 32
schau "die Flaeche des Knopfes hat die Farbe aus /etc/theme (btn=3a4a5e)" \
    flaeche "$TMPD/ruhe.ppm" $((CX + BX + 3)) $((CY + BY + 3)) 16 5 58 74 94
# Das Textfeld hat einen dunkleren Grund als das Fenster -- sonst waere
# nicht zu sehen, dass es eines ist.
EX=$(rect "$TMPD/ruhe.txt" wigdemo 3 x); EY=$(rect "$TMPD/ruhe.txt" wigdemo 3 y)
schau "das Textfeld hat seine eigene Flaeche" \
    flaeche "$TMPD/ruhe.ppm" $((CX + EX + 300)) $((CY + EY + 6)) 60 10 18 24 32

echo "== 6. bedienen: echte Klicks aus dem QEMU-Monitor =="
# Die Stellen kommen aus den Rechtecken, die die Anwendung gemeldet hat
# -- nicht aus Zahlen, die hier stehen.
mitte() { # id -> "x y" auf dem BILDSCHIRM
    local x y w h
    x=$(rect "$TMPD/ruhe.txt" wigdemo "$1" x); y=$(rect "$TMPD/ruhe.txt" wigdemo "$1" y)
    w=$(rect "$TMPD/ruhe.txt" wigdemo "$1" w); h=$(rect "$TMPD/ruhe.txt" wigdemo "$1" h)
    echo "$((CX + x + w / 2)) $((CY + y + h / 2))"
}
KNOPF=$(mitte 5); HAKEN_X=$((CX + $(rect "$TMPD/ruhe.txt" wigdemo 7 x) + 7))
HAKEN_Y=$((CY + $(rect "$TMPD/ruhe.txt" wigdemo 7 y) + 14))
LX=$(rect "$TMPD/ruhe.txt" wigdemo 11 x); LY=$(rect "$TMPD/ruhe.txt" wigdemo 11 y)
E1Y=$(rect "$TMPD/ruhe.txt" wigdemo 3 y); E2Y=$(rect "$TMPD/ruhe.txt" wigdemo 4 y)
E1H=$(rect "$TMPD/ruhe.txt" wigdemo 3 h)
# Der zweite Reiter: hinter dem ersten. Seine Breite steht nicht im
# Mitschnitt, also wird der Punkt so gewaehlt, dass er sicher im
# zweiten liegt -- und die Zusage prueft, WELCHER Reiter aktiv wurde.
TABX=$((CX + $(rect "$TMPD/ruhe.txt" wigdemo 1 x) + 130))
TABY=$((CY + $(rect "$TMPD/ruhe.txt" wigdemo 1 y) + 13))

M="$TMPD/klick.mon"; : > "$M"
zeiger "$M" ${KNOPF% *} ${KNOPF#* }
cat >> "$M" <<EOF
mouse_button 1
warte 0.3
mouse_button 0
warte 0.3
EOF
foto klick "gfx wm wig wmhold wiglong $GRUND" "$M"
num "der Kern beendet sich sauber" "$RC" eq 21
has "$TMPD/klick.txt" "wigdemo: fired id=5 kind=2" "der Knopf meldet sich -- mit seiner Nummer und seiner Art"
kl=$(feld "$TMPD/klick.txt" "wigdemo: state" klicks)
num "und genau EINMAL" "$kl" eq 1
hasnot "$TMPD/ruhe.txt" "wigdemo: fired" "ohne Klick meldet sich kein Widget"

M="$TMPD/haken.mon"; : > "$M"
zeiger "$M" "$HAKEN_X" "$HAKEN_Y"
cat >> "$M" <<EOF
mouse_button 1
warte 0.3
mouse_button 0
warte 0.5
mouse_move 120 120
mouse_move 60 60
EOF
foto haken "gfx wm wig wmhold wiglong $GRUND" "$M"
has "$TMPD/haken.txt" "wigdemo: fired id=7 kind=3 ix=1" "das Kaestchen kippt und meldet seinen neuen Wert"
# UND DAS IST IM BILD ZU SEHEN: der Haken ist aus zwei Strichen in der
# Betonungsfarbe. Ohne Klick ist dort KEIN einziger solcher Bildpunkt.
HKX=$((CX + $(rect "$TMPD/ruhe.txt" wigdemo 7 x))); HKY=$((CY + $(rect "$TMPD/ruhe.txt" wigdemo 7 y) + 7))
mit=$(python3 tools/k15/zaehl.py "$TMPD/haken.ppm" "$HKX" "$HKY" 14 14 92 200 255)
ohne=$(python3 tools/k15/zaehl.py "$TMPD/ruhe.ppm" "$HKX" "$HKY" 14 14 92 200 255)
num "Bildpunkte des Hakens NACH dem Klick" "$mit" gt 12
num "und VOR dem Klick (die Gegenprobe)" "$ohne" eq 0

M="$TMPD/reiter.mon"; : > "$M"
zeiger "$M" "$TABX" "$TABY"
cat >> "$M" <<EOF
mouse_button 1
warte 0.3
mouse_button 0
warte 0.4
EOF
foto reiter "gfx wm wig wmhold wiglong $GRUND" "$M"
rt=$(feld "$TMPD/reiter.txt" "wigdemo: state" reiter)
num "der zweite Reiter ist aktiv" "$rt" eq 1
has "$TMPD/reiter.txt" "wigdemo: fired id=1 kind=7 ix=1" "und der Reiter meldet den Wechsel"

echo "== 7. die Tastatur: Weiterschaltung, Tippen, Zwischenablage =="
# Klick in das erste Textfeld, alles auswaehlen, kopieren; in das
# zweite, einfuegen, drei Zeichen tippen. Der Weg der Zwischenablage
# geht WIRKLICH durch den Kernel (WIG_CLIPSET/WIG_CLIPGET).
E1X=$((CX + 120))
M="$TMPD/tast.mon"; : > "$M"
zeiger "$M" "$E1X" $((CY + E1Y + E1H / 2))
cat >> "$M" <<EOF
mouse_button 1
mouse_button 0
warte 0.3
sendkey ctrl-a
sendkey ctrl-c
warte 0.3
mouse_move 0 $((E2Y - E1Y))
mouse_button 1
mouse_button 0
warte 0.3
sendkey ctrl-v
sendkey minus
sendkey a
sendkey b
warte 0.6
mouse_move 120 120
mouse_move 60 60
EOF
foto tast "gfx wm wig wmhold wiglong $GRUND" "$M"
num "der Kern beendet sich sauber" "$RC" eq 21
e2=$(grep -a 'wigdemo: state' "$TMPD/tast.txt" | tail -1 | sed 's/.*e2=\[//; s/\]$//')
gleich "was im zweiten Textfeld steht" "Kopiermich-ab" "$e2"
cs=$(feld "$TMPD/tast.txt" "wig: blits" clipset)
cg=$(feld "$TMPD/tast.txt" "wig: blits" clipget)
num "in die Zwischenablage geschrieben" "$cs" ge 1
num "und daraus gelesen" "$cg" ge 1
# UND ES STEHT IM BILD, Zeichen fuer Zeichen.
EBG=$(frgb "$TMPD/ruhe.txt" "wigdemo: text e1" bg)
EFG=$(frgb "$TMPD/ruhe.txt" "wigdemo: text e1" fg)
EBASE=$(feld "$TMPD/ruhe.txt" "wigdemo: text e1" base)
E1TX=$(feld "$TMPD/ruhe.txt" "wigdemo: text e1" x)
schau "und es steht bildpunktgenau im zweiten Feld" \
    ttext "$TMPD/tast.ppm" "$SANS" 15 $((CX + E1TX)) $((CY + EBASE + E2Y - E1Y)) \
    $EFG $EBG "Kopiermich-ab"
schau_nicht "im Lauf OHNE Tastendruecke steht dort NICHTS" \
    ttext "$TMPD/ruhe.ppm" "$SANS" 15 $((CX + E1TX)) $((CY + EBASE + E2Y - E1Y)) \
    $EFG $EBG "Kopiermich-ab"
# DIE GEGENPROBE, DIE DIE ZUSAGE ERST WERTVOLL MACHT: dieselben
# Tastendruecke mit abgeschalteter Zwischenablage.
foto noclip "gfx wm wig wignoclip wmhold wiglong $GRUND" "$M"
e2n=$(grep -a 'wigdemo: state' "$TMPD/noclip.txt" | tail -1 | sed 's/.*e2=\[//; s/\]$//')
gleich "mit 'noclip' kommt NUR das Getippte an" "-ab" "$e2n"
schau_nicht "und im Bild steht der eingefuegte Text dann nicht" \
    ttext "$TMPD/noclip.ppm" "$SANS" 15 $((CX + E1TX)) $((CY + EBASE + E2Y - E1Y)) \
    $EFG $EBG "Kopiermich-ab"
# Die Weiterschaltung mit der Tabulatortaste.
M="$TMPD/tab.mon"; : > "$M"
zeiger "$M" "$E1X" $((CY + E1Y + E1H / 2))
cat >> "$M" <<EOF
mouse_button 1
mouse_button 0
warte 0.3
sendkey tab
warte 0.4
sendkey x
sendkey y
warte 0.5
mouse_move 120 120
mouse_move 60 60
EOF
foto tabkey "gfx wm wig wmhold wiglong $GRUND" "$M"
e2t=$(grep -a 'wigdemo: state' "$TMPD/tabkey.txt" | tail -1 | sed 's/.*e2=\[//; s/\]$//')
gleich "nach der Tabulatortaste tippt man in das NAECHSTE Feld" "xy" "$e2t"
e1t=$(grep -a 'wigdemo: state' "$TMPD/tabkey.txt" | tail -1 | sed 's/.*e1=\[//; s/\] e2.*//')
gleich "und im vorigen steht unveraendert, was darin stand" "Kopiermich" "$e1t"
schau "der Fokusring ist mitgewandert -- er liegt jetzt um das zweite Feld" \
    rechteck "$TMPD/tabkey.ppm" $((CX + $(rect "$TMPD/ruhe.txt" wigdemo 4 x))) \
    $((CY + E2Y)) $(rect "$TMPD/ruhe.txt" wigdemo 4 w) \
    $(rect "$TMPD/ruhe.txt" wigdemo 4 h) 255 192 32
schau_nicht "und NICHT mehr um das erste" \
    rechteck "$TMPD/tabkey.ppm" $((CX + $(rect "$TMPD/ruhe.txt" wigdemo 3 x))) \
    $((CY + E1Y)) $(rect "$TMPD/ruhe.txt" wigdemo 3 w) "$E1H" 255 192 32

echo "== 8. Menues und Dialoge -- eigene Fenster beim Server =="
# Die rechte Maustaste auf der Liste. SIE IST BIT 1 UND NICHT BIT 2:
# der PS/2-Baustein legt links auf Bit 0, rechts auf Bit 1, die Mitte
# auf Bit 2, und der QEMU-Monitor nimmt dieselbe Reihenfolge
# (`mouse_button 2` ist rechts). Die erste Fassung dieser Runde pruefte
# auf 4, und das Kontextmenue klappte nie auf.
POPX=$((CX + LX + 100)); POPY=$((CY + LY + 42))
M="$TMPD/pop.mon"; : > "$M"
zeiger "$M" "$POPX" "$POPY"
cat >> "$M" <<EOF
mouse_button 2
warte 0.3
mouse_button 0
warte 0.8
# DEN ZEIGER WEGFAHREN, BEVOR FOTOGRAFIERT WIRD. Er steht sonst auf der
# linken oberen Ecke des Menuefensters -- genau dort, wo es aufklappt --
# und deckt fuenfzehn Bildpunkte des Rahmens zu. Das Menue bleibt dabei
# offen: es schliesst sich beim WAEHLEN, nicht beim Verlassen.
mouse_move 120 -120
mouse_move 120 -120
mouse_move 120 -30
warte 0.5
EOF
foto pop "gfx wm wig wmhold wiglong $GRUND" "$M"
has "$TMPD/pop.txt" "wigdemo: fired id=11 kind=11" "die rechte Taste kommt bei der Liste an, mit der Zeile"
has "$TMPD/pop.txt" "wigdemo: menu " "und die Bibliothek macht ein EIGENES Fenster dafuer auf"
MNX=$(feld "$TMPD/pop.txt" "wigdemo: menu" x)
MNY=$(feld "$TMPD/pop.txt" "wigdemo: menu" y)
MNW=$(feld "$TMPD/pop.txt" "wigdemo: menu" w)
MNH=$(feld "$TMPD/pop.txt" "wigdemo: menu" h)
MZH=$(feld "$TMPD/pop.txt" "wigdemo: menu" zh)
gleich "es liegt genau am Zeiger" "$POPX $POPY" "$MNX $MNY"
num "und ist so hoch, wie drei Punkte brauchen" "$MNH" eq $((3 * MZH + 4))
# DAS MENUE LIEGT AM ZEIGER, also an einer Stelle, die kein Testlaeufer
# erraten kann. Er bekommt sie gesagt und rechnet den Text darin je
# Zeichen nach -- auf dem Grund, den das Farbschema fuer Menues fuehrt.
MENUBG=$(python3 -c "print(0x2a3542)")
i=0
for punkt in Oeffnen Umbenennen Entfernen; do
    # TOLERANZ 96, UND HIER STEHT DIE GEMESSENE ZAHL DAZU. Wo sich zwei
    # Glyphenkaesten ueberlappen -- "ff" in "Oeffnen" --, mischt die
    # Bibliothek (und `wm.text` genauso) Zeichen AUF Zeichen, waehrend
    # der Referenzrasterer jedes auf den reinen Grund mischt. Gemessen
    # an dieser Zeile: bei Toleranz 0 sind 4 von 345 Tintenpunkten
    # verschieden, bei 32 noch 2, bei 64 noch 1, bei 96 keiner. Die
    # groesste Abweichung ist also kleiner als 96 von 255 Stufen und
    # betrifft vier Bildpunkte. Dass die Zusage damit trotzdem etwas
    # prueft, zeigt die Gegenprobe darunter: ein anderes Wort faellt
    # auch bei Toleranz 128 durch (146 falsch, zwei Zeichen ohne Tinte).
    schau "Menuepunkt $i steht bildpunktgenau im Menuefenster: '$punkt'" \
        ttext "$TMPD/pop.ppm" "$SANS" 15 $((MNX + BORDER + 8)) \
        $((MNY + TITLE + 15 + i * MZH)) $(rgb 15265524) $(rgb "$MENUBG") "$punkt" 96
    i=$((i + 1))
done
schau "der Rahmen des Menuefensters liegt bildpunktgenau" \
    rechteck "$TMPD/pop.ppm" "$MNX" "$MNY" $((MNW + 2 * BORDER)) \
    $((MNH + TITLE + BORDER)) 76 154 232
schau_nicht "ohne rechte Taste gibt es das Menue NICHT" \
    ttext "$TMPD/ruhe.ppm" "$SANS" 15 $((MNX + BORDER + 8)) \
    $((MNY + TITLE + 15)) $(rgb 15265524) $(rgb "$MENUBG") "Oeffnen" 96
schau_nicht "und ein anderes Wort steht auch bei Toleranz 64 nicht dort" \
    ttext "$TMPD/pop.ppm" "$SANS" 15 $((MNX + BORDER + 8)) \
    $((MNY + TITLE + 15)) $(rgb 15265524) $(rgb "$MENUBG") "Schuetzen" 128
# Und ein Klick darauf waehlt.
M="$TMPD/popw.mon"; : > "$M"
zeiger "$M" "$POPX" "$POPY"
cat >> "$M" <<EOF
mouse_button 2
warte 0.3
mouse_button 0
warte 0.8
mouse_move 20 25
mouse_button 1
warte 0.3
mouse_button 0
warte 0.6
EOF
foto popw "gfx wm wig wmhold wiglong $GRUND" "$M"
has "$TMPD/popw.txt" "wigdemo: fired id=11 kind=8" "ein Klick auf einen Menuepunkt meldet ihn beim Besitzer"
mn=$(feld "$TMPD/popw.txt" "wigdemo: state" menues)
num "und das Menue hat genau EINMAL gefeuert" "$mn" ge 1
schau_nicht "danach ist das Menuefenster wieder weg" \
    ttext "$TMPD/popw.ppm" "$SANS" 15 $((MNX + BORDER + 8)) \
    $((MNY + TITLE + 15)) $(rgb 15265524) $(rgb "$MENUBG") "Oeffnen" 96

# Der Dialog: der Knopf "Loeschen" macht ihn auf.
DEL=$(mitte 9)
M="$TMPD/dlg.mon"; : > "$M"
zeiger "$M" ${DEL% *} ${DEL#* }
cat >> "$M" <<EOF
mouse_button 1
mouse_button 0
warte 1.0
EOF
foto dlg "gfx wm wig wmhold wiglong $GRUND" "$M"
has "$TMPD/dlg.txt" "wigdemo: dlgwin" "der Dialog ist ein eigenes Fenster"
DW=$(feld "$TMPD/dlg.txt" "wigdemo: dlgwin" w)
DH=$(feld "$TMPD/dlg.txt" "wigdemo: dlgwin" h)
num "er ist so breit, wie die Bibliothek ihn baut" "$DW" eq 340
DLX=$(( (800 - DW) / 2 )); DLY=$(( (600 - DH) / 2 ))
schau "und er steht mittig auf dem Schirm, bildpunktgenau" \
    rechteck "$TMPD/dlg.ppm" "$DLX" "$DLY" $((DW + 4)) $((DH + 24)) 76 154 232
DTX=$(feld "$TMPD/dlg.txt" "wigdemo: text dlg" x)
DTB=$(feld "$TMPD/dlg.txt" "wigdemo: text dlg" base)
DTF=$(frgb "$TMPD/dlg.txt" "wigdemo: text dlg" fg)
DTG=$(frgb "$TMPD/dlg.txt" "wigdemo: text dlg" bg)
schau "seine Frage steht darin, je Zeichen" \
    ttext "$TMPD/dlg.ppm" "$SANS" 15 $((DLX + BORDER + DTX)) \
    $((DLY + TITLE + DTB)) $DTF $DTG "Neuer Name"
# Den Knopf anklicken, den die Bibliothek gemeldet hat.
OKX=$(grep -a 'wigdemo: dlgrect' "$TMPD/dlg.txt" | head -1 | grep -oE 'x=[0-9]+' | sed 's/.*=//')
OKY=$(grep -a 'wigdemo: dlgrect' "$TMPD/dlg.txt" | head -1 | grep -oE 'y=[0-9]+' | sed 's/.*=//')
OKW=$(grep -a 'wigdemo: dlgrect' "$TMPD/dlg.txt" | head -1 | grep -oE 'w=[0-9]+' | sed 's/.*=//')
OKH=$(grep -a 'wigdemo: dlgrect' "$TMPD/dlg.txt" | head -1 | grep -oE 'h=[0-9]+' | sed 's/.*=//')
M="$TMPD/dlgok.mon"; : > "$M"
zeiger "$M" ${DEL% *} ${DEL#* }
cat >> "$M" <<EOF
mouse_button 1
mouse_button 0
warte 1.0
EOF
zeiger "$M" $((DLX + 2 + OKX + OKW / 2)) $((DLY + 22 + OKY + OKH / 2))
cat >> "$M" <<EOF
mouse_button 1
mouse_button 0
warte 0.8
EOF
foto dlgok "gfx wm wig wmhold wiglong $GRUND" "$M"
has "$TMPD/dlgok.txt" "wigdemo: dlg state=2" "der Dialog wird mit OK bestaetigt und gibt seinen Text zurueck"
dt=$(grep -a 'wigdemo: dlg state=2' "$TMPD/dlgok.txt" | tail -1 | sed 's/.*text=//')
gleich "und der Text ist der, mit dem er aufgemacht wurde" "Kopiermich" "$dt"
schau_nicht "danach ist auch das Dialogfenster weg" \
    rechteck "$TMPD/dlgok.ppm" "$DLX" "$DLY" $((DW + 4)) $((DH + 24)) 76 154 232

echo "== 9. der Dateimanager: /bin/files gegen die Platte =="
foto files "gfx wm wigfiles wmhold wiglong $GRUND"
num "der Kern beendet sich sauber" "$RC" eq 21
has "$TMPD/files.txt" "k15: start /bin/files" "/bin/files kommt von der Platte"
has "$TMPD/files.txt" "files: ready" "und hat sein Fenster gemalt"
FN=$(feld "$TMPD/files.txt" "files: cd" n)
SOLLN=$(wc -l < "$TMPD/baum/soll.txt")
num "er zaehlt so viele Stuecke in /daten, wie baum.py angelegt hat" "$FN" eq "$SOLLN"
FBW=$(feld "$TMPD/files.txt" "files: geom" w); FBH=$(feld "$TMPD/files.txt" "files: geom" h)
FWX=$(feld "$TMPD/files.txt" "files: geom" x); FWY=$(feld "$TMPD/files.txt" "files: geom" y)
FCX=$((FWX + BORDER)); FCY=$((FWY + TITLE))
aus=$(python3 tools/k15/anordnung.py "$TMPD/files.txt" files "$FBW" "$FBH" 8 2>&1)
if [ $? -eq 0 ]; then ok "die Anordnung des Dateimanagers: $aus"
else bad "die Anordnung des Dateimanagers stimmt nicht"; echo "$aus" | sed 's/^/        /' | head -6; fi
TX=$(feld "$TMPD/files.txt" "files: rows" x)
TB=$(feld "$TMPD/files.txt" "files: rows" base)
TZH=$(feld "$TMPD/files.txt" "files: rows" zh)
TKOPF=$(feld "$TMPD/files.txt" "files: rows" kopf)
TFG=$(frgb "$TMPD/files.txt" "files: rows" fg)
TBG=$(frgb "$TMPD/files.txt" "files: rows" bg)
TSEL=$(frgb "$TMPD/files.txt" "files: rows" sel)
TSFG=$(frgb "$TMPD/files.txt" "files: rows" selfg)
TDIM=$(frgb "$TMPD/files.txt" "files: rows" dim)
SP=($(grep -a '^files: spalten' "$TMPD/files.txt" | tail -1 | sed 's/^files: spalten //'))
schau "die Kopfzeile: die erste Spalte heisst 'Name'" \
    ttext "$TMPD/files.ppm" "$SANS" 15 $((FCX + TX)) $((FCY + TKOPF)) \
    $TFG $(rgb 3293262) "Name"
schau "und die zweite 'Groesse'" \
    ttext "$TMPD/files.ppm" "$SANS" 15 $((FCX + ${SP[1]})) $((FCY + TKOPF)) \
    $TFG $(rgb 3293262) "Groesse"
# JEDE ZEILE, JE ZEICHEN, GEGEN DAS, WAS baum.py ANGELEGT HAT -- und in
# derselben Reihenfolge: Verzeichnisse zuerst, dann nach Namen.
zeile=0
while IFS=$'\t' read -r name gr kind; do
    y=$((FCY + TB + zeile * TZH))
    if [ "$zeile" = 0 ]; then vg="$TSFG"; hg="$TSEL"; else vg="$TFG"; hg="$TBG"; fi
    schau "Zeile $zeile der Tabelle: '$name'" \
        ttext "$TMPD/files.ppm" "$SANS" 15 $((FCX + TX)) "$y" $vg $hg "$name"
    if [ "$kind" != "d" ] && [ "$zeile" != 0 ]; then
        schau "und ihre Groesse in Spalte 2: $gr" \
            ttext "$TMPD/files.ppm" "$SANS" 15 $((FCX + ${SP[1]})) "$y" \
            $TDIM $hg "$gr"
    fi
    zeile=$((zeile + 1))
done < "$TMPD/baum/soll.txt"
# Die Spalte "Rechte" kommt aus den Bits, die `stat` meldet -- 0755 fuer
# ein Verzeichnis, 0644 fuer eine Datei. Sie steht hier, WEIL sie sonst
# eine hingeschriebene Zeichenkette waere.
# EINE BENANNTE TOLERANZ, UND HIER STEHT WARUM. Der Referenzrasterer
# mischt JEDES Zeichen auf den reinen Hintergrund; die Bibliothek (und
# `wm.text` genauso) mischt es auf das, was schon da steht. Wo sich zwei
# Glyphenkaesten ueberlappen -- bei "rw" in dieser Schrift und Groesse um
# einen Bildpunkt --, kommt deshalb ein anderer Zwischenwert heraus.
# Gemessen: 4 von 373 Tintenpunkten, und die Abweichung ist kleiner als
# 64 Stufen. Mit Toleranz 0 waere die Zusage falsch, mit Toleranz 64 ist
# sie richtig -- und die Gegenprobe daneben zeigt, dass sie trotzdem
# etwas prueft: eine ANDERE Rechtezeichenkette faellt durch.
schau "die Rechte eines Verzeichnisses, aus den Bits von stat" \
    ttext "$TMPD/files.ppm" "$SANS" 15 $((FCX + ${SP[3]})) $((FCY + TB)) \
    $TSFG $TSEL "drwxr-xr-x" 64
schau_nicht "und eine ANDERE Rechtezeichenkette faellt bei derselben Toleranz durch" \
    ttext "$TMPD/files.ppm" "$SANS" 15 $((FCX + ${SP[3]})) $((FCY + TB)) \
    $TSFG $TSEL "drwxrwxrwx" 64
schau "und die einer Datei" \
    ttext "$TMPD/files.ppm" "$SANS" 15 $((FCX + ${SP[3]})) $((FCY + TB + 2 * TZH)) \
    $TDIM $TBG "-rw-r--r--" 64
# DIE SPALTE "ZEIT" IST LEER, UND DAS IST DIE EHRLICHE ZUSAGE: dieses
# Dateisystem hat keinen Zeitstempel (`kernel/fs.fi`: der Inode ist 128
# Oktette und voll). Eine erfundene Zeit waere schlimmer als keine.
schau "die Spalte Zeit zeigt zwei Striche -- OFS hat keinen Zeitstempel" \
    ttext "$TMPD/files.ppm" "$SANS" 15 $((FCX + ${SP[2]})) $((FCY + TB + 2 * TZH)) \
    $TDIM $TBG "--"

echo "== 9b. hineingehen, sortieren, anlegen =="
# Doppelklick auf Zeile 0 -- das ist ein Verzeichnis, also wird es
# geoeffnet, und danach steht ETWAS ANDERES in der Tabelle.
DX=$((FCX + TX + 60)); DY=$((FCY + TB - 8))
M="$TMPD/fdbl.mon"; : > "$M"
zeiger "$M" "$DX" "$DY"
cat >> "$M" <<EOF
mouse_button 1
mouse_button 0
mouse_button 1
mouse_button 0
warte 1.0
mouse_move 120 120
EOF
foto fdbl "gfx wm wigfiles wmhold wiglong $GRUND" "$M"
has "$TMPD/fdbl.txt" "files: cd /daten/bilder" "der Doppelklick geht in das Verzeichnis hinein"
n2=$(grep -a '^files: cd' "$TMPD/fdbl.txt" | tail -1 | grep -oE 'n=[0-9]+' | sed 's/.*=//')
num "und darin liegen zwei Dateien" "$n2" eq 2
schau "die erste davon steht im Bild" \
    ttext "$TMPD/fdbl.ppm" "$SANS" 15 $((FCX + TX)) $((FCY + TB)) \
    $TSFG $TSEL "blau.ppm"
schau_nicht "und der alte Inhalt steht NICHT mehr da" \
    ttext "$TMPD/fdbl.ppm" "$SANS" 15 $((FCX + TX)) $((FCY + TB)) \
    $TSFG $TSEL "bilder"
# Nach der Spalte "Groesse" sortieren: Kopfzeile anklicken.
SX=$((FCX + ${SP[1]} + 20)); SY=$((FCY + TKOPF - 6))
M="$TMPD/fsort.mon"; : > "$M"
zeiger "$M" "$SX" "$SY"
cat >> "$M" <<EOF
mouse_button 1
mouse_button 0
warte 0.8
mouse_move 120 120
EOF
foto fsort "gfx wm wigfiles wmhold wiglong $GRUND" "$M"
has "$TMPD/fsort.txt" "files: op" "ein Klick auf die Kopfzeile sortiert um"
sb=$(grep -a '^files: op' "$TMPD/fsort.txt" | tail -1 | grep -oE 'w=[0-9]+' | sed 's/.*=//')
num "und zwar nach Spalte 1 (Groesse)" "$sb" eq 1
# delta.txt ist leer (0 Oktette) und steht nach der Groesse ganz oben
# unter den Dateien -- Verzeichnisse bleiben davor.
schau "nach der Groesse sortiert steht die leere Datei zuerst unter den Dateien" \
    ttext "$TMPD/fsort.ppm" "$SANS" 15 $((FCX + TX)) $((FCY + TB + 2 * TZH)) \
    $TFG $TBG "delta.txt"
schau_nicht "nach dem Namen sortiert stand dort etwas anderes" \
    ttext "$TMPD/files.ppm" "$SANS" 15 $((FCX + TX)) $((FCY + TB + 2 * TZH)) \
    $TFG $TBG "delta.txt"
# Ein neues Verzeichnis ueber Kontextmenue und Dialog -- und danach wird
# nicht das BILD geglaubt, sondern im PLATTENABBILD nachgesehen.
PX2=$((FCX + TX + 100)); PY2=$((FCY + TB + 2 * TZH - 6))
M="$TMPD/fneu.mon"; : > "$M"
zeiger "$M" "$PX2" "$PY2"
cat >> "$M" <<EOF
mouse_button 2
warte 0.3
mouse_button 0
warte 0.8
mouse_move 40 $((22 + 2 + 3 * 22 + 11))
mouse_button 1
mouse_button 0
warte 1.0
sendkey n
sendkey e
sendkey u
warte 0.5
EOF
zeiger "$M" $((230 + 2 + OKX + OKW / 2)) $((246 + 22 + OKY + OKH / 2))
cat >> "$M" <<EOF
mouse_button 1
mouse_button 0
warte 1.2
EOF
foto fneu "gfx wm wigfiles wmhold wiglong $GRUND" "$M"
has "$TMPD/fneu.txt" "files: tat 2" "der Dialog legt ein Verzeichnis an"
rc2=$(grep -a '^files: tat' "$TMPD/fneu.txt" | tail -1 | grep -oE 'rc=[0-9]+' | sed 's/.*=//')
num "und der Kernel nimmt es an" "$rc2" eq 0
# DIE OKTETTE AUF DER PLATTE, nicht das Bild.
python3 tools/osum/mkfs.py list "$TMPD/live-fneu.img" > "$TMPD/fneu.ls" 2>&1
if grep -qE '/daten/neu' "$TMPD/fneu.ls"; then
    ok "und /daten/neu steht WIRKLICH im Plattenabbild"
else
    bad "/daten/neu steht nicht im Plattenabbild"
    grep -c . "$TMPD/fneu.ls" | sed 's/^/        Zeilen: /'
fi
python3 tools/osum/mkfs.py list "$TMPD/live-files.img" > "$TMPD/files.ls" 2>&1
if grep -qE '/daten/neu' "$TMPD/files.ls"; then
    bad "im Abbild OHNE die Bedienung steht /daten/neu auch -- die Zusage sagt nichts"
else
    ok "im Abbild ohne die Bedienung steht es NICHT (die Gegenprobe)"
fi

echo "== 10. die Zeiten: was ein Neuzeichnen wirklich kostet =="
# WAS HIER VERGLICHEN WIRD, und warum die Zahl sonst nichts bedeutet:
#   `wig: pixels` sind die Bildpunkte, die RING 3 in seine Fenster
#   geschoben hat. `wm: pixels` sind die, die der SERVER daraufhin
#   zusammengesetzt hat. Beide zusammen sagen, was ein Klick kostet.
RP=$(feld "$TMPD/ruhe.txt" "wig: blits" pixels)
HP=$(feld "$TMPD/haken.txt" "wig: blits" pixels)
RB2=$(feld "$TMPD/ruhe.txt" "wig: blits" blits)
HB=$(feld "$TMPD/haken.txt" "wig: blits" blits)
FLAECHE=$((BW * BH))
DELTA=$((HP - RP))
num "Bildpunkte fuer den ganzen Aufbau des Fensters" "$RP" gt 100000
if [ "$DELTA" -gt 0 ] && [ "$DELTA" -lt $((FLAECHE / 8)) ]; then
    ok "ein Klick auf das Kaestchen kostet $DELTA Bildpunkte statt $FLAECHE -- Faktor $((FLAECHE / DELTA))"
else
    bad "ein Klick kostet $DELTA von $FLAECHE Bildpunkten (erwartet deutlich weniger)"
fi
num "und dafuer $((HB - RB2)) Aufrufe hinueber, nicht mehr" $((HB - RB2)) lt 12
GP=$(feld "$TMPD/ruhe.txt" "wig: blits" glyphs)
num "Glyphen, die die Bibliothek beim Kernel geholt hat (je Zeichen EINE)" "$GP" lt 90
# DIE GEGENPROBE ZUR BEREICHSVERFOLGUNG. Mit `nodirty` wird jede
# Meldung eines schmutzigen Bereichs zu "der ganze Schirm", und der
# Server setzt fuer denselben Klick das ganze Bild neu zusammen.
foto haken_nd "gfx wm wig nodirty wmhold wiglong $GRUND" "$TMPD/haken.mon"
WMP=$(zahl2 "$TMPD/haken.txt" 'wm: composites=[0-9]+  blits=[0-9]+  pixels=[0-9]+')
WMPN=$(zahl2 "$TMPD/haken_nd.txt" 'wm: composites=[0-9]+  blits=[0-9]+  pixels=[0-9]+')
if [ -n "$WMP" ] && [ -n "$WMPN" ] && [ "$WMPN" -gt "$WMP" ]; then
    ok "mit Bereichsverfolgung setzt der Server $WMP Bildpunkte zusammen, ohne sie $WMPN -- Faktor $((WMPN / WMP))"
else
    bad "ohne Bereichsverfolgung wird es nicht teurer: $WMP gegen $WMPN"
fi
# Und die Anwendung tut in beiden Laeufen DASSELBE -- sonst waere die
# Zahl ein Vergleich zweier verschiedener Dinge.
hnd=$(feld "$TMPD/haken_nd.txt" "wigdemo: state" haken)
gleich "und die Anwendung hat in beiden Laeufen dasselbe getan" "1" "$hnd"

echo "== 11. die Gegenproben =="
# 11a. OHNE TREFFERPRUEFUNG. Dieselben Klicks, dieselben Ereignisse --
#      und kein Widget erfaehrt davon.
foto nohit "gfx wm wig wignohit wmhold wiglong $GRUND" "$TMPD/haken.mon"
hasnot "$TMPD/nohit.txt" "wigdemo: fired" "mit 'nohit' meldet sich KEIN Widget"
nh=$(feld "$TMPD/nohit.txt" "wigdemo: state" haken)
gleich "und das Kaestchen bleibt leer" "0" "$nh"
nhp=$(python3 tools/k15/zaehl.py "$TMPD/nohit.ppm" "$HKX" "$HKY" 14 14 92 200 255)
num "auch im Bild: kein Bildpunkt des Hakens" "$nhp" eq 0
nhd=$(zahl2 "$TMPD/nohit.txt" 'downs=[0-9]+')
num "obwohl der Klick beim Fenster ANGEKOMMEN ist" "$nhd" ge 1
# 11b. OHNE ZEIGEGERAET.
foto nomaus "gfx wm wig nomouse wmhold wiglong $GRUND" "$TMPD/haken.mon"
hasnot "$TMPD/nomaus.txt" "wigdemo: fired" "mit 'nomouse' kommt gar kein Klick an"
has "$TMPD/nomaus.txt" "wigdemo: ready" "die Anwendung malt trotzdem -- nur bedienen kann man sie nicht"
# 11c. OHNE EINGABEFOKUS. Die Taste geht dann an JEDES Fenster, also
#      auch an das Terminal -- und das ist die Zusage aus Runde K10 in
#      der Form, in der sie diese Runde braucht.
foto nofok "gfx wm wig nofocus wmhold wiglong $GRUND" "$TMPD/tab.mon"
k0=$(zahl2 "$TMPD/tabkey.txt" 'keys0=[0-9]+')
k0n=$(zahl2 "$TMPD/nofok.txt" 'keys0=[0-9]+')
num "im Regellauf bekommt das Terminalfenster KEINE Taste" "$k0" eq 0
num "mit 'nofocus' bekommt es sie alle" "$k0n" ge 3
# 11d. OHNE DAS WORT `wig`. Dann gibt es die Anwendung nicht, und alles
#      andere verhaelt sich wie in Runde K10.
foto ohne "gfx wm wmhold $GRUND"
hasnot "$TMPD/ohne.txt" "k15: start" "ohne das Wort 'wig' wird keine Anwendung gestartet"
hasnot "$TMPD/ohne.txt" "wigdemo:" "und es meldet sich keine"
has "$TMPD/ohne.txt" "wclick: passed 10 / 10" "statt dessen laeuft die Anwendung der Runde K10 wie vorher"
wz=$(zahl "$TMPD/ohne.txt" 'wm: selftest [0-9]+')
num "und der Fensterserver sagt dasselbe wie vorher" "$wz" eq 17
# Die Naht ist trotzdem da und sagt, dass sie nichts getan hat.
ob=$(feld "$TMPD/ohne.txt" "wig: blits" blits)
num "die Naht hat in diesem Lauf nichts hinuebergeschoben" "$ob" eq 0

echo "== 12. das Farbschema kommt aus einer Datei =="
tn=$(zahl "$TMPD/ruhe.txt" 'wigdemo: theme n=[0-9]+')
soll=$(grep -cE '^[a-z]+=' "$TMPD/baum/theme")
num "Farben, die aus /etc/theme gelesen wurden" "$tn" eq "$soll"
# UND SIE WIRKEN. Der Knopf hat die Farbe aus der Datei; mit einer
# ANDEREN Datei hat er eine andere -- das ist die Gegenprobe, ohne die
# "es gibt ein Farbschema" eine Behauptung ueber eine Zahl waere.
sed 's/^btn=.*/btn=804020/' "$TMPD/baum/theme" > "$TMPD/theme2"
ARGS2=(build "$TMPD/disk2.img" 4096 /lib/
      "/lib/mono.ttf=$MONO" "/lib/sans.ttf=$SANS" /bin/)
for p in $PROGS; do ARGS2+=("/bin/$p=$TMPD/${p}0.elf"); done
ARGS2+=(/etc/ "/etc/theme=$TMPD/theme2")
while read -r z; do ARGS2+=("$z"); done < "$TMPD/baum/liste"
python3 tools/osum/mkfs.py "${ARGS2[@]}" > "$TMPD/mkfs2.txt" 2>&1
cp -f "$TMPD/disk.img" "$TMPD/disk1.img"
cp -f "$TMPD/disk2.img" "$TMPD/disk.img"
foto theme2 "gfx wm wig wmhold wiglong $GRUND"
cp -f "$TMPD/disk1.img" "$TMPD/disk.img"
schau "mit btn=804020 in der Datei hat der Knopf DIESE Farbe" \
    flaeche "$TMPD/theme2.ppm" $((CX + BX + 3)) $((CY + BY + 3)) 16 5 128 64 32
schau_nicht "und die vorige hat er dann NICHT mehr" \
    flaeche "$TMPD/theme2.ppm" $((CX + BX + 3)) $((CY + BY + 3)) 16 5 58 74 94
# Der Text steht trotzdem, und zwar auf dem NEUEN Grund -- also wird die
# Farbe wirklich beim Mischen benutzt und nicht nur beim Fuellen.
schau "und der Text darauf ist gegen den neuen Grund gemischt" \
    ttext "$TMPD/theme2.ppm" "$SANS" 15 $((CX + $(feld "$TMPD/ruhe.txt" "wigdemo: text knopf" x))) \
    $((CY + $(feld "$TMPD/ruhe.txt" "wigdemo: text knopf" base))) \
    $(rgb 15265524) 128 64 32 "Knopf"

echo "== 13. das Zeigerbild -- die einzige Stelle, an der Ring 3 dem Server etwas ueber den Zeiger sagt =="
M="$TMPD/beam.mon"; : > "$M"
zeiger "$M" "$E1X" $((CY + E1Y + E1H / 2))
cat >> "$M" <<EOF
mouse_move 0 0
warte 0.8
EOF
foto beam "gfx wm wig wmhold wiglong $GRUND" "$M"
sh1=$(feld "$TMPD/beam.txt" "wig: blits" shape)
num "ueber einem Textfeld wird der Zeiger zum Balken" "$sh1" eq 1
sh0=$(feld "$TMPD/ruhe.txt" "wig: blits" shape)
num "sonst bleibt er der Pfeil" "$sh0" eq 0
# Und das steht im Bild: der Balken ist zwei Bildpunkte breit und
# achtzehn hoch, der Pfeil ist an derselben Stelle schwarz und breit.
schau "die Mitte des Balkens ist weiss" \
    punkt "$TMPD/beam.ppm" $((E1X + 6)) $((CY + E1Y + E1H / 2 + 9)) 255 255 255
schau_nicht "und drei Bildpunkte weiter rechts ist nichts vom Zeiger" \
    punkt "$TMPD/beam.ppm" $((E1X + 9)) $((CY + E1Y + E1H / 2 + 9)) 255 255 255

echo
echo "K15: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
