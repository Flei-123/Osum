#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/qa/gates.sh -- the MINIMUM set of gates for a change, by level.
#
#   gates.sh --changed [--base REF] [--level quick|full|nightly] [--run] [--jobs N] [--keep]
#   gates.sh --changed --only tokens,softui --run     explicit gates, same runner + classification
#   gates.sh --list [--level L]       manifest table (tools/qa/gates.tsv)
#   gates.sh --check                  manifest vs tools/*/run.sh (new gate without a row = error)
#   gates.sh --times                  last measured wall time per gate (from earlier --run)
#
# --changed prints the gates for the files changed against BASE (default
# origin/main, three-dot) plus uncommitted files. Without --run it only prints
# (dry run). With --run every gate runs through /root/jarvis/bin/heavy (the
# server-wide slot limit applies), the log is classified by tools/qa/redcheck.sh
# ("expected red" from tools/qa/expected-red.txt vs "NEW red") and the exit code
# is 1 only on NEW red.
#
# Levels (cumulative): quick = fast/representative gates of the touched areas
# (aim: minutes), full = + all other gates of the touched areas (before a merge),
# nightly = ALL gates, ignores the paths (cron on main).
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
QA=$ROOT/tools/qa
GROOT=""   # --root DIR: select/run the gates of ANOTHER worktree (manifest + redcheck stay from here)
HEAVY=${GATES_HEAVY:-/root/jarvis/bin/heavy}
TIMES=${GATES_TIMES:-${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/osum-gates/times.tsv}

mode=""; BASE=origin/main; LEVEL=full; RUN=0; JOBS=2; KEEP=0; ONLY=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --changed|--list|--check|--times) mode=$1 ;;
        --base) BASE=$2; shift ;;
        --level) LEVEL=$2; shift ;;
        --run) RUN=1 ;;
        --jobs) JOBS=$2; shift ;;
        --keep) KEEP=1 ;;
        --root) GROOT=$2; shift ;;   # run in this worktree instead of the current one
        --only) ONLY=$2; shift ;;   # comma list of gates: skip the selection
        -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
        *) echo "unknown option $1" >&2; exit 2 ;;
    esac
    shift
done
[[ -n $mode ]] || { sed -n '2,19p' "$0"; exit 2; }

case $mode in
--check) python3 -I $QA/gen-manifest.py --check; exit $? ;;
--times)
    [[ -f $TIMES ]] && sort -t$'\t' -k2 -rn "$TIMES" | awk -F'\t' '!s[$1]++{printf "%-14s %6d s  %s  %s\n",$1,$2,$3,$4}' || echo "no times yet ($TIMES)"
    exit 0 ;;
--list)
    awk -F'\t' -v l="$LEVEL" 'BEGIN{ok["quick"]="quick"; ok["full"]="quick full"; ok["nightly"]="quick full nightly"}
        NR>1 && index(" " ok[l] " ", " " $2 " ") {printf "%-14s %-8s %-14s %s\n",$1,$2,$3,$6; n++}
        END{printf "%d gates at level %s\n", n, l}' "$QA/gates.tsv"
    exit 0 ;;
esac

# --changed
[[ -n $GROOT ]] && cd "$GROOT"
CH=$(mktemp)
trap 'rm -f "$CH"' EXIT
{ git diff --name-only "$BASE"...HEAD 2>/dev/null; git diff --name-only HEAD 2>/dev/null; git ls-files --others --exclude-standard; } | sort -u > "$CH"
NCH=$(wc -l < "$CH")
# notes go to stderr (prefixed '#'), the gate names to stdout
if [[ -n $ONLY ]]; then SEL=(); else mapfile -t SEL < <(python3 -I $QA/gates-select.py --level "$LEVEL" --explain < "$CH"); fi
[[ -n $ONLY ]] && IFS=, read -r -a SEL <<<"$ONLY"
echo "base=$BASE level=$LEVEL changed_files=$NCH gates=${#SEL[@]}"
printf '  %s\n' "${SEL[@]}"
[[ $RUN -eq 1 ]] || { echo "(dry run -- add --run to execute through heavy)"; exit 0; }
[[ ${#SEL[@]} -gt 0 ]] || { echo "nothing to run"; exit 0; }

OUT=$(mktemp -d); mkdir -p "$(dirname "$TIMES")"
trap 'rm -f "$CH"; [[ $KEEP -eq 1 ]] && echo "logs kept in $OUT" || rm -rf "$OUT"' EXIT

run_one() { # gate
    local g=$1 t0 t1 rc
    t0=$(date +%s)
    if [[ -x $HEAVY ]]; then "$HEAVY" bash "tools/$g/run.sh" > "$OUT/$g.log" 2>&1; rc=$?
    else bash "tools/$g/run.sh" > "$OUT/$g.log" 2>&1; rc=$?; fi
    t1=$(date +%s)
    echo "$rc" > "$OUT/$g.rc"
    printf '%s\t%d\t%s\t%s\n' "$g" $((t1 - t0)) "$(date +%F)" "rc=$rc" >> "$TIMES"
}
for g in "${SEL[@]}"; do
    while (( $(jobs -rp | wc -l) >= JOBS )); do wait -n 2>/dev/null || break; done
    run_one "$g" &
done
wait

new_total=0
for g in "${SEL[@]}"; do
    rc=$(cat "$OUT/$g.rc" 2>/dev/null || echo 99)
    echo "== $g (exit $rc) =="
    bash $QA/redcheck.sh "$g/run" "$OUT/$g.log" "$rc" | sed 's/^/   /' || new_total=$((new_total + 1))
    tail -2 "$OUT/$g.log" | sed 's/^/   | /'
done
echo "gates: ${#SEL[@]} run, $new_total with NEW red"
[[ $new_total -eq 0 ]]
