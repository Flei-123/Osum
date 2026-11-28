#!/usr/bin/env bash
set -uo pipefail
GATE=${1:?gate}; GOOD=${2:?good commit}; BAD=${3:-origin/main}
REPO=${OSUM_REPO:-$(cd "$(dirname "$0")/../.." && pwd)}
WT=$(mktemp -d "${TMPDIR:-/tmp}/qa-bisect.XXXXXX")
cleanup() { git -C "$REPO" worktree remove --force "$WT" >/dev/null 2>&1; rm -rf "$WT"; }
trap cleanup EXIT
git -C "$REPO" worktree add -q --detach "$WT" "$BAD" || exit 2
cd "$WT" || exit 2
cat > "$WT/.git-probe.sh" <<PROBE
#!/usr/bin/env bash
LOG=\$(mktemp)
bash tools/qa/gates.sh --changed --only "$GATE" --run --jobs 1 --base HEAD > "\$LOG" 2>&1
RC=\$?
grep -q ' SKIP: ' "\$LOG" && RC=125
rm -f "\$LOG"
exit \$RC
PROBE
git bisect start "$BAD" "$GOOD" > /dev/null || exit 2
git bisect run bash "$WT/.git-probe.sh" 2>&1 | tail -40
git bisect reset > /dev/null 2>&1
