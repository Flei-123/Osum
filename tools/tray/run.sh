#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/tray/run.sh -- tray model (lib/fui/tray.fi), tray texts (lib/fui/trayaudio.fi) and the audio hub mirror
# (lib/audio/hub.fi) on the build host. No QEMU, seconds.
#   bash tools/tray/run.sh
# 1) lib/audio/hub.fi is byte-identical to Firn's (when /root/firn is there)  2) tools/tray/hub_host.fi (= Firn's tests/2790) 3) tools/tray/host.fi
set -uo pipefail
cd "$(dirname "$0")/../.."
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || { echo "fetch-firnc.sh failed"; exit 1; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
rc=0
if [ -f /root/firn/lib/audio/hub.fi ]; then
    if cmp -s lib/audio/hub.fi /root/firn/lib/audio/hub.fi; then echo "OK    hub.fi mirror identical to Firn"; else echo "FAIL  hub.fi differs from Firn's copy"; rc=1; fi
fi
for p in hub_host host; do
    FIRNLIB="$PWD/lib" vendor/firn/bin/firnc --profile=app tools/tray/$p.fi -o "$T/$p" > "$T/$p.build" 2>&1 \
        || { echo "FAIL  build $p"; grep -v '^warning' "$T/$p.build" | head -20; rc=1; continue; }
    "$T/$p" > "$T/$p.out"; prc=$?
    grep '^FAIL' "$T/$p.out" | head -20
    echo "$p: $(tail -1 "$T/$p.out") (exit $prc)"
    [ "$prc" = 0 ] || rc=1
done
exit $rc
