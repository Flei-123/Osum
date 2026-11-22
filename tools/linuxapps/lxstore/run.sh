#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../../.."
ROOT=$(pwd)
LXROOT=${LXSTORE_ROOT:-/root/abbilder/lapps/root}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { echo "  OK    $*"; pass=$((pass+1)); }
bad() { echo "  FAIL  $*"; fail=$((fail+1)); }
MK="python3 -I tools/linuxapps/lxstore/mkpkgs.py"

python3 -I tools/linuxapps/lxstore/test_plan.py > "$T/unit.txt" 2>&1 && ok "closure + runtime/app split: $(tail -1 "$T/unit.txt")" || { bad "plan unit test"; tail -5 "$T/unit.txt"; }

python3 -I tools/linuxapps/lxstore/check_icons.py > "$T/reg.txt" 2>&1 && ok "registry: every icon key is in tools/svg/apps.tsv and resolves to a bundle" || { bad "registry icons"; cat "$T/reg.txt"; }

cp tools/linuxapps/store-apps.tsv "$T/bad.tsv"
sed -i 's/\tterminal\t/\tno-such-icon\t/' "$T/bad.tsv"
python3 -I tools/linuxapps/lxstore/check_icons.py "$T/bad.tsv" > "$T/mut.txt" 2>&1 && bad "mutant: unknown icon key not caught" || { grep -q 'not in the icon registry' "$T/mut.txt" && ok "mutant: unknown icon key is caught" || { bad "mutant: wrong message"; cat "$T/mut.txt"; }; }

if [ -f "$LXROOT/lib/apk/db/installed" ]; then
    echo stub > "$T/launcher"
    $MK --root "$LXROOT" --launcher "$T/launcher" --out "$T/out" --apps foot,galculator > "$T/build.txt" 2>&1 && ok "foot + galculator + linuxrt build" || { bad "build failed"; tail -5 "$T/build.txt"; }
    for p in linuxrt foot galculator; do [ -s "$T/out/$p-1.opk" ] && ok "$p-1.opk exists" || bad "$p-1.opk missing"; done
    OPK=$(python3 -I -c 'import sys; sys.path.insert(0,"tools/lib"); import opkpfad; print(opkpfad.path_2())')
    python3 -I "$OPK" zeigen "$T/out/foot-1.opk" > "$T/info.txt" 2>&1
    grep -q 'linuxrt' "$T/info.txt" && ok "foot depends on linuxrt" || { bad "foot has no dependency on linuxrt"; head -5 "$T/info.txt"; }
    grep -q '^category=System' "$T/out/foot.store.meta" && grep -q '^icon=terminal' "$T/out/foot.store.meta" && ok "foot meta: category + icon from registry" || bad "foot meta wrong"
    n=$(ls "$T/out" | grep -c '^foot.tar.part'); [ "$n" -ge 1 ] && ok "foot payload split into $n part(s)" || bad "foot has no parts"
else
    echo "  SKIP  no prepared Alpine root ($LXROOT)"
fi
echo "LXSTORE: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
