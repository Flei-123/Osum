#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/iconfb/run.sh -- counts programs that would draw the letter-tile fallback instead of the baked SVG symbol. Ratchet: 0.
set -uo pipefail
cd "$(dirname "$0")/../.."
python3 -I - <<'PY'
import glob, os, re, sys
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
