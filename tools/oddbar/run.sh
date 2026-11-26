#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/../lib/brand-env.sh"
# SPDX-License-Identifier: GPL-2.0-only
# tools/oddbar/run.sh -- taskbar pixels at an ODD screen width with UI scale 2 (VirtualBox 2495x1506 gave an empty bar).
# The desktop boots on QEMU -vga vmware with `uiscale=2` and `vmsvgaodd`, whose first hint is 1397x777 (odd; sp(width()) = 1396 != 1397).
# Judged on the first hint step: the centre half of the bar holds icon ink (dark pixels), not just empty ghost pills.
# Counter-proof: the same run with bar_overlay compared against sp(width()) again must have almost no ink.
# Usage: [IMG=<stick image>] bash tools/oddbar/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
HERE=$(pwd)/tools/oddbar
T=$(mktemp -d)
cp kernel/user/taskbar/tbpaint.fi "$T/tbpaint.fi.orig"
trap 'cp "$T/tbpaint.fi.orig" kernel/user/taskbar/tbpaint.fi; rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok()  { echo "  OK    $*"; PASS=$((PASS+1)); }
bad() { echo "  FAIL  $*"; FAIL=$((FAIL+1)); }
MIN_INK=600
MAX_INK_BROKEN=200
ATTEMPTS=3
shoot() {
    local name=$1 image=$2 try
    for try in $(seq "$ATTEMPTS"); do
        rm -rf "$T/$name"
        EXTRA_WORDS="vmsvgaodd uiscale=2" SIZES=1397x777,1111x703,1853x1049 KEEP="$T/$name" IMG="$image" bash tools/vmsvgaresize/run.sh > "$T/$name.log" 2>&1
        [ -s "$T/$name/o.1.ppm" ] && break
    done
    [ -s "$T/$name/o.1.ppm" ] || return 1
    python3 -I -W ignore "$HERE/ink.py" "$T/$name/o.1.ppm"
}
build_image() {
    local name=$1
    mkdir -p "$T/$name.img"
    PARTTAB=mbr bash tools/usbimg/build.sh "$T/$name.img" > "$T/$name.build.log" 2>&1 || return 1
    echo "$T/$name.img/${MARKE_DATEI}-usb.img"
}
good_img=${IMG:-$(build_image good)}
[ -s "$good_img" ] || { bad "no image"; echo "ODDBAR: $PASS passed, $FAIL failed"; exit 1; }
echo "== A. odd width, scale 2, fixed tree"
read -r w h ink < <(shoot good "$good_img")
[ "$((${w:-0} % 2))" = 1 ] && ok "first hint is odd wide (${w}x${h})" || bad "width '$w' is not odd"
[ "${ink:-0}" -ge "$MIN_INK" ] && ok "bar centre has icon ink ($ink dark pixels >= $MIN_INK)" || bad "bar centre is empty ($ink dark pixels)"
echo "== B. counter-proof: overlay compared against sp(width())"
sed -i 's/fuiscene.canvas_w()/fuiscene.sp(fuiscene.width())/; s/fuiscene.canvas_h()/fuiscene.sp(fuiscene.height())/' kernel/user/taskbar/tbpaint.fi
cmp -s "$T/tbpaint.fi.orig" kernel/user/taskbar/tbpaint.fi && bad "mutation did not apply"
broken_img=$(build_image broken)
cp "$T/tbpaint.fi.orig" kernel/user/taskbar/tbpaint.fi
[ -s "$broken_img" ] || { bad "no counter-proof image"; echo "ODDBAR: $PASS passed, $FAIL failed"; exit 1; }
read -r w2 h2 ink2 < <(shoot broken "$broken_img")
[ "${ink2:-9999}" -le "$MAX_INK_BROKEN" ] && ok "counter-proof is red: bar centre empty ($ink2 dark pixels <= $MAX_INK_BROKEN)" || bad "counter-proof not red ($ink2 dark pixels)"
echo "ODDBAR: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
