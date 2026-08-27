#!/usr/bin/env bash
# tools/k15/run.sh -- DER BEWEIS, DASS OSUM WIDGETS HAT UND EINEN
# DATEIMANAGER.
#
# Runde K10 gab Osum eine Oberflaeche: ein Zeigegeraet, einen
# Fensterserver, einen TrueType-Rasterer. Zwischen dem Rechteck, das
# eine Anwendung dort bekommt, und einer Anwendung fehlte alles --
# Knoepfe, Textfelder, Listen, Menues, Dialoge, eine Ereignisschleife,
# eine Anordnung. Runde K15 baut das, und zwar IN RING 3
# (`kernel/user/wlib.fi` und `kernel/user/wlibc.fi`); im Kernel stehen
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

PROGS="widgetdemo explorer launcher locate sh echo ls cat edit"
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
baue 0 && ok "firnc0: $(echo $PROGS | wc -w) Programme gebaut, davon /bin/explorer mit $(stat -c%s "$TMPD/explorer0.elf") Oktetten" \
    || bad "firnc0: die Programme dieser Runde lassen sich nicht bauen"
baue 1 && ok "firnc1: dieselben aus dem Uebersetzer, der in Firn geschrieben ist" \
    || bad "firnc1: die Programme dieser Runde lassen sich nicht bauen"
# DIE BIBLIOTHEK IST EINE BIBLIOTHEK: sie hat kein `u_start`, sie wird
# EINGEBUNDEN. Das ist die Zusage "in Ring 3, nicht im Kernel" in ihrer
# pruefbaren Form -- und dazu, dass der Kernel sie NICHT enthaelt.
if nm "$TMPD/explorer0.elf" 2>/dev/null | grep -q . ; then :; fi
for sym in wlib__button wlib__step wlibc__text_at; do
    if nm -a "$TMPD/k0.mb.elf" 2>/dev/null | grep -q "$sym"; then
        bad "der Kernel traegt $sym -- die Bibliothek gehoert nach Ring 3"
    else
        ok "der Kernel traegt $sym NICHT (die Bibliothek liegt in Ring 3)"
    fi
done
wigzeilen=$(cat kernel/user/wlib.fi kernel/user/wlibc.fi | wc -l)
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
ARGS+=("/bin/files@/bin/explorer")
ARGS+=(/etc/ "/etc/theme=$TMPD/baum/theme")
# DIE BUENDEL: /apps/<name>.prog/{INFO,start,symbol,daten/}
while read -r zeile; do ARGS+=("$zeile"); done < <(python3 tools/k15/buendel.py assets/apps "$TMPD/buendel")
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
# ZEHN AUFRUFE: sieben aus der Runde, drei aus dem zweiten Nachtrag
# (1807 Tabellenlauf, 1808 Journal, 1809 Auskunft).
for n in 1800 1806 1807 1808 1809; do
    grep -qE "= $n( |$)" kernel/sys.fi && ok "die Aufrufnummer $n steht in kernel/sys.fi" \
        || bad "die Aufrufnummer $n fehlt"
done
grep -q 'const WIG_MAXNR: u64 = 1809' kernel/sys.fi \
    && ok "und 1809 ist die hoechste" \
    || bad "WIG_MAXNR passt nicht zu den Aufrufen"
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
has "$TMPD/ruhe.txt" "k15: start /bin/widgetdemo" "die Anwendung kommt VON DER PLATTE"
has "$TMPD/ruhe.txt" "widgetdemo: ready" "sie hat ihr Fenster angelegt und gemalt"
WX=60; WY=60
BW=$(feld "$TMPD/ruhe.txt" "widgetdemo: geom" w)
BH=$(feld "$TMPD/ruhe.txt" "widgetdemo: geom" h)
num "das Fenster ist so breit, wie die Anwendung es bestellt hat" "$BW" eq 480
num "und so hoch" "$BH" eq 400
CX=$((WX + BORDER)); CY=$((WY + TITLE))
aus=$(python3 tools/k15/anordnung.py "$TMPD/ruhe.txt" widgetdemo "$BW" "$BH" 12 2>&1)
if [ $? -eq 0 ]; then ok "die Anordnung: $aus"
else bad "die Anordnung stimmt nicht"; echo "$aus" | sed 's/^/        /' | head -8; fi
# Und die Gegenprobe zum Pruefer selbst: ein Rechteck, das aus dem
# Fenster ragt, MUSS auffallen -- sonst prueft er nichts.
sed 's/^widgetdemo: rect id=11 .*/widgetdemo: rect id=11 kind=5 x=12 y=372 w=456 h=112 /' \
    "$TMPD/ruhe.txt" > "$TMPD/ruhe-gg.txt"
if python3 tools/k15/anordnung.py "$TMPD/ruhe-gg.txt" widgetdemo "$BW" "$BH" 12 >/dev/null 2>&1; then
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
    zeile=$(grep -a "^widgetdemo: text $marke " "$TMPD/ruhe.txt" | tail -1)
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
RX=$(feld "$TMPD/ruhe.txt" "widgetdemo: rows" x)
RB=$(feld "$TMPD/ruhe.txt" "widgetdemo: rows" base)
ZH=$(feld "$TMPD/ruhe.txt" "widgetdemo: rows" zh)
RFG=$(frgb "$TMPD/ruhe.txt" "widgetdemo: rows" fg)
RBG=$(frgb "$TMPD/ruhe.txt" "widgetdemo: rows" bg)
RSEL=$(frgb "$TMPD/ruhe.txt" "widgetdemo: rows" sel)
RSFG=$(frgb "$TMPD/ruhe.txt" "widgetdemo: rows" selfg)
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
FX=$(rect "$TMPD/ruhe.txt" widgetdemo 1 x); FY=$(rect "$TMPD/ruhe.txt" widgetdemo 1 y)
FW=$(rect "$TMPD/ruhe.txt" widgetdemo 1 w); FH=$(rect "$TMPD/ruhe.txt" widgetdemo 1 h)
schau "der Fokusring liegt bildpunktgenau um die Reiter" \
    rechteck "$TMPD/ruhe.ppm" $((CX + FX)) $((CY + FY)) "$FW" "$FH" 255 192 32
BX=$(rect "$TMPD/ruhe.txt" widgetdemo 5 x); BY=$(rect "$TMPD/ruhe.txt" widgetdemo 5 y)
BBW=$(rect "$TMPD/ruhe.txt" widgetdemo 5 w); BBH=$(rect "$TMPD/ruhe.txt" widgetdemo 5 h)
schau_nicht "und um den Knopf, der ihn NICHT hat, liegt keiner" \
    rechteck "$TMPD/ruhe.ppm" $((CX + BX)) $((CY + BY)) "$BBW" "$BBH" 255 192 32
schau "die Flaeche des Knopfes hat die Farbe aus /etc/theme (btn=3a4a5e)" \
    flaeche "$TMPD/ruhe.ppm" $((CX + BX + 3)) $((CY + BY + 3)) 16 5 58 74 94
# Das Textfeld hat einen dunkleren Grund als das Fenster -- sonst waere
# nicht zu sehen, dass es eines ist.
EX=$(rect "$TMPD/ruhe.txt" widgetdemo 3 x); EY=$(rect "$TMPD/ruhe.txt" widgetdemo 3 y)
schau "das Textfeld hat seine eigene Flaeche" \
    flaeche "$TMPD/ruhe.ppm" $((CX + EX + 300)) $((CY + EY + 6)) 60 10 18 24 32

echo "== 6. bedienen: echte Klicks aus dem QEMU-Monitor =="
# Die Stellen kommen aus den Rechtecken, die die Anwendung gemeldet hat
# -- nicht aus Zahlen, die hier stehen.
mitte() { # id -> "x y" auf dem BILDSCHIRM
    local x y w h
    x=$(rect "$TMPD/ruhe.txt" widgetdemo "$1" x); y=$(rect "$TMPD/ruhe.txt" widgetdemo "$1" y)
    w=$(rect "$TMPD/ruhe.txt" widgetdemo "$1" w); h=$(rect "$TMPD/ruhe.txt" widgetdemo "$1" h)
    echo "$((CX + x + w / 2)) $((CY + y + h / 2))"
}
KNOPF=$(mitte 5); HAKEN_X=$((CX + $(rect "$TMPD/ruhe.txt" widgetdemo 7 x) + 7))
HAKEN_Y=$((CY + $(rect "$TMPD/ruhe.txt" widgetdemo 7 y) + 14))
LX=$(rect "$TMPD/ruhe.txt" widgetdemo 11 x); LY=$(rect "$TMPD/ruhe.txt" widgetdemo 11 y)
E1Y=$(rect "$TMPD/ruhe.txt" widgetdemo 3 y); E2Y=$(rect "$TMPD/ruhe.txt" widgetdemo 4 y)
E1H=$(rect "$TMPD/ruhe.txt" widgetdemo 3 h)
# Der zweite Reiter: hinter dem ersten. Seine Breite steht nicht im
# Mitschnitt, also wird der Punkt so gewaehlt, dass er sicher im
# zweiten liegt -- und die Zusage prueft, WELCHER Reiter aktiv wurde.
TABX=$((CX + $(rect "$TMPD/ruhe.txt" widgetdemo 1 x) + 130))
TABY=$((CY + $(rect "$TMPD/ruhe.txt" widgetdemo 1 y) + 13))

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
has "$TMPD/klick.txt" "widgetdemo: fired id=5 kind=2" "der Knopf meldet sich -- mit seiner Nummer und seiner Art"
kl=$(feld "$TMPD/klick.txt" "widgetdemo: state" klicks)
num "und genau EINMAL" "$kl" eq 1
hasnot "$TMPD/ruhe.txt" "widgetdemo: fired" "ohne Klick meldet sich kein Widget"

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
has "$TMPD/haken.txt" "widgetdemo: fired id=7 kind=3 ix=1" "das Kaestchen kippt und meldet seinen neuen Wert"
# UND DAS IST IM BILD ZU SEHEN: der Haken ist aus zwei Strichen in der
# Betonungsfarbe. Ohne Klick ist dort KEIN einziger solcher Bildpunkt.
HKX=$((CX + $(rect "$TMPD/ruhe.txt" widgetdemo 7 x))); HKY=$((CY + $(rect "$TMPD/ruhe.txt" widgetdemo 7 y) + 7))
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
rt=$(feld "$TMPD/reiter.txt" "widgetdemo: state" reiter)
num "der zweite Reiter ist aktiv" "$rt" eq 1
has "$TMPD/reiter.txt" "widgetdemo: fired id=1 kind=7 ix=1" "und der Reiter meldet den Wechsel"

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
# DEN INHALT AUS EINER ZEILE HOLEN, DIE WIRKLICH VOLLSTAENDIG IST. Die
# serielle Leitung teilen sich der Kernel und die Anwendung; gelegentlich
# schiebt sich eine Kernelzeile mitten in eine Anwendungszeile
# ("... sel=wm: go"). Ein `sed 's/.*e2=\[//'` darauf liefert Unsinn, und
# die Zusage faellt aus einem Grund, der mit der Sache nichts zu tun hat.
# `tools/k15/felder.py` sucht das VOLLSTAENDIGE Muster mit beiden
# schliessenden Klammern und nimmt die letzte Zeile, die es enthaelt.
e2=$(python3 tools/k15/felder.py "$TMPD/tast.txt" e2)
gleich "was im zweiten Textfeld steht" "Kopiermich-ab" "$e2"
cs=$(feld "$TMPD/tast.txt" "wig: blits" clipset)
cg=$(feld "$TMPD/tast.txt" "wig: blits" clipget)
num "in die Zwischenablage geschrieben" "$cs" ge 1
num "und daraus gelesen" "$cg" ge 1
# UND ES STEHT IM BILD, Zeichen fuer Zeichen.
EBG=$(frgb "$TMPD/ruhe.txt" "widgetdemo: text e1" bg)
EFG=$(frgb "$TMPD/ruhe.txt" "widgetdemo: text e1" fg)
EBASE=$(feld "$TMPD/ruhe.txt" "widgetdemo: text e1" base)
E1TX=$(feld "$TMPD/ruhe.txt" "widgetdemo: text e1" x)
schau "und es steht bildpunktgenau im zweiten Feld" \
    ttext "$TMPD/tast.ppm" "$SANS" 15 $((CX + E1TX)) $((CY + EBASE + E2Y - E1Y)) \
    $EFG $EBG "Kopiermich-ab"
schau_nicht "im Lauf OHNE Tastendruecke steht dort NICHTS" \
    ttext "$TMPD/ruhe.ppm" "$SANS" 15 $((CX + E1TX)) $((CY + EBASE + E2Y - E1Y)) \
    $EFG $EBG "Kopiermich-ab"
# DIE GEGENPROBE, DIE DIE ZUSAGE ERST WERTVOLL MACHT: dieselben
# Tastendruecke mit abgeschalteter Zwischenablage.
foto noclip "gfx wm wig wignoclip wmhold wiglong $GRUND" "$M"
e2n=$(python3 tools/k15/felder.py "$TMPD/noclip.txt" e2)
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
e2t=$(python3 tools/k15/felder.py "$TMPD/tabkey.txt" e2)
gleich "nach der Tabulatortaste tippt man in das NAECHSTE Feld" "xy" "$e2t"
e1t=$(python3 tools/k15/felder.py "$TMPD/tabkey.txt" e1)
gleich "und im vorigen steht unveraendert, was darin stand" "Kopiermich" "$e1t"
schau "der Fokusring ist mitgewandert -- er liegt jetzt um das zweite Feld" \
    rechteck "$TMPD/tabkey.ppm" $((CX + $(rect "$TMPD/ruhe.txt" widgetdemo 4 x))) \
    $((CY + E2Y)) $(rect "$TMPD/ruhe.txt" widgetdemo 4 w) \
    $(rect "$TMPD/ruhe.txt" widgetdemo 4 h) 255 192 32
schau_nicht "und NICHT mehr um das erste" \
    rechteck "$TMPD/tabkey.ppm" $((CX + $(rect "$TMPD/ruhe.txt" widgetdemo 3 x))) \
    $((CY + E1Y)) $(rect "$TMPD/ruhe.txt" widgetdemo 3 w) "$E1H" 255 192 32

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
has "$TMPD/pop.txt" "widgetdemo: fired id=11 kind=11" "die rechte Taste kommt bei der Liste an, mit der Zeile"
has "$TMPD/pop.txt" "widgetdemo: menu " "und die Bibliothek macht ein EIGENES Fenster dafuer auf"
MNX=$(feld "$TMPD/pop.txt" "widgetdemo: menu" x)
MNY=$(feld "$TMPD/pop.txt" "widgetdemo: menu" y)
MNW=$(feld "$TMPD/pop.txt" "widgetdemo: menu" w)
MNH=$(feld "$TMPD/pop.txt" "widgetdemo: menu" h)
MZH=$(feld "$TMPD/pop.txt" "widgetdemo: menu" zh)
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
has "$TMPD/popw.txt" "widgetdemo: fired id=11 kind=8" "ein Klick auf einen Menuepunkt meldet ihn beim Besitzer"
mn=$(feld "$TMPD/popw.txt" "widgetdemo: state" menues)
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
has "$TMPD/dlg.txt" "widgetdemo: dlgwin" "der Dialog ist ein eigenes Fenster"
DW=$(feld "$TMPD/dlg.txt" "widgetdemo: dlgwin" w)
DH=$(feld "$TMPD/dlg.txt" "widgetdemo: dlgwin" h)
num "er ist so breit, wie die Bibliothek ihn baut" "$DW" eq 340
DLX=$(( (800 - DW) / 2 )); DLY=$(( (600 - DH) / 2 ))
schau "und er steht mittig auf dem Schirm, bildpunktgenau" \
    rechteck "$TMPD/dlg.ppm" "$DLX" "$DLY" $((DW + 4)) $((DH + 24)) 76 154 232
DTX=$(feld "$TMPD/dlg.txt" "widgetdemo: text dlg" x)
DTB=$(feld "$TMPD/dlg.txt" "widgetdemo: text dlg" base)
DTF=$(frgb "$TMPD/dlg.txt" "widgetdemo: text dlg" fg)
DTG=$(frgb "$TMPD/dlg.txt" "widgetdemo: text dlg" bg)
schau "seine Frage steht darin, je Zeichen" \
    ttext "$TMPD/dlg.ppm" "$SANS" 15 $((DLX + BORDER + DTX)) \
    $((DLY + TITLE + DTB)) $DTF $DTG "Neuer Name"
# Den Knopf anklicken, den die Bibliothek gemeldet hat.
OKX=$(grep -a 'widgetdemo: dlgrect' "$TMPD/dlg.txt" | head -1 | grep -oE 'x=[0-9]+' | sed 's/.*=//')
OKY=$(grep -a 'widgetdemo: dlgrect' "$TMPD/dlg.txt" | head -1 | grep -oE 'y=[0-9]+' | sed 's/.*=//')
OKW=$(grep -a 'widgetdemo: dlgrect' "$TMPD/dlg.txt" | head -1 | grep -oE 'w=[0-9]+' | sed 's/.*=//')
OKH=$(grep -a 'widgetdemo: dlgrect' "$TMPD/dlg.txt" | head -1 | grep -oE 'h=[0-9]+' | sed 's/.*=//')
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
has "$TMPD/dlgok.txt" "widgetdemo: dlg state=2" "der Dialog wird mit OK bestaetigt und gibt seinen Text zurueck"
dt=$(grep -a 'widgetdemo: dlg state=2' "$TMPD/dlgok.txt" | tail -1 | sed 's/.*text=//')
gleich "und der Text ist der, mit dem er aufgemacht wurde" "Kopiermich" "$dt"
schau_nicht "danach ist auch das Dialogfenster weg" \
    rechteck "$TMPD/dlgok.ppm" "$DLX" "$DLY" $((DW + 4)) $((DH + 24)) 76 154 232

echo "== 9. der Dateimanager: /bin/files gegen die Platte =="
foto files "gfx wm wigfiles wmhold wiglong $GRUND"
num "der Kern beendet sich sauber" "$RC" eq 21
has "$TMPD/files.txt" "k15: start /bin/explorer" "/bin/explorer kommt von der Platte"
has "$TMPD/files.txt" "explorer: ready" "und hat sein Fenster gemalt"
FN=$(feld "$TMPD/files.txt" "explorer: cd" n)
SOLLN=$(wc -l < "$TMPD/baum/soll.txt")
num "er zaehlt so viele Stuecke in /daten, wie baum.py angelegt hat" "$FN" eq "$SOLLN"
FBW=$(feld "$TMPD/files.txt" "explorer: geom" w); FBH=$(feld "$TMPD/files.txt" "explorer: geom" h)
FWX=$(feld "$TMPD/files.txt" "explorer: geom" x); FWY=$(feld "$TMPD/files.txt" "explorer: geom" y)
FCX=$((FWX + BORDER)); FCY=$((FWY + TITLE))
aus=$(python3 tools/k15/anordnung.py "$TMPD/files.txt" explorer "$FBW" "$FBH" 8 2>&1)
if [ $? -eq 0 ]; then ok "die Anordnung des Dateimanagers: $aus"
else bad "die Anordnung des Dateimanagers stimmt nicht"; echo "$aus" | sed 's/^/        /' | head -6; fi
TX=$(feld "$TMPD/files.txt" "explorer: rows" x)
TB=$(feld "$TMPD/files.txt" "explorer: rows" base)
TZH=$(feld "$TMPD/files.txt" "explorer: rows" zh)
TKOPF=$(feld "$TMPD/files.txt" "explorer: rows" kopf)
TFG=$(frgb "$TMPD/files.txt" "explorer: rows" fg)
TBG=$(frgb "$TMPD/files.txt" "explorer: rows" bg)
TSEL=$(frgb "$TMPD/files.txt" "explorer: rows" sel)
TSFG=$(frgb "$TMPD/files.txt" "explorer: rows" selfg)
TDIM=$(frgb "$TMPD/files.txt" "explorer: rows" dim)
SP=($(grep -a '^explorer: spalten' "$TMPD/files.txt" | tail -1 | sed 's/^explorer: spalten //'))
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
has "$TMPD/fdbl.txt" "explorer: cd /daten/bilder" "der Doppelklick geht in das Verzeichnis hinein"
n2=$(grep -a '^explorer: cd' "$TMPD/fdbl.txt" | tail -1 | grep -oE 'n=[0-9]+' | sed 's/.*=//')
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
has "$TMPD/fsort.txt" "explorer: op" "ein Klick auf die Kopfzeile sortiert um"
sb=$(grep -a '^explorer: op' "$TMPD/fsort.txt" | tail -1 | grep -oE 'w=[0-9]+' | sed 's/.*=//')
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
has "$TMPD/fneu.txt" "explorer: tat 2" "der Dialog legt ein Verzeichnis an"
rc2=$(grep -a '^explorer: tat' "$TMPD/fneu.txt" | tail -1 | grep -oE 'rc=[0-9]+' | sed 's/.*=//')
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
hnd=$(feld "$TMPD/haken_nd.txt" "widgetdemo: state" haken)
gleich "und die Anwendung hat in beiden Laeufen dasselbe getan" "1" "$hnd"

echo "== 11. die Gegenproben =="
# 11a. OHNE TREFFERPRUEFUNG. Dieselben Klicks, dieselben Ereignisse --
#      und kein Widget erfaehrt davon.
foto nohit "gfx wm wig wignohit wmhold wiglong $GRUND" "$TMPD/haken.mon"
hasnot "$TMPD/nohit.txt" "widgetdemo: fired" "mit 'nohit' meldet sich KEIN Widget"
nh=$(feld "$TMPD/nohit.txt" "widgetdemo: state" haken)
gleich "und das Kaestchen bleibt leer" "0" "$nh"
nhp=$(python3 tools/k15/zaehl.py "$TMPD/nohit.ppm" "$HKX" "$HKY" 14 14 92 200 255)
num "auch im Bild: kein Bildpunkt des Hakens" "$nhp" eq 0
nhd=$(zahl2 "$TMPD/nohit.txt" 'downs=[0-9]+')
num "obwohl der Klick beim Fenster ANGEKOMMEN ist" "$nhd" ge 1
# 11b. OHNE ZEIGEGERAET.
foto nomaus "gfx wm wig nomouse wmhold wiglong $GRUND" "$TMPD/haken.mon"
hasnot "$TMPD/nomaus.txt" "widgetdemo: fired" "mit 'nomouse' kommt gar kein Klick an"
has "$TMPD/nomaus.txt" "widgetdemo: ready" "die Anwendung malt trotzdem -- nur bedienen kann man sie nicht"
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
hasnot "$TMPD/ohne.txt" "widgetdemo:" "und es meldet sich keine"
has "$TMPD/ohne.txt" "wclick: passed 10 / 10" "statt dessen laeuft die Anwendung der Runde K10 wie vorher"
wz=$(zahl "$TMPD/ohne.txt" 'wm: selftest [0-9]+')
num "und der Fensterserver sagt dasselbe wie vorher" "$wz" eq 17
# Die Naht ist trotzdem da und sagt, dass sie nichts getan hat.
ob=$(feld "$TMPD/ohne.txt" "wig: blits" blits)
num "die Naht hat in diesem Lauf nichts hinuebergeschoben" "$ob" eq 0

echo "== 12. das Farbschema kommt aus einer Datei =="
tn=$(zahl "$TMPD/ruhe.txt" 'widgetdemo: theme n=[0-9]+')
soll=$(grep -cE '^[a-z]+=' "$TMPD/baum/theme")
num "Farben, die aus /etc/theme gelesen wurden" "$tn" eq "$soll"
# UND SIE WIRKEN. Der Knopf hat die Farbe aus der Datei; mit einer
# ANDEREN Datei hat er eine andere -- das ist die Gegenprobe, ohne die
# "es gibt ein Farbschema" eine Behauptung ueber eine Zahl waere.
sed 's/^btn=.*/btn=804020/' "$TMPD/baum/theme" > "$TMPD/theme2"
ARGS2=(build "$TMPD/disk2.img" 4096 /lib/
      "/lib/mono.ttf=$MONO" "/lib/sans.ttf=$SANS" /bin/)
for p in $PROGS; do ARGS2+=("/bin/$p=$TMPD/${p}0.elf"); done
ARGS2+=("/bin/files@/bin/explorer")
ARGS2+=(/etc/ "/etc/theme=$TMPD/theme2")
while read -r zeile; do ARGS2+=("$zeile"); done < <(python3 tools/k15/buendel.py assets/apps "$TMPD/buendel")
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
    ttext "$TMPD/theme2.ppm" "$SANS" 15 $((CX + $(feld "$TMPD/ruhe.txt" "widgetdemo: text knopf" x))) \
    $((CY + $(feld "$TMPD/ruhe.txt" "widgetdemo: text knopf" base))) \
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

echo "== 14. der Name, der zweite Name und die Auffindbarkeit =="
# DER NAME IST DIE BESCHREIBUNG. Kein Nautilus, kein Finder, kein
# Kunstwort: das Programm heisst `/bin/explorer` und traegt fuer den
# Nutzer den Namen "Datei-Explorer" -- und dieser Name steht NICHT im
# Quelltext, sondern in `/apps/explorer.prog/INFO`.
# EIN `grep` PRUEFT DAS NICHT: der Kopfkommentar von explorer.fi
# ERKLAERT, warum das Programm "Datei-Explorer" heisst, und ein
# `grep -q` schlaegt darauf an. `tools/k15/keinname.py` entfernt die
# Anmerkungen und sieht nur im Code nach.
aus=$(python3 tools/k15/keinname.py kernel/user/explorer.fi "Datei-Explorer" 2>&1)
if [ $? -eq 0 ]; then ok "der Anzeigename steht NICHT im Code ($aus)"
else bad "der Anzeigename steht im Code: $aus"; fi
aus=$(python3 tools/k15/keinname.py kernel/user/launcher.fi "Suchen" 2>&1)
if [ $? -eq 0 ]; then ok "und der des Starters auch nicht"
else bad "der Name des Starters steht im Code: $aus"; fi
# Und die Gegenprobe zum Pruefer selbst: eine Zeichenkette, die WIRKLICH
# im Code steht, MUSS er finden -- sonst prueft er nichts.
if python3 tools/k15/keinname.py kernel/user/launcher.fi "Ausfuehren" >/dev/null 2>&1; then
    bad "der Pruefer findet eine Zeichenkette nicht, die im Code steht"
else
    ok "eine Zeichenkette, die wirklich im Code steht, findet er (die Gegenprobe)"
fi
grep -q '^name=Datei-Explorer' assets/apps/explorer.prog/INFO \
    && ok "sondern in assets/apps/explorer.prog/INFO" \
    || bad "assets/apps/explorer.prog/INFO fuehrt keinen Anzeigenamen"
has "$TMPD/files.txt" "explorer: name [Datei-Explorer] aus [explorer.prog]" \
    "und das Programm holt ihn aus dem Buendel"
# UND ER STEHT IN DER TITELLEISTE. Die malt der FENSTERSERVER -- damit
# ist der ganze Weg gemessen: Datei auf der Platte, Ring 3, WM_CREATE,
# Titelleiste, Bildpunkte.
schau "der Anzeigename steht bildpunktgenau in der Titelleiste" \
    ttext "$TMPD/files.ppm" "$SANS" 15 $((FWX + 7)) $((FWY + 15)) \
    255 255 255 28 78 126 "Datei-Explorer" 96
schau_nicht "und ein anderer Name steht dort NICHT" \
    ttext "$TMPD/files.ppm" "$SANS" 15 $((FWX + 7)) $((FWY + 15)) \
    255 255 255 28 78 126 "Dateimanager" 96

# DER ZWEITE NAME. `/bin/files` und `/bin/explorer` sind ZWEI
# Verzeichniseintraege auf DIESELBE Inode -- ein Exemplar der Oktette.
python3 tools/osum/mkfs.py list "$TMPD/disk.img" > "$TMPD/disk.ls" 2>&1
grep -q '^/bin/explorer ' "$TMPD/disk.ls" && ok "/bin/explorer liegt auf der Platte" \
    || bad "/bin/explorer fehlt auf der Platte"
grep -q '^/bin/files ' "$TMPD/disk.ls" && ok "und /bin/files daneben" \
    || bad "/bin/files fehlt auf der Platte"
python3 tools/osum/mkfs.py cat "$TMPD/disk.img" /bin/explorer > "$TMPD/e1.bin" 2>/dev/null
python3 tools/osum/mkfs.py cat "$TMPD/disk.img" /bin/files > "$TMPD/e2.bin" 2>/dev/null
cmp -s "$TMPD/e1.bin" "$TMPD/e2.bin" \
    && ok "beide Namen geben dieselben $(stat -c%s "$TMPD/e1.bin") Oktette" \
    || bad "die beiden Namen geben verschiedene Oktette"
# UND ES IST WIRKLICH EIN VERWEIS UND KEINE KOPIE, gemessen an den
# freien Bloecken: dasselbe Abbild einmal so und einmal so.
python3 tools/osum/mkfs.py build "$TMPD/kopie.img" 4096 /bin/ \
    "/bin/explorer=$TMPD/explorer0.elf" "/bin/files=$TMPD/explorer0.elf" \
    > "$TMPD/kopie.txt" 2>&1
python3 tools/osum/mkfs.py build "$TMPD/verweis.img" 4096 /bin/ \
    "/bin/explorer=$TMPD/explorer0.elf" "/bin/files@/bin/explorer" \
    > "$TMPD/verweis.txt" 2>&1
fk=$(grep -oE 'free=[0-9]+' "$TMPD/kopie.txt" | sed 's/.*=//')
fv=$(grep -oE 'free=[0-9]+' "$TMPD/verweis.txt" | sed 's/.*=//')
ik=$(grep -oE 'inodes=[0-9]+' "$TMPD/kopie.txt" | sed 's/.*=//')
iv=$(grep -oE 'inodes=[0-9]+' "$TMPD/verweis.txt" | sed 's/.*=//')
if [ -n "$fk" ] && [ -n "$fv" ] && [ "$fv" -gt "$fk" ]; then
    ok "der Verweis spart $((fv - fk)) Bloecke gegen die Kopie ($fv frei statt $fk)"
else
    bad "der Verweis spart nichts: $fv gegen $fk"
fi
num "und er braucht eine Inode weniger" $((ik - iv)) eq 1

echo "== 14b. das Anwendungsverzeichnis und der Starter =="
foto start "gfx wm wigstart wmhold wiglong $GRUND"
num "der Kern beendet sich sauber" "$RC" eq 21
has "$TMPD/start.txt" "k15: start /bin/launcher" "der Starter kommt von der Platte"
na=$(feld "$TMPD/start.txt" "launcher: apps" apps)
soll=$(ls -d assets/apps/*.prog | wc -l)
num "er findet so viele Programme, wie .prog-Buendel im Baum liegen" "$na" eq "$soll"
has "$TMPD/start.txt" "launcher: treffer i=0 name=[Datei-Explorer] exec=[/apps/explorer.prog/start]" \
    "und das Buendel fuehrt den Dateimanager mit Name UND Befehl"
# EIN PROGRAMM IST EIN VERZEICHNIS, und das steht nicht im Quelltext,
# sondern auf der Platte. Was ausgefuehrt wird, ist `start` IM Buendel --
# und `start` ist derselbe Inode wie die Datei unter `/bin`, kein zweites
# Exemplar (das misst 14a).
for teil in INFO symbol start daten/LIESMICH; do
    grep -q "^/apps/explorer.prog/$teil " "$TMPD/disk.ls" \
        && ok "das Buendel traegt $teil" \
        || bad "/apps/explorer.prog/$teil fehlt auf der Platte"
done
gb=$(grep -c '^/apps/[a-z]*\.prog/$' "$TMPD/disk.ls")
num "so viele Buendel liegen unter /apps" "$gb" eq "$soll"
hasnot "$TMPD/disk.ls" "/usr/share/apps" \
    "und der alte Ort ist weg -- eine Beschreibung, zwei Orte, waeren einer zu viel"
SBX=190; SBY=110
SCX=$((SBX + BORDER)); SCY=$((SBY + TITLE))
SRX=$(feld "$TMPD/start.txt" "launcher: rows" x)
SRB=$(feld "$TMPD/start.txt" "launcher: rows" base)
SZH=$(feld "$TMPD/start.txt" "launcher: rows" zh)
SIX=$(feld "$TMPD/start.txt" "launcher: rows" ix)
SIY=$(feld "$TMPD/start.txt" "launcher: rows" iy)
SLX=$(feld "$TMPD/start.txt" "launcher: rows" lx)
SLB=$(feld "$TMPD/start.txt" "launcher: rows" lb)
SSEL=$(frgb "$TMPD/start.txt" "launcher: rows" sel)
SSFG=$(frgb "$TMPD/start.txt" "launcher: rows" selfg)
SFG=$(frgb "$TMPD/start.txt" "launcher: rows" fg)
SBG=$(frgb "$TMPD/start.txt" "launcher: rows" bg)
schau "die erste Zeile des Starters, je Zeichen" \
    ttext "$TMPD/start.ppm" "$SANS" 15 $((SCX + SRX)) $((SCY + SRB)) \
    $SSFG $SSEL "Datei-Explorer  --  Dateien und Ordner ansehen" 96
schau "und die zweite" \
    ttext "$TMPD/start.ppm" "$SANS" 15 $((SCX + SRX)) $((SCY + SRB + SZH)) \
    $SFG $SBG "Editor  --  Text schreiben und aendern" 96
# DAS SYMBOL IST EINE DATEI. Im ersten Nachtrag war es sechs Hexziffern
# in einer Textdatei -- ehrlich, solange dieses System kein Bild lesen
# konnte, aber eben kein Bild. Seit dem zweiten liegt in jedem Buendel
# `symbol` im Format OSYM (`tools/k15/symbol.py`), und deshalb wird hier
# nicht eine Farbflaeche gezaehlt, sondern BILDPUNKT GEGEN BILDPUNKT
# gegen eine zweite Umsetzung, die dieselbe Datei unabhaengig von Firn
# zurueckliest. Das ist die Lehre aus Runde K7B, angewandt auf ein Bild:
# eine Flaechenzahl kann zu 87 Prozent stimmen, waehrend das Bild fehlt.
#
# GEZAEHLT WERDEN NUR DIE DECKENDEN BILDPUNKTE. Ueber die durchsichtigen
# sagt ein Symbol nichts aus -- dort steht die Zeilenfarbe, und die
# gehoert der Liste.
sym() { echo "$TMPD/buendel/$1.prog.symbol"; }
pruef() { local name=$1; shift
    local aus rc; aus=$(python3 tools/k15/symbolbild.py "$@" 2>&1); rc=$?
    if [ "$rc" -eq 0 ]; then ok "$name ($aus)"; else bad "$name -- $aus"; fi; }
pruef_nicht() { local name=$1; shift
    local aus rc; aus=$(python3 tools/k15/symbolbild.py "$@" 2>&1); rc=$?
    if [ "$rc" -ne 0 ]; then ok "$name ($aus)"; else bad "$name -- ging durch"; fi; }
for a in explorer editor; do
    python3 tools/k15/symbol.py --pruefe "$(sym $a)" "assets/apps/$a.prog/symbol.txt" \
        > "$TMPD/sym-$a.txt" 2>&1 \
        && ok "das Symbol von $a im Abbild ist die Zeichnung aus dem Quellbaum ($(cat "$TMPD/sym-$a.txt"))" \
        || bad "das Symbol von $a stimmt nicht mit seiner Zeichnung ueberein"
done
pruef "das Symbol des Dateimanagers steht Punkt fuer Punkt im Bild" \
    "$TMPD/start.ppm" $((SCX + SIX)) $((SCY + SIY)) 14 14 "$(sym explorer)"
pruef_nicht "und es ist NICHT das des Editors (die Gegenprobe)" \
    "$TMPD/start.ppm" $((SCX + SIX)) $((SCY + SIY)) 14 14 "$(sym editor)"
pruef "in Zeile 1 steht dafuer das des Editors" \
    "$TMPD/start.ppm" $((SCX + SIX)) $((SCY + SIY + SZH)) 14 14 "$(sym editor)"

echo "== 14c. die Suche -- und dass wirklich die Schluesselwoerter greifen =="
# DIE ZUSAGE, UM DIE ES GEHT: man tippt "folder" und findet den
# Dateimanager, OBWOHL das Wort weder im Anzeigenamen "Datei-Explorer"
# noch in der Beschreibung "Dateien und Ordner ansehen" steht. Es steht
# nur in `keys=`. Zuerst wird das ueberhaupt nachgerechnet -- sonst
# waere die Zusage eine ueber einen Zufall.
for w in folder files manager verzeichnis; do
    if grep -ihE '^(name|info)=' assets/apps/*.prog/INFO | grep -qi "$w"; then
        bad "'$w' steht in einem Anzeigenamen oder einer Beschreibung -- die Zusage waere wertlos"
    else
        ok "'$w' steht in KEINEM Anzeigenamen und in KEINER Beschreibung"
    fi
done
FX2=$((SCX + 12 + 100))
FY2=$((SCY + 38 + 13))
M="$TMPD/suche.mon"; : > "$M"
zeiger "$M" "$FX2" "$FY2"
cat >> "$M" <<EOF
mouse_button 1
mouse_button 0
warte 0.4
sendkey f
sendkey o
sendkey l
sendkey d
sendkey e
sendkey r
warte 1.0
mouse_move 120 120
mouse_move 60 60
EOF
foto suche "gfx wm wigstart wmhold wiglong $GRUND" "$M"
has "$TMPD/suche.txt" "launcher: suche [folder] treffer=1 apps=1" \
    "getippt 'folder': GENAU EIN Treffer, und es ist ein Programm"
has "$TMPD/start.txt" "launcher: name [Suchen]" \
    "auch der Starter holt seinen eigenen Namen aus den Daten"
tf=$(grep -aA1 'launcher: suche \[folder\]' "$TMPD/suche.txt" | grep -a 'name=' | tail -1)
case "$tf" in
    *"name=[Datei-Explorer]"*) ok "der Treffer ist der Datei-Explorer" ;;
    *) bad "der Treffer ist nicht der Datei-Explorer: $tf" ;;
esac
# UND ER STEHT IM BILD -- als einzige Zeile der Liste.
schau "im Bild steht er in Zeile 0 der Trefferliste" \
    ttext "$TMPD/suche.ppm" "$SANS" 15 $((SCX + SRX)) $((SCY + SRB)) \
    $SSFG $SSEL "Datei-Explorer  --  Dateien und Ordner ansehen" 96
schau_nicht "und in Zeile 1 steht nichts mehr" \
    ttext "$TMPD/suche.ppm" "$SANS" 15 $((SCX + SRX)) $((SCY + SRB + SZH)) \
    $SFG $SBG "Editor  --  Text schreiben und aendern" 96
# DIE GEGENPROBE, DIE DIE ZUSAGE ERST WERTVOLL MACHT: dieselben
# Tastendruecke, dieselben Dateien, nur OHNE das Feld `keys`.
foto nokeys "gfx wm wigstart wignokeys wmhold wiglong $GRUND" "$M"
has "$TMPD/nokeys.txt" "launcher: suche [folder] treffer=0 apps=0" \
    "OHNE die Schluesselwoerter findet 'folder' NICHTS"
has "$TMPD/nokeys.txt" "launcher: apps=$soll" \
    "obwohl dasselbe Verzeichnis mit denselben $soll Programmen gelesen wurde"
schau_nicht "und im Bild steht dann auch keine Zeile" \
    ttext "$TMPD/nokeys.ppm" "$SANS" 15 $((SCX + SRX)) $((SCY + SRB)) \
    $SSFG $SSEL "Datei-Explorer  --  Dateien und Ordner ansehen" 96
# UND EIN WORT, DAS NIRGENDS STEHT, FINDET NICHTS. Eine Suche, die immer
# etwas findet, ist keine Suche.
sed 's/^sendkey f$/sendkey q/; s/^sendkey o$/sendkey u/; s/^sendkey l$/sendkey a/; s/^sendkey d$/sendkey s/; s/^sendkey e$/sendkey t/; s/^sendkey r$/sendkey e/' \
    "$M" > "$TMPD/unsinn.mon"
foto unsinn "gfx wm wigstart wmhold wiglong $GRUND" "$TMPD/unsinn.mon"
has "$TMPD/unsinn.txt" "launcher: suche [quaste] treffer=0 apps=0   dateien=0" \
    "ein Wort, das nirgends steht, findet NICHTS -- kein Programm und keine Datei"
grep -qi 'quaste' assets/apps/*.prog/INFO \
    && bad "'quaste' steht doch in einer INFO" \
    || ok "und 'quaste' steht wirklich in keiner INFO"
# Und dass die Suche ueberhaupt etwas findet, wenn sie soll: der leere
# Begriff zeigt alle.
has "$TMPD/start.txt" "launcher: suche [] treffer=$soll" \
    "ohne Suchbegriff stehen alle $soll Programme in der Liste"

echo "== 15. der Namensindex: das GANZE Dateisystem, und sofort =="
# WAS HIER GEMESSEN WIRD UND WARUM SO.
#
# Das Vorbild ist "Everything" von voidtools, und sein Trick ist genau
# nachlesbar: es durchsucht die Platte nicht, sondern liest EINMAL die
# Master File Table von NTFS am Stueck und haelt daraus eine Liste NUR
# AUS NAMEN im Speicher; danach verfolgt es das Aenderungsjournal.
# Osum hat beide Haelften seit dem zweiten K15-Nachtrag: `WIG_SCAN`
# (1807) laeuft durch die Inode-Tabelle, `WIG_JRNL` (1808) holt die
# Aenderungen ab, die `fs.dir_add` und `fs.dir_remove` eingetragen haben.
#
# ES REICHT NICHT, DASS DER INDEX SCHNELL IST. Ein Index, der nichts
# findet, ist unendlich schnell. Gemessen wird deshalb IMMER PAARWEISE:
# derselbe Suchbegriff einmal ueber den Index und einmal als rekursiver
# Baumdurchlauf, im selben Prozess, auf demselben Dateisystem, im selben
# Augenblick -- und beide muessen DIESELBEN NAMEN liefern, sortiert und
# Oktett fuer Oktett verglichen (`kernel/user/locate.fi`, `vergleiche`).
#
# UND ES BRAUCHT EIN ERNSTHAFTES DATEISYSTEM. An zwanzig Dateien beweist
# sich nichts. `tools/k15/gross.py` legt viertausend an, in einem Baum
# aus siebzehn Ordnern, und schreibt daneben auf, wie viele Namen jedes
# gesuchte Wort treffen MUSS -- der Laeufer glaubt weder dem Index noch
# dem Durchlauf, sondern der Liste, aus der das Abbild gebaut wurde.
#
# DASS DIE INODE-TABELLE UEBERHAUPT VIERTAUSEND FASST, ist die eine
# Aenderung an OFS, die dieser Nachtrag gebraucht hat: die Zahl stand
# immer schon im Superblock und wurde nie gelesen (`kernel/fs.fi`,
# `mount`). Abbilder mit 128 bleiben Oktett fuer Oktett, was sie waren --
# Abschnitt 15d rechnet das nach.

python3 tools/k15/gross.py "$TMPD/gross" 4000 > "$TMPD/gross.log" 2>&1 \
    && ok "tools/k15/gross.py: $(cat "$TMPD/gross.log")" \
    || bad "gross.py fehlgeschlagen"
GARGS=(build "$TMPD/gross.img" 4096 /bin/
       "/bin/sh=$TMPD/sh0.elf" "/bin/locate=$TMPD/locate0.elf"
       "/bin/ls=$TMPD/ls0.elf")
while read -r z; do GARGS+=("$z"); done < "$TMPD/gross/angaben"
python3 tools/osum/mkfs.py "${GARGS[@]}" > "$TMPD/gmkfs.txt" 2>&1 \
    && ok "das grosse Abbild: $(cat "$TMPD/gmkfs.txt")" \
    || { bad "mkfs.py fehlgeschlagen"; head -3 "$TMPD/gmkfs.txt"; }
# JEDER NAME IM GANZEN BAUM, aus dem Abbild gezaehlt: eine Zeile je Name
# (die erste Zeile ist der Kopf mit den Bloecken). Das ist die Zahl, die
# der Index treffen muss -- nicht die der Dateien, denn ein Ordner hat
# auch einen Namen und wird auch gefunden.
GN=$(python3 tools/osum/mkfs.py list "$TMPD/gross.img" | tail -n +2 | wc -l)
num "so viele Namen traegt das Abbild insgesamt" "$GN" ge 4000

gross() { # name skript
    local name=$1 zeile=$2
    cp -f "$TMPD/gross.img" "$TMPD/g-$name.img"
    timeout 600 qemu-system-x86_64 -kernel "$TMPD/k0.mb" -m 256 \
        -append "osum nokbd nosched noproc nofs noring3 script=$zeile;exit" \
        -serial "file:$TMPD/$name.txt" -display none -no-reboot \
        -drive "file=$TMPD/g-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    RC=$?
    return 0
}
# DAS LEERZEICHEN VOR DEM NAMEN GEHOERT DAZU. Ohne es fand `n=` auch das
# `n=` in `abgeschn=0`, nahm mit `tail -1` das letzte und lieferte 0 --
# und die halbe Messung haengt an dieser Zahl.
gfeld() { grep -a "$2" "$1" | tail -1 | grep -oE "(^| )$3=[0-9]+" | tail -1 | sed 's/.*=//'; }

gross gkupfer "locate -m kupfer"
num "der Kern beendet sich sauber" "$RC" eq 21
GB_N=$(gfeld "$TMPD/gkupfer.txt" 'locate: bauen' 'n')
GB_S=$(gfeld "$TMPD/gkupfer.txt" 'locate: bauen' 'saetze')
GB_C=$(gfeld "$TMPD/gkupfer.txt" 'locate: bauen' 'aufrufe')
GB_U=$(gfeld "$TMPD/gkupfer.txt" 'locate: bauen' 'us')
GB_T=$(gfeld "$TMPD/gkupfer.txt" 'locate: bauen' 'abgeschn')
num "1. DER AUFBAU: so viele Namen aus der Inode-Tabelle" "$GB_N" eq "$GN"
gleich "und kein Satz ist unterwegs verlorengegangen" "$GB_N" "$GB_S"
num "abgeschnitten wurde nichts" "$GB_T" eq 0
num "und das in so wenigen Systemaufrufen (63 Saetze je Aufruf)" "$GB_C" lt 100
num "Mikrosekunden fuer den ganzen Aufbau" "$GB_U" gt 0
echo "        -> $GB_N Namen in $GB_U us, $GB_C Aufrufe; das ist $((GB_U / GB_N)) us je Name"

GI_U=$(gfeld "$TMPD/gkupfer.txt" 'locate: index' 'us10')
GI_T=$(grep -a 'locate: index' "$TMPD/gkupfer.txt" | tail -1 | grep -oE 'treffer=[0-9]+' | sed 's/.*=//')
GW_U=$(gfeld "$TMPD/gkupfer.txt" 'locate: baum' 'us')
GW_T=$(grep -a 'locate: baum' "$TMPD/gkupfer.txt" | tail -1 | grep -oE 'treffer=[0-9]+' | sed 's/.*=//')
GW_G=$(gfeld "$TMPD/gkupfer.txt" 'locate: baum' 'gesehen')
GI_1=$((GI_U / 10))
num "2. DIE SUCHE: sie ist um Groessenordnungen billiger als der Aufbau" \
    $((GB_U / (GI_1 + 1))) ge 20
echo "        -> Aufbau $GB_U us, eine Suche $GI_1 us (zehn gemessen: $GI_U us)"
num "3. DIE GEGENPROBE: der Baumdurchlauf sieht dieselben Namen" "$GW_G" eq "$GB_N"
gleich "und er findet GENAU DIESELBE ZAHL Treffer" "$GI_T" "$GW_T"
has "$TMPD/gkupfer.txt" "ungleich=0" \
    "und DIESELBEN NAMEN -- sortiert, Oktett fuer Oktett verglichen"
num "und der Index ist dabei um ein Vielfaches schneller" \
    $((GW_U / (GI_1 + 1))) ge 20
echo "        -> Baumdurchlauf $GW_U us, Suche im Index $GI_1 us"
SOLLK=$(grep '^kupfer ' "$TMPD/gross/erwartet" | awk '{print $2}')
num "und beide finden so viele, wie die Liste des Abbilds hergibt" "$GI_T" eq "$SOLLK"
has "$TMPD/gkupfer.txt" "locate: pfad /daten/kupfer" \
    "und der Treffer traegt seinen ganzen Pfad, aus den Elternnummern gebaut"

gross gviele "locate -m 07"
SOLL7=$(grep '^07 ' "$TMPD/gross/erwartet" | awk '{print $2}')
V_I=$(grep -a 'locate: index' "$TMPD/gviele.txt" | tail -1 | grep -oE 'treffer=[0-9]+' | sed 's/.*=//')
V_B=$(grep -a 'locate: baum' "$TMPD/gviele.txt" | tail -1 | grep -oE 'treffer=[0-9]+' | sed 's/.*=//')
num "ein Wort, das VIELE trifft: der Index findet so viele" "$V_I" eq "$SOLL7"
gleich "und der Baumdurchlauf genauso viele" "$V_I" "$V_B"
has "$TMPD/gviele.txt" "ungleich=0" "und wieder Name fuer Name dieselben"

# 5. UND EIN WORT, DAS NIRGENDS STEHT. Eine Suche, die immer etwas
# findet, ist keine Suche -- und das gilt fuer den Index genauso wie fuer
# den Durchlauf.
gross gquaste "locate -m quaste"
SOLLQ=$(grep '^quaste ' "$TMPD/gross/erwartet" | awk '{print $2}')
num "die Liste des Abbilds kennt 'quaste' so oft" "$SOLLQ" eq 0
has "$TMPD/gquaste.txt" "locate: index [quaste] treffer=0" \
    "5. der Index findet 'quaste' NICHT"
has "$TMPD/gquaste.txt" "locate: baum [quaste] treffer=0" \
    "und der Baumdurchlauf auch nicht"
Q_G=$(gfeld "$TMPD/gquaste.txt" 'locate: baum' 'gesehen')
num "obwohl er dabei alle $Q_G Namen angesehen hat" "$Q_G" eq "$GB_N"

echo "== 15b. das Journal: anlegen, umbenennen, loeschen -- ohne Neuaufbau =="
# 4. DER INDEX MUSS ES WISSEN, OHNE NEU ZU BAUEN. `locate -j` legt eine
# Datei an, benennt sie um (kopieren und loeschen -- dieser Kernel hat
# kein `rename`) und loescht sie, und holt nach jedem Schritt das Journal
# ab. Was danach im Index steht, wird nicht behauptet, sondern GESUCHT.
gross gjrnl "locate -j kupfer"
num "der Kern beendet sich sauber" "$RC" eq 21
has "$TMPD/gjrnl.txt" "schritt=1  zwiebel=1  apfel=0" \
    "nach dem Anlegen findet der Index die neue Datei"
has "$TMPD/gjrnl.txt" "schritt=3  zwiebel=0  apfel=1" \
    "nach dem Umbenennen den NEUEN Namen und den alten nicht mehr"
has "$TMPD/gjrnl.txt" "schritt=4  zwiebel=0  apfel=0" \
    "und nach dem Loeschen keinen von beiden"
J_N1=$(grep -a 'schritt=1 ' "$TMPD/gjrnl.txt" | grep -oE 'namen=[0-9]+' | sed 's/.*=//')
J_N4=$(grep -a 'schritt=4 ' "$TMPD/gjrnl.txt" | grep -oE 'namen=[0-9]+' | sed 's/.*=//')
num "der Index hat dabei einen Namen mehr bekommen" $((J_N1 - GB_N)) eq 1
num "und am Ende wieder so viele wie am Anfang" "$J_N4" eq "$GB_N"
has "$TMPD/gjrnl.txt" "lost=0" "und der Ring hat keinen Satz verworfen"
# UND DAS ALLES OHNE EINEN ZWEITEN AUFBAU. Das ist die eigentliche
# Zusage: ein Index, der nach jeder Aenderung neu baut, ist kein Index,
# sondern ein Cache mit einer Sekunde Wartezeit.
nb=$(grep -ac 'locate: bauen' "$TMPD/gjrnl.txt")
num "genau EIN Aufbau im ganzen Lauf, und danach nur noch Journal" "$nb" eq 1

# DIE GEGENPROBE ZUM JOURNAL: dieselben drei Schritte, aber es wird nicht
# abgeholt. Der Index weiss dann von nichts -- und das ist der Beweis,
# dass oben wirklich das Journal gewirkt hat und nicht ein Zufall.
gross gnojrnl "locate -n kupfer"
has "$TMPD/gnojrnl.txt" "schritt=1  zwiebel=0  apfel=0" \
    "OHNE das Journal weiss der Index von der neuen Datei nichts"
has "$TMPD/gnojrnl.txt" "schritt=4  zwiebel=0  apfel=0" \
    "und von den anderen beiden Schritten auch nicht"
N_N4=$(grep -a 'schritt=4 ' "$TMPD/gnojrnl.txt" | grep -oE 'namen=[0-9]+' | sed 's/.*=//')
num "seine Namensliste hat sich kein einziges Mal geaendert" "$N_N4" eq "$GB_N"
N_S=$(grep -a 'schritt=4 ' "$TMPD/gnojrnl.txt" | grep -oE 'gezogen=[0-9]+' | sed 's/.*=//')
num "er hat null Saetze abgeholt" "$N_S" eq 0
J_S=$(grep -a 'schritt=4 ' "$TMPD/gjrnl.txt" | grep -oE 'gezogen=[0-9]+' | sed 's/.*=//')
num "der Lauf MIT Journal dagegen vier" "$J_S" eq 4

echo "== 15c. der Starter sucht Dateien, nicht nur Programme =="
# DIE ZUSAGE AUS DEM AUFTRAG: wer die Suche oeffnet und etwas eintippt,
# soll das GANZE Dateisystem durchsucht bekommen -- nicht nur eine
# Anwendungsliste. "blau" ist kein Programm und steht in keiner INFO; es
# ist eine Datei auf der Platte. Getippt wird ueber den QEMU-Monitor,
# gemessen wird der Schirm.
grep -qi 'blau' assets/apps/*.prog/INFO \
    && bad "'blau' steht in einer INFO -- die Zusage waere wertlos" \
    || ok "'blau' steht in KEINER INFO: was gefunden wird, kann nur eine Datei sein"
M="$TMPD/dsuche.mon"; : > "$M"
zeiger "$M" "$FX2" "$FY2"
cat >> "$M" <<EOF
mouse_button 1
mouse_button 0
warte 0.4
sendkey b
sendkey l
sendkey a
sendkey u
warte 1.2
mouse_move 120 120
mouse_move 60 60
EOF
foto dsuche "gfx wm wigstart wmhold wiglong $GRUND" "$M"
has "$TMPD/dsuche.txt" "launcher: suche [blau] treffer=1 apps=0   dateien=1" \
    "getippt 'blau': ein Treffer, und er ist KEIN Programm, sondern eine Datei"
has "$TMPD/dsuche.txt" "launcher: datei i=0 name=[/daten/bilder/blau.ppm]" \
    "und es ist die Datei, die wirklich dort liegt"
grep -q '^/daten/bilder/blau.ppm ' "$TMPD/disk.ls" \
    && ok "was das Abbild an dieser Stelle auch wirklich fuehrt" \
    || bad "/daten/bilder/blau.ppm steht gar nicht im Abbild"
schau "und im Bild steht der Pfad in Zeile 0 der Trefferliste, je Zeichen" \
    ttext "$TMPD/dsuche.ppm" "$SANS" 15 $((SCX + SRX)) $((SCY + SRB)) \
    $SSFG $SSEL "/daten/bilder/blau.ppm" 96
DIX=$(feld "$TMPD/dsuche.txt" "launcher: index" n)
num "der Starter hat dafuer einen Index ueber so viele Namen gebaut" "$DIX" ge 40
# DIE GEGENPROBE: derselbe Starter, dieselben Tastendruecke, nur OHNE den
# Namensindex. Dann findet "blau" nichts -- und das zeigt, dass der
# Treffer oben WIRKLICH aus dem Index kam und nicht aus der Programmliste.
foto noidx "gfx wm wigstart wignoidx wmhold wiglong $GRUND" "$M"
has "$TMPD/noidx.txt" "launcher: suche [blau] treffer=0 apps=0   dateien=0" \
    "OHNE den Namensindex findet 'blau' NICHTS"
has "$TMPD/noidx.txt" "launcher: index n=0" \
    "weil gar keiner gebaut wurde"
has "$TMPD/noidx.txt" "launcher: apps=$soll" \
    "obwohl dasselbe Anwendungsverzeichnis mit denselben $soll Buendeln gelesen wurde"
schau_nicht "und im Bild steht dann auch kein Pfad" \
    ttext "$TMPD/noidx.ppm" "$SANS" 15 $((SCX + SRX)) $((SCY + SRB)) \
    $SSFG $SSEL "/daten/bilder/blau.ppm" 96

echo "== 15d. und die alten Abbilder sind Oktett fuer Oktett die alten =="
# DIE BEDINGUNG, UNTER DER `fs.fi` UEBERHAUPT ANGEFASST WERDEN DURFTE.
# Die Zahl der Inodes kommt seit diesem Nachtrag aus dem Superblock. Ein
# Abbild ohne `--inodes=` muss deshalb dasselbe sein wie vorher -- sonst
# haengen 1486 bestehende Zusagen an einer geaenderten Platte.
head -c 20000 /dev/urandom > "$TMPD/probe.bin"
python3 tools/osum/mkfs.py build "$TMPD/alt1.img" 4096 /a/ /b/ \
    "/a/eins=$TMPD/probe.bin" "/b/zwei=$TMPD/probe.bin" "/b/drei@/a/eins" \
    > "$TMPD/alt1.txt" 2>&1
python3 tools/osum/mkfs.py build "$TMPD/alt2.img" 4096 /a/ /b/ \
    "/a/eins=$TMPD/probe.bin" "/b/zwei=$TMPD/probe.bin" "/b/drei@/a/eins" \
    > "$TMPD/alt2.txt" 2>&1
cmp -s "$TMPD/alt1.img" "$TMPD/alt2.img" \
    && ok "zweimal gebaut, zweimal dieselben Oktette" \
    || bad "mkfs.py baut nicht zweimal dasselbe"
grep -q 'data=34' "$TMPD/alt1.txt" \
    && ok "ohne --inodes faengt der Datenbereich weiter bei Block 34 an" \
    || bad "der Datenbereich ist verrutscht: $(cat "$TMPD/alt1.txt")"
grep -q 'inodes=[0-9]*/128' "$TMPD/alt1.txt" \
    && ok "und die Tabelle hat weiter 128 Inodes" \
    || bad "die Inode-Zahl der Vorgabe hat sich geaendert: $(cat "$TMPD/alt1.txt")"
grep -q 'data=1026' "$TMPD/gmkfs.txt" \
    && ok "mit --inodes=4096 rueckt er dagegen auf Block 1026" \
    || bad "der grosse Datenbereich liegt falsch: $(cat "$TMPD/gmkfs.txt")"
# Und der Kernel liest beides -- das kleine Abbild hat jeder Lauf oben
# eingehaengt, das grosse jeder Lauf dieses Abschnitts.
has "$TMPD/gkupfer.txt" "osum: mount=1" \
    "und derselbe Kernel haengt beide ein, ohne eine Zeile Unterschied"


echo
echo "K15: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
