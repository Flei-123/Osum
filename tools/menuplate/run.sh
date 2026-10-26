#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT" "$OUT-build"' EXIT; fi
export DESIGNBUILD="${DESIGNBUILD:-$OUT-build}"
mkdir -p "$OUT"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
bash tools/design/eh6.sh "$OUT/run" res=1920x1080 accel=kvm mode=light lang=de \
    tbextra="align=center;labels=never;height=48" drehbuch="$(pwd)/tools/menuplate/scene.txt" > "$OUT/run.log" 2>&1
D="$OUT/run"
C=tools/menuplate/check.py
chk() { # chk <label> <plate|same> <rest> <hover> x0 y0 x1 y1 limit [pointer_x pointer_y]
    local label=$1; shift
    local msg
    if msg=$(python3 -I "$C" "$@"); then ok "$label ($msg)"; else bad "$label ($msg)"; fi
}
for f in p0-rest p1-tile p1d-tile-down p2-allapps p2d-allapps-down p5-power p3-list-rest p4-list-hover; do
    [ -s "$D/$f.ppm" ] || bad "picture $f is missing"
done
chk "pinned tile under the pointer shows its plate" plate "$D/p0-rest.ppm" "$D/p1-tile.ppm" 665 715 755 790 8 710 745
chk "pinned tile pressed is darker than hovered" plate "$D/p1-tile.ppm" "$D/p1d-tile-down.ppm" 665 715 755 790 6 710 745
chk "neighbour tile stays plain" same "$D/p0-rest.ppm" "$D/p1-tile.ppm" 770 715 850 790 2
chk "All apps button shows a hover plate" plate "$D/p0-rest.ppm" "$D/p2-allapps.ppm" 1090 680 1190 705 6 1172 688
chk "All apps button pressed is darker than hovered" plate "$D/p2-allapps.ppm" "$D/p2d-allapps-down.ppm" 1090 680 1190 705 4 1172 688
chk "power button shows a hover plate" plate "$D/p0-rest.ppm" "$D/p5-power.ppm" 1186 953 1228 993 6 1205 973
chk "result row under the pointer shows its plate" plate "$D/p3-list-rest.ppm" "$D/p4-list-hover.ppm" 665 815 1250 865 6 910 830
chk "first result row keeps the selection colour" same "$D/p3-list-rest.ppm" "$D/p4-list-hover.ppm" 665 712 1250 760 2
echo "menuplate: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
