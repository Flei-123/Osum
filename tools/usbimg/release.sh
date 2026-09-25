#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/usbimg/release.sh -- ROUND LIVE: THE TWO STICKS, AND WHERE EACH GOES.
#
#   bash tools/usbimg/release.sh public     the DOWNLOAD image
#   bash tools/usbimg/release.sh personal   Justin's own test stick
#
# ==================================================================
# WHY THERE ARE TWO, AND WHY THIS IS THE ONLY WAY OUT
# ==================================================================
#
# Until 25.09.2026 there was one build and one place: the stick Justin
# tested on his Dell 9020 was copied by hand to
# store.fleitec.com/abbilder/orientos-usb-neuestes.img.xz -- the public
# download. It carried his account `justin` (with the start password),
# /users/justin/, and would have carried his bridge settings the day
# JARVIS_CONF was set for his machine.
#
#   public    IMAGE_PROFILE=public, PARTTAB=mbr (the variant the 9020 and
#             every other firmware boot). A live system: the generic user
#             `live` signed in automatically, root locked, bridge off,
#             "Install OrientOS" in the menu and the taskbar. Checked with
#             tools/usbimg/pubcheck.py on the FINISHED image -- both the
#             root.img the stick boots (EFI partition) and the copy on
#             partition 2 -- and, unless SKIP_LIVE_TEST=1, run through
#             tools/usbimg/live.sh. Only then is it copied to
#             $STORE_DIR/abbilder (default /srv/store/abbilder, served as
#             https://store.fleitec.com/abbilder/) and
#             orientos-usb-neuestes.img.xz points at it.
#   personal  IMAGE_PROFILE=personal, PARTTAB=mbr: root + justin, the
#             normal sign-in screen, JARVIS_CONF if given (his bridge).
#             Written to $PERSONAL_DIR (default /root/abbilder), which is
#             NOT served by any web server. This script refuses to put a
#             personal image anywhere under $STORE_DIR.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
ZIEL=${1:-}
STORE_DIR=${STORE_DIR:-/srv/store}
PUB_DIR="$STORE_DIR/abbilder"
PERSONAL_DIR=${PERSONAL_DIR:-/root/abbilder}
STAMP=$(date +%Y%m%d)
REV=$(git rev-parse --short=7 HEAD)
[ -z "$(git status --porcelain -- kernel lib tools assets locale 2>/dev/null)" ] || REV="$REV-dirty"
fehler() { printf '== %s\n' "$*" >&2; exit 1; }

case "$ZIEL" in
public)
    [ "${REV%-dirty}" = "$REV" ] || fehler "public images are built from a clean tree only ($REV)"
    BAU=${BAU:-/tmp/osum-release-public}
    rm -rf "$BAU"
    env -u JARVIS_CONF -u PW_JUSTIN -u PW_ROOT IMAGE_PROFILE=public PARTTAB=mbr \
        bash tools/usbimg/build.sh "$BAU" > "$BAU.log" 2>&1 \
        || { tail -20 "$BAU.log" >&2; fehler "build failed"; }
    IMG="$BAU/orientos-usb.img"
    python3 tools/usbimg/pubcheck.py "$IMG" || fehler "pubcheck: the boot root is not fit"
    # And the copy on partition 2, which /bin/install finds on a machine
    # whose controller can read the stick.
    P2=$(python3 -c "
import struct,sys
d=open('$IMG','rb').read(512)
print(struct.unpack('<I', d[446+16+8:446+16+12])[0])")
    dd if="$IMG" of="$BAU/p2.img" bs=512 skip="$P2" status=none
    python3 tools/usbimg/pubcheck.py "$BAU/p2.img" || fehler "pubcheck: partition 2 is not fit"
    if [ -z "${SKIP_LIVE_TEST:-}" ]; then
        BAU="$BAU" SCHNELL=1 bash tools/usbimg/live.sh "$BAU/live" > "$BAU/live.log" 2>&1 \
            || { grep -E 'FAIL|LIVE:' "$BAU/live.log" >&2; fehler "live.sh failed"; }
        grep 'LIVE:' "$BAU/live.log"
    fi
    NAME="orientos-usb-$STAMP-$REV-live.img.xz"
    mkdir -p "$PUB_DIR"
    [ -e "$PUB_DIR/$NAME" ] && fehler "$PUB_DIR/$NAME exists already"
    xz -T0 -9 -c "$IMG" > "$PUB_DIR/$NAME.part" || fehler "xz failed"
    mv "$PUB_DIR/$NAME.part" "$PUB_DIR/$NAME"
    (cd "$PUB_DIR" && sha256sum "$NAME" > "$NAME.sha256")
    ln -sfn "$NAME" "$PUB_DIR/orientos-usb-neuestes.img.xz"
    ln -sfn "$NAME.sha256" "$PUB_DIR/orientos-usb-neuestes.img.xz.sha256"
    echo "public: $PUB_DIR/$NAME ($(stat -c%s "$PUB_DIR/$NAME") octets)"
    echo "        https://store.fleitec.com/abbilder/orientos-usb-neuestes.img.xz -> $NAME"
    ;;
personal)
    case "$(readlink -f "$PERSONAL_DIR")/" in
        "$(readlink -f "$STORE_DIR")"/*) fehler "PERSONAL_DIR lies under $STORE_DIR -- that is public" ;;
    esac
    BAU=${BAU:-/tmp/osum-release-personal}
    rm -rf "$BAU"
    IMAGE_PROFILE=personal PARTTAB=mbr bash tools/usbimg/build.sh "$BAU" > "$BAU.log" 2>&1 \
        || { tail -20 "$BAU.log" >&2; fehler "build failed"; }
    NAME="orientos-usb-$STAMP-$REV-personal.img.xz"
    mkdir -p "$PERSONAL_DIR"
    xz -T0 -9 -c "$BAU/orientos-usb.img" > "$PERSONAL_DIR/$NAME" || fehler "xz failed"
    (cd "$PERSONAL_DIR" && sha256sum "$NAME" > "$NAME.sha256")
    echo "personal: $PERSONAL_DIR/$NAME (not public -- hand it over directly)"
    ;;
*)
    sed -n 3,6p "$0"; exit 2 ;;
esac
