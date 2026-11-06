#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
SUMMARY_PREFIX=${SUMMARY_PREFIX:-GATE}
SUMMARY_DONE=0
SUMMARY_BAD=0

summary_begin() {
    SUMMARY_PREFIX=$1
    SUMMARY_DONE=0
    SUMMARY_BAD=0
}

summary_guard() {
    [ "$SUMMARY_DONE" = 1 ] && return 0
    SUMMARY_BAD=1
    printf '\n%s: 0 passed, 1 failed (summary missing: the script ended before its last line)\n' "$SUMMARY_PREFIX"
}

summary_exit_status() {
    [ "$SUMMARY_BAD" = 0 ]
}

summary_note() {
    [ -z "${SUMMARY_SUPPRESS:-}" ] || return 0
    printf '%s: %s\n' "$SUMMARY_PREFIX" "$1"
    SUMMARY_DONE=1
}

summary_emit() {
    local pass=$1 fail=$2 floor=${3:-0}
    if [ $((pass + fail)) -lt "$floor" ]; then
        printf '  FAIL  only %d checks ran, at least %d expected (output or run cut short)\n' $((pass + fail)) "$floor"
        fail=$((fail + 1))
    fi
    if [ -z "${SUMMARY_SUPPRESS:-}" ]; then
        printf '\n%s: %d passed, %d failed\n' "$SUMMARY_PREFIX" "$pass" "$fail"
        SUMMARY_DONE=1
    fi
    [ "$fail" -eq 0 ]
}
