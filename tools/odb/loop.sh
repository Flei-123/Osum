#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/odb/loop.sh -- agent round trip (ODB) on a FULL image in QEMU: boot, wait for the agent, then N rounds of
# ping / info / exec / push+pull / ps / shot / login / desktop check / start Terminal / type a command / read it back /
# shot compare / close Terminal -- one persistent session, a time per step (tools/odb/loop.py).
#
#   bash tools/odb/loop.sh --image /root/abbilder/<id>/orientos-usb.img [--rounds 5] [--keep <dir>] [--json <file>]
#                          [--token-file F] [--smp 2] [--mem 1536] [--reboot-between]
#
# The image must be an ODB=1 build (ODB=1 bash tools/vbox/run.sh build <id> <worktree>). It is copied to a private
# temp dir (the guest writes to it) and removed again; --keep <dir> keeps the shots, the COM1 log and the result table.
# Exit code 0 = every check of every round passed. Heavy (boots a full desktop): run through /root/jarvis/bin/heavy.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
IMG=""; ROUNDS=5; KEEP=""; JSON=""; TOKEN=/root/abbilder/odb.token; SMP=2; MEM=1536; LOOPARGS=()
while [ $# -gt 0 ]; do
    case $1 in
        --image) IMG=$2; shift 2 ;;
        --rounds) ROUNDS=$2; shift 2 ;;
        --keep) KEEP=$2; shift 2 ;;
        --json) JSON=$2; shift 2 ;;
        --token-file) TOKEN=$2; shift 2 ;;
        --smp) SMP=$2; shift 2 ;;
        --mem) MEM=$2; shift 2 ;;
        --scale|--quant|--password) LOOPARGS+=("$1" "$2"); shift 2 ;;
        --no-terminal) LOOPARGS+=("$1"); shift ;;
        *) echo "unknown option $1"; sed -n 2,12p "$0"; exit 2 ;;
    esac
done
[ -f "$IMG" ] || { echo "loop: --image <orientos-usb.img of an ODB=1 build> required"; exit 2; }
[ -s "$TOKEN" ] || { echo "loop: token file $TOKEN missing (tools/vbox/run.sh odb-token)"; exit 2; }
command -v qemu-system-x86_64 >/dev/null || { echo "loop: no qemu"; exit 2; }

D=$(mktemp -d)
cleanup() {
    bash "$ROOT/tools/odbc/qemu.sh" stop "$D" >/dev/null 2>&1
    if [ -n "$KEEP" ]; then
        mkdir -p "$KEEP"; cp -r "$D/shots" "$KEEP/" 2>/dev/null; cp "$D/com1.log" "$D/result.txt" "$KEEP/" 2>/dev/null
    fi
    rm -rf "$D"
}
trap cleanup EXIT

cp --reflink=auto "$IMG" "$D/disk.img" || exit 2
bash "$ROOT/tools/odbc/qemu.sh" start "$D/disk.img" "$D" "$SMP" "$MEM" || exit 1
PORT="unix:$D/odb.sock"
T0=$(date +%s.%N)
python3 -I "$ROOT/tools/odbc/odbc.py" --port "$PORT" --token-file "$TOKEN" wait 240 || { echo "FAIL  agent never answered"; tail -5 "$D/com1.log"; exit 1; }
echo "boot to agent: $(echo "$(date +%s.%N) - $T0" | bc) s"
python3 -I "$ROOT/tools/odb/loop.py" --port "$PORT" --token-file "$TOKEN" --rounds "$ROUNDS" --out "$D/shots" \
    ${JSON:+--json "$JSON"} "${LOOPARGS[@]}" 2>&1 | tee "$D/result.txt"
exit "${PIPESTATUS[0]}"
