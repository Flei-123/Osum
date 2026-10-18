#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/vbox/run.sh -- SERVER half of the OrientOS VirtualBox dev loop.
#
#   bash tools/vbox/run.sh lock <who>            take /root/abbilder/vm.lock (one test VM at a time)
#   bash tools/vbox/run.sh unlock                release it
#   bash tools/vbox/run.sh lockstatus
#   bash tools/vbox/run.sh build <id> <worktree> build image /root/abbilder/<id>/orientos-usb.img via heavy (~11 min, run it in background!)
#   bash tools/vbox/run.sh publish <id>          xz + publish at https://jarvis.fleitec.com/t-<hex>/o.xz, prints the laptop fetch line
#   bash tools/vbox/run.sh script                publish tools/vbox/vbtest.ps1, prints the laptop install line
#   bash tools/vbox/run.sh pull <dir> <name>...  copy delivered screenshots (remote_deliver) into <dir>
#   bash tools/vbox/run.sh unpublish <hex>|all   remove published folders
#   bash tools/vbox/run.sh stamp <label>         append a timing mark to /root/abbilder/vbox-round.log
#   bash tools/vbox/run.sh clean <id>            delete the image dir /root/abbilder/<id> (rebuildable)
#
# The laptop half is tools/vbox/vbtest.ps1 (driven by the worker through remote_shell). See README.md.
set -euo pipefail
ABB=/root/abbilder
PUB=/root/jarvis/public
LOCK=$ABB/vm.lock
URLBASE=https://jarvis.fleitec.com
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK_STALE_S=10800

cmd="${1:-help}"; shift || true
case "$cmd" in
  lock)
    who="${1:?usage: lock <who>}"
    if [ -f "$LOCK" ]; then
      age=$(( $(date +%s) - $(stat -c %Y "$LOCK") ))
      if [ "$age" -lt "$LOCK_STALE_S" ]; then echo "LOCKED by: $(cat "$LOCK") (age ${age}s)"; exit 2; fi
      echo "stale lock ($(cat "$LOCK"), ${age}s) taken over"
    fi
    echo "$who $(date -Is)" > "$LOCK"; echo "OK: lock held by $who" ;;
  unlock) rm -f "$LOCK"; echo "OK: lock released" ;;
  lockstatus) if [ -f "$LOCK" ]; then echo "LOCKED: $(cat "$LOCK")"; else echo "free"; fi ;;
  build)
    id="${1:?usage: build <id> <worktree>}"; wt="${2:?worktree}"
    cd "$wt"
    export PARTTAB=mbr FS_BLOCKS=122880 JARVIS_DEVICE_KEY=$ABB/vm-device.key JARVIS_CONF=$ABB/justin-permissions.conf IMAGE_ID="$id"
    date +%s > "$ABB/$id.t0"
    /root/jarvis/bin/heavy bash tools/usbimg/build.sh "$ABB/$id"
    date +%s > "$ABB/$id.t1"
    echo "OK: built $ABB/$id/orientos-usb.img in $(( $(cat "$ABB/$id.t1") - $(cat "$ABB/$id.t0") ))s (queue wait included)" ;;
  publish)
    id="${1:?usage: publish <id>}"; img="$ABB/$id/orientos-usb.img"
    [ -f "$img" ] || { echo "no $img"; exit 1; }
    raw=$(sha256sum "$img" | cut -c1-64); hex=${raw:0:12}
    dir="$PUB/t-$hex"; mkdir -p "$dir"
    s=$(date +%s); xz -T4 -3 -c "$img" > "$dir/o.xz"; e=$(date +%s)
    xzsha=$(sha256sum "$dir/o.xz" | cut -c1-64); size=$(stat -c %s "$dir/o.xz")
    echo "$raw" > "$ABB/$id.sha"
    echo "INFO: xz $((e-s))s, $size bytes"
    echo "URL=$URLBASE/t-$hex/o.xz"; echo "SHA_XZ=$xzsha"; echo "SHA_RAW=$raw"
    echo "LAPTOP: powershell -NoProfile -ExecutionPolicy Bypass -File C:\\Users\\justi\\vbl\\vbtest.ps1 fetch $URLBASE/t-$hex/o.xz $xzsha $raw" ;;
  script)
    mkdir -p "$PUB/t-vbl"; cp "$HERE/vbtest.ps1" "$PUB/t-vbl/vbtest.ps1"
    echo "LAPTOP: New-Item -ItemType Directory -Force C:\\Users\\justi\\vbl | Out-Null; curl.exe -sS -f -o C:\\Users\\justi\\vbl\\vbtest.ps1 $URLBASE/t-vbl/vbtest.ps1" ;;
  pull)
    dest="${1:?usage: pull <dir> <name>...}"; shift; mkdir -p "$dest"
    for n in "$@"; do
      f=$(ls -t /root/jarvis/downloads/*/*/"$n" 2>/dev/null | head -1 || true)
      if [ -n "$f" ]; then cp "$f" "$dest/$n"; echo "OK: $n"; else echo "MISSING: $n"; fi
    done ;;
  unpublish)
    t="${1:?usage: unpublish <hex>|all}"
    if [ "$t" = all ]; then rm -rf "$PUB"/t-vbl "$PUB"/t-vbpipe; for d in "$PUB"/t-[0-9a-f]*; do [ -f "$d/o.xz" ] && rm -rf "$d"; done
    else rm -rf "${PUB:?}/t-$t"; fi
    echo "OK: unpublished $t" ;;
  stamp) echo "$(date +%s) $(date -Is) ${*:-mark}" >> "$ABB/vbox-round.log"; tail -1 "$ABB/vbox-round.log" ;;
  clean) id="${1:?usage: clean <id>}"; rm -rf "${ABB:?}/$id" "$ABB/$id".{sha,t0,t1,build.log,sperre,sperre.wer}; echo "OK: cleaned $id" ;;
  *) sed -n 2,16p "$0" ;;
esac
