#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/wm/run.sh -- DER BEWEIS, DASS OSUM EINE OBERFLAECHE HAT.
#
# Runde K7 gab Osum einen Bildschirm: 800x600, eine Textkonsole darauf,
# /dev/fb fuer Ring 3.  Sie endete mit einem zugegebenen Mangel, und der
# steht woertlich in `kernel/fb.fi`: "Zwei Zeichner auf einer Flaeche
# vertragen sich, solange sie verschiedene Zeilen nehmen.  Ein
# Fenstersystem waere die Antwort darauf und ist nicht diese Runde."
#
# Diese Runde ist es, und sie hat drei Teile: ein ZEIGEGERAET
# (`kernel/ps2m.fi`), einen FENSTERSERVER (`kernel/wm.fi`) und einen
# TRUETYPE-RASTERER (`kernel/ttf.fi`).
#
# WAS HIER GEMESSEN WIRD, UND WARUM ES SO GEMESSEN WERDEN MUSS.
#
# Ein Fensterserver, der nie eine Maus gesehen hat, ist keiner.  Also
# werden ueber den QEMU-Monitor echte Mausbewegungen, echte Klicks und
# echte Tastendruecke in die laufende Maschine eingespeist
# (`tools/wm/monitor.py`), und danach wird ein Bildschirmfoto gemacht und
# MASCHINELL nachgerechnet (`tools/gfx/checkshot.py`).
#
# Und fuer den Text gilt die Lehre aus Runde K7B, die dieser Runde
# ausdruecklich mitgegeben wurde: dort schien Text zu 87 Prozent zu
# stimmen, waehrend in Wahrheit JEDER BUCHSTABE fehlte -- die 87 Prozent
# waren schwarzer Hintergrund.  Hier wird deshalb nicht Flaeche gegen
# Flaeche gerechnet, sondern JE ZEICHEN die gesetzten Bildpunkte gegen
# eine zweite, unabhaengige Rasterung desselben Umrisses
# (`tools/ttf/raster.py`) -- und ein Zeichen, das im Bild KEINE Tinte
# hat, laesst die Zusage fallen, egal wie viel Hintergrund stimmt.
#
# Die Abschnitte:
#
#   1. BAUEN. Beide Uebersetzer bauen denselben Kernel.
#   2. DIE SPEICHERKARTE VON kdata. Drei neue Bereiche (MOUSE, WM, TTF)
#      in den beiden Luecken, die Runde K7B als frei ausgewiesen hat --
#      und der Kollisionspruefer rechnet nach.
#   3. DIE SCHRIFTEN. `tools/ttf/subset.py` schneidet sie aus DejaVu
#      zusammen; das Ergebnis liegt in `assets/` und wird hier
#      REPRODUZIERT und Oktett fuer Oktett verglichen.
#   4. DER RASTERER. Der Kernel gibt acht Glyphen als Text und als
#      Pruefsumme aus; `tools/ttf/raster.py` rastert dieselben selbst.
#      Zwei Fassungen desselben Algorithmus, in zwei Sprachen.
#   5. DAS ZEIGEGERAET. Aufsetzen ueber den 8042, die Kennung, der
#      Selbsttest -- und die Zahlen darueber, auf welchem Weg die
#      Oktette wirklich ankamen.
#   6. DER FENSTERSERVER. Sein Selbsttest, und dann das FOTO: liegt das
#      Fenster, wo es liegen soll, und verdeckt das obere das untere?
#   7. DER TEXT IM FENSTER, bildpunktgenau gegen die zweite Fassung des
#      Rasterers -- Zeichenraster und freier Text mit Unterschneidung.
#   8. DIE MAUS. Bewegungen und Klicks von aussen: landet der Zeiger, wo
#      er soll, und kommt der Klick beim RICHTIGEN Fenster an, mit den
#      richtigen Ortskoordinaten?
#   9. VERSCHIEBEN UND SCHLIESSEN mit der Maus.
#  10. DER EINGABEFOKUS, und die Gegenprobe `nofocus`.
#  11. DIE ZEITEN. Zusammensetzen mit und ohne Bereichsverfolgung,
#      Rasterung mit und ohne Zwischenspeicher.
#  12. DIE SHELL IM TERMINALFENSTER.
#  13. DIE GEGENPROBEN. Ohne `wm` gibt es nichts davon, und die Runden
#      52 bis K9 messen Zeile fuer Zeile, was sie vorher gemessen haben.
#
# Verwendung:  bash tools/wm/run.sh
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

has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' sollte nicht da sein" || ok "$3"; }

schau() { local name=$1; shift
    local aus rc
    aus=$(python3 tools/gfx/checkshot.py "$@" 2>&1); rc=$?
    if [ "$rc" -eq 0 ]; then ok "$name ($aus)"; else bad "$name -- $aus"; fi
}
schau_nicht() { local name=$1; shift
    local aus rc
    aus=$(python3 tools/gfx/checkshot.py "$@" 2>&1); rc=$?
    if [ "$rc" -ne 0 ]; then ok "$name ($aus)"; else bad "$name -- ging durch: $aus"; fi
}
zahl() { grep -aoE "$2" "$1" | head -1 | grep -oE '[0-9]+' | tail -1; }
zahl2() { grep -aoE "$2" "$1" | tail -1 | grep -oE '[0-9]+' | tail -1; }

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "vendor/firn/fetch-firnc.sh fehlgeschlagen"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "WM: skipped, qemu-system-x86_64 ist nicht da"
    exit 0
fi

# --------------------------------------------------------------- Laeufe
#
# Jeder Lauf bekommt eine EIGENE Kopie des Abbilds -- die Schriften
# liegen darauf, und ein Lauf, der schreibt, darf den naechsten nicht
# aendern.

DISK="$TMPD/disk.img"
GRUND="nokbd nosched noproc nofs"

lauf() { # abbild kommandozeile ausgabe
    local abbild=$1 zeile=$2 aus=$3
    cp -f "$DISK" "$TMPD/live.img"
    timeout 180 $QEMU_X86 -kernel "$abbild" -m 256 -append "$zeile" \
        -serial "file:$aus" -display none -no-reboot -vga std \
        -drive "file=$TMPD/live.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    return $?
}

RC=0
foto() { # abbild kommandozeile ausgabe ppm [monitorbefehle]
    local abbild=$1 zeile=$2 aus=$3 ppm=$4 mon=${5:-}
    local sock="$TMPD/mon-$$.sock"
    local live="$TMPD/live-$(basename "$aus").img"
    rm -f "$aus" "$ppm" "$sock"
    cp -f "$DISK" "$live"
    timeout 180 $QEMU_X86 -kernel "$abbild" -m 256 -append "$zeile" \
        -serial "file:$aus" -display none -no-reboot -vga std \
        -monitor "unix:$sock,server,nowait" \
        -drive "file=$live,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local pid=$!
    local i=0
    while [ $i -lt 900 ]; do
        grep -qa '^wm: hold' "$aus" 2>/dev/null && break
        grep -qa '^fb: hold' "$aus" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.15
        i=$((i + 1))
    done
    if [ -n "$mon" ]; then
        python3 tools/wm/monitor.py "$sock" "$mon" > "$TMPD/mon.txt" 2>&1
    fi
    python3 tools/gfx/screenshot.py "$sock" "$ppm" 25 > "$TMPD/schuss.txt" 2>&1
    wait "$pid"
    RC=$?
    rm -f "$sock"
    return 0
}

echo "== 1. bauen: derselbe Kernel aus beiden Uebersetzern =="
for s in 0 1; do
    if bash tools/build-kernel.sh "$TMPD/k$s.mb" --stufe "$s" > "$TMPD/b$s.log" 2>&1; then
        ok "firnc$s: Kernel gebaut ($(stat -c%s "$TMPD/k$s.mb") Oktette)"
    else
        bad "firnc$s: der Kernel laesst sich nicht bauen"
        sed 's/^/        /' "$TMPD/b$s.log" | head -12
    fi
done
K0="$TMPD/k0.mb"
[ -f "$K0" ] || { echo "WM: $pass passed, $((fail + 1)) failed"; exit 1; }

echo "== 2. die Speicherkarte von kdata: drei neue Bereiche =="
# Runde K7 legte den Zeichensatz auf eine Seite, die Runde K9 schon
# hatte, und beide Zweige waren fuer sich gruen.  Seit K7B rechnet ein
# Programm die Karte nach; diese Runde traegt drei Bereiche ein und
# haelt sich daran.
kart=$(python3 tools/kernel/memmap.py kernel 2>&1)
if [ $? -eq 0 ]; then ok "die Speicherkarte von kdata: $kart"
else bad "die Speicherkarte von kdata kollidiert"; echo "$kart" | sed 's/^/        /'; fi
for b in MOUSE WM TTF; do
    if python3 tools/kernel/memmap.py kernel -v 2>/dev/null | grep -q " $b  *kstate.fi:"; then
        ok "der Bereich $b steht in der Karte"
    else
        bad "der Bereich $b steht NICHT in der Karte"
    fi
done
# Und die Gegenprobe zum Pruefer: legt man WM auf die Seite des
# Rahmenpuffers, MUSS er anschlagen.
# RUNDE ARM: die Kopie braucht `kernel/arch/x86_64/` mit -- `hv.fi` liegt
# seit dem Trennschnitt dort, und ohne sie stirbt der Kartenpruefer an
# einem KeyError statt die Kollision zu melden, die hier gemessen wird.
GG="$TMPD/kernel-gg"; mkdir -p "$GG/arch/x86_64"
cp kernel/*.fi "$GG/"
cp kernel/arch/x86_64/*.fi "$GG/arch/x86_64/"
sed -i 's/^const WM_OFF: u64 = 0x1E000/const WM_OFF: u64 = 0x3C000/' "$GG/kstate.fi"
gg=$(python3 tools/kernel/memmap.py "$GG" 2>&1)
if [ $? -ne 0 ] && printf '%s' "$gg" | grep -q 'KOLLISION'; then
    ok "mit WM_OFF auf 0x3C000 findet der Pruefer die Kollision mit FB"
else
    bad "der Kollisionspruefer findet die neue Kollision NICHT: $gg"
fi
# DIE VEKTORTABELLE, und sie steht hier, weil diese Runde denselben
# Fehler eine Ebene hoeher gemacht hat: `VEC_MOUSE` bekam die 44, und 44
# ist seit Runde K2 der NVMe-Regler.  Die Weiche in `trap.fi` ist eine
# Kette von `if`s -- die Maus stand davor, und die Abschlussmeldungen des
# Reglers gingen an den Maustreiber.  `nvme: irqs=0` statt `irqs=5`, in
# JEDEM Lauf, auch ohne das Wort `wm`.  Gefunden hat es Abschnitt 6 von
# `./test.sh`.  Ab jetzt findet es ein Programm.
vt=$(python3 tools/kernel/memmap.py kernel -v 2>/dev/null | grep -A9 'die Vektortabelle' | tail -8 | tr -s ' ' | sed 's/^ //' | tr '\n' ' ')
if python3 tools/kernel/memmap.py kernel >/dev/null 2>&1; then
    ok "die Vektortabelle ist ueberschneidungsfrei ($vt)"
else
    bad "die Vektortabelle kollidiert"
fi
# RUNDE ARM: die Kopie muss auch das Maschinenverzeichnis mitnehmen --
# `trap.fi` liegt seit dem Trennschnitt unter arch/x86_64/.
GV="$TMPD/kernel-gv"; mkdir -p "$GV/arch/x86_64"
cp kernel/*.fi "$GV/"
cp kernel/arch/x86_64/*.fi "$GV/arch/x86_64/"
sed -i 's/^const VEC_MOUSE: u64 = 46/const VEC_MOUSE: u64 = 44/' "$GV/arch/x86_64/trap.fi"
gv=$(python3 tools/kernel/memmap.py "$GV" 2>&1)
if [ $? -ne 0 ] && printf '%s' "$gv" | grep -q 'Vektor 44 haben zwei Namen'; then
    ok "mit VEC_MOUSE zurueck auf 44 findet der Pruefer die Kollision mit VEC_NVME"
else
    bad "der Vektorpruefer findet den Fehler dieser Runde NICHT: $gv"
fi

echo "== 3. die Schriften: reproduzierbar aus DejaVu geschnitten =="
DEJAVU=${DEJAVU:-/usr/share/fonts/truetype/dejavu}
for f in mono sans; do
    [ -f "assets/osum-$f.ttf" ] && ok "assets/osum-$f.ttf liegt im Baum ($(stat -c%s assets/osum-$f.ttf) Oktette)" \
        || bad "assets/osum-$f.ttf fehlt"
done
if [ -f "$DEJAVU/DejaVuSansMono.ttf" ]; then
    python3 tools/ttf/subset.py "$DEJAVU/DejaVuSansMono.ttf" "$TMPD/mono.ttf" >/dev/null 2>&1
    python3 tools/ttf/subset.py "$DEJAVU/DejaVuSans.ttf" "$TMPD/sans.ttf" >/dev/null 2>&1
    cmp -s "$TMPD/mono.ttf" assets/osum-mono.ttf \
        && ok "osum-mono.ttf entsteht Oktett fuer Oktett neu aus DejaVu Sans Mono" \
        || bad "osum-mono.ttf laesst sich nicht reproduzieren"
    cmp -s "$TMPD/sans.ttf" assets/osum-sans.ttf \
        && ok "osum-sans.ttf entsteht Oktett fuer Oktett neu aus DejaVu Sans" \
        || bad "osum-sans.ttf laesst sich nicht reproduzieren"
else
    echo "        (DejaVu liegt nicht unter $DEJAVU -- Schnitt nicht nachgerechnet)"
fi
info=$(python3 tools/ttf/raster.py info assets/osum-sans.ttf)
echo "        $info"
case "$info" in
    *"kern="0*) bad "die Antiqua hat keine Unterschneidungspaare" ;;
    *"kern="*) ok "die Antiqua traegt eine kern-Tabelle: ${info##*kern=}" ;;
esac
# Und das Abbild, auf dem sie liegen.  Sie kommen VON DER PLATTE -- ein
# Zeichensatzleser, der seinen Zeichensatz im Kernelabbild traegt, liest
# keinen.
# Und die Shell dazu, als eigenstaendige ELF-Datei -- so, wie Runde K6
# sie baut (`tools/userland/run.sh`): crt.s davor, `kernel/user/user.ld`
# als Linkerskript.
gebaut=1
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || gebaut=0
for p in sh echo uname; do
    vendor/firn/bin/firnc "kernel/user/$p.fi" -o "$TMPD/$p.o" >"$TMPD/$p.log" 2>&1 \
        && ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
            -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>>"$TMPD/$p.log" \
        || { gebaut=0; sed 's/^/        /' "$TMPD/$p.log" | head -4; }
done
[ "$gebaut" = 1 ] && ok "/bin/sh, /bin/echo und /bin/uname gebaut ($(stat -c%s "$TMPD/sh.elf" 2>/dev/null) Oktette fuer die Shell)" \
    || bad "die Programme fuer das Terminalfenster lassen sich nicht bauen"
python3 tools/osum/mkfs.py build "$DISK" 4096 /lib/ \
    /lib/mono.ttf=assets/osum-mono.ttf /lib/sans.ttf=assets/osum-sans.ttf \
    /bin/ /bin/sh="$TMPD/sh.elf" /bin/echo="$TMPD/echo.elf" \
    /bin/uname="$TMPD/uname.elf" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "mkfs.py baut ein Abbild mit beiden Schriften und der Shell" \
    || { bad "mkfs.py fehlgeschlagen"; sed 's/^/        /' "$TMPD/mkfs.txt"; }

echo "== 4. der Rasterer: Kernel gegen Wirt, Oktett fuer Oktett =="
# Der Kernel gibt acht Glyphen als Text und als Pruefsumme ueber die
# ROHEN Deckungswerte aus; `raster.py` rastert dieselben selbst.  Das ist
# die staerkste Zusage ueber den Rasterer, die es ohne ein Bild gibt.
lauf "$K0" "gfx wm ttfdump $GRUND" "$TMPD/dump.txt"
rc=$?
num "der Kern beendet sich sauber" "$rc" eq 21
has "$TMPD/dump.txt" "ttfglyph c=86" "der Kern gibt seine Glyphen aus"
v=$(python3 tools/ttf/raster.py vergleich assets/osum-mono.ttf "$TMPD/dump.txt" 2>&1)
if [ $? -eq 0 ]; then ok "beide Rasterer sind sich einig ($v)"
else bad "die beiden Rasterer gehen auseinander"; echo "$v" | sed 's/^/        /'; fi
# Die Gegenprobe zum Vergleich selbst: gegen die ANDERE Schrift darf er
# nicht aufgehen -- sonst prueft er nichts.
if python3 tools/ttf/raster.py vergleich assets/osum-sans.ttf "$TMPD/dump.txt" >/dev/null 2>&1; then
    bad "der Vergleich geht auch gegen die falsche Schrift auf"
else
    ok "gegen die Antiqua geht derselbe Vergleich NICHT auf"
fi
st=$(zahl "$TMPD/dump.txt" 'ttf: mono.*selftest [0-9]+')
num "die Zusagen des Schriftlesers ueber sich selbst (mono)" "$st" eq 12
st2=$(zahl "$TMPD/dump.txt" 'ttf: sans.*selftest [0-9]+')
num "dieselben fuer die Antiqua" "$st2" eq 12
kp=$(grep -aoE 'ttf: sans.*kern=[0-9]+' "$TMPD/dump.txt" | grep -oE 'kern=[0-9]+' | grep -oE '[0-9]+')
num "Zeichenpaare, die wirklich unterschnitten werden" "$kp" gt 20
km=$(grep -aoE 'ttf: mono.*kern=[0-9]+' "$TMPD/dump.txt" | grep -oE 'kern=[0-9]+' | grep -oE '[0-9]+')
num "und die Festbreitenschrift hat keine (sie braucht keine)" "$km" eq 0

echo "== 5. das Zeigegeraet: PS/2 am zweiten Anschluss des 8042 =="
ms=$(zahl "$TMPD/dump.txt" 'mouse: id=[0-9]+')
num "die Kennung nach dem Radgriff (3 = mit Rad, vier Oktette je Paket)" "$ms" eq 3
mst=$(zahl "$TMPD/dump.txt" 'mouse: .*selftest [0-9]+')
num "die Zusagen des Treibers ueber sich selbst" "$mst" eq 10
# Der Eintrag der Umleitungstabelle steht im Bericht am Ende eines
# Laufes mit `wmhold` -- er wird in Abschnitt 6 geholt.

echo "== 6. der Fensterserver: Selbsttest und das Foto =="
foto "$K0" "gfx wm wmhold $GRUND" "$TMPD/w.txt" "$TMPD/w.ppm"
num "der Kern beendet sich sauber" "$RC" eq 21
has "$TMPD/w.txt" "wm: hold" "der Kern haelt fuer das Foto still"
ws=$(zahl "$TMPD/w.txt" 'wm: .*selftest [0-9]+')
num "die Zusagen des Fensterservers ueber sich selbst" "$ws" eq 30
has "$TMPD/w.txt" "wm: 800x600" "der Server kennt die Flaeche"
has "$TMPD/w.txt" "wm: term win=0  cols=56  rows=20  cell=10x19" \
    "das Terminalfenster hat ein Raster von 56x20 Zellen zu 10x19"
wn=$(zahl2 "$TMPD/w.txt" 'wm: windows=[0-9]+')
num "zwei Fenster: das Terminal und die Anwendung aus Ring 3" "$wn" eq 2
schau "das Foto ist 800x600" groesse "$TMPD/w.ppm" 800 600
# DIE GEOMETRIE: der Rahmen des Fensters aus Ring 3 liegt auf den
# Bildpunkt da, wo der Server ihn fuehrt -- 264x174 bei (420,330), und
# einen Bildpunkt daneben ist er NICHT.
schau "der Rahmen des Fensters aus Ring 3 liegt bildpunktgenau" \
    rechteck "$TMPD/w.ppm" 420 330 264 174 76 154 232
# DIE STAPELREIHENFOLGE: an einer Stelle, die BEIDE Fenster bedecken,
# gewinnt das obere.  Das ist die ganze Zusage in einem Rechteck.
# Die Flaeche, die RING 3 in sein Fenster gemalt hat (0x101820), an einer
# Stelle, an der darunter das Terminalfenster liegt.
schau "an der Ueberschneidung steht das OBERE Fenster" \
    flaeche "$TMPD/w.ppm" 430 353 100 6 16 24 32
schau_nicht "und NICHT die Flaeche des unteren" \
    flaeche "$TMPD/w.ppm" 430 353 100 6 16 20 26
schau "der Hintergrund neben den Fenstern gehoert dem Server" \
    flaeche "$TMPD/w.ppm" 700 60 80 80 30 42 56
# Der Zeiger: die Spitze steht in der Mitte, und der Umriss ist schwarz.
gsi=$(grep -aoE 'gsi=0x[0-9a-f]+' "$TMPD/w.txt" | head -1 | sed 's/.*=//')
if [ "$gsi" = "0x2e" ]; then
    ok "der Eintrag der Umleitungstabelle fuer GSI 12: $gsi (Vektor 46, nicht maskiert)"
else
    bad "GSI 12 zeigt '$gsi' statt 0x2e"
fi
schau "die Spitze des Zeigers steht in der Bildmitte" \
    punkt "$TMPD/w.ppm" 399 299 0 0 0
schau "und zwei Bildpunkte tiefer ist er weiss gefuellt" \
    punkt "$TMPD/w.ppm" 400 301 255 255 255

echo "== 7. der Text im Fenster, bildpunktgenau gegen den zweiten Rasterer =="
# NICHT Flaeche gegen Flaeche.  Je Zeichen die gesetzten Bildpunkte, und
# ein Zeichen ohne Tinte laesst die Zusage fallen -- die Lehre aus K7B.
schau "Zeile 0 des Terminalfensters" \
    tgrid "$TMPD/w.ppm" assets/osum-mono.ttf 16 26 62 10 19 0 0 \
    224 230 236 16 20 26 "OSUM K10 WINDOW SERVER 0123"
schau "Zeile 1 des Terminalfensters" \
    tgrid "$TMPD/w.ppm" assets/osum-mono.ttf 16 26 62 10 19 1 0 \
    224 230 236 16 20 26 "abcdefghijklm ABCDEFGHIJK +-*/"
# Der Titel in der Antiqua, mit Laufweite und Unterschneidung -- eine
# Festbreitenrechnung ginge hier NICHT auf.
schau "der Titel des Fensters aus Ring 3, mit Unterschneidung" \
    ttext "$TMPD/w.ppm" assets/osum-sans.ttf 15 427 345 255 255 255 \
    28 78 126 "Klick mich"
schau "der Titel des Terminalfensters, unbeleuchtet" \
    ttext "$TMPD/w.ppm" assets/osum-sans.ttf 15 31 55 144 156 168 \
    44 56 72 "Terminal -- sh"
# IST ES WIRKLICH EINE KANTENGLAETTUNG?  Eine Rasterung ohne Glaettung
# haette KEINE Zwischenstufe und ginge durch alles oben hindurch.
schau "der Text ist wirklich kantengeglaettet" \
    glatt "$TMPD/w.ppm" 26 62 280 20 224 230 236 16 20 26 100
# Und die Gegenprobe zum Pruefer: an einer Stelle, an der kein Text
# steht, findet er keinen.
schau_nicht "wo kein Text steht, geht dieselbe Rechnung NICHT auf" \
    tgrid "$TMPD/w.ppm" assets/osum-mono.ttf 16 26 62 10 19 8 0 \
    224 230 236 16 20 26 "OSUM K10 WINDOW SERVER 0123"

echo "== 8. die Maus: Bewegung und Klick von aussen in die Maschine =="
# Erst in die linke obere Ecke (der Anschlag loescht die Vorgeschichte),
# dann in Schritten unter 128 an eine Stelle, die sich AUSRECHNEN laesst:
# 0 + 4*100 + 100 = 500 waagerecht, 0 + 4*100 = 400 senkrecht.
cat > "$TMPD/klick.mon" <<'EOF'
mouse_move -120 -120
mouse_move -120 -120
mouse_move -120 -120
mouse_move -120 -120
mouse_move -120 -120
mouse_move -120 -120
mouse_move 100 100
mouse_move 100 100
mouse_move 100 100
mouse_move 100 100
mouse_move 100 0
mouse_button 1
mouse_button 0
mouse_move 120 120
mouse_move 120 79
EOF
foto "$K0" "gfx wm wmhold $GRUND" "$TMPD/k.txt" "$TMPD/k.ppm" "$TMPD/klick.mon"
num "der Kern beendet sich sauber" "$RC" eq 21
mx=$(grep -aoE 'wminput: x=[0-9]+' "$TMPD/k.txt" | tail -1 | grep -oE '[0-9]+')
my=$(grep -aoE 'wminput: x=[0-9]+  y=[0-9]+' "$TMPD/k.txt" | tail -1 | sed 's/.*y=//')
num "der Zeiger landet waagerecht, wo er soll" "$mx" eq 740
num "und senkrecht ebenso" "$my" eq 599
pk=$(grep -aoE 'packets=[0-9]+' "$TMPD/k.txt" | tail -1 | grep -oE '[0-9]+')
num "Pakete, die der Treiber zusammengesetzt hat" "$pk" eq 15
dr=$(grep -aoE 'drops=[0-9]+' "$TMPD/k.txt" | tail -1 | grep -oE '[0-9]+')
num "und KEIN Oktett, das er wegwerfen musste" "$dr" eq 0
# DIE ZUSAGE: der Klick kommt beim RICHTIGEN Fenster an, und mit seinen
# ORTSKOORDINATEN.  (500,400) auf dem Schirm ist (78,48) im Fenster aus
# Ring 3 -- 500 - 420 - 2 und 400 - 330 - 22.
has "$TMPD/k.txt" "wclick: down 78,48" \
    "der Klick kommt in Ring 3 an, mit den Koordinaten IM Fenster"
# Und was die Anwendung daraufhin gemalt hat, steht im Foto -- genau da.
schau "der Fleck, den Ring 3 auf den Klick hin gemalt hat" \
    flaeche "$TMPD/k.ppm" 500 400 8 8 255 192 32
schau_nicht "und einen Bildpunkt daneben ist er nicht" \
    punkt "$TMPD/k.ppm" 499 400 255 192 32
# Die Gegenprobe: OHNE Klick gibt es den Fleck nicht.
schau_nicht "ohne Klick ist der Fleck NICHT da" \
    flaeche "$TMPD/w.ppm" 500 400 8 8 255 192 32
hasnot "$TMPD/w.txt" "wclick: down" "und in Ring 3 kommt dann auch nichts an"
# Und ein Klick auf den HINTERGRUND geht an kein Fenster.
cat > "$TMPD/leer.mon" <<'EOF'
mouse_move -120 -120
mouse_move -120 -120
mouse_move -120 -120
mouse_move -120 -120
mouse_move -120 -120
mouse_move -120 -120
mouse_move 120 120
mouse_move 120 120
mouse_move 120 120
mouse_move 120 120
mouse_move 120 90
mouse_move 120 0
mouse_button 1
mouse_button 0
EOF
foto "$K0" "gfx wm wmhold $GRUND" "$TMPD/l.txt" "$TMPD/l.ppm" "$TMPD/leer.mon"
hasnot "$TMPD/l.txt" "wclick: down" \
    "ein Klick auf den Hintergrund kommt bei KEINEM Fenster an"
lx=$(grep -aoE 'wminput: x=[0-9]+' "$TMPD/l.txt" | tail -1 | grep -oE '[0-9]+')
num "der Zeiger stand dabei rechts unten, neben beiden Fenstern" "$lx" eq 720

echo "== 9. verschieben und schliessen -- mit der Maus =="
# Die Titelleiste des Fensters aus Ring 3 liegt bei y = 330..351; ein
# Druck darauf und eine Bewegung verschieben es.
cat > "$TMPD/zieh.mon" <<'EOF'
mouse_move -120 -120
mouse_move -120 -120
mouse_move -120 -120
mouse_move -120 -120
mouse_move -120 -120
mouse_move -120 -120
mouse_move 100 100
mouse_move 100 100
mouse_move 100 100
mouse_move 120 40
mouse_move 40 0
mouse_button 1
mouse_move -60 -60
mouse_move -60 -60
mouse_button 0
mouse_move 100 100
mouse_move 100 100
EOF
foto "$K0" "gfx wm wmhold $GRUND" "$TMPD/z.txt" "$TMPD/z.ppm" "$TMPD/zieh.mon"
num "der Kern beendet sich sauber" "$RC" eq 21
# Gedrueckt bei (460,340) -- das ist 40 waagerecht und 10 senkrecht
# innerhalb des Fensters --, dann 120 nach links oben: das Fenster steht
# jetzt bei (300,210).
schau "das Fenster steht nach dem Ziehen an der neuen Stelle" \
    rechteck "$TMPD/z.ppm" 300 210 264 174 76 154 232
schau_nicht "und an der alten NICHT mehr" \
    rechteck "$TMPD/z.ppm" 420 330 264 174 76 154 232
schau "der Titel ist mitgewandert, bildpunktgenau" \
    ttext "$TMPD/z.ppm" assets/osum-sans.ttf 15 307 225 255 255 255 \
    28 78 126 "Klick mich"
# Und das Schliessfeld: es sitzt rechts oben im Rahmen.  Nach dem
# Verschieben liegt es bei (300 + 264 - 2 - 14 - 3, 210 + 4) = (545,214).
cat > "$TMPD/zu.mon" <<'EOF'
mouse_move -120 -120
mouse_move -120 -120
mouse_move -120 -120
mouse_move -120 -120
mouse_move -120 -120
mouse_move -120 -120
mouse_move 120 120
mouse_move 120 120
mouse_move 120 100
mouse_move 120 0
mouse_move 100 0
mouse_move 92 0
mouse_button 1
mouse_button 0
EOF
foto "$K0" "gfx wm wmhold $GRUND" "$TMPD/c.txt" "$TMPD/c.ppm" "$TMPD/zu.mon"
cx=$(grep -aoE 'wminput: x=[0-9]+' "$TMPD/c.txt" | tail -1 | grep -oE '[0-9]+')
num "der Zeiger steht auf dem Schliessfeld" "$cx" eq 672
wn2=$(grep -aoE 'wmafter: n=[0-9]+' "$TMPD/c.txt" | tail -1 | sed 's/.*=//')
num "nach dem Klick auf das Schliessfeld bleibt EIN Fenster" "$wn2" eq 1
wnv=$(grep -aoE 'wmafter: n=[0-9]+' "$TMPD/w.txt" | tail -1 | sed 's/.*=//')
num "ohne den Klick bleiben es zwei" "$wnv" eq 2
schau_nicht "der Rahmen des geschlossenen Fensters ist weg" \
    rechteck "$TMPD/c.ppm" 420 330 264 174 76 154 232
# UND DAS IST DIE ZUSAGE UEBER DIE WIEDERHERSTELLUNG: da, wo das Fenster
# war, steht jetzt wieder das, was darunter lag -- kein Gespenst.
schau "wo das Fenster war, steht wieder der Hintergrund des Servers" \
    flaeche "$TMPD/c.ppm" 600 460 60 40 30 42 56
schau "und wo es das Terminalfenster verdeckte, steht wieder dessen Flaeche" \
    flaeche "$TMPD/c.ppm" 440 400 100 30 16 20 26

echo "== 10. der Eingabefokus =="
cat > "$TMPD/tasten.mon" <<'EOF'
sendkey o
sendkey s
sendkey u
sendkey m
EOF
foto "$K0" "gfx wm wmhold $GRUND" "$TMPD/t.txt" "$TMPD/t.ppm" "$TMPD/tasten.mon"
k0=$(grep -aoE 'keys0=[0-9]+' "$TMPD/t.txt" | tail -1 | sed 's/.*=//')
k1=$(grep -aoE 'keys1=[0-9]+' "$TMPD/t.txt" | tail -1 | sed 's/.*=//')
num "die vier Tasten kommen beim Fenster MIT dem Fokus an" "$k1" eq 4
num "und beim anderen kommt KEINE an" "$k0" eq 0
has "$TMPD/t.txt" "wclick: key 111" "Ring 3 sieht das gedrueckte Zeichen"
# DIE GEGENPROBE, und sie ist der Grund, warum die Zeile darueber etwas
# wert ist: mit `nofocus` geht jede Taste an JEDES Fenster.
foto "$K0" "gfx wm wmhold nofocus $GRUND" "$TMPD/nf.txt" "$TMPD/nf.ppm" \
    "$TMPD/tasten.mon"
n0=$(grep -aoE 'keys0=[0-9]+' "$TMPD/nf.txt" | tail -1 | sed 's/.*=//')
n1=$(grep -aoE 'keys1=[0-9]+' "$TMPD/nf.txt" | tail -1 | sed 's/.*=//')
num "mit 'nofocus' bekommt das falsche Fenster sie AUCH" "$n0" eq 4
num "und das richtige weiterhin" "$n1" eq 4
has "$TMPD/nf.txt" "focus=0" "und der Lauf sagt selbst, dass der Fokus aus ist"

echo "== 11. die Zeiten =="
grep -aE '^wmbench: ' "$TMPD/dump.txt" | sed 's/^/   /'
voll=$(grep -a 'wmbench: compose' "$TMPD/dump.txt" | grep -oE 'full=[0-9]+' | grep -oE '[0-9]+')
klein=$(grep -a 'wmbench: compose' "$TMPD/dump.txt" | grep -oE 'small=[0-9]+' | grep -oE '[0-9]+')
kalt=$(grep -a 'wmbench: glyph' "$TMPD/dump.txt" | grep -oE 'cold=[0-9]+' | grep -oE '[0-9]+')
warm=$(grep -a 'wmbench: glyph' "$TMPD/dump.txt" | grep -oE 'warm=[0-9]+' | grep -oE '[0-9]+')
num "voller Bildaufbau des Servers (us)" "$voll" gt 0
num "nur der Bereich eines Zeigers (us)" "$klein" gt 0
num "und der ist DEUTLICH billiger (Faktor mal 100)" \
    "$((voll * 100 / (klein > 0 ? klein : 1)))" gt 500
num "95 Glyphen frisch gerastert (us)" "$kalt" gt 0
num "dieselben aus dem Zwischenspeicher (us)" "$warm" gt 0
num "und der Speicher lohnt sich (Faktor mal 100)" \
    "$((kalt * 100 / (warm > 0 ? warm : 1)))" gt 1000
# DIE GEGENPROBE ZUR MESSUNG: mit `nodirty` gibt es keine
# Bereichsverfolgung -- dann MUSS der kleine Fall so teuer werden wie der
# grosse.  Ohne diese Zeile misst die Zahl darueber nichts.
lauf "$K0" "gfx wm nodirty ttfdump $GRUND" "$TMPD/nd.txt"
nvoll=$(grep -a 'wmbench: compose' "$TMPD/nd.txt" | grep -oE 'full=[0-9]+' | grep -oE '[0-9]+')
nklein=$(grep -a 'wmbench: compose' "$TMPD/nd.txt" | grep -oE 'small=[0-9]+' | grep -oE '[0-9]+')
echo "        ohne Bereichsverfolgung: full=$nvoll us  small=$nklein us"
if [ -n "$nklein" ] && [ -n "$klein" ] && [ "$nklein" -gt $((klein * 3)) ]; then
    ok "mit 'nodirty' kostet der kleine Bereich das Vielfache ($nklein statt $klein us)"
else
    bad "mit 'nodirty' aendert sich nichts: $nklein statt $klein us"
fi
has "$TMPD/nd.txt" "dirty=0" "und der Lauf sagt selbst, dass sie aus ist"

echo "== 12. die Shell im Terminalfenster =="
# Die Zeilendisziplin aus Runde K9 ist ausdruecklich so gebaut, dass das
# ANZEIGEGERAET austauschbar ist (`tty.SINK_SCREEN`).  Diese Runde traegt
# sich dort ein: SINK_WINDOW schreibt in ein Fenster -- UND weiter auf
# die serielle Leitung, damit der Mitschnitt die Grundwahrheit bleibt.
# KEIN `osum` auf der Zeile, und das ist wichtig: die Kommandozeile
# traegt EIN Skript, und es gehoert der Shell im Fenster.  `wmshell`
# haelt deshalb die Shell aus Runde K1 und die aus Runde K6 zurueck --
# sonst liest die erste das Skript weg und im Fenster steht eine leere
# Eingabezeile (gemessen, genau so passiert).
foto "$K0" "gfx wm wmhold wmshell script=uname;echo hallo-fenster;exit $GRUND" \
    "$TMPD/sh.txt" "$TMPD/sh.ppm"
num "der Kern beendet sich sauber" "$RC" eq 21
has "$TMPD/sh.txt" "sh: ready, osum" "die Shell von der Platte ist gestartet"
has "$TMPD/sh.txt" "hallo-fenster" "die Shell hat geschrieben (seriell)"
she=$(grep -aoE 'wm: sh exit=[0-9]+' "$TMPD/sh.txt" | grep -oE '[0-9]+$')
num "und sich sauber beendet" "$she" eq 0
# Und dasselbe steht IM FENSTER, bildpunktgenau.  Die Zeilen 0 und 1
# gehoeren dem Kernbanner; ab Zeile 2 schreibt die Shell.
schau "die Kopfzeile des Terminalfensters steht im Bild" \
    tgrid "$TMPD/sh.ppm" assets/osum-mono.ttf 16 26 62 10 19 0 0 \
    224 230 236 16 20 26 "OSUM K10 WINDOW SERVER 0123"
if grep -qa 'hallo-fenster' "$TMPD/sh.txt"; then
    # WELCHE Rasterzeile die Ausgabe traegt, haengt daran, wie viele
    # Zeilen die Shell vorher geschrieben hat.  Also wird sie GESUCHT:
    # die erste Zeile, in der die Zusage aufgeht -- und wenn sie in
    # keiner aufgeht, faellt sie.
    gefunden=""
    for z in 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19; do
        if aus=$(python3 tools/gfx/checkshot.py tgrid "$TMPD/sh.ppm" \
            assets/osum-mono.ttf 16 26 62 10 19 "$z" 0 \
            224 230 236 16 20 26 "hallo-fenster" 2>&1); then
            gefunden="$z"; break
        fi
    done
    if [ -n "$gefunden" ]; then
        ok "die Ausgabe der Shell steht bildpunktgenau in Zeile $gefunden des Fensters ($aus)"
    else
        bad "die Ausgabe der Shell steht in keiner Zeile des Fensters"
    fi
fi

echo "== 13. DIE GEGENPROBEN: ohne 'wm' aendert sich nichts =="
lauf "$K0" "gfx $GRUND" "$TMPD/ohne.txt"
rc=$?
num "der Kern beendet sich sauber" "$rc" eq 21
has "$TMPD/ohne.txt" "wm: skipped" "ohne das Wort 'wm' faengt der Server gar nicht an"
hasnot "$TMPD/ohne.txt" "ttf: mono" "kein Zeichensatz wird gelesen"
hasnot "$TMPD/ohne.txt" "mouse: id=" "kein Zeigegeraet wird aufgesetzt"
hasnot "$TMPD/ohne.txt" "wclick:" "und kein Fenster in Ring 3"
# Und die Textkonsole aus Runde K7 tut wieder, was sie immer tat.
has "$TMPD/ohne.txt" "fb: console mirrored to screen" \
    "die Textkonsole aus Runde K7 spiegelt wie vorher"
# `nomouse`: der Server laeuft, der Zeiger fehlt.
foto "$K0" "gfx wm wmhold nomouse $GRUND" "$TMPD/nm.txt" "$TMPD/nm.ppm"
has "$TMPD/nm.txt" "mouse: kein Zeiger" "mit 'nomouse' gibt es kein Zeigegeraet"
has "$TMPD/nm.txt" "cursor=0" "und der Server malt keinen"
schau_nicht "im Bild steht an der Zeigerstelle KEIN Zeiger" \
    punkt "$TMPD/nm.ppm" 400 301 255 255 255
schau "das Terminalfenster steht trotzdem da" \
    tgrid "$TMPD/nm.ppm" assets/osum-mono.ttf 16 26 62 10 19 0 0 \
    224 230 236 16 20 26 "OSUM K10 WINDOW SERVER 0123"
# `nompoll`: NUR die Unterbrechung.  Die Zahl dahinter ist der ehrliche
# Befund dieser Runde ueber QEMUs 8042 -- siehe docs/ROUNDK10.md.
foto "$K0" "gfx wm wmhold nompoll $GRUND" "$TMPD/np.txt" "$TMPD/np.ppm" \
    "$TMPD/klick.mon"
nppk=$(grep -aoE 'packets=[0-9]+' "$TMPD/np.txt" | tail -1 | sed 's/.*=//')
npx=$(grep -aoE 'wminput: x=[0-9]+' "$TMPD/np.txt" | tail -1 | sed 's/.*=//')
nppo=$(grep -aoE 'polls=[0-9]+' "$TMPD/np.txt" | tail -1 | sed 's/.*=//')
num "mit 'nompoll' traegt IRQ 12 ALLEIN dieselben Pakete" "$nppk" eq 15
num "und der Zeiger landet an derselben Stelle" "$npx" eq 740
num "abgefragt wurde dabei kein einziges Mal" "$nppo" eq 0
has "$TMPD/np.txt" "wclick: down 78,48" \
    "auch der Klick kommt ueber die Unterbrechung allein an"
# UND DIE ZAHL, DIE DEN RUECKFALL BEGRUENDET: im Regellauf wird BEIDES
# benutzt, und wie viel auf welchem Weg kam, steht da.
npi=$(grep -aoE 'irqs=[0-9]+' "$TMPD/k.txt" | tail -1 | sed 's/.*=//')
npp=$(grep -aoE 'polls=[0-9]+' "$TMPD/k.txt" | tail -1 | sed 's/.*=//')
nps=$(grep -aoE 'spurious=[0-9]+' "$TMPD/k.txt" | tail -1 | sed 's/.*=//')
echo "        im Regellauf: irqs=$npi  davon leer=$nps  abgefragt=$npp"
num "im Regellauf kommen Oktette auf BEIDEN Wegen an (Unterbrechungen)" \
    "$npi" gt 0

echo
if [ "$fail" -eq 0 ]; then
    echo "WM: $pass passed, 0 failed"
else
    echo "WM: $pass passed, $fail FAILED"
fi
[ "$fail" -eq 0 ]
