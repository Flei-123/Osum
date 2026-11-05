#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

osum_descendants() {
    local parent=$1 child
    for child in $(pgrep -P "$parent" 2>/dev/null); do
        osum_descendants "$child"
        printf '%s\n' "$child"
    done
}

osum_kill_children() {
    local signal=${2:-TERM} pid
    for pid in $(osum_descendants "$1"); do
        kill "-$signal" "$pid" 2>/dev/null
    done
    return 0
}

osum_kill_tree() {
    local signal=${2:-TERM}
    osum_kill_children "$1" "$signal"
    kill "-$signal" "$1" 2>/dev/null
    return 0
}
