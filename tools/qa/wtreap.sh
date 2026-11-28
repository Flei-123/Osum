#!/usr/bin/env bash
set -uo pipefail
REPO=${OSUM_REPO:-/root/jarvis/projects/u_DiS4in7esMF1/osum}
ROOT=${WT_ROOT:-/root/jarvis/data/staff_wt/orientos}
MAX_AGE_DAYS=${WT_MAX_AGE_DAYS:-7}
MIN_IDLE_DAYS=${WT_MIN_IDLE_DAYS:-1}
APPLY=0; STALE=0
while [[ $# -gt 0 ]]; do
    case $1 in
        --apply) APPLY=1 ;;
        --include-stale) STALE=1 ;;
        -h|--help) echo "usage: wtreap.sh [--apply] [--include-stale]   dry run by default; --apply removes merged worktrees and merged branches; --include-stale also removes unmerged ones idle > ${MAX_AGE_DAYS} days with no worker"; exit 0 ;;
        *) echo "unknown option $1" >&2; exit 2 ;;
    esac
    shift
done
git -C "$REPO" fetch -q --prune origin 2> /dev/null
BASE=refs/remotes/origin/main
git -C "$REPO" rev-parse -q --verify $BASE > /dev/null || BASE=refs/heads/main
USED=$(for p in /proc/[0-9]*; do readlink "$p/cwd"; tr '\0' '\n' < "$p/cmdline" 2> /dev/null | grep '^/'; done 2> /dev/null | sort -u)
in_use() { grep -q -F -e "$1" <<< "$USED"; }
idle_days() { echo $(( ( $(date +%s) - $(git -C "$1" log -1 --format=%ct 2> /dev/null || echo 0) ) / 86400 )); }
newest_file_days() { local m; m=$(find "$1" -xdev -path '*/.git' -prune -o -type f -printf '%T@\n' 2> /dev/null | sort -rn | head -1); echo $(( ( $(date +%s) - ${m%.*} ) / 86400 )); }
removed=0; kept=0
printf '%-9s %-8s %-6s %-5s %s\n' VERDICT MERGED IDLE DIRTY WORKTREE
declare -A REGISTERED=()
while read -r wt head branch; do
    [[ $wt == "$ROOT"/* ]] || continue
    REGISTERED[$wt]=1
    br=${branch#refs/heads/}
    merged=no; git -C "$REPO" merge-base --is-ancestor "$head" $BASE 2> /dev/null && merged=yes
    dirty=$(git -C "$wt" status --porcelain 2> /dev/null | grep -c .)
    idle=$(newest_file_days "$wt")
    verdict=keep
    if in_use "$wt"; then verdict=keep-busy
    elif [[ $merged == yes && $dirty -eq 0 && $idle -ge $MIN_IDLE_DAYS ]]; then verdict=remove
    elif [[ $merged == no && $STALE -eq 1 && $idle -gt $MAX_AGE_DAYS && $dirty -eq 0 ]]; then verdict=remove-stale
    elif [[ $merged == no && $idle -gt $MAX_AGE_DAYS ]]; then verdict=stale
    fi
    printf '%-9s %-8s %-6s %-5s %s (%s)\n' "$verdict" "$merged" "${idle}d" "$dirty" "$wt" "$br"
    if [[ $verdict == remove || $verdict == remove-stale ]]; then
        if [[ $APPLY -eq 1 ]]; then
            git -C "$REPO" worktree remove --force "$wt" && removed=$((removed + 1))
            if [[ $verdict == remove ]]; then git -C "$REPO" branch -d "$br" > /dev/null 2>&1 || git -C "$REPO" branch -D "$br" > /dev/null 2>&1; fi
        else removed=$((removed + 1)); fi
    else kept=$((kept + 1)); fi
done < <(git -C "$REPO" worktree list --porcelain | awk '/^worktree /{w=$2} /^HEAD /{h=$2} /^branch /{b=$2} /^detached/{b="detached"} /^$/{print w, h, b; w=h=b=""}')
for dir in "$ROOT"/*/; do
    dir=${dir%/}
    [[ -d $dir && -z ${REGISTERED[$dir]:-} ]] || continue
    gitdir=$(sed -n 's/^gitdir: //p' "$dir/.git" 2> /dev/null)
    [[ -n $gitdir ]] || continue
    idle=$(newest_file_days "$dir")
    verdict=orphan-keep
    if [[ $gitdir == "$REPO"/.git/worktrees/* && ! -d $gitdir ]] && ! in_use "$dir" && [[ $idle -gt $MAX_AGE_DAYS ]]; then verdict=orphan-remove; fi
    [[ $gitdir == "$REPO"/.git/worktrees/* ]] || verdict=foreign-keep
    printf '%-9s %-8s %-6s %-5s %s\n' "$verdict" - "${idle}d" - "$dir"
    if [[ $verdict == orphan-remove && $APPLY -eq 1 ]]; then rm -rf "$dir"; fi
done
git -C "$REPO" worktree prune
echo "branches merged into ${BASE#refs/remotes/}, not checked out:"
CHECKED=$(git -C "$REPO" worktree list --porcelain | sed -n 's#^branch refs/heads/##p')
while read -r b; do
    [[ $b == staff/* ]] || continue
    grep -qx -- "$b" <<< "$CHECKED" && continue
    echo "  branch $b"
    [[ $APPLY -eq 1 ]] && git -C "$REPO" branch -d "$b" > /dev/null 2>&1
done < <(git -C "$REPO" branch --merged $BASE --format='%(refname:short)')
echo "worktrees: $removed removable${APPLY:+ (applied=$APPLY)}, $kept kept"
