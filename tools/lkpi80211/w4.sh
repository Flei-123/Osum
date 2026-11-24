#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
. tools/lib/tmpdir.sh
D=$(mktemp -d); osum_tmp_guard "" "$D"
DRIVER=iwlwifi
RATCHET=compat/linuxkpi/units/$DRIVER.ratchet
cached="${LINUXKPI_CACHE:-/root/lkpi-src/dl612}/linux-6.12.101.tar.xz"
[ -z "${LINUXKPI_TARBALL:-}" ] && [ -f "$cached" ] && export LINUXKPI_TARBALL="$cached"
field() { python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); v=d[sys.argv[2]]; print(len(v) if isinstance(v,list) else v)' "$1" "$2"; }
limit() { sed -n "s/^$1=//p" "$RATCHET"; }

tree=$(bash compat/linuxkpi/fetch.sh $DRIVER "$D/f" 2>"$D/f.err")
[ -n "$tree" ] && [ -f "$tree/mvm/ops.c" ] && ok "fetch: $DRIVER tree from the pinned tarball, tree sha256 verified" || { bad "fetch tree"; cat "$D/f.err"; }
for h in hdr-ieee80211 hdr-nl80211 hdr-radiotap; do
    bash compat/linuxkpi/fetch.sh $h "$D/$h" >/dev/null 2>&1 && ok "fetch: $h verified" || bad "fetch: $h"
done
sed 's/f26e1c7731d9b0f625dc72eba2c47cad3923658f5e6f9a6964daa0e3626c60db/0000000000000000000000000000000000000000000000000000000000000000/' compat/linuxkpi/sources.tsv > "$D/bad.tsv"
LKPI_SOURCES="$D/bad.tsv" bash compat/linuxkpi/fetch.sh $DRIVER "$D/f-bad" >/dev/null 2>&1; [ $? -eq 3 ] && ok "counter-proof: wrong tree hash rejected (driver code is never patched)" || bad "counter-proof: wrong tree hash accepted"
[ "$(git ls-files 'drivers/*' '*/iwlwifi/*' | wc -l)" -eq 0 ] && ok "repo tracks no Linux driver file" || bad "repo tracks Linux driver files"

if bash compat/linuxkpi/treeprobe.sh $DRIVER "$D/r.json" > "$D/r.txt" 2>&1; then
    ok "probe: $(tail -1 "$D/r.txt")"
    u=$(field "$D/r.json" units_ok); h=$(field "$D/r.json" headers_missing)
    [ "$u" -ge "$(limit units_ok_min)" ] && ok "ratchet: units compiling $u >= $(limit units_ok_min)" || bad "ratchet: units compiling $u < $(limit units_ok_min)"
    [ "$h" -le "$(limit headers_missing_max)" ] && ok "ratchet: headers missing $h <= $(limit headers_missing_max)" || bad "ratchet: headers missing $h > $(limit headers_missing_max)"
    if [ "$(field "$D/r.json" complete)" = True ]; then
        n=$(field "$D/r.json" undefined)
        [ "$n" -eq 0 ] && ok "closure: 0 undefined symbols" || bad "closure: $n undefined symbols"
    fi
else
    bad "probe run"; tail -5 "$D/r.txt"
fi
cp -r compat/linuxkpi/shim "$D/shim-minus"; rm "$D/shim-minus/include/linux/list.h"
if LKPI_SHIM="$D/shim-minus" bash compat/linuxkpi/treeprobe.sh $DRIVER "$D/m.json" > "$D/m.txt" 2>&1; then
    hm=$(field "$D/m.json" headers_missing)
    [ "$hm" -gt "$(limit headers_missing_max)" ] && ok "counter-proof: shim without linux/list.h trips the ratchet ($hm missing)" || bad "counter-proof: ratchet blind to a removed header ($hm)"
else
    bad "counter-proof probe run"
fi
echo "LKPI80211-W4: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
