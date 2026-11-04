#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/iconfb/run.sh -- icon fallback ratchet: static (0 bundles without baked symbol), overlay (republish ships missing bundle files), runtime (0 `sym miss` / `sym fb` lines on a booted desktop). ICONFB_QUICK=1 skips the boot.
set -uo pipefail
cd "$(dirname "$0")/../.."
FAIL=0
ok() { echo "  OK    $1"; }
bad() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

python3 -I - <<'PY' || FAIL=$((FAIL + 1))
import glob, os, sys
miss = []
for b in sorted(glob.glob("assets/apps/*.osp")):
    for f in ("symbol.osym", "symbol.svg"):
        if not os.path.isfile(os.path.join(b, f)):
            miss.append("%s: no %s" % (b, f))
for r in sorted(glob.glob("pakete/*/rezept")):
    t = open(r, errors="replace").read()
    if "datei=start" in t and "datei=symbol" not in t:
        miss.append("%s: GUI package without datei=symbol" % r)
for m in miss:
    print("FALLBACK", m)
print("FALLBACK-COUNT", len(miss))
sys.exit(1 if miss else 0)
PY

PROGS=$(for d in assets/apps/*.osp; do head -n 20 "$d/start.txt" | grep -v '^#' | head -n 1 | sed 's|.*/||'; done | tr '\n' ' ')
python3 tools/k15/bundle.py assets/apps "$TMP/work" "nur=$PROGS term" > "$TMP/list" 2>/dev/null
N=$(grep -c '^/apps/[^/]*/symbol=' "$TMP/list")
NB=$(ls -d assets/apps/*.osp | wc -l)
[ "$N" = "$NB" ] && ok "every bundle ships a symbol ($N/$NB)" || bad "bundles with symbol $N of $NB"

check_overlay() {
    local mod=$1
    mkdir -p "$TMP/empty" "$TMP/same" "$TMP/nocertus" "$TMP/out1" "$TMP/out2" "$TMP/out3"
    cp "$TMP"/work/*.symbol "$TMP/same/"
    cp "$TMP"/work/*.symbol "$TMP/nocertus/"
    rm -f "$TMP/nocertus/certus.osp.symbol"
    local a b c
    a=$(python3 -I "$mod" "$TMP/list" "$TMP/empty" "$TMP/out1" | grep -c '/symbol$')
    b=$(python3 -I "$mod" "$TMP/list" "$TMP/same" "$TMP/out2" | grep -c '/symbol$')
    c=$(python3 -I "$mod" "$TMP/list" "$TMP/nocertus" "$TMP/out3" | grep '/symbol$' | tr '\n' ' ')
    [ "$a" = "$NB" ] && [ "$b" = 0 ] && [ "$c" = "bundlefiles: /apps/certus.osp/symbol " ] && [ -s "$TMP/out3/apps/certus.osp/INFO" ] && [ -s "$TMP/out3/apps/certus.osp/data/README" ]
}
if check_overlay tools/ota/bundlefiles.py; then ok "overlay ships exactly the missing/changed bundle symbols"; else bad "overlay bundle files"; fi
sed 's/changed = fresh or not/changed = False and not/' tools/ota/bundlefiles.py > "$TMP/mut.py"
rm -rf "$TMP/out1" "$TMP/out2" "$TMP/out3"
if check_overlay "$TMP/mut.py"; then bad "mutation 'never-ship-symbols' not caught"; else ok "mutation 'never-ship-symbols' is caught"; fi
grep -q 'tools/ota/bundlefiles.py' tools/ota/republish-hp.sh && ok "republish-hp.sh ships bundle files" || bad "republish-hp.sh not wired to bundlefiles.py"

if [ "${ICONFB_QUICK:-0}" != 1 ]; then
    bash tools/iconfb/boot.sh "$TMP/boot" || FAIL=$((FAIL + 1))
fi
echo "iconfb: $FAIL failure(s)"
[ "$FAIL" = 0 ]
