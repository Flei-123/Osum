#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
python3 -I tools/kdatalayout/check.py .
rc=$?
python3 -I tools/kdatalayout/control.py .
cp=$?
[ "$rc" -eq 0 ] && [ "$cp" -eq 0 ]
