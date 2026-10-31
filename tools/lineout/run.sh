#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
pass=0
fail=0
ok() { pass=$((pass + 1)); echo "OK   $1"; }
bad() { fail=$((fail + 1)); echo "FAIL $1"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

if python3 -I tools/lineout/lint.py . > "$work/real.log"; then
    ok "tree has no piecewise serial writes in GUI/WM programs ($(tail -1 "$work/real.log"))"
else
    bad "tree has piecewise serial writes"
    head -20 "$work/real.log"
fi

mkdir -p "$work/mut/kernel/user" "$work/mut/tools/lineout"
cp kernel/user/*.fi "$work/mut/kernel/user/"
cp tools/lineout/extra.txt "$work/mut/tools/lineout/"

cp "$work/mut/kernel/user/settings.fi" "$work/settings.orig"
printf 'fn lineout_probe() {\n    ulib.say("x")\n    ulib.nl()\n}\n' >> "$work/mut/kernel/user/settings.fi"
if python3 -I tools/lineout/lint.py "$work/mut" > /dev/null; then
    bad "counter-proof: injected ulib.say in settings.fi was not caught"
else
    ok "counter-proof: injected ulib.say in settings.fi is caught"
fi
cp "$work/settings.orig" "$work/mut/kernel/user/settings.fi"

printf 'fn lineout_probe() {\n    ulib.sayu(5)\n}\n' >> "$work/mut/kernel/user/wmd.fi"
if python3 -I tools/lineout/lint.py "$work/mut" > /dev/null; then
    bad "counter-proof: injected ulib.sayu in wmd.fi was not caught"
else
    ok "counter-proof: injected ulib.sayu in wmd.fi is caught"
fi
cp kernel/user/wmd.fi "$work/mut/kernel/user/wmd.fi"

printf 'fn lineout_probe() {\n    ulib.say("x")\n}\n' >> "$work/mut/kernel/user/wmplug.fi"
if python3 -I tools/lineout/lint.py "$work/mut" > /dev/null; then
    bad "counter-proof: injected ulib.say in wmplug.fi (extra list) was not caught"
else
    ok "counter-proof: injected ulib.say in wmplug.fi (extra list) is caught"
fi
cp kernel/user/wmplug.fi "$work/mut/kernel/user/wmplug.fi"

sed -i 's/lineout\.end_line()//; s/\\n//g' "$work/mut/kernel/user/theme.fi"
if python3 -I tools/lineout/lint.py "$work/mut" > /dev/null; then
    bad "counter-proof: pieces without end_line in theme.fi were not caught"
else
    ok "counter-proof: pieces without end_line in theme.fi are caught"
fi

echo "lineout: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
