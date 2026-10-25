#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/fonthint/run.sh -- G-009b: light vertical autohint (lib/fonthint.fi) for small sizes, host test with a pixel metric (seconds, no QEMU).
#   bash tools/fonthint/run.sh [repo-root]
# 1) host.fi rasterises E T F Z z at 9..16 px with and without hinting: top-row fill (crispness), exact zone rows, width and area kept
# 2) wiring audit: fuiglyph glyph_into asks fonthint.vfactor and rasterises through the y-scaling outline
# 3) COUNTER-PROOFS: nohint (hinting off) fails 1), unwired fuiglyph fails 2), overhint (factor applied to every top) fails 1)
# 4) fUi painter (r1927): painter.fi paints E rows at 9..16 px through fui.painter with the hook (vendor patch 0011); audit: fuiglyph.fontset attaches it; counter-proofs nopainter, unattached
set -uo pipefail
ROOT=${1:-$(cd "$(dirname "$0")/../.." && pwd)}
cd "$ROOT"
[ -x vendor/firn/bin/firnc ] || bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok()  { echo "  OK    $*"; PASS=$((PASS+1)); }
bad() { echo "  FAIL  $*"; FAIL=$((FAIL+1)); }

mkdir -p "$T/fonts"
cp assets/osum-sans.ttf "$T/fonts/sans.ttf"; cp assets/osum-symbols.ttf "$T/fonts/symbols.ttf"

build_host() {
    FIRNLIB="$1" vendor/firn/bin/firnc --profile=app tools/fonthint/host.fi -o "$2" > "$T/build.log" 2>&1
}
run_host() {
    (cd "$T/fonts" && "$1" > "$2" 2>&1)
}

if build_host "$ROOT/lib" "$T/host"; then
    run_host "$T/host" "$T/host.out"; rc=$?
    grep -a '^FAIL' "$T/host.out" | head -20
    grep -a '^\(zones\|crisp\) ' "$T/host.out" | sed 's/^/        /'
    tail -1 "$T/host.out"
    PASS=$((PASS+$(grep -ac '^ok ' "$T/host.out")))
    [ "$rc" = 0 ] && ok "host test: crispness, rows, width, area" || bad "host test (exit $rc)"
else bad "host build"; grep -v '^warning' "$T/build.log" | head -20; fi

mkdir -p "$T/lib-nohint"; cp -r lib/. "$T/lib-nohint/"
sed -i 's/^static mut s_enabled: u64 = 1$/static mut s_enabled: u64 = 0/; s/^    s_enabled = v$/    s_enabled = 0/' "$T/lib-nohint/fonthint.fi"
if build_host "$T/lib-nohint" "$T/host-nohint"; then
    run_host "$T/host-nohint" "$T/nohint.out"; rc=$?
    nf=$(grep -ac '^FAIL' "$T/nohint.out")
    if [ "$rc" != 0 ] && [ "$nf" -ge 2 ]; then ok "counter-proof nohint: hinting off -> $nf checks red"; else bad "counter-proof nohint not caught (exit $rc, $nf red)"; fi
else bad "nohint build"; fi

mkdir -p "$T/lib-over"; cp -r lib/. "$T/lib-over/"
sed -i 's/^    let tol: i32 = upem \/ 48$/    let tol: i32 = upem/' "$T/lib-over/fonthint.fi"
if build_host "$T/lib-over" "$T/host-over"; then
    run_host "$T/host-over" "$T/over.out"; rc=$?
    nf=$(grep -ac '^FAIL' "$T/over.out")
    if [ "$rc" != 0 ] && [ "$nf" -ge 1 ]; then ok "counter-proof overhint: every top snapped -> $nf checks red"; else bad "counter-proof overhint not caught (exit $rc, $nf red)"; fi
else bad "overhint build"; fi

if FIRNLIB="$ROOT/lib" vendor/firn/bin/firnc --profile=app -c kernel/user/charmap.fi -o "$T/charmap.o" > "$T/fg.log" 2>&1; then ok "fuiglyph (via charmap) compiles in profile app"; else bad "fuiglyph compile"; grep -v '^warning' "$T/fg.log" | head; fi

wire() {
python3 -I - "$1" <<'PY'
import sys,os,re
r=sys.argv[1]
src=open(os.path.join(r,"kernel/user/fuiglyph.fi"),'rb').read().decode('latin1')
def fn(name):
    m=re.search(r'^fn '+name+r'\(.*?^}', src, re.S|re.M)
    return m.group(0) if m else ""
def say(ok,m): print(("OK    " if ok else "FAIL  ")+m)
g=fn("glyph_into")
say("import fonthint" in src, "fuiglyph imports the hinter")
say("fonthint.vfactor" in g, "glyph_into asks the hinter for the vertical factor")
say("font_outline_m" in g and "font_outline(" not in g, "glyph_into rasterises through the y-scaling outline")
say(re.search(r'by1 = fceil\(.*vf', g) is not None, "bearing and size use the scaled top")
say("ROLE_ICON" in g[g.find("fonthint.vfactor")-80:g.find("fonthint.vfactor")], "the icon font is never hinted")
PY
}
wire "$ROOT" > "$T/wire.out"; cat "$T/wire.out"
PASS=$((PASS+$(grep -c '^OK' "$T/wire.out"))); FAIL=$((FAIL+$(grep -c '^FAIL' "$T/wire.out")))
mkdir -p "$T/old/kernel/user"
sed 's/fonthint\.vfactor/REMOVED_/g' kernel/user/fuiglyph.fi > "$T/old/kernel/user/fuiglyph.fi"
wire "$T/old" > "$T/wire-old.out"
if grep -q '^FAIL' "$T/wire-old.out"; then ok "counter-proof unwired: $(grep -c '^FAIL' "$T/wire-old.out") audit lines red"; else bad "counter-proof unwired not caught"; fi

build_painter() {
    FIRNLIB="$1" vendor/firn/bin/firnc --profile=app tools/fonthint/painter.fi -o "$2" > "$T/pbuild.log" 2>&1
}
if build_painter "$ROOT/lib" "$T/painter"; then
    run_host "$T/painter" "$T/painter.out"; rc=$?
    grep -a '^FAIL' "$T/painter.out" | head -20
    grep -a '^crisp ' "$T/painter.out" | sed 's/^/        /'
    PASS=$((PASS+$(grep -ac '^ok ' "$T/painter.out")))
    [ "$rc" = 0 ] && ok "painter test: crisp flat tops through fui.painter, no sideways shift" || bad "painter test (exit $rc)"
else bad "painter build"; grep -v '^warning' "$T/pbuild.log" | head -20; fi

mkdir -p "$T/lib-nopainter"; cp -r lib/. "$T/lib-nopainter/"
sed -i 's/^    return vfactor(painter_slot(f), f, px as u64, top)$/    return 1.0/' "$T/lib-nopainter/fonthint.fi"
if build_painter "$T/lib-nopainter" "$T/painter-no"; then
    run_host "$T/painter-no" "$T/painter-no.out"; rc=$?
    nf=$(grep -ac '^FAIL' "$T/painter-no.out")
    if [ "$rc" != 0 ] && [ "$nf" -ge 2 ]; then ok "counter-proof nopainter: hook answers 1.0 -> $nf checks red"; else bad "counter-proof nopainter not caught (exit $rc, $nf red)"; fi
else bad "nopainter build"; fi

attach() {
python3 -I - "$1" "$2" <<'PY'
import sys,os,re
r=sys.argv[1]; v=sys.argv[2]
src=open(os.path.join(r,"kernel/user/fuiglyph.fi"),'rb').read().decode('latin1')
pat=open(os.path.join(v,"lib/fui/painter.fi"),'rb').read().decode('latin1')
m=re.search(r'^fn fontset\(.*?^}', src, re.S|re.M)
fs=m.group(0) if m else ""
def say(ok,t): print(("OK    " if ok else "FAIL  ")+t)
say("fonthint.painter_attach(&(*fs).f)" in fs, "fontset attaches the painter hook")
say("if role != ROLE_ICON {" in fs and fs.find("fonthint.painter_attach") > fs.find("if role != ROLE_ICON {"), "the icon font set never gets the hook")
say("ttf.font_vhint(f, pxi as u32, by1)" in pat and "1.0, 0.0, m10, vy, 0.0, 0.0" in pat, "vendor painter scales glyphs by the hook factor (patch 0011)")
PY
}
attach "$ROOT" "$ROOT/vendor/firn" > "$T/attach.out"; cat "$T/attach.out"
PASS=$((PASS+$(grep -c '^OK' "$T/attach.out"))); FAIL=$((FAIL+$(grep -c '^FAIL' "$T/attach.out")))
mkdir -p "$T/old2/kernel/user"
sed 's/fonthint\.painter_attach/REMOVED_/g' kernel/user/fuiglyph.fi > "$T/old2/kernel/user/fuiglyph.fi"
attach "$T/old2" "$ROOT/vendor/firn" > "$T/attach-old.out"
if grep -q '^FAIL' "$T/attach-old.out"; then ok "counter-proof unattached: $(grep -c '^FAIL' "$T/attach-old.out") audit lines red"; else bad "counter-proof unattached not caught"; fi

echo "FONTHINT: $PASS ok, $FAIL fail"
[ "$FAIL" = 0 ]
