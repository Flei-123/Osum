#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:?stage output dir}
NAV_COLOR=0000c8
URL_COLOR=00c800
text=$(python3 -I tools/linuxapps/f7check.py "$OUT/ser.clean" 2>&1)
nav=$(python3 -I tools/linuxapps/f7pix.py "$OUT/nav.ppm" "$NAV_COLOR" 2>&1)
url=$(python3 -I tools/linuxapps/f7pix.py "$OUT/url.ppm" "$URL_COLOR" 2>&1)
state=green
[ "${text%% *}" = green ] && [ "${nav%% *}" = green ] && [ "${url%% *}" = green ] || state=red
echo "$state $text; nav pixels ${nav}; url pixels ${url}"
[ "$state" = green ]
