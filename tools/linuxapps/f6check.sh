#!/usr/bin/env bash
set -uo pipefail
ser=${1:?ser.clean}
runs=$(grep -ac '^FX11 run [0-9]* begin' "$ser")
good=$(grep -aEc '^FX11 run [0-9]+ rc=0 bytes=[0-9]{4,}' "$ser")
if grep -aq 'user fault\|Segmentation fault' "$ser"; then echo "red user fault or SEGV in the https run"; exit 1; fi
if [ "$runs" -lt 1 ] || [ "$good" -ne "$runs" ]; then echo "red $good of $runs https runs produced a screenshot"; exit 1; fi
echo "green $good of $runs https screenshots"
