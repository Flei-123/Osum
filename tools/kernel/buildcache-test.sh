#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/kernel/buildcache-test.sh -- proof for tools/kernel/buildcache.sh:
#   1. cold build (cache empty) = miss x2
#   2. warm build (same tree)   = hit x2, byte-identical image + ELF
#   3. uncached build (OSUM_BUILD_CACHE=off) is byte-identical to the cached ones
#   4. counter-proof: a changed source line gives a miss AND a different image
#   5. paranoid verify mode (OSUM_BUILD_CACHE_VERIFY=1) accepts the hit
# Prints timings (wall seconds per build).  Heavy: 3-4 kernel builds -- run via heavy.
set -uo pipefail
cd "$(dirname "$0")/../.."
T=$(mktemp -d); trap 'git checkout -q -- kernel/klog.fi 2>/dev/null; rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
export OSUM_BUILD_CACHE="$T/cache"
now() { date +%s.%N; }
build() { # name [env...]  -> $T/name.mb, $T/name.log, $T/name.s
    local n=$1; shift; local a b; a=$(now)
    env "$@" bash tools/build-kernel.sh "$T/$n.mb" > "$T/$n.log" 2>&1; local rc=$?
    b=$(now); awk -v a="$a" -v b="$b" 'BEGIN{printf "%.1f", b-a}' > "$T/$n.s"; return $rc
}
secs() { cat "$T/$1.s"; }
hits() { grep -c "buildcache: hit" "$T/$1.log"; }
miss() { grep -c "buildcache: miss" "$T/$1.log"; }

echo "== 1. cold =="
build cold X=1 && ok "cold build ok ($(secs cold) s)" || bad "cold build failed: $(tail -3 "$T/cold.log")"
[[ $(miss cold) -eq 2 && $(hits cold) -eq 0 ]] && ok "cold: 2 misses, 0 hits" || bad "cold: miss=$(miss cold) hit=$(hits cold)"
echo "== 2. warm =="
build warm X=1 && ok "warm build ok ($(secs warm) s)" || bad "warm build failed"
[[ $(hits warm) -eq 2 && $(miss warm) -eq 0 ]] && ok "warm: 2 hits, 0 misses" || bad "warm: miss=$(miss warm) hit=$(hits warm)"
cmp -s "$T/cold.mb" "$T/warm.mb" && ok "warm image byte-identical to cold" || bad "warm image differs from cold"
cmp -s "$T/cold.mb.elf" "$T/warm.mb.elf" && ok "warm ELF byte-identical to cold" || bad "warm ELF differs from cold"
echo "== 3. uncached =="
build plain OSUM_BUILD_CACHE=off && ok "uncached build ok ($(secs plain) s)" || bad "uncached build failed"
[[ $(hits plain)$(miss plain) == 00 ]] && ok "uncached: no cache lines" || bad "uncached build touched the cache"
cmp -s "$T/cold.mb" "$T/plain.mb" && ok "uncached image byte-identical to cached" || bad "uncached image differs from cached"
cmp -s "$T/cold.mb.elf" "$T/plain.mb.elf" && ok "uncached ELF byte-identical to cached" || bad "uncached ELF differs from cached"
echo "== 4. counter-proof: source change =="
echo "// buildcache-test marker" >> kernel/klog.fi
build chg X=1 && ok "changed-source build ok ($(secs chg) s)" || bad "changed-source build failed"
[[ $(miss chg) -eq 2 ]] && ok "changed source: 2 misses (key follows the content)" || bad "changed source: miss=$(miss chg) hit=$(hits chg)"
cmp -s "$T/cold.mb" "$T/chg.mb" && bad "changed source gave the SAME image (cache or build blind)" || ok "changed source gives a different image"
git checkout -q -- kernel/klog.fi
echo "== 5. verify mode =="
build ver OSUM_BUILD_CACHE_VERIFY=1 && ok "verify build ok ($(secs ver) s)" || bad "verify build failed: $(tail -2 "$T/ver.log")"
[[ $(hits ver) -eq 2 ]] && ok "verify: hits accepted" || bad "verify: hit=$(hits ver)"
echo
echo "TIMES: cold=$(secs cold)s warm=$(secs warm)s uncached=$(secs plain)s"
echo "BUILDCACHE: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
