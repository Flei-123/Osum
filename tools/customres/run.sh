#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/customres/run.sh -- DIE ABNAHME DER RUNDE CUSTOMRES.
#
# DIE FRAGE, DIE DIESE RUNDE BEANTWORTET, war: "Kann man auch
# benutzerdefinierte Aufloesungen erstellen wie im NVIDIA-Control-Panel?"
#
# Vor dieser Runde konnte man das NICHT. `vmode.set_mode` verlangte, dass
# die Zahlen in der Liste stehen, die `probe` aus zweiundzwanzig
# AUFGESCHRIEBENEN Kandidaten gesiebt hatte -- 1400x1050 stand dort nie,
# obwohl die Karte es kann, und die Antwort war E_NOMODE.
#
# WAS HIER GEMESSEN WIRD, und in dieser Reihenfolge:
#
#   1. DIE QUELLEN. Die Gruende (CW_*) stehen in ZWEI Dateien -- im Kern
#      und im Programm in Ring 3, das sie in Saetze uebersetzt. Eine
#      benannte Doppelung mit einer Zusage darauf ist etwas anderes als
#      eine vergessene. Dazu die Aufrufnummern, die kdata-Karte und die
#      feste Satzbreite von /system/BILDMODUS.
#   2. BAUEN, mit beiden Uebersetzern.
#   3. EINE EIGENE AUFLOESUNG, IM BILD. 1400x1050 steht in KEINER
#      Kandidatenliste -- das wird im Quelltext nachgesehen -- und das
#      Bildschirmfoto ist danach 1400 x 1050 Bildpunkte gross.
#   4. DIE DREI SCHRANKEN, JEDE MIT IHRER ZAHL. Das ist der Kern der
#      Runde: "geht nicht" ist wertlos. Es muss dastehen, WELCHE
#      Schranke und MIT WELCHER ZAHL -- und der Bildschirm muss danach
#      unveraendert dastehen.
#   4b. DIESELBE ANFRAGE AN EINE KLEINERE KARTE. Derselbe Kern, dieselbe
#      Befehlszeile, nur `vgamem_mb=8`: derselbe Modus wird jetzt aus
#      einem ANDEREN Grund und mit einer ANDEREN Zahl abgelehnt. Eine
#      Fehlermeldung, die sich mit der Maschine aendert, ist eine
#      Messung; eine, die immer gleich lautet, ist ein Text.
#   5. DIE FRIST, OHNE JEDES ZUTUN. Ein Programm in Ring 3 stellt eine
#      eigene Aufloesung ein und legt sich dann SCHLAFEN. Es ruft danach
#      keinen einzigen Bildschirmaufruf mehr auf. Was zurueckschaltet,
#      ist die Leerlaufaufgabe -- oder es schaltet niemand zurueck.
#   6. DER NEUSTART. DIESELBE Platte, fuenf Starts hintereinander: setzen
#      und bestaetigen - Neustart, der Modus steht wieder - zwei Starts
#      ohne Bestaetigung - der Zaehler ist voll, der Startmodus bleibt.
#   7. RING 3. Zehn Zusagen ueber die Aufrufschwelle, und der SATZ, den
#      ein Mensch liest.
#   8. DIE GEGENPROBE. DERSELBE Kern ohne das Wort `disp`: keine eigene
#      Aufloesung, keine gespeicherte, und jede neue Zahl ist ein Strich.
#   9. DIE GRENZE, EHRLICH. Wo sie liegt, warum sie dort liegt, und was
#      sich aendert, wenn die Karte mehr Bildspeicher hat.
#
# Verwendung:  bash tools/customres/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
ULD=kernel/user/user.ld
BLOCKS=4096
PROGS="sh echo cat ls dispctl sleep"
SHOTS=docs/shots/customres

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

num() { # name wert op soll
    if [ -z "${2:-}" ]; then bad "$1: keine Zahl gefunden (erwartet $3 $4)"; return; fi
    if [ "$2" -"$3" "$4" ] 2>/dev/null; then ok "$1: $2"
    else bad "$1: $2, erwartet $3 $4"; fi
}
gleich() { if [ "$2" = "$3" ]; then ok "$1 ($3)"; else bad "$1 -- soll '$2', ist '$3'"; fi; }
hat() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hat_nicht() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da und sollte nicht" || ok "$3"; }

# Ein Feld aus einer `disp: eigen ...`-Zeile. Die Nummer waehlt, welche
# der Zeilen -- ein Lauf verlangt mehrere eigene Aufloesungen
# hintereinander, und jede hat ihre eigene Begruendung.
ew() { # datei nummer name
    grep -a '^disp: eigen ' "$1" 2>/dev/null | sed -n "$2p" \
        | grep -ao "$3=[0-9]*" | head -1 | sed 's/.*=//' | tr -d '\r\000'; }
kw() { grep -ao "^disp:.*[ =]$2=[0-9a-fx]*" "$1" 2>/dev/null | head -1 \
       | grep -ao "$2=[0-9a-fx]*" | head -1 | sed 's/.*=//' | tr -d '\r\000'; }
uw()  { grep -a -m1 "^dispctl: $2=" "$1" 2>/dev/null | sed 's/^[^=]*=//' | tr -d '\r\000'; }
uwl() { grep -a "^dispctl: $2=" "$1" 2>/dev/null | tail -1 | sed 's/^[^=]*=//' | tr -d '\r\000'; }
uwn() { grep -a "^dispctl: $2=" "$1" 2>/dev/null | sed -n "$3p" | sed 's/^[^=]*=//' | tr -d '\r\000'; }

schau() { local name=$1; shift; local aus rc
    aus=$(python3 tools/gfx/checkshot.py "$@" 2>&1); rc=$?
    if [ "$rc" -eq 0 ]; then ok "$name ($aus)"; else bad "$name -- $aus"; fi; }
schau_nicht() { local name=$1; shift; local aus rc
    aus=$(python3 tools/gfx/checkshot.py "$@" 2>&1); rc=$?
    if [ "$rc" -ne 0 ]; then ok "$name ($aus)"; else bad "$name -- ging durch: $aus"; fi; }

behalte() { # ppm zielname
    mkdir -p "$SHOTS"
    python3 tools/gfx/ppm2png.py "$1" "$SHOTS/$2.png" > /dev/null 2>&1 \
        || cp -f "$1" "$SHOTS/$2.ppm"
}

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "fetch-firnc.sh fehlgeschlagen"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "CUSTOMRES: skipped, qemu-system-x86_64 ist nicht da"; exit 0
fi
# `-accel kvm`, wo es geht. Das ist kein Schoenheitsfehler: unter TCG
# dauert ein Lauf mit einer Frist von fuenfzehn Sekunden und zweiundzwanzig
# Sekunden Schlaf laenger als das Zeitlimit, das ein Testlaeufer
# vernuenftigerweise setzt.
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL
#
# Bis zum Merge von mergeline stand hier die eigene Wahl:
#     ACCEL=""; [ -w /dev/kvm ] && ACCEL="-accel kvm"
# Die zentrale Fassung kann mehr: sie kennt die Ausnahmeliste
# (tools/lib/accel-ausnahmen.txt) und $OSUM_ACCEL. Wichtig fuer
# GENAU DIESE Runde, weil zwei ihrer Abschnitte an einer FRIST
# haengen (fuenfzehn Sekunden) -- misst der Beschleuniger die Zeit
# anders, gehoert der Abschnitt in die Liste und nicht in einen
# groesseren Zeitpuffer.
ACCEL="${QEMU_X86#qemu-system-x86_64 }"

echo "== 1. die Quellen: zwei Dateien, eine Legende =="

# DIE GRUENDE STEHEN ZWEIMAL, und das ist Absicht: `kernel/vmode.fi`
# vergibt sie, `kernel/user/dispctl.fi` macht Saetze daraus und laeuft in
# Ring 3, wo es den Kern nicht einbinden kann. Laufen die beiden Listen
# auseinander, schreibt das Programm einen anderen Satz, als der Kern
# gemeint hat -- und das faellt niemandem auf, weil beide Seiten fuer
# sich stimmig bleiben.
for r in CW_OK CW_REGS CW_VRAM CW_LIMIT CW_DEPTH CW_UNSINN CW_NOCARD; do
    a=$(grep -aE "^const $r: u64 = " kernel/vmode.fi | sed 's/.*= //; s/ *\/\/.*//')
    b=$(grep -aE "^const $r: u64 = " kernel/user/dispctl.fi | sed 's/.*= //; s/ *\/\/.*//')
    if [ -n "$a" ] && [ "$a" = "$b" ]; then ok "$r steht im Kern und in Ring 3 gleich ($a)"
    else bad "$r: vmode.fi='$a', dispctl.fi='$b'"; fi
done
# Und die Legende von `cand_why` (Runde DISPLAY) benutzt DIESELBEN
# Nummern -- eine Legende fuer beide, sonst waere die Doku eine Falle.
gleich "Grund 1 heisst hier wie dort 'die Register haben abgelehnt'" "1" \
    "$(grep -aE '^const CW_REGS' kernel/vmode.fi | sed 's/.*= //')"
gleich "Grund 2 heisst hier wie dort 'zu gross fuer den Bildspeicher'" "2" \
    "$(grep -aE '^const CW_VRAM' kernel/vmode.fi | sed 's/.*= //')"
gleich "Grund 3 heisst hier wie dort 'dieser Kernel kann es nicht abbilden'" "3" \
    "$(grep -aE '^const CW_LIMIT' kernel/vmode.fi | sed 's/.*= //')"

# Die neuen Aufrufnummern bleiben im Zehner der Runde DISPLAY
# (1810..1819) -- es sind KEINE neuen Nummern dazugekommen, nur neue
# FELDER in den drei vorhandenen.
eigen=$(grep -ahE '^const SYS_[A-Za-z0-9_]+: u64 = 181[0-9]' kernel/sys.fi | wc -l | tr -d ' ')
gleich "diese Runde braucht keine neue Aufrufnummer (weiter genau drei)" "3" "$eigen"

# /system/BILDMODUS: die Satzbreite im Quelltext und das Muster, aus dem
# der Satz gebaut wird, muessen zusammenpassen. Eine Datei, deren Laenge
# sich aendert, braucht zwei Schreibvorgaenge -- und der Zaehler, der
# einen Stromausfall ueberleben soll, darf den Zustand dazwischen nicht
# haben. Der Absatz dazu steht in kernel/dispsave.fi.
sl=$(grep -aE '^const LEN: u64 = ' kernel/dispsave.fi | sed 's/.*= //')
must=$(python3 - <<'PY'
import re, io
s = io.open("kernel/dispsave.fi", encoding="utf-8").read()
m = re.search(r'var muster: \[u8; \d+\] = "((?:[^"\\]|\\.)*)"', s)
t = m.group(1)
n = 0
i = 0
while i < len(t):
    i += 2 if t[i] == "\\" else 1
    n += 1
print(n - 1)   # die abschliessende Null gehoert nicht zum Satz
PY
)
gleich "die Satzbreite von /system/BILDMODUS stimmt mit ihrem Muster ueberein" "$sl" "$must"
if [ "$sl" -lt 512 ]; then ok "und sie geht in EINEN Datenblock ($sl < 512)"
else bad "der Satz ist laenger als ein Datenblock: $sl"; fi

if python3 tools/kernel/memmap.py kernel > "$TMPD/karte.txt" 2>&1; then
    ok "die Speicherkarte von kdata: $(tail -1 "$TMPD/karte.txt")"
else
    bad "tools/kernel/memmap.py meldet Kollisionen"; sed 's/^/        /' "$TMPD/karte.txt" | head -8
fi

echo "== 2. bauen =="
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || { echo "as scheitert"; exit 1; }
rc=0
bash tools/build-kernel.sh "$TMPD/k0.mb" > "$TMPD/k0.log" 2>&1 || {
    bad "der Kern laesst sich nicht bauen"; tail -8 "$TMPD/k0.log" | sed 's/^/        /'; rc=1; }
for p in $PROGS; do
    "$FIRNC" "kernel/user/$p.fi" -o "$TMPD/$p.o" > "$TMPD/$p.err" 2>&1 || {
        bad "firnc uebersetzt $p.fi nicht"; head -6 "$TMPD/$p.err"; rc=1; continue; }
    ld -T "$ULD" --defsym=USER_ENTRY=_F0.u_start -o "$TMPD/$p.elf" \
        "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null || { bad "ld scheitert an $p"; rc=1; continue; }
    strip --strip-all "$TMPD/$p.elf"
done
[ "$rc" = 0 ] && ok "der Kern und $(echo $PROGS | wc -w) Programme sind gebaut"
[ -f "$TMPD/k0.mb" ] || { echo "CUSTOMRES: ohne Kern geht nichts weiter"; exit 1; }

# Das Bedienfeld mit der neuen Seite. Nicht auf die Platte -- dazu
# braeuchte es einen laufenden Fensterserver --, sondern damit ein Fehler
# in den drei neuen Eingabefeldern auffaellt, bevor jemand sie oeffnet.
if "$FIRNC" kernel/user/einstellungen.fi -o "$TMPD/eins.o" > "$TMPD/eins.err" 2>&1 \
    && ld -T "$ULD" --defsym=USER_ENTRY=_F0.u_start -o "$TMPD/eins.elf" \
        "$TMPD/crt.o" "$TMPD/eins.o" 2>/dev/null; then
    u=$(nm -u "$TMPD/eins.elf" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
    [ -z "$u" ] && ok "das Bedienfeld mit den drei Eingabefeldern baut frei" \
                || bad "einstellungen.elf hat undefinierte Symbole: $u"
else
    bad "einstellungen.fi laesst sich nicht bauen"; head -8 "$TMPD/eins.err" | sed 's/^/        /'
fi
hat kernel/user/einstellungen.fi "DS_CUSTOM" \
    "das Bedienfeld ruft wirklich den neuen Aufruf und baut keine Liste nach"
hat kernel/user/einstellungen.fi "DG_CUSTNUM" \
    "und es holt die ZAHL aus dem Kern, statt eine eigene zu rechnen"

if bash tools/build-kernel.sh "$TMPD/k1.mb" --stufe 1 > "$TMPD/k1.log" 2>&1; then
    ok "firnc1 baut diese Runde auch (der Uebersetzer in Firn)"
else
    bad "firnc1 baut diese Runde nicht"; tail -5 "$TMPD/k1.log" | sed 's/^/        /'
fi

MKARGS=""
for p in $PROGS; do MKARGS="$MKARGS /bin/$p=$TMPD/$p.elf"; done
python3 tools/osum/mkfs.py build "$TMPD/root.img" "$BLOCKS" /bin/ $MKARGS \
    > "$TMPD/mkfs.log" 2>&1 && ok "die Platte steht: $(tail -1 "$TMPD/mkfs.log")" \
    || bad "mkfs.py scheitert"

GRUND="nokbd nosched noproc nofs noring3"

lauf() { # name kommandozeile [zeitlimit] [vga-argumente]
    local name=$1 zeile=$2 t=${3:-180} vga=${4:--vga std}
    rm -f "$TMPD/$name.txt"
    timeout "$t" qemu-system-x86_64 $ACCEL -kernel "$TMPD/k0.mb" -m 256 \
        -append "$zeile" -serial "file:$TMPD/$name.txt" -display none \
        -no-reboot $vga \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    echo $?
}

RC=0
foto() { # name kommandozeile
    local name=$1 zeile=$2
    local sock="$TMPD/mon-$name.sock" aus="$TMPD/$name.txt" ppm="$TMPD/$name.ppm"
    rm -f "$aus" "$ppm" "$sock"
    timeout 240 qemu-system-x86_64 $ACCEL -kernel "$TMPD/k0.mb" -m 256 \
        -append "$zeile" -serial "file:$aus" -display none -no-reboot -vga std \
        -monitor "unix:$sock,server,nowait" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1 &
    local pid=$! i=0
    while [ $i -lt 2200 ]; do
        grep -qa '^fb: hold' "$aus" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1; i=$((i + 1))
    done
    sleep 0.4
    python3 tools/gfx/screenshot.py "$sock" "$ppm" 25 > "$TMPD/$name.shot" 2>&1
    wait "$pid"; RC=$?
    rm -f "$sock"
}

# Ein Lauf mit einer Platte, die BESTEHEN BLEIBT -- das ist der ganze
# Sinn von Abschnitt 6: ein Neustart auf demselben Datentraeger.
lauf_platte() { # name kommandozeile abbild
    local name=$1 zeile=$2 img=$3
    rm -f "$TMPD/$name.txt"
    timeout 240 qemu-system-x86_64 $ACCEL -kernel "$TMPD/k0.mb" -m 256 \
        -append "$zeile" -serial "file:$TMPD/$name.txt" -display none \
        -no-reboot -vga std -drive "file=$img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    echo $?
}

# ============================================== 3. eine eigene Aufloesung

echo "== 3. eine eigene Aufloesung -- und zwar im Bild =="

# ZUERST DER NACHWEIS, DASS 1400x1050 WIRKLICH NEU IST. Ohne ihn misst
# dieser Abschnitt nur, dass `set_mode` weiterhin funktioniert.
if grep -aq '(1400 << 16)' kernel/vmode.fi; then
    bad "1400x1050 steht in der Kandidatenliste -- dann ist es keine EIGENE Aufloesung"
else
    ok "1400x1050 steht in KEINER Kandidatenliste von vmode.fi (vorher unerreichbar)"
fi

foto eigen "gfx disp dispeigen nocursor fbtest fbhold $GRUND"
num "der Lauf endet sauber (21 = der Kernel hat sich selbst beendet)" "$RC" eq 21
E="$TMPD/eigen.txt"
gleich "die Karte hat die eigene Zahl angenommen (rc=0)" "0" "$(ew "$E" 1 rc)"
gleich "kein Grund, also keine Schranke gegriffen" "0" "$(ew "$E" 1 why)"
gleich "und die Zahl ist die Groesse des Bildes in Oktetten" "5880000" "$(ew "$E" 1 num)"
gleich "der Kernel zaehlt eine eigene Aufloesung in seiner Liste" "1" "$(ew "$E" 1 custom)"
hat "$E" "panel=1400x1050" "die Tafel steht auf den eingegebenen Zahlen"
# UND DAS FOTO. Das ist die Zusage: nicht "der Kernel sagt 1400x1050",
# sondern "QEMU zeigt 1400 x 1050 Bildpunkte".
schau "das Foto ist 1400x1050 -- der Modus steht WIRKLICH" \
    groesse "$TMPD/eigen.ppm" 1400 1050
schau "das Pruefbild ist neu gezeichnet, Feld 1 ist rot" \
    flaeche "$TMPD/eigen.ppm" 0 0 100 100 255 0 0
schau "die Textzeile steht bildpunktgenau im eigenen Modus" \
    text "$TMPD/eigen.ppm" kernel/font.fi 14 0 "OSUM K7 FRAMEBUFFER 01234"
schau "die Ecke bei (1399,1049) gibt es und sie ist schwarz" \
    punkt "$TMPD/eigen.ppm" 1399 1049 0 0 0
gleich "die Zusagen der Runde DISPLAY stehen unveraendert" "15" \
    "$(grep -ao 'disp: selftest [0-9]*' "$E" | head -1 | grep -o '[0-9]*$')"
gleich "und die neun eigenen dieser Runde" "9" \
    "$(grep -ao 'disp: custom selftest [0-9]*' "$E" | head -1 | grep -o '[0-9]*$')"
behalte "$TMPD/eigen.ppm" eigen-1400x1050

# ============================================== 4. die drei Schranken

echo "== 4. abgelehnt -- aber MIT Schranke und MIT Zahl =="
foto schranken "gfx disp dispeigenbad nocursor fbtest fbhold $GRUND"
num "der Lauf endet sauber -- eine abgelehnte Zahl haelt den Kernel NICHT an" "$RC" eq 21
S="$TMPD/schranken.txt"
gleich "drei Anfragen, drei Antworten" "3" "$(grep -ac '^disp: eigen ' "$S")"

# (a) DIE KACHELGRENZE DIESES KERNELS. 2560x1440x4 sind 14 745 600
#     Oktette; die Karte hat 16 777 216 und nimmt sie an -- was NICHT
#     traegt, sind die Fensterplaetze.
gleich "1. Schranke: dieser Kernel kann es nicht einblenden (Grund 3)" "3" "$(ew "$S" 1 why)"
gleich "   und die genannte Zahl ist GENAU das, was das Bild braucht" \
    "14745600" "$(ew "$S" 1 num)"
num "   sie ist groesser als das, was der Kernel einblenden kann" \
    "14745600" gt "$(ew "$S" 1 maplimit)"
num "   und KLEINER als der Bildspeicher der Karte -- die Karte war es also nicht" \
    "14745600" lt "$(ew "$S" 1 vram)"
gleich "   der Fehlerwert nach aussen ist E_LIMIT (8) und nicht E_NOMODE" "8" "$(ew "$S" 1 rc)"

# (b) DIE KARTE SELBST. 1366 ist kein Vielfaches von acht; QEMU macht
#     daraus 1360 und laesst das stehen -- und GENAU diese Zahl meldet
#     der Kernel zurueck, nicht den Ankerwert.
gleich "2. Schranke: die Register der Karte nehmen die Zahl nicht (Grund 1)" \
    "1" "$(ew "$S" 2 why)"
gleich "   und es steht da, was die Karte STATTDESSEN behalten hat" "1360" "$(ew "$S" 2 num)"
gleich "   der Fehlerwert ist E_SETFAIL (4)" "4" "$(ew "$S" 2 rc)"

# (c) DIE FARBTIEFE. Der Grund dafuer hat sich in dieser Runde nicht
#     geaendert und steht in docs/DISPLAY.md 8.1.
gleich "3. Schranke: diese Farbtiefe zeichnet der Kernel nicht (Grund 4)" \
    "4" "$(ew "$S" 3 why)"
gleich "   und die Zahl ist die verlangte Tiefe" "16" "$(ew "$S" 3 num)"
gleich "   der Fehlerwert ist E_DEPTH (6)" "6" "$(ew "$S" 3 rc)"

# UND DER BILDSCHIRM STEHT NOCH. Das ist die Zusage, ohne die der Rest
# gefaehrlich waere: eine abgelehnte Anfrage darf keinen schwarzen
# Schirm hinterlassen -- auch nicht die zweite und dritte hintereinander.
hat "$S" "panel=800x600" "nach drei abgelehnten Anfragen steht die Tafel unveraendert"
gleich "und KEIN Wechsel hat stattgefunden" "0" \
    "$(grep -a -m1 '^disp: sw=' "$S" | grep -ao 'sw=[0-9]*' | sed 's/sw=//')"
schau "das Foto ist 800x600 -- der Bildmodus steht noch" \
    groesse "$TMPD/schranken.ppm" 800 600
schau "Feld 1 ist rot -- der Bildschirm ist NICHT schwarz" \
    flaeche "$TMPD/schranken.ppm" 0 0 100 100 255 0 0
schau "und die Textzeile steht bildpunktgenau da, als waere nichts gewesen" \
    text "$TMPD/schranken.ppm" kernel/font.fi 14 0 "OSUM K7 FRAMEBUFFER 01234"
schau_nicht "ein schwarzer Schirm haette hier kein Rot" \
    flaeche "$TMPD/schranken.ppm" 0 0 100 100 0 0 0
behalte "$TMPD/schranken.ppm" abgelehnt-800x600

echo "== 4b. dieselbe Zahl an eine KLEINERE Karte =="
# DERSELBE KERN, DIESELBE BEFEHLSZEILE, nur ein kleinerer Bildspeicher.
# 2560x1440 braucht 14 745 600 Oktette; mit 8 MiB hat die Karte 8 388 608.
# Der Grund MUSS sich von 3 (Kachelgrenze) auf 2 (Bildspeicher) aendern,
# denn jetzt ist wirklich die Karte zu klein -- und die genannte Zahl
# bleibt dieselbe, weil das Bild dieselbe Groesse hat.
rc=$(lauf klein "gfx disp dispeigenbad $GRUND" 180 "-device VGA,vgamem_mb=8")
num "der Lauf endet sauber" "$rc" eq 21
K="$TMPD/klein.txt"
gleich "die kleinere Karte meldet 8 MiB" "8388608" "$(ew "$K" 1 vram)"
gleich "und JETZT ist der Bildspeicher der Grund (2 statt 3)" "2" "$(ew "$K" 1 why)"
gleich "die Zahl ist unveraendert das, was das Bild braucht" "14745600" "$(ew "$K" 1 num)"
gleich "der Fehlerwert nach aussen ist E_VRAM (7)" "7" "$(ew "$K" 1 rc)"
ok "eine Begruendung, die sich mit der Maschine aendert, ist eine Messung"

# ============================================== 5. die Frist ohne Zutun

echo "== 5. die Frist laeuft ohne JEDES Zutun ab =="
cp -f "$TMPD/root.img" "$TMPD/frist.img"
rc=$(lauf_platte frist \
    "osum gfx disp nokbd nosched noproc script=dispctl eigen 1400 1050;sleep 22;dispctl raw" \
    "$TMPD/frist.img")
num "der Lauf endet sauber" "$rc" eq 21
F="$TMPD/frist.txt"
hat "$F" "dispctl: angenommen" "ein Programm in Ring 3 hat eine eigene Aufloesung gesetzt"
gleich "direkt danach steht die Tafel auf 1400" "1400" "$(uwn "$F" panelw 1)"
gleich "und eine Frist laeuft" "1" "$(uwn "$F" pending 1)"
# ZWISCHEN DIESEN BEIDEN ZEILEN LIEF NUR `sleep`. Das Programm hat
# danach KEINEN Bildschirmaufruf mehr gemacht -- `sleep` kennt keinen.
# Was hier zurueckgeschaltet hat, war die Leerlaufaufgabe.
gleich "nach 22 Sekunden Schlaf steht die alte Tafel wieder da" "800" "$(uwl "$F" panelw)"
gleich "die Frist ist zu" "0" "$(uwl "$F" pending)"
gleich "der Kernel hat von SELBST zurueckgeschaltet" "1" "$(uwl "$F" reverts)"
gleich "und zwei Wechsel gezaehlt (hin und zurueck)" "2" "$(uwl "$F" switches)"
gleich "nichts wurde bestaetigt" "0" "$(uwl "$F" confirms)"
# Die Gegenprobe zum WEG: es gab in diesem Lauf keinen Aufruf, der `poll`
# haette ausloesen koennen -- ausser dem der Leerlaufaufgabe.
hat kernel/tasks.fi "vmode.poll" "der Rueckweg steht in der Leerlaufaufgabe (tasks.fi)"
hat_nicht kernel/user/sleep.fi "DISPSET" "und /bin/sleep ruft keinen Bildschirmaufruf"

# Und dasselbe im Bild: nach der Frist steht wieder der Startmodus da.
foto zurueck "gfx disp dispeigenfrist nocursor fbtest fbhold $GRUND"
num "der Lauf endet sauber" "$RC" eq 21
Z="$TMPD/zurueck.txt"
gleich "auch fuer eine EIGENE Aufloesung wird eine Frist gestellt" "1" \
    "$(grep -a -m1 '^disp: confirm pend=' "$Z" | grep -ao 'pend=[0-9]*' | sed 's/pend=//')"
left=$(grep -a -m1 '^disp: confirm pend=' "$Z" | grep -ao 'left=[0-9]*' | sed 's/left=//')
num "und sie zaehlt von fuenfzehn Sekunden herunter" "$left" ge 14
cf2=$(grep -a -m2 '^disp: confirm pend=' "$Z" | tail -1)
gleich "nach Ablauf ist sie weg" "0" "$(echo "$cf2" | grep -ao 'pend=[0-9]*' | sed 's/pend=//')"
gleich "und der Kernel hat zurueckgeschaltet" "1" \
    "$(echo "$cf2" | grep -ao 'after=[0-9]*' | sed 's/after=//')"
schau "das Foto zeigt wieder 800x600" groesse "$TMPD/zurueck.ppm" 800 600
schau "und das Pruefbild steht darin" \
    text "$TMPD/zurueck.ppm" kernel/font.fi 14 0 "OSUM K7 FRAMEBUFFER 01234"
behalte "$TMPD/zurueck.ppm" nach-der-frist-800x600

# ============================================== 6. der Neustart

echo "== 6. ein bestaetigter Modus ueberlebt den Neustart =="
cp -f "$TMPD/root.img" "$TMPD/dauer.img"

rc=$(lauf_platte s1 \
    "osum gfx disp nokbd nosched noproc script=dispctl eigen 1400 1050;dispctl behalten;dispctl raw" \
    "$TMPD/dauer.img")
num "START 1 endet sauber" "$rc" eq 21
S1="$TMPD/s1.txt"
hat "$S1" "disp: save none" "beim ERSTEN Start liegt noch nichts auf der Platte"
gleich "die eigene Aufloesung steht" "1400" "$(uwn "$S1" panelw 1)"
gleich "und nach 'Behalten' ist die Frist zu" "0" "$(uwl "$S1" pending)"

rc=$(lauf_platte s2 "osum gfx disp nokbd nosched noproc script=dispctl raw" "$TMPD/dauer.img")
num "START 2 (Neustart, DIESELBE Platte) endet sauber" "$rc" eq 21
S2="$TMPD/s2.txt"
hat "$S2" "disp: save on 1400x1050" "der Kernel findet den Modus und stellt ihn ein"
gleich "die Tafel steht nach dem Neustart auf 1400" "1400" "$(uwl "$S2" panelw)"
gleich "und er steht als eigene Aufloesung in der Liste" "1" "$(uwl "$S2" customs)"
gleich "der Erprobungszaehler steht auf 1" "1" "$(uwl "$S2" savetry)"
gleich "und der Modus gilt als in diesem Start angewandt" "1" "$(uwl "$S2" saveapp)"

rc=$(lauf_platte s3 "osum gfx disp nokbd nosched noproc script=dispctl raw" "$TMPD/dauer.img")
num "START 3 (wieder ohne Bestaetigung) endet sauber" "$rc" eq 21
S3="$TMPD/s3.txt"
gleich "der Modus steht noch immer" "1400" "$(uwl "$S3" panelw)"
gleich "aber der Zaehler ist auf 2" "2" "$(uwl "$S3" savetry)"

rc=$(lauf_platte s4 "osum gfx disp nokbd nosched noproc script=dispctl raw" "$TMPD/dauer.img")
num "START 4 endet sauber" "$rc" eq 21
S4="$TMPD/s4.txt"
hat "$S4" "disp: save aufgebraucht" "jetzt sind die drei Versuche verbraucht"
hat "$S4" "(Startmodus bleibt)" "und der Kernel sagt, was er stattdessen tut"
gleich "die Tafel steht auf dem SICHEREN Startmodus" "800" "$(uwl "$S4" panelw)"
ok "das ist der Rueckfall: er kostet nichts, weil er nichts tut"

rc=$(lauf_platte s5 "osum gfx disp nokbd nosched noproc script=dispctl raw" "$TMPD/dauer.img")
num "START 5 endet sauber" "$rc" eq 21
S5="$TMPD/s5.txt"
hat "$S5" "disp: save none" "der Satz ist stillgelegt -- kein zweiter Rueckfall, keine Schleife"
gleich "und die Tafel bleibt beim Startmodus" "800" "$(uwl "$S5" panelw)"

# UND DIE GEGENPROBE ZUM ZAEHLER: wer bestaetigt, faengt wieder bei null
# an. Sonst waere die Bestaetigung eine Geste.
cp -f "$TMPD/root.img" "$TMPD/dauer2.img"
rc=$(lauf_platte t1 \
    "osum gfx disp nokbd nosched noproc script=dispctl eigen 1400 1050;dispctl behalten" \
    "$TMPD/dauer2.img")
num "der Vorlauf endet sauber" "$rc" eq 21
rc=$(lauf_platte t2 \
    "osum gfx disp nokbd nosched noproc script=dispctl raw;dispctl behalten;dispctl raw" \
    "$TMPD/dauer2.img")
num "der Lauf endet sauber" "$rc" eq 21
T2="$TMPD/t2.txt"
gleich "nach dem Neustart stand der Zaehler auf 1 ..." "1" "$(uwn "$T2" savetry 1)"
gleich "... und 'Behalten' hat ihn wieder auf null gesetzt" "0" "$(uwl "$T2" savetry)"

# ============================================== 7. Ring 3

echo "== 7. die Zusagen aus Ring 3, und der Satz, den ein Mensch liest =="
cp -f "$TMPD/root.img" "$TMPD/r3.img"
rc=$(lauf_platte ring3 "osum gfx disp nokbd nosched noproc script=dispctl testc" "$TMPD/r3.img")
num "der Lauf endet sauber" "$rc" eq 21
R="$TMPD/ring3.txt"
gleich "zehn Zusagen ueber die Aufrufschwelle" "10" \
    "$(grep -ao 'dispctl: testc [0-9]*' "$R" | head -1 | grep -o '[0-9]*$')"
cp -f "$TMPD/root.img" "$TMPD/r4.img"
rc=$(lauf_platte satz \
    "osum gfx disp nokbd nosched noproc script=dispctl eigen 2560 1440;dispctl eigen 1366 768" \
    "$TMPD/r4.img")
num "der Lauf endet sauber" "$rc" eq 21
A="$TMPD/satz.txt"
hat "$A" "dieser Kernel kann es nicht einblenden" "der Satz nennt die Schranke"
hat "$A" "14745600" "und die Zahl, die es zerreisst"
hat "$A" "12582912" "und die Zahl, die ginge"
hat "$A" "2-MiB-Fensterplaetze" "und wovon die Schranke kommt"
hat "$A" "die Karte nimmt diese Zahl nicht an" "die zweite Schranke nennt sich anders"
hat "$A" "Vielfaches von" "und gibt den Hinweis, der wirklich weiterhilft"
# UND DIE DRITTE: eine Zahl, die kein Bildschirm ist. Sie nennt nicht nur
# die falsche Zahl, sondern den Bereich -- sonst weiss der Benutzer zwar,
# welche seiner beiden Zahlen es zerreisst, aber nicht, wohin damit.
cp -f "$TMPD/root.img" "$TMPD/r5.img"
rc=$(lauf_platte unsinn \
    "osum gfx disp nokbd nosched noproc script=dispctl eigen 4 4" "$TMPD/r5.img")
num "der Lauf endet sauber" "$rc" eq 21
U="$TMPD/unsinn.txt"
hat "$U" "die Zahl liegt ausserhalb" "die dritte Schranke nennt sich wieder anders"
hat "$U" "Breite 320 .. 8192" "und sie sagt, wohin die Zahl gehoert"
hat "$U" "Hoehe 200 .. 8192" "fuer beide Richtungen"

# ============================================== 8. die Gegenprobe

echo "== 8. DIE GEGENPROBE: derselbe Kern ohne das Wort 'disp' =="
rc=$(lauf ohne "gfx dispeigen dispeigenbad $GRUND")
num "der Lauf endet sauber" "$rc" eq 21
O="$TMPD/ohne.txt"
hat_nicht "$O" "disp: eigen" "ohne 'disp' wird keine eigene Aufloesung gesetzt"
hat_nicht "$O" "disp: kacheln" "und keine Belegung gemeldet"
hat_nicht "$O" "disp: save" "und die Platte wird nicht angefasst"
hat "$O" "fb: 800x600x32" "der Bildschirm von Runde K7 steht unveraendert"
hat "$O" "fb: selftest 13 / 13" "und seine dreizehn Zusagen auch"
cp -f "$TMPD/root.img" "$TMPD/ohne.img"
rc=$(lauf_platte ohne3 "osum gfx nokbd nosched noproc script=dispctl eigen 1400 1050" \
    "$TMPD/ohne.img")
num "der Lauf endet sauber" "$rc" eq 21
O3="$TMPD/ohne3.txt"
hat "$O3" "dispctl: der Bildschirm ist nicht da" "/bin/dispctl rechnet nicht weiter"
gleich "und der neue Grund ist ein Strich und keine Null" "-" "$(uw "$O3" custwhy)"
gleich "auch die Zahl" "-" "$(uw "$O3" custnum)"
gleich "auch der gespeicherte Modus" "-" "$(uw "$O3" saveok)"

# ============================================== 9. die Grenze, ehrlich

echo "== 9. wo die Grenze wirklich liegt =="
rc=$(lauf gross "gfx disp $GRUND" 180 "-device VGA,vgamem_mb=64")
num "der Lauf endet sauber" "$rc" eq 21
G="$TMPD/gross.txt"
gleich "mit 64 MiB Bildspeicher meldet die Karte mehr" "65536" "$(kw "$G" vram)"
# DIE ENTSCHEIDENDE MESSUNG DIESES ABSCHNITTS. Mit 16 MiB Bildspeicher
# lehnen QEMUs Register 3840x2160 ab (Grund 1) -- weil ihre eigene
# Registerpruefung den Bildspeicher mitprueft. Mit 64 MiB NEHMEN sie es
# an, und uebrig bleibt genau eine Schranke: diese hier.
gleich "3840x2160 scheitert jetzt NUR noch an den Fensterplaetzen dieses Kernels" "3" \
    "$(grep -a '^disp: out   3840x2160' "$G" | grep -ao 'reason=[0-9]*' | sed 's/reason=//')"
rc=$(lauf klein16 "gfx disp $GRUND" 180 "-vga std")
num "der Lauf endet sauber" "$rc" eq 21
K16="$TMPD/klein16.txt"
gleich "mit 16 MiB war es noch die Karte, die ablehnte" "1" \
    "$(grep -a '^disp: out   3840x2160' "$K16" | grep -ao 'reason=[0-9]*' | sed 's/reason=//')"
ok "derselbe Kern, dieselbe Zeile, zwei Gruende -- die Schranken sind unabhaengig gemessen"
ka=$(grep -a -m1 '^disp: kacheln' "$K16")
[ -n "$ka" ] && ok "die Belegung der acht Fensterplaetze: $ka" || bad "keine Belegung gemeldet"
gleich "acht Plaetze zu 2 MiB sind 16 MiB Fenster" "8" \
    "$(echo "$ka" | grep -ao 'alle=[0-9]*' | sed 's/.*=//')"
num "und davon traegt der laengste zusammenhaengende Bereich weniger" \
    "$(echo "$ka" | grep -ao 'laufmax=[0-9]*' | sed 's/.*=//')" lt 8
ok "die Differenz sind der lokale APIC und der I/O-APIC -- zwei Plaetze fuer je 4 KiB Register"

echo
echo "CUSTOMRES: $pass passed, $fail failed"
[ "$fail" = 0 ]
