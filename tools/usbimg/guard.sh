#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/usbimg/guard.sh -- ROUND LIVE: THE WATCHMAN OF THE DOWNLOAD FOLDER.
#
#   bash tools/usbimg/guard.sh [download-dir] [private-dir]
#
# release.sh is the one way INTO /srv/store/abbilder. But the folder is a
# folder: on 25.09.2026, half an hour after the public live image went
# up, a personal test stick (accounts root + justin) was copied there by
# hand by another round. This script runs on every change of the folder
# (systemd path unit `osum-abbilder-guard.path`) and every ten minutes:
# each stick image in it is unpacked and checked with pubcheck.py; one
# that is not fit is MOVED (not deleted) to the private folder
# (default /root/abbilder, served by nothing), and orientos-usb-neuestes
# is pointed back at the newest image that is fit.
#
# Checked images are remembered by their sha256 in $GUARD_OK (outside the
# served folder), so an
# unchanged folder costs one sha256 per file.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
DL=${1:-/srv/store/abbilder}
PRIV=${2:-/root/abbilder}
OKF=${GUARD_OK:-/var/lib/osum-abbilder-guard.ok}
LOG=${GUARD_LOG:-/var/log/osum-abbilder-guard.log}
mkdir -p "$PRIV"
touch "$OKF"
say() { printf '%s %s\n' "$(date -Is)" "$*" >> "$LOG"; }

for f in "$DL"/*.img.xz "$DL"/*.img; do
    [ -f "$f" ] && [ ! -L "$f" ] || continue
    case "$f" in *.part) continue ;; esac
    sum=$(sha256sum < "$f" | cut -c1-64)
    grep -q "^$sum " "$OKF" && continue
    tmp=$(mktemp /tmp/guard.XXXXXX.img)
    case "$f" in
        *.xz) xz -dc "$f" > "$tmp" 2>/dev/null ;;
        *)    cp -f "$f" "$tmp" ;;
    esac
    if python3 "$HERE/pubcheck.py" "$tmp" > "$tmp.txt" 2>&1; then
        echo "$sum $(basename "$f")" >> "$OKF"
        say "fit: $(basename "$f")"
    else
        mv -f "$f" "$PRIV/" && [ -f "$f.sha256" ] && mv -f "$f.sha256" "$PRIV/"
        say "NOT FIT, moved to $PRIV: $(basename "$f") -- $(grep -o 'NOT FIT -- .*' "$tmp.txt" | head -3 | tr '\n' ';')"
    fi
    rm -f "$tmp" "$tmp.txt"
done

# The "newest" link must point at something that is there and fit.
ziel=$(readlink "$DL/orientos-usb-neuestes.img.xz" 2>/dev/null || true)
if [ -z "$ziel" ] || [ ! -f "$DL/$ziel" ]; then
    neu=$(ls -t "$DL"/orientos-usb-*-live.img.xz 2>/dev/null | head -1)
    if [ -n "$neu" ]; then
        ln -sfn "$(basename "$neu")" "$DL/orientos-usb-neuestes.img.xz"
        ln -sfn "$(basename "$neu").sha256" "$DL/orientos-usb-neuestes.img.xz.sha256"
        say "neuestes -> $(basename "$neu")"
    fi
fi
exit 0
