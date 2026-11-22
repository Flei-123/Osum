#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:?usage: stage.sh <root-dir>}
XR_DIR=${XR_DIR:-/root/jarvis/data/orientos-xremote/system}
OPK=${OPK:-$(python3 tools/lib/opkpfad.py)}
for f in freeviewer-host libgcc_s.so.1; do
    [ -s "$XR_DIR/$f" ] || { echo "xremote stage: $XR_DIR/$f is missing" >&2; exit 1; }
done
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
PKG="$WORK/pkg"
rm -rf "$OUT"
mkdir -p "$PKG/bau" "$OUT"
cp pakete/xremote/INFO pakete/xremote/INITTAB pakete/xremote/DEFAULTS pakete/xremote/rezept pakete/xremote/start "$PKG/"
if [ -n "${XR_VERSION:-}" ]; then
    sed -i "s/^version=.*/version=$XR_VERSION/" "$PKG/rezept" "$PKG/INFO"
fi
python3 tools/k15/mksymbol.py pakete/xremote "$PKG/bau/symbol" > /dev/null
cp "$XR_DIR/freeviewer-host" "$XR_DIR/libgcc_s.so.1" "$PKG/bau/"
bash tools/xremote/build-daemon.sh "$PKG/bau/xremoted"
bash tools/xremote/build-daemon.sh "$PKG/bau/xremote" kernel/user/xrcli.fi
cp assets/musl/ld-musl-x86_64.so.1 "$PKG/bau/ld-musl-x86_64.so.1"
(cd "$PKG" && python3 "$OPK" bauen rezept -o "$WORK/xremote.opk") > "$WORK/build.log" 2>&1 || { cat "$WORK/build.log" >&2; exit 1; }
python3 "$OPK" installieren --wurzel "$OUT" "$WORK/xremote.opk" > "$WORK/install.log" 2>&1 || { cat "$WORK/install.log" >&2; exit 1; }
python3 -I tools/xremote/guestplan.py "$OUT"
[ -z "${XR_OPK_OUT:-}" ] || cp "$WORK/xremote.opk" "$XR_OPK_OUT"
rm -rf "$OUT/users" "$OUT/system/device.key" "$OUT/system/device.pub" "$OUT/system/machine-id"
echo "xremote stage: $(find "$OUT/apps/xremote.osp" -type f | wc -l) files in $OUT/apps/xremote.osp, package record under $OUT/store"
