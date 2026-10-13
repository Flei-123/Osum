#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/ota/fvstand.sh -- add the FreeViewer viewer package to an OTA "stand".
#
# A stand is a directory of .opk files (tools/loader/pakete.sh writes one);
# tools/ota/veroeffentlichen.py turns it into a signed feed (INDEX, VERZEICHNIS,
# ed25519 signatures). This script builds pakete/fvviewer and drops
# fvviewer-<N>.opk next to the other packages -- nothing is published here.
#
#   bash tools/ota/fvstand.sh <stand-dir>
#
# Needs kernel/user/fvviewer.fi (fails loudly if the package was not built).
set -uo pipefail
cd "$(dirname "$0")/../.."
STAND=${1:?usage: fvstand.sh <stand-dir>}
[ -d "$STAND" ] || { echo "== $STAND is not a directory"; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
bash pakete/bauen.sh "$T" > "$T/log" 2>&1
OPKF=$(ls "$T"/fvviewer-*.opk 2>/dev/null | head -1)
[ -n "$OPKF" ] || { echo "== fvviewer package not built:"; grep -i fvviewer "$T/log"; exit 1; }
FASSUNG=$(sed -n 's/^fassung=//p' pakete/fvviewer/rezept | head -1)
cp "$OPKF" "$STAND/fvviewer-${FASSUNG%%.*}.opk" && echo "ok: $STAND/fvviewer-${FASSUNG%%.*}.opk"
