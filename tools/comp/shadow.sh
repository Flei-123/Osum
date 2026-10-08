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
run() { # run <name> <extra words> [capture argument]
    bash tools/design/capture.sh "$D/$1" uitrace=yes accel=kvm drehbuch="$D/dreh.txt" \
        "extra=wigapp=/bin/wmd wighalt=150 $2" "progs=desktop taskbar settings launcher explorer edit sh echo ls cat theme wmd" ${3:+"$3"} \
        > "$D/$1.log" 2>&1
    grep -a "FEHLGESCHLAGEN" "$D/$1.log" | head -3
}
stats() { # stats <serial>  ->  judged cycles, max compared, sum compared, sum differ, max compose_us
    grep -a '^wmd: cycle ' "$1" | awk '{
        n++; for (i = 1; i <= NF; i++) { split($i, kv, "=");
            if (kv[1] == "compared") { c = kv[2]; if (c > cm) cm = c; cs += c }
            if (kv[1] == "differ") ds += kv[2]
            if (kv[1] == "compose_us") { u = kv[2]; if (u > um) um = u; us[n] = u } }
    } END { m = 0; if (n > 0) { for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) if (us[j] < us[i]) { t = us[i]; us[i] = us[j]; us[j] = t }; m = us[int((n + 1) / 2)] } printf "%d %d %d %d %d\n", n, cm, cs, ds, m }'
}

echo "== 1. the desktop with the shadow compositor =="
run shd "" window_alpha=100
S="$D/shd/serial.txt"
grep -a '^wmd:' "$S" | sed 's/^/        /' | head -110
grep -aq '^wmd: ' "$S" || { echo "        (no wmd line; capture log tail:)"; tail -n 12 "$D/shd.log" | sed 's/^/        /'; grep -a "desk:\|wmd\|exec\|spawn\|fault\|page" "$S" | head -20 | cut -c1-200 | sed 's/^/        D: /'; grep -a "wmd\|ELF\|elf\|error\|Error" "$D/shd.log" | head -10 | cut -c1-200 | sed 's/^/        L: /'; }
grep -aq '^wmd: ready screen=' "$S" && ok "wmd found the screen and the window table page" || bad "wmd did not start ($(grep -a '^wmd:' "$S" | head -2 | tr '\n' ' '))"
read N CM CS DS UM < <(stats "$S")
[ "${N:-0}" -ge 5 ] && ok "$N stable cycles were judged" || bad "only ${N:-0} stable cycles"
[ "${CM:-0}" -ge 200000 ] && ok "the largest judged area: $CM pixels (the file manager's client area)" || bad "the largest judged area is only ${CM:-0} pixels"
[ "${CS:-0}" -gt 0 ] && [ "${DS:-1}" = 0 ] && ok "$CS pixels judged over all cycles, 0 differ from the kernel's picture" || bad "differing pixels: ${DS:-?} of ${CS:-0}"
[ "${UM:-99999}" -le 8000 ] && ok "composing a frame in ring 3 took ${UM} us (median of the cycles) (budget 8000)" || bad "composing took ${UM:-?} us, median (budget 8000)"
echo "        cycles=$N max_area=$CM compared_sum=$CS differ_sum=$DS compose_us_max=$UM"
# r486: the desktop window (the wallpaper, a screen-sized window) paints into a shared buffer too, so wmd judges the wallpaper from the
# very first cycle on (before: nothing was judged until the file manager opened; 21.9 M pixels in all)
grep -aq '^desktop: shared=1' "$S" && ok "the desktop window paints into a shared buffer" || bad "desktop: $(grep -a '^desktop: shared' "$S" | head -1)"
C1=$(grep -a '^wmd: cycle ' "$S" | head -1 | tr ' ' '\n' | awk -F= '$1 == "compared" { print $2; exit }')
[ "${C1:-0}" -ge 300000 ] && ok "the first cycle already judged the wallpaper: $C1 pixels" || bad "the first cycle judged only ${C1:-0} pixels"
[ "${CS:-0}" -ge 30000000 ] && ok "$CS pixels judged over all cycles (21.9 M before the desktop was shared)" || bad "only ${CS:-0} pixels judged over all cycles"

echo "== 2. counter-proof: noshare -- no shared buffer, wmd can judge nothing =="
run nsh "noshare" window_alpha=100
S2="$D/nsh/serial.txt"
read N2 CM2 CS2 DS2 UM2 < <(stats "$S2")
echo "        cycles=$N2 max_area=$CM2 compared_sum=$CS2 differ_sum=$DS2"
[ "${CM2:-1}" -lt "${CM:-0}" ] && [ "${CM2:-1}" -lt 20000 ] && ok "noshare: wmd could judge only $CM2 pixels (against $CM)" || bad "noshare: wmd judged $CM2 pixels anyway"
grep -aq '^desktop: shared=0' "$S2" && ok "noshare: the desktop window falls back to the copy path (shared=0)" || bad "noshare: $(grep -a '^desktop: shared' "$S2" | head -1)"

echo
echo "SHADOW: $pass passed, $fail failed"
[ "$fail" = 0 ]
