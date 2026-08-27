#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/desktop/run.sh -- THE PROOF THAT THE TASKBAR HAS A POSITION.
#
# Round DESKTOP gave this system a taskbar. It sat at the bottom edge
# because `py = sh - PH` was written into the source; there was no
# position, no setting and no way to move it. This runner measures the
# addendum that gave it one.
#
# WHAT IS MEASURED, AND WHY IN THIS WAY:
#
#   1. THE GEOMETRY IS CHECKED BY ARITHMETIC AND NOT BY EYE.
#      `tools/desktop/rects.py` takes the server's window table, the
#      server's work area and the work area the taskbar reads back from
#      ring 3, and proves for each of the four edges: the bar is on its
#      edge, the work area is the screen minus the bar exactly, the
#      maximized window IS the work area, and the two rectangles share
#      no pixel and leave no gap. A picture cannot answer that -- a
#      window one pixel under the bar looks like a window flush with it.
#
#   2. THE TEXT IS CHECKED PER CHARACTER. That is the lesson of round
#      K7B, where text was "87 percent correct" while every single
#      letter was missing -- the 87 percent were black background. So
#      the position and the two colours are taken from what the
#      APPLICATION reported, and every inked pixel of every glyph is
#      recomputed in the picture against a second, independent
#      rasterization (`tools/gfx/checkshot.py tkette`). A vertical bar is
#      where this matters most: it is the place where a lazy
#      implementation clips the text instead of wrapping it, and clipped
#      text passes an area test and fails this one.
#
#   3. THE BAR IS REALLY DRAGGED. Real mouse packets go into the running
#      machine through the QEMU monitor (`tools/wm/monitor.py`): press
#      on an empty part of the bar, pull to the left edge, let go. Then
#      the CONFIGURATION FILE IS READ BACK OUT OF THE DISK IMAGE
#      (`mkfs.py cat`), and the machine is booted a SECOND time from
#      that same image to show that the setting survives.
#
#   4. THE SETTINGS ARE REALLY CLICKED. The drop-down on the page
#      "Darstellung" is opened with a click, the row "right" is taken
#      with a click, "Uebernehmen" is pressed -- and then the taskbar,
#      a different process, moves. Nothing is passed between them but
#      /etc/taskbar.conf.
#
#   5. EVERY CLAIM HAS A COUNTER-TEST. `nostrut` switches the
#      reservation off in the server: the work area becomes the whole
#      screen, the maximized window covers the bar, and `rects.py`
#      demands exactly that. A claim whose counter-test also passes is
#      not a measurement.
#
# Usage:  bash tools/desktop/run.sh [--shots <dir>]
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

SHOTS="docs/shots/taskbar"
while [ $# -gt 0 ]; do
    case "$1" in
        --shots) SHOTS=$2; shift 2 ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
done
mkdir -p "$SHOTS"

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { local name=$1 wert=$2 op=$3 want=$4
    if [ -z "$wert" ]; then bad "$name: no number found (wanted $op $want)"; return; fi
    if [ "$wert" -"$op" "$want" ] 2>/dev/null; then ok "$name: $wert"
    else bad "$name: $wert, wanted $op $want"; fi
}
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' is missing"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' is there and should not be" || ok "$3"; }
same() { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$3' instead of '$2'"; fi; }
rgb() { python3 -c "v=int('${1:-0}');print((v>>16)&255,(v>>8)&255,v&255)"; }

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "TASKBAR: skipped, qemu-system-x86_64 is not here"
    exit 0
fi
bash vendor/firn/fetch-firnc.sh >/dev/null || {
    echo "vendor/firn/fetch-firnc.sh failed"; exit 1; }

MONO=assets/osum-mono.ttf
SANS=assets/osum-sans.ttf
BASE="gfx wm wig desk wmhold wiglong nokbd nosched noproc nofs"
SCREEN_W=800
SCREEN_H=600

echo "== 1. building: the kernel out of both compilers, and the programs =="
for s in 0 1; do
    if bash tools/build-kernel.sh "$TMPD/k$s.mb" --stufe "$s" > "$TMPD/b$s.log" 2>&1; then
        ok "firnc$s: kernel built ($(stat -c%s "$TMPD/k$s.mb") octets)"
    else
        bad "firnc$s: the kernel does not build"
        sed 's/^/        /' "$TMPD/b$s.log" | head -12
    fi
done
[ -f "$TMPD/k0.mb" ] || { echo "TASKBAR: $pass passed, $((fail + 1)) failed"; exit 1; }

PROGS="desktop taskbar settings launcher dhcp explorer widgetdemo locate sh echo ls cat edit"
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null \
    || bad "crt.s does not assemble"
build_progs() { # stage
    local s=$1 cc p rc=0
    if [ "$s" = 0 ]; then cc=vendor/firn/bin/firnc; else cc=vendor/firn/bin/firnc1; fi
    for p in $PROGS; do
        "$cc" "kernel/user/$p.fi" -o "$TMPD/$p$s.o" > "$TMPD/e$p$s" 2>&1 || {
            bad "firnc$s does not compile $p.fi"
            sed 's/^/        /' "$TMPD/e$p$s" | head -6
            rc=1; continue; }
        ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F$s.u_start" \
            -o "$TMPD/$p$s.elf" "$TMPD/crt.o" "$TMPD/$p$s.o" \
            2>"$TMPD/ld$s.err" || { bad "firnc$s: ld fails on $p"; rc=1; continue; }
        strip --strip-all "$TMPD/$p$s.elf"
    done
    return $rc
}
build_progs 0 && ok "firnc0: $(echo $PROGS | wc -w) programs built, /bin/taskbar is $(stat -c%s "$TMPD/taskbar0.elf") octets" \
    || bad "firnc0: the programs do not build"
build_progs 1 && ok "firnc1: the same ones out of the compiler written in Firn" \
    || bad "firnc1: the programs do not build"

# THE BAR IS A PROGRAM IN RING 3. Not a claim -- the kernel image does
# not carry a single one of its symbols.
for sym in taskbar__paint taskbar__conf_read taskbar__drag_step; do
    if nm -a "$TMPD/k0.mb.elf" 2>/dev/null | grep -q "$sym"; then
        bad "the kernel carries $sym -- the taskbar belongs in ring 3"
    else
        ok "the kernel does NOT carry $sym (the taskbar is a ring 3 program)"
    fi
done

python3 tools/k15/tree.py "$TMPD/baum" > "$TMPD/baum.log" 2>&1 \
    && ok "the directory tree is built" || bad "tools/k15/tree.py failed"

conf() { # edge height width autohide ontop -> file
    printf '# taskbar.conf\nedge=%s\nheight=%s\nwidth=%s\nautohide=%s\nontop=%s\n' \
        "$1" "$2" "$3" "$4" "$5"
}
mk_image() { # image conf-file
    local img=$1 cf=$2
    # 16384 BLOCKS AND NOT 4096. mkfs' block is 512 octets, so this is
    # 8 MiB and used to be 2. Round LOOK made the three programs of the
    # desktop considerably bigger -- the shape tokens and the rounded,
    # antialiased drawing in settings, the icon glyphs and the second
    # status field in the taskbar, and a message catalogue that went
    # from 72 keys to 154:
    #
    #     settings  384200 -> 565248     taskbar  278032 -> 371248
    #     desktop   181568 -> 249368     (+342 KiB together)
    #
    # and the image stopped fitting. The failure is loud but it is loud
    # in the WRONG PLACE: `mkfs: the disk is full`, then twenty-nine
    # assertions about drag, autohide and the settings page fail because
    # there was no image to boot. tools/look/shot.sh and
    # tools/netview/run.sh were already on 8192 for the same set of
    # programs, which is why they did not notice.
    local ARGS=(build "$img" 16384 /lib/
        "/lib/mono.ttf=$MONO" "/lib/sans.ttf=$SANS" /bin/)
    local p
    for p in $PROGS; do ARGS+=("/bin/$p=$TMPD/${p}0.elf"); done
    ARGS+=("/bin/files@/bin/explorer")
    ARGS+=(/etc/ "/etc/theme=$TMPD/baum/theme" "/etc/taskbar.conf=$cf")
    while read -r z; do ARGS+=("$z"); done < <(python3 tools/k15/bundle.py assets/apps "$TMPD/buendel")
    while read -r z; do ARGS+=("$z"); done < "$TMPD/baum/liste"
    python3 tools/osum/mkfs.py "${ARGS[@]}" > "$TMPD/mkfs.txt" 2>&1
}

echo "== 2. the memory map, the call numbers and the mode words =="
kart=$(python3 tools/kernel/memmap.py kernel 2>&1)
if [ $? -eq 0 ]; then ok "the memory map of kdata: $kart"
else bad "the memory map collides"; echo "$kart" | sed 's/^/        /'; fi
for n in 2112 2113; do
    grep -qE "= $n( |$)" kernel/sys.fi && ok "call number $n is in kernel/sys.fi" \
        || bad "call number $n is missing"
done
grep -q 'const WM_MAXNR: u64 = 2113' kernel/sys.fi \
    && ok "and 2113 is the highest of the window server" \
    || bad "WM_MAXNR does not match the calls"
# THE FOUR EDGES ARE THE SAME FOUR NUMBERS IN FOUR PLACES. Not a
# translation table -- one set of numbers, written down four times, and
# a runner that would notice if one of them drifted.
for f in kernel/wm.fi kernel/sys.fi kernel/user/wlibc.fi; do
    if grep -qE '(EDGE|WE)_BOTTOM: u64 = 0' "$f" \
       && grep -qE '(EDGE|WE)_RIGHT: u64 = 3' "$f"; then
        ok "$f numbers the edges 0..3 the same way"
    else
        bad "$f numbers the edges differently"
    fi
done
grep -q 'edge=' kernel/user/taskbar.fi && grep -q 'edge=' kernel/user/settings.fi \
    && ok "both writers of /etc/taskbar.conf spell the key 'edge'" \
    || bad "the two writers of /etc/taskbar.conf disagree about the key"

RC=0
run() { # name conf-file cmdline-extra [monitor-file] [reuse-image]
    local name=$1 cf=$2 extra=$3 mon=${4:-} reuse=${5:-}
    local sock="$TMPD/mon-$name.sock"
    local out="$TMPD/$name.txt" ppm="$TMPD/$name.ppm"
    rm -f "$out" "$ppm" "$sock"
    if [ -n "$reuse" ]; then
        cp -f "$reuse" "$TMPD/live-$name.img"
    else
        mk_image "$TMPD/disk-$name.img" "$cf" || {
            bad "mkfs.py failed for $name"; sed 's/^/        /' "$TMPD/mkfs.txt" | head -5; return 1; }
        cp -f "$TMPD/disk-$name.img" "$TMPD/live-$name.img"
    fi
    timeout 240 qemu-system-x86_64 -kernel "$TMPD/k0.mb" -m 256 \
        -append "$BASE $extra" -serial "file:$out" -display none -no-reboot \
        -vga std -monitor "unix:$sock,server,nowait" \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/$name.qemu" 2>&1 &
    local pid=$!
    local i=0
    while [ $i -lt 1400 ]; do
        grep -qaE '^wm: hold' "$out" 2>/dev/null && break
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

# The reported position of a piece of text, and the text itself, checked
# character by character in the picture.
# THE BAR IS NOT A STILL LIFE, and that is why every reported state is
# tried and not only the last one. The clock ticks, windows open and
# close, buttons are re-laid out; the screenshot catches ONE of those
# states, and which one is a matter of a few hundred milliseconds. The
# claim being measured is therefore: what stands in the picture is one
# of the states the bar reported, AND at that place every inked pixel of
# every glyph is right. The tolerance stays zero -- only the choice of
# which reported state to compare against is left open.
check_text() { # log ppm mark
    local log=$1 ppm=$2 mark=$3
    local tried=0 lastaus="" lasttext="" line
    # THE BAR REPORTS IN ITS OWN COORDINATES, THE PICTURE IS THE SCREEN.
    # The bar has no decoration, so the offset is exactly the position of
    # its window -- and forgetting it costs nothing at the top edge
    # (offset 0,0) and everything at the other three. It cost four
    # measurements here before it was noticed, and the failure looked
    # like a font defect: every inked pixel wrong, which is what one
    # gets when comparing a glyph against a piece of desktop.
    local gline gx gy
    gline=$(grep -a "^taskbar: geom " "$log" | tail -1)
    gx=$(printf '%s' "$gline" | grep -oE ' x=[0-9]+' | head -1 | sed 's/.*=//')
    gy=$(printf '%s' "$gline" | grep -oE ' y=[0-9]+' | head -1 | sed 's/.*=//')
    gx=${gx:-0}; gy=${gy:-0}
    if ! grep -qa "^taskbar: text $mark " "$log"; then
        bad "the taskbar does not report the text '$mark'"
        return
    fi
    while IFS= read -r line; do
        local x base fg bg text aus
        x=$(printf '%s' "$line" | grep -oE ' x=[0-9]+' | head -1 | sed 's/.*=//')
        base=$(printf '%s' "$line" | grep -oE ' base=[0-9]+' | sed 's/.*=//')
        fg=$(printf '%s' "$line" | grep -oE ' fg=[0-9]+' | sed 's/.*=//')
        bg=$(printf '%s' "$line" | grep -oE ' bg=[0-9]+' | sed 's/.*=//')
        text=$(printf '%s' "$line" | sed 's/^.* t=//')
        [ -z "$text" ] && continue
        tried=$((tried + 1))
        aus=$(python3 tools/gfx/checkshot.py tkette "$ppm" "$SANS" 15 \
            "$((x + gx))" "$((base + gy))" \
            $(rgb "$fg") $(rgb "$bg") "$text" 2>&1)
        if [ $? -eq 0 ]; then
            ok "'$text' at screen $((x + gx)),$((base + gy)) -- $aus (1 of $tried reported states)"
            return
        fi
        lastaus=$aus
        lasttext="'$text' at screen $((x + gx)),$((base + gy))"
    done < <(grep -a "^taskbar: text $mark " "$log" | tail -8 | tac)
    bad "none of the $tried reported states of '$mark' is in the picture; last was $lasttext -- $lastaus"
}

png() { # ppm name
    python3 - "$1" "$SHOTS/$2.png" <<'PYEOF' 2>/dev/null
import sys
from PIL import Image
Image.open(sys.argv[1]).save(sys.argv[2])
PYEOF
}

echo "== 3. the four edges: geometry, work area, and the text per character =="
for e in bottom top left right; do
    THICK=28
    case $e in left|right) THICK=104 ;; esac
    conf "$e" 28 104 0 1 > "$TMPD/conf-$e"
    run "$e" "$TMPD/conf-$e" "wmax" || continue
    L="$TMPD/$e.txt"; P="$TMPD/$e.ppm"
    num "[$e] the kernel exits cleanly" "$RC" eq 21
    has "$L" "taskbar: conf edge=" "[$e] the bar read /etc/taskbar.conf"
    src=$(grep -a 'taskbar: conf ' "$L" | tail -1 | grep -oE 'src=[a-z]+' | sed 's/.*=//')
    same "[$e] and it came from the file, not from the defaults" "file" "$src"
    ename=$(grep -a 'taskbar: conf ' "$L" | tail -1 | grep -oE 'ename=[a-z]+' | sed 's/.*=//')
    same "[$e] the edge it read" "$e" "$ename"
    aus=$(python3 tools/desktop/rects.py "$L" "$e" "$THICK" 2>&1)
    if [ $? -eq 0 ]; then ok "[$e] the rectangles: $aus"
    else bad "[$e] the rectangles do not add up"; printf '%s\n' "$aus"; fi
    ws=$(grep -a 'wm: selftest' "$L" | tail -1 | grep -oE '[0-9]+ / [0-9]+')
    same "[$e] the window server's claims about itself" "30 / 30" "$ws"
    # the text, per character
    check_text "$L" "$P" "start"
    check_text "$L" "$P" "clock"
    check_text "$L" "$P" "battery"
    check_text "$L" "$P" "net"
    check_text "$L" "$P" "button"
    # a vertical bar has to wrap or shrink -- never clip. Whatever it
    # decided, the reported text is the drawn text, and the check above
    # is the proof; here we only record what it decided.
    for f in net battery clock; do
        li=$(grep -a "taskbar: field $f " "$L" | tail -1 | grep -oE 'lines=[0-9]+' | sed 's/.*=//')
        [ -n "$li" ] && ok "[$e] the field '$f' needed $li line(s)" \
            || bad "[$e] the field '$f' reports no line count"
    done
    png "$P" "$e"
    [ -f "$SHOTS/$e.png" ] && ok "[$e] screenshot: $SHOTS/$e.png" \
        || bad "[$e] no screenshot was written"
done

echo "== 4. the counter-test: without the strut the bar is covered =="
conf bottom 28 104 0 1 > "$TMPD/conf-ns"
run nostrut "$TMPD/conf-ns" "wmax nostrut"
aus=$(python3 tools/desktop/rects.py "$TMPD/nostrut.txt" bottom 28 --nostrut 2>&1)
if [ $? -eq 0 ]; then ok "with 'nostrut' the work area is the whole screen and the bar is under the window: $aus"
else bad "the counter-test does not behave as it must"; printf '%s\n' "$aus"; fi
# and the same picture WITH the strut must fail that same check --
# otherwise the checker is not checking anything.
if python3 tools/desktop/rects.py "$TMPD/bottom.txt" bottom 28 --nostrut >/dev/null 2>&1; then
    bad "rects.py lets the normal run pass as if it were the counter-test"
else
    ok "and the normal run does NOT pass the counter-test's expectations"
fi
png "$TMPD/nostrut.ppm" "nostrut"

echo "== 5. dragging the bar to another edge, with real mouse packets =="
python3 - > "$TMPD/mon-drag" <<'PYEOF'
def go(x, y):
    out = ["mouse_move -120 -120"] * 6
    dx, dy = x, y
    while dx > 0 or dy > 0:
        sx, sy = min(dx, 120), min(dy, 120)
        out.append("mouse_move %d %d" % (sx, sy))
        dx -= sx
        dy -= sy
    return out
L = go(520, 586)
L += ["warte 1", "mouse_button 1", "warte 1"]
# pull towards the left edge, in packets a PS/2 mouse can carry
L += ["mouse_move -120 -60"] * 3 + ["mouse_move -40 -66", "warte 1"]
L += ["mouse_move -120 0"] * 2 + ["warte 1"]
L += ["mouse_button 0", "warte 2"]
print("\n".join(L))
PYEOF
conf bottom 28 104 0 1 > "$TMPD/conf-drag"
run drag "$TMPD/conf-drag" "" "$TMPD/mon-drag"
L="$TMPD/drag.txt"
has "$L" "taskbar: drag start" "the press on an empty part of the bar starts a drag"
p0=$(grep -a 'taskbar: drag edge=' "$L" | head -1 | grep -oE 'edge=[0-9]+' | sed 's/.*=//')
same "the first preview rectangle is the edge it started on" "0" "$p0"
p1=$(grep -a 'taskbar: drag edge=' "$L" | tail -1 | grep -oE 'edge=[0-9]+' | sed 's/.*=//')
same "the last preview rectangle is the left edge" "2" "$p1"
prv=$(grep -ac 'taskbar: drag edge=' "$L")
num "the preview followed the pointer (rectangles drawn)" "$prv" ge 2
has "$L" "taskbar: drag done edge=2 written=1" "letting go moved the bar and wrote the file"
g=$(grep -a 'taskbar: geom ' "$L" | tail -1)
same "the bar is now vertical" "1" "$(printf '%s' "$g" | grep -oE 'vertical=[0-9]+' | sed 's/.*=//')"
same "at x=0 with the full height" "x=0 y=0 w=104 h=600" \
    "$(printf '%s' "$g" | grep -oE 'x=[0-9]+ y=[0-9]+ w=[0-9]+ h=[0-9]+')"
w=$(grep -a 'taskbar: work ' "$L" | tail -1 | grep -oE 'x=[0-9]+ y=[0-9]+ w=[0-9]+ h=[0-9]+')
same "and the work area moved with it" "x=104 y=0 w=696 h=600" "$w"
# THE FILE, READ BACK OUT OF THE DISK IMAGE. Not out of the program's
# memory -- out of the blocks.
python3 tools/osum/mkfs.py cat "$TMPD/live-drag.img" /etc/taskbar.conf \
    > "$TMPD/drag.conf" 2>&1
if grep -q '^edge=left$' "$TMPD/drag.conf"; then
    ok "/etc/taskbar.conf on the disk says edge=left"
else
    bad "/etc/taskbar.conf on the disk does not say edge=left"
    sed 's/^/        /' "$TMPD/drag.conf" | head -8
fi
png "$TMPD/drag.ppm" "after-drag"

echo "== 6. the setting survives a restart =="
run reboot "" "wmax" "" "$TMPD/live-drag.img"
L="$TMPD/reboot.txt"
ename=$(grep -a 'taskbar: conf ' "$L" | tail -1 | grep -oE 'ename=[a-z]+' | sed 's/.*=//')
same "booted a second time from the same image, the bar comes up on" "left" "$ename"
aus=$(python3 tools/desktop/rects.py "$L" left 104 2>&1)
if [ $? -eq 0 ]; then ok "and the rectangles are the ones of a left bar: $aus"
else bad "after the restart the rectangles are wrong"; printf '%s\n' "$aus"; fi

echo "== 7. auto-hide: the bar goes away and comes back, in milliseconds =="
python3 - > "$TMPD/mon-hide" <<'PYEOF'
L = ["mouse_move -120 -120"] * 6 + ["warte 3"]
L += ["mouse_move 120 120"] * 3 + ["mouse_move 40 120", "mouse_move 0 119"]
L += ["warte 3"]
print("\n".join(L))
PYEOF
conf bottom 28 104 1 1 > "$TMPD/conf-hide"
run hide "$TMPD/conf-hide" "" "$TMPD/mon-hide"
L="$TMPD/hide.txt"
has "$L" "taskbar: hide" "the pointer left the bar and the bar slid out"
ms=$(grep -a 'taskbar: show ' "$L" | tail -1 | grep -oE 'ms=[0-9]+' | sed 's/.*=//')
if [ -n "$ms" ]; then
    num "the pointer reached the edge and the bar stood there again after" "$ms" le 200
    echo "        (ticks are 10 ms in this kernel, kernel/time.fi TICK_HZ=100 --"
    echo "         that is the resolution of this number, not one millisecond)"
else
    bad "the bar never came back"
fi
# WITH AUTO-HIDE THE RESERVATION IS A SLIVER, IN BOTH STATES. Not the
# full height while it is out and zero while it is in: that would resize
# every maximized window twice a second as the pointer wanders past.
st=$(grep -a 'taskbar: strut ' "$L" | tail -1 | grep -oE 'size=[0-9]+' | sed 's/.*=//')
same "and the reservation stays a sliver the whole time" "2" "$st"
wk=$(grep -a 'taskbar: work ' "$L" | tail -1 | grep -oE 'h=[0-9]+' | sed 's/.*=//')
same "so the work area is the screen minus that sliver" "598" "$wk"
png "$TMPD/hide.ppm" "autohide"

echo "== 8. the settings write the same file, and the bar follows =="
# THE CLICKS ARE COMPUTED, NOT REMEMBERED.
#
# This used to be three pairs of coordinates somebody had read off a
# screenshot once: (172,328), (174,443), (212,471). Round LOOK put a
# shape chooser and an alignment chooser on this page above the taskbar
# section, every control below them moved down, and the three clicks
# landed on the wrong widgets. Six assertions went red and not one of
# them said "the page moved" -- they said the drop-down had not opened.
#
# So the run is in TWO PASSES. The first boots the settings program and
# clicks nothing; the program reports where it put its widgets
# (`settings: rect name=... x= y= w= h=`) and where the window is. From
# those the second pass works out where to press:
#
#   the chooser   the middle of the `edge` rectangle
#   row 3         the drop-down opens directly under the chooser at the
#                 x/y the program reports when it opens, `rh` per row
#   Apply         the middle of the `apply` rectangle
#
# All of it inside the window, whose inner origin is x+2, y+22 -- the
# border and the title bar the SERVER draws, which is why a window
# clamped into a corner reports its OUTER position.
conf bottom 28 104 0 1 > "$TMPD/conf-set"
: > "$TMPD/mon-probe"
run set-probe "$TMPD/conf-set" "einst" "$TMPD/mon-probe" || true
P="$TMPD/set-probe.txt"
rect() { # name field -> value
    grep -a "settings: rect name=$1 " "$P" | tail -1 \
        | grep -oE " $2=[0-9]+" | tail -1 | grep -oE '[0-9]+'
}
WX=$(rect win x);  WY=$(rect win y)
EX=$(rect edge x); EY=$(rect edge y); EW=$(rect edge w); EH=$(rect edge h)
AX=$(rect apply x); AY=$(rect apply y); AW=$(rect apply w); AH=$(rect apply h)
if [ -z "$WX" ] || [ -z "$EX" ] || [ -z "$AX" ]; then
    bad "the settings did not report their geometry -- no clicks can be computed"
    grep -a 'settings: rect' "$P" | sed 's/^/        /' | head -8
else
    ok "the settings report where their taskbar widgets are (win $WX,$WY  edge $EX,$EY  apply $AX,$AY)"
    IX=$((WX + 2)); IY=$((WY + 22))
    CX=$((IX + EX + EW / 2)); CY=$((IY + EY + EH / 2))
    # the menu opens at the chooser's own x and directly under it
    MX=$((IX + EX)); MY=$((IY + EY + EH))
    # The row height of a drop-down is `zeilen_hoehe() + 2`, and
    # `zeilen_hoehe()` is the `row` token the program prints when it
    # starts. Read it, do not assume it: it is 20 under `classic` and
    # 24 under `modern`, and a runner that assumes one of them is a
    # runner that works on one appearance.
    RH=$(grep -a 'settings: shape file=' "$P" | tail -1 \
         | grep -oE ' row=[0-9]+' | grep -oE '[0-9]+')
    if [ -z "$RH" ]; then
        bad "the settings did not report their row height"
        RH=20
    fi
    RH=$((RH + 2))
    # row 3 is "right": bottom, top, left, right
    RX=$((MX + 20)); RY=$((MY + 3 * RH + RH / 2))
    BX=$((IX + AX + AW / 2)); BY=$((IY + AY + AH / 2))
    python3 - "$CX" "$CY" "$RX" "$RY" "$BX" "$BY" > "$TMPD/mon-set" <<'PYEOF'
import sys
def go(x, y):
    out = ["mouse_move -120 -120"] * 6
    dx, dy = x, y
    while dx > 0 or dy > 0:
        sx, sy = min(dx, 120), min(dy, 120)
        out.append("mouse_move %d %d" % (sx, sy))
        dx -= sx
        dy -= sy
    return out
a = [int(v) for v in sys.argv[1:7]]
L = go(a[0], a[1]) + ["warte 1", "mouse_button 1", "mouse_button 0", "warte 2"]
L += go(a[2], a[3]) + ["warte 1", "mouse_button 1", "mouse_button 0", "warte 2"]
L += go(a[4], a[5]) + ["warte 1", "mouse_button 1", "mouse_button 0", "warte 3"]
print("\n".join(L))
PYEOF
    echo "        clicks: chooser $CX,$CY   row3 $RX,$RY   apply $BX,$BY   (rh=$RH)"
    run settings "$TMPD/conf-set" "einst" "$TMPD/mon-set"
    L="$TMPD/settings.txt"
    has "$L" "settings: menu open" "the click opened the drop-down"
    r=$(grep -a 'settings: menu took ' "$L" | tail -1 | grep -oE 'row=[0-9]+' | sed 's/.*=//')
    same "and the row that was clicked is 'right'" "3" "$r"
    has "$L" "settings: taskbar edge=right" "'Uebernehmen' wrote edge=right"
    wr=$(grep -a 'settings: taskbar ' "$L" | tail -1 | grep -oE 'wrote=[0-9]+' | sed 's/.*=//')
    num "and it really wrote a file" "$wr" ge 1
    ename=$(grep -a 'taskbar: conf ' "$L" | tail -1 | grep -oE 'ename=[a-z]+' | sed 's/.*=//')
    same "the taskbar -- a different process -- re-read the file and moved to" "right" "$ename"
    g=$(grep -a 'taskbar: geom ' "$L" | tail -1 | grep -oE 'x=[0-9]+ y=[0-9]+ w=[0-9]+ h=[0-9]+')
    same "to exactly the right edge" "x=696 y=0 w=104 h=600" "$g"
    png "$TMPD/settings.ppm" "settings"
fi

echo "== 9. what the older runners said, and still say =="
for t in tools/wm/run.sh tools/k15/run.sh; do
    if [ -x "$t" ] || [ -f "$t" ]; then
        bash "$t" > "$TMPD/$(basename $(dirname $t)).log" 2>&1
        line=$(tail -4 "$TMPD/$(basename $(dirname $t)).log" | grep -iE '[0-9]+ passed' | tail -1)
        nf=$(printf '%s' "$line" | grep -oiE '[0-9]+ failed' | grep -oE '[0-9]+')
        if [ -n "$line" ]; then
            if [ "${nf:-1}" -eq 0 ]; then ok "$t: $line"
            else bad "$t: $line"; fi
        else
            bad "$t: no summary line"
            tail -5 "$TMPD/$(basename $(dirname $t)).log" | sed 's/^/        /'
        fi
    fi
done

echo
echo "screenshots: $SHOTS"
echo "TASKBAR: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
