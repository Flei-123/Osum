#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/sync/gc.sh
. tools/lib/qemu.sh
. tools/lib/summary.sh
summary_begin K15
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
if [ -n "${K15_KEEP:-}" ]; then TMPD=$K15_KEEP; mkdir -p "$TMPD"; else TMPD=$(mktemp -d); fi
trap 'summary_guard; [ -n "${K15_KEEP:-}" ] || rm -rf "$TMPD"; summary_exit_status || exit 1' EXIT
trap 'exit 1' HUP INT TERM

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
    summary_note "skipped, qemu-system-x86_64 is not available"
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
[ -f "$TMPD/k0.mb" ] || { summary_emit "$pass" "$((fail + 1))"; exit 1; }

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
wigzeilen=$(cat kernel/user/wlib.fi kernel/user/wlibc.fi kernel/user/wlib/*.fi kernel/user/wlibc/*.fi | wc -l)
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
bash tools/mkfsfi/mkfs.sh "${ARGS[@]}" > "$TMPD/mkfs.txt" 2>&1 \
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
if [ $? -ne 0 ] && printf '%s' "$gg" | grep -q 'COLLISION'; then
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

