#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/fui/navkit-sync.sh -- lib/fui/navkit.fi and navnum.fi here must equal Firn's (see lib/FROM-FIRN.md).
cd "$(dirname "$0")/../.."
FIRN=${FIRN_REPO:-/root/jarvis/projects/u_DiS4in7esMF1/firn}
if [ ! -f "$FIRN/lib/fui/navkit.fi" ]; then echo "navkit-sync: Firn has no navkit.fi (yet) at $FIRN -- skipped"; exit 0; fi
rc=0
for f in navkit navnum cmdbar; do
    cmp -s "lib/fui/$f.fi" "$FIRN/lib/fui/$f.fi" || { echo "navkit-sync: $f.fi DIFFERENT"; rc=1; }
done
[ $rc -eq 0 ] && echo "navkit-sync: identical"
exit $rc
