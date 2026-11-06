#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
#
#
#
#
#
# Die Abschnitte:
#
#
# Verwendung:  bash tools/wm/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/brand.sh
marke_laden . || exit 1
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
    if [ -z "$wert" ]; then bad "$name: no number found (expected $op $want)"; return; fi
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
    if [ "$rc" -ne 0 ]; then ok "$name ($aus)"; else bad "$name -- passed: $aus"; fi
}
zahl() { grep -aoE "$2" "$1" | head -1 | grep -oE '[0-9]+' | tail -1; }
zahl2() { grep -aoE "$2" "$1" | tail -1 | grep -oE '[0-9]+' | tail -1; }

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "vendor/firn/fetch-firnc.sh fehlgeschlagen"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "WM: skipped, qemu-system-x86_64 is missing"
    exit 0
fi

# --------------------------------------------------------------- Laeufe
#

DISK="$TMPD/disk.img"
GRUND="nokbd nosched noproc nofs"

#
VGA_STD=${VGA_STD:-"-vga std -global VGA.edid=off"}

# r389: the default mode of the VM is 1280x800 now, this runner's arithmetic (the pointer in the
# middle of the picture at 399,299, the window places) is for 800x600
res800() { case " $1 " in *" fbres="*) printf '%s' "$1" ;; *) printf '%s fbres=800x600' "$1" ;; esac; }
lauf() { # abbild kommandozeile ausgabe
    local abbild=$1 zeile=$(res800 "$2") aus=$3
    cp -f "$DISK" "$TMPD/live.img"
    timeout 180 $QEMU_X86 -kernel "$abbild" -m 256 -append "$zeile" \
        -serial "file:$aus" -display none -no-reboot $VGA_STD \
        -drive "file=$TMPD/live.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    return $?
}

RC=0
foto() { # abbild kommandozeile ausgabe ppm [monitorbefehle]
    local abbild=$1 zeile=$(res800 "$2") aus=$3 ppm=$4 mon=${5:-}
    local sock="$TMPD/mon-$$.sock"
    local live="$TMPD/live-$(basename "$aus").img"
    rm -f "$aus" "$ppm" "$sock"
    cp -f "$DISK" "$live"
    timeout 180 $QEMU_X86 -kernel "$abbild" -m 256 -append "$zeile" \
        -serial "file:$aus" -display none -no-reboot $VGA_STD \
        -monitor "unix:$sock,server,nowait" \
        -drive "file=$live,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local pid=$!
    local i=0
    while [ $i -lt 900 ]; do
        grep -qa '^wm: hold' "$aus" 2>/dev/null && break
        grep -qa '^fb: hold' "$aus" 2>/dev/null && break
        grep -qa 'wm: dauer' "$aus" 2>/dev/null && { sleep 2; break; }
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.15
        i=$((i + 1))
    done
    if [ -n "$mon" ]; then
        python3 tools/wm/monitor.py "$sock" "$mon" > "$TMPD/mon.txt" 2>&1
    fi
    python3 tools/gfx/screenshot.py "$sock" "$ppm" 25 > "$TMPD/schuss.txt" 2>&1
    # FOTO_QUIT=1: a run that never ends by itself (`wmdauer`, a shell
    # waiting for keys) is ended through the monitor after the photo.
    if [ -n "${FOTO_QUIT:-}" ]; then
        python3 -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); s.sendall(b"quit\n")' "$sock" 2>/dev/null
    fi
    wait "$pid"
    RC=$?
    if [ -n "${WM_KEEP:-}" ]; then cp "$ppm" "$aus" "$WM_KEEP/" 2>/dev/null; fi
    rm -f "$sock"
    return 0
}

echo "== 1. build: the same kernel from both compilers =="
for s in 0 1; do
    if bash tools/build-kernel.sh "$TMPD/k$s.mb" --stufe "$s" > "$TMPD/b$s.log" 2>&1; then
        ok "firnc$s: Kernel gebaut ($(stat -c%s "$TMPD/k$s.mb") Oktette)"
    else
        bad "firnc$s: the kernel cannot be built"
        sed 's/^/        /' "$TMPD/b$s.log" | head -12
    fi
done
K0="$TMPD/k0.mb"
[ -f "$K0" ] || { echo "WM: $pass passed, $((fail + 1)) failed"; exit 1; }

echo "== 2. the memory map of kdata: three new regions =="
kart=$(python3 tools/kernel/memmap.py kernel 2>&1)
if [ $? -eq 0 ]; then ok "the memory map of kdata: $kart"
else bad "the memory map of kdata collides"; echo "$kart" | sed 's/^/        /'; fi
#
#
kartv=$(python3 tools/kernel/memmap.py kernel -v 2>/dev/null)
if [ $? -ne 0 ]; then
    bad "memmap.py -v ist fehlgeschlagen"
fi
for b in MOUSE WM TTF; do
    if grep -q " $b  *kstate.fi:" <<< "$kartv"; then
        ok "the region $b is in the map"
    else
        bad "the region $b is NOT in the map"
    fi
done
GG="$TMPD/kernel-gg"; mkdir -p "$GG"
( cd kernel && find . -name '*.fi' -exec cp --parents {} "$GG/" \; )
sed -i 's/^const WM_OFF: u64 = 0x1E000/const WM_OFF: u64 = 0x3C000/' "$GG/lib/kstate.fi"
gg=$(python3 tools/kernel/memmap.py "$GG" 2>&1)
if [ $? -ne 0 ] && printf '%s' "$gg" | grep -q 'COLLISION'; then
    ok "with WM_OFF at 0x3C000 the checker finds the collision with FB"
else
    bad "the collision checker does NOT find the new collision: $gg"
fi
vt=$(printf '%s\n' "$kartv" | grep -A9 'die Vektortabelle' | tail -8 | tr -s ' ' | sed 's/^ //' | tr '\n' ' ')
if python3 tools/kernel/memmap.py kernel >/dev/null 2>&1; then
    ok "the vector table has no overlaps ($vt)"
else
    bad "die Vektortabelle kollidiert"
fi
GV="$TMPD/kernel-gv"; mkdir -p "$GV"
( cd kernel && find . -name '*.fi' -exec cp --parents {} "$GV/" \; )
sed -i 's/^const VEC_MOUSE: u64 = 46/const VEC_MOUSE: u64 = 44/' "$GV/arch/x86_64/trap.fi"
gv=$(python3 tools/kernel/memmap.py "$GV" 2>&1)
if [ $? -ne 0 ] && printf '%s' "$gv" | grep -q 'vector 44 has two names'; then
    ok "with VEC_MOUSE back at 44 the checker finds the collision with VEC_NVME"
else
    bad "the vector checker does NOT find this round's bug: $gv"
fi

echo "== 3. the fonts: reproducibly cut from DejaVu =="
DEJAVU=${DEJAVU:-/usr/share/fonts/truetype/dejavu}
for f in mono sans; do
    [ -f "assets/osum-$f.ttf" ] && ok "assets/osum-$f.ttf is in the tree ($(stat -c%s assets/osum-$f.ttf) octets)" \
        || bad "assets/osum-$f.ttf fehlt"
done
if [ -f "$DEJAVU/DejaVuSansMono.ttf" ]; then
    python3 tools/ttf/subset.py "$DEJAVU/DejaVuSansMono.ttf" "$TMPD/mono.ttf" >/dev/null 2>&1
    cmp -s "$TMPD/mono.ttf" assets/osum-mono.ttf \
        && ok "osum-mono.ttf is rebuilt octet by octet from DejaVu Sans Mono" \
        || bad "osum-mono.ttf cannot be reproduced"
else
    echo "        (DejaVu is not under $DEJAVU -- cut not recomputed)"
fi
# r399 (design audit): the proportional faces are Inter (SIL OFL), cut by tools/design/mkfont.py
if [ -f assets/src/Inter-Regular.ttf ] && python3 -c "import fontTools, uharfbuzz" 2>/dev/null; then
    python3 tools/design/mkfont.py assets/src/Inter-Regular.ttf "$TMPD/sans.ttf" assets/src/osum-sans.cps >/dev/null 2>&1
    python3 tools/design/mkfont.py assets/src/Inter-SemiBold.ttf "$TMPD/sansb.ttf" assets/src/osum-sans.cps >/dev/null 2>&1
    cmp -s "$TMPD/sans.ttf" assets/osum-sans.ttf \
        && ok "osum-sans.ttf is rebuilt octet by octet from Inter Regular" \
        || bad "osum-sans.ttf cannot be reproduced"
    cmp -s "$TMPD/sansb.ttf" assets/osum-sans-bold.ttf \
        && ok "osum-sans-bold.ttf is rebuilt octet by octet from Inter SemiBold" \
        || bad "osum-sans-bold.ttf cannot be reproduced"
else
    echo "        (Inter source or fontTools/uharfbuzz missing -- cut not recomputed)"
fi
info=$(python3 tools/ttf/raster.py info assets/osum-sans.ttf)
echo "        $info"
case "$info" in
    *"kern="0*) bad "the roman face has no kerning pairs" ;;
    *"kern="*) ok "the roman face carries a kern table: ${info##*kern=}" ;;
esac
gebaut=1
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || gebaut=0
for p in sh echo uname; do
    vendor/firn/bin/firnc "kernel/user/$p.fi" -o "$TMPD/$p.o" >"$TMPD/$p.log" 2>&1 \
        && ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
            -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>>"$TMPD/$p.log" \
        || { gebaut=0; sed 's/^/        /' "$TMPD/$p.log" | head -4; }
done
[ "$gebaut" = 1 ] && ok "/bin/sh, /bin/echo und /bin/uname gebaut ($(stat -c%s "$TMPD/sh.elf" 2>/dev/null) Oktette fuer die Shell)" \
    || bad "the programs for the terminal window cannot be built"
bash tools/mkfsfi/mkfs.sh build "$DISK" 4096 /lib/ \
    /lib/mono.ttf=assets/osum-mono.ttf /lib/sans.ttf=assets/osum-sans.ttf \
    /bin/ /bin/sh="$TMPD/sh.elf" /bin/echo="$TMPD/echo.elf" \
    /bin/uname="$TMPD/uname.elf" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "mkfs.py builds an image with both fonts and the shell" \
    || { bad "mkfs.py fehlgeschlagen"; sed 's/^/        /' "$TMPD/mkfs.txt"; }

echo "== 4. the rasteriser: kernel against host, octet by octet =="
lauf "$K0" "gfx wm ttfdump $GRUND" "$TMPD/dump.txt"
rc=$?
num "der Kern beendet sich sauber" "$rc" eq 21
has "$TMPD/dump.txt" "ttfglyph c=86" "der Kern gibt seine Glyphen aus"
v=$(python3 tools/ttf/raster.py vergleich assets/osum-mono.ttf "$TMPD/dump.txt" 2>&1)
if [ $? -eq 0 ]; then ok "both rasterisers agree ($v)"
else bad "the two rasterisers diverge"; echo "$v" | sed 's/^/        /'; fi
if python3 tools/ttf/raster.py vergleich assets/osum-sans.ttf "$TMPD/dump.txt" >/dev/null 2>&1; then
    bad "the comparison also works against the wrong font"
else
    ok "against the roman face the same comparison does NOT work"
fi
st=$(zahl "$TMPD/dump.txt" 'ttf: mono.*selftest [0-9]+')
num "die Zusagen des Schriftlesers ueber sich selbst (mono)" "$st" eq 12
st2=$(zahl "$TMPD/dump.txt" 'ttf: sans.*selftest [0-9]+')
num "dieselben fuer die Antiqua" "$st2" eq 12
kp=$(grep -aoE 'ttf: sans.*kern=[0-9]+' "$TMPD/dump.txt" | grep -oE 'kern=[0-9]+' | grep -oE '[0-9]+')
num "Zeichenpaare, die wirklich unterschnitten werden" "$kp" gt 20
km=$(grep -aoE 'ttf: mono.*kern=[0-9]+' "$TMPD/dump.txt" | grep -oE 'kern=[0-9]+' | grep -oE '[0-9]+')
num "und die Festbreitenschrift hat keine (sie braucht keine)" "$km" eq 0

echo "== 5. the pointing device: PS/2 on the second port of the 8042 =="
ms=$(zahl "$TMPD/dump.txt" 'mouse: id=[0-9]+')
num "die Kennung nach dem Radgriff (3 = mit Rad, vier Oktette je Paket)" "$ms" eq 3
mst=$(zahl "$TMPD/dump.txt" 'mouse: .*selftest [0-9]+')
num "die Zusagen des Treibers ueber sich selbst" "$mst" eq 13

echo "== 6. the window server: self-test and the photo =="
foto "$K0" "gfx wm wmhold $GRUND" "$TMPD/w.txt" "$TMPD/w.ppm"
num "der Kern beendet sich sauber" "$RC" eq 21
has "$TMPD/w.txt" "wm: hold" "der Kern haelt fuer das Foto still"
ws=$(zahl "$TMPD/w.txt" 'wm: .*selftest [0-9]+')
num "die Zusagen des Fensterservers ueber sich selbst" "$ws" eq 31
# r400: the VT subset of the terminal (cursor position, erase, reverse video, swallowed private
# sequences, a sequence cut in two writes, an unknown sequence dropped whole)
has "$TMPD/w.txt" "wm: vttest 7 / 7" "das Terminal versteht die VT-Teilmenge (7 von 7)"
has "$TMPD/w.txt" "wm: vttest2 32 / 32" "das Terminal fuehrt Cursor, Loeschen, Region, Farben, Alt-Bildschirm, Zeichenketten aus (32 von 32)"
has "$TMPD/w.txt" "wm: 800x600" "der Server kennt die Flaeche"
has "$TMPD/w.txt" "wm: term win=0  cols=56  rows=20  cell=10x19" \
    "das Terminalfenster hat ein Raster von 56x20 Zellen zu 10x19"
wn=$(zahl2 "$TMPD/w.txt" 'wm: windows=[0-9]+')
num "zwei Fenster: das Terminal und die Anwendung aus Ring 3" "$wn" eq 2
schau "das Foto ist 800x600" size "$TMPD/w.ppm" 800 600
schau "der Rahmen des Fensters aus Ring 3 liegt bildpunktgenau" \
    rect "$TMPD/w.ppm" 420 330 264 174 76 154 232
schau "an der Ueberschneidung steht das OBERE Fenster" \
    area "$TMPD/w.ppm" 430 353 100 6 16 24 32
schau_nicht "und NICHT die Flaeche des unteren" \
    area "$TMPD/w.ppm" 430 353 100 6 16 20 26
schau "der Hintergrund neben den Fenstern gehoert dem Server" \
    area "$TMPD/w.ppm" 700 60 80 80 30 42 56
gsi=$(grep -aoE 'gsi=0x[0-9a-f]+' "$TMPD/w.txt" | head -1 | sed 's/.*=//')
if [ "$gsi" = "0x2e" ]; then
    ok "the redirection table entry for GSI 12: $gsi (vector 46, not masked)"
else
    bad "GSI 12 zeigt '$gsi' statt 0x2e"
fi
# r389: the pointer is the modern arrow now (black body, light outline, anti-aliased edge),
# not the old black outline with a white fill: at the tip the picture is no longer the
# background, two points inside it is black.
schau_nicht "die Spitze des Zeigers steht in der Bildmitte (dort ist nicht mehr der Hintergrund)" \
    pixel "$TMPD/w.ppm" 399 299 30 42 56
# W-CURSOR: the pointer stands over the terminal window's client grid, so it is the text bar (I-beam,
# rim white, stem black): the stem is two points wide at x 398-399, white rim at x 400.
schau "und zwei Bildpunkte tiefer ist die Textmarke schwarz gefuellt (Zeiger ueber dem Terminalraster)" \
    pixel "$TMPD/w.ppm" 398 301 0 0 0

echo "== 7. the text in the window, pixel-exact against the second rasteriser =="
schau "Zeile 0 des Terminalfensters" \
    tgrid "$TMPD/w.ppm" assets/osum-mono.ttf 16 26 62 10 19 0 0 \
    224 230 236 16 20 26 "$MARKE_PRODUKT K10 WM 0123"
schau "Zeile 1 des Terminalfensters" \
    tgrid "$TMPD/w.ppm" assets/osum-mono.ttf 16 26 62 10 19 1 0 \
    224 230 236 16 20 26 "abcdefghijklm ABCDEFGHIJK +-*/"
schau "der Titel des Fensters aus Ring 3, mit Unterschneidung" \
    tchain "$TMPD/w.ppm" assets/osum-sans.ttf 15 432 348 255 255 255 \
    28 78 126 "Klick mich"
schau "the active tab label of the terminal window (title strip)" \
    tchain "$TMPD/w.ppm" assets/osum-sans.ttf 15 44 58 224 230 236 \
    16 20 26 "Terminal 1" 0 58
# ... and it IS fUi's ink: the kernel's old 4x4 samples do NOT match.
schau_nicht "COUNTER-PROOF: the tab label is NOT the old kernel ink" \
    tchain "$TMPD/w.ppm" kern:assets/osum-sans.ttf 15 44 58 224 230 236 \
    16 20 26 "Terminal 1" 0 58
schau "der Text ist wirklich kantengeglaettet" \
    smooth "$TMPD/w.ppm" 26 62 280 20 224 230 236 16 20 26 100
schau_nicht "wo kein Text steht, geht dieselbe Rechnung NICHT auf" \
    tgrid "$TMPD/w.ppm" assets/osum-mono.ttf 16 26 62 10 19 8 0 \
    224 230 236 16 20 26 "$MARKE_PRODUKT K10 WM 0123"

echo "== 8. the mouse: movement and click from outside into the machine =="
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
has "$TMPD/k.txt" "wclick: down 78,48" \
    "der Klick kommt in Ring 3 an, mit den Koordinaten IM Fenster"
schau "der Fleck, den Ring 3 auf den Klick hin gemalt hat" \
    area "$TMPD/k.ppm" 500 400 8 8 255 192 32
schau_nicht "und einen Bildpunkt daneben ist er nicht" \
    pixel "$TMPD/k.ppm" 499 400 255 192 32
schau_nicht "ohne Klick ist der Fleck NICHT da" \
    area "$TMPD/w.ppm" 500 400 8 8 255 192 32
hasnot "$TMPD/w.txt" "wclick: down" "und in Ring 3 kommt dann auch nichts an"
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

echo "== 9. move and close -- with the mouse =="
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
schau "das Fenster steht nach dem Ziehen an der neuen Stelle" \
    rect "$TMPD/z.ppm" 300 210 264 174 76 154 232
schau_nicht "und an der alten NICHT mehr" \
    rect "$TMPD/z.ppm" 420 330 264 174 76 154 232
schau "der Titel ist mitgewandert, bildpunktgenau" \
    tchain "$TMPD/z.ppm" assets/osum-sans.ttf 15 312 228 255 255 255 \
    28 78 126 "Klick mich"
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
    rect "$TMPD/c.ppm" 420 330 264 174 76 154 232
schau "wo das Fenster war, steht wieder der Hintergrund des Servers" \
    area "$TMPD/c.ppm" 600 460 60 40 30 42 56
schau "und wo es das Terminalfenster verdeckte, steht wieder dessen Flaeche" \
    area "$TMPD/c.ppm" 440 400 100 30 16 20 26

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
# r389: 500 and not 1000 -- cached glyphs are 5 to 10 times cheaper (measured 784 and 680 on KVM);
# the factor depends on the host, "worth it" is what is asked
num "und der Speicher lohnt sich (Faktor mal 100)" \
    "$((kalt * 100 / (warm > 0 ? warm : 1)))" gt 500
lauf "$K0" "gfx wm nodirty ttfdump $GRUND" "$TMPD/nd.txt"
nvoll=$(grep -a 'wmbench: compose' "$TMPD/nd.txt" | grep -oE 'full=[0-9]+' | grep -oE '[0-9]+')
nklein=$(grep -a 'wmbench: compose' "$TMPD/nd.txt" | grep -oE 'small=[0-9]+' | grep -oE '[0-9]+')
echo "        without region tracking: full=$nvoll us  small=$nklein us"
if [ -n "$nklein" ] && [ -n "$klein" ] && [ "$nklein" -gt $((klein * 3)) ]; then
    ok "mit 'nodirty' kostet der kleine Bereich das Vielfache ($nklein statt $klein us)"
else
    bad "mit 'nodirty' aendert sich nichts: $nklein statt $klein us"
fi
has "$TMPD/nd.txt" "dirty=0" "und der Lauf sagt selbst, dass sie aus ist"

echo "== 12. the shell in the terminal window =="
foto "$K0" "gfx wm wmhold wmshell script=uname;echo hallo-fenster;exit $GRUND" \
    "$TMPD/sh.txt" "$TMPD/sh.ppm"
num "der Kern beendet sich sauber" "$RC" eq 21
has "$TMPD/sh.txt" "sh: ready, osum" "die Shell von der Platte ist gestartet"
has "$TMPD/sh.txt" "hallo-fenster" "die Shell hat geschrieben (seriell)"
she=$(grep -aoE 'wm: sh exit=[0-9]+' "$TMPD/sh.txt" | grep -oE '[0-9]+$')
num "und sich sauber beendet" "$she" eq 0
schau "die Kopfzeile des Terminalfensters steht im Bild" \
    tgrid "$TMPD/sh.ppm" assets/osum-mono.ttf 16 26 62 10 19 0 0 \
    224 230 236 16 20 26 "$MARKE_PRODUKT K10 WM 0123"
if grep -qa 'hallo-fenster' "$TMPD/sh.txt"; then
    gefunden=""
    for z in 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19; do
        if aus=$(python3 tools/gfx/checkshot.py tgrid "$TMPD/sh.ppm" \
            assets/osum-mono.ttf 16 26 62 10 19 "$z" 0 \
            224 230 236 16 20 26 "hallo-fenster" 2>&1); then
            gefunden="$z"; break
        fi
    done
    if [ -n "$gefunden" ]; then
        ok "the output of the shell is pixel-exact in row $gefunden of the window ($aus)"
    else
        bad "the output of the shell is in no row of the window"
    fi
fi

echo "== 12b. the line being typed is visible BEFORE Enter (26.09.2026) =="
# Justin on the Dell 9020: "I only see what I typed after pressing Enter".
# The console has ECHO off (the serial record), and the shell printed the
# line only after reading it. Now the shell sets ECHOWIN for its read and
# the kernel draws the edit line into the WINDOW only. Typed here WITHOUT
# Enter, then photographed: a row of the terminal must carry `xyzq`.
cat > "$TMPD/live.mon" <<'EOF'
warte 3
# the demo window holds the focus -- click into the terminal first
mouse_move -120 -120
mouse_move -120 -120
mouse_move -120 -120
mouse_move -120 -120
mouse_move 100 100
mouse_button 1
mouse_button 0
warte 1.5
sendkey x
warte 0.3
sendkey y
warte 0.3
sendkey z
warte 0.3
sendkey q
warte 2
EOF
FOTO_QUIT=1 foto "$K0" "gfx wm wmhold wmshell wmdauer nosched noproc nofs" "$TMPD/le.txt" "$TMPD/le.ppm" \
    "$TMPD/live.mon"
gefunden=""
fehlt=""
for ch in x y z q; do
    hit=""
    for z in 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19; do
        if python3 tools/gfx/checkshot.py tgrid "$TMPD/le.ppm" \
            assets/osum-mono.ttf 16 26 62 10 19 "$z" 0 \
            224 230 236 16 20 26 "$ch" >/dev/null 2>&1; then
            hit="$z"; break
        fi
    done
    if [ -n "$hit" ]; then gefunden="$gefunden$ch@$hit "; else fehlt="$fehlt$ch"; fi
done
if [ -z "$fehlt" ]; then
    ok "the typed line stands in the window before Enter (rows: $gefunden)"
else
    bad "the typed line 'xyzq' is not in the window before Enter (missing: $fehlt)"
    [ -n "${WM_KEEP:-}" ] && cp "$TMPD/le.ppm" "$TMPD/le.txt" "$WM_KEEP/" 2>/dev/null
    grep -a -E 'sh:|key:' "$TMPD/le.txt" | tail -8 | sed 's/^/        /'
fi
# The serial record is untouched: the window echo never goes onto the line.
hasnot "$TMPD/le.txt" "xyzq" "and the serial line carries no echo of it"

echo "== 13. THE CONTROLS: without 'wm' aendert sich nichts =="
lauf "$K0" "gfx $GRUND" "$TMPD/ohne.txt"
rc=$?
num "der Kern beendet sich sauber" "$rc" eq 21
has "$TMPD/ohne.txt" "wm: skipped" "ohne das Wort 'wm' faengt der Server gar nicht an"
hasnot "$TMPD/ohne.txt" "ttf: mono" "kein Zeichensatz wird gelesen"
hasnot "$TMPD/ohne.txt" "mouse: id=" "kein Zeigegeraet wird aufgesetzt"
hasnot "$TMPD/ohne.txt" "wclick:" "und kein Fenster in Ring 3"
has "$TMPD/ohne.txt" "fb: console mirrored to screen" \
    "die Textkonsole aus Runde K7 spiegelt wie vorher"
foto "$K0" "gfx wm wmhold nomouse $GRUND" "$TMPD/nm.txt" "$TMPD/nm.ppm"
has "$TMPD/nm.txt" "mouse: no pointer" "mit 'nomouse' gibt es kein Zeigegeraet"
has "$TMPD/nm.txt" "cursor=0" "und der Server malt keinen"
schau_nicht "im Bild steht an der Zeigerstelle KEIN Zeiger" \
    pixel "$TMPD/nm.ppm" 400 301 255 255 255
schau "das Terminalfenster steht trotzdem da" \
    tgrid "$TMPD/nm.ppm" assets/osum-mono.ttf 16 26 62 10 19 0 0 \
    224 230 236 16 20 26 "$MARKE_PRODUKT K10 WM 0123"
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
npi=$(grep -aoE 'irqs=[0-9]+' "$TMPD/k.txt" | tail -1 | sed 's/.*=//')
npp=$(grep -aoE 'polls=[0-9]+' "$TMPD/k.txt" | tail -1 | sed 's/.*=//')
nps=$(grep -aoE 'spurious=[0-9]+' "$TMPD/k.txt" | tail -1 | sed 's/.*=//')
echo "        in the regular run: irqs=$npi  of them empty=$nps  polled=$npp"
num "im Regellauf kommen Oktette auf BEIDEN Wegen an (Unterbrechungen)" \
    "$npi" gt 0

#
echo
echo "== 18. der Mauszeiger (Runde BLECH-HID) =="
if python3 tools/wm/cursor.py kernel/ui/wm/wmcursor.fi > "$TMPD/zeiger.txt" 2>&1; then
    ok "the pointer is an arrow: $(tail -1 "$TMPD/zeiger.txt" | sed 's/^ *//')"
else
    bad "the pointer is not an arrow"
fi
sed 's/^/       /' "$TMPD/zeiger.txt"

echo
if [ "$fail" -eq 0 ]; then
    echo "WM: $pass passed, 0 failed"
else
    echo "WM: $pass passed, $fail FAILED"
fi
[ "$fail" -eq 0 ]
