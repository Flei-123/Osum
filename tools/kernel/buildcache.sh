#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/kernel/buildcache.sh -- content-addressed cache for the two Firn compile steps of
# tools/build-kernel.sh (k.o from kmain.fi, uprog.o from uprog.fi).  ACCEL phase 1, B-01/B-02.
#
# WHY WHOLE-TREE KEYS: firnc compiles the whole kernel as ONE unit per root (kmain.fi / uprog.fi);
# there is no per-module object to cache.  So the key is the hash of EVERYTHING the compiler can
# read for that root, and a hit skips the compile completely (typically 40 s of the 44-58 s build):
#
#   key = sha256( firnc binary, vendor/firn/.gebaut, the prepared kernel copy (after brand/version
#                 substitution and stub swaps), lib/ (FIRNLIB), vendor/firn/lib, stage, root path,
#                 FORMAT )
#
# The kernel copy contains the git short hash (kernel/version.fi), so across COMMITS the key changes
# (the version line is part of the image) -- the cache pays off for every further build of the SAME
# commit/tree: the dozens of gates per branch, retries, and parallel workers sharing one cache dir.
#
# CORRECTNESS: the compile runs with cwd = the kernel copy and a RELATIVE root path, so no random
# mktemp name ends up in the object (before: 13312 occurrences of /tmp/tmp.XXXXXXXXXX in the image,
# two uncached builds differed in 133120 bytes).  `tools/kernel/buildcache-test.sh` proves
# cached == uncached == uncached again, byte for byte.
#
# Env: OSUM_BUILD_CACHE=off      disable (always compile)
#      OSUM_BUILD_CACHE=<dir>    cache directory (default ~/.cache/osum-build)
#      OSUM_BUILD_CACHE_MAX_MB   prune oldest entries above this size (default 1024)
#      OSUM_BUILD_CACHE_VERIFY=1 on a hit ALSO compile and compare (paranoid mode, costs the time)
# Log lines (stderr): "buildcache: hit|miss <root> key=<12 hex> (<n> ms)".

BC_FORMAT=1

bc_dir() {
    case "${OSUM_BUILD_CACHE:-}" in
        off) return 1 ;;
        "") printf '%s' "${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/osum-build" ;;
        *) printf '%s' "$OSUM_BUILD_CACHE" ;;
    esac
}

# bc_tree_hash DIR [DIR...]   (paths relative to cwd; names + contents; deterministic)
bc_tree_hash() {
    find "$@" -type f -print0 2>/dev/null | LC_ALL=C sort -z | xargs -0 sha256sum 2>/dev/null | sha256sum | cut -c1-64
}

# bc_common_key FIRNC ROOT_DIR(kernel copy parent) STUFE
bc_common_key() {
    local firnc=$1 work=$2 stufe=$3
    {
        echo "format=$BC_FORMAT stufe=$stufe"
        sha256sum "$firnc" | cut -d' ' -f1
        cat "$ROOT/vendor/firn/.gebaut" 2>/dev/null
        (cd "$work" && bc_tree_hash kernel)
        (cd "$ROOT" && bc_tree_hash lib vendor/firn/lib)
    } | sha256sum | cut -c1-64
}

# bc_compile FIRNC WORK COMMONKEY ROOT_REL OUT
#   compiles WORK/ROOT_REL into OUT with cwd=WORK (relative path), or copies the cached object.
bc_compile() {
    local firnc=$1 work=$2 ck=$3 rel=$4 out=$5 dir key t0 t1 tmpo
    t0=$(date +%s%N)
    if dir=$(bc_dir) && [[ -n $ck ]]; then
        key=$(printf '%s %s' "$ck" "$rel" | sha256sum | cut -c1-64)
        if [[ -f $dir/$key.o ]]; then
            cp -f "$dir/$key.o" "$out" && touch "$dir/$key.o"
            if [[ ${OSUM_BUILD_CACHE_VERIFY:-0} == 1 ]]; then
                (cd "$work" && "$firnc" -o "$out.verify" "$rel") || return 1
                cmp -s "$out" "$out.verify" || { echo "buildcache: VERIFY FAILED for $rel (cached object differs from fresh compile)" >&2; return 1; }
                rm -f "$out.verify"
            fi
            t1=$(date +%s%N)
            echo "buildcache: hit  $rel key=${key:0:12} ($(( (t1 - t0) / 1000000 )) ms)" >&2
            return 0
        fi
        (cd "$work" && "$firnc" -o "$out" "$rel") || return 1
        mkdir -p "$dir" && tmpo=$(mktemp "$dir/.put.XXXXXX") && cp -f "$out" "$tmpo" && mv -f "$tmpo" "$dir/$key.o"
        t1=$(date +%s%N)
        echo "buildcache: miss $rel key=${key:0:12} ($(( (t1 - t0) / 1000000 )) ms)" >&2
        bc_prune "$dir"
        return 0
    fi
    (cd "$work" && "$firnc" -o "$out" "$rel")
}

bc_prune() { # dir: drop oldest objects above the size limit
    local dir=$1 max=${OSUM_BUILD_CACHE_MAX_MB:-1024} kb f
    kb=$(du -sk "$dir" 2>/dev/null | cut -f1)
    [[ ${kb:-0} -le $((max * 1024)) ]] && return 0
    ls -tr "$dir"/*.o 2>/dev/null | while read -r f; do
        rm -f "$f"
        kb=$(du -sk "$dir" | cut -f1)
        [[ $kb -le $((max * 1024 * 8 / 10)) ]] && break
    done
}
