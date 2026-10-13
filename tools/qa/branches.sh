#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/qa/branches.sh -- merge-debt report (ACCEL #5): REPORT ONLY, never deletes anything.
#
#   bash tools/qa/branches.sh [base]      base defaults to origin/main
#
# For every remote branch and every local branch (staff/*, worktrees) it prints
#   merged   tip is an ancestor of base            -> safe to delete (git branch -d / push --delete)
#   same     (only with BR_DEEP=1, slow) merge-tree against base: no net change -> content already in base
#   ahead    unique commits (ahead/behind counts)    -> keep, or needs an owner decision
# and, per worktree, whether it has uncommitted changes. Deleting is a human/worker decision:
# the report only prints the commands.
set -uo pipefail
cd "$(dirname "$0")/../.."
BASE=${1:-origin/main}
git rev-parse --verify -q "$BASE" >/dev/null || { echo "no such base: $BASE" >&2; exit 2; }
printf '%-8s %-44s %6s %6s  %s\n' state branch ahead behind last
git for-each-ref --format='%(refname:short)' refs/remotes/origin refs/heads | grep -v -e '^origin$' -e "^${BASE}$" -e '/HEAD$' |
while read -r b; do
    read -r ahead behind < <(git rev-list --left-right --count "$b...$BASE" 2>/dev/null) || continue
    if [ "$ahead" = 0 ]; then st=merged
    elif [ -n "${BR_DEEP:-}" ] && [ "$(git merge-tree --write-tree "$BASE" "$b" 2>/dev/null | head -1)" = "$(git rev-parse "$BASE^{tree}")" ]; then st=same
    else st=ahead; fi
    printf '%-8s %-44s %6s %6s  %s\n' "$st" "$b" "$ahead" "$behind" "$(git log -1 --format=%cs "$b")"
done | sort -k1,1 -k2,2
echo
echo "worktrees with uncommitted changes:"
git worktree list --porcelain | awk '/^worktree /{w=$2} /^branch /{print w, $2}' | while read -r w br; do
    n=$(git -C "$w" status --short 2>/dev/null | wc -l)
    [ "$n" -gt 0 ] && echo "  $w ($br): $n changed"
done
echo "(report only -- delete merged ones yourself: git push origin --delete <name> / git branch -d <name>)"
