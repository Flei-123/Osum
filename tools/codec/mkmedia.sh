#!/usr/bin/env bash
set -u
ZIEL=${1:?Zielverzeichnis fehlt}
mkdir -p "$ZIEL"

mach() {
    local name=$1 w=$2 h=$3 n=$4; shift 4
    local quelle=$1; shift
    ffmpeg -y -v error -f lavfi -i "$quelle" -frames:v "$n" \
        -c:v libx264 -profile:v baseline -pix_fmt yuv420p \
        "$@" -f h264 "$ZIEL/$name.264" 2>"$ZIEL/$name.enc.log" || return 1
    ffmpeg -y -v error -i "$ZIEL/$name.264" \
        -f rawvideo -pix_fmt yuv420p "$ZIEL/$name.yuv" \
        2>"$ZIEL/$name.dec.log" || return 1
    printf '%s %s %s %s\n' "$name" "$w" "$h" "$n" >> "$ZIEL/liste.txt"
    return 0
}

rm -f "$ZIEL/liste.txt"

mach i_klein   64  64  3 "testsrc2=size=64x64:rate=5"     -g 1 -qp 26
mach i_sd     176 144  3 "testsrc2=size=176x144:rate=5"   -g 1 -qp 26
mach i_glatt  128  96  2 "color=c=gray:size=128x96:rate=5" -g 1 -qp 20
mach i_scharf 160 128  2 "testsrc=size=160x128:rate=5"    -g 1 -qp 18

mach p_klein   64  64  6 "testsrc2=size=64x64:rate=5"     -g 100 -qp 26
mach p_sd     176 144  8 "testsrc2=size=176x144:rate=5"   -g 100 -qp 26
mach p_bewegt 176 144  8 "testsrc2=size=352x288:rate=5" -g 100 -qp 24 \
     -vf "crop=176:144:'min(88,n*8)':'min(72,n*4)'"
mach p_skip   128  96  6 "color=c=navy:size=128x96:rate=5" -g 100 -qp 26

mach cif      352 288 10 "testsrc2=size=352x288:rate=10" -g 100 -qp 26

mach vga      640 480  6 "testsrc2=size=640x480:rate=10" -g 100 -qp 26
mach hd720   1280 720  4 "testsrc2=size=1280x720:rate=10" -g 100 -qp 26

mach slices   176 144  3 "testsrc2=size=176x144:rate=5" -g 1 -qp 26 \
     -x264-params slices=4

echo "PRUEFMATERIAL:"
while read -r name w h n; do
    s264=$(stat -c%s "$ZIEL/$name.264" 2>/dev/null || echo 0)
    syuv=$(stat -c%s "$ZIEL/$name.yuv" 2>/dev/null || echo 0)
    soll=$(( w * h * 3 / 2 * n ))
    printf '  %-10s %3dx%-3d %d Bilder  %6d Oktette .264  %8d YUV (soll %d)\n' \
        "$name" "$w" "$h" "$n" "$s264" "$syuv" "$soll"
done < "$ZIEL/liste.txt"
