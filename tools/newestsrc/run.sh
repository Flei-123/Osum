#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

mkdir -p "$T/kernel/user/sub" "$T/lib/deep/er"
touch -d '2020-01-01' "$T/kernel/user/top.fi"
touch -d '2020-01-02' "$T/kernel/user/sub/inner.fi"
touch -d '2020-01-03' "$T/lib/deep/er/lib.fi"

newest() { ( cd "$T" && bash "$ROOT/tools/design/newest-source.sh" ); }
old_rule() { ( cd "$T" && ls -t kernel/user/*.fi 2>/dev/null | head -1 ); }

[ "$(newest)" = "lib/deep/er/lib.fi" ] && ok "newest source found in a deep lib folder" || bad "deep lib folder missed: $(newest)"
touch -d '2020-02-01' "$T/kernel/user/sub/inner.fi"
[ "$(newest)" = "kernel/user/sub/inner.fi" ] && ok "newest source found in a kernel/user subfolder" || bad "subfolder missed: $(newest)"
[ "$(old_rule)" = "kernel/user/top.fi" ] && ok "counter-probe: the old top-level rule misses the subfolder" || bad "counter-probe: old rule saw $(old_rule)"

stale=0
for f in tools/design/eh6.sh tools/design/eh6-two.sh tools/design/eh5.sh tools/design/capture.sh tools/design/audit.sh \
         tools/themestore/build.sh tools/toolbench/build.sh tools/alltag/build.sh tools/look/shot.sh; do
    if grep -q 'ls -t kernel/user/\*.fi' "$f"; then stale=$((stale+1)); bad "$f still uses the top-level rule"; fi
    grep -q 'tools/design/newest-source.sh' "$f" || { stale=$((stale+1)); bad "$f does not use newest-source.sh"; }
done
[ "$stale" = 0 ] && ok "all nine build scripts use newest-source.sh"

echo "NEWESTSRC: $pass passed, $fail failed"
[ "$fail" = 0 ]
