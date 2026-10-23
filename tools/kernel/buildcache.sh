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
#      OSUM_BUILD_CACHE=<dir>    cache directory (default /root/.osum-bcache, shared by ALL worker dirs)
#      OSUM_BUILD_CACHE_MAX_MB   prune oldest entries above this size (default 4096)
#      OSUM_BUILD_CACHE_VERIFY=1 on a hit ALSO compile and compare (paranoid mode, costs the time)
# Log lines (stderr): "buildcache: hit|miss <root> key=<12 hex> (<n> ms)".

BC_FORMAT=1

bc_dir() {
    case "${OSUM_BUILD_CACHE:-}" in
        off) return 1 ;;
        "") printf '%s' "${OSUM_BCACHE_DIR:-/root/.osum-bcache}" ;;
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
    local dir=$1 max=${OSUM_BUILD_CACHE_MAX_MB:-4096} kb f
    kb=$(du -sk "$dir" 2>/dev/null | cut -f1)
    [[ ${kb:-0} -le $((max * 1024)) ]] && return 0
    ls -tr "$dir"/*.o "$dir"/p/*.o 2>/dev/null | while read -r f; do
        rm -f "$f"
        kb=$(du -sk "$dir" | cut -f1)
        [[ $kb -le $((max * 1024 * 8 / 10)) ]] && break
    done
    find "$dir/p" -name '*.deps' -mtime +14 -delete 2>/dev/null
    find "$dir" -maxdepth 2 -name '.put.*' -mmin +60 -delete 2>/dev/null
}

# ---------------------------------------------------------------------------------------------
# PROGRAM OBJECT CACHE (W-BUILD, 23.10.2026): one firnc -c step per program, keyed by what the
# compile really READ.  Two levels, like ccache's direct mode:
#   key1  = sha256(format, firnc, .gebaut, flags, source path, FIRNLIB, FIRN_* env, listing of all
#           .fi names under lib/ kernel/ vendor/firn/lib  -- so a NEW file that shadows an import
#           changes the key)
#   deps  = p/<key1>.<listhash>.deps : the source files firnc read (--deps-out), ROOT-relative
#   obj   = p/<key1>.<listhash>.<contenthash>.o   (contenthash = sha256 of the content of all deps)
# A lookup tries every manifest of key1, hashes the listed files (~ms) and hits if the object exists.
# Unrelated edits elsewhere in kernel/ or lib/ therefore do NOT invalidate an unaffected program.
# Objects are bit-identical across worker dirs (checked: no absolute path in the object).
# Concurrency: every write is mktemp in the same dir + mv -f (atomic); a failed cp falls back to compile.
# Env: OSUM_BUILD_CACHE=off disables; OSUM_BUILD_CACHE_VERIFY=1 compiles on a hit too and compares.
# Log: "buildcache: phit|pmiss <src> key=<12 hex> (<ms> ms)" on stderr.

bc_list_hash() { # once per process: names of all .fi files (no contents)
    [[ -n ${BC_LIST_HASH:-} ]] && return 0
    BC_LIST_HASH=$( (cd "$ROOT" && find lib kernel vendor/firn/lib -type f -name '*.fi' 2>/dev/null | LC_ALL=C sort | sha256sum | cut -c1-64) )
    export BC_LIST_HASH
}

bc_rel() { local rp r; rp=$(cd "$ROOT" && pwd -P); r=${1//$ROOT/@}; printf '%s' "${r//$rp/@}"; }
bc_norm() { local rp; rp=$(cd "$ROOT" && pwd -P); sed -e "s|^$rp/||" -e "s|^$ROOT/||"; }

# bc_prepare FIRNC  (call once in the parent before forking jobs: list hash + compiler hash)
bc_prepare() { bc_list_hash; BC_FIRNC_PATH=$1; BC_FIRNC_SUM=$(sha256sum "$1" | cut -c1-64); }

# bc_deps_hash DEPSFILE -> content hash of the files named in it (cwd = ROOT); non-zero when a file is gone
bc_deps_hash() {
    local f
    { while IFS= read -r f; do
          [[ -f $f ]] || return 1
          printf '%s %s\n' "$f" "$(sha256sum < "$f" | cut -c1-64)"
      done < "$1"; } | sha256sum | cut -c1-64
}

# bc_deps_finish FILE: --deps-out list -> ROOT-relative, only real files (drops the pseudo path lib/gc/gc.fi), plus the files
# pulled in by __include_str("...") (firnc does NOT list them; path is relative to the including file; settings.d/*).
bc_deps_finish() {
    local f inc q
    bc_norm < "$1" > "$1.n"
    {
        while IFS= read -r f; do
            [[ -f $f ]] || continue
            printf '%s\n' "$f"
            [[ $f == *.fi ]] || continue
            grep -ao '__include_str("[^"]*")' "$f" 2>/dev/null | sed 's/^__include_str("//; s/")$//' | while IFS= read -r inc; do
                q=$(realpath -m "$(dirname "$f")/$inc") && printf '%s\n' "$q" | bc_norm
            done
        done < "$1.n"
    } | LC_ALL=C sort -u > "$1"
    rm -f "$1.n"
}

# bc_cc OUT SRC FIRNC [FLAGS...]    (cwd = ROOT, FIRNLIB as the caller set it)
#   runs: FIRNC FLAGS -c SRC -o OUT, cached.  Compiler output goes to stderr/stdout of the caller.
bc_cc() {
    local out=$1 src=$2 firnc=$3 dir key1 t0 t1 m dh obj dtmp tmpo lh ch
    shift 3
    t0=$(date +%s%N)
    if ! dir=$(bc_dir) || [[ ${OSUM_PROG_CACHE:-1} = 0 ]]; then
        "$firnc" "$@" -c "$src" -o "$out"; return
    fi
    bc_list_hash
    [[ -n ${BC_FIRNC_SUM:-} && ${BC_FIRNC_PATH:-} == "$firnc" ]] || { BC_FIRNC_SUM=$(sha256sum "$firnc" | cut -c1-64); BC_FIRNC_PATH=$firnc; }
    key1=$( {
        echo "pformat=1 $BC_FIRNC_SUM $BC_LIST_HASH $src $(bc_rel "${FIRNLIB:-}")"
        cat "${BC_GEBAUT:-$ROOT/vendor/firn/.gebaut}" 2>/dev/null
        printf '%s\n' "$@"
        env | grep '^FIRN_' | LC_ALL=C sort
    } | sha256sum | cut -c1-64 )
    mkdir -p "$dir/p" 2>/dev/null
    for m in $(ls -t "$dir/p/$key1".*.deps 2>/dev/null | head -8); do
        lh=${m##*/}; lh=${lh#"$key1".}; lh=${lh%.deps}
        ch=$(bc_deps_hash "$m") || continue
        obj="$dir/p/$key1.$lh.$ch.o"
        if [[ -f $obj ]] && cp -f "$obj" "$out" 2>/dev/null; then
            touch "$obj" "$m" 2>/dev/null
            if [[ ${OSUM_BUILD_CACHE_VERIFY:-0} == 1 ]]; then
                "$firnc" "$@" -c "$src" -o "$out.verify" || return 1
                cmp -s "$out" "$out.verify" || { echo "buildcache: VERIFY FAILED for $src" >&2; return 1; }
                rm -f "$out.verify"
            fi
            t1=$(date +%s%N)
            echo "buildcache: phit  $src key=${key1:0:12} ($(( (t1 - t0) / 1000000 )) ms)" >&2
            [[ -n ${BC_STATS:-} ]] && echo "phit $src $(( (t1 - t0) / 1000000 ))" >> "$BC_STATS"
            return 0
        fi
    done
    dtmp=$(mktemp "$dir/.put.XXXXXX") || { "$firnc" "$@" -c "$src" -o "$out"; return; }
    "$firnc" "$@" --deps-out="$dtmp" -c "$src" -o "$out" || { rm -f "$dtmp"; return 1; }
    bc_deps_finish "$dtmp"
    if ch=$(bc_deps_hash "$dtmp") && [[ -s $dtmp ]]; then
        lh=$(sha256sum < "$dtmp" | cut -c1-64)
        tmpo=$(mktemp "$dir/.put.XXXXXX") && cp -f "$out" "$tmpo" \
            && mv -f "$tmpo" "$dir/p/$key1.$lh.$ch.o" && mv -f "$dtmp" "$dir/p/$key1.$lh.deps"
    fi
    rm -f "$dtmp" "$dtmp.n"
    t1=$(date +%s%N)
    echo "buildcache: pmiss $src key=${key1:0:12} ($(( (t1 - t0) / 1000000 )) ms)" >&2
    [[ -n ${BC_STATS:-} ]] && echo "pmiss $src $(( (t1 - t0) / 1000000 ))" >> "$BC_STATS"
    return 0
}

# bc_jobs  -> number of parallel compile jobs (OSUM_BUILD_JOBS, default 6; ONE heavy slot, never nested heavy)
bc_jobs() { local j=${OSUM_BUILD_JOBS:-6}; [[ $j =~ ^[0-9]+$ && $j -ge 1 ]] || j=1; echo "$j"; }
