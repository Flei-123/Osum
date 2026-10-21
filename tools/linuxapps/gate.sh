#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
WD=${1:?workdir from prep-firefox.sh}
OUT=${2:-$(mktemp -d)}
EXPECT=${EXPECT:-tools/linuxapps/expected-red.txt}
mkdir -p "$OUT"
declare -A GUEST=( [F3]=tools/linuxapps/guest-fx1-version.sh [F4]=tools/linuxapps/guest-fx2-shot.sh )
declare -A MARK=( [F3]="FX1 rc=0" [F4]="FX2 rc=0" )
pass=0
fail=0
KERNEL_ARG=()
[ -n "${KERNEL:-}" ] && KERNEL_ARG=(env "KERNEL=$KERNEL")
for stage in F3 F4 F5; do
    want=$(awk -v s="$stage" '$1==s{print $2}' "$EXPECT")
    got=red
    first="no run: window stage needs a Wayland-capable run (F5 not implemented)"
    if [ -n "${GUEST[$stage]:-}" ]; then
        BLOCKS=${BLOCKS:-1000000} TMO=${TMO:-900} bash tools/linuxapps/run.sh "$WD" "${GUEST[$stage]}" "$OUT/$stage" > "$OUT/$stage.log" 2>&1
        if grep -qaF -- "${MARK[$stage]}" "$OUT/$stage/ser.clean" 2>/dev/null; then got=green; first=""; else
            first=$(grep -a -m1 -E '^sys: (ERR|ENOSYS)|Error|error|fault' "$OUT/$stage/ser.clean" 2>/dev/null)
            [ -n "$first" ] || first="no marker and no error line"
        fi
    fi
    if [ "$got" = "${want:-red}" ]; then pass=$((pass+1)); printf '  OK    %s is %s (expected %s)%s\n' "$stage" "$got" "${want:-red}" "${first:+; first failure: $first}"
    else fail=$((fail+1)); printf '  FAIL  %s is %s, expected %s%s\n' "$stage" "$got" "${want:-red}" "${first:+; first failure: $first}"; fi
done
echo "LINUXAPPS-GATE: $pass matched, $fail differ"
[ "$fail" -eq 0 ]
