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
N=$(grep -c '/symbol=' "$TMP/list")
[ "$N" = 0 ] && ok "bundle listing ships no per-bundle symbol (registry owns icons)" || bad "bundle listing still has $N symbol lines"
python3 -I tools/appreg/build.py "$PWD" "$TMP/reg" > "$TMP/reg.log" 2>&1 && ok "registry builds a symbol for every app" || bad "registry build: $(tail -1 "$TMP/reg.log")"
NB=$(ls -d assets/apps/*.osp | wc -l)
NS=$(for d in assets/apps/*.osp; do b=$(basename "$d" .osp); [ -s "$TMP/reg/usr/share/appreg/$b/symbol" ] || [ -s "$TMP/reg/usr/share/appreg/$(sed -n "s/^\([a-z0-9]*\)\t.*apps\/$b\.osp\$/\1/p" tools/appreg/alias.tsv | head -1)/symbol" ] || echo "$b"; done | wc -l)
[ "$NS" = 0 ] && ok "every bundle resolves to a registry symbol ($NB bundles)" || bad "$NS bundles without registry symbol"

check_overlay() {
    local mod=$1 want got
    mkdir -p "$TMP/out1"
    want=$(grep -c -E '^/apps/[^/]+/(INFO|SYSTEM|data/README)=' "$TMP/list")
    got=$(python3 -I "$mod" "$TMP/list" "$TMP/out1" | grep -c '^bundlefiles: /apps/')
    [ "$got" = "$want" ] && [ "$want" -gt 0 ] && ! find "$TMP/out1" -name symbol | grep -q . && [ -s "$TMP/out1/apps/certus.osp/INFO" ] && [ -s "$TMP/out1/apps/certus.osp/data/README" ]
}
if check_overlay tools/ota/bundlefiles.py; then ok "overlay ships every bundle file and no symbol"; else bad "overlay bundle files"; fi
sed 's/result.append((m.group(1), m.group(2), m.group(3)))/pass/' tools/ota/bundlefiles.py > "$TMP/mut.py"
rm -rf "$TMP/out1"
if check_overlay "$TMP/mut.py"; then bad "mutation 'never-ship-files' not caught"; else ok "mutation 'never-ship-files' is caught"; fi
grep -q 'tools/ota/bundlefiles.py' tools/ota/republish-hp.sh && ok "republish-hp.sh ships bundle files" || bad "republish-hp.sh not wired to bundlefiles.py"

if [ "${ICONFB_QUICK:-0}" != 1 ]; then
    bash tools/iconfb/boot.sh "$TMP/boot" || FAIL=$((FAIL + 1))
fi
echo "iconfb: $FAIL failure(s)"
[ "$FAIL" = 0 ]
