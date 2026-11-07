#!/usr/bin/env bash
set -u
OUT=${1:?output directory missing}
mkdir -p "$OUT"
rm -f "$OUT/list.txt"

encode() {
    local name=$1 w=$2 h=$3 n=$4 container=$5 src=$6
    shift 6
    ffmpeg -y -v error -f lavfi -i "$src" -frames:v "$n" \
        -c:v libx264 -profile:v baseline -pix_fmt yuv420p "$@" \
        "$OUT/$name.$container" 2>"$OUT/$name.enc.log" || return 1
    ffmpeg -y -v error -i "$OUT/$name.$container" -an \
        -f rawvideo -pix_fmt yuv420p "$OUT/$name.yuv" 2>>"$OUT/$name.enc.log" || return 1
    printf '%s %s %s %s %s\n' "$name" "$w" "$h" "$n" "$container" >> "$OUT/list.txt"
}

encode i_only 176 144 4 mp4 "testsrc2=size=176x144:rate=10" -g 1 -qp 26
encode p_moov_end 176 144 9 mp4 "testsrc2=size=176x144:rate=10" -g 100 -qp 26
encode p_faststart 176 144 9 mp4 "testsrc2=size=176x144:rate=10" -g 5 -qp 26 -movflags +faststart
encode p_cif 352 288 8 mp4 "testsrc2=size=352x288:rate=10" -g 100 -qp 26
encode p_mov 128 96 6 mov "testsrc2=size=128x96:rate=10" -g 4 -qp 24
encode p_long 176 144 12 mp4 "testsrc2=size=176x144:rate=10" -g 100 -qp 26
encode p_gop4 128 96 12 mov "testsrc2=size=128x96:rate=10" -g 4 -qp 24
encode p_long30 176 144 30 mp4 "testsrc2=size=176x144:rate=10" -g 100 -qp 20
encode p_hq 96 80 20 mp4 "testsrc2=size=96x80:rate=10" -g 7 -qp 6

ffmpeg -y -v error -f lavfi -i "testsrc2=size=176x144:rate=10" \
    -f lavfi -i "sine=frequency=440:sample_rate=22050:duration=1.2" \
    -frames:v 9 -c:v libx264 -profile:v baseline -pix_fmt yuv420p -g 100 -qp 26 \
    -c:a pcm_s16le -ac 2 -t 1.2 "$OUT/av.mov" 2>"$OUT/av.enc.log" || exit 1
ffmpeg -y -v error -i "$OUT/av.mov" -an -f rawvideo -pix_fmt yuv420p "$OUT/av.yuv" || exit 1
ffmpeg -y -v error -i "$OUT/av.mov" -vn -f s16le -acodec pcm_s16le "$OUT/av.pcm" || exit 1
printf '%s %s %s %s %s\n' av 176 144 9 mov >> "$OUT/list.txt"

ffmpeg -y -v error -f lavfi -i "sine=frequency=330:sample_rate=16000:duration=0.8" \
    -c:a pcm_s16le -ac 1 "$OUT/audio_only.mov" 2>"$OUT/ao.enc.log" || exit 1
ffmpeg -y -v error -i "$OUT/audio_only.mov" -f s16le -acodec pcm_s16le "$OUT/audio_only.pcm" || exit 1

ffmpeg -y -v error -f lavfi -i "testsrc2=size=128x96:rate=10" -frames:v 3 \
    -c:v libx264 -profile:v high -pix_fmt yuv420p "$OUT/x_high.mp4" 2>/dev/null || exit 1
ffmpeg -y -v error -f lavfi -i "testsrc2=size=1920x1080:rate=5" -frames:v 2 \
    -c:v libx264 -profile:v baseline -pix_fmt yuv420p "$OUT/x_big.mp4" 2>/dev/null || exit 1
echo "MEDIA: $(wc -l < "$OUT/list.txt") clips"
