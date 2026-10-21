#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/preview/watch.sh -- host loop for a fUi program: on every save of
# kernel/user/<prog>.fi compile it (7-11 s, no VM) and re-render the preview.
#
#   bash tools/preview/watch.sh <prog> [--dump FILE] [--window TITLE] [--out PNG]
#                               [--dark] [--once] [--interval SEC]
#
# * compile = tools/sync/build.sh (same compiler call as the image build), so
#   a red here is red in the image; errors are printed, the loop goes on.
# * preview = tools/preview/axpng.py on the a11y.tree dump FILE (e.g. from a
#   guest: `act call a11y.tree window=<title>`; or hand-edited to try a layout).
#   The dump is re-read on every round, so editing the dump re-renders too.
# * --once = one round and exit (exit 1 on compile error / no window); the gate uses it.
# * USRC=<dir> compiles from another copy of kernel/user (gate counter-proofs).
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
PROG=${1:?usage: watch.sh <prog> [--dump FILE] [--window TITLE] [--out PNG] [--dark] [--once]}
shift
DUMP=""; WIN=""; OUT=""; DARK=""; ONCE=0; INT=1
while [ $# -gt 0 ]; do
    case "$1" in
        --dump) DUMP=$2; shift 2 ;;
        --window) WIN=$2; shift 2 ;;
        --out) OUT=$2; shift 2 ;;
        --dark) DARK=--dark; shift ;;
        --once) ONCE=1; shift ;;
        --interval) INT=$2; shift 2 ;;
        *) echo "unknown option $1" >&2; exit 2 ;;
    esac
done
USRC="${USRC:-kernel/user}"
SRC="$USRC/$PROG.fi"
[ -f "$SRC" ] || { echo "no such program source: $SRC" >&2; exit 2; }
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
[ -n "$OUT" ] || OUT="$WORK/$PROG.png"
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1

round() {
    local t0 t1 rc=0 sig
    t0=$(date +%s.%N)
    if USRC="$USRC" bash tools/sync/build.sh "$WORK/bin" 0 "$PROG" > "$WORK/b.txt" 2>&1; then
        t1=$(date +%s.%N)
        printf 'BUILD ok   %s  %.1f s  %s bytes\n' "$PROG" "$(awk -v a="$t0" -v b="$t1" "BEGIN{print b-a}")" "$(stat -c %s "$WORK/bin/$PROG.elf")"
    else
        printf 'BUILD FAIL %s\n' "$PROG"; sed 's/^/    /' "$WORK/b.txt" | head -14; rc=1
    fi
    if [ -n "$DUMP" ]; then
        python3 -I tools/preview/axpng.py "$DUMP" ${WIN:+--window "$WIN"} $DARK -o "$OUT" || rc=1
    fi
    return $rc
}

sig() { stat -c %Y "$SRC" ${DUMP:+"$DUMP"} 2>/dev/null | tr '\n' ' '; }

round; rc=$?
[ "$ONCE" = 1 ] && exit $rc
echo "watching $SRC${DUMP:+ and $DUMP} (Ctrl-C ends)"
last=$(sig)
while sleep "$INT"; do
    cur=$(sig)
    [ "$cur" = "$last" ] && continue
    last=$cur
    echo "--- change $(date +%T)"
    round
done
