#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/nav/run.sh -- host gate of the navigation toolkit (docs/NAVIGATION-TOOLKIT.md). No VM, seconds.
#   1. golden cases (URI, loader errors + rollback, registry, stack, crumbs, search, dynamic routes)
#   2. the real Settings route table in en and de: keys exist, labels <= 38, every route found by its title and keyword,
#      no lint violation (controls per page <= limit, related targets exist)
#   3. mutations: every broken copy of the library must turn step 1 or 2 red
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || { echo "fetch-firnc.sh failed"; exit 1; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
ROUTES=kernel/user/settings.d/settings.routes

build() { FIRNLIB="$1" vendor/firn/bin/firnc --profile=app tools/nav/drive.fi -o "$2" > "$2.build" 2>&1; }

golden() { # binary -> number of failing checks
    local bin=$1 n=0 f
    for f in tools/nav/cases/*.txt; do
        "$bin" < "$f" > "$T/out.txt" 2>/dev/null
        cmp -s "$T/out.txt" "${f%.txt}.expect" || n=$((n+1))
    done
    for lc in en de; do
        python3 -I tools/nav/realtable.py $ROUTES locale/$lc/messages case > "$T/real-$lc.txt" 2>/dev/null
        "$bin" < "$T/real-$lc.txt" > "$T/real-$lc.out" 2>/dev/null
        if grep -q ' miss$' "$T/real-$lc.out" || ! grep -q '^lint 0$' "$T/real-$lc.out" || ! grep -q '^section 1 ok' "$T/real-$lc.out"; then n=$((n+1)); fi
    done
    echo "$n"
}

echo "== 1. build + golden =="
if build "$ROOT/lib" "$T/drive"; then ok "tools/nav/drive.fi builds against lib/nav"; else
    bad "drive.fi does not build"; grep -v '^warning' "$T/drive.build" | head; echo "NAV: $pass passed, $fail failed"; exit 1; fi
if [ "${1:-}" = "--update" ]; then
    for f in tools/nav/cases/*.txt; do "$T/drive" < "$f" > "${f%.txt}.expect"; done
    echo "golden files updated"; exit 0
fi
G=$(golden "$T/drive")
if [ "$G" = 0 ]; then ok "all $(ls tools/nav/cases/*.txt | wc -l) golden cases + real table (en, de) pass"; else bad "$G golden/real-table checks differ"; fi

echo "== 2. real route table =="
for lc in en de; do
    if python3 -I tools/nav/realtable.py $ROUTES locale/$lc/messages keys > "$T/keys.out" 2>&1; then ok "every route key exists in $lc, labels <= 38 ($(cat "$T/keys.out" | tail -1))"; else bad "catalogue $lc: $(head -3 "$T/keys.out" | tr '\n' ' ')"; fi
    n=$(grep -c '^find .* hit$' "$T/real-$lc.out"); m=$(grep -c '^find .* miss$' "$T/real-$lc.out")
    if [ "$m" = 0 ] && [ "$n" -gt 40 ]; then ok "search finds every route in $lc ($n finds, 0 misses)"; else bad "search $lc: $n hits, $m misses"; fi
done
sb=$(grep -c '^  settings://' <("$T/drive" <<< $'%% run\nsidebar settings' ) || true)
python3 -I - "$ROUTES" <<'P' && ok "sidebar has <= 12 entries, depth <= 4, every route has a controls line" || bad "route table shape"
import sys,re
n=0;side=0;ctrl=0;routes=0;last=None
for ln in open(sys.argv[1]):
    w=ln.split("#")[0].split()
    if not w: continue
    if w[0]=="route":
        routes+=1
        depth=len([s for s in w[1].split("://",1)[1].split("/") if s])
        if depth>4: sys.exit(1)
        if depth==1 and "advanced" not in w[5:] and "hidden" not in w[5:]: side+=1
    if w[0]=="controls": ctrl+=1
sys.exit(0 if side<=12 and ctrl==routes else 1)
P

echo "== 3. mutations =="
mut() { # file old new label
    local d="$T/m"; rm -rf "$d"; mkdir -p "$d/nav"; cp lib/nav/*.fi "$d/nav/"
    if ! python3 -I - "$d/nav/$1" "$2" "$3" <<'P'
import sys
p,a,b=sys.argv[1:4]
s=open(p).read()
if a not in s: sys.exit(1)
open(p,'w').write(s.replace(a,b,1))
P
    then bad "mutation pattern not found: $4"; return; fi
    if ! FIRNLIB="$d" vendor/firn/bin/firnc --profile=app tools/nav/drive.fi -o "$d/drive" > "$d/build" 2>&1; then bad "mutation does not build: $4"; return; fi
    local g; g=$(golden "$d/drive")
    if [ "$g" != 0 ]; then ok "mutation red ($g): $4"; else bad "mutation SURVIVED: $4"; fi
}
mut reg.fi 'if r_ctrl[(i) as usize] > lim {' 'if r_ctrl[(i) as usize] > lim + 1 {' "limit off by one"
mut reg.fi 'hit = route.is_prefix(ru, rl, p, n)' 'hit = route.same_path(ru, rl, p, n)' "dynamic route only exact"
mut reg.fi '&& f / F_HIDDEN % 2 == 0' '' "hidden routes in sidebar"
mut reg.fi 'if r_flags[(par) as usize] / F_DYNAMIC % 2 == 1 {' 'if false {' "child under dynamic route allowed"
mut route.fi 'if l == 0 && e > st {' 'if l == 99 && e > st {' "empty segment accepted"
mut route.fi 'if rd(b, ea) == 47 {' 'if rd(b, ea) != 0 {' "prefix without segment boundary"
mut stack.fi 'cnt[(h) as usize] = at + 1' 'cnt[(h) as usize] = cnt[(h) as usize] + 1' "forward tail kept on push"
mut stack.fi 'at = CAP - 1' 'at = CAP - 2' "full stack drops wrong end"
mut stack.fi 'if route.same_path(current(h), current_len(h), p, n) {' 'if false {' "same route pushed twice"
mut search.fi 'if all_title {
        return 0' 'if all_title {
        return 1' "title rank lost"
mut search.fi 'reg.flags(id) / reg.F_DYNAMIC % 2 == 0' 'reg.flags(id) / reg.F_DYNAMIC % 2 <= 1' "dynamic routes searched"
mut loader.fi 'if !dir_matches(1) {' 'if false {' "package may speak for another dir"
mut loader.fi '        reg.txn_rollback()
        return ERR' '        return ERR' "rejected file leaves routes behind"
mut crumbs.fi 'if used + sep + w > avail {' 'if used + sep + w >= avail {' "crumb fit off by one"
mut route.fi 'if !is_hex(rd(p, i + 1)) || !is_hex(rd(p, i + 2)) {
                    return false' 'if !is_hex(rd(p, i + 1)) && !is_hex(rd(p, i + 2)) {
                    return false' "half valid percent escape accepted"

echo "NAV: $pass passed, $fail failed"
[ "$fail" = 0 ]
