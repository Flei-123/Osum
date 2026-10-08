#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/comp/shadow.sh -- docs/COMPOSITOR.md stage S4: `wmd`, THE SHADOW COMPOSITOR, AND THE ORACLE `wm.fi`.
#
#   bash tools/comp/shadow.sh        (start it through /root/jarvis/bin/heavy)
#
# Boots the desktop with /bin/wmd (kernel/user/wmd.fi) as the extra program. wmd is an OBSERVER: it reads the window table page and
# the buffers of the shared windows, composes the client areas of the plain windows into an off-screen picture with `fui.comp`,
# reads the screen back from /dev/fb and counts the pixels that differ. The drehbuch opens the file manager (a shared scene window)
# so that there is something big to judge.
#
# Gates: wmd saw the screen and the table; enough stable cycles; one of them judged a large area (the file manager's client);
# NOT ONE judged pixel differs (differ = 0 summed over all cycles); composing one frame in ring 3 costs 8 ms or less.
# Counter-proof: with the kernel word `noshare` no window has a shared buffer, wmd can judge nothing (compared = 0), so the
# "0 differences" above cannot be an accident of looking at nothing.
set -uo pipefail
cd "$(dirname "$0")/../.."
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

cat > "$D/dreh.txt" <<'DREH'
warteauf 'launcher: ready' || 90
warte 25
klick 24,780
warte 4
klickauf start_File Explorer
warte 14
fahre 1250,780
warte 40
taste f12
warte 3
DREH
run() { # run <name> <extra words>
    bash tools/design/capture.sh "$D/$1" uitrace=yes accel=kvm drehbuch="$D/dreh.txt" \
        "extra=wigapp=/bin/wmd wighalt=150 $2" "progs=desktop taskbar settings launcher explorer edit sh echo ls cat theme wmd" \
        > "$D/$1.log" 2>&1
    grep -a "FEHLGESCHLAGEN" "$D/$1.log" | head -3
}
stats() { # stats <serial>  ->  judged cycles, max compared, sum compared, sum differ, max compose_us
    grep -a '^wmd: cycle ' "$1" | awk '{
        n++; for (i = 1; i <= NF; i++) { split($i, kv, "=");
            if (kv[1] == "compared") { c = kv[2]; if (c > cm) cm = c; cs += c }
            if (kv[1] == "differ") ds += kv[2]
            if (kv[1] == "compose_us") { u = kv[2]; if (u > um) um = u } }
    } END { printf "%d %d %d %d %d\n", n, cm, cs, ds, um }'
}

echo "== 1. the desktop with the shadow compositor =="
run shd ""
S="$D/shd/serial.txt"
grep -a '^wmd:' "$S" | sed 's/^/        /' | head -40
grep -aq '^wmd: ready screen=' "$S" && ok "wmd found the screen and the window table page" || bad "wmd did not start ($(grep -a '^wmd:' "$S" | head -2 | tr '\n' ' '))"
read N CM CS DS UM < <(stats "$S")
[ "${N:-0}" -ge 5 ] && ok "$N stable cycles were judged" || bad "only ${N:-0} stable cycles"
[ "${CM:-0}" -ge 200000 ] && ok "the largest judged area: $CM pixels (the file manager's client area)" || bad "the largest judged area is only ${CM:-0} pixels"
[ "${CS:-0}" -gt 0 ] && [ "${DS:-1}" = 0 ] && ok "$CS pixels judged over all cycles, 0 differ from the kernel's picture" || bad "differing pixels: ${DS:-?} of ${CS:-0}"
[ "${UM:-99999}" -le 8000 ] && ok "composing a frame in ring 3 took at most ${UM} us (budget 8000)" || bad "composing took up to ${UM:-?} us (budget 8000)"
echo "        cycles=$N max_area=$CM compared_sum=$CS differ_sum=$DS compose_us_max=$UM"

echo "== 2. counter-proof: noshare -- no shared buffer, wmd can judge nothing =="
run nsh "noshare"
S2="$D/nsh/serial.txt"
read N2 CM2 CS2 DS2 UM2 < <(stats "$S2")
echo "        cycles=$N2 max_area=$CM2 compared_sum=$CS2 differ_sum=$DS2"
[ "${CM2:-1}" -lt "${CM:-0}" ] && [ "${CM2:-1}" -lt 20000 ] && ok "noshare: wmd could judge only $CM2 pixels (against $CM)" || bad "noshare: wmd judged $CM2 pixels anyway"

echo
echo "SHADOW: $pass passed, $fail failed"
[ "$fail" = 0 ]
