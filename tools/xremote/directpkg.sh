#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:?usage: directpkg.sh <out-dir>}
BUND=${OSUM_BUND:-/root/.secrets/osum-ota-bund.json}
PASS_FILE=${OSUM_SIGN_PASS_FILE:-/root/.secrets/osum-ota-pass.txt}
TOOLS=${XR_TOOLS:-/root/jarvis/data/orientos-xremote}
HOSTBIN=${XR_HOST:-$TOOLS/v2/freeviewer-host}
LIBS=${XR_LIBS_DIR:-/root/fxhp/fx-root}
OPK=$(python3 tools/lib/opkpfad.py)
for f in "$HOSTBIN" "$LIBS/lib/ld-musl-x86_64.so.1" "$LIBS/usr/lib/libgcc_s.so.1" "$OPK" "$BUND"; do
    [ -e "$f" ] || { echo "directpkg: $f is missing"; exit 1; }
done
if [ -z "${OSUM_SIGN_PASS:-}" ] && [ -s "$PASS_FILE" ]; then
    OSUM_SIGN_PASS=$(cat "$PASS_FILE")
    export OSUM_SIGN_PASS
fi
mkdir -p "$OUT"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bau"
cp pakete/xremote/INFO pakete/xremote/rezept "$T/"
cp "$HOSTBIN" "$T/bau/freeviewer-host"
cp "$LIBS/lib/ld-musl-x86_64.so.1" "$T/bau/ld-musl-x86_64.so.1"
cp "$LIBS/usr/lib/libgcc_s.so.1" "$T/bau/libgcc_s.so.1"
python3 tools/k15/icon.py pakete/xremote/symbol.txt "$T/bau/symbol" > /dev/null
(cd "$T" && python3 "$OPK" bauen rezept -o "$OUT/xremote.opk")
python3 tools/ota/keyring.py "$BUND" signieren "$OUT/xremote.opk" -o "$OUT/xremote.opk.sig"
ls -l "$OUT/xremote.opk" "$OUT/xremote.opk.sig"
echo "next: put both files on the HP in one folder, then on the HP terminal: /bin/opk install <folder>/xremote.opk"
