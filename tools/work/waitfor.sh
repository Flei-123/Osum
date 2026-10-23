#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/work/waitfor.sh -- wait for something, return AS SOON AS it happens (no blind `sleep 560; tail`).
#
#   waitfor.sh [-t SECONDS] [-i SECONDS] [-n LINES] pid  PID...         wait until all PIDs are gone
#   waitfor.sh [-t SECONDS] [-i SECONDS] [-n LINES] log  FILE REGEX     wait until FILE has a line matching REGEX (ERE)
#   waitfor.sh [-t SECONDS] [-i SECONDS] [-n LINES] file PATH...        wait until all paths exist (non-empty for files)
#   waitfor.sh [-t SECONDS] [-i SECONDS] [-n LINES] gone PATH...        wait until none of the paths exists
#   waitfor.sh [-t SECONDS] [-i SECONDS] [-n LINES] heavy [PATTERN]     wait until no heavy slot runs a command matching PATTERN
#                                                                       (default: this checkout's cwd)
#
#   -t  timeout in seconds (default 540; run_shell/run_parallel abort at ~60/600 s, so stay below)
#   -i  poll interval (default 5)
#   -n  how many tail lines of the watched log to print (default 15; log mode: the match plus context)
#   Optional env WAITFOR_LOG=FILE: tail this file on every exit path (pid/file/heavy modes).
#
# Exit codes: 0 = done / marker found, 124 = timeout (poll again, nothing is lost), 2 = usage.
# Output: one line "waitfor: <mode> <what> -> done|timeout after <n> s" and the tail of the log.
#
# Typical worker use (long gate in the background):
#   (setsid nohup /root/jarvis/bin/heavy bash tools/desktop/run.sh > /root/x/log 2>&1 < /dev/null &)
#   bash tools/work/waitfor.sh log /root/x/log '^(OK|FAIL|rc=|== )'     # returns the moment the marker shows up
#   bash tools/work/waitfor.sh -t 500 heavy                               # or: until my heavy runs left the slots
# Always re-call it on exit 124 instead of `sleep N`.
set -u
T=540; I=5; N=15
while getopts "t:i:n:" o; do
    case $o in t) T=$OPTARG ;; i) I=$OPTARG ;; n) N=$OPTARG ;; *) exit 2 ;; esac
done
shift $((OPTIND - 1))
mode=${1:-}; shift || true
[[ $T =~ ^[0-9]+$ && $I =~ ^[0-9]+$ && $N =~ ^[0-9]+$ && $I -ge 1 ]] || { echo "waitfor: -t/-i/-n need numbers" >&2; exit 2; }
start=$SECONDS
what="$*"

finish() { # rc msg
    local rc=$1 msg=$2
    echo "waitfor: $mode $what -> $msg after $((SECONDS - start)) s"
    if [[ -n ${WAITFOR_LOG:-} && -f ${WAITFOR_LOG:-/nonexistent} ]]; then tail -n "$N" "$WAITFOR_LOG"; fi
    exit "$rc"
}

check() { return 1; }
case $mode in
    pid)
        [[ $# -ge 1 ]] || { echo "usage: waitfor.sh pid PID..." >&2; exit 2; }
        check() { local p; for p in "$@"; do [[ -d /proc/$p ]] && return 1; done; return 0; }
        ;;
    log)
        [[ $# -ge 2 ]] || { echo "usage: waitfor.sh log FILE REGEX" >&2; exit 2; }
        LOGF=$1; RE=$2; what="$LOGF /$RE/"
        check() { [[ -f $LOGF ]] && grep -Eq -- "$RE" "$LOGF"; }
        finish_log() {
            local rc=$1 msg=$2
            echo "waitfor: log $what -> $msg after $((SECONDS - start)) s"
            [[ -f $LOGF ]] && { grep -En -- "$RE" "$LOGF" | head -3; echo "--- tail $LOGF"; tail -n "$N" "$LOGF"; }
            exit "$rc"
        }
        set -- ;;
    file)
        [[ $# -ge 1 ]] || { echo "usage: waitfor.sh file PATH..." >&2; exit 2; }
        check() { local f; for f in "$@"; do [[ -e $f ]] || return 1; [[ -f $f && ! -s $f ]] && return 1; done; return 0; }
        ;;
    gone)
        [[ $# -ge 1 ]] || { echo "usage: waitfor.sh gone PATH..." >&2; exit 2; }
        check() { local f; for f in "$@"; do [[ -e $f ]] && return 1; done; return 0; }
        ;;
    heavy)
        PAT=${1:-$(pwd)}; what="$PAT"
        check() { ! /root/jarvis/bin/heavy --status 2>/dev/null | grep '^slot[0-9]*: BUSY' | grep -Fq -- "$PAT"; }
        set -- ;;
    *) sed -n '2,29p' "$0"; exit 2 ;;
esac

while :; do
    if check "$@"; then
        [[ $mode == log ]] && finish_log 0 done
        finish 0 done
    fi
    if (( SECONDS - start >= T )); then
        [[ $mode == log ]] && finish_log 124 timeout
        finish 124 timeout
    fi
    rem=$((T - (SECONDS - start))); (( rem < 1 )) && rem=1; sleep "$(( rem < I ? rem : I ))"
done
