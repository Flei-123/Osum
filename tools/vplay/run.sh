#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
KEEP=${1:-}
D=$(mktemp -d)
. tools/lib/summary.sh; summary_begin VPLAY
trap 'summary_guard; rm -rf "$D"; summary_exit_status || exit 1' EXIT
trap 'exit 1' HUP INT TERM
pass=0; fail=0
for w in ffmpeg python3 qemu-system-x86_64; do
    command -v "$w" >/dev/null 2>&1 || { summary_note "skipped, $w is missing"; exit 0; }
done
python3 -I -c 'import numpy' 2>/dev/null || { summary_note "skipped, numpy is missing"; exit 0; }
for l in de en; do
    n=$(grep -c '^vplay\.' locale/$l/messages)
    if [ "$n" -ge 5 ]; then echo "  OK    locale $l: $n vplay.* keys"; pass=$((pass+1)); else echo "  FAIL  locale $l: $n vplay.* keys"; fail=$((fail+1)); fi
done
if grep -q '/apps/vplay.osp/start' tools/usbimg/build.sh && grep -q '/bin/vplay' tools/usbimg/build.sh && [ -f assets/apps/vplay.osp/symbol.osym ]; then
    echo "  OK    usbimg ships /bin/vplay and its bundle"; pass=$((pass+1))
else echo "  FAIL  usbimg list or bundle"; fail=$((fail+1)); fi
bash tools/vplay/mkclip.sh "$D/m" || { echo "  FAIL  clip"; summary_emit "$pass" $((fail+1)) 0; exit 1; }
bash tools/vplay/shot.sh "$D/new" new "$D/m/clip.mov" 1 > "$D/new.log" 2>&1 &
p1=$!
bash tools/vplay/shot.sh "$D/nosync" nosync "$D/m/clip.mov" 1 > "$D/nosync.log" 2>&1 &
p2=$!
bash tools/vplay/shot.sh "$D/x2" new "$D/m/clip.mov" 2 > "$D/x2.log" 2>&1 &
p3=$!
bash tools/vplay/shot.sh "$D/mp3a" new "$D/m/clip_mp3.mp4" 1 > "$D/mp3a.log" 2>&1 &
p6=$!
wait $p1 $p2 $p3 $p6
bash tools/vplay/shot.sh "$D/click" new "$D/m/clip.mov" 1 "$PWD/tools/vplay/click.txt" > "$D/click.log" 2>&1 &
p4=$!
bash tools/vplay/shot.sh "$D/stall" stall "$D/m/clip.mov" 1 "$PWD/tools/vplay/click.txt" > "$D/stall.log" 2>&1 &
p5=$!
bash tools/vplay/shot.sh "$D/mp3b" new "$D/m/clip_mp3.mov" 1 > "$D/mp3b.log" 2>&1 &
p7=$!
bash tools/vplay/shot.sh "$D/mute" mute "$D/m/clip_mp3.mp4" 1 > "$D/mute.log" 2>&1 &
p8=$!
bash tools/vplay/shot.sh "$D/aac" new "$D/m/clip_aac.mp4" 1 > "$D/aac.log" 2>&1 &
p9=$!
bash tools/vplay/shot.sh "$D/aacmute" mute "$D/m/clip_aac.mp4" 1 > "$D/aacmute.log" 2>&1 &
p10=$!
wait $p4 $p5 $p7 $p8 $p9 $p10
python3 -I tools/vplay/check.py "$D/new" "$D/m/clip.yuv" | tee "$D/new.res"
python3 -I tools/vplay/check.py "$D/nosync" "$D/m/clip.yuv" nosync | tee "$D/ns.res"
python3 -I tools/vplay/check.py "$D/x2" "$D/m/clip.yuv" | grep -a "all .* shown frames\|reached the end" | sed 's/^  \(OK\|FAIL\)  /  \1    scale 2: /' | tee "$D/x2.res"
python3 -I tools/vplay/check.py "$D/mp3a" "$D/m/clip_mp3.yuv" | sed 's/^  \(OK\|FAIL\)  /  \1    mp3 in mp4: /' | tee "$D/mp3a.res"
python3 -I tools/vplay/mp3check.py "$D/mp3a" | sed 's/^  \(OK\|FAIL\)  /  \1    mp3 in mp4: /' | tee "$D/mp3a2.res"
python3 -I tools/vplay/check.py "$D/mp3b" "$D/m/clip_mp3.yuv" | grep -a "all .* shown frames\|reached the end\|audio clock vs frame" | sed 's/^  \(OK\|FAIL\)  /  \1    mp3 in mov: /' | tee "$D/mp3b.res"
python3 -I tools/vplay/mp3check.py "$D/mp3b" | sed 's/^  \(OK\|FAIL\)  /  \1    mp3 in mov: /' | tee "$D/mp3b2.res"
python3 -I tools/vplay/mp3check.py "$D/mute" mute | tee "$D/mute.res"
python3 -I tools/vplay/check.py "$D/aac" "$D/m/clip_aac.yuv" | sed 's/^  \(OK\|FAIL\)  /  \1    aac in mp4: /' | tee "$D/aac1.res"
python3 -I tools/vplay/aaccheck.py "$D/aac" "$D/m/clip_aac.ref" | sed 's/^  \(OK\|FAIL\)  /  \1    aac in mp4: /' | tee "$D/aac2.res"
python3 -I tools/vplay/aaccheck.py "$D/aacmute" "$D/m/clip_aac.ref" mute | tee "$D/aac3.res"
python3 -I tools/vplay/clickcheck.py "$D/click" | tee "$D/click.res"
python3 -I tools/vplay/clickcheck.py "$D/stall" stall | tee "$D/stall.res"
[ -n "$KEEP" ] && { mkdir -p "$KEEP"; cp -r "$D"/new "$D"/nosync "$D"/x2 "$D"/click "$D"/stall "$D"/mp3a "$D"/mp3b "$D"/mute "$D"/aac "$D"/aacmute "$KEEP/" 2>/dev/null; }
n_ok=$(cat "$D"/*.res | grep -ac '^  OK'); n_bad=$(cat "$D"/*.res | grep -ac '^  FAIL')
summary_emit $((pass + n_ok)) $((fail + n_bad)) 68
