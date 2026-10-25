#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/wmheads/run.sh -- r826 WINDOW SERVER PER OUTPUT.
#
# WHAT IT MEASURES (QEMU, virtio-gpu max_outputs=2, heads 640x480, extended desktop 1280x480)
#   Word `hdtest` runs a test bed after the window server is up (kernel/ui/wm.fi hd_demo) and prints `hd:` lines:
#   1. a 28 px bottom bar over the whole desktop is a strut on BOTH heads (work area 452 high on each head,
#      head 1 starts at x=640);
#   2. a window on head 1, maximized, fills the work area of head 1 (x=640 w=640 h=452), NOT the desktop;
#      a window on head 0 fills head 0; un-maximize keeps the window on its head;
#   3. fullscreen of a window on head 1 = exactly head 1 (640,0 640x480);
#   4. pointer clamp with heads of different height: a point below the short head goes back onto it;
#   4b. r828 edge docking on head 1 (floating halves at the outer edges, not at the seam, not with docking off);
#   5. word `hdhot`: unplug head 1 -> the window comes to head 0 (maximized = head 0 work area), only head 0 left;
#      replug -> head 1 is back with its strut.
# COUNTER-CONTROLS: a plain single-head machine prints "hd: no extend" and no head lines (model off);
#   the old behaviour (hdtest without vgpuextend) keeps a work area of the whole screen.
#
# Usage: [WMH_KERNEL=<kernel.mb>] bash tools/wmheads/run.sh   (builds its own kernel when unset)
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh >/dev/null 2>&1
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
K=${WMH_KERNEL:-$T/k.mb}
if [ -z "${WMH_KERNEL:-}" ]; then
    bash tools/build-kernel.sh "$K" >"$T/build.log" 2>&1 || { echo "build failed"; tail -20 "$T/build.log"; exit 1; }
fi
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

python3 tools/osum/mkfs.py build "$T/d.img" 32768 --v3 /lib/ \
    /lib/mono.ttf=assets/osum-mono.ttf /lib/sans.ttf=assets/osum-sans.ttf >/dev/null 2>&1

run_case() { # run_case <tag> <max_outputs> <kernel words>
    local tag=$1 mo=$2 words=$3
    cp -f "$T/d.img" "$T/$tag.img"
    timeout 120 $QEMU_X86 -kernel "$K" -m 256 \
        -append "gfx disp wm wmhold osum vfs $words nokbd" \
        -serial "file:$T/$tag.txt" -display none -no-reboot \
        -vga std -device virtio-gpu-pci,id=vg,max_outputs=$mo,xres=640,yres=480 -global VGA.edid=off \
        -drive "file=$T/$tag.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
}
hd() { grep -a "^hd: $1 " "$T/$2.txt" | head -1; }  # hd <tag> <case>
has() { grep -aq "$1" "$T/$2.txt"; }                   # has <regex> <case>

echo "== two heads, hdtest + hdhot"
run_case two 2 "fbres=1280x480 vgpuheads vgpuextend hdtest hdhot"
grep -a "^wm: head \|^wm: heads \|^hd: " "$T/two.txt" | head -90 | sed 's/^/   /'
has '^wm: head 0 rect=0,0 640x480 work=0,0 640x452$' two && ok "head 0 work area 640x452 (bar strut)" || bad "head 0 work area"
has '^wm: head 1 rect=640,0 640x480 work=640,0 640x452$' two && ok "head 1 work area 640,0 640x452 (bar strut on head 1 too)" || bad "head 1 work area"
hd max1 two | grep -aq 'x=640 y=0 w=640 h=452 head=1' && ok "maximize on head 1 fills head 1 work area" || bad "max1: $(hd max1 two)"
hd max0 two | grep -aq 'x=0 y=0 w=640 h=452 head=0' && ok "maximize on head 0 fills head 0 work area" || bad "max0: $(hd max0 two)"
hd unmax1 two | grep -aq 'head=1' && ok "un-maximize keeps the window on head 1" || bad "unmax1: $(hd unmax1 two)"
hd full1 two | grep -aq 'x=640 y=0 w=640 h=480 head=1' && ok "fullscreen on head 1 = head 1 (640,0 640x480)" || bad "full1: $(hd full1 two)"
has '^hd: clamp x=700 y=239$' two && ok "pointer below the 240-high head 1 is pulled onto it (700,239)" || bad "clamp: $(grep -a '^hd: clamp' $T/two.txt)"
grep -aqE '^wm: hscale 0=(100|125|150|175|200|250|300) u=[1-4]$' $T/two.txt && grep -aqE '^wm: hscale 1=(100|125|150|175|200|250|300) u=[1-4]$' $T/two.txt && ok "r815: every head reports its EDID scale suggestion (percent) next to the UI scale in use" || bad "hscale lines: $(grep -a '^wm: hscale' $T/two.txt | head -3)"
grep -aq '^wm: hscale 0=100 u=1$' $T/two.txt && ok "r815: QEMU EDID (100 dpi) suggests 100 %, UI scale stays 1 (no regression of the VM gates)" || bad "hscale 0 not 100/1"
# r839: tile tree per head (hdtest tile section: bar and old windows gone, tiling on, head work areas = head rects)
has '^hd: trees start nodes=0 leaves=0$' two && ok "r839: clean slate, no tiled window" || bad "tile start"
hd tile-c1 two | grep -aq 'x=640 y=0 w=640 h=480 head=1' && ok "r839: first window on head 1 fills head 1 (own tree)" || bad "tile-c1: $(hd tile-c1 two)"
grep -aq '^hd: tree tile-c1 tree=1 tiled=1$' $T/two.txt && ok "r839: that window is in tree 1 (head 1)" || bad "tree tile-c1"
hd tile-c0 two | grep -aq 'x=0 y=0 w=640 h=480 head=0' && ok "r839: first window on head 0 fills head 0 (main tree)" || bad "tile-c0: $(hd tile-c0 two)"
grep -aq '^hd: tree tile-c0 tree=0 tiled=1$' $T/two.txt && ok "r839: that window is in tree 0 (primary head)" || bad "tree tile-c0"
hd split-c1 two | grep -aq 'x=640 y=0 w=320 h=480 head=1' && ok "r839: 2nd window on head 1 splits head 1: left half" || bad "split-c1: $(hd split-c1 two)"
hd split-c2 two | grep -aq 'x=960 y=0 w=320 h=480 head=1' && ok "r839: ... right half" || bad "split-c2: $(hd split-c2 two)"
[ "$(grep -a '^hd: tile-c0 ' $T/two.txt | tail -1 | grep -ac 'x=0 y=0 w=640 h=480 head=0')" = 1 ] && ok "r839: head 0 untouched by the split on head 1" || bad "head 0 changed"
has '^hd: drope=3 pos=top1$' two && ok "r839: top edge of head 1 -> docking edge 3 (tiled upper half)" || bad "top1 hover"
hd top-c0 two | grep -aq 'x=640 y=0 w=640 h=240 head=1' && ok "r839: dragged window from head 0 = upper half of head 1" || bad "top-c0: $(hd top-c0 two)"
hd top-c1 two | grep -aq 'x=640 y=240 w=320 h=240 head=1' && ok "r839: the others share the lower half (left)" || bad "top-c1: $(hd top-c1 two)"
hd top-c2 two | grep -aq 'x=960 y=240 w=320 h=240 head=1' && ok "r839: ... (right)" || bad "top-c2: $(hd top-c2 two)"
has '^hd: drope=0 pos=seam$' two && ok "r828: the seam between the heads is no docking edge" || bad "seam"
has '^hd: drope=0 pos=middle$' two && ok "r828: the middle of a head: no docking edge" || bad "middle"
has '^hd: drope=0 pos=off$' two && ok "r828: tiling off: no docking on head 1" || bad "off"
for k in c0 c1 c2; do
    grep -aq "^hd: tree unplug-$k tree=0 tiled=1\$" $T/two.txt && ok "r839: unplug head 1: $k back in the main tree" || bad "unplug tree $k"
done
hd unplug-c1 two | grep -aq 'x=0 y=0 w=320 h=480 head=0' && ok "r839: unplug: windows re-tiled onto head 0 (left half)" || bad "unplug-c1: $(hd unplug-c1 two)"
hd replug-c3 two | grep -aq 'x=640 y=0 w=640 h=480 head=1' && ok "r839: replug: a new window on head 1 gets a fresh tree, fills head 1" || bad "replug-c3: $(hd replug-c3 two)"
grep -aq '^hd: tree replug-c3 tree=1 tiled=1$' $T/two.txt && ok "r839: replug: new tree tag 1" || bad "replug tree"
has '^hd: trees end nodes=0 leaves=0$' two && ok "r839: tiling off releases every tree" || bad "trees end"
hd unplug-a two | grep -aq 'x=0 y=0 w=640 h=452 head=0' && ok "unplug head 1: maximized window refit to head 0 work area" || bad "unplug-a: $(hd unplug-a two)"
has '^wm: heads n=2 present=1 ' two && ok "unplug: one head present" || bad "unplug: present count"
hd replug-bar two | grep -aq 'head=' && ok "replug ran" || bad "replug missing"
has '^wm: head 1 rect=640,0 640x480 work=640,0 640x452$' two && ok "replug: head 1 back with its strut" || bad "replug head 1"
hd mirror-pre two | grep -aq 'head=1' && ok "r872: new window stands on head 1 before the mirror switch" || bad "mirror-pre: $(hd mirror-pre two)"
hd mode-on two | grep -aq 'mirror=1 connected=2 present=1' && ok "r872: run-time mirror: 2 connected, 1 head in the window server" || bad "mode-on: $(hd mode-on two)"
hd mirror-on two | grep -aq 'head=0' && ok "r872: mirror: the window on head 1 came to head 0" || bad "mirror-on: $(hd mirror-on two)"
hd mode-off two | grep -aq 'mirror=0 connected=2 present=2' && ok "r872: back to extend: 2 heads in the window server" || bad "mode-off: $(hd mode-off two)"

echo "== control: single head (max_outputs=1) with the same words"
run_case one 1 "fbres=1280x480 vgpuheads vgpuextend hdtest"
has '^hd: no extend$' one && ok "one head: per-head model off" || bad "one head: model on"
! has '^wm: head 1 ' one && ok "one head: no head 1 line" || bad "one head: head 1 line"

echo "wmheads: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
