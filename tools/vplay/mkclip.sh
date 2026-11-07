#!/usr/bin/env bash
set -euo pipefail
OUT=${1:?output directory missing}
mkdir -p "$OUT"
ffmpeg -y -v error -f lavfi -i "testsrc2=size=176x144:rate=10" \
    -f lavfi -i "sine=frequency=440:sample_rate=48000" \
    -c:v libx264 -profile:v baseline -pix_fmt yuv420p -g 10 -qp 26 \
    -c:a pcm_s16le -ar 48000 -ac 2 -t 20 "$OUT/clip.mov" 2>"$OUT/clip.log"
ffmpeg -y -v error -i "$OUT/clip.mov" -an -f rawvideo -pix_fmt yuv420p "$OUT/clip.yuv"
for ext in mp4 mov; do
    ffmpeg -y -v error -f lavfi -i "testsrc2=size=176x144:rate=10" \
        -f lavfi -i "sine=frequency=440:sample_rate=44100" \
        -c:v libx264 -profile:v baseline -pix_fmt yuv420p -g 10 -qp 26 \
        -c:a libmp3lame -b:a 128k -ar 44100 -ac 2 -t 20 "$OUT/clip_mp3.$ext" 2>>"$OUT/clip.log"
done
ffmpeg -y -v error -i "$OUT/clip_mp3.mp4" -an -f rawvideo -pix_fmt yuv420p "$OUT/clip_mp3.yuv"
