#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/menualive/run.sh -- THE START MENU STAYS USABLE (Dell bug, 04.10.2026).
#
#   bash tools/menualive/run.sh
#
# Justin's Dell, 13:30: the start menu opens ("Programm suchen:"), but nothing
# can be clicked, nothing typed, the highlight sticks, and the taskbar says
# "CPU 100 %". Reproduced with the Dell's own image in a VM (4 cores, xHCI
# keyboard and mouse, 1920x1080):
#   * the menu's process ("starter", the launcher started hidden) polled in a
#     loop that only YIELDED -- it burnt a core for as long as the machine ran
#     (2338 of 2700 ticks in 27 s) and had a limit of 4 000 000 rounds;
#   * a process that ends does not take its windows with it. The launcher
#     ended (limit, fault or kill), its window stayed as a PICTURE; Super
#     toggled that picture and every key went into it. That is the Dell photo.
# Fixes: (1) `wlib.step` sleeps after 200 quiet rounds, the round limits of the
# scene programs are gone; (2) `kgui.fenster_wache` destroys windows whose
# owner is dead, so the next Super / Start starts a fresh launcher; (3) the
# desktop loop of the kernel waits for the next interrupt (`sched.idle_wait`)
# instead of spinning on core 0 (the taskbar's CPU gauge reads this core).
#
# What this run does (the machine of the stick: tools/design/eh6.sh, USB):
#   1. two `ps` listings 20 s apart: the hidden launcher uses < 10 % of a core;
#   2. the launcher is killed from the terminal (the Dell's state);
#   3. Super: a menu comes up, typing "file" + Enter starts the file manager;
#   4. COUNTER-PROOF with the kernel words `nowinsweep nohltidle` (sweep off,
#      desktop loop spinning): the dead window is still there, typing starts
#      nothing -- the Dell's state -- and the desktop loop uses the core again.
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
export DESIGNBUILD="$TMPD/build"

run() { # run <name> <extra kernel words>
    local name=$1; shift
    bash tools/design/eh6.sh "$TMPD/$name" res=1920x1080 accel=kvm \
        drehbuch=tools/menualive/dreh.txt extra="$*" > "$TMPD/$name.log" 2>&1
    grep -a "FEHLGESCHLAGEN\|NICHT DA\|killstarter:" "$TMPD/$name.log" | head -3
}

echo "== fix on: build and run =="
run fix
D="$TMPD/fix"
[ -s "$D/04-after-enter.ppm" ] && ok "the run took all pictures" \
    || bad "pictures are missing: $(tail -3 "$TMPD/fix.log" | tr '\n' ' ')"
python3 tools/menualive/check.py cpu "$D/serial.txt" starter | tee "$TMPD/cpu.txt" | sed 's/^/        /'
sh=$(sed -n 's/.*share=\([-0-9.]*\).*/\1/p' "$TMPD/cpu.txt" | head -1)
awk -v s="${sh:--1}" 'BEGIN{exit !(s >= 0 && s < 10)}' \
    && ok "the hidden launcher uses ${sh} % of a core (limit 10 %)" \
    || bad "the hidden launcher uses ${sh:-?} % of a core (limit 10 %)"
python3 tools/menualive/check.py cpu "$D/serial.txt" kind:boot | tee "$TMPD/cpub.txt" | sed 's/^/        /'
shb=$(sed -n 's/.*share=\([-0-9.]*\).*/\1/p' "$TMPD/cpub.txt" | head -1)
awk -v s="${shb:--1}" 'BEGIN{exit !(s >= 0 && s < 15)}' \
    && ok "the desktop loop (boot task, core 0) uses ${shb} % at idle (limit 15 %)" \
    || bad "the desktop loop (boot task, core 0) uses ${shb:-?} % at idle (limit 15 %)"
grep -aq 'kgui: dead window removed' "$D/serial.txt" \
    && ok "the window of the killed launcher was swept away" \
    || bad "no 'kgui: dead window removed' after the kill"
grep -aq '^explorer: ready' "$D/serial.txt" \
    && ok "Super, typing \"file\", Enter: the file manager started" \
    || bad "after the kill the menu took no input (no 'explorer: ready')"
if [ -s "$D/02-menu.ppm" ] && [ -s "$D/03-typed.ppm" ]; then
    n=$(python3 tools/menualive/check.py diff "$D/02-menu.ppm" "$D/03-typed.ppm" 8 580 450 1035 | sed 's/changed=//')
    [ "${n:-0}" -gt 500 ] \
        && ok "typing changed the menu ($n pixels): the field and the list answer" \
        || bad "typing changed ${n:-0} pixels in the menu: it takes no keys"
fi

echo "== counter-proof: the sweep off (nowinsweep) =="
run ctl nowinsweep nohltidle
D="$TMPD/ctl"
python3 tools/menualive/check.py cpu "$D/serial.txt" kind:boot | tee "$TMPD/cpub2.txt" | sed 's/^/        /'
shc=$(sed -n 's/.*share=\([-0-9.]*\).*/\1/p' "$TMPD/cpub2.txt" | head -1)
awk -v s="${shc:--1}" 'BEGIN{exit !(s >= 50)}' \
    && ok "with nohltidle the desktop loop spins again (${shc} %): the CPU check measures something" \
    || bad "with nohltidle the desktop loop uses only ${shc:-?} % -- the CPU check is blind"
if grep -aq '^explorer: ready' "$D/serial.txt"; then
    bad "even with nowinsweep the menu worked -- the test is blind"
else
    ok "with nowinsweep the dead menu takes no input (the Dell's state)"
fi
if [ -s "$D/02-menu.ppm" ] && [ -s "$D/03-typed.ppm" ]; then
    n=$(python3 tools/menualive/check.py diff "$D/02-menu.ppm" "$D/03-typed.ppm" 8 580 450 1035 | sed 's/changed=//')
    [ "${n:-0}" -le 500 ] \
        && ok "with nowinsweep typing changes nothing ($n pixels)" \
        || bad "with nowinsweep typing still changed $n pixels -- the test is blind"
fi

echo
echo "MENUALIVE: $pass passed, $fail failed"
[ "$fail" = 0 ]
