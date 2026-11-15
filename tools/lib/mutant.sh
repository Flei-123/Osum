#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

mutant_tree() {
    local tree=$1 file=$2 function=$3 statement=$4
    git worktree add --detach "$tree" HEAD > /dev/null 2>&1 || return 1
    python3 -I "$(dirname "${BASH_SOURCE[0]}")/mutant.py" "$tree" "$file" "$function" "$statement"
}
