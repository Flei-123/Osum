#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
WD=${1:?workdir from prep-wine.sh}
OUT=${2:-$(mktemp -d)}
. tools/lib/tmpdir.sh
osum_tmp_guard "${2:-}" "$OUT"
mkdir -p "$OUT"
echo "  start $(date +%T) TMO=${TMO:-1500}"
RUN=$OUT/run
mkdir -p "$RUN"
SOCK="$RUN/mon.sock"
mon() { printf '%s\n' "$1" | socat - "UNIX-CONNECT:$SOCK" > /dev/null 2>&1; }
wait_serial() {
    local pattern=$1 cap=$2 waited=0
    until grep -qa -- "$pattern" "$RUN/ser.txt" 2>/dev/null || [ "$waited" -ge "$cap" ]; do sleep 3; waited=$((waited + 3)); done
}
poll_white() {
    local n=0
    while [ "$n" -lt "${NP_POLLS:-40}" ]; do
        mon "screendump $RUN/window.ppm"; sleep 3
        python3 -I -c "import sys; sys.path.insert(0, 'tools/linuxapps'); import notepad_pix as p; sys.exit(0 if p.white(p.read_ppm('$RUN/window.ppm')) >= p.MIN_WHITE else 1)" 2>/dev/null && return 0
        sleep "${NP_POLLGAP:-5}"; n=$((n + 1))
    done
    return 1
}
(
    wait_serial 'wayd: ready' 900
    sleep 3
    mon "screendump $RUN/baseline.ppm"; sleep 3
    wait_serial 'wayd: window c=' "${NP_WINDOWCAP:-900}"
    sleep "${NP_SETTLE:-10}"
    poll_white
    sleep 5
    for k in h e l l o spc w o r l d shift-1; do mon "sendkey $k"; sleep 1; done
    sleep "${NP_TYPEWAIT:-8}"
    mon "screendump $RUN/typed.ppm"; sleep 3
    mon "sendkey alt-f4"; sleep 4
    mon "sendkey n"; sleep 4
    mon "sendkey ret"
) &
DP=$!
trap 'kill $DP 2>/dev/null' EXIT
for name in $(compgen -v NP_); do printf '%s=%q\n' "$name" "${!name}"; done > "$OUT/np-guest.sh"
cat tools/linuxapps/guest-wine-notepad.sh >> "$OUT/np-guest.sh"
SPEC=${SPEC:-$WD/run/spec.txt} GUI=1 DONE=FX-END BLOCKS=${BLOCKS:-2400000} INODES=${INODES:-20000} TMO=${TMO:-1500} MEM=${MEM:-3072} \
    EXTRA="/etc/wine-notepad.sh=$OUT/np-guest.sh@755" \
    KARGS="gfx disp wm wmdauer wmshell osum vfs bus fremdtrace script=sh /etc/fx.sh;exit" \
    bash tools/linuxapps/run.sh "$WD" tools/linuxapps/guest-wine-notepad-boot.sh "$RUN" > "$OUT/run.log" 2>&1
kill $DP 2>/dev/null; wait $DP 2>/dev/null
ok=1
for f in baseline window typed; do [ -s "$RUN/$f.ppm" ] || { echo "  FAIL  no screenshot $f"; ok=0; }; done
result=$(python3 -I tools/linuxapps/notepad_pix.py "$RUN/baseline.ppm" "$RUN/window.ppm" "$RUN/typed.ppm" 2>&1)
echo "  end $(date +%T)"
echo "  pixel: $result"
if [ "$ok" -eq 1 ] && [ "${result%% *}" = green ]; then echo "LINUXAPPS-WINE-NOTEPAD: green"; exit 0; fi
echo "LINUXAPPS-WINE-NOTEPAD: red"
grep -a '^WINE' "$RUN/ser.clean" 2>/dev/null | tail -10
exit 1
