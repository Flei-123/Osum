#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
export FIRNLIB="$PWD/lib"
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
echo "== rfkillwatch: hardware rfkill edge detection + retry policy =="
if $FIRNC tools/rfkillwatch/watch.fi -o "$D/w" 2> "$D/err"; then ok "tools/rfkillwatch/watch.fi builds"; else bad "build"; head -20 "$D/err"; echo "RESULT pass=$pass fail=$fail"; exit 1; fi
"$D/w" > "$D/out"; rc=$?
n_ok=$(grep -ac '^OK ' "$D/out"); n_bad=$(grep -ac '^FAIL ' "$D/out")
[ "$rc" = 0 ] && [ "$n_bad" = 0 ] && [ "$n_ok" -ge 12 ] && ok "$n_ok library checks pass" || { bad "library checks ($n_ok ok, $n_bad fail, rc=$rc)"; grep -a '^FAIL ' "$D/out" | head; }
mut() {
    mkdir -p "$D/m" && rm -rf "$D/m"/* && cp -r lib/. "$D/m/"; sed -i "$1" "$D/m/wlan/iwl_rfkill.fi"
    if FIRNLIB="$D/m" $FIRNC tools/rfkillwatch/watch.fi -o "$D/mm" 2> /dev/null; then
        if ! "$D/mm" > "$D/mo" 2>&1; then ok "mutant caught: $2"; else bad "mutant NOT caught: $2"; fi
    else bad "mutant did not build: $2"; fi
}
mut 's/return (gp \& GP_HW_RF_KILL_SW) == 0/return (gp \& GP_HW_RF_KILL_SW) != 0/' "bit 27 polarity inverted"
mut 's/if now != 0 || boot_blocked != 0 { (\*w).armed = 1 }/if now != 0 { (*w).armed = 1 }/' "boot-time block ignored"
mut 's/(\*w).retries < MAX_RETRIES/true/' "retry cap removed"
mut 's/^    (\*w).armed = 0$/    (*w).armed = 1/' "armed not cleared after retry"
mut 's/(\*w).changes = (\*w).changes + 1/(*w).changes = (*w).changes/' "changes not counted"
echo "RESULT pass=$pass fail=$fail"
[ "$fail" = 0 ]
