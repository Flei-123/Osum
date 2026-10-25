#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/fontchain/run.sh -- G-009: font fallback chain (lib/fontchain.fi registry) + pair kerning, host test with pixel checks (seconds, no QEMU).
#   bash tools/fontchain/run.sh [repo-root]
# 1) registry + fallback + kerning against the real font files (host.fi, rasterised pixels)
# 2) wiring audit: fuiglyph asks the registry (miss callback, rasteriser, kerning), no hard-wired faces left
# 3) COUNTER-PROOFS: nofallback (chain disabled) fails 1), nokern (font without kerning) fails 1), unwired fuiglyph fails 2)
set -uo pipefail
ROOT=${1:-$(cd "$(dirname "$0")/../.." && pwd)}
cd "$ROOT"
[ -x vendor/firn/bin/firnc ] || bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok()  { echo "  OK    $*"; PASS=$((PASS+1)); }
bad() { echo "  FAIL  $*"; FAIL=$((FAIL+1)); }

mkdir -p "$T/fonts" "$T/monofonts"
cp assets/osum-sans.ttf "$T/fonts/sans.ttf"; cp assets/osum-symbols.ttf "$T/fonts/symbols.ttf"; cp assets/osum-emoji.ttf "$T/fonts/emoji.ttf"
cp assets/osum-mono.ttf "$T/monofonts/sans.ttf"; cp assets/osum-symbols.ttf "$T/monofonts/symbols.ttf"; cp assets/osum-emoji.ttf "$T/monofonts/emoji.ttf"

build_host() { # build_host <libdir> <out>
    FIRNLIB="$1" vendor/firn/bin/firnc --profile=app tools/fontchain/host.fi -o "$2" > "$T/build.log" 2>&1
}
run_host() { # run_host <bin> <fontdir> <out>
    (cd "$2" && "$1" > "$3" 2>&1)
}

if FIRNLIB="$ROOT/lib" vendor/firn/bin/firnc --profile=app -c kernel/user/charmap.fi -o "$T/charmap.o" > "$T/fg.log" 2>&1; then ok "fuiglyph (via charmap) compiles in profile app"; else bad "fuiglyph compile"; grep -v '^warning' "$T/fg.log" | head; fi

if build_host "$ROOT/lib" "$T/host"; then
    run_host "$T/host" "$T/fonts" "$T/host.out"; rc=$?
    grep -a '^FAIL' "$T/host.out" | head -20
    grep -a '^\(cp\|kern\|gap\) ' "$T/host.out" | sed 's/^/        /'
    tail -1 "$T/host.out"
    n_ok=$(grep -ac '^ok ' "$T/host.out"); PASS=$((PASS+n_ok))
    [ "$rc" = 0 ] && ok "host test: registry, fallback pixels, kerning pixels" || bad "host test (exit $rc)"
else bad "host build"; grep -v '^warning' "$T/build.log" | head -20; fi

mkdir -p "$T/lib-nofb"; cp -r lib/. "$T/lib-nofb/"
sed -i 's/^    s_enabled = v$/    s_enabled = 0/' "$T/lib-nofb/fontchain.fi"
if build_host "$T/lib-nofb" "$T/host-nofb"; then
    run_host "$T/host-nofb" "$T/fonts" "$T/nofb.out"; rc=$?
    nf=$(grep -ac '^FAIL' "$T/nofb.out")
    if [ "$rc" != 0 ] && [ "$nf" -ge 8 ]; then ok "counter-proof nofallback: chain disabled -> $nf checks red (missing box, no ink)"; else bad "counter-proof nofallback not caught (exit $rc, $nf red)"; fi
else bad "nofallback build"; fi

if [ -x "$T/host" ]; then
    run_host "$T/host" "$T/monofonts" "$T/nokern.out"; rc=$?
    if [ "$rc" != 0 ] && grep -aq '^FAIL sans carries kerning pairs' "$T/nokern.out"; then ok "counter-proof nokern: a font without pairs is caught"; else bad "counter-proof nokern not caught (exit $rc)"; fi
fi

wire() { # wire <root>
python3 -I - "$1" <<'PY'
import sys,os,re
r=sys.argv[1]
src=open(os.path.join(r,"kernel/user/fuiglyph.fi"),'rb').read().decode('latin1')
def fn(name):
    m=re.search(r'^fn '+name+r'\(.*?^}', src, re.S|re.M)
    return m.group(0) if m else ""
def say(ok,m): print(("OK    " if ok else "FAIL  ")+m)
say("import fontchain" in src, "fuiglyph imports the registry")
say("fontchain.find" in fn("fb_miss"), "painter miss callback asks the registry")
say("fontchain.find" in fn("fb_slot"), "rasteriser / character map lookup asks the registry")
say("fontchain.pair_kern" in fn("fb_kern"), "kerning inside a fallback face asks the registry")
say("fb_kern" in fn("kern26"), "kern26 reaches the fallback kerning")
say(not re.search(r'/lib/(symbols|emoji)\.ttf', src), "no hard-wired face paths left in fuiglyph")
say("SLOT_SYM" not in src and "SLOT_EMO" not in src, "no hard-wired face slots left in fuiglyph")
PY
}
wire "$ROOT" > "$T/wire.out"; cat "$T/wire.out"
PASS=$((PASS+$(grep -c '^OK' "$T/wire.out"))); FAIL=$((FAIL+$(grep -c '^FAIL' "$T/wire.out")))
mkdir -p "$T/old/kernel/user"
sed 's/fontchain\.find/REMOVED_/g' kernel/user/fuiglyph.fi > "$T/old/kernel/user/fuiglyph.fi"
wire "$T/old" > "$T/wire-old.out"
if grep -q '^FAIL' "$T/wire-old.out"; then ok "counter-proof unwired: $(grep -c '^FAIL' "$T/wire-old.out") audit lines red"; else bad "counter-proof unwired not caught"; fi

echo "FONTCHAIN: $PASS ok, $FAIL fail"
[ "$FAIL" = 0 ]
