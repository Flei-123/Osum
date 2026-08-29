#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/speicher/run.sh -- DER BEWEIS, DASS OSUM DIE FRAGE "WAS FRISST
# MEINEN PLATZ" BEANTWORTET, OHNE DIE PLATTE ZU DURCHLAUFEN.
#
# TreeSize und WizTree koennen diese Frage auch. Beide muessen dafuer
# beim Start die Platte lesen -- WizTree die Master File Table am Stueck,
# TreeSize Verzeichnis fuer Verzeichnis --, und beide fangen bei jedem
# Start von vorn an. Osum nicht: `kernel/nidx.fi` fuehrt seit Runde K15
# ein Aenderungsjournal des Dateisystems, und seit dieser Runde traegt es
# nicht nur Namen, sondern auch GROESSEN, aufsummiert bis zur Wurzel.
#
# DAS IST EINE BEHAUPTUNG. Dieser Laeufer macht Zahlen daraus:
#
#   1. ZEIT GEGEN ZEIT. Auf einem Abbild mit viertausend Dateien wird
#      dieselbe Frage zweimal gestellt -- einmal an den Index, einmal an
#      einen vollstaendigen Verzeichnisdurchlauf --, und beide Zeiten
#      stehen nebeneinander. Gemessen wird IM GAST, mit derselben Uhr,
#      hintereinander, damit die Last des Wirts beide gleich trifft.
#   2. RICHTIGKEIT VOR GESCHWINDIGKEIT. Eine sofortige, aber falsche Zahl
#      ist wertlos. Also wird JEDES Verzeichnis des Abbilds Oktett fuer
#      Oktett gegen den echten Durchlauf gehalten (`du -p`) -- und
#      zusaetzlich gegen eine DRITTE Zahl, die `tools/speicher/tree.py`
#      auf dem WIRT ausrechnet, in Python, ohne den Kernel zu kennen
#      (`tools/speicher/pruefen.py`). Zwei Wege koennen denselben
#      Denkfehler haben; drei ist unwahrscheinlicher.
#   3. DAS JOURNAL MUSS WACHSTUM MITBEKOMMEN. Ein Namensindex merkt, dass
#      es einen Namen mehr gibt. Ein Speicherindex muss merken, dass eine
#      Datei GEWACHSEN ist -- das passiert oefter. `du -w` schreibt in
#      eine Datei und prueft, dass die Summen sich um genau den
#      Unterschied bewegt haben, ohne Neuaufbau.
#   4. JEDE ZUSAGE HAT EINE GEGENPROBE. `du -W` schaltet das Nachziehen
#      ab: dann MUSS die Zahl falsch werden. `wignoidx` nimmt der
#      Oberflaeche den Index: dann MUESSEN dort Nullen stehen. Eine
#      Messung, die auch ohne ihre Quelle noch stimmt, misst nichts.
#   5. DIE OBERFLAECHE WIRD ANGESEHEN. `/bin/speicher` laeuft unter dem
#      Fensterserver, und es entstehen Bildschirmfotos -- ein Baum, der
#      im Quelltext richtig aussieht, kann im Bild uebereinander liegen.
#
# DAUER: die Laeufe mit vollstaendigem Durchlauf brauchen Minuten, nicht
# Sekunden -- ohne KVM ist jeder Inode-Zugriff emulierte IDE. Genau das
# ist ja der Punkt.
#
# Verwendung:  bash tools/speicher/run.sh [ausgabeverzeichnis]
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
TMPD=${1:-$(mktemp -d)}
mkdir -p "$TMPD"
SHOTS=${SHOTS:-$ROOT/docs/bilder/speicher}

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
# EIN FELD AUS EINER GEMELDETEN ZEILE. `grep -oE '.*okt=[0-9]+'` waere
# gierig und faende bei `laufkb=` das falsche Feld; deshalb wird der
# Feldname mit Wortgrenze davor gesucht.
# DIE ZAHL HINTER DEM GLEICHHEITSZEICHEN, und zwar NUR sie. Die erste
# Fassung schloss mit `grep -oE '[0-9]+'` ab und gab fuer `us10=161`
# zwei Zahlen zurueck ("10" aus dem Feldnamen und "161"); jede Zusage,
# die darauf rechnete, verglich Unsinn. Also wird der Feldname mit
# `sed` abgeschnitten statt nach Ziffern gesucht.
feld() { grep -aoE "(^|[^a-z])$3=[0-9]+" <(grep -aF "$2" "$1" | tail -1) \
         | tail -1 | sed 's/.*=//'; }

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "SPEICHER: uebersprungen, qemu-system-x86_64 ist nicht da"; exit 0
fi
bash vendor/firn/fetch-firnc.sh >/dev/null || {
    echo "vendor/firn/fetch-firnc.sh fehlgeschlagen"; exit 1; }

echo "== bauen"
bash tools/speicher/build.sh "$TMPD" || exit 1

# --------------------------------------------------------------- Laeufe
#
# `nokbd nosched noproc nofs noring3` ist die stille Grundlage: kein
# Zeitgeber, der in die Messung hineinredet, keine Selbsttests, die die
# serielle Leitung fuellen. `script=...` gibt der Schale eine Zeile.
lauf() { # name kommandozeile [abbild] [frist]
    local name=$1 zeile=$2 img=${3:-inhalt.img} frist=${4:-3000}
    cp -f "$TMPD/$img" "$TMPD/live-$name.img"
    timeout "$frist" $QEMU_X86 -kernel "$TMPD/k.mb" -m 256 \
        -append "osum nokbd nosched noproc nofs noring3 script=$zeile;exit" \
        -serial "file:$TMPD/$name.txt" -display none -no-reboot \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    echo "RC=$?" > "$TMPD/$name.rc"
}

# EIN BILDSCHIRMFOTO. Der Weg ist der aus Runde K15: QEMU bekommt eine
# Bildflaeche (`-vga std`) auch bei `-display none`, und ueber den
# Monitor an einem Unix-Socket schreibt `screendump` sie als PPM.
foto() { # name kommandozeile [marke]
    local name=$1 zeile=$2 marke=${3:-'^speicher: ready'}
    local sock="$TMPD/mon-$name.sock"
    local aus="$TMPD/$name.txt" ppm="$TMPD/$name.ppm"
    rm -f "$aus" "$ppm" "$sock"
    cp -f "$TMPD/inhalt.img" "$TMPD/live-$name.img"
    timeout 900 $QEMU_X86 -kernel "$TMPD/k.mb" -m 256 \
        -append "$zeile" -serial "file:$aus" -display none -no-reboot \
        -vga std -monitor "unix:$sock,server,nowait" \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local pid=$!
    local i=0
    while [ $i -lt 4000 ]; do
        grep -qaE "$marke" "$aus" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.15
        i=$((i + 1))
    done
    sleep 2
    python3 tools/gfx/screenshot.py "$sock" "$ppm" 25 > "$TMPD/$name.shot" 2>&1
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    rm -f "$sock"
    return 0
}

echo "== 1. Zeit: der Index gegen den vollstaendigen Durchlauf"
echo "   (auf gross.img, viertausend Dateien -- das dauert Minuten)"
lauf zeit 'du -m /data' gross.img
IUS=$(feld "$TMPD/zeit.txt" "du: index [/data]" us10)
WUS=$(feld "$TMPD/zeit.txt" "du: durchlauf [/data]" us)
NDAT=$(feld "$TMPD/zeit.txt" "du: durchlauf [/data]" dateien)
BUS=$(feld "$TMPD/zeit.txt" "du: bauen" us)
has "$TMPD/zeit.txt" "du: vergleich" "die Messung ist durchgelaufen"
num "Dateien im Durchlauf" "$NDAT" ge 4000
if [ -n "${IUS:-}" ] && [ -n "${WUS:-}" ] && [ "$IUS" -gt 0 ]; then
    # us10 ist die Zeit fuer ZEHN Abfragen -- so gemessen, weil eine
    # einzelne unter der Koernung der Uhr laege.
    FAKTOR=$(( WUS * 10 / IUS ))
    ok "Index $((IUS / 10)) us je Abfrage, Durchlauf $WUS us -- Faktor $FAKTOR"
    num "der Index ist wenigstens tausendmal schneller" "$FAKTOR" ge 1000
    ok "einmaliger Aufbau des Index: $BUS us"
    if [ -n "${BUS:-}" ] && [ "$BUS" -gt 0 ]; then
        num "schon der AUFBAU schlaegt den Durchlauf" \
            $(( WUS / BUS )) ge 2
    fi
else
    bad "Zeiten fehlen (Index '$IUS', Durchlauf '$WUS')"
fi

echo "== 2. Richtigkeit: dieselbe Frage auf einem Abbild MIT Inhalt"
lauf mess 'du -m /data'
MOKT=$(feld "$TMPD/mess.txt" "du: index [/data]" okt)
MWOKT=$(feld "$TMPD/mess.txt" "du: durchlauf [/data]" okt)
SOLL=$(awk '$1=="/data"{print $2}' "$TMPD/baum/soll")
num "die Summe ist nicht null" "${MOKT:-0}" gt 0
if [ "${MOKT:-x}" = "${MWOKT:-y}" ]; then ok "Index = Durchlauf: $MOKT Oktette"
else bad "Index $MOKT, Durchlauf $MWOKT"; fi
if [ "${MOKT:-x}" = "${SOLL:-y}" ]; then ok "und der Wirt rechnet dasselbe: $SOLL"
else bad "der Wirt sagt $SOLL, der Gast $MOKT"; fi
has "$TMPD/mess.txt" "oktok=1" "die Gegenprobe des Gastes selbst"

echo "== 3. JEDES Verzeichnis, Oktett fuer Oktett, gegen drei Zahlen"
lauf probe 'du -p'
if python3 tools/speicher/pruefen.py "$TMPD/baum/soll" "$TMPD/probe.txt" \
        > "$TMPD/pruefen.log" 2>&1; then
    ok "$(tail -1 "$TMPD/pruefen.log")"
else
    bad "die grosse Gegenprobe: $(tail -3 "$TMPD/pruefen.log" | tr '\n' ' ')"
fi
sed 's/^/     /' "$TMPD/pruefen.log"

echo "== 4. Das Journal muss WACHSTUM mitbekommen (nicht nur neue Namen)"
lauf schreib 'du -w'
has "$TMPD/schreib.txt" "du: schreib" "die Schreibprobe ist gelaufen"
num "kein Satz ist verlorengegangen" "$(feld "$TMPD/schreib.txt" 'du: schreib nachgezogen' lost)" eq 0
num "die Summe wurde nachgezogen, ohne neu zu bauen" \
    "$(feld "$TMPD/schreib.txt" 'du: schreib bauten' bauten)" eq 1
num "die nachgezogene Summe stimmt" \
    "$(feld "$TMPD/schreib.txt" 'du: schreib nachgezogen' ok)" eq 1
num "und nach dem Loeschen steht wieder der alte Stand da" \
    "$(feld "$TMPD/schreib.txt" 'du: schreib weg' ok)" eq 1

echo "== 5. Gegenprobe: ohne Nachziehen MUSS die Zahl falsch werden"
lauf schreibW 'du -W'
# GEPRUEFT WIRD DAS FELD, NICHT DIE ZEICHENFOLGE. `grep -qa "ok=0"`
# stand hier zuerst und ging IMMER durch: die Energieschicht schreibt
# beim Hochfahren `pwr: tempok=0` und `pwr: acok=0`, und beides enthaelt
# "ok=0". Die Gegenprobe haette also auch dann bestanden, wenn sie
# durchgefallen waere -- genau der Fehler, den diese Runde an anderer
# Stelle schon einmal gemacht hat.
WOK=$(feld "$TMPD/schreibW.txt" 'du: schreib nachgezogen' ok)
WNACH=$(feld "$TMPD/schreibW.txt" 'du: schreib nachgezogen' nachher)
WERW=$(feld "$TMPD/schreibW.txt" 'du: schreib nachgezogen' erwartet)
if [ "${WOK:-1}" = "0" ] && [ "${WNACH:-0}" != "${WERW:-0}" ]; then
    ok "ohne Journal steht die Summe daneben ($WNACH statt $WERW) -- also zog vorher wirklich das Journal"
else
    bad "ohne Journal stimmte trotzdem alles (ok=$WOK, $WNACH gegen $WERW): dann misst die Probe nichts"
fi

echo "== 6. Die Oberflaeche"
mkdir -p "$SHOTS"
GRUND="nokbd nosched noproc nofs"
# GEWARTET WIRD AUF `speicher: ready`, UND DAS DAUERT. Das Programm macht
# vor dieser Zeile seine eigene Gegenprobe -- einen vollstaendigen
# Durchlauf des angezeigten Verzeichnisses --, und genau die soll hier
# mit aufgezeichnet werden. Die Kacheln stehen laengst im Bild; wer nur
# ein Foto will, nimmt `speicher: kachel` als Marke und ist in Sekunden
# fertig.
foto ruhe "gfx wm wig wigspeicher wmhold wiglong $GRUND" '^speicher: ready'
has "$TMPD/ruhe.txt" "k15: start /bin/speicher" "/bin/speicher kommt VON DER PLATTE"
has "$TMPD/ruhe.txt" "speicher: kachel" "es hat seine Kacheln gerechnet"
SOKT=$(feld "$TMPD/ruhe.txt" "speicher: cd /data" okt)
if [ "${SOKT:-x}" = "${SOLL:-y}" ]; then
    ok "die Oberflaeche zeigt dieselbe Zahl wie du und wie der Wirt: $SOKT"
else
    bad "die Oberflaeche sagt '$SOKT', du und der Wirt sagen '$SOLL'"
fi
# Die Summe der angezeigten Zeilen MUSS die angezeigte Gesamtsumme sein.
# Eine Oberflaeche, deren Zeilen sich auf etwas anderes addieren als auf
# ihre eigene Statuszeile, zeigt zwei verschiedene Wahrheiten.
ZSUM=$(grep -aoE '^speicher: zeile i=[0-9]+ okt=[0-9]+' "$TMPD/ruhe.txt" \
       | grep -oE 'okt=[0-9]+' | sed 's/okt=//' \
       | awk '{s+=$1} END{print s+0}')
if [ "${ZSUM:-0}" = "${SOKT:-x}" ]; then
    ok "die Zeilen summieren sich auf die Gesamtsumme: $ZSUM"
else
    bad "die Zeilen ergeben $ZSUM, oben steht $SOKT"
fi
has "$TMPD/ruhe.txt" "speicher: probe" "die Oberflaeche rechnet sich selbst gegen"
num "und zwar richtig" "$(feld "$TMPD/ruhe.txt" 'speicher: probe' ok)" eq 1

# DIE KACHELN WERDEN IM BILD NACHGEMESSEN, nicht im Quelltext geglaubt.
if [ -s "$TMPD/ruhe.ppm" ]; then
    python3 tools/gfx/ppm2png.py "$TMPD/ruhe.ppm" "$SHOTS/speicher.png" \
        > "$TMPD/png.log" 2>&1 || cp -f "$TMPD/ruhe.ppm" "$SHOTS/speicher.ppm"
    ok "Bildschirmfoto: $SHOTS/speicher.png"
    if python3 tools/speicher/kachelprobe.py "$TMPD/ruhe.ppm" \
            "$TMPD/ruhe.txt" > "$TMPD/kachel.log" 2>&1; then
        ok "$(tail -1 "$TMPD/kachel.log")"
    else
        bad "die Treemap im Bild: $(tail -2 "$TMPD/kachel.log" | tr '\n' ' ')"
    fi
    sed 's/^/     /' "$TMPD/kachel.log"
else
    bad "kein Bildschirmfoto entstanden"
fi

echo "== 7. Gegenprobe: dieselbe Oberflaeche ohne Index"
foto ohne "gfx wm wig wigspeicher wignoidx wmhold wiglong $GRUND" \
    '^speicher: (ready|cd)'
OOKT=$(feld "$TMPD/ohne.txt" "speicher: cd" okt)
if [ "${OOKT:-0}" = "0" ]; then
    ok "ohne Index zeigt die Oberflaeche null -- sie erfindet nichts"
else
    bad "ohne Index steht dort '$OOKT': woher?"
fi
if grep -qa "speicher: kachel" "$TMPD/ohne.txt"; then
    bad "ohne Index werden trotzdem Kacheln gemalt -- aus welchen Anteilen?"
else
    ok "ohne Index verschwinden die Kacheln"
fi
[ -s "$TMPD/ohne.ppm" ] && { python3 tools/gfx/ppm2png.py "$TMPD/ohne.ppm" \
    "$SHOTS/speicher-ohne-index.png" >/dev/null 2>&1 || \
    cp -f "$TMPD/ohne.ppm" "$SHOTS/speicher-ohne-index.ppm"; }

echo
echo "SPEICHER: $pass bestanden, $fail durchgefallen   (Arbeitsstand: $TMPD)"
[ "$fail" -eq 0 ] || exit 1
exit 0
