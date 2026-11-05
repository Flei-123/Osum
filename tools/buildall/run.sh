#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
CC="${FIRNC:-$ROOT/vendor/firn/bin/firnc}"
BASELINE="$ROOT/tools/buildall/baseline.txt"
JOBS="${BUILDALL_JOBS:-6}"
MODE="${1:-check}"
OUTDIR="${2:-}"
D=$(mktemp -d)
. tools/lib/tmpdir.sh; osum_tmp_guard "$OUTDIR" "$D"
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/o" "$D/l"

list() { ls kernel/user/*.fi kernel/app/*.fi; echo kernel/kmain.fi; echo kernel/uprog.fi; }

one() {
    local f=$1 n flags=""
    n=$(echo "$f" | tr / _)
    grep -qa '^profile app' "$f" && flags=--profile=app
    if timeout 300 "$CC" $flags -c "$f" -o "$D/o/$n.o" > "$D/l/$n.log" 2>&1; then
        echo "$f ok"
    else
        echo "$f fail"
    fi
}
export -f one
export D CC

list | xargs -P "$JOBS" -I{} bash -c 'one {}' | sort > "$D/result.txt"
STANDALONE=$(grep -c ' ok$' "$D/result.txt")
python3 -I tools/buildall/reach.py "$D/result.txt" "$ROOT" > "$D/failed.txt" 2> "$D/reach.txt"
stub_check() {
    local f=$1 n dir base prof stub
    n=$(echo "$f" | tr / _)
    grep -q "has no function 'main'" "$D/l/$n.log" || return 1
    dir=$(dirname "$f")
    base=$(basename "$f" .fi)
    stub="$D/stub/$n"
    mkdir -p "$stub"
    ln -s "$ROOT/$dir"/* "$stub/" 2>/dev/null
    rm -f "$stub/_stub_main.fi"
    prof=$(grep -a -m1 '^profile ' "$f" | cut -d' ' -f2)
    printf 'profile %s\nimport %s\nfn main() -> i32 {\n    return 0\n}\n' "${prof:-app}" "$base" > "$stub/_stub_main.fi"
    timeout 300 "$CC" ${prof:+--profile=$prof} -c "$stub/_stub_main.fi" -o "$D/o/$n.stub.o" > "$D/l/$n.stub.log" 2>&1
}
: > "$D/failed2.txt"
while read -r f; do
    [ -z "$f" ] && continue
    stub_check "$f" || echo "$f" >> "$D/failed2.txt"
done < "$D/failed.txt"
STUBBED=$(( $(grep -c . "$D/failed.txt") - $(grep -c . "$D/failed2.txt") ))
mv "$D/failed2.txt" "$D/failed.txt"
FAIL=$(grep -c . "$D/failed.txt")
TOTAL=$(grep -c . "$D/result.txt")
MODULES=$((TOTAL - STANDALONE - FAIL))
echo "buildall: $((STANDALONE + MODULES)) ok / $FAIL fail of $TOTAL ($STANDALONE standalone, $MODULES module-only verified through an importer, $STUBBED through a stub importer)"

if [ -n "$OUTDIR" ]; then
    mkdir -p "$OUTDIR"
    cp "$D/result.txt" "$D/failed.txt" "$OUTDIR/"
    cp -r "$D/l" "$OUTDIR/logs"
fi

if [ "$MODE" = update ]; then
    cp "$D/failed.txt" "$BASELINE"
    echo "baseline updated: $FAIL failing files"
    exit 0
fi

touch "$BASELINE"
NEW=$(comm -13 <(sort "$BASELINE") <(sort "$D/failed.txt"))
FIXED=$(comm -23 <(sort "$BASELINE") <(sort "$D/failed.txt"))
rc=0
if [ -n "$NEW" ]; then
    echo "NEW FAILURES (not in baseline):"
    echo "$NEW" | sed 's/^/  /'
    rc=1
fi
if [ -n "$FIXED" ]; then
    echo "FIXED since baseline (run: tools/buildall/run.sh update):"
    echo "$FIXED" | sed 's/^/  /'
    rc=1
fi
[ "$rc" = 0 ] && echo "buildall gate: OK"
exit $rc
