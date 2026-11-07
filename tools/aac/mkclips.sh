#!/usr/bin/env bash
set -euo pipefail
OUT=${1:?output directory missing}
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT"
: > "$OUT/list.txt"
mk() {
    local name=$1 rate=$2 ch=$3 kind=$4; shift 4
    python3 -I "$HERE/synth.py" "$OUT/$name.wav" "$rate" "$ch" "$kind"
    ffmpeg -y -v error -i "$OUT/$name.wav" -c:a aac "$@" -f adts "$OUT/$name.aac"
    ffmpeg -y -v error -i "$OUT/$name.aac" -f s16le -ac "$ch" "$OUT/$name.ref"
    echo "$name $rate $ch" >> "$OUT/list.txt"
}
mk tone_st 44100 2 tone
mk tone_mono 22050 1 tone
mk mix_st 44100 2 mix -b:a 128k
mk mix_ms 48000 2 mix -b:a 96k -aac_ms 1 -aac_is 0
mk mix_tns 32000 2 mix -b:a 64k -aac_tns 1
mk mix_pns 44100 2 mix -b:a 48k -aac_pns 1 -aac_is 1
mk mix_mono8 8000 1 mix -b:a 16k
mk mix_hi 96000 2 mix -b:a 256k
