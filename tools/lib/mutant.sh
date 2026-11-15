#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

MUTANT_PY="$(dirname "${BASH_SOURCE[0]}")/mutant.py"

mutant_tree() {
    local tree=$1 file=$2 function=$3 statement=$4
    git worktree add --detach "$tree" HEAD > /dev/null 2>&1 || return 1
    python3 -I "$MUTANT_PY" insert "$tree/$file" "$function" "$statement"
}

mutant_tree_move() {
    local tree=$1 file=$2 moved=$3 anchor=$4
    git worktree add --detach "$tree" HEAD > /dev/null 2>&1 || return 1
    python3 -I "$MUTANT_PY" move "$tree/$file" "$moved" "$anchor"
}
