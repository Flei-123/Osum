#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/fps/run.sh -- W-E (17.10.2026): frame cadence (60 fps pacing) and the debug FPS overlay (settings key debug.fps).
#
#   /root/jarvis/bin/heavy bash tools/fps/run.sh [outdir] [cases]   (one boot per case, ~3 min each; cases default: all four, one after the other)
#
# Cases (tools/design/audit.sh, drehbuch tools/fps/fps.txt):
#   paced   default kernel: an active stretch is held to the 16.667 ms slot (kgui lj_wait + wm lj_may_compose)
#   nolatfix kernel word `nolatfix` = the old 10-20 ms tick rounds (counter-proof: cadence must NOT be 60 fps)
#   fpson   paced + /etc/mouse.conf fps=true: green text top-left of the screenshot
#   ovon / ovoff / ovplain  FPS-OV: Ctrl+Alt+F + idle/sweep/drag on VMSVGA, same without the key, same on plain VGA (tools/fps/fpsov.txt)
#   fpsoff  paced, switch off: no overlay pixels top-left (counter-proof of the switch)
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT" "$OUT"-*' EXIT; fi
mkdir -p "$OUT"
run_case() { # name, extra kernel words, [audit.sh args...]
    # r1039 (17.10.2026): the old alltag build ran `kbd=no ... usb hidgen`: the QEMU monitor mouse (drive.py fahre/wische/ziehe) never
    # reached a USB HID, so the pointer phases were never fed. tools/design/audit.sh (PS/2 mouse, like tools/latency) plays the same
    # drehbuch with `wmshell wmdauer` = the shipping desktop loop (kgui wait_wm).
    local n=$1 words=$2; shift 2
    export DESIGNBUILD="$OUT-build-$n"
    bash tools/design/audit.sh "$OUT/$n" accel=kvm uitrace=yes extra="phases wmshell wmdauer $words" halt="${HALT:-700}" \
        drehbuch="${DREH:-$(pwd)/tools/fps/fps.txt}" "$@" > "$OUT/$n.log" 2>&1
    rm -rf "$DESIGNBUILD"
}
CASES=${2:-paced nolatfix fpson fpsoff ovon ovoff ovplain}
for c in $CASES; do
    case $c in
        paced)  run_case paced "" ;;
        nolatfix) run_case nolatfix "nolatfix" ;;
        fpson)  run_case fpson "" fps=on ;;
        fpsoff) run_case fpsoff "" ;;
        # FPS-OV: Ctrl+Alt+F in the script (VMSVGA card: the present clock has a driver to read), the same script without the key
        # (counter-proof), and the plain VGA card (present clock "n/a")
        ovon)   DREH=$(pwd)/tools/fps/fpsov.txt run_case ovon "" gpu=vmsvga ;;
        ovoff)  grep -v ctrl-alt-f tools/fps/fpsov.txt > "$OUT-ovoff.txt"; DREH="$OUT-ovoff.txt" run_case ovoff "" gpu=vmsvga ;;
        ovplain) DREH=$(pwd)/tools/fps/fpsov.txt run_case ovplain "" ;;
    esac
done
[ "${NOJUDGE:-}" = 1 ] || python3 -I tools/fps/judge.py "$OUT"
