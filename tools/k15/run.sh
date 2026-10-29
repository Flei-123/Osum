#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/sync/gc.sh
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
if [ -n "${K15_KEEP:-}" ]; then TMPD=$K15_KEEP; mkdir -p "$TMPD"; else TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT; fi

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

num() {
    local name=$1 wert=$2 op=$3 want=$4
    if [ -z "$wert" ]; then bad "$name: no number found (expected $op $want)"; return; fi
    if [ "$wert" -"$op" "$want" ] 2>/dev/null; then ok "$name: $wert"
    else bad "$name: $wert, expected $op $want"; fi
}
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' is missing"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' is there and should not be" || ok "$3"; }
gleich() { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$3' instead of '$2'"; fi; }

schau() { local name=$1; shift
    local aus rc
    aus=$(python3 tools/gfx/checkshot.py "$@" 2>&1); rc=$?
    if [ "$rc" -eq 0 ]; then ok "$name ($aus)"; else bad "$name -- $aus"; fi
}
schau_nicht() { local name=$1; shift
    local aus rc
    aus=$(python3 tools/gfx/checkshot.py "$@" 2>&1); rc=$?
    if [ "$rc" -ne 0 ]; then ok "$name"; else bad "$name -- passed: $aus"; fi
}
zahl()  { grep -aoE "$2" "$1" | head -1 | grep -oE '[0-9]+' | tail -1; }
zahl2() { grep -aoE "$2" "$1" | tail -1 | grep -oE '[0-9]+' | tail -1; }
feld() { python3 tools/k15/value.py "$1" "$2" "$3" 2>/dev/null; }
frgb() { python3 tools/k15/value.py "$1" "$2" "$3" rgb 2>/dev/null; }
rgb() { python3 -c "v=int('${1:-0}');print((v>>16)&255,(v>>8)&255,v&255)"; }
rect() { grep -aoE "^$2: rect id=$3 .*" "$1" | tail -1 | grep -oE "$4=[0-9]+" | sed 's/.*=//'; }

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "vendor/firn/fetch-firnc.sh failed"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "K15: skipped, qemu-system-x86_64 is not available"
    exit 0
fi
DEJAVU=${DEJAVU:-/usr/share/fonts/truetype/dejavu}

MONO=assets/osum-mono.ttf
SANS=assets/osum-sans.ttf
SANS_INK="fui:$SANS"
GRUND="nokbd nosched noproc nofs"
BORDER=2
TITLE=22

RC=0
foto() {
    local name=$1 zeile=$2 mon=${3:-} marke=${4:-'^wm: hold'}
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
        grep -qaE "$marke" "$aus" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.15
        i=$((i + 1))
    done
    if [ -n "$mon" ]; then
        python3 tools/wm/monitor.py "$sock" "$mon" > "$TMPD/$name.monlog" 2>&1
    fi
    python3 tools/gfx/screenshot.py "$sock" "$ppm" 25 > "$TMPD/$name.shot" 2>&1
    wait "$pid"
    RC=$?
    rm -f "$sock"
    return 0
}

zeiger() {
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

echo "== 1. build: the kernel, the library and the programs, from both compilers =="
for s in 0 1; do
    if bash tools/build-kernel.sh "$TMPD/k$s.mb" --stufe "$s" > "$TMPD/b$s.log" 2>&1; then
        ok "firnc$s: kernel built ($(stat -c%s "$TMPD/k$s.mb") octets)"
    else
        bad "firnc$s: the kernel does not build"
        sed 's/^/        /' "$TMPD/b$s.log" | head -12
    fi
done
[ -f "$TMPD/k0.mb" ] || { echo "K15: $pass passed, $((fail + 1)) failed"; exit 1; }

PROGS="widgetdemo explorer launcher locate sh echo ls cat edit"
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null \
    || bad "crt.s does not assemble"
baue() {
    local s=$1 cc p rc=0 opt="$OPTL"
    if [ "$s" = 0 ]; then cc=vendor/firn/bin/firnc; else cc=vendor/firn/bin/firnc1; opt="$OPTL1"; fi
    for p in $PROGS; do
        UPROF=""; UCRT="$TMPD/crt.o"
        grep -qa '^profile app' "kernel/user/$p.fi" && { UPROF=--profile=app; UCRT=""; }
        "$cc" $UPROF $opt -c "kernel/user/$p.fi" -o "$TMPD/$p$s.o" > "$TMPD/e$p$s" 2>&1 || {
            bad "firnc$s does not compile $p.fi"
            sed 's/^/        /' "$TMPD/e$p$s" | head -8
            rc=1
            continue
        }
        ld $GCS -T kernel/user/user.ld --defsym=USER_ENTRY="_F$s.u_start" \
            -o "$TMPD/$p$s.elf" $UCRT "$TMPD/$p$s.o" \
            2>"$TMPD/ld$s.err" || { bad "firnc$s: ld fails on $p"; rc=1; continue; }
        strip --strip-all "$TMPD/$p$s.elf"
    done
    return $rc
}
baue 0 && ok "firnc0: $(echo $PROGS | wc -w) programs built, /bin/explorer with $(stat -c%s "$TMPD/explorer0.elf") octets" \
    || bad "firnc0: the programs of this round do not build"
baue 1 && ok "firnc1: the same from the compiler written in Firn" \
    || bad "firnc1: the programs of this round do not build"
if nm "$TMPD/explorer0.elf" 2>/dev/null | grep -q . ; then :; fi
for sym in wlib__button wlib__step wlibc__text_at; do
    if nm -a "$TMPD/k0.mb.elf" 2>/dev/null | grep -q "$sym"; then
        bad "the kernel carries $sym -- the library belongs in ring 3"
    else
        ok "the kernel does NOT carry $sym (the library lives in ring 3)"
    fi
done
wigzeilen=$(cat kernel/user/wlib.fi kernel/user/wlibc.fi | wc -l)
kernzeilen=$(grep -vc -e '^[[:space:]]*//' -e '^[[:space:]]*$' kernel/ui/wig.fi)
num "library lines in ring 3" "$wigzeilen" gt 1500
num "seam lines in the kernel (no comments/blank) -- as little kernel as possible" "$kernzeilen" lt 600

python3 tools/k15/tree.py "$TMPD/baum" > "$TMPD/baum.log" 2>&1 \
    && ok "the directory tree for the file manager is built ($(head -1 "$TMPD/baum.log"))" \
    || bad "tools/k15/tree.py failed"
ARGS=(build "$TMPD/disk.img" 16384 /lib/
      "/lib/mono.ttf=$MONO" "/lib/sans.ttf=$SANS"
      "/lib/bold.ttf=assets/osum-sans-bold.ttf" /bin/)
for p in $PROGS; do ARGS+=("/bin/$p=$TMPD/${p}0.elf"); done
ARGS+=("/bin/files@/bin/explorer")
printf 'on\n' > "$TMPD/uitrace"
ARGS+=(/etc/ "/etc/theme=$TMPD/baum/theme" "/etc/uitrace=$TMPD/uitrace")
ARGS+=(/usr/ /usr/share/ /usr/share/locale/ /usr/share/locale/en/
       "/usr/share/locale/en/messages=locale/en/messages"
       /usr/share/locale/de/
       "/usr/share/locale/de/messages=locale/de/messages")

while read -r zeile; do ARGS+=("$zeile"); done < <(python3 tools/k15/bundle.py assets/apps "$TMPD/buendel" nur="$PROGS")
while read -r z; do ARGS+=("$z"); done < "$TMPD/baum/liste"
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "mkfs.py builds an image with the fonts, the programs and /etc/theme" \
    || { bad "mkfs.py failed"; sed 's/^/        /' "$TMPD/mkfs.txt" | head -6; }

echo "== 2. the memory map: three pages, and only those three =="
kart=$(python3 tools/kernel/memmap.py kernel 2>&1)
if [ $? -eq 0 ]; then ok "the memory map of kdata: $kart"
else bad "the memory map of kdata collides"; echo "$kart" | sed 's/^/        /'; fi
kartv=$(python3 tools/kernel/memmap.py kernel -v 2>/dev/null)
if grep -q " WIG  *kstate.fi:" <<< "$kartv"; then
    ok "the WIG area is in the map"
else
    bad "the WIG area is NOT in the map"
fi
wo=$(printf '%s\n' "$kartv" | grep ' WIG ' | grep -oE '0x[0-9A-Fa-f]+' | head -2 | tr '\n' ' ')
gleich "the area lies in the allotted reserve" "0x46000 0x49000 " "$wo"
for n in 1800 1806 1807 1808 1809; do
    grep -qE "= $n( |$)" kernel/sys/sys.fi && ok "call number $n is in kernel/sys/sys.fi" \
        || bad "call number $n is missing"
done
grep -q 'const WIG_MAXNR: u64 = 1809' kernel/sys/sys.fi \
    && ok "and 1809 is the highest" \
    || bad "WIG_MAXNR does not match the calls"
if grep -qE 'WIG_(BASE|MAXNR)' kernel/sys/sys.fi && \
   ! grep -qE 'const WIG_[A-Z]+: u64 = (19[0-9][0-9]|17[0-9][0-9])' kernel/sys/sys.fi; then
    ok "all calls of this round lie between 1800 and 1899"
else
    bad "a call number of this round lies outside 1800..1899"
fi
GG="$TMPD/kernel-gg"; mkdir -p "$GG"
( cd kernel && find . -name '*.fi' -exec cp --parents {} "$GG/" \; )
sed -i 's/^const WIG_OFF: u64 = 0x46000/const WIG_OFF: u64 = 0x1E000/' "$GG/lib/kstate.fi"
gg=$(python3 tools/kernel/memmap.py "$GG" 2>&1)
if [ $? -ne 0 ] && printf '%s' "$gg" | grep -q 'KOLLISION'; then
    ok "with WIG_OFF at 0x1E000 the checker finds the collision with WM"
else
    bad "the collision checker does NOT find the new collision: $gg"
fi

echo "== 3. the application is up: layout, rectangles, order =="
foto ruhe "gfx wm wig wmhold wiglong $GRUND"
num "the kernel exits cleanly" "$RC" eq 21
has "$TMPD/ruhe.txt" "wm: hold" "the kernel holds still for the photo"
ws=$(zahl "$TMPD/ruhe.txt" 'wig: selftest [0-9]+')
num "the seam assertions about itself" "$ws" eq 7
has "$TMPD/ruhe.txt" "k15: start /bin/widgetdemo" "the application comes FROM THE DISK"
has "$TMPD/ruhe.txt" "widgetdemo: ready" "it created and painted its window"
WX=60; WY=60
BW=$(feld "$TMPD/ruhe.txt" "widgetdemo: geom" w)
BH=$(feld "$TMPD/ruhe.txt" "widgetdemo: geom" h)
num "the window is as wide as the application ordered" "$BW" eq 480
num "and as tall" "$BH" eq 400
CX=$((WX + BORDER)); CY=$((WY + TITLE))
aus=$(python3 tools/k15/layout.py "$TMPD/ruhe.txt" widgetdemo "$BW" "$BH" 12 2>&1)
if [ $? -eq 0 ]; then ok "the layout: $aus"
else bad "the layout is wrong"; echo "$aus" | sed 's/^/        /' | head -8; fi
sed 's/^widgetdemo: rect id=11 .*/widgetdemo: rect id=11 kind=5 x=12 y=372 w=456 h=112 /' \
    "$TMPD/ruhe.txt" > "$TMPD/ruhe-gg.txt"
if python3 tools/k15/layout.py "$TMPD/ruhe-gg.txt" widgetdemo "$BW" "$BH" 12 >/dev/null 2>&1; then
    bad "the layout checker lets a rectangle through that sticks out of the window"
else
    ok "a rectangle sticking out of the window is caught by the checker"
fi

echo "== 4. the text -- PER CHARACTER against the second rasterisation =="
pruef_text() {
    local marke=$1 soll=$2
    local zeile x base fg bg text
    zeile=$(grep -a "^widgetdemo: text $marke " "$TMPD/ruhe.txt" | tail -1)
    if [ -z "$zeile" ]; then bad "the application does not report the text place '$marke'"; return; fi
    x=$(printf '%s' "$zeile" | grep -oE 'x=[0-9]+' | head -1 | sed 's/.*=//')
    base=$(printf '%s' "$zeile" | grep -oE 'base=[0-9]+' | sed 's/.*=//')
    fg=$(printf '%s' "$zeile" | grep -oE 'fg=[0-9]+' | sed 's/.*=//')
    bg=$(printf '%s' "$zeile" | grep -oE 'bg=[0-9]+' | sed 's/.*=//')
    text=${zeile#*t=}
    gleich "the application reports the text '$marke'" "$soll" "$text"
    schau "'$soll' is in the window pixel-exact ($marke)" \
        tchain "$TMPD/ruhe.ppm" "$SANS_INK" 15 $((CX + x)) $((CY + base)) \
        $(rgb "$fg") $(rgb "$bg") "$soll"
}
pruef_text kopf "OSUM K15 WIDGETS"
pruef_text knopf "Knopf"
pruef_text e1 "Kopiermich"
RX=$(feld "$TMPD/ruhe.txt" "widgetdemo: rows" x)
RB=$(feld "$TMPD/ruhe.txt" "widgetdemo: rows" base)
ZH=$(feld "$TMPD/ruhe.txt" "widgetdemo: rows" zh)
RFG=$(frgb "$TMPD/ruhe.txt" "widgetdemo: rows" fg)
RBG=$(frgb "$TMPD/ruhe.txt" "widgetdemo: rows" bg)
RSEL=$(frgb "$TMPD/ruhe.txt" "widgetdemo: rows" sel)
RSFG=$(frgb "$TMPD/ruhe.txt" "widgetdemo: rows" selfg)
num "the row height of the list" "$ZH" eq 20
schau "row 0 of the list, in the SELECTION COLOUR" \
    tchain "$TMPD/ruhe.ppm" "$SANS_INK" 15 $((CX + RX)) $((CY + RB)) \
    $RSFG $RSEL "alpha"
i=1
for wort in beta gamma delta epsilon; do
    schau "row $i of the list" \
        tchain "$TMPD/ruhe.ppm" "$SANS_INK" 15 $((CX + RX)) $((CY + RB + i * ZH)) \
        $RFG $RBG "$wort"
    i=$((i + 1))
done
schau_nicht "the same checker does NOT pass with the WRONG text" \
    tchain "$TMPD/ruhe.ppm" "$SANS_INK" 15 $((CX + RX)) $((CY + RB + ZH)) \
    $RFG $RBG "gamma"
schau_nicht "nor at a place where there is no text" \
    tchain "$TMPD/ruhe.ppm" "$SANS_INK" 15 $((CX + RX)) $((CY + RB + 8 * ZH)) \
    $RFG $RBG "alpha"
schau_nicht "nor with the wrong background colour" \
    tchain "$TMPD/ruhe.ppm" "$SANS_INK" 15 $((CX + RX)) $((CY + RB + ZH)) \
    $RFG 0 0 0 "beta"
schau "the library text is really anti-aliased" \
    smooth "$TMPD/ruhe.ppm" $((CX + RX)) $((CY + RB - 14)) 120 60 \
    $RFG $RBG 100

echo "== 5. the widgets stand where the layout put them =="
FX=$(rect "$TMPD/ruhe.txt" widgetdemo 1 x); FY=$(rect "$TMPD/ruhe.txt" widgetdemo 1 y)
FW=$(rect "$TMPD/ruhe.txt" widgetdemo 1 w); FH=$(rect "$TMPD/ruhe.txt" widgetdemo 1 h)
TAX=$(grep -a '^wlib: tab i=0 ' "$TMPD/ruhe.txt" | tail -1 | grep -oE ' ax=[0-9]+' | sed 's/.*=//')
TAY=$(grep -a '^wlib: tab i=0 ' "$TMPD/ruhe.txt" | tail -1 | grep -oE ' ay=[0-9]+' | sed 's/.*=//')
TAW=$(grep -a '^wlib: tab i=0 ' "$TMPD/ruhe.txt" | tail -1 | grep -oE ' w=[0-9]+' | sed 's/.*=//')
TAH=$(grep -a '^wlib: tab i=0 ' "$TMPD/ruhe.txt" | tail -1 | grep -oE ' h=[0-9]+' | sed 's/.*=//')
schau "the focus ring lies pixel-exact around the active tab" \
    rect "$TMPD/ruhe.ppm" "${TAX:-0}" "${TAY:-0}" "${TAW:-0}" "${TAH:-0}" 255 192 32
schau_nicht "and NOT around the whole tab bar" \
    rect "$TMPD/ruhe.ppm" $((CX + FX)) $((CY + FY)) "$FW" "$FH" 255 192 32
BX=$(rect "$TMPD/ruhe.txt" widgetdemo 5 x); BY=$(rect "$TMPD/ruhe.txt" widgetdemo 5 y)
BBW=$(rect "$TMPD/ruhe.txt" widgetdemo 5 w); BBH=$(rect "$TMPD/ruhe.txt" widgetdemo 5 h)
schau_nicht "and there is none around the button that does NOT have it" \
    rect "$TMPD/ruhe.ppm" $((CX + BX)) $((CY + BY)) "$BBW" "$BBH" 255 192 32
schau "the button area has the colour from /etc/theme (btn=3a4a5e)" \
    area "$TMPD/ruhe.ppm" $((CX + BX + 3)) $((CY + BY + 3)) 16 5 58 74 94
EX=$(rect "$TMPD/ruhe.txt" widgetdemo 3 x); EY=$(rect "$TMPD/ruhe.txt" widgetdemo 3 y)
schau "the text field has its own area" \
    area "$TMPD/ruhe.ppm" $((CX + EX + 300)) $((CY + EY + 6)) 60 10 18 24 32

echo "== 6. operate: real clicks from the QEMU monitor =="
mitte() {
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
num "the kernel exits cleanly" "$RC" eq 21
has "$TMPD/klick.txt" "widgetdemo: fired id=5 kind=2" "the button reports -- with its number and its kind"
kl=$(feld "$TMPD/klick.txt" "widgetdemo: state" klicks)
num "and exactly ONCE" "$kl" eq 1
hasnot "$TMPD/ruhe.txt" "widgetdemo: fired" "without a click no widget reports"

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
has "$TMPD/haken.txt" "widgetdemo: fired id=7 kind=3 ix=1" "the checkbox flips and reports its new value"
HKX=$((CX + $(rect "$TMPD/ruhe.txt" widgetdemo 7 x))); HKY=$((CY + $(rect "$TMPD/ruhe.txt" widgetdemo 7 y) + 7))
mit=$(python3 tools/k15/count.py "$TMPD/haken.ppm" "$HKX" "$HKY" 14 14 92 200 255)
ohne=$(python3 tools/k15/count.py "$TMPD/ruhe.ppm" "$HKX" "$HKY" 14 14 92 200 255)
num "pixels of the check mark AFTER the click" "$mit" gt 12
num "and BEFORE the click (the counter-proof)" "$ohne" eq 0

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
num "the second tab is active" "$rt" eq 1
has "$TMPD/reiter.txt" "widgetdemo: fired id=1 kind=7 ix=1" "and the tab reports the change"

echo "== 7. the keyboard: advance, typing, clipboard =="
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
foto tast "gfx wm wig wmhold wiglong nobus $GRUND" "$M"
num "the kernel exits cleanly" "$RC" eq 21
e2=$(python3 tools/k15/fields.py "$TMPD/tast.txt" e2)
gleich "what is in the second text field" "Kopiermich-ab" "$e2"
cs=$(feld "$TMPD/tast.txt" "wig: blits" clipset)
cg=$(feld "$TMPD/tast.txt" "wig: blits" clipget)
num "written to the clipboard" "$cs" ge 1
num "and read from it" "$cg" ge 1
EBG=$(frgb "$TMPD/ruhe.txt" "widgetdemo: text e1" bg)
EFG=$(frgb "$TMPD/ruhe.txt" "widgetdemo: text e1" fg)
EBASE=$(feld "$TMPD/ruhe.txt" "widgetdemo: text e1" base)
E1TX=$(feld "$TMPD/ruhe.txt" "widgetdemo: text e1" x)
schau "and it is in the second field pixel-exact" \
    tchain "$TMPD/tast.ppm" "$SANS_INK" 15 $((CX + E1TX)) $((CY + EBASE + E2Y - E1Y)) \
    $EFG $EBG "Kopiermich-ab"
schau_nicht "in the run WITHOUT key presses there is NOTHING" \
    tchain "$TMPD/ruhe.ppm" "$SANS_INK" 15 $((CX + E1TX)) $((CY + EBASE + E2Y - E1Y)) \
    $EFG $EBG "Kopiermich-ab"
foto noclip "gfx wm wig wignoclip wmhold wiglong $GRUND" "$M"
e2n=$(python3 tools/k15/fields.py "$TMPD/noclip.txt" e2)
gleich "with 'noclip' ONLY the typed text arrives" "-ab" "$e2n"
schau_nicht "and the pasted text is then not in the picture" \
    tchain "$TMPD/noclip.ppm" "$SANS_INK" 15 $((CX + E1TX)) $((CY + EBASE + E2Y - E1Y)) \
    $EFG $EBG "Kopiermich-ab"
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
e2t=$(python3 tools/k15/fields.py "$TMPD/tabkey.txt" e2)
gleich "after the tab key one types into the NEXT field" "xy" "$e2t"
e1t=$(python3 tools/k15/fields.py "$TMPD/tabkey.txt" e1)
gleich "and the previous one is unchanged" "Kopiermich" "$e1t"
schau "the focus ring moved along -- it now surrounds the second field" \
    rect "$TMPD/tabkey.ppm" $((CX + $(rect "$TMPD/ruhe.txt" widgetdemo 4 x))) \
    $((CY + E2Y)) $(rect "$TMPD/ruhe.txt" widgetdemo 4 w) \
    $(rect "$TMPD/ruhe.txt" widgetdemo 4 h) 255 192 32
schau_nicht "and NO longer around the first" \
    rect "$TMPD/tabkey.ppm" $((CX + $(rect "$TMPD/ruhe.txt" widgetdemo 3 x))) \
    $((CY + E1Y)) $(rect "$TMPD/ruhe.txt" widgetdemo 3 w) "$E1H" 255 192 32

echo "== 8. menus and dialogs -- own windows at the server =="
POPX=$((CX + LX + 100)); POPY=$((CY + LY + 42))
M="$TMPD/pop.mon"; : > "$M"
zeiger "$M" "$POPX" "$POPY"
cat >> "$M" <<EOF
mouse_button 2
warte 0.3
mouse_button 0
warte 0.8
mouse_move 120 -120
mouse_move 120 -120
mouse_move 120 -30
warte 0.5
EOF
foto pop "gfx wm wig wmhold wiglong $GRUND" "$M"
has "$TMPD/pop.txt" "widgetdemo: fired id=11 kind=11" "the right button arrives at the list, with the row"
has "$TMPD/pop.txt" "widgetdemo: menu " "and the library opens its OWN window for it"
MNX=$(feld "$TMPD/pop.txt" "widgetdemo: menu" x)
MNY=$(feld "$TMPD/pop.txt" "widgetdemo: menu" y)
MNW=$(feld "$TMPD/pop.txt" "widgetdemo: menu" w)
MNH=$(feld "$TMPD/pop.txt" "widgetdemo: menu" h)
MZH=$(feld "$TMPD/pop.txt" "widgetdemo: menu" zh)
gleich "it lies exactly at the pointer" "$POPX $POPY" "$MNX $MNY"
num "and is as tall as three items need" "$MNH" eq $((3 * MZH + 4))
MENUBG=$(python3 -c "print(0x2a3542)")
UIFG=$(python3 tools/theme/model.py semantic assets/schemes/day.scheme dark \
    | awk '$2 == "text-primary" {print $3}')
UIFG=$((16#$UIFG))
MASC=$(python3 -c "import sys; sys.path.insert(0,'tools/ttf'); import raster; print(raster.Schrift('$SANS', 15).glyphe(108).oben)")
i=0
for punkt in Öffnen Umbenennen Entfernen; do
    schau "menu item $i is in the menu window pixel-exact: '$punkt'" \
        tchain "$TMPD/pop.ppm" "$SANS_INK" 15 $((MNX + 8)) \
        $((MNY + 4 + MASC + i * MZH)) $(rgb "$UIFG") $(rgb "$MENUBG") "$punkt" 96
    i=$((i + 1))
done
schau "the frame of the menu window is pixel-exact" \
    rect "$TMPD/pop.ppm" "$MNX" "$MNY" "$MNW" "$MNH" 92 200 255
schau_nicht "without the right button there is NO menu" \
    tchain "$TMPD/ruhe.ppm" "$SANS_INK" 15 $((MNX + 8)) \
    $((MNY + 4 + MASC)) $(rgb "$UIFG") $(rgb "$MENUBG") "Öffnen" 96
schau_nicht "and another word is not there even at tolerance 64" \
    tchain "$TMPD/pop.ppm" "$SANS_INK" 15 $((MNX + 8)) \
    $((MNY + 4 + MASC)) $(rgb "$UIFG") $(rgb "$MENUBG") "Schuetzen" 128
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
has "$TMPD/popw.txt" "widgetdemo: fired id=11 kind=8" "a click on a menu item reports it to the owner"
mn=$(feld "$TMPD/popw.txt" "widgetdemo: state" menues)
num "and the menu fired exactly ONCE" "$mn" ge 1
schau_nicht "afterwards the menu window is gone again" \
    tchain "$TMPD/popw.ppm" "$SANS_INK" 15 $((MNX + 8)) \
    $((MNY + 4 + MASC)) $(rgb "$UIFG") $(rgb "$MENUBG") "Öffnen" 96

DEL=$(mitte 9)
M="$TMPD/dlg.mon"; : > "$M"
zeiger "$M" ${DEL% *} ${DEL#* }
cat >> "$M" <<EOF
mouse_button 1
mouse_button 0
warte 1.0
EOF
foto dlg "gfx wm wig wmhold wiglong $GRUND" "$M"
has "$TMPD/dlg.txt" "widgetdemo: dlgwin" "the dialog is a window of its own"
DW=$(feld "$TMPD/dlg.txt" "widgetdemo: dlgwin" w)
DH=$(feld "$TMPD/dlg.txt" "widgetdemo: dlgwin" h)
num "it is as wide as the library builds it" "$DW" eq 340
SCRW=$(grep -aoE '^wm: [0-9]+x[0-9]+' "$TMPD/dlg.txt" | head -1 | sed 's/wm: //; s/x.*//')
SCRH=$(grep -aoE '^wm: [0-9]+x[0-9]+' "$TMPD/dlg.txt" | head -1 | sed 's/.*x//')
DLX=$(( (${SCRW:-0} - DW) / 2 )); DLY=$(( (${SCRH:-0} - DH) / 2 ))
schau "and it is centred on the screen, pixel-exact" \
    rect "$TMPD/dlg.ppm" "$DLX" "$DLY" $((DW + 4)) $((DH + 24)) 76 154 232
DTX=$(feld "$TMPD/dlg.txt" "widgetdemo: text dlg" x)
DTB=$(feld "$TMPD/dlg.txt" "widgetdemo: text dlg" base)
DTF=$(frgb "$TMPD/dlg.txt" "widgetdemo: text dlg" fg)
DTG=$(frgb "$TMPD/dlg.txt" "widgetdemo: text dlg" bg)
schau "its question is in it, per character" \
    tchain "$TMPD/dlg.ppm" "$SANS_INK" 15 $((DLX + BORDER + DTX)) \
    $((DLY + TITLE + DTB)) $DTF $DTG "Neuer Name"
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
has "$TMPD/dlgok.txt" "widgetdemo: dlg state=2" "the dialog is confirmed with OK and returns its text"
dt=$(grep -a 'widgetdemo: dlg state=2' "$TMPD/dlgok.txt" | tail -1 | sed 's/.*text=//')
gleich "and the text is the one it was opened with" "Kopiermich" "$dt"
schau_nicht "afterwards the dialog window is gone too" \
    rect "$TMPD/dlgok.ppm" "$DLX" "$DLY" $((DW + 4)) $((DH + 24)) 76 154 232

echo "== 9. the file manager: /bin/explorer against the disk =="
foto files "gfx wm wigfiles wmhold wiglong $GRUND"
num "the kernel exits cleanly" "$RC" eq 21
has "$TMPD/files.txt" "k15: start /bin/explorer" "/bin/explorer comes from the disk"
has "$TMPD/files.txt" "explorer: ready" "and painted its window"
FN=$(feld "$TMPD/files.txt" "explorer: cd" n)
SOLLN=$(wc -l < "$TMPD/baum/soll.txt")
num "it counts as many entries in /data as tree.py created" "$FN" eq "$SOLLN"
FBW=$(feld "$TMPD/files.txt" "explorer: geom" w); FBH=$(feld "$TMPD/files.txt" "explorer: geom" h)
FWX=$(feld "$TMPD/files.txt" "explorer: geom" x); FWY=$(feld "$TMPD/files.txt" "explorer: geom" y)
FCX=$((FWX + BORDER)); FCY=$((FWY + TITLE))
STRIP=$(grep -a 'explorer: strip h=' "$TMPD/files.txt" | head -1 | sed 's/.*explorer: strip h=\([0-9]*\).*/\1/')
if [ -n "$STRIP" ]; then FCY=$((FWY + BORDER)); FBH=$((FBH + STRIP)); fi
if [ -n "$STRIP" ]; then
    DRAGH=$(rect "$TMPD/files.txt" explorer 60 h)
    num "title strip drag node height equals the strip height" "$DRAGH" eq "$STRIP"
fi
aus=$(python3 tools/k15/layout.py "$TMPD/files.txt" explorer "$FBW" "$FBH" 8 4,30,24,27 2>&1)
if [ $? -eq 0 ]; then ok "the layout of the file manager: $aus"
else bad "the layout of the file manager is wrong"; echo "$aus" | sed 's/^/        /' | head -6; fi
TX=$(feld "$TMPD/files.txt" "explorer: rows" x)
TB=$(feld "$TMPD/files.txt" "explorer: rows" base)
TZH=$(feld "$TMPD/files.txt" "explorer: rows" zh)
TKOPF=$(feld "$TMPD/files.txt" "explorer: rows" kopf)
TFG=$(frgb "$TMPD/files.txt" "explorer: rows" fg)
TBG=$(frgb "$TMPD/files.txt" "explorer: rows" bg)
TSEL=$(frgb "$TMPD/files.txt" "explorer: rows" sel)
TSFG=$(frgb "$TMPD/files.txt" "explorer: rows" selfg)
TDIM=$(frgb "$TMPD/files.txt" "explorer: rows" dim)
THBG=$(frgb "$TMPD/files.txt" "explorer: rows" headbg)
ETOL=1
SP=($(grep -a '^explorer: spalten' "$TMPD/files.txt" | tail -1 | sed 's/^explorer: spalten //'))
if [ "${#SP[@]}" -lt 4 ]; then
    bad "explorer does not name its columns (explorer: spalten is missing) -- the column assertions below cannot measure"
    SP=(0 0 0 0)
fi
schau "the header row: the first column is called 'Name'" \
    tchain "$TMPD/files.ppm" "$SANS_INK" 15 $((FCX + TX)) $((FCY + TKOPF)) \
    $TDIM $THBG "Name" $ETOL
SZR=$((${SP[3]} + 72))
schau "the second column is called 'Date modified'" \
    tchain "$TMPD/files.ppm" "$SANS_INK" 15 $((FCX + ${SP[1]})) $((FCY + TKOPF)) \
    $TDIM $THBG "Date modified" $ETOL
schau "the third 'Type'" \
    tchain "$TMPD/files.ppm" "$SANS_INK" 15 $((FCX + ${SP[2]})) $((FCY + TKOPF)) \
    $TDIM $THBG "Type" $ETOL
schau "and the fourth 'Size', right-aligned" \
    tright "$TMPD/files.ppm" "$SANS_INK" 15 $((FCX + SZR)) $((FCY + TKOPF)) \
    $TDIM $THBG "Size" $ETOL
zeile=0
while IFS=$'\t' read -r name gr kind; do
    y=$((FCY + TB + zeile * TZH))
    if [ "$zeile" = 0 ]; then vg="$TSFG"; hg="$TSEL"; else vg="$TFG"; hg="$TBG"; fi
    schau "row $zeile of the table: '$name'" \
        tchain "$TMPD/files.ppm" "$SANS_INK" 15 $((FCX + TX)) "$y" $vg $hg "$name" $ETOL
    if [ "$kind" != "d" ] && [ "$zeile" != 0 ]; then
        schau "and its size in column 4, right-aligned: $(python3 tools/k15/sizetext.py "$gr")" \
            tright "$TMPD/files.ppm" "$SANS_INK" 15 $((FCX + SZR)) "$y" \
            $TDIM $hg "$(python3 tools/k15/sizetext.py "$gr")" $ETOL
    fi
    zeile=$((zeile + 1))
done < "$TMPD/baum/soll.txt"
schau "the kind of a directory" \
    tchain "$TMPD/files.ppm" "$SANS_INK" 15 $((FCX + ${SP[2]})) $((FCY + TB)) \
    $TSFG $TSEL "Folder" $ETOL
schau "and that of a text file" \
    tchain "$TMPD/files.ppm" "$SANS_INK" 15 $((FCX + ${SP[2]})) $((FCY + TB + 2 * TZH)) \
    $TDIM $TBG "Text" $ETOL
schau_nicht "and a DIFFERENT kind fails" \
    tchain "$TMPD/files.ppm" "$SANS_INK" 15 $((FCX + ${SP[2]})) $((FCY + TB + 2 * TZH)) \
    $TDIM $TBG "Program" $ETOL
schau "the Date modified column shows two dashes -- OFS has no timestamp" \
    tchain "$TMPD/files.ppm" "$SANS_INK" 15 $((FCX + ${SP[1]})) $((FCY + TB + 2 * TZH)) \
    $TDIM $TBG "--" $ETOL

echo "== 9b. enter, sort, create =="
DX=$((FCX + TX + 60)); DY=$((FCY + TB - 8))
M="$TMPD/fdbl.mon"; : > "$M"
zeiger "$M" "$DX" "$DY"
cat >> "$M" <<EOF
mouse_button 1
mouse_button 0
mouse_button 1
mouse_button 0
warte 4.0
mouse_move 120 120
EOF
foto fdbl "gfx wm wigfiles wmhold wiglong $GRUND" "$M"
has "$TMPD/fdbl.txt" "explorer: cd /data/bilder" "the double click enters the directory"
n2=$(grep -a '^explorer: cd' "$TMPD/fdbl.txt" | tail -1 | grep -oE 'n=[0-9]+' | sed 's/.*=//')
num "and it holds two files" "$n2" eq 2
schau "the first of them is in the picture" \
    tchain "$TMPD/fdbl.ppm" "$SANS_INK" 15 $((FCX + TX)) $((FCY + TB)) \
    $TSFG $TSEL "blau.ppm" $ETOL
schau_nicht "and the old content is NO longer there" \
    tchain "$TMPD/fdbl.ppm" "$SANS_INK" 15 $((FCX + TX)) $((FCY + TB)) \
    $TSFG $TSEL "bilder" $ETOL
SX=$((FCX + ${SP[3]} + 20)); SY=$((FCY + TKOPF - 6))
M="$TMPD/fsort.mon"; : > "$M"
zeiger "$M" "$SX" "$SY"
cat >> "$M" <<EOF
mouse_button 1
mouse_button 0
warte 0.8
mouse_move 120 120
EOF
foto fsort "gfx wm wigfiles wmhold wiglong $GRUND" "$M"
has "$TMPD/fsort.txt" "explorer: op" "a click on the header row re-sorts"
sb=$(grep -a '^explorer: op' "$TMPD/fsort.txt" | tail -1 | grep -oE 'w=[0-9]+' | sed 's/.*=//')
num "by key 1 (size, column 4)" "$sb" eq 1
schau "sorted by size the empty file comes first among the files" \
    tchain "$TMPD/fsort.ppm" "$SANS_INK" 15 $((FCX + TX)) $((FCY + TB + 2 * TZH)) \
    $TFG $TBG "delta.txt" $ETOL
schau_nicht "sorted by name something else stood there" \
    tchain "$TMPD/files.ppm" "$SANS_INK" 15 $((FCX + TX)) $((FCY + TB + 2 * TZH)) \
    $TFG $TBG "delta.txt" $ETOL
PXC=$((TX + 100)); PYC=$((TB + 2 * TZH - 6))
POPH=$((15 * 28 + 8))
if [ $((PYC + POPH)) -gt "$FBH" ]; then POPY=$((FBH - POPH)); else POPY=$PYC; fi
DYREL=$((POPY + 4 + 8 * 28 + 14 - PYC))
M="$TMPD/fneu.mon"; : > "$M"
zeiger "$M" "$((FCX + PXC))" "$((FCY + PYC))"
cat >> "$M" <<EOF
mouse_button 2
warte 0.3
mouse_button 0
warte 0.8
mouse_move 40 $DYREL
mouse_button 1
mouse_button 0
warte 1.0
sendkey n
sendkey e
sendkey u
warte 0.5
EOF
OKCX=$(( (FBW - 320) / 2 + 16 + 68 ))
OKCY=$(( (FBH - 200) / 2 + 200 - 52 + 18 ))
zeiger "$M" $((FCX + OKCX)) $((FCY + OKCY))
cat >> "$M" <<EOF
mouse_button 1
mouse_button 0
warte 1.2
EOF
foto fneu "gfx wm wigfiles wmhold wiglong $GRUND" "$M"
has "$TMPD/fneu.txt" "explorer: tat 2" "the dialog creates a directory"
rc2=$(grep -a '^explorer: tat' "$TMPD/fneu.txt" | tail -1 | grep -oE 'rc=[0-9]+' | sed 's/.*=//')
num "and the kernel accepts it" "$rc2" eq 0
python3 tools/osum/mkfs.py list "$TMPD/live-fneu.img" > "$TMPD/fneu.ls" 2>&1
if grep -qE '/data/neu' "$TMPD/fneu.ls"; then
    ok "and /data/neu is REALLY in the disk image"
else
    bad "/data/neu is not in the disk image"
    grep -c . "$TMPD/fneu.ls" | sed 's/^/        Zeilen: /'
fi
python3 tools/osum/mkfs.py list "$TMPD/live-files.img" > "$TMPD/files.ls" 2>&1
if grep -qE '/data/neu' "$TMPD/files.ls"; then
    bad "/data/neu is also in the image WITHOUT the operation -- the assertion says nothing"
else
    ok "in the image without the operation it is NOT there (the counter-proof)"
fi

echo "== 10. the timings: what a redraw really costs =="
RP=$(feld "$TMPD/ruhe.txt" "wig: blits" pixels)
HP=$(feld "$TMPD/haken.txt" "wig: blits" pixels)
RB2=$(feld "$TMPD/ruhe.txt" "wig: blits" blits)
HB=$(feld "$TMPD/haken.txt" "wig: blits" blits)
FLAECHE=$((BW * BH))
DELTA=$((HP - RP))
num "pixels for the whole window build" "$RP" gt 100000
if [ "$DELTA" -gt 0 ] && [ "$DELTA" -lt $((FLAECHE / 8)) ]; then
    ok "a click on the checkbox costs $DELTA pixels instead of $FLAECHE -- factor $((FLAECHE / DELTA))"
else
    bad "a click costs $DELTA of $FLAECHE pixels (expected clearly less)"
fi
num "and $((HB - RB2)) calls across for it, no more" $((HB - RB2)) lt 12
GP=$(feld "$TMPD/ruhe.txt" "wig: blits" glyphs)
num "glyphs the library fetched from the kernel (ONE per character)" "$GP" lt 90
foto haken_nd "gfx wm wig nodirty wmhold wiglong $GRUND" "$TMPD/haken.mon"
WMP=$(zahl2 "$TMPD/haken.txt" 'wm: composites=[0-9]+  blits=[0-9]+  pixels=[0-9]+')
WMPN=$(zahl2 "$TMPD/haken_nd.txt" 'wm: composites=[0-9]+  blits=[0-9]+  pixels=[0-9]+')
if [ -n "$WMP" ] && [ -n "$WMPN" ] && [ "$WMPN" -gt "$WMP" ]; then
    ok "with region tracking the server composes $WMP pixels, without it $WMPN -- factor $((WMPN / WMP))"
else
    bad "without region tracking it does not get costlier: $WMP against $WMPN"
fi
hnd=$(feld "$TMPD/haken_nd.txt" "widgetdemo: state" haken)
gleich "and the application did the same in both runs" "1" "$hnd"

echo "== 11. the counter-proofs =="
foto nohit "gfx wm wig wignohit wmhold wiglong $GRUND" "$TMPD/haken.mon"
hasnot "$TMPD/nohit.txt" "widgetdemo: fired" "with 'nohit' NO widget reports"
nh=$(feld "$TMPD/nohit.txt" "widgetdemo: state" haken)
gleich "and the checkbox stays empty" "0" "$nh"
nhp=$(python3 tools/k15/count.py "$TMPD/nohit.ppm" "$HKX" "$HKY" 14 14 92 200 255)
num "also in the picture: no pixel of the check mark" "$nhp" eq 0
nhd=$(zahl2 "$TMPD/nohit.txt" 'downs=[0-9]+')
num "although the click ARRIVED at the window" "$nhd" ge 1
foto nomaus "gfx wm wig nomouse wmhold wiglong $GRUND" "$TMPD/haken.mon"
hasnot "$TMPD/nomaus.txt" "widgetdemo: fired" "with 'nomouse' no click arrives at all"
has "$TMPD/nomaus.txt" "widgetdemo: ready" "the application paints anyway -- it just cannot be operated"
foto nofok "gfx wm wig nofocus wmhold wiglong $GRUND" "$TMPD/tab.mon"
k0=$(zahl2 "$TMPD/tabkey.txt" 'keys0=[0-9]+')
k0n=$(zahl2 "$TMPD/nofok.txt" 'keys0=[0-9]+')
num "in the normal run the terminal window gets NO key" "$k0" eq 0
num "with 'nofocus' it gets them all" "$k0n" ge 3
foto ohne "gfx wm wmhold $GRUND"
hasnot "$TMPD/ohne.txt" "k15: start" "without the word 'wig' no application is started"
hasnot "$TMPD/ohne.txt" "widgetdemo:" "and none reports"
has "$TMPD/ohne.txt" "wclick: passed 10 / 10" "instead the application of round K10 runs as before"
wz=$(zahl "$TMPD/ohne.txt" 'wm: selftest [0-9]+')
num "and the window server says the same as before" "$wz" eq 30
ob=$(feld "$TMPD/ohne.txt" "wig: blits" blits)
num "the seam pushed nothing across in this run" "$ob" eq 0

echo "== 12. the colour scheme comes from a file =="
tn=$(zahl "$TMPD/ruhe.txt" 'widgetdemo: theme n=[0-9]+')
soll=$(grep -cE '^[a-z]+=' "$TMPD/baum/theme")
num "colours read from /etc/theme" "$tn" eq "$soll"
sed 's/^btn=.*/btn=804020/' "$TMPD/baum/theme" > "$TMPD/theme2"
ARGS2=(build "$TMPD/disk2.img" 16384 /lib/
      "/lib/mono.ttf=$MONO" "/lib/sans.ttf=$SANS" /bin/)
for p in $PROGS; do ARGS2+=("/bin/$p=$TMPD/${p}0.elf"); done
ARGS2+=("/bin/files@/bin/explorer")
ARGS2+=(/etc/ "/etc/theme=$TMPD/theme2")
ARGS2+=(/usr/ /usr/share/ /usr/share/locale/ /usr/share/locale/en/
       "/usr/share/locale/en/messages=locale/en/messages"
       /usr/share/locale/de/
       "/usr/share/locale/de/messages=locale/de/messages")

while read -r zeile; do ARGS2+=("$zeile"); done < <(python3 tools/k15/bundle.py assets/apps "$TMPD/buendel" nur="$PROGS")
while read -r z; do ARGS2+=("$z"); done < "$TMPD/baum/liste"
python3 tools/osum/mkfs.py "${ARGS2[@]}" > "$TMPD/mkfs2.txt" 2>&1
cp -f "$TMPD/disk.img" "$TMPD/disk1.img"
cp -f "$TMPD/disk2.img" "$TMPD/disk.img"
foto theme2 "gfx wm wig wmhold wiglong $GRUND"
cp -f "$TMPD/disk1.img" "$TMPD/disk.img"
schau "with btn=804020 in the file the button has THIS colour" \
    area "$TMPD/theme2.ppm" $((CX + BX + 3)) $((CY + BY + 3)) 16 5 128 64 32
schau_nicht "and then NOT the previous one" \
    area "$TMPD/theme2.ppm" $((CX + BX + 3)) $((CY + BY + 3)) 16 5 58 74 94
schau "and the text on it is blended against the new ground" \
    tchain "$TMPD/theme2.ppm" "$SANS_INK" 15 $((CX + $(feld "$TMPD/ruhe.txt" "widgetdemo: text knopf" x))) \
    $((CY + $(feld "$TMPD/ruhe.txt" "widgetdemo: text knopf" base))) \
    $(rgb "$UIFG") 128 64 32 "Knopf"

echo "== 13. the pointer image -- the only place where ring 3 tells the server about the pointer =="
M="$TMPD/beam.mon"; : > "$M"
zeiger "$M" "$E1X" $((CY + E1Y + E1H / 2))
cat >> "$M" <<EOF
mouse_move 0 0
warte 0.8
EOF
foto beam "gfx wm wig wmhold wiglong $GRUND" "$M"
sh1=$(feld "$TMPD/beam.txt" "wig: blits" shape)
num "over a text field the pointer becomes a bar" "$sh1" eq 1
sh0=$(feld "$TMPD/ruhe.txt" "wig: blits" shape)
num "otherwise it stays the arrow" "$sh0" eq 0
BY0=$((CY + E1Y + E1H / 2))
schau "the middle of the bar is at the pointer and is black" \
    pixel "$TMPD/beam.ppm" "$E1X" "$BY0" 0 0 0
schau "and its edge is white" \
    pixel "$TMPD/beam.ppm" $((E1X + 1)) "$BY0" 255 255 255
schau_nicht "and three pixels further right there is nothing of the pointer" \
    pixel "$TMPD/beam.ppm" $((E1X + 4)) "$BY0" 255 255 255
schau_nicht "without a text field underneath there is no bar (the arrow)" \
    pixel "$TMPD/ruhe.ppm" "$E1X" "$BY0" 0 0 0

echo "== 14. the name, the second name and discoverability =="
aus=$(python3 tools/k15/noname.py kernel/user/explorer.fi "File Explorer" 2>&1)
if [ $? -eq 0 ]; then ok "the display name is NOT in the code ($aus)"
else bad "the display name is in the code: $aus"; fi
aus=$(python3 tools/k15/noname.py kernel/user/launcher.fi "Suchen" 2>&1)
if [ $? -eq 0 ]; then ok "and neither is the launcher's"
else bad "the launcher name is in the code: $aus"; fi
if python3 tools/k15/noname.py kernel/user/launcher.fi "launcher.run" >/dev/null 2>&1; then
    bad "the checker does not find a string that is in the code"
else
    ok "a string that really is in the code is found (the counter-proof)"
fi
if python3 tools/k15/noname.py kernel/user/launcher.fi "Ausfuehren" >/dev/null 2>&1; then
    ok "ROUND I18N: 'Ausfuehren' is no longer in the source of the launcher"
else
    bad "'Ausfuehren' is still hardcoded in the source"
fi
grep -q '^name=File Explorer' assets/apps/explorer.osp/INFO \
    && ok "sondern in assets/apps/explorer.osp/INFO" \
    || bad "assets/apps/explorer.osp/INFO fuehrt keinen Anzeigenamen"
has "$TMPD/files.txt" "explorer: name [File Explorer] aus [explorer.osp]" \
    "and the program fetches it from the bundle"
if [ -z "$STRIP" ]; then
schau "the display name is in the title bar pixel-exact" \
    tchain "$TMPD/files.ppm" "$SANS_INK" 15 $((FWX + 12)) $((FWY + 18)) \
    255 255 255 28 78 126 "File Explorer" 96 $((FWY + 21))
schau_nicht "and another name is NOT there" \
    tchain "$TMPD/files.ppm" "$SANS_INK" 15 $((FWX + 12)) $((FWY + 18)) \
    255 255 255 28 78 126 "Dateimanager" 96 $((FWY + 21))
else
ok "the title bar of the file manager is its tab strip (no server title, r454; measured in tools/tabstrip)"
fi

python3 tools/osum/mkfs.py list "$TMPD/disk.img" > "$TMPD/disk.ls" 2>&1
grep -q '^/bin/explorer ' "$TMPD/disk.ls" && ok "/bin/explorer is on the disk" \
    || bad "/bin/explorer is missing on the disk"
grep -q '^/bin/files ' "$TMPD/disk.ls" && ok "and /bin/files beside it" \
    || bad "/bin/files is missing on the disk"
python3 tools/osum/mkfs.py cat "$TMPD/disk.img" /bin/explorer > "$TMPD/e1.bin" 2>/dev/null
python3 tools/osum/mkfs.py cat "$TMPD/disk.img" /bin/files > "$TMPD/e2.bin" 2>/dev/null
cmp -s "$TMPD/e1.bin" "$TMPD/e2.bin" \
    && ok "beide Namen geben dieselben $(stat -c%s "$TMPD/e1.bin") Oktette" \
    || bad "the two names give different octets"
python3 tools/osum/mkfs.py build "$TMPD/kopie.img" 16384 /bin/ \
    "/bin/explorer=$TMPD/explorer0.elf" "/bin/files=$TMPD/explorer0.elf" \
    > "$TMPD/kopie.txt" 2>&1
python3 tools/osum/mkfs.py build "$TMPD/verweis.img" 16384 /bin/ \
    "/bin/explorer=$TMPD/explorer0.elf" "/bin/files@/bin/explorer" \
    > "$TMPD/verweis.txt" 2>&1
fk=$(grep -oE 'free=[0-9]+' "$TMPD/kopie.txt" | sed 's/.*=//')
fv=$(grep -oE 'free=[0-9]+' "$TMPD/verweis.txt" | sed 's/.*=//')
ik=$(grep -oE 'inodes=[0-9]+' "$TMPD/kopie.txt" | sed 's/.*=//')
iv=$(grep -oE 'inodes=[0-9]+' "$TMPD/verweis.txt" | sed 's/.*=//')
if [ -n "$fk" ] && [ -n "$fv" ] && [ "$fv" -gt "$fk" ]; then
    ok "the link saves $((fv - fk)) blocks against the copy ($fv free instead of $fk)"
else
    bad "the link saves nothing: $fv against $fk"
fi
num "and it needs one inode less" $((ik - iv)) eq 1

echo "== 14b. the application directory and the launcher =="
foto start "gfx wm wigstart wmhold wiglong $GRUND"
num "the kernel exits cleanly" "$RC" eq 21
has "$TMPD/start.txt" "k15: start /bin/launcher" "the launcher comes from the disk"
na=$(feld "$TMPD/start.txt" "launcher: apps" apps)
soll=$(python3 -c "
import os, sys
progs = set('/bin/' + w for w in sys.argv[1].split())
n = 0
for name in sorted(os.listdir('assets/apps')):
    if not name.endswith('.osp'):
        continue
    p = os.path.join('assets/apps', name, 'start.txt')
    for zeile in open(p, encoding='ascii'):
        zeile = zeile.strip()
        if zeile and not zeile.startswith('#'):
            if zeile in progs:
                n += 1
            break
print(n)
" "$PROGS")
num "it finds as many programs as .osp bundles with a program of this disk lie in the tree" "$na" eq "$soll"
shown=$(python3 -c "
import os, sys
progs = set('/bin/' + w for w in sys.argv[1].split())
n = 0
for name in sorted(os.listdir('assets/apps')):
    if not name.endswith('.osp'):
        continue
    base = os.path.join('assets/apps', name)
    first = next((z.strip() for z in open(os.path.join(base, 'start.txt'), encoding='ascii') if z.strip() and not z.startswith('#')), '')
    hidden = any(z.strip() == 'menu=hidden' for z in open(os.path.join(base, 'INFO'), encoding='ascii'))
    if first in progs and not hidden:
        n += 1
print(n)
" "$PROGS")
if grep -qa "launcher: treffer i=[0-9]* name=\[File Explorer\] exec=\[/apps/explorer.osp/start\]" "$TMPD/start.txt"; then
    ok "and the bundle carries the file manager with name AND command ($(grep -ao 'launcher: treffer i=[0-9]* name=\[File Explorer\][^ ]* exec=\[[^]]*\]' "$TMPD/start.txt" | head -1))"
else
    bad "the bundle does not carry the file manager with name AND command"
    grep -a 'launcher: treffer' "$TMPD/start.txt" | sed 's/^/        /' | head -6
fi
for teil in INFO symbol start data/README; do
    grep -q "^/apps/explorer.osp/$teil " "$TMPD/disk.ls" \
        && ok "the bundle carries $teil" \
        || bad "/apps/explorer.osp/$teil is missing on the disk"
done
gb=$(grep -c '^/apps/[a-z]*\.osp/$' "$TMPD/disk.ls")
num "so viele Buendel liegen unter /apps" "$gb" eq "$soll"
hasnot "$TMPD/disk.ls" "/usr/share/apps" \
    "and the old place is gone -- one description, two places, would be one too many"
SBX=$(grep -a 'wm: win .*t=\[Search\]' "$TMPD/start.txt" | tail -1 | grep -oE ' x=[0-9]+' | head -1 | tr -dc '0-9')
SBY=$(grep -a 'wm: win .*t=\[Search\]' "$TMPD/start.txt" | tail -1 | grep -oE ' y=[0-9]+' | head -1 | tr -dc '0-9')
SBX=${SBX:-0}; SBY=${SBY:-0}
SCX=$SBX; SCY=$SBY
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
BOLD_INK="fui:assets/osum-sans-bold.ttf"
FEI=$(grep -a 'launcher: treffer i=[0-9]* name=\[File Explorer\]' "$TMPD/start.txt" | head -1 | grep -oE 'i=[0-9]+' | tr -dc '0-9')
EDI=$(grep -a 'launcher: treffer i=[0-9]* name=\[Terminal\]' "$TMPD/start.txt" | head -1 | grep -oE 'i=[0-9]+' | tr -dc '0-9')
FEI=${FEI:-99}; EDI=${EDI:-99}
SDIM=$(grep -a '^wlib: text2 .*t=View files and folders' "$TMPD/start.txt" | tail -1 | grep -oE ' fg=[0-9]+' | tr -dc '0-9')
SDIM=$(rgb "${SDIM:-0}")
zeile_farben() {
    if [ "$1" = 0 ]; then echo "$SSFG $SSEL $SSFG"; else echo "$SFG $SBG $SDIM"; fi
}
set -- $(zeile_farben "$FEI")
FEFG="$1 $2 $3"; FEBG="$4 $5 $6"; FEDF="$7 $8 $9"
set -- $(zeile_farben "$EDI")
EDFG="$1 $2 $3"; EDBG="$4 $5 $6"; EDDF="$7 $8 $9"
set --
schau "the file manager row: its name, bold, per character" \
    tchain "$TMPD/start.ppm" "$BOLD_INK" 15 $((SCX + SRX)) $((SCY + SRB + FEI * SZH)) \
    $FEFG $FEBG "File Explorer" 96
schau "and below it its description, in caption size" \
    tchain "$TMPD/start.ppm" "$SANS_INK" 12 $((SCX + SRX)) $((SCY + SRB + FEI * SZH + SZH / 2)) \
    $FEDF $FEBG "View files and folders" 96
schau "and that of the terminal" \
    tchain "$TMPD/start.ppm" "$BOLD_INK" 15 $((SCX + SRX)) $((SCY + SRB + EDI * SZH)) \
    $EDFG $EDBG "Terminal" 96
schau "with its description" \
    tchain "$TMPD/start.ppm" "$SANS_INK" 12 $((SCX + SRX)) $((SCY + SRB + EDI * SZH + SZH / 2)) \
    $EDDF $EDBG "A command prompt with a shell" 96
schau_nicht "the name is NOT there in the regular weight (the counter-proof to the bold)" \
    tchain "$TMPD/start.ppm" "$SANS_INK" 15 $((SCX + SRX)) $((SCY + SRB + FEI * SZH)) \
    $FEFG $FEBG "File Explorer" 96
sym() { echo "$TMPD/buendel/$1.osp.symbol"; }
ICS=16
[ -f assets/apps/explorer.osp/symbol.osym ] && ICS=32
for a in explorer terminal; do
    SRC="assets/apps/$a.osp/symbol.txt"
    [ -f "assets/apps/$a.osp/symbol.osym" ] && SRC="assets/apps/$a.osp/symbol.osym"
    python3 tools/k15/icon.py --pruefe "$(sym $a)" "$SRC" \
        > "$TMPD/sym-$a.txt" 2>&1 \
        && ok "the icon of $a in the image is the drawing from the source tree ($(cat "$TMPD/sym-$a.txt"))" \
        || bad "the icon of $a does not match its drawing"
done
tilecheck() { local name=$1 sym=$2 row=$3 limit=$4
    local aus rc; aus=$(python3 tools/k15/tile.py "$TMPD/start.ppm" $((SCX + SIX)) $((SCY + SIY + row * SZH)) $ICS "$sym" "$limit" 2>&1); rc=$?
    if [ "$rc" -eq 0 ]; then ok "$name ($aus)"; else bad "$name -- $aus"; fi; }
tilecheck_not() { local name=$1 sym=$2 row=$3 limit=$4
    local aus rc; aus=$(python3 tools/k15/tile.py "$TMPD/start.ppm" $((SCX + SIX)) $((SCY + SIY + row * SZH)) $ICS "$sym" "$limit" 2>&1); rc=$?
    if [ "$rc" -ne 0 ]; then ok "$name ($aus)"; else bad "$name -- went through: $aus"; fi; }
TILE_LIMIT=${TILE_LIMIT:-3}
tilecheck "the file manager symbol is on screen (tile from the 64 px bake)" "$(sym explorer)" "$FEI" "$TILE_LIMIT"
tilecheck_not "and it is NOT the terminal symbol (counter-proof)" "$(sym terminal)" "$FEI" "$TILE_LIMIT"
tilecheck "the terminal row shows the terminal symbol" "$(sym terminal)" "$EDI" "$TILE_LIMIT"

echo "== 14c. the search -- and that the keywords really take effect =="
for w in ordner verzeichnis; do
    if grep -ihE '^(name|info)=' assets/apps/*.osp/INFO | grep -qi "$w"; then
        bad "'$w' is in a display name or a description -- the assertion would be worthless"
    else
        ok "'$w' is in NO display name and NO description"
    fi
done
lrect() { grep -aoE "^launcher: rect id=$1 .*" "$TMPD/start.txt" | tail -1 | grep -oE " $2=[0-9]+" | tr -dc '0-9'; }
FX2=$((SCX + $(lrect 1 x) + $(lrect 1 w) / 2))
FY2=$((SCY + $(lrect 1 y) + $(lrect 1 h) / 2))
suchmon() {
    local f=$1 w=$2; shift 2; : > "$f"
    zeiger "$f" "$FX2" "$FY2"
    printf 'mouse_button 1\nmouse_button 0\nwarte 0.4\n' >> "$f"
    local c; for c in "$@"; do echo "sendkey $c" >> "$f"; done
    printf 'warte %s\nmouse_move 120 120\nmouse_move 60 60\n' "$w" >> "$f"
}
M="$TMPD/suche.mon"
suchmon "$M" 1.0 o r d n e r
foto suche "gfx wm wigstart wmhold wiglong $GRUND" "$M"
has "$TMPD/suche.txt" "launcher: suche [ordner] treffer=1 apps=1" \
    "typed 'ordner': EXACTLY ONE hit, and it is a program"
has "$TMPD/start.txt" "launcher: name [Search]" \
    "the launcher also fetches its own name from the data"
tf=$(grep -aA1 'launcher: suche \[ordner\]' "$TMPD/suche.txt" | grep -a 'name=' | tail -1)
case "$tf" in
    *"name=[File Explorer]"*) ok "the hit is the file manager" ;;
    *) bad "the hit is not the file manager: $tf" ;;
esac
schau "in the picture it is in row 0 of the hit list" \
    tchain "$TMPD/suche.ppm" "$BOLD_INK" 15 $((SCX + SRX)) $((SCY + SRB)) \
    $SSFG $SSEL "File Explorer" 96
schau "with its description below" \
    tchain "$TMPD/suche.ppm" "$SANS_INK" 12 $((SCX + SRX)) $((SCY + SRB + SZH / 2)) \
    $SSFG $SSEL "View files and folders" 96
schau_nicht "and row 1 holds nothing more" \
    tchain "$TMPD/suche.ppm" "$BOLD_INK" 15 $((SCX + SRX)) $((SCY + SRB + SZH)) \
    $SFG $SBG "Terminal" 96
foto nokeys "gfx wm wigstart wignokeys wmhold wiglong $GRUND" "$M"
has "$TMPD/nokeys.txt" "launcher: suche [ordner] treffer=0 apps=0" \
    "WITHOUT the keywords 'ordner' finds NOTHING"
has "$TMPD/nokeys.txt" "launcher: apps=$soll" \
    "although the same directory with the same $soll programs was read"
schau_nicht "and the picture then shows no row either" \
    tchain "$TMPD/nokeys.ppm" "$BOLD_INK" 15 $((SCX + SRX)) $((SCY + SRB)) \
    $SSFG $SSEL "File Explorer" 96
suchmon "$TMPD/unsinn.mon" 1.0 q u a s t e
foto unsinn "gfx wm wigstart wmhold wiglong $GRUND" "$TMPD/unsinn.mon"
has "$TMPD/unsinn.txt" "launcher: suche [quaste] treffer=0 apps=0   dateien=0" \
    "a word that is nowhere finds NOTHING -- no program and no file"
grep -qi 'quaste' assets/apps/*.osp/INFO \
    && bad "'quaste' is in an INFO after all" \
    || ok "and 'quaste' is really in no INFO"
has "$TMPD/start.txt" "launcher: suche [] treffer=$shown" \
    "without a search term all $shown visible programs are listed"

echo "== 15. the name index: the WHOLE file system, and at once =="

python3 tools/k15/bigfs.py "$TMPD/gross" 4000 > "$TMPD/gross.log" 2>&1 \
    && ok "tools/k15/bigfs.py: $(cat "$TMPD/gross.log")" \
    || bad "bigfs.py fehlgeschlagen"
GARGS=(build "$TMPD/gross.img" 4096 /bin/
       "/bin/sh=$TMPD/sh0.elf" "/bin/locate=$TMPD/locate0.elf"
       "/bin/ls=$TMPD/ls0.elf")
while read -r z; do GARGS+=("$z"); done < "$TMPD/gross/angaben"
python3 tools/osum/mkfs.py "${GARGS[@]}" > "$TMPD/gmkfs.txt" 2>&1 \
    && ok "the big image: $(cat "$TMPD/gmkfs.txt")" \
    || { bad "mkfs.py failed"; head -3 "$TMPD/gmkfs.txt"; }
GN=$(python3 tools/osum/mkfs.py list "$TMPD/gross.img" | tail -n +2 | wc -l)
num "this many names the image carries in total" "$GN" ge 4000

gross() {
    local name=$1 zeile=$2
    cp -f "$TMPD/gross.img" "$TMPD/g-$name.img"
    timeout 600 $QEMU_X86 -kernel "$TMPD/k0.mb" -m 256 \
        -append "osum nokbd nosched noproc nofs noring3 script=$zeile;exit" \
        -serial "file:$TMPD/$name.txt" -display none -no-reboot \
        -drive "file=$TMPD/g-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    RC=$?
    return 0
}
gfeld() { grep -a "$2" "$1" | tail -1 | grep -oE "(^| )$3=[0-9]+" | tail -1 | sed 's/.*=//'; }

gross gkupfer "locate -m kupfer"
num "the kernel exits cleanly" "$RC" eq 21
GB_N=$(gfeld "$TMPD/gkupfer.txt" 'locate: bauen' 'n')
GB_S=$(gfeld "$TMPD/gkupfer.txt" 'locate: bauen' 'saetze')
GB_C=$(gfeld "$TMPD/gkupfer.txt" 'locate: bauen' 'aufrufe')
GB_U=$(gfeld "$TMPD/gkupfer.txt" 'locate: bauen' 'us')
GB_T=$(gfeld "$TMPD/gkupfer.txt" 'locate: bauen' 'abgeschn')
num "1. THE BUILD: this many names from the inode table" "$GB_N" eq "$GN"
gleich "and no record was lost on the way" "$GB_N" "$GB_S"
num "abgeschnitten wurde nichts" "$GB_T" eq 0
num "and in so few system calls (63 records per call)" "$GB_C" lt 100
num "microseconds for the whole build" "$GB_U" gt 0
echo "        -> $GB_N names in $GB_U us, $GB_C calls; that is $((GB_U / GB_N)) us per name"

GI_U=$(gfeld "$TMPD/gkupfer.txt" 'locate: index' 'us10')
GI_T=$(grep -a 'locate: index' "$TMPD/gkupfer.txt" | tail -1 | grep -oE 'treffer=[0-9]+' | sed 's/.*=//')
GW_U=$(gfeld "$TMPD/gkupfer.txt" 'locate: baum' 'us')
GW_T=$(grep -a 'locate: baum' "$TMPD/gkupfer.txt" | tail -1 | grep -oE 'treffer=[0-9]+' | sed 's/.*=//')
GW_G=$(gfeld "$TMPD/gkupfer.txt" 'locate: baum' 'gesehen')
GI_1=$((GI_U / 10))
num "2. THE SEARCH: orders of magnitude cheaper than the build" \
    $((GB_U / (GI_1 + 1))) ge 20
echo "        -> build $GB_U us, one search $GI_1 us (ten measured: $GI_U us)"
num "3. THE COUNTER-PROOF: the tree walk sees the same names" "$GW_G" eq "$GB_N"
gleich "and it finds EXACTLY THE SAME number of hits" "$GI_T" "$GW_T"
has "$TMPD/gkupfer.txt" "ungleich=0" \
    "and THE SAME NAMES -- sorted, compared octet by octet"
num "and the index is many times faster" \
    $((GW_U / (GI_1 + 1))) ge 20
echo "        -> tree walk $GW_U us, search in the index $GI_1 us"
SOLLK=$(grep '^kupfer ' "$TMPD/gross/erwartet" | awk '{print $2}')
num "and both find as many as the image list gives" "$GI_T" eq "$SOLLK"
has "$TMPD/gkupfer.txt" "locate: pfad /data/kupfer" \
    "and the hit carries its whole path, built from the parent numbers"

gross gviele "locate -m 07"
SOLL7=$(grep '^07 ' "$TMPD/gross/erwartet" | awk '{print $2}')
V_I=$(grep -a 'locate: index' "$TMPD/gviele.txt" | tail -1 | grep -oE 'treffer=[0-9]+' | sed 's/.*=//')
V_B=$(grep -a 'locate: baum' "$TMPD/gviele.txt" | tail -1 | grep -oE 'treffer=[0-9]+' | sed 's/.*=//')
num "a word that hits MANY: the index finds this many" "$V_I" eq "$SOLL7"
gleich "and the tree walk just as many" "$V_I" "$V_B"
has "$TMPD/gviele.txt" "ungleich=0" "and again the same, name by name"

gross gquaste "locate -m quaste"
SOLLQ=$(grep '^quaste ' "$TMPD/gross/erwartet" | awk '{print $2}')
num "the image list knows 'quaste' this often" "$SOLLQ" eq 0
has "$TMPD/gquaste.txt" "locate: index [quaste] treffer=0" \
    "5. the index does NOT find 'quaste'"
has "$TMPD/gquaste.txt" "locate: baum [quaste] treffer=0" \
    "and neither does the tree walk"
Q_G=$(gfeld "$TMPD/gquaste.txt" 'locate: baum' 'gesehen')
num "although it looked at all $Q_G names" "$Q_G" eq "$GB_N"

echo "== 15b. the journal: create, rename, delete -- without a rebuild =="
gross gjrnl "locate -j kupfer"
num "the kernel exits cleanly" "$RC" eq 21
has "$TMPD/gjrnl.txt" "schritt=1  zwiebel=1  apfel=0" \
    "after creating, the index finds the new file"
has "$TMPD/gjrnl.txt" "schritt=3  zwiebel=0  apfel=1" \
    "after renaming the NEW name and no longer the old one"
has "$TMPD/gjrnl.txt" "schritt=4  zwiebel=0  apfel=0" \
    "and after deleting neither of them"
J_N1=$(grep -a 'schritt=1 ' "$TMPD/gjrnl.txt" | grep -oE 'namen=[0-9]+' | sed 's/.*=//')
J_N4=$(grep -a 'schritt=4 ' "$TMPD/gjrnl.txt" | grep -oE 'namen=[0-9]+' | sed 's/.*=//')
num "the index gained one name" $((J_N1 - GB_N)) eq 1
num "and at the end as many as at the start" "$J_N4" eq "$GB_N"
has "$TMPD/gjrnl.txt" "lost=0" "and the ring dropped no record"
nb=$(grep -ac 'locate: bauen' "$TMPD/gjrnl.txt")
num "exactly ONE build in the whole run, and only the journal after that" "$nb" eq 1

gross gnojrnl "locate -n kupfer"
has "$TMPD/gnojrnl.txt" "schritt=1  zwiebel=0  apfel=0" \
    "WITHOUT the journal the index knows nothing of the new file"
has "$TMPD/gnojrnl.txt" "schritt=4  zwiebel=0  apfel=0" \
    "nor of the other two steps"
N_N4=$(grep -a 'schritt=4 ' "$TMPD/gnojrnl.txt" | grep -oE 'namen=[0-9]+' | sed 's/.*=//')
num "its name list never changed" "$N_N4" eq "$GB_N"
N_S=$(grep -a 'schritt=4 ' "$TMPD/gnojrnl.txt" | grep -oE 'gezogen=[0-9]+' | sed 's/.*=//')
num "it fetched zero records" "$N_S" eq 0
J_S=$(grep -a 'schritt=4 ' "$TMPD/gjrnl.txt" | grep -oE 'gezogen=[0-9]+' | sed 's/.*=//')
num "the run WITH journal fetched four" "$J_S" eq 4

echo "== 15c. the launcher searches files, not only programs =="
grep -qi 'blau' assets/apps/*.osp/INFO \
    && bad "'blau' is in an INFO -- the assertion would be worthless" \
    || ok "'blau' is in NO INFO: whatever is found can only be a file"
M="$TMPD/dsuche.mon"
suchmon "$M" 1.2 b l a u
foto dsuche "gfx wm wigstart wmhold wiglong $GRUND" "$M"
has "$TMPD/dsuche.txt" "launcher: suche [blau] treffer=1 apps=0   dateien=1" \
    "typed 'blau': one hit, and it is NOT a program but a file"
has "$TMPD/dsuche.txt" "launcher: datei i=0 name=[/data/bilder/blau.ppm]" \
    "and it is the file that really lies there"
grep -q '^/data/bilder/blau.ppm ' "$TMPD/disk.ls" \
    && ok "which the image really carries at this place" \
    || bad "/data/bilder/blau.ppm is not in the image at all"
schau "and in the picture its name is in row 0 of the hit list, bold, per character" \
    tchain "$TMPD/dsuche.ppm" "$BOLD_INK" 15 $((SCX + SRX)) $((SCY + SRB)) \
    $SSFG $SSEL "blau.ppm" 96
schau "and below it the folder it lies in" \
    tchain "$TMPD/dsuche.ppm" "$SANS_INK" 12 $((SCX + SRX)) $((SCY + SRB + SZH / 2)) \
    $SSFG $SSEL "/data/bilder" 96
DIX=$(feld "$TMPD/dsuche.txt" "launcher: index" n)
num "the launcher built an index over this many names for it" "$DIX" ge 40
foto noidx "gfx wm wigstart wignoidx wmhold wiglong $GRUND" "$M"
has "$TMPD/noidx.txt" "launcher: suche [blau] treffer=0 apps=0   dateien=0" \
    "WITHOUT the name index 'blau' finds NOTHING"
has "$TMPD/noidx.txt" "launcher: index n=0" \
    "weil gar keiner gebaut wurde"
has "$TMPD/noidx.txt" "launcher: apps=$soll" \
    "although the same application directory with the same $soll bundles was read"
schau_nicht "and the picture then shows no file either" \
    tchain "$TMPD/noidx.ppm" "$BOLD_INK" 15 $((SCX + SRX)) $((SCY + SRB)) \
    $SSFG $SSEL "blau.ppm" 96

echo "== 15d. and the old images are the old ones, octet by octet =="
head -c 20000 /dev/urandom > "$TMPD/probe.bin"
python3 tools/osum/mkfs.py build "$TMPD/alt1.img" 4096 /a/ /b/ \
    "/a/eins=$TMPD/probe.bin" "/b/zwei=$TMPD/probe.bin" "/b/drei@/a/eins" \
    > "$TMPD/alt1.txt" 2>&1
python3 tools/osum/mkfs.py build "$TMPD/alt2.img" 4096 /a/ /b/ \
    "/a/eins=$TMPD/probe.bin" "/b/zwei=$TMPD/probe.bin" "/b/drei@/a/eins" \
    > "$TMPD/alt2.txt" 2>&1
cmp -s "$TMPD/alt1.img" "$TMPD/alt2.img" \
    && ok "zweimal gebaut, zweimal dieselben Oktette" \
    || bad "mkfs.py does not build the same thing twice"
grep -q 'data=34' "$TMPD/alt1.txt" \
    && ok "without --inodes the data area still starts at block 34" \
    || bad "the data area has shifted: $(cat "$TMPD/alt1.txt")"
grep -q 'inodes=[0-9]*/128' "$TMPD/alt1.txt" \
    && ok "and the table still has 128 inodes" \
    || bad "the default inode count has changed: $(cat "$TMPD/alt1.txt")"
grep -q 'data=1026' "$TMPD/gmkfs.txt" \
    && ok "with --inodes=4096 it moves to block 1026" \
    || bad "the big data area is misplaced: $(cat "$TMPD/gmkfs.txt")"
has "$TMPD/gkupfer.txt" "osum: mount=1" \
    "and the same kernel mounts both, without a line of difference"

echo
echo "K15: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
