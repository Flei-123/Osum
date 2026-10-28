#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
EH_MKFS_EXTRA="/proc/" bash tools/design/eh6.sh "$TMPD/run" res=1280x800 accel=kvm tafel=nein moreprogs=term "extra=vfs lang=en termdump pixelguard=all" drehbuch=tools/procread/script.txt > "$TMPD/run.log" 2>&1
S="$TMPD/run/serial.txt"
if [ -n "${PROCREAD_KEEP:-}" ]; then
    mkdir -p "$PROCREAD_KEEP"; cp "$S" "$TMPD/run.log" "$PROCREAD_KEEP/"
    for n in "$TMPD"/run/*.ppm; do [ -s "$n" ] && python3 tools/design/ppm2png.py "$n" "$PROCREAD_KEEP/$(basename "$n" .ppm).png" > /dev/null 2>&1; done
fi
tail -2 "$TMPD/run.log"
python3 tools/procread/cells.py "$S"; rc=$?
if command -v tesseract > /dev/null; then
    python3 tools/procread/pic.py "$TMPD"/run/*.ppm || rc=1
fi
echo "PROCREAD: exit $rc"
exit $rc
