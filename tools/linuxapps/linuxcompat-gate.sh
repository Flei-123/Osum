#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
WD=${1:?workdir from linuxcompat-prep.sh}
OUT=${2:-$(mktemp -d)}
export EXPECT=${EXPECT:-tools/linuxapps/linuxcompat-expected-red.txt}
export GUEST=tools/linuxapps/guest-linuxcompat.sh
export BLOCKS=${BLOCKS:-3600000}
export MIN_RESULTS=${MIN_RESULTS:-90}
export TMO=${TMO:-2700}
exec bash tools/linuxapps/apps-gate.sh "$WD" "$OUT"
