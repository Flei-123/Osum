#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { local name=$1 value=$2 op=$3 want=$4
    if [ -z "$value" ]; then bad "$name: no number found (expected $op $want)"; return; fi
    if [ "$value" -"$op" "$want" ] 2>/dev/null; then ok "$name: $value"
    else bad "$name: $value, erwartet $op $want"; fi
}
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' sollte nicht dastehen" || ok "$3"; }
val() { tr -d '\r' < "$1" | grep -a "$2" | sed -n "${4:-1}p" | grep -oE " $3=[0-9a-fx]+" | head -1 | sed 's/.*=//'; }
