#!/usr/bin/env bash
#
# Verwendung:  bash tools/display/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/marke.sh
marke_laden . || exit 1
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
FC1=${FIRNC1:-vendor/firn/bin/firnc1}
ULD=kernel/user/user.ld
BLOCKS=4096
PROGS="sh echo cat ls dispctl"

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

kw() { grep -ao "^disp:.*[ =]$2=[0-9a-fx]*" "$1" 2>/dev/null | head -1 \
       | grep -ao "$2=[0-9a-fx]*" | head -1 | sed 's/.*=//' | tr -d '\r\000'; }
uw()  { grep -a -m1 "^dispctl: $2=" "$1" 2>/dev/null | sed 's/^[^=]*=//' | tr -d '\r\000'; }
uwl() { grep -a "^dispctl: $2=" "$1" 2>/dev/null | tail -1 | sed 's/^[^=]*=//' | tr -d '\r\000'; }

schau() { local name=$1; shift; local aus rc
    aus=$(python3 tools/gfx/checkshot.py "$@" 2>&1); rc=$?
    if [ "$rc" -eq 0 ]; then ok "$name ($aus)"; else bad "$name -- $aus"; fi; }
schau_nicht() { local name=$1; shift; local aus rc
    aus=$(python3 tools/gfx/checkshot.py "$@" 2>&1); rc=$?
    if [ "$rc" -ne 0 ]; then ok "$name ($aus)"; else bad "$name -- ging durch: $aus"; fi; }

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "vendor/firn/fetch-firnc.sh fehlgeschlagen"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "DISPLAY: skipped, qemu-system-x86_64 ist nicht da"; exit 0
fi

# ============================================== 1. die Quellen

echo "== 1. die Quellen: zwei Dateien, eine Wahrheit =="

for r in VBE_INDEX VBE_DATA VBE_ID VBE_XRES VBE_YRES VBE_BPP VBE_ENABLE \
         VBE_BANK VBE_VWIDTH VBE_VHEIGHT VBE_XOFF VBE_YOFF \
         VBE_DISABLED VBE_ENABLED VBE_LFB VBE_ID_LO VBE_ID_HI; do
    a=$(grep -aE "^const $r: (u16|u64) = " kernel/gfx/fb.fi | sed 's/.*= //; s/ *\/\/.*//')
    b=$(grep -aE "^const $r: (u16|u64) = " kernel/gfx/vmode.fi | sed 's/.*= //; s/ *\/\/.*//')
    if [ -n "$a" ] && [ "$a" = "$b" ]; then ok "$r steht in fb.fi und vmode.fi gleich ($a)"
    else bad "$r: fb.fi='$a', vmode.fi='$b'"; fi
done
v64=$(grep -aE '^const VBE_VRAM64K' kernel/gfx/vmode.fi | sed 's/.*= //; s/ *\/\/.*//')
gleich "VBE_VIDEO_MEMORY_64K ist Index 10 (0x0A)" "10" "$v64"

d1=$(grep -aE '^const DISP_OFF' kernel/lib/kstate.fi | sed 's/.*= //')
d2=$(grep -aE '^const DLUT_OFF' kernel/lib/kstate.fi | sed 's/.*= //')
[ -n "$d1" ] && ok "die kdata-Seite des Modustreibers steht in kstate.fi: $d1" \
             || bad "DISP_OFF fehlt in kernel/lib/kstate.fi"
[ -n "$d2" ] && ok "die kdata-Seite der Nachschlagetabelle steht daneben: $d2" \
             || bad "DLUT_OFF fehlt in kernel/lib/kstate.fi"
gleich "und sie folgt unmittelbar auf den Modustreiber" \
    "$(printf '0x%X' $(( $d1 + 0x1000 )))" "$(printf '0x%X' $(( $d2 )))"
fremd=$(grep -ran --include='*.fi' -E '^const SYS_[A-Za-z0-9_]+: u64 = 181[0-9]' kernel/ \
    | grep -v -e '^kernel/sys/sys.fi' -e '^kernel/user/dispctl.fi' \
              -e '^kernel/user/settings.fi' -e '^kernel/user/qs.fi' \
              -e '^kernel/user/snip.fi' -e '^kernel/user/wmd.fi' || true)
[ -z "$fremd" ] && ok "keine Aufrufnummer aus 1810..1819 steht ausserhalb der Dateien dieser Runde" \
                || bad "Aufrufnummern aus 1810..1819 stehen auch in: $(echo $fremd | tr '\n' ' ')"
eigen=$(grep -ahE '^const SYS_[A-Za-z0-9_]+: u64 = 181[0-9]' kernel/sys/sys.fi | wc -l | tr -d ' ')
gleich "in kernel/sys/sys.fi stehen genau drei Nummern aus dem Vorrat" "3" "$eigen"

if python3 tools/kernel/memmap.py kernel > "$TMPD/karte.txt" 2>&1; then
    ok "die Speicherkarte von kdata: $(tail -1 "$TMPD/karte.txt")"
else
    bad "tools/kernel/memmap.py meldet Kollisionen"; sed 's/^/        /' "$TMPD/karte.txt" | head -8
fi

# ============================================== 2. bauen

echo "== 2. der Kern und die Programme =="
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
[ -f "$TMPD/k0.mb" ] || { echo "DISPLAY: ohne Kern geht nichts weiter"; echo "DISPLAY: $pass passed, $((fail+1)) failed"; exit 1; }

UPROF=""; UCRT="$TMPD/crt.o"
grep -qa '^profile app' kernel/user/settings.fi && { UPROF=--profile=app; UCRT=""; }
if "$FIRNC" $UPROF -c kernel/user/settings.fi -o "$TMPD/eins.o" > "$TMPD/eins.err" 2>&1 \
    && ld -T "$ULD" --defsym=USER_ENTRY=_F0.u_start -o "$TMPD/eins.elf" \
        $UCRT "$TMPD/eins.o" 2>/dev/null; then
    u=$(nm -u "$TMPD/eins.elf" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
    [ -z "$u" ] && ok "das Einstellungen-Programm mit der neuen Bildschirmseite baut frei" \
                || bad "settings.elf hat undefinierte Symbole: $u"
else
    bad "settings.fi laesst sich nicht bauen"; head -8 "$TMPD/eins.err" | sed 's/^/        /'
fi
for f in locale/de/messages locale/en/messages; do
    hat_nicht "$f" "kann dieser Kernel ihn nicht wechseln" \
        "der unwahre Satz steht nicht in $f"
    hat_nicht "$f" "this kernel cannot change it" \
        "und auch nicht in seiner englischen Fassung in $f"
done
grep -v '^\s*//' kernel/user/settings.fi > "$TMPD/eins-code.fi"
hat_nicht "$TMPD/eins-code.fi" "kann dieser Kernel ihn nicht wechseln" \
    "der Satz 'im Betrieb kann dieser Kernel ihn nicht wechseln' ist aus dem Programm weg"
hat kernel/user/settings.fi "SYS_DISPSET" \
    "das Einstellungen-Programm ruft wirklich den Kernel und schreibt keine Datei mehr"

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

# --------------------------------------------------------------- Laeufe

GRUND="nokbd nosched noproc nofs noring3"

VGA_STD=${VGA_STD:-"-vga std -global VGA.edid=off"}

lauf() { # name kommandozeile [zeitlimit]
    local name=$1 zeile=$2 t=${3:-180}
    rm -f "$TMPD/$name.txt"
    timeout "$t" $QEMU_X86 -kernel "$TMPD/k0.mb" -m 256 -append "$zeile" \
        -serial "file:$TMPD/$name.txt" -display none -no-reboot $VGA_STD \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    echo $?
}

RC=0
foto() { # name kommandozeile
    local name=$1 zeile=$2
    local sock="$TMPD/mon-$name.sock" aus="$TMPD/$name.txt" ppm="$TMPD/$name.ppm"
    rm -f "$aus" "$ppm" "$sock"
    timeout 200 $QEMU_X86 -kernel "$TMPD/k0.mb" -m 256 -append "$zeile" \
        -serial "file:$aus" -display none -no-reboot $VGA_STD \
        -monitor "unix:$sock,server,nowait" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1 &
    local pid=$! i=0
    while [ $i -lt 1500 ]; do
        grep -qa '^fb: hold' "$aus" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1; i=$((i + 1))
    done
    sleep 0.4
    python3 tools/gfx/screenshot.py "$sock" "$ppm" 25 > "$TMPD/$name.shot" 2>&1
    wait "$pid"; RC=$?
    rm -f "$sock"
}

lauf_platte() { # name kommandozeile
    local name=$1 zeile=$2
    rm -f "$TMPD/$name.txt"
    cp -f "$TMPD/root.img" "$TMPD/live-$name.img"
    timeout 200 $QEMU_X86 -kernel "$TMPD/k0.mb" -m 256 -append "$zeile" \
        -serial "file:$TMPD/$name.txt" -display none -no-reboot $VGA_STD \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    echo $?
}

# ============================================== 3. die Liste

echo "== 3. die Modusliste: was QEMU wirklich annimmt =="
rc=$(lauf liste "gfx disp $GRUND")
num "der Lauf endet sauber (21 = der Kernel hat sich selbst beendet)" "$rc" eq 21
L="$TMPD/liste.txt"
vram=$(kw "$L" vram)
num "die Karte meldet ihren Bildspeicher ueber VBE_VIDEO_MEMORY_64K (KiB)" "$vram" ge 1024
probed=$(kw "$L" probed)
num "es wurden Kandidaten gefragt und nicht geraten" "$probed" ge 20
anz=$(grep -a -m1 '^disp: modes ' "$L" | sed 's/.*modes //' | tr -d '\r\000')
num "die Liste ist laenger als die zwei Konstanten von Runde K7" "$anz" gt 2
num "und kuerzer als die Kandidatenliste -- es wurde wirklich ausgesiebt" "$anz" lt "$probed"
ref=$(kw "$L" refused); tb=$(kw "$L" toobig); um=$(kw "$L" unmappable)
ok "gefragt $probed · aufgenommen $anz · Register abgelehnt $ref · zu gross fuer den Bildspeicher $tb · nicht abbildbar $um"
s=$((anz + ref + tb + um))
gleich "die vier Zahlen gehen auf" "$probed" "$s"
hat "$L" "disp:   800x600x 32" "800x600 steht in der Liste (was Runde K7 konnte)"
hat "$L" "disp:   1024x768x 32" "1024x768 steht in der Liste (was Runde K7 auch konnte)"
hat "$L" "disp:   1920x1080x 32" "1920x1080 steht in der Liste (was Runde K7 NICHT konnte)"
n_out=$(grep -ac '^disp: out ' "$L")
gleich "jeder ausgeschlossene Kandidat wird mit Grund gemeldet" "$((ref + tb + um))" "$n_out"
lim=$(kw "$L" maplimit)
num "die Schranke dieses Kernels (acht 2-MiB-Fensterplaetze) steht als Zahl" "$lim" ge 4194304
st=$(grep -ao 'disp: selftest [0-9]*' "$L" | head -1 | grep -o '[0-9]*$')
gleich "die Zusagen des Modustreibers ueber sich selbst" "15" "$st"
st2=$(grep -ao 'fb: selftest2 [0-9]*' "$L" | head -1 | grep -o '[0-9]*$')
gleich "die Zusagen ueber Drehung, Skalierung und Tabelle" "11" "$st2"
st1=$(grep -ao 'fb: selftest [0-9]*' "$L" | head -1 | grep -o '[0-9]*$')
gleich "und die dreizehn aus Runde K7 stehen unveraendert" "13" "$st1"

# ============================================== 4. EDID

echo "== 4. EDID: was der Bildschirm ueber sich sagt =="
rc=$(VGA_STD="-vga std" lauf edid "gfx disp dispedid $GRUND")
num "der Lauf endet sauber" "$rc" eq 21
E="$TMPD/edid.txt"
if grep -qa '^disp: edid ok' "$E"; then
    ok "ein gueltiger EDID-Block wurde gelesen (Kennung und Pruefsumme stimmen)"
    hat "$E" "ven=RHT" "der Hersteller steht drin -- QEMU meldet sich als RHT (Red Hat)"
    hat "$E" "mod=QEMU Monitor" "und der Modellname"
    nat=$(grep -ao 'nat=[0-9]*x[0-9]*' "$E" | head -1 | sed 's/nat=//')
    [ -n "$nat" ] && ok "die native Aufloesung aus dem ersten Zeitlagensatz: $nat" \
                  || bad "keine native Aufloesung im EDID-Block"
    roh=$(grep -a -m1 '^disp: edid 0x' "$E" | sed 's/^disp: edid //' | tr -d '\r\000')
    python3 - "$roh" <<'PY' > "$TMPD/edid.chk" 2>&1
import sys, re
b = [int(x, 16) for x in re.findall(r'0x([0-9a-fA-F]+)', sys.argv[1])]
assert len(b) == 128, f"128 Oktette erwartet, {len(b)} bekommen"
assert b[0:8] == [0,255,255,255,255,255,255,0], "die EDID-Kennung stimmt nicht"
assert sum(b) % 256 == 0, f"Pruefsumme {sum(b)%256}, erwartet 0"
m = (b[8] << 8) | b[9]
ven = "".join(chr(64 + ((m >> s) & 31)) for s in (10, 5, 0))
w = b[56] | ((b[58] >> 4) << 8)
h = b[59] | ((b[61] >> 4) << 8)
print(f"{ven} {w}x{h} version {b[18]}.{b[19]}")
PY
    if [ $? -eq 0 ]; then ok "der rohe Block rechnet nach: $(cat "$TMPD/edid.chk")"
    else bad "der rohe EDID-Block geht nicht auf: $(cat "$TMPD/edid.chk")"; fi
else
    why=$(kw "$E" why)
    ok "kein EDID-Block auf dieser Maschine, Grund $why -- der Rueckfall auf die Modusliste traegt"
    num "und die Liste traegt ihn wirklich" "$(grep -a -m1 '^disp: modes ' "$E" | sed 's/.*modes //')" gt 2
fi

# ============================================== 5. der Wechsel

echo "== 5. der Wechsel zur Laufzeit, im Bild =="

foto vorher "gfx disp nocursor fbtest fbhold $GRUND"
num "der Lauf endet sauber" "$RC" eq 21
schau "VORHER: das Foto ist 800x600" size "$TMPD/vorher.ppm" 800 600
schau "VORHER: Feld 1 ist reines Rot" area "$TMPD/vorher.ppm" 0 0 100 100 255 0 0
schau "VORHER: die Textzeile steht bildpunktgenau" \
    text "$TMPD/vorher.ppm" kernel/gfx/font.fi 14 0 "$MARKE_PRODUKT K7 FRAMEBUFFER 01234"

foto nachher "gfx disp dispbig nocursor fbtest fbhold $GRUND"
num "der Lauf endet sauber" "$RC" eq 21
N="$TMPD/nachher.txt"
hat "$N" "fb: 800x600x32" "der Kernel startet in 800x600"
sw=$(grep -a -m1 '^disp: switch 800x600 -> 1024x768' "$N")
[ -n "$sw" ] && ok "der Wechsel ist im Mitschnitt: $sw" || bad "kein Wechsel gemeldet"
rcsw=$(echo "$sw" | grep -ao 'rc=[0-9]*' | sed 's/rc=//')
gleich "der Wechsel meldet Erfolg" "0" "$rcsw"
us=$(echo "$sw" | grep -ao 'us=[0-9]*' | sed 's/us=//')
[ -n "$us" ] && ok "er hat $us Mikrosekunden gedauert (Registersatz, Neuabbildung, Zweitpuffer, Neuzeichnen)" \
             || bad "keine Zeit gemessen"
schau "NACHHER: das Foto ist 1024x768 -- der Modus wurde WIRKLICH gewechselt" \
    size "$TMPD/nachher.ppm" 1024 768
schau "NACHHER: das Pruefbild ist neu gezeichnet, Feld 1 ist wieder rot" \
    area "$TMPD/nachher.ppm" 0 0 100 100 255 0 0
schau "NACHHER: Feld 4 ist weiss" area "$TMPD/nachher.ppm" 300 0 100 100 255 255 255
schau "NACHHER: die Textzeile steht bildpunktgenau im NEUEN Modus" \
    text "$TMPD/nachher.ppm" kernel/gfx/font.fi 14 0 "$MARKE_PRODUKT K7 FRAMEBUFFER 01234"
schau "NACHHER: die Ecke bei (1023,767) gibt es jetzt und sie ist schwarz" \
    pixel "$TMPD/nachher.ppm" 1023 767 0 0 0
schau_nicht "VORHER gab es diese Ecke NICHT" pixel "$TMPD/vorher.ppm" 1023 767 0 0 0

foto zurueck "gfx disp dispbig dispback nocursor fbtest fbhold $GRUND"
num "der Lauf endet sauber" "$RC" eq 21
Z="$TMPD/zurueck.txt"
hat "$Z" "disp: switch 1024x768 -> 800x600" "der Rueckweg steht im Mitschnitt"
swz=$(grep -a -m1 '^disp: sw=' "$Z" | grep -ao 'sw=[0-9]*' | sed 's/sw=//')
gleich "zwei Wechsel in einem Lauf" "2" "$swz"
schau "ZURUECK: das Foto ist wieder 800x600" size "$TMPD/zurueck.ppm" 800 600
schau "ZURUECK: und das Pruefbild steht wieder da" \
    text "$TMPD/zurueck.ppm" kernel/gfx/font.fi 14 0 "$MARKE_PRODUKT K7 FRAMEBUFFER 01234"

# ============================================== 6. der Fehlerfall

echo "== 6. der Fehlerfall: kein schwarzer Bildschirm =="
foto schlecht "gfx disp dispbad nocursor fbtest fbhold $GRUND"
num "der Lauf endet sauber -- der abgelehnte Modus haelt den Kernel NICHT an" "$RC" eq 21
S="$TMPD/schlecht.txt"
sb=$(grep -a -m1 '^disp: switch 800x600 -> 4096x4096' "$S")
[ -n "$sb" ] && ok "der Versuch steht im Mitschnitt: $sb" || bad "kein Versuch gemeldet"
rcb=$(echo "$sb" | grep -ao 'rc=[0-9]*' | sed 's/rc=//')
num "er wird abgelehnt (2 = der Modus steht in keiner Liste)" "$rcb" eq 2
hat "$S" "panel=800x600" "und die Tafel ist danach unveraendert"
fb_=$(grep -a -m1 '^disp: sw=' "$S" | grep -ao 'fail=[0-9]*' | sed 's/fail=//')
num "der Zaehler der abgelehnten Wechsel steht" "$fb_" ge 1
swb=$(grep -a -m1 '^disp: sw=' "$S" | grep -ao 'sw=[0-9]*' | sed 's/sw=//')
gleich "und KEIN Wechsel hat stattgefunden" "0" "$swb"
schau "das Foto ist 800x600 -- der Bildmodus steht noch" size "$TMPD/schlecht.ppm" 800 600
schau "Feld 1 ist rot -- der Bildschirm ist NICHT schwarz" \
    area "$TMPD/schlecht.ppm" 0 0 100 100 255 0 0
schau "und die Textzeile steht bildpunktgenau da, als waere nichts gewesen" \
    text "$TMPD/schlecht.ppm" kernel/gfx/font.fi 14 0 "$MARKE_PRODUKT K7 FRAMEBUFFER 01234"
schau_nicht "ein schwarzer Schirm haette hier kein Rot" \
    area "$TMPD/schlecht.ppm" 0 0 100 100 0 0 0

# ============================================== 7. die Frist

echo "== 7. die Bestaetigungsfrage: wer nichts sagt, bekommt den alten Modus =="
rc=$(lauf frist "gfx disp dispconfirm $GRUND" 260)
num "der Lauf endet sauber" "$rc" eq 21
F="$TMPD/frist.txt"
hat "$F" "disp: switch 800x600 -> 1024x768" "gewechselt wurde"
cf1=$(grep -a -m1 '^disp: confirm pend=' "$F" | grep -ao 'pend=[0-9]*' | sed 's/pend=//')
gleich "danach steht eine Frist offen" "1" "$cf1"
left=$(grep -a -m1 '^disp: confirm pend=' "$F" | grep -ao 'left=[0-9]*' | sed 's/left=//')
num "und sie zaehlt in Sekunden herunter (15, wie bei Windows)" "$left" ge 14
cf2=$(grep -a -m2 '^disp: confirm pend=' "$F" | tail -1)
p2=$(echo "$cf2" | grep -ao 'pend=[0-9]*' | sed 's/pend=//')
a2=$(echo "$cf2" | grep -ao 'after=[0-9]*' | sed 's/after=//')
gleich "nach Ablauf ist die Frist weg" "0" "$p2"
gleich "und der Kernel hat von SELBST zurueckgeschaltet" "1" "$a2"
case "$cf2" in
    *panel=800x600*) ok "die Tafel steht wieder auf dem alten Modus" ;;
    *) bad "die Tafel steht nicht wieder auf 800x600: $cf2" ;;
esac
rv=$(grep -a -m1 '^disp: sw=' "$F" | grep -ao 'rev=[0-9]*' | sed 's/rev=//')
num "der Zaehler der Rueckkehren steht" "$rv" ge 1

# ============================================== 8. die Drehung

echo "== 8. die Drehung: im Bild und nicht nur in der Zahl =="
foto dreh "gfx disp disprot nocursor fbtest fbhold $GRUND"
num "der Lauf endet sauber" "$RC" eq 21
D="$TMPD/dreh.txt"
hat "$D" "disp: rot=90" "der Kernel meldet die Vierteldrehung"
hat "$D" "img=600x800" "das BILD ist danach 600x800 ..."
hat "$D" "panel=800x600" "... und die TAFEL bleibt 800x600"
schau "das Foto ist 800x600 -- gedreht wird beim Uebertragen, nicht in der Karte" \
    size "$TMPD/dreh.ppm" 800 600
schau "Feld 1 (rot) liegt nach der Drehung rechts oben" \
    pixel "$TMPD/dreh.ppm" 749 50 255 0 0
schau "Feld 2 (gruen) liegt darunter" pixel "$TMPD/dreh.ppm" 749 150 0 255 0
schau_nicht "und links oben, wo es UNGEDREHT laege, ist es nicht" \
    pixel "$TMPD/dreh.ppm" 50 50 255 0 0

# ============================================== 9. die Kosten

echo "== 9. die Kosten des Umrechnens, gemessen =="
rc=$(lauf kosten "gfx disp dispbench $GRUND" 260)
num "der Lauf endet sauber" "$rc" eq 21
B="$TMPD/kosten.txt"
bz=$(grep -a -m1 '^disp: bench [0-9]' "$B")
[ -n "$bz" ] && ok "gemessen: $bz" || bad "keine Messung"
px=$(echo "$bz" | grep -ao 'px=[0-9]*' | sed 's/px=//')
d_fl=$(echo "$bz" | grep -ao 'flush=[0-9]*' | sed 's/flush=//')
d_lu=$(echo "$bz" | grep -ao 'lut=[0-9]*' | sed 's/lut=//')
d_ln=$(echo "$bz" | grep -ao 'lutline=[0-9]*' | sed 's/lutline=//')
d_ro=$(echo "$bz" | grep -ao 'rot90=[0-9]*' | sed 's/rot90=//')
num "gemessen wurde bei der GROESSTEN Aufloesung der Liste (Bildpunkte)" "$px" ge 1000000
num "der schnelle Weg von Runde K7 steht noch (Mikrosekunden je Bild)" "$d_fl" gt 0
num "die Nachschlagetabelle kostet mehr als der schnelle Weg" "$d_lu" gt "$d_fl"
num "eine TEXTZEILE durch die Tabelle kostet deutlich weniger als ein volles Bild" \
    "$d_ln" lt "$((d_lu / 4))"
num "die Vierteldrehung kostet ein volles Bild" "$d_ro" gt 0
ok "je Bildpunkt: flush $((d_fl * 1000 / px)) ns · Tabelle $((d_lu * 1000 / px)) ns · Drehung $((d_ro * 1000 / px)) ns (QEMU/TCG, kein KVM)"

# ============================================== 10. Ring 3

echo "== 10. dieselben Zahlen aus Ring 3, ueber 1800..1802 =="
rc=$(VGA_STD="-vga std" lauf_platte ring3 "osum gfx disp nokbd nosched noproc script=dispctl test;dispctl raw")
num "der Lauf mit /bin/dispctl endet sauber" "$rc" eq 21
R="$TMPD/ring3.txt"
hat "$R" "osum\$ dispctl" "das Programm ist gestartet"
t3=$(grep -ao 'dispctl: test [0-9]*' "$R" | head -1 | grep -o '[0-9]*$')
gleich "die Zusagen aus Ring 3" "12" "$t3"
wig=$(grep -aE '^const WIG_BASE' kernel/sys/sys.fi | sed 's/.*= //')
dg=$(grep -aE '^const SYS_OSUM_DISPGET' kernel/sys/sys.fi | sed 's/.*= //')
if [ "$dg" -gt "$((wig + 9))" ]; then
    ok "die Aufrufnummern dieser Runde ($dg..) liegen hinter dem Block der Widgets ($wig..$((wig+9)))"
else
    bad "die Aufrufnummern kollidieren mit WIG_BASE: disp=$dg, wig=$wig"
fi

for f in vram:vram maplimit:maplimit probed:probed refused:refused toobig:toobig; do
    kn=${f%%:*}; un=${f##*:}
    a=$(kw "$L" "$kn"); b=$(uw "$R" "$un")
    if [ "$kn" = vram ]; then a=$((a * 1024)); fi
    gleich "$kn: Kernelmeldung und Ring 3 sagen dasselbe" "$a" "$b"
done
u_anz=$(uw "$R" count)
gleich "auch die Laenge der Liste" "$anz" "$u_anz"
#
k_panel=$(grep -ao '^disp: eigen .* panel=[0-9]*x[0-9]*' "$R" 2>/dev/null \
    | tail -1 | grep -ao 'panel=[0-9]*' | sed 's/panel=//')
[ -n "$k_panel" ] || k_panel=$(grep -ao '^fb: [0-9]*x[0-9]*' "$R" 2>/dev/null \
    | head -1 | sed 's/^fb: //' | cut -dx -f1)
gleich "die Tafel -- dieselbe Breite, die der Kern im selben Lauf meldet" \
    "$k_panel" "$(uw "$R" panelw)"
gleich "und das Bild ist ungedreht genauso gross" "$k_panel" "$(uw "$R" imgw)"
gleich "32 Bit je Bildpunkt" "32" "$(uw "$R" bpp)"
gleich "EDID hat auch Ring 3 gesehen" "1" "$(uw "$R" edidok)"
hat "$R" "dispctl: vendor=RHT" "der Herstellername kommt ueber osum_dispstr in Ring 3 an"
hat "$R" "dispctl: model=QEMU Monitor" "der Modellname auch"
n_modes=$(grep -ac '^dispctl: mode ' "$R")
gleich "und die Liste kommt Zeile fuer Zeile heraus" "$anz" "$n_modes"

rc=$(lauf_platte ring3b "osum gfx disp nokbd nosched noproc script=dispctl set 1024 768;dispctl keep;dispctl raw")
num "der Lauf endet sauber" "$rc" eq 21
R2="$TMPD/ring3b.txt"
gleich "ein Programm in Ring 3 hat die Tafel umgestellt" "1024" "$(uwl "$R2" panelw)"
gleich "und die Hoehe" "768" "$(uwl "$R2" panelh)"
gleich "die Zeilenlaenge ist mitgewandert" "4096" "$(uwl "$R2" pitch)"
gleich "der Kernel zaehlt genau einen Wechsel" "1" "$(uwl "$R2" switches)"
gleich "direkt nach dem Wechsel laeuft die Bestaetigungsfrist" "1" "$(uw "$R2" pending)"
gleich "nach dem Bestaetigen ist sie zu" "0" "$(uwl "$R2" pending)"
gleich "und der Kernel hat die Bestaetigung gezaehlt" "1" "$(uwl "$R2" confirms)"

# ============================================== 11. die Gegenprobe

echo "== 11. DIE GEGENPROBE: derselbe Kernel ohne das Wort 'disp' =="
rc=$(lauf ohne "gfx $GRUND")
num "der Lauf endet sauber" "$rc" eq 21
O="$TMPD/ohne.txt"
hat_nicht "$O" "disp: vram=" "ohne 'disp' wird nichts erkundet"
hat_nicht "$O" "disp: modes" "und es gibt keine Liste"
hat_nicht "$O" "disp: edid" "und kein EDID"
hat "$O" "fb: 800x600x32" "der Bildschirm von Runde K7 steht unveraendert"
hat "$O" "fb: selftest 13 / 13" "und seine dreizehn Zusagen auch"
rc=$(lauf_platte ohne3 "osum gfx nokbd nosched noproc script=dispctl raw;dispctl test")
num "der Lauf endet sauber" "$rc" eq 21
O3="$TMPD/ohne3.txt"
hat "$O3" "dispctl: there is no screen" "/bin/dispctl sagt es und rechnet nicht weiter"
gleich "und jede Zahl ist ein Strich und keine Null" "-" "$(uw "$O3" vram)"
gleich "auch die Laenge der Liste" "-" "$(uw "$O3" count)"
gleich "auch EDID" "-" "$(uw "$O3" edidok)"

echo
echo "DISPLAY: $pass passed, $fail failed"
[ "$fail" = 0 ]
