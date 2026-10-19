#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/vmsvgaresize/big.sh -- r1139: a host hint OVER the framebuffer tile limit ends directly in the shrunk mode.
# Kernel words `vmsvgahints vmsvgabig` play 1280x720, 2496x1507, 1024x768, 1600x900. 2496x1507 needs 8 tiles of 2 MiB (limit: 8 minus the
# tiles other devices hold) and is above QEMU's card register limit, so vmode.follow_host must shrink it ONCE (x15/16) to 2340x1412 and
# switch there at once: one mode switch, no failed switch, no rollback in between (r1137: a switch + rollback path crashed the kernel).
# Per step the serial line `vmsvga: testhint WxH rc=N now=WxH sw=S fl=F rv=R` (switch / fail / revert counters) is judged:
#   step 2: rc=0, now=2340x1412, sw +1, fl +0, rv +0.   All other steps: now == the requested size, rc=0, fl +0, rv +0.
# Then the whole run.sh checks (size, taskbar, menu) run against the size the kernel reports.
# Usage: [STICK_DIR=<dir with orientos-usb.img>] [IMG=<file>] bash tools/vmsvgaresize/big.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
K=$(mktemp -d); trap 'rm -rf "$K"' EXIT
EXTRA_WORDS="vmsvgabig" RESIZE_USE_NOW=1 SIZES=1280x720,2496x1507,1024x768,1600x900 KEEP="$K" \
    bash tools/vmsvgaresize/run.sh
rc=$?
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
mapfile -t L < <(grep -a '^vmsvga: testhint ' "$K/serial.txt" | head -4)
for l in "${L[@]}"; do echo "  NOTE  $l"; done
[ "${#L[@]}" -ge 4 ] && ok "4 testhint lines" || bad "only ${#L[@]} testhint lines"
want=("1280x720" "2340x1412" "1024x768" "1600x900")
psw=0; pfl=0; prv=0
for i in 0 1 2 3; do
    line=${L[$i]:-}
    now=$(echo "$line" | grep -oE 'now=[0-9]+x[0-9]+' | cut -d= -f2)
    rcv=$(echo "$line" | grep -oE 'rc=[0-9]+' | cut -d= -f2)
    sw=$(echo "$line" | grep -oE 'sw=[0-9]+' | cut -d= -f2); fl=$(echo "$line" | grep -oE 'fl=[0-9]+' | cut -d= -f2); rv=$(echo "$line" | grep -oE 'rv=[0-9]+' | cut -d= -f2)
    [ "$now" = "${want[$i]}" ] && ok "hint $((i+1)): screen is ${want[$i]}" || bad "hint $((i+1)): screen '$now', wanted ${want[$i]} ($line)"
    [ "$rcv" = 0 ] && ok "hint $((i+1)): rc=0" || bad "hint $((i+1)): rc='$rcv'"
    if [ "$i" = 0 ]; then
        # the first line is the baseline (boot already counts its own refusals, e.g. fl=2); only the CHANGE per hint is judged
        psw=${sw:-0}; pfl=${fl:-0}; prv=${rv:-0}
    else
        [ "${fl:-9}" = "$pfl" ] && ok "hint $((i+1)): no failed switch" || bad "hint $((i+1)): fails $pfl -> ${fl:-?}"
        [ "${rv:-9}" = "$prv" ] && ok "hint $((i+1)): no rollback" || bad "hint $((i+1)): reverts $prv -> ${rv:-?}"
    fi
    if [ "$i" = 1 ]; then
        [ "$(( ${sw:-0} - psw ))" = 1 ] && ok "hint 2: exactly ONE mode switch (direct to the shrunk size)" || bad "hint 2: switches $psw -> ${sw:-?}, wanted +1"
    fi
    psw=${sw:-$psw}; pfl=${fl:-$pfl}; prv=${rv:-$prv}
done
echo "big: $pass ok, $fail fail (run.sh rc=$rc)"
[ "$fail" = 0 ] && [ "$rc" = 0 ]
