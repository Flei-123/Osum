#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
WD=${1:?workdir from prep-firefox.sh}
OUT=${2:-$(mktemp -d)}
. tools/lib/tmpdir.sh
osum_tmp_guard "${2:-}" "$OUT"
EXPECT=${EXPECT:-tools/linuxapps/expected-red.txt}
mkdir -p "$OUT"
declare -A GUEST=( [F3]=tools/linuxapps/guest-fx1-version.sh [F4]=tools/linuxapps/guest-fx2-shot.sh [F5]=tools/linuxapps/guest-fx3-boot.sh [F6]=tools/linuxapps/guest-fx11-https-runs.sh )
declare -A MARK=( [F3]="FX1 rc=0" [F4]="FX2 png ok" [F5]="wayd: window c=" )
pass=0
fail=0
KERNEL_ARG=()
[ -n "${KERNEL:-}" ] && KERNEL_ARG=(env "KERNEL=$KERNEL")
HTTPS_ARGS=("KARGS=osum vfs nokbd nosched noproc nofs fremdtrace gfx nic nip=10.0.2.15/24 ngw=10.0.2.2" "QEMU_EXTRA=-netdev user,id=n0 -device e1000,netdev=n0")
for stage in ${STAGES:-F3 F4 F5 F6 F7}; do
    want=$(awk -v s="$stage" '$1==s{print $2}' "$EXPECT")
    got=red
    first="no run: window stage needs a Wayland-capable run (F5 not implemented)"
    if [ -n "${GUEST[$stage]:-}" ]; then
        STAGE_ENV=()
        [ "$stage" = F6 ] && STAGE_ENV=(env "${HTTPS_ARGS[@]}")
        [ "$stage" = F5 ] && STAGE_ENV=(env GUI=1 "EXTRA=/etc/fx3.sh=$PWD/tools/linuxapps/guest-fx3-window.sh@755" "KARGS=gfx disp wm wmdauer wmshell osum vfs bus fremdtrace script=sh /etc/fx.sh;exit")
        BLOCKS=${BLOCKS:-1000000} TMO=${TMO:-900} "${STAGE_ENV[@]}" bash tools/linuxapps/run.sh "$WD" "${GUEST[$stage]}" "$OUT/$stage" > "$OUT/$stage.log" 2>&1
        if [ "$stage" = F5 ]; then verdict=$(python3 -I tools/linuxapps/f5check.py "$OUT/$stage/ser.clean" 2>&1); else verdict=""; fi
        if [ "$stage" = F6 ]; then verdict=$(bash tools/linuxapps/f6check.sh "$OUT/$stage/ser.clean" 2>&1); fi
        if [[ "$stage" = F5 || "$stage" = F6 ]] && [ "${verdict%% *}" = green ]; then got=green; first=""
        elif [[ "$stage" = F5 || "$stage" = F6 ]]; then first="$verdict"
        elif grep -qaF -- "${MARK[$stage]}" "$OUT/$stage/ser.clean" 2>/dev/null; then got=green; first=""; else
            first=$(grep -a -m1 -E '^sys: (ERR|ENOSYS)|Error|error|fault' "$OUT/$stage/ser.clean" 2>/dev/null)
            [ -n "$first" ] || first="no marker and no error line"
        fi
    fi
    if [ "$stage" = F7 ]; then
        BLOCKS=${BLOCKS:-1000000} TMO=${TMO:-1500} FX7_WAIT=${FX7_WAIT:-240} "${KERNEL_ARG[@]}" bash tools/linuxapps/fx7.sh "$WD" "$OUT/F7" > "$OUT/F7.log" 2>&1
        verdict=$(python3 -I tools/linuxapps/f7check.py "$OUT/F7/ser.clean" 2>&1)
        if [ "${verdict%% *}" = green ]; then got=green; first=""; else first="$verdict"; fi
    fi
    if [ "$got" = "${want:-red}" ]; then pass=$((pass+1)); printf '  OK    %s is %s (expected %s)%s\n' "$stage" "$got" "${want:-red}" "${first:+; first failure: $first}"
    else fail=$((fail+1)); printf '  FAIL  %s is %s, expected %s%s\n' "$stage" "$got" "${want:-red}" "${first:+; first failure: $first}"; fi
done
echo "LINUXAPPS-GATE: $pass matched, $fail differ"
[ "$fail" -eq 0 ]
