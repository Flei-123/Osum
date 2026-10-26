#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/../lib/marke-env.sh"
# SPDX-License-Identifier: GPL-2.0-only
# tools/odbloop/run.sh -- NIGHTLY GATE WRAPPER for tools/odb/loop.sh (ODB round trip on a FULL image, QEMU).
#
#   bash tools/odbloop/run.sh                       build an own ODB=1 image (~9 min), 3 rounds, image deleted afterwards
#   ODBLOOP_IMAGE=<orientos-usb.img> bash ...       skip the build, use this ODB=1 image (copied by loop.sh, never modified)
#   ODBLOOP_ROUNDS=5 ODBLOOP_KEEP=<dir> ...         more rounds / keep shots + result table
#
# loop.sh needs an image path; this wrapper makes it a self-contained gate. Run it through /root/jarvis/bin/heavy
# (full desktop boot). Pass = loop.sh exit 0, i.e. every check of every round passed (agent auth, exec, push/pull,
# ps, shot, login, terminal typing read back, shot compare). The loop has its own per-step checks and fails on any.
set -uo pipefail
cd "$(dirname "$0")/../.."
ABB=${ABB:-/root/abbilder}
ROUNDS=${ODBLOOP_ROUNDS:-3}
TOKEN=${ODB_TOKEN_FILE:-$ABB/odb.token}
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
fin() { echo; echo "ODBLOOP: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }

[ -s "$TOKEN" ] || bash tools/vbox/run.sh odb-token >/dev/null 2>&1
[ -s "$TOKEN" ] || { echo "odbloop: no token file $TOKEN"; exit 2; }
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1

IMG=${ODBLOOP_IMAGE:-}
if [ -z "$IMG" ]; then
    # same environment as `tools/vbox/run.sh build` (personal image, login justin/startkennwort)
    ( export ODB=1 PARTTAB=mbr FS_BLOCKS=122880 JARVIS_DEVICE_KEY=$ABB/vm-device.key JARVIS_CONF=$ABB/justin-permissions.conf \
             IMAGE_ID="odbloop-$$" ODB_TOKEN_FILE=$TOKEN
      bash tools/usbimg/build.sh "$D/img" > "$D/build.log" 2>&1 ) || { tail -15 "$D/build.log"; bad "ODB=1 image build"; fin; }
    IMG=$D/img/"${MARKE_DATEI}-usb".img
    [ -s "$IMG" ] && ok "ODB=1 image built ($(du -m "$IMG" | cut -f1) MiB)" || { bad "no image after build"; fin; }
fi

bash tools/odb/loop.sh --image "$IMG" --rounds "$ROUNDS" --token-file "$TOKEN" ${ODBLOOP_KEEP:+--keep "$ODBLOOP_KEEP"} 2>&1 | tee "$D/loop.log"
rc=${PIPESTATUS[0]}
[ "$rc" -eq 0 ] && ok "loop.sh: $ROUNDS rounds, every check passed" || bad "loop.sh rc=$rc"
fin
