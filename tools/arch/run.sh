#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/arch/run.sh -- layering lint gate (host only, seconds).
#   bash tools/arch/run.sh
# 1) tools/arch/layers.py --strict on the tree: 0 violations of L1 (layer table), A1 (app->app), P1 (import of a program)
# 2) counter-proofs: a planted violation in a scratch copy of kernel/user MUST turn the lint red
#    (base imports toolkit, app imports shell, import of a program)
# 3) baseline file is empty (no accepted debt)
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
ok=0; bad=0
chk() { if [ "$1" = ok ]; then echo "OK    $2"; ok=$((ok+1)); else echo "FAIL  $2"; bad=$((bad+1)); fi; }

out=$(python3 -I tools/arch/layers.py --strict 2>&1); rc=$?
echo "$out" | sed -n '/^violations/,/^--- S1/p' | sed '$d'
[ $rc -eq 0 ] && chk ok "lint strict: no layer violation" || chk bad "lint strict: violations found (rc=$rc)"

[ "$(tr -d ' \n[]' < tools/arch/layers.baseline.json)" = "" ] && chk ok "baseline is empty" || chk bad "baseline holds accepted violations"

# scratch tree: real copy (the graph skips symlinks), lib linked
mk() { rm -rf "$T/$1"; mkdir -p "$T/$1/kernel"; cp -a kernel/user "$T/$1/kernel/user"; ln -s "$ROOT/lib" "$T/$1/lib"; }
plant() { # name file import-line
    mk "$1"
    printf '\n%s\n' "$3" >> "$T/$1/kernel/user/$2"
    o=$(python3 -I tools/arch/layers.py --root "$T/$1" --strict 2>&1); r=$?
    if [ $r -ne 0 ] && echo "$o" | grep -q -- "  ${2%.fi} -> " ; then chk ok "counter-proof $1: planted '$3' in $2 -> red"
    else chk bad "counter-proof $1: planted violation NOT detected (rc=$r)"; fi
}
mk clean
python3 -I tools/arch/layers.py --root "$T/clean" --strict >/dev/null 2>&1 && chk ok "counter-proof control: unplanted copy is green" || chk bad "control copy is red"
plant base_toolkit msg.fi   "import wlib"
plant svc_toolkit  dhcp.fi  "import fuiscene"
plant app_shell    calc.fi  "import taskbar"
plant prog_import  ls.fi    "import cat"

echo "ARCH: $ok passed, $bad failed"
[ $bad -eq 0 ]
