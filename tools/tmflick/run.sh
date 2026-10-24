#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/tmflick/run.sh -- W-FLICKER: a window resize keeps the old picture (no flat dark flash) until the client has painted the new size.
#
#   /root/jarvis/bin/heavy bash tools/tmflick/run.sh [taskmgr] [explorer] [charmap] [snip] [netmon] [welcome]
#   TMFLICK_KEEP=<dir> keeps the screendumps; TMFLICK_RES=WxH, TMFLICK_EXTRA=<kernel words> for other set-ups
#
# Boots one program at 1920x1080 (QEMU KVM), drags its bottom-right corner back and forth (serie drag:, 72 screendumps) and counts frames whose
# client area is flat dark (blank.py). Case `new` must show <= 2 blank frames; the counter-proof `old` must show many, else the measurement
# proves nothing:  taskmgr -> kernel word `resclear` (the window server clears to the background),
#                  explorer -> /etc/paintdirect (the client paints in place into the shared buffer instead of a private atomic picture).
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap '[ -n "${TMFLICK_KEEP:-}" ] && { mkdir -p "$TMFLICK_KEEP"; cp -r "$TMPD"/. "$TMFLICK_KEEP"/; }; rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
APPS=${*:-taskmgr explorer}
corner() { case $1 in taskmgr) echo 982,618;; explorer) echo 931,673;; charmap) echo 922,543;; snip) echo 812,623;; netmon) echo 732,493;; welcome) echo 682,473;; esac; }
appargs() { case $1 in taskmgr) echo ",takt,100";; *) echo "";; esac; }
for app in $APPS; do
    printf "warte 8\nfoto base\nfahre $(corner $app)\nwarte 2\nserie drag:14,9,12 72 r 35\nwarte 2\nfoto post\n" > "$TMPD/book.txt"
    for v in new old; do
        w=""; xf=()
        if [ $v = old ]; then
            if [ $app = taskmgr ]; then w=" resclear"; else : > "$TMPD/pd"; xf=(xfile=/etc/paintdirect="$TMPD/pd"); fi
        fi
        d="$TMPD/$app-$v"
        OSUM_ACCEL=kvm bash tools/alltag/build.sh "$d" kbd=yes uitrace=yes warten=6 res=${TMFLICK_RES:-1920x1080} \
            extra="wigapp=/bin/$app$(appargs $app) wighalt=100$w ${TMFLICK_EXTRA:-}" progs="$app theme sh echo ls cat" drive="$TMPD/book.txt" ${xf[@]+"${xf[@]}"} > "$d.log" 2>&1
        out=$(python3 -I tools/tmflick/blank.py "$d" r 2>&1 | head -1)
        echo "  $app $v: $out"
        n=$(echo "$out" | sed -n 's/.*blank=\([0-9]*\).*/\1/p')
        if [ -z "$n" ]; then bad "$app $v: no measurement"; continue; fi
        if [ $v = new ]; then
            [ "$n" -le 2 ] && ok "$app: resize keeps a whole picture (blank frames $n <= 2)" || bad "$app: resize flashes blank ($n frames)"
        else
            [ "$n" -ge 20 ] && ok "$app counter-proof: $n blank frames (old behaviour reproduced)" || bad "$app counter-proof shows only $n blank frames"
        fi
    done
done
git checkout -- docs 2>/dev/null
echo "TMFLICK: $pass passed, $fail failed"
[ "$fail" = 0 ]
