#!/usr/bin/env bash
#
# Verwendung:  bash tools/customres/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/brand.sh
marke_laden . || exit 1
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
. tools/lib/firnenv.sh
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
    if [ -z "${2:-}" ]; then bad "$1: no number found (expected $3 $4)"; return; fi
    if [ "$2" -"$3" "$4" ] 2>/dev/null; then ok "$1: $2"
    else bad "$1: $2, erwartet $3 $4"; fi
}
gleich() { if [ "$2" = "$3" ]; then ok "$1 ($3)"; else bad "$1 -- soll '$2', ist '$3'"; fi; }
hat() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hat_nicht() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da und sollte nicht" || ok "$3"; }

ew() { # datei nummer name
    grep -a '^disp: own ' "$1" 2>/dev/null | sed -n "$2p" \
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
    if [ "$rc" -ne 0 ]; then ok "$name ($aus)"; else bad "$name -- passed: $aus"; fi; }

behalte() { # ppm zielname
    mkdir -p "$SHOTS"
    python3 tools/gfx/ppm2png.py "$1" "$SHOTS/$2.png" > /dev/null 2>&1 \
        || cp -f "$1" "$SHOTS/$2.ppm"
}

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "CUSTOMRES: skipped, qemu-system-x86_64 is not there"; exit 0
fi
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL
#
ACCEL="${QEMU_X86#qemu-system-x86_64 }"

echo "== 1. the sources: two files, one legend =="

for r in CW_OK CW_REGS CW_VRAM CW_LIMIT CW_DEPTH CW_UNSINN CW_NOCARD; do
    a=$(grep -aE "^const $r: u64 = " kernel/gfx/vmode.fi | sed 's/.*= //; s/ *\/\/.*//')
    b=$(grep -aE "^const $r: u64 = " kernel/user/dispctl.fi | sed 's/.*= //; s/ *\/\/.*//')
    if [ -n "$a" ] && [ "$a" = "$b" ]; then ok "$r is the same in the kernel and in ring 3 ($a)"
    else bad "$r: vmode.fi='$a', dispctl.fi='$b'"; fi
done
gleich "Grund 1 heisst hier wie dort 'die Register haben abgelehnt'" "1" \
    "$(grep -aE '^const CW_REGS' kernel/gfx/vmode.fi | sed 's/.*= //')"
gleich "Grund 2 heisst hier wie dort 'zu gross fuer den Bildspeicher'" "2" \
    "$(grep -aE '^const CW_VRAM' kernel/gfx/vmode.fi | sed 's/.*= //')"
gleich "Grund 3 heisst hier wie dort 'dieser Kernel kann es nicht abbilden'" "3" \
    "$(grep -aE '^const CW_LIMIT' kernel/gfx/vmode.fi | sed 's/.*= //')"

eigen=$(grep -ahE '^const SYS_[A-Za-z0-9_]+: u64 = 181[0-9]' kernel/sys/sys.fi | wc -l | tr -d ' ')
gleich "diese Runde braucht keine neue Aufrufnummer (weiter genau drei)" "3" "$eigen"

sl=$(grep -aE '^const LEN: u64 = ' kernel/gfx/dispsave.fi | sed 's/.*= //')
must=$(python3 - <<'PY'
import re, io
s = io.open("kernel/gfx/dispsave.fi", encoding="utf-8").read()
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
if [ "$sl" -lt 512 ]; then ok "and it fits in ONE data block ($sl < 512)"
else bad "the sentence is longer than a data block: $sl"; fi

if python3 tools/kernel/memmap.py kernel > "$TMPD/karte.txt" 2>&1; then
    ok "the kdata memory map: $(tail -1 "$TMPD/karte.txt")"
else
    bad "tools/kernel/memmap.py meldet Kollisionen"; sed 's/^/        /' "$TMPD/karte.txt" | head -8
fi

echo "== 2. bauen =="
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || { echo "as scheitert"; exit 1; }
rc=0
bash tools/build-kernel.sh "$TMPD/k0.mb" > "$TMPD/k0.log" 2>&1 || {
    bad "the kernel cannot be built"; tail -8 "$TMPD/k0.log" | sed 's/^/        /'; rc=1; }
for p in $PROGS; do
    "$FIRNC" "kernel/user/$p.fi" -o "$TMPD/$p.o" > "$TMPD/$p.err" 2>&1 || {
        bad "firnc uebersetzt $p.fi nicht"; head -6 "$TMPD/$p.err"; rc=1; continue; }
    ld -T "$ULD" --defsym=USER_ENTRY=_F0.u_start -o "$TMPD/$p.elf" \
        "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null || { bad "ld scheitert an $p"; rc=1; continue; }
    strip --strip-all "$TMPD/$p.elf"
done
[ "$rc" = 0 ] && ok "the kernel and $(echo $PROGS | wc -w) programs are built"
[ -f "$TMPD/k0.mb" ] || { echo "CUSTOMRES: nothing goes on without the kernel"; exit 1; }

UPROF=""; UCRT="$TMPD/crt.o"
grep -qa '^profile app' kernel/user/settings.fi && { UPROF=--profile=app; UCRT=""; }
if "$FIRNC" $UPROF -c kernel/user/settings.fi -o "$TMPD/eins.o" > "$TMPD/eins.err" 2>&1 \
    && ld -T "$ULD" --defsym=USER_ENTRY=_F0.u_start -o "$TMPD/eins.elf" \
        $UCRT "$TMPD/eins.o" 2>/dev/null; then
    u=$(nm -u "$TMPD/eins.elf" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
    [ -z "$u" ] && ok "the control panel with the three input fields builds cleanly" \
                || bad "settings.elf hat undefinierte Symbole: $u"
else
    bad "settings.fi cannot be built"; head -8 "$TMPD/eins.err" | sed 's/^/        /'
fi
hat <(bash tools/structure/catprog.sh kernel/user/settings.fi) "DS_CUSTOM" \
    "das Bedienfeld ruft wirklich den neuen Aufruf und baut keine Liste nach"
hat <(bash tools/structure/catprog.sh kernel/user/settings.fi) "DG_CUSTNUM" \
    "und es holt die ZAHL aus dem Kern, statt eine eigene zu rechnen"

if bash tools/build-kernel.sh "$TMPD/k1.mb" --stufe 1 > "$TMPD/k1.log" 2>&1; then
    ok "firnc1 builds this round too (the compiler in Firn)"
else
    bad "firnc1 does not build this round"; tail -5 "$TMPD/k1.log" | sed 's/^/        /'
fi

MKARGS=""
for p in $PROGS; do MKARGS="$MKARGS /bin/$p=$TMPD/$p.elf"; done
bash tools/mkfsfi/mkfs.sh build "$TMPD/root.img" "$BLOCKS" /bin/ $MKARGS \
    > "$TMPD/mkfs.log" 2>&1 && ok "the disk is ready: $(tail -1 "$TMPD/mkfs.log")" \
    || bad "mkfs.py scheitert"

GRUND="nokbd nosched noproc nofs noring3"

VGA_STD=${VGA_STD:-"-vga std -global VGA.edid=off"}

lauf() { # name kommandozeile [zeitlimit] [vga-argumente]
    local name=$1 zeile=$2 t=${3:-180} vga=${4:-$VGA_STD}
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
        -append "$zeile" -serial "file:$aus" -display none -no-reboot $VGA_STD \
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

lauf_platte() { # name kommandozeile abbild
    local name=$1 zeile=$2 img=$3
    rm -f "$TMPD/$name.txt"
    timeout 240 qemu-system-x86_64 $ACCEL -kernel "$TMPD/k0.mb" -m 256 \
        -append "$zeile" -serial "file:$TMPD/$name.txt" -display none \
        -no-reboot $VGA_STD -drive "file=$img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    echo $?
}

# ============================================== 3. eine eigene Aufloesung

echo "== 3. a custom resolution -- in the picture =="

if grep -aq '(1400 << 16)' kernel/gfx/vmode.fi; then
    bad "1400x1050 is in the candidate list -- then it is not a CUSTOM resolution"
else
    ok "1400x1050 is in NO candidate list of vmode.fi (unreachable before)"
fi

foto eigen "gfx disp dispeigen nocursor fbtest fbhold $GRUND"
num "der Lauf endet sauber (21 = der Kernel hat sich selbst beendet)" "$RC" eq 21
E="$TMPD/eigen.txt"
gleich "die Karte hat die eigene Zahl angenommen (rc=0)" "0" "$(ew "$E" 1 rc)"
gleich "kein Grund, also keine Schranke gegriffen" "0" "$(ew "$E" 1 why)"
gleich "und die Zahl ist die Groesse des Bildes in Oktetten" "5880000" "$(ew "$E" 1 num)"
gleich "der Kernel zaehlt eine eigene Aufloesung in seiner Liste" "1" "$(ew "$E" 1 custom)"
hat "$E" "panel=1400x1050" "die Tafel steht auf den eingegebenen Zahlen"
schau "das Foto ist 1400x1050 -- der Modus steht WIRKLICH" \
    size "$TMPD/eigen.ppm" 1400 1050
schau "das Pruefbild ist neu gezeichnet, Feld 1 ist rot" \
    area "$TMPD/eigen.ppm" 0 0 100 100 255 0 0
schau "die Textzeile steht bildpunktgenau im eigenen Modus" \
    text "$TMPD/eigen.ppm" kernel/gfx/font.fi 14 0 "$MARKE_PRODUKT K7 FRAMEBUFFER 01234"
schau "die Ecke bei (1399,1049) gibt es und sie ist schwarz" \
    pixel "$TMPD/eigen.ppm" 1399 1049 0 0 0
gleich "die Zusagen der Runde DISPLAY stehen unveraendert" "15" \
    "$(grep -ao 'disp: selftest [0-9]*' "$E" | head -1 | grep -o '[0-9]*$')"
gleich "und die neun eigenen dieser Runde" "9" \
    "$(grep -ao 'disp: custom selftest [0-9]*' "$E" | head -1 | grep -o '[0-9]*$')"
behalte "$TMPD/eigen.ppm" eigen-1400x1050

echo "== 4. rejected -- but WITH a limit and WITH a number =="
VGA_STD="-device VGA,edid=off,vgamem_mb=64" \
    foto schranken "gfx disp dispeigenbad nocursor fbtest fbhold $GRUND"
num "der Lauf endet sauber -- eine abgelehnte Zahl haelt den Kernel NICHT an" "$RC" eq 21
S="$TMPD/schranken.txt"
gleich "drei Anfragen, drei Antworten" "3" "$(grep -ac '^disp: own ' "$S")"

gleich "1. Schranke: dieser Kernel kann es nicht einblenden (Grund 3)" "3" "$(ew "$S" 1 why)"
gleich "   und die genannte Zahl ist GENAU das, was das Bild braucht" \
    "33177600" "$(ew "$S" 1 num)"
num "   sie ist groesser als das, was der Kernel einblenden kann" \
    "33177600" gt "$(ew "$S" 1 maplimit)"
num "   und KLEINER als der Bildspeicher der Karte -- die Karte war es also nicht" \
    "33177600" lt "$(ew "$S" 1 vram)"
gleich "   der Fehlerwert nach aussen ist E_LIMIT (8) und nicht E_NOMODE" "8" "$(ew "$S" 1 rc)"

gleich "2. Schranke: die Register der Karte nehmen die Zahl nicht (Grund 1)" \
    "1" "$(ew "$S" 2 why)"
gleich "   und es steht da, was die Karte STATTDESSEN behalten hat" "1360" "$(ew "$S" 2 num)"
gleich "   der Fehlerwert ist E_SETFAIL (4)" "4" "$(ew "$S" 2 rc)"

gleich "3. Schranke: diese Farbtiefe zeichnet der Kernel nicht (Grund 4)" \
    "4" "$(ew "$S" 3 why)"
gleich "   und die Zahl ist die verlangte Tiefe" "16" "$(ew "$S" 3 num)"
gleich "   der Fehlerwert ist E_DEPTH (6)" "6" "$(ew "$S" 3 rc)"

hat "$S" "panel=800x600" "nach drei abgelehnten Anfragen steht die Tafel unveraendert"
gleich "und KEIN Wechsel hat stattgefunden" "0" \
    "$(grep -a -m1 '^disp: sw=' "$S" | grep -ao 'sw=[0-9]*' | sed 's/sw=//')"
schau "das Foto ist 800x600 -- der Bildmodus steht noch" \
    size "$TMPD/schranken.ppm" 800 600
schau "Feld 1 ist rot -- der Bildschirm ist NICHT schwarz" \
    area "$TMPD/schranken.ppm" 0 0 100 100 255 0 0
schau "und die Textzeile steht bildpunktgenau da, als waere nichts gewesen" \
    text "$TMPD/schranken.ppm" kernel/gfx/font.fi 14 0 "$MARKE_PRODUKT K7 FRAMEBUFFER 01234"
schau_nicht "ein schwarzer Schirm haette hier kein Rot" \
    area "$TMPD/schranken.ppm" 0 0 100 100 0 0 0
behalte "$TMPD/schranken.ppm" abgelehnt-800x600

echo "== 4b. the same number on a SMALLER card =="
rc=$(lauf klein "gfx disp dispeigenbad $GRUND" 180 "-device VGA,edid=off,vgamem_mb=8")
num "der Lauf endet sauber" "$rc" eq 21
K="$TMPD/klein.txt"
gleich "die kleinere Karte meldet 8 MiB" "8388608" "$(ew "$K" 1 vram)"
gleich "und JETZT ist der Bildspeicher der Grund (2 statt 3)" "2" "$(ew "$K" 1 why)"
gleich "die Zahl ist unveraendert das, was das Bild braucht" "33177600" "$(ew "$K" 1 num)"
gleich "der Fehlerwert nach aussen ist E_VRAM (7)" "7" "$(ew "$K" 1 rc)"
ok "a reason that changes with the machine is a measurement"

echo "== 5. the deadline expires without ANY action =="
cp -f "$TMPD/root.img" "$TMPD/frist.img"
rc=$(lauf_platte frist \
    "osum gfx disp nokbd nosched noproc script=dispctl custom 1400 1050;sleep 22;dispctl raw" \
    "$TMPD/frist.img")
num "der Lauf endet sauber" "$rc" eq 21
F="$TMPD/frist.txt"
hat "$F" "dispctl: accepted" "ein Programm in Ring 3 hat eine eigene Aufloesung gesetzt"
gleich "direkt danach steht die Tafel auf 1400" "1400" "$(uwn "$F" panelw 1)"
gleich "und eine Frist laeuft" "1" "$(uwn "$F" pending 1)"
gleich "nach 22 Sekunden Schlaf steht die alte Tafel wieder da" "800" "$(uwl "$F" panelw)"
gleich "die Frist ist zu" "0" "$(uwl "$F" pending)"
gleich "der Kernel hat von SELBST zurueckgeschaltet" "1" "$(uwl "$F" reverts)"
gleich "und zwei Wechsel gezaehlt (hin und zurueck)" "2" "$(uwl "$F" switches)"
gleich "nichts wurde bestaetigt" "0" "$(uwl "$F" confirms)"
hat kernel/tasks.fi "gfx.disp_poll" "the way back is polled in the idle task (tasks.fi -> gfx.disp_poll -> vmode.poll)"
hat kernel/gfx/gfx.fi "vmode.poll(state)" "and gfx.disp_poll calls vmode.poll"
hat_nicht kernel/user/sleep.fi "DISPSET" "und /bin/sleep ruft keinen Bildschirmaufruf"

echo "== 5b. English command names reach the same code =="
cp -f "$TMPD/root.img" "$TMPD/back.img"
rc=$(lauf_platte back \
    "osum gfx disp nokbd nosched noproc script=dispctl custom 1400 1050;dispctl back;dispctl raw" \
    "$TMPD/back.img")
num "the 'back' run ends cleanly" "$rc" eq 21
gleich "'dispctl back' returns to the old panel" "800" "$(uwl "$TMPD/back.txt" panelw)"
gleich "'dispctl back' counts one revert" "1" "$(uwl "$TMPD/back.txt" reverts)"
cp -f "$TMPD/root.img" "$TMPD/light.img"
rc=$(lauf_platte light \
    "osum gfx disp nokbd nosched noproc script=dispctl light 70;dispctl raw" \
    "$TMPD/light.img")
num "the 'light' run ends cleanly" "$rc" eq 21
gleich "'dispctl light 70' sets brightness 70" "70" "$(uwl "$TMPD/light.txt" bright)"

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
schau "das Foto zeigt wieder 800x600" size "$TMPD/zurueck.ppm" 800 600
schau "und das Pruefbild steht darin" \
    text "$TMPD/zurueck.ppm" kernel/gfx/font.fi 14 0 "$MARKE_PRODUKT K7 FRAMEBUFFER 01234"
behalte "$TMPD/zurueck.ppm" nach-der-frist-800x600

# ============================================== 6. der Neustart

echo "== 6. a confirmed mode survives the restart =="
cp -f "$TMPD/root.img" "$TMPD/dauer.img"

rc=$(lauf_platte s1 \
    "osum gfx disp nokbd nosched noproc script=dispctl custom 1400 1050;dispctl keep;dispctl raw" \
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
ok "that is the fallback: it costs nothing because it does nothing"

rc=$(lauf_platte s5 "osum gfx disp nokbd nosched noproc script=dispctl raw" "$TMPD/dauer.img")
num "START 5 endet sauber" "$rc" eq 21
S5="$TMPD/s5.txt"
hat "$S5" "disp: save none" "der Satz ist stillgelegt -- kein zweiter Rueckfall, keine Schleife"
gleich "und die Tafel bleibt beim Startmodus" "800" "$(uwl "$S5" panelw)"

cp -f "$TMPD/root.img" "$TMPD/dauer2.img"
rc=$(lauf_platte t1 \
    "osum gfx disp nokbd nosched noproc script=dispctl custom 1400 1050;dispctl keep" \
    "$TMPD/dauer2.img")
num "der Vorlauf endet sauber" "$rc" eq 21
rc=$(lauf_platte t2 \
    "osum gfx disp nokbd nosched noproc script=dispctl raw;dispctl keep;dispctl raw" \
    "$TMPD/dauer2.img")
num "der Lauf endet sauber" "$rc" eq 21
T2="$TMPD/t2.txt"
gleich "nach dem Neustart stand der Zaehler auf 1 ..." "1" "$(uwn "$T2" savetry 1)"
gleich "... und 'Behalten' hat ihn wieder auf null gesetzt" "0" "$(uwl "$T2" savetry)"

# ============================================== 7. Ring 3

echo "== 7. the promises from ring 3, and the sentence a human reads =="
cp -f "$TMPD/root.img" "$TMPD/r3.img"
rc=$(lauf_platte ring3 "osum gfx disp nokbd nosched noproc script=dispctl testc" "$TMPD/r3.img")
num "der Lauf endet sauber" "$rc" eq 21
R="$TMPD/ring3.txt"
gleich "zehn Zusagen ueber die Aufrufschwelle" "10" \
    "$(grep -ao 'dispctl: testc [0-9]*' "$R" | head -1 | grep -o '[0-9]*$')"
cp -f "$TMPD/root.img" "$TMPD/r4.img"
rc=$(VGA_STD="-device VGA,edid=off,vgamem_mb=64" lauf_platte satz \
    "osum gfx disp nokbd nosched noproc script=dispctl custom 3840 2160;dispctl custom 1366 768" \
    "$TMPD/r4.img")
num "der Lauf endet sauber" "$rc" eq 21
A="$TMPD/satz.txt"
hat "$A" "this kernel cannot show it" "der Satz nennt die Schranke"
hat "$A" "33177600" "und die Zahl, die es zerreisst"
hat "$A" "29360128" "und die Zahl, die ginge"
hat "$A" "2-MiB window slots" "und wovon die Schranke kommt"
hat "$A" "the card does not accept this number" "die zweite Schranke nennt sich anders"
hat "$A" "multiple of" "und gibt den Hinweis, der wirklich weiterhilft"
cp -f "$TMPD/root.img" "$TMPD/r5.img"
rc=$(lauf_platte unsinn \
    "osum gfx disp nokbd nosched noproc script=dispctl custom 4 4" "$TMPD/r5.img")
num "der Lauf endet sauber" "$rc" eq 21
U="$TMPD/unsinn.txt"
hat "$U" "the number is out of range" "die dritte Schranke nennt sich wieder anders"
hat "$U" "width 320 .. 8192" "und sie sagt, wohin die Zahl gehoert"
hat "$U" "height 200 .. 8192" "fuer beide Richtungen"

# ============================================== 8. die Gegenprobe

echo "== 8. THE NEGATIVE TEST: the same kernel without the word 'disp' =="
rc=$(lauf ohne "gfx dispeigen dispeigenbad $GRUND")
num "der Lauf endet sauber" "$rc" eq 21
O="$TMPD/ohne.txt"
hat_nicht "$O" "disp: own" "ohne 'disp' wird keine eigene Aufloesung gesetzt"
hat_nicht "$O" "disp: tiles" "und keine Belegung gemeldet"
hat_nicht "$O" "disp: save" "und die Platte wird nicht angefasst"
hat "$O" "fb: 800x600x32" "der Bildschirm von Runde K7 steht unveraendert"
hat "$O" "fb: selftest 13 / 13" "und seine dreizehn Zusagen auch"
cp -f "$TMPD/root.img" "$TMPD/ohne.img"
rc=$(lauf_platte ohne3 "osum gfx nokbd nosched noproc script=dispctl custom 1400 1050" \
    "$TMPD/ohne.img")
num "der Lauf endet sauber" "$rc" eq 21
O3="$TMPD/ohne3.txt"
hat "$O3" "dispctl: there is no screen" "/bin/dispctl rechnet nicht weiter"
gleich "und der neue Grund ist ein Strich und keine Null" "-" "$(uw "$O3" custwhy)"
gleich "auch die Zahl" "-" "$(uw "$O3" custnum)"
gleich "auch der gespeicherte Modus" "-" "$(uw "$O3" saveok)"

echo "== 9. where the limit really lies =="
rc=$(lauf gross "gfx disp $GRUND" 180 "-device VGA,edid=off,vgamem_mb=64")
num "der Lauf endet sauber" "$rc" eq 21
G="$TMPD/gross.txt"
gleich "mit 64 MiB Bildspeicher meldet die Karte mehr" "65536" "$(kw "$G" vram)"
gleich "3840x2160 scheitert jetzt NUR noch an den Fensterplaetzen dieses Kernels" "3" \
    "$(grep -a '^disp: out   3840x2160' "$G" | grep -ao 'reason=[0-9]*' | sed 's/reason=//')"
rc=$(lauf klein16 "gfx disp $GRUND" 180 "$VGA_STD")
num "der Lauf endet sauber" "$rc" eq 21
K16="$TMPD/klein16.txt"
gleich "mit 16 MiB war es noch die Karte, die ablehnte" "1" \
    "$(grep -a '^disp: out   3840x2160' "$K16" | grep -ao 'reason=[0-9]*' | sed 's/reason=//')"
ok "the same kernel, the same line, two reasons -- the limits are measured independently"
ka=$(grep -a -m1 '^disp: tiles' "$K16")
[ -n "$ka" ] && ok "the allocation of the window slots: $ka" || bad "keine Belegung gemeldet"
gleich "sechzehn Plaetze zu 2 MiB sind 32 MiB Fenster" "16" \
    "$(echo "$ka" | grep -ao 'all=[0-9]*' | sed 's/.*=//')"
num "und davon traegt der laengste zusammenhaengende Bereich weniger" \
    "$(echo "$ka" | grep -ao 'laufmax=[0-9]*' | sed 's/.*=//')" lt 16
ok "the difference is the local APIC and the I/O-APIC -- two slots of 4 KiB registers each"

echo
echo "CUSTOMRES: $pass passed, $fail failed"
[ "$fail" = 0 ]
