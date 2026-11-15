#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/firnenv.sh
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "OK    $1"; }
bad() { fail=$((fail+1)); echo "FAIL  $1"; }
host() { FIRNLIB="$1" "$FIRNC" --profile=app tools/lkpi80211/host.fi -o "$2" > "$2.build" 2>&1; }
if FIRNLIB="$PWD/lib" "$FIRNC" --profile=kernel -c tools/lkpi80211/kcheck.fi -o "$T/kcheck.o" > "$T/kcheck.build" 2>&1; then
    ok "wlan.macplan compiles in profile kernel"
else
    bad "wlan.macplan does not compile in profile kernel"; grep -v '^warning' "$T/kcheck.build" | head -10
fi
if host "$PWD/lib" "$T/host"; then
    "$T/host" > "$T/host.out"; rc=$?
    grep '^FAIL' "$T/host.out" | head -10
    [ "$rc" = 0 ] && ok "host sequences: $(grep '^checks=' "$T/host.out")" || bad "host sequences: $(grep '^checks=' "$T/host.out")"
else
    bad "host build"; grep -v '^warning' "$T/host.build" | head -10
fi
mutant() {
    local name=$1 from=$2 to=$3 lib="$T/m-$1"
    mkdir -p "$lib"; cp -rs "$PWD/lib/." "$lib/"
    rm "$lib/wlan/macplan.fi"
    python3 -I -c 'import sys; s=open(sys.argv[1]).read(); assert sys.argv[2] in s; open(sys.argv[4],"w").write(s.replace(sys.argv[2], sys.argv[3], 1))' \
        lib/wlan/macplan.fi "$from" "$to" "$lib/wlan/macplan.fi" || { bad "mutant $name: pattern missing"; return; }
    if host "$lib" "$T/host-$name" && ! "$T/host-$name" > "$T/host-$name.out" 2>&1; then
        ok "mutant $name rejected ($(grep -c '^FAIL' "$T/host-$name.out") checks red)"
    else
        bad "mutant $name not rejected"
    fi
}
mutant jump "        (*p).sta = (*p).sta - 1" "        (*p).sta = target"
mutant keepkeys "    drop_keys(p)" "    (*p).n = (*p).n"
mutant nochanctx "    emit(p, OP_ADD_CHANCTX, 0)" "    (*p).n = (*p).n"
mutant openauth "        if (*p).rsn && !(*p).ptk { return false }" "        (*p).n = (*p).n"
echo "LKPI80211: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
