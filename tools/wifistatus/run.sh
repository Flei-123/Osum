#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
. tools/lib/summary.sh
summary_begin WIFISTATUS
T=$(mktemp -d); trap 'rm -rf "$T"; summary_guard; summary_exit_status || exit 1' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

SRC=kernel/user/settings/setwifi.fi
HEALTH=kernel/net/nethealth.fi

check() {
    local f=$1 label=$2 n=0
    local nogw noinet get
    nogw=$(sed -n 's/^const H_NOGW: u64 = \([0-9]*\)$/\1/p' "$HEALTH")
    noinet=$(sed -n 's/^const H_NOINET: u64 = \([0-9]*\)$/\1/p' "$HEALTH")
    get=$(sed -n 's/^const NG_HEALTH: u64 = \([0-9]*\)$/\1/p' kernel/sys/sys.fi)
    grep -q "^const NG_HEALTH: u64 = $get$" "$f" || n=$((n+1))
    grep -q "^const HEALTH_NO_GATEWAY: u64 = $nogw$" "$f" || n=$((n+1))
    grep -q "^const HEALTH_NO_INTERNET: u64 = $noinet$" "$f" || n=$((n+1))
    grep -q "ulib.sys(setbase.SYS_NETGET, NG_HEALTH, 0, 0)" "$f" || n=$((n+1))
    grep -q "^            if no_internet() {$" "$f" || n=$((n+1))
    echo "$n"
}

echo "== 1. the Wi-Fi status uses the net health stage =="
[ "$(check $SRC now)" = 0 ] && ok "setwifi reads NG_HEALTH with the kernel numbers (no gateway .. no internet)" || bad "setwifi does not read the net health stage"

echo "== 2. mutations must go red =="
mut() {
    local name=$1 from=$2 to=$3
    sed "s|$from|$to|" $SRC > "$T/m.fi"
    cmp -s $SRC "$T/m.fi" && { bad "mutation $name did not change the file"; return; }
    [ "$(check "$T/m.fi" m)" != 0 ] && ok "mutation $name goes red" || bad "mutation $name stays green"
}
mut old-arp-only 'if no_internet() {' 'if nv.link_state() < NET_ONLINE {'
mut wrong-range-low 'HEALTH_NO_GATEWAY: u64 = 2' 'HEALTH_NO_GATEWAY: u64 = 3'
mut wrong-range-high 'HEALTH_NO_INTERNET: u64 = 4' 'HEALTH_NO_INTERNET: u64 = 5'
mut wrong-call 'NG_HEALTH, 0, 0)' 'NG_STATE, 0, 0)'

echo "== 3. the settings program builds =="
mkdir -p "$T/bin"
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
if bash tools/sync/build.sh "$T/bin" 0 settings > "$T/b.txt" 2>&1 && [ -s "$T/bin/settings.elf" ]; then ok "settings builds with the new status check"; else bad "settings build failed"; tail -8 "$T/b.txt"; fi

summary_emit "$pass" "$fail" 6
