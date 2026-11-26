#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:?usage: videos.sh <out-dir> [width height fps seconds]}
W=${2:-1920}
H=${3:-1080}
FPS=${4:-60}
SECS=${5:-5}
FRAMES=$((FPS * SECS))
FONT=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf
mkdir -p "$OUT"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
. tools/lib/firnenv.sh
"$FIRNC" --profile=app --opt-level=release-fast tools/bootanim/render.fi -o "$T/render" > "$T/build.log" 2>&1 || { grep -v '^warning' "$T/build.log" | head; exit 1; }
python3 tools/bootloader/mklogo.py assets/marke/signet-1024.png "$T/logo" > /dev/null
ffmpeg -v error -y -i assets/ref/sea-wallpaper.jpg -vf "scale=$W:$H:force_original_aspect_ratio=increase:flags=lanczos,crop=$W:$H" -pix_fmt bgr0 -f rawvideo "$T/target"
STYLES="mix ignite sunrise particle reactor"
TITLES=("5 Mix (default): rings over the horizon glow" "1 Ignite: light traces the logo" "2 Sunrise: the logo rises like the sun" "3 Particles: thousands of sparks form the logo" "4 Reactor: one ring per boot phase")
i=0
: > "$T/list.txt"
for s in $STYLES; do
    "$T/render" "$T/logo" "$T/target" "$s" "$W" "$H" "$FRAMES" "$FPS" \
        | ffmpeg -v error -y -f rawvideo -pix_fmt bgr0 -s "${W}x$H" -r "$FPS" -i - -c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p -movflags +faststart "$OUT/bootanim-$s.mp4"
    printf '%s' "${TITLES[$i]}" > "$T/title-$s.txt"
    ffmpeg -v error -y -i "$OUT/bootanim-$s.mp4" -vf "drawtext=fontfile=$FONT:textfile=$T/title-$s.txt:fontcolor=white:fontsize=$((H / 24)):x=(w-text_w)/2:y=h*0.08:alpha='if(lt(t,1.4),1,max(0,1-(t-1.4)/0.5))':shadowcolor=black@0.6:shadowx=2:shadowy=2" \
        -c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p "$T/titled-$s.mp4"
    echo "file '$T/titled-$s.mp4'" >> "$T/list.txt"
    echo "video $s: $(stat -c %s "$OUT/bootanim-$s.mp4") bytes"
    i=$((i + 1))
done
ffmpeg -v error -y -f concat -safe 0 -i "$T/list.txt" -c copy -movflags +faststart "$OUT/bootanim-all.mp4"
echo "video all: $(stat -c %s "$OUT/bootanim-all.mp4") bytes"
