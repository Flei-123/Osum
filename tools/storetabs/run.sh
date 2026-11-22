#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/firnenv.sh
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
rc=0

build_and_run() {
    local lib=$1 tag=$2
    FIRNLIB="$lib" "$FIRNC" --profile=app tools/storetabs/host.fi -o "$T/host-$tag" > "$T/build-$tag.txt" 2>&1 \
        || { echo "FAIL  build $tag"; grep -v '^warning' "$T/build-$tag.txt" | head -20; return 2; }
    "$T/host-$tag" > "$T/out-$tag.txt"
    local prc=$?
    grep '^FAIL' "$T/out-$tag.txt" | head -20
    echo "$prc" > "$T/rc-$tag"
    return 0
}

FIRNLIB="$PWD/lib" "$FIRNC" --profile=kernel -c tools/storetabs/kcheck.fi -o "$T/kcheck.o" > "$T/kcheck.build" 2>&1 \
    && echo "OK    store.registry compiles in profile kernel" \
    || { echo "FAIL  store.registry does not compile in profile kernel"; grep -v '^warning' "$T/kcheck.build" | head -20; rc=1; }

build_and_run "$PWD/lib" real || exit 1
checks=$(sed -n 's/^checks=\([0-9]*\) fails=.*/\1/p' "$T/out-real.txt")
fails=$(sed -n 's/^checks=.* fails=\([0-9]*\)/\1/p' "$T/out-real.txt")
[ "$(cat "$T/rc-real")" = 0 ] || rc=1

mutate() {
    local name=$1 expr=$2
    local lib="$T/lib-$name"
    mkdir -p "$lib"
    for e in lib/*; do [ "$(basename "$e")" = store ] || ln -s "$PWD/$e" "$lib/$(basename "$e")"; done
    mkdir -p "$lib/store"
    sed "$expr" lib/store/registry.fi > "$lib/store/registry.fi"
    cmp -s lib/store/registry.fi "$lib/store/registry.fi" && { echo "FAIL  mutant $name changed nothing"; rc=1; return; }
    build_and_run "$lib" "$name" || { rc=1; return; }
    local mf
    mf=$(sed -n 's/^checks=.* fails=\([0-9]*\)/\1/p' "$T/out-$name.txt")
    if [ "${mf:-0}" -gt 0 ]; then echo "OK    old logic $name is caught ($mf red)"; else echo "FAIL  old logic $name stays green"; rc=1; fi
}
mutate showall 's/if view_tab != item_tab {/if false {/'
mutate nosearch 's/    if searching {/    if false {/'
mutate noskip 's/return b(have, 0) != 0 \&\& ver_at_least(have, min)/return false/'
mutate nover 's/return b(have, 0) != 0 \&\& ver_at_least(have, min)/return b(have, 0) != 0/'
mutate hideinst 's/if view_tab == TAB_APPS \&\& installed \&\& !show_installed {/if false {/'
mutate order 's/    p_state\[i as usize\] = ST_DONE/    p_state[i as usize] = ST_DONE\n    if i != 0 { p_n = p_n }/;s/visit(j, depth + 1)/p_n = p_n/'

echo "STORETABS: ${checks:-0} passed, ${fails:-1} failed"
exit $rc
