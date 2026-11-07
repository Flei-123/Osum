#!/usr/bin/env bash
set -u
OUT=${1:?output directory missing}
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT"
rm -f "$OUT/list.txt"

reorder_clip() {
    local name=$1 frames=$2 gop=$3 vui=$4 reorder=$5 effective=$6
    ffmpeg -y -v error -f lavfi -i "testsrc2=size=176x144:rate=10" -frames:v "$frames" \
        -c:v libx264 -profile:v baseline -pix_fmt yuv420p -qp 26 -g "$gop" \
        -x264opts "keyint=$gop:min-keyint=$gop:scenecut=0" -f h264 "$OUT/$name.src.h264" || return 1
    python3 -I "$HERE/mkreorder.py" "$OUT/$name.src.h264" "$OUT/$name.h264" "$vui" "$reorder" "$gop" \
        > "$OUT/$name.order" || return 1
    local d="mod(N\\,$gop)"
    local pts="120000*(N-$d+if(eq($d\\,0)\\,0\\,if(eq(mod($d\\,2)\\,1)\\,$d+1\\,$d-1))+1)"
    ffmpeg -y -v error -f h264 -framerate 10 -i "$OUT/$name.h264" -c copy \
        -bsf:v "setts=dts=120000*N:pts=$pts" "$OUT/$name.mp4" || return 1
    ffmpeg -y -v error -i "$OUT/$name.mp4" -an -f rawvideo -pix_fmt yuv420p "$OUT/$name.yuv" || return 1
    ffmpeg -y -v error -i "$OUT/$name.src.h264" -f rawvideo -pix_fmt yuv420p "$OUT/$name.src.yuv" || return 1
    printf '%s %s\n' "$gop" "$effective" > "$OUT/$name.meta"
    printf '%s 176 144 %s mp4\n' "$name" "$frames" >> "$OUT/list.txt"
}

reorder_clip ro_min 10 5 min 1 1 || exit 1
reorder_clip ro_full 10 5 full 1 1 || exit 1
reorder_clip ro_none 10 5 none 1 2 || exit 1
reorder_clip ro_wrap 21 21 min 1 1 || exit 1

ffmpeg -y -v error -f lavfi -i "testsrc2=size=176x144:rate=10" -frames:v 9 \
    -c:v libx264 -profile:v main -pix_fmt yuv420p -qp 26 -bf 2 -g 100 \
    -x264opts cabac=0:weightp=0:b-pyramid=none:direct=spatial "$OUT/b_main.mp4" || exit 1
echo "MEDIA: $(wc -l < "$OUT/list.txt") reorder clips + b_main"
