#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/qa/redcheck.sh -- classify the red of ONE gate run: "expected red" vs "NEW red".
#
#   redcheck.sh GATE LOGFILE EXITCODE        GATE = e.g. pci/run  (tools/pci/run.sh)
#   redcheck.sh --list                        print the baseline as a table
#
# Reads the log of a gate run, finds the failure lines (FAIL / NEIN / FEHL /
# FEHLGESCHLAGEN / ROT / FEHLER, with or without colour codes), matches each one
# against tools/qa/expected-red.txt and prints:
#   expected red : <line>   (reason)
#   NEW red      : <line>
# Exit code: 0 = green or only expected red, 1 = at least one NEW red,
#            2 = usage error.
# Env: EXPECTED_RED = baseline file (default: next to this script).
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BASE=${EXPECTED_RED:-$HERE/expected-red.txt}

baseline() { # prints "gate<TAB>case<TAB>kind<TAB>reason" for non-comment lines
    awk -F' [|] ' '/^[[:space:]]*#/ || NF < 4 {next} {printf "%s\t%s\t%s\t%s\n", $1, $2, $3, $4}' "$BASE"
}

if [[ ${1:-} == --list ]]; then
    printf '%-14s %-6s %-40s %s\n' GATE KIND CASE REASON
    baseline | while IFS=$'\t' read -r g c k r; do printf '%-14s %-6s %-40s %s\n' "$g" "$k" "${c:0:40}" "$r"; done
    exit 0
fi

GATE=${1:-}; LOG=${2:-}; RC=${3:-}
if [[ -z $GATE || -z $LOG || -z $RC || ! -f $LOG ]]; then
    sed -n '2,15p' "$0"; exit 2
fi

new=0; exp=0
declare -A FIRED=()
# strip colour codes, then take the failure lines
mapfile -t FAILS < <(sed -E 's/\x1b\[[0-9;]*m//g' "$LOG" | \
    grep -aE '^[[:space:]]*(FAIL|NEIN|FEHL|FEHLGESCHLAGEN|ROT|FEHLER)([[:space:]:]|$)' | \
    sed -E 's/^[[:space:]]*(FAIL|NEIN|FEHLGESCHLAGEN|FEHLER|FEHL|ROT):?[[:space:]]*//')
mapfile -t ENT < <(baseline | awk -F'\t' -v g="$GATE" '$1==g')

has_star=""; star_reason=""
for e in "${ENT[@]}"; do
    IFS=$'\t' read -r g c k r <<<"$e"
    [[ $c == '*' ]] && { has_star=1; star_reason=$r; }
done

for line in "${FAILS[@]}"; do
    hit=""
    for e in "${ENT[@]}"; do
        IFS=$'\t' read -r g c k r <<<"$e"
        if [[ $c != '*' ]] && grep -qE -- "$c" <<<"$line"; then hit=$r; FIRED[$c]=1; break; fi
    done
    [[ -z $hit && -n $has_star ]] && hit=$star_reason
    if [[ -n $hit ]]; then
        exp=$((exp + 1)); printf 'expected red : %s   (%s)\n' "$line" "$hit"
    else
        new=$((new + 1)); printf 'NEW red      : %s\n' "$line"
    fi
done

# exit code without any FAIL line (crash, timeout, gate without FAIL lines)
if [[ $RC -ne 0 && ${#FAILS[@]} -eq 0 ]]; then
    if [[ -n $has_star ]]; then
        exp=$((exp + 1)); printf 'expected red : exit code %s without FAIL line   (%s)\n' "$RC" "$star_reason"
    else
        new=$((new + 1)); printf 'NEW red      : exit code %s without any FAIL line (crash/timeout?)\n' "$RC"
    fi
fi

# baseline entries that did not fire in a green-ish run: report stale lines
if [[ $RC -eq 0 ]]; then
    for e in "${ENT[@]}"; do
        IFS=$'\t' read -r g c k r <<<"$e"
        [[ $k == flaky ]] && continue
        [[ $c == '*' || -n ${FIRED[$c]:-} ]] || printf 'FIXED?       : baseline entry "%s" did not fire (gate green) -- remove it\n' "$c"
    done
fi

printf 'redcheck %s: %d expected red, %d NEW red (exit %s)\n' "$GATE" "$exp" "$new" "$RC"
[[ $new -eq 0 ]]
