#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
REPO=${FIRN_REPO:-$HOME/firn}
REF=${1:-pin}
PIN=$(cat "$ROOT/vendor/firn/COMMIT")
if [[ $REF == pin ]]; then
    TARGET=$PIN
else
    TARGET=$(git -C "$REPO" rev-parse "$REF")
fi
fail=0
ok() { echo "OK   $*"; }
bad() { echo "FAIL $*"; fail=$((fail + 1)); }
git -C "$REPO" cat-file -e "$PIN^{commit}" 2>/dev/null && ok "pin ${PIN:0:8} exists in $REPO" || bad "pin ${PIN:0:8} missing in $REPO"
git -C "$REPO" cat-file -e "$TARGET^{commit}" 2>/dev/null || { bad "target $REF missing"; exit 1; }
if git -C "$REPO" remote | grep -qx origin; then
    git -C "$REPO" branch -r --contains "$PIN" 2>/dev/null | grep -q origin/ \
        && ok "pin is reachable from an origin branch" || bad "pin is not on any origin branch"
fi
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
cp -a "$ROOT/vendor/firn/." "$D/"
rm -rf "$D/bin" "$D/lib" "$D/.gebaut"
echo "$TARGET" > "$D/COMMIT"
if OSUM_FIRN_TOOLCHAIN=0 FIRN_REPO=$REPO bash "$D/fetch-firnc.sh" --force > "$D/build.log" 2>&1; then
    ok "fetch-firnc.sh --force builds ${TARGET:0:8} with $(find "$ROOT/vendor/firn/patches" -name "*.patch" 2>/dev/null | wc -l) patches"
else
    bad "fetch-firnc.sh --force failed on ${TARGET:0:8}"
    tail -15 "$D/build.log"
fi
echo "$fail failed"
exit $((fail > 0))
