#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/firnenv.sh
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail=0

build_and_run() {
    local dir="$1"
    cp tools/uicheck/host.fi "$dir/host.fi"
    FIRNLIB="$PWD/lib" "$FIRNC" --profile=app "$dir/host.fi" -o "$dir/host" > "$dir/build.log" 2>&1 \
        || { echo "FAIL  build $dir"; head -20 "$dir/build.log"; return 1; }
    "$dir/host" > "$dir/rows.txt" || { echo "FAIL  host program"; return 1; }
}

mkdir -p "$T/real" "$T/mutant/uikit"
ln -s "$PWD/kernel/user/uikit" "$T/real/uikit"
build_and_run "$T/real" || exit 1
python3 -I tools/uicheck/check.py "$T/real/rows.txt" || fail=1

cp kernel/user/uikit/*.fi "$T/mutant/uikit/"
sed -i -e 's/if legacy_look || w < 3 || h < 3 {/if true {/' -e 's/if legacy_look || translucent(kind) || w < 3.0 || h < 3.0 {/if true {/' "$T/mutant/uikit/uiplate.fi"
build_and_run "$T/mutant" || exit 1
if python3 -I tools/uicheck/check.py "$T/mutant/rows.txt" > "$T/mutant.out" 2>&1; then
    echo "FAIL  counter-probe: old plate look passed the component check"
    fail=1
else
    echo "OK    counter-probe: old plate look is red ($(grep -c '^FAIL' "$T/mutant.out") claims)"
fi

python3 tools/uicheck/ratchet.py check || fail=1
python3 tools/uicheck/ratchet.py selftest || fail=1
python3 tools/palette/ratchet.py check || fail=1
if [ "$fail" = 0 ]; then
    echo "UICHECK: passed"
else
    echo "UICHECK: failed"
fi
exit "$fail"
