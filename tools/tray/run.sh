#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/tray/run.sh -- tray model (lib/fui/tray.fi), tray texts (lib/fui/trayaudio.fi) and the audio hub
# (audio.hub from Firn's lib) on the build host. No QEMU, seconds.
#   bash tools/tray/run.sh
# 0) kernel-profile compile check  1) tools/tray/hub_host.fi (= Firn's tests/2790)  2) tools/tray/host.fi  3) tools/tray/slots_host.fi
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/firnenv.sh
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
rc=0
if FIRNLIB="$PWD/lib" "$FIRNC" --profile=kernel -c tools/tray/kcheck.fi -o "$T/kcheck.o" > "$T/kcheck.build" 2>&1; then
    echo "OK    fui.tray compiles in profile kernel"
else
    echo "FAIL  fui.tray does not compile in profile kernel"; grep -v '^warning' "$T/kcheck.build" | head -20; rc=1
fi
for p in hub_host host slots_host line_host; do
    FIRNLIB="$PWD/lib" "$FIRNC" --profile=app tools/tray/$p.fi -o "$T/$p" > "$T/$p.build" 2>&1 \
        || { echo "FAIL  build $p"; grep -v '^warning' "$T/$p.build" | head -20; rc=1; continue; }
    "$T/$p" > "$T/$p.out"; prc=$?
    grep '^FAIL' "$T/$p.out" | head -20
    echo "$p: $(tail -1 "$T/$p.out") (exit $prc)"
    [ "$prc" = 0 ] || rc=1
done
exit $rc
