#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/appicon/run.sh -- host test of lib/appicon.fi + wiring audit of the fallback icon (seconds, no QEMU).
#   bash tools/appicon/run.sh [repo-root]
# 1) lib/appicon.fi compiles in profile kernel  2) host unit test  3) palette contrast >= 4.5 for white text
# 4) wiring: bar, start menu, Alt+Tab, task manager all use the one module  5) COUNTER-PROOF: a tree without the wiring fails
set -uo pipefail
ROOT=${1:-$(cd "$(dirname "$0")/../.." && pwd)}
cd "$ROOT"
[ -x vendor/firn/bin/firnc ] || bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok()  { echo "  OK    $*"; PASS=$((PASS+1)); }
bad() { echo "  FAIL  $*"; FAIL=$((FAIL+1)); }
cat > "$T/kcheck.fi" <<'FI'
profile kernel
import appicon
fn main() -> i32 {
    return appicon.hash_of(0) as i32
}
FI
if FIRNLIB="$ROOT/lib" vendor/firn/bin/firnc --profile=kernel -c "$T/kcheck.fi" -o "$T/kcheck.o" > "$T/kcheck.log" 2>&1; then ok "lib/appicon.fi compiles in profile kernel"; else bad "kernel compile"; grep -v '^warning' "$T/kcheck.log" | head; fi
if FIRNLIB="$ROOT/lib" vendor/firn/bin/firnc --profile=app tools/appicon/host.fi -o "$T/host" > "$T/host.log" 2>&1; then
    "$T/host" > "$T/host.out"; rc=$?
    grep '^FAIL' "$T/host.out" | head -20
    tail -1 "$T/host.out"
    [ "$rc" = 0 ] && ok "host unit test" || bad "host unit test (exit $rc)"
else bad "host build"; grep -v '^warning' "$T/host.log" | head -20; fi
python3 -I - "$T/host.out" <<'PY' && ok "palette: 12 colours, white text contrast >= 4.5" || bad "palette contrast"
import sys
def lin(c):
    c/=255
    return c/12.92 if c<=0.03928 else ((c+0.055)/1.055)**2.4
pal=[]
for l in open(sys.argv[1]):
    if l.startswith("pal "): pal.append(int(l.split()[2]))
assert len(pal)==12 and len(set(pal))==12, pal
for v in pal:
    L=0.2126*lin(v>>16&255)+0.7152*lin(v>>8&255)+0.0722*lin(v&255)
    cr=1.05/(L+0.05)
    if cr<4.5:
        print("low contrast %06x %.2f"%(v,cr)); sys.exit(1)
PY
wire() { # wire <root>: prints OK/FAIL lines
python3 -I - "$1" <<'PY'
import sys,re,os
r=sys.argv[1]
def rd(p): return open(os.path.join(r,p),'rb').read().decode('latin1')
def say(ok,m): print(("OK    " if ok else "FAIL  ")+m)
say("app_icon" in rd("kernel/user/taskbar.fi"), "bar: taskbar.sym_of asks appicon (wlibc.app_icon)")
say("app_icon" in rd("kernel/user/appdir.fi"), "start menu: appdir.icon_load asks the fallback")
say("appicon." in rd("kernel/ui/wm.fi"), "Alt+Tab: wm switcher paints the fallback tile")
say("app_icon" in rd("kernel/user/taskmgr.fi"), "task manager: program rows ask the fallback")
PY
}
wire "$ROOT" > "$T/wire.out"; cat "$T/wire.out"; PASS=$((PASS+$(grep -c '^OK' "$T/wire.out"))); FAIL=$((FAIL+$(grep -c '^FAIL' "$T/wire.out")))
# COUNTER-PROOF: the tree before the wiring (git stash-free: copy of the files with the calls removed) must fail
mkdir -p "$T/old/kernel/user" "$T/old/kernel/ui"
for f in kernel/user/taskbar.fi kernel/user/appdir.fi kernel/ui/wm.fi kernel/user/taskmgr.fi; do sed 's/app_icon\|appicon\./REMOVED_/g' "$f" > "$T/old/$f"; done
wire "$T/old" > "$T/wire.old"
if [ "$(grep -c '^FAIL' "$T/wire.old")" = 4 ]; then ok "counter-proof: without the wiring all four places are red"; else bad "counter-proof did not turn red"; fi
echo "== APPICON: $PASS green, $FAIL red =="
[ "$FAIL" = 0 ]
