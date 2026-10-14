#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# pakete/repro.sh -- IS THE PACKAGE BUILD REPRODUCIBLE?
#
# Builds the packages twice (pakete/bauen.sh) into two fresh directories, with a
# different file mtime, time zone and umask the second time, and compares the
# SHA-256 of every .opk. A package that differs between two builds of the same
# source cannot be signed once and verified by anybody else.
#
#   bash pakete/repro.sh [name ...]        default: fvviewer
set -uo pipefail
cd "$(dirname "$0")/.."
NAMES=("$@"); [ ${#NAMES[@]} -gt 0 ] || NAMES=(fvviewer)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
bash pakete/bauen.sh "$T/a" > "$T/a.log" 2>&1 || { tail -8 "$T/a.log"; echo "REPRO: build 1 failed"; exit 1; }
# second build: touch the sources, other zone, other umask, no leftover payloads
find kernel/user lib -name '*.fi' -exec touch {} + 2>/dev/null
rm -rf pakete/*/bau
( umask 077; TZ=Asia/Tokyo bash pakete/bauen.sh "$T/b" > "$T/b.log" 2>&1 ) || { tail -8 "$T/b.log"; echo "REPRO: build 2 failed"; exit 1; }
bad=0
for n in "${NAMES[@]}"; do
    f=$(cd "$T/a" && ls "$n"-*.opk 2>/dev/null | head -1)
    [ -n "$f" ] || { echo "  FAIL  $n: no package built"; bad=$((bad+1)); continue; }
    ha=$(sha256sum "$T/a/$f" | cut -d' ' -f1); hb=$(sha256sum "$T/b/$f" 2>/dev/null | cut -d' ' -f1)
    if [ "$ha" = "$hb" ]; then echo "  OK    $f identical ($ha)"; else echo "  FAIL  $f differs ($ha vs ${hb:-missing})"; bad=$((bad+1)); fi
done
echo "REPRO: $([ $bad = 0 ] && echo ok || echo "$bad failed")"
[ $bad = 0 ]
