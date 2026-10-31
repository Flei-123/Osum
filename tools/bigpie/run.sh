#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
BASE_SPEC=${BASE_SPEC:?base spec of an Alpine root (tools/linuxapps/prep-firefox.sh output)}
W=${1:-$(mktemp -d)}
mkdir -p "$W"
cleanup() { [ -n "${KEEP:-}" ] || rm -rf "$W/o" "$W/big" "$W/small" "$W/guest.sh" "$W/spec.txt"; }
trap cleanup EXIT
gcc -O1 -pie -o "$W/big" tools/bigpie/big.c || exit 1
gcc -O1 -pie -o "$W/small" tools/bigpie/small.c || exit 1
L=/usr/lib/x86_64-linux-gnu
{
    cat "$BASE_SPEC"
    echo "/lib64/@755"; echo "/lib/x86_64-linux-gnu/@755"; echo "/opt/@755"; echo "/opt/t/@755"
    echo "/lib64/ld-linux-x86-64.so.2=/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2@755"
    echo "/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2=$L/ld-linux-x86-64.so.2@755"
    echo "/lib/x86_64-linux-gnu/libc.so.6=$L/libc.so.6@755"
    echo "/opt/t/big=$W/big@755"; echo "/opt/t/small=$W/small@755"
} > "$W/spec.txt"
cat > "$W/guest.sh" <<'G'
export LD_LIBRARY_PATH=/lib/x86_64-linux-gnu
/opt/t/small a b
echo "G small rc=$?"
/opt/t/big x
echo "G big rc=$?"
/lib64/ld-linux-x86-64.so.2 /opt/t/small q
echo "G ldso-small rc=$?"
/lib64/ld-linux-x86-64.so.2 /opt/t/big q
echo "G ldso-big rc=$?"
echo FX-END
G
SPEC="$W/spec.txt" TMO=${TMO:-400} bash tools/linuxapps/run.sh "$W" "$W/guest.sh" "$W/o" > "$W/run.log" 2>&1
pass=0; fail=0
chk() { if grep -aqF -- "$2" "$W/o/ser.clean"; then pass=$((pass + 1)); echo "  ok   $1"; else fail=$((fail + 1)); echo "  FAIL $1"; fi; }
chk "small glibc PIE runs via PT_INTERP" "SMALLPIE argc=3"
chk "small exit code 0" "G small rc=0"
chk "15 MB glibc PIE runs via PT_INTERP" "BIGPIE sum=1 dat=16 zer=3 m=5 argc=2"
chk "big exit code 0" "G big rc=0"
chk "ld.so runs small PIE directly" "SMALLPIE argc=2"
chk "ld.so runs big PIE directly" "BIGPIE sum=1 dat=16 zer=3 m=5 argc=2"
chk "no refused exec" "G ldso-big rc=0"
if grep -aq "user fault" "$W/o/ser.clean"; then fail=$((fail + 1)); echo "  FAIL user fault"; else pass=$((pass + 1)); echo "  ok   no user fault"; fi
echo "BIGPIE: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
