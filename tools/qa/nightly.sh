#!/usr/bin/env bash
set -uo pipefail
REPO=${OSUM_REPO:-/root/jarvis/projects/u_DiS4in7esMF1/osum}
REPORTS=${QA_REPORT_DIR:-/root/jarvis/data/projects_kb/orientos/reports}
EXTRA=${NIGHTLY_EXTRA:-}
JOBS=${NIGHTLY_JOBS:-4}
QA=$(cd "$(dirname "$0")" && pwd)
exec 9> /run/osum-nightly.lock
flock -n 9 || { echo "nightly already running"; exit 0; }
git -C "$REPO" fetch -q origin || { echo "fetch failed"; exit 1; }
COMMIT=$(git -C "$REPO" rev-parse "${NIGHTLY_REF:-origin/main}")
WT=$(mktemp -d "${TMPDIR:-/tmp}/qa-nightly.XXXXXX")
cleanup() { git -C "$REPO" worktree remove --force "$WT" > /dev/null 2>&1; rm -rf "$WT"; }
trap cleanup EXIT
git -C "$REPO" worktree add -q --detach "$WT" "$COMMIT" || exit 1
cd "$WT" || exit 1
GATES=${NIGHTLY_ONLY:-$(awk -F"\t" 'NR>1 && $2=="nightly" {print $1}' tools/qa/gates.tsv | paste -sd, -)}
[[ -n $EXTRA ]] && GATES="$GATES,$EXTRA"
GUI_WD=${GUIAPPS_WD:-/root/abbilder/lapps}
if [[ ! -e $GUI_WD ]]; then
    /root/jarvis/bin/heavy bash tools/linuxapps/guiapps-prep.sh "$GUI_WD" > /dev/null 2>&1 || echo "guiapps prep failed: $GUI_WD missing, linuxapps-gui will be skipped"
fi
RESULTS=$(mktemp)
LOG=$(mktemp)
GATES_RESULTS=$RESULTS bash tools/qa/gates.sh --changed --only "$GATES" --run --jobs "$JOBS" --base HEAD > "$LOG" 2>&1
STAMP=$(date -u +%Y%m%d-%H%M%S)
REPORT=$REPORTS/${STAMP}_nightly-gates.md
mkdir -p "$REPORTS"
LG=$QA/lastgreen.py
declare -A KNOWN_RED=()
while IFS=$'\t' read -r gate status; do
    [[ $status == red && -n $(python3 -I "$LG" field "$gate" first_red) ]] && KNOWN_RED[$gate]=1
done < "$RESULTS"
declare -A PREV_GREEN=()
while IFS=$'\t' read -r gate status; do
    PREV_GREEN[$gate]=$(python3 -I "$LG" field "$gate" last_green)
done < "$RESULTS"
python3 -I "$LG" record "$RESULTS" "$COMMIT"
{
    echo "# Nightly gates $STAMP"
    echo "- main: $COMMIT"
    echo "- gates run: $(wc -l < "$RESULTS") (green $(grep -c 'green$' "$RESULTS"), red $(grep -c 'red$' "$RESULTS"))"
    echo "## Red gates"
    while IFS=$'\t' read -r gate status; do
        [[ $status == red ]] || continue
        if [[ -n ${KNOWN_RED[$gate]:-} ]]; then
            echo "- $gate: still red, first red $(python3 -I "$LG" field "$gate" first_red | cut -c1-9)"
            continue
        fi
        good=${PREV_GREEN[$gate]:-}
        if [[ -z $good ]]; then
            echo "- $gate: red, no earlier green known (no bisect)"
            continue
        fi
        echo "- $gate: NEW red since last green ${good:0:9}, bisect:"
        bash "$QA/bisect-gate.sh" "$gate" "$good" "$COMMIT" 2>&1 | grep -E 'is the first bad commit|^commit|^    ' | head -8 | sed 's/^/  /'
    done < "$RESULTS"
    echo "## Gate log"
    echo '```'
    grep -E '^(==|gates:|   (NEW|PREEXISTING|SKIP))' "$LOG" | head -300
    echo '```'
} > "$REPORT"
rm -f "$RESULTS" "$LOG"
echo "report: $REPORT"
