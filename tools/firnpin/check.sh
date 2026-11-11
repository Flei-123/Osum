#!/usr/bin/env bash
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
. "$ROOT/tools/lib/summary.sh"
. "$ROOT/tools/lib/firnenv.sh"
summary_begin FIRNPIN
trap summary_guard EXIT
SHADOWS="$ROOT/tools/firnpin/shadows.txt"
pass=0
fail=0
ok() { echo "  OK    $*"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $*"; fail=$((fail + 1)); }

[ -f "$ROOT/firn.toolchain" ] && ok "firn.toolchain present" || bad "firn.toolchain missing"
[ -d "$FIRN_TOOLCHAIN/lib" ] && ok "toolchain $FIRN_VERSION_USED installed" || bad "toolchain $FIRN_VERSION_USED not installed"

for path in vendor/firn/bin vendor/firn/lib vendor/firn/COMMIT vendor/firn/fetch-firnc.sh; do
    [ -e "$ROOT/$path" ] && bad "forbidden path exists: $path" || ok "absent: $path"
done

refs=$(git -C "$ROOT" grep -lI 'vendor/firn' -- . ':!*.md' ':!reports' ':!belege' ':!.mess' ':!tools/lib/firnenv.sh' ':!tools/firnpin/check.sh' || true)
[ -z "$refs" ] && ok "no script refers to vendor/firn" || bad "vendor/firn referenced in: $(echo $refs | tr '\n' ' ')"

while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    [ -f "$ROOT/lib/$rel" ] || { bad "stale shadow entry: $rel"; continue; }
    [ -f "$FIRN_TOOLCHAIN/lib/$rel" ] || { bad "shadow entry not in toolchain: $rel"; continue; }
    if cmp -s "$ROOT/lib/$rel" "$FIRN_TOOLCHAIN/lib/$rel"; then
        bad "duplicate (identical to toolchain), delete it: $rel"
    else
        ok "shadow $rel"
    fi
done < "$SHADOWS"

while IFS= read -r rel; do
    [ -f "$FIRN_TOOLCHAIN/lib/$rel" ] || continue
    grep -qxF "$rel" "$SHADOWS" && continue
    if cmp -s "$ROOT/lib/$rel" "$FIRN_TOOLCHAIN/lib/$rel"; then
        bad "duplicate (identical to toolchain), delete it: $rel"
    else
        bad "unlisted shadow of toolchain lib: $rel"
    fi
done < <(git -C "$ROOT" ls-files lib | grep '\.fi$' | sed 's#^lib/##')

summary_emit "$pass" "$fail" 10
