#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/comp/present.sh -- docs/COMPOSITOR.md stage S5: `wmd present` TAKES THE SCAN-OUT, THE KERNEL KEEPS A WATCHDOG.
#
#   bash tools/comp/present.sh        (start it through /root/jarvis/bin/heavy)
#
# Boots the desktop with /bin/wmd started as `wmd present ...` (kernel/user/wmd.fi, run_present): the kernel hands every finished
# rectangle over instead of pushing it to the card, the program calls WM_COMP / CP_PRESENT. F12 prints the kernel's counters
# (`wm: comp on= att= det= miss= hand= pres= kpres= ev= evref= hopn= ... wlatn= wlatavg= wlatmax= ...`).
#
# Scenes (one boot each, same drehbuch: pointer moves, F12, a button press, F12, a window drag, F12):
#   1 normal    the compositor shows the frames: pres grows, the kernel shows none itself (kpres does not move), no miss, no detach,
#               it got the pointer copy, and the input-to-picture time (pointer interrupt -> card) is 16 ms or less
#   2 die       `dieon=1`: the program exits at the first button press -> detached at once (det=1), the kernel presents again
#               (kpres moves), the window drag after it still works (kpres moves again)
#   3 hang      `hangon=1`: alive but silent -> the watchdog pushes frames (miss >= 3), detaches (det=1), the kernel presents again
#   4 slow      `slow=120`: every frame takes longer than the 50 ms limit -> misses, detach, the kernel presents again
#   5 counter-proofs
#     nowatch   hang WITHOUT the watchdog: no miss, no detach, kpres frozen, hand grows and pres does not: the picture would freeze
#               (so the take-over in 3 measured something)
#     nocomp    the attach is refused: the program says so, pres = 0, the kernel shows every frame (kpres moves)
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
fahre 300,300
fahre 700,500
fahre 200,150
fahre 900,300
warte 2
taste f12
warte 1
klick 24,780
warte 3
taste esc
warte 2
taste f12
ziehe 300,57 700,300
warte 2
ziehe 700,300 200,150
warte 3
taste f12
warte 1
DREH

run() { # run <name> <wigapp arguments> [extra kernel words]
    bash tools/design/capture.sh "$D/$1" uitrace=yes accel=kvm drehbuch="$D/dreh.txt" \
        "extra=wigapp=/bin/wmd,present${2:+,$2} wighalt=150 ${3:-}" "progs=desktop taskbar settings launcher explorer edit sh echo ls cat theme wmd" \
        > "$D/$1.log" 2>&1
    grep -a "FEHLGESCHLAGEN" "$D/$1.log" | head -3
    # PRESENT_KEEP=<dir>: keep the serial output of every scene for a look afterwards
    [ -n "${PRESENT_KEEP:-}" ] && { mkdir -p "$PRESENT_KEEP"; cp "$D/$1/serial.txt" "$PRESENT_KEEP/$1.serial" 2>/dev/null; }
}
comp() { # comp <serial> <n>  -> the n-th "wm: comp" line (1-based), empty if there is none
    grep -a '^wm: comp ' "$1" | sed -n "${2}p"
}
val() { # val <line> <name> -> the number after name=
    printf '%s\n' "$1" | tr ' ' '\n' | awk -F= -v k="$2" '$1 == k { print $2; exit }'
}
dl() { # dl <lineA> <lineB> <name> -> B - A of a running total
    echo $(( $(val "$2" "$3") - $(val "$1" "$3") ))
}
show() { # show <name>
    grep -a '^wm: comp \|^wm: compositor detached\|^wmd: attach\|^wmd: hanging\|^wmd: dying\|^wmd: wait failed' "$D/$1/serial.txt" | cut -c1-260 | sed 's/^/        /' | head -12
}

# ---------------------------------------------------------------------------------------------------- 1 normal
echo "== 1. normal: the compositor shows the frames =="
run nor ""
[ "${PRESENT_ONLY:-}" = nor ] && { grep -a '^wmd:\|^wm: comp' "$D/nor/serial.txt" | head -80; }
S="$D/nor/serial.txt"
show nor
A=$(comp "$S" 1); C=$(comp "$S" 3)
grep -aq '^wmd: attached' "$S" && ok "wmd attached as the compositor" || bad "wmd did not attach"
[ -n "$A" ] && [ -n "$C" ] || bad "fewer than three F12 lines (A='${A:0:30}' C='${C:0:30}')"
PA=$(val "$A" pres); PC=$(val "$C" pres); KA=$(val "$A" kpres); KC=$(val "$C" kpres)
[ "$(val "$C" on)" = 1 ] && ok "still attached at the end (on=1)" || bad "not attached at the end"
# the start-up storm (many programs at once) can make the compositor late three times in a row: the watchdog detaches it and `wmd`
# attaches again 500 ms later (att=2). So the gate is about the run AFTER the first F12, 27 s after the desktop came up.
[ "$(dl "$A" "$C" det)" = 0 ] && [ "$(dl "$A" "$C" miss)" = 0 ] && ok "no detach and no miss after the first F12 (det $(val "$A" det) -> $(val "$C" det), miss $(val "$A" miss) -> $(val "$C" miss))" || bad "det $(val "$A" det) -> $(val "$C" det), miss $(val "$A" miss) -> $(val "$C" miss)"
[ "${PC:-0}" -ge "$(( ${PA:-0} + 10 ))" ] && [ "${PC:-0}" -ge 30 ] && ok "the compositor showed $PC frames ($((PC - PA)) of them during pointer, press and window drag)" || bad "pres $PA -> $PC"
[ "${KC:-1}" = "${KA:-0}" ] && ok "the kernel showed no frame itself after the first F12 (kpres $KA -> $KC)" || bad "kpres $KA -> $KC (the kernel kept presenting)"
[ "$(val "$C" ev)" -ge 20 ] 2>/dev/null && ok "the input copy ring delivered $(val "$C" ev) events (evref $(val "$C" evref))" || bad "ev=$(val "$C" ev)"
HN=$(val "$C" hopn); HM=$(val "$C" hopmax); HA=$(val "$C" hopavg)
echo "        hand-over to present: n=$HN avg=${HA} us max=${HM} us"
# the input-to-picture clock: every F12 line holds the clock of the phase BEFORE it; the window drag is the last phase
WN=$(val "$C" wlatn); WA=$(val "$C" wlatavg); WM=$(val "$C" wlatmax)
echo "        pointer interrupt to card (compositor path), window drag phase: n=$WN avg=${WA} us max=${WM} us"
[ "${WN:-0}" -ge 5 ] && [ "${WA:-99999999}" -le 16000 ] && ok "input to picture: mean ${WA} us over $WN pointer frames (budget 16000)" || bad "input to picture: n=${WN:-?} mean=${WA:-?} us"
[ "${WM:-99999999}" -le 100000 ] && ok "slowest pointer frame ${WM} us (budget 100000: a loaded host stalls a VM for tens of ms; the mean is the gate)" || bad "slowest pointer frame ${WM:-?} us"

[ "${PRESENT_ONLY:-}" = nor ] && { echo "PRESENT (scene 1 only): $pass passed, $fail failed"; [ "$fail" = 0 ]; exit; }

# ---------------------------------------------------------------------------------------------------- 2 die
echo "== 2. the compositor dies at the first button press =="
run die "dieon=1"
S="$D/die/serial.txt"
show die
A=$(comp "$S" 1); B=$(comp "$S" 2); C=$(comp "$S" 3)
grep -aq 'wmd: dying now' "$S" && ok "the compositor exited on cue" || bad "no 'wmd: dying now'"
grep -aq '^wm: compositor detached why=1' "$S" && ok "the kernel saw the death and detached it (why=1)" || bad "no detach why=1"
[ "$(dl "$A" "$B" det)" = 1 ] && ok "one second after the press the counters already say one more detach (det $(val "$A" det) -> $(val "$B" det))" || bad "det $(val "$A" det) -> $(val "$B" det)"
KB=$(val "$B" kpres); KC=$(val "$C" kpres)
[ "${KB:-0}" -gt "$(val "$A" kpres)" ] && ok "the kernel shows the frames itself again (kpres $(val "$A" kpres) -> $KB)" || bad "kpres did not move after the death ($(val "$A" kpres) -> $KB)"
[ "${KC:-0}" -ge "$(( ${KB:-0} + 10 ))" ] && ok "the window drag afterwards is shown (kpres $KB -> $KC)" || bad "window drag not shown (kpres $KB -> $KC)"
[ "$(val "$C" on)" = 0 ] && ok "on=0 at the end" || bad "on=$(val "$C" on) at the end"

# ---------------------------------------------------------------------------------------------------- 3 hang
echo "== 3. the compositor hangs (alive and silent) =="
run hng "hangon=1"
S="$D/hng/serial.txt"
show hng
A=$(comp "$S" 1); B=$(comp "$S" 2); C=$(comp "$S" 3)
grep -aq 'wmd: hanging now' "$S" && ok "the compositor hangs on cue" || bad "no 'wmd: hanging now'"
grep -aq '^wm: compositor detached why=2' "$S" && ok "the watchdog detached it after 3 misses in a row (why=2)" || bad "no detach why=2"
[ "$(dl "$A" "$C" miss)" -ge 3 ] 2>/dev/null && ok "the watchdog pushed $(dl "$A" "$C" miss) frames to the card itself" || bad "miss $(val "$A" miss) -> $(val "$C" miss)"
[ "$(dl "$A" "$B" det)" = 1 ] && ok "one second after the press the kernel has taken over (det $(val "$A" det) -> $(val "$B" det))" || bad "det $(val "$A" det) -> $(val "$B" det)"
KB=$(val "$B" kpres); KC=$(val "$C" kpres)
[ "${KC:-0}" -ge "$(( ${KB:-0} + 10 ))" ] && ok "the window drag afterwards is shown (kpres $KB -> $KC)" || bad "window drag not shown (kpres $KB -> $KC)"

# ---------------------------------------------------------------------------------------------------- 4 slow
echo "== 4. the compositor is too slow (120 ms per frame, limit 50 ms) =="
run slw "slow=120"
S="$D/slw/serial.txt"
show slw
C=$(comp "$S" 3)
[ "$(val "$C" miss)" -ge 3 ] 2>/dev/null && ok "the watchdog pushed $(val "$C" miss) late frames" || bad "miss=$(val "$C" miss)"
[ "$(val "$C" det)" -ge 2 ] 2>/dev/null && ok "a compositor that is always late is detached again and again (det=$(val "$C" det))" || bad "det=$(val "$C" det)"
[ "$(dl "$(comp "$S" 1)" "$C" kpres)" -gt 0 ] 2>/dev/null && ok "the kernel showed frames itself (kpres $(val "$(comp "$S" 1)" kpres) -> $(val "$C" kpres))" || bad "kpres $(val "$(comp "$S" 1)" kpres) -> $(val "$C" kpres)"

# ---------------------------------------------------------------------------------------------------- 5 counter-proofs
echo "== 5a. counter-proof nowatch: a hung compositor and no watchdog =="
run nwa "hangon=1" nowatch
S="$D/nwa/serial.txt"
show nwa
B=$(comp "$S" 2); C=$(comp "$S" 3)
HB=$(val "$B" hand); HC=$(val "$C" hand); PB=$(val "$B" pres); PC=$(val "$C" pres)
[ "$(val "$C" miss)" = 0 ] && [ "$(val "$C" det)" = 0 ] && ok "no miss, no detach without the watchdog" || bad "miss=$(val "$C" miss) det=$(val "$C" det) (the watchdog worked anyway)"
[ "${PC:-1}" = "${PB:-0}" ] && [ "${HC:-0}" -gt "${HB:-0}" ] && ok "frames pile up: handed over $HB -> $HC, shown stays $PB -> $PC (the picture is frozen)" || bad "hand $HB -> $HC, pres $PB -> $PC"
[ "$(val "$C" kpres)" = "$(val "$B" kpres)" ] && ok "the kernel shows nothing either (kpres stays $(val "$C" kpres))" || bad "kpres moved"

echo "== 5b. counter-proof nocomp: the attach is refused =="
run nco "" "nocomp phases"
S="$D/nco/serial.txt"
show nco
C=$(comp "$S" 3)
grep -aq '^wmd: attach refused' "$S" && ok "the attach was refused" || bad "no refusal"
[ "${C:-}" = "" ] || [ "$(val "$C" pres)" = 0 ] && ok "the compositor showed no frame (pres=0)" || bad "pres=$(val "$C" pres)"
[ "$(val "$C" kpres)" -ge 10 ] 2>/dev/null && ok "the kernel showed every frame itself (kpres=$(val "$C" kpres))" || bad "kpres=$(val "$C" kpres)"

echo
echo "PRESENT: $pass passed, $fail failed"
[ "$fail" = 0 ]
