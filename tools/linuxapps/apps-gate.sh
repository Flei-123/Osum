#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
WD=${1:?workdir from prep-apps.sh}
OUT=${2:-$(mktemp -d)}
. tools/lib/tmpdir.sh
osum_tmp_guard "${2:-}" "$OUT"
EXPECT=${EXPECT:-tools/linuxapps/apps-expected-red.txt}
mkdir -p "$OUT"
SPEC=${SPEC:-$WD/run/spec.txt} BLOCKS=${BLOCKS:-2400000} INODES=${INODES:-20000} TMO=${TMO:-1500} DONE=FX-END \
    bash tools/linuxapps/run.sh "$WD" tools/linuxapps/guest-apps.sh "$OUT/run" > "$OUT/run.log" 2>&1
pass=0
fail=0
while read -r name verdict _; do
    want=ok
    grep -qx "$name" "$EXPECT" && want=red
    if [ "$verdict" = "$want" ]; then pass=$((pass + 1)); printf '  OK    %s is %s\n' "$name" "$verdict"
    else fail=$((fail + 1)); printf '  FAIL  %s is %s, expected %s\n' "$name" "$verdict" "$want"; fi
done < <(grep -a '^APPS-RESULT ' "$OUT/run/ser.clean" | awk '{print $2, $3}')
total=$((pass + fail))
[ "$total" -ge 60 ] || { fail=$((fail + 1)); echo "  FAIL  only $total results, guest script incomplete"; }
echo "LINUXAPPS-APPS-GATE: $pass matched, $fail differ"
[ "$fail" -eq 0 ]
