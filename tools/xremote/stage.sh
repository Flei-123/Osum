#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:?usage: stage.sh <root-dir>}
XR_DIR=${XR_DIR:-/root/jarvis/data/orientos-xremote/system}
BUNDLE="$OUT/apps/xremote.osp"
for f in freeviewer-host libgcc_s.so.1; do
    [ -s "$XR_DIR/$f" ] || { echo "xremote stage: $XR_DIR/$f is missing" >&2; exit 1; }
done
mkdir -p "$BUNDLE/bin" "$BUNDLE/lib"
cp pakete/xremote/INFO "$BUNDLE/INFO"
cp pakete/xremote/INITTAB "$BUNDLE/INITTAB"
python3 tools/k15/mksymbol.py pakete/xremote "$BUNDLE/symbol" > /dev/null
printf 'shipped with the OrientOS image\n' > "$BUNDLE/SYSTEM"
cp "$XR_DIR/freeviewer-host" "$BUNDLE/bin/freeviewer-host"
bash tools/xremote/build-daemon.sh "$BUNDLE/bin/xremoted"
cp "$XR_DIR/libgcc_s.so.1" "$BUNDLE/lib/libgcc_s.so.1"
cp assets/musl/ld-musl-x86_64.so.1 "$BUNDLE/lib/ld-musl-x86_64.so.1"
chmod 755 "$BUNDLE/bin/xremoted" "$BUNDLE/bin/freeviewer-host" "$BUNDLE/lib/ld-musl-x86_64.so.1"
echo "xremote stage: $(find "$BUNDLE" -type f | wc -l) files in $BUNDLE"
