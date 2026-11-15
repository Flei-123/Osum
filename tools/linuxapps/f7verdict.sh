#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:?stage output dir}
NAV_COLOR=0000c8
URL_COLOR=00c800
text=$(python3 -I tools/linuxapps/f7check.py "$OUT/ser.clean" 2>&1)
nav=$(python3 -I tools/linuxapps/f7pix.py "$OUT/nav.ppm" "$NAV_COLOR" 2>&1)
url=$(python3 -I tools/linuxapps/f7pix.py "$OUT/url.ppm" "$URL_COLOR" 2>&1)
edge=$(python3 -I tools/linuxapps/f7edge.py "$OUT/nav.ppm" "$OUT/ser.clean" 2>&1)
popedge=""
if [ "${FX7_POPUP:-1}" != 0 ]; then popedge=$(python3 -I tools/linuxapps/f7popupedge.py "$OUT/popup.ppm" 2>&1); fi
state=green
[ "${text%% *}" = green ] && [ "${nav%% *}" = green ] && [ "${url%% *}" = green ] && [ "${edge%% *}" = green ] && { [ -z "$popedge" ] || [ "${popedge%% *}" = green ]; } || state=red
echo "$state $text; nav pixels ${nav}; url pixels ${url}; edge ${edge}; popup edge ${popedge:-skipped}"
[ "$state" = green ]
