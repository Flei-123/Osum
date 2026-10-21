#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/gpu3/run.sh <workdir from tools/linuxapps/prep-firefox.sh> -- GPU-3: a Firn --shared dummy Vulkan ICD loads in the Osum dynamic loader (dlopen/dlsym/call/dlclose) like on the host.
set -uo pipefail
cd "$(dirname "$0")/../.."
WD=${1:?workdir}
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
export FIRNLIB="$(pwd)/lib"
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
FIRNC=vendor/firn/bin/firnc
pass=0; fail=0
ck() { if [ "$2" = ok ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
$FIRNC --shared -o "$D/libicd.so" tools/gpu3/icd.fi && $FIRNC --shared -o "$D/libicd_partial.so" tools/gpu3/partial.fi && ck "firnc --shared builds the ICD" ok || ck "firnc --shared builds the ICD" no
musl-gcc -O1 -o "$D/client" tools/gpu3/client.c && ck "musl client builds (dynamic)" ok || ck "musl client builds (dynamic)" no
gcc -O1 -o "$D/hostclient" tools/gpu3/client.c -ldl && "$D/hostclient" "$D/libicd.so" > "$D/host.txt" 2>&1; grep -aq "GPU3 DONE bad=0" "$D/host.txt" && ck "host Linux loads the ICD (reference)" ok || ck "host Linux loads the ICD (reference)" no
"$D/hostclient" "$D/libicd_partial.so" > "$D/hostp.txt" 2>&1; grep -aq "GPU3 FAIL dlsym vkCreateInstance" "$D/hostp.txt" && ck "host: partial ICD is detected (counter-proof)" ok || ck "host: partial ICD is detected (counter-proof)" no
grep -v '^/etc/inittab' "$WD/fxrun/spec.txt" > "$D/spec.txt"
printf '/gpu3/@755\n/gpu3/client=%s@755\n/gpu3/libicd.so=%s@755\n/gpu3/libicd_partial.so=%s@755\n' "$D/client" "$D/libicd.so" "$D/libicd_partial.so" >> "$D/spec.txt"
SPEC="$D/spec.txt" BLOCKS=${BLOCKS:-1000000} TMO=${TMO:-600} bash tools/linuxapps/run.sh "$WD" tools/gpu3/guest.sh "$D/out" > "$D/run.log" 2>&1
S="$D/out/ser.clean"
grep -aq "^GPU3 DONE bad=0" "$S" && ck "guest: dlopen + 10 dlsym + calls + dlclose, bad=0" ok || ck "guest: dlopen + 10 dlsym + calls + dlclose, bad=0" no
[ "$(grep -ac '^GPU3 ok' "$S")" -ge 20 ] && ck "guest: at least 20 checks ok" ok || ck "guest: at least 20 checks ok" no
grep -aq "^GPU3 rc=0" "$S" && ck "guest: client exits 0" ok || ck "guest: client exits 0" no
grep -aq "^GPU3 FAIL dlopen" "$S" && grep -aq "^GPU3 neg-missing rc=1" "$S" && ck "guest: missing .so refused (counter-proof)" ok || ck "guest: missing .so refused (counter-proof)" no
grep -aq "^GPU3 FAIL dlsym vkCreateInstance" "$S" && grep -aq "^GPU3 neg-partial rc=1" "$S" && ck "guest: partial ICD detected (counter-proof)" ok || ck "guest: partial ICD detected (counter-proof)" no
echo "GPU3: $pass ok, $fail failed"
[ "$fail" -eq 0 ]
