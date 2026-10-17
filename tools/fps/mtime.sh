#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/fps/mtime.sh -- W-E: shipped files carry a real mtime (Explorer "Date modified" column), counter-proof without --time.
set -uo pipefail
cd "$(dirname "$0")/../.."
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
printf 'x\n' > "$D/a.txt"
fail=0
chk() { if eval "$2"; then echo "OK   $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
python3 tools/osum/mkfs.py build "$D/new.img" 2048 --v3 --time=1760000000 /etc/ "/etc/a.txt=$D/a.txt@0644" >/dev/null 2>&1
python3 tools/osum/mkfs.py build "$D/old.img" 2048 --v3 /etc/ "/etc/a.txt=$D/a.txt@0644" >/dev/null 2>&1
chk "with --time: mtime is the stamp" 'python3 tools/osum/mkfs.py times "$D/new.img" /etc/a.txt | grep -q "mtime=1760000000"'
chk "counter-proof without --time: mtime=0 (the old \"--\")" 'python3 tools/osum/mkfs.py times "$D/old.img" /etc/a.txt | grep -q "mtime=0 "'
chk "usbimg/build.sh passes --time=" 'grep -q -- "--time=\$FS_TIME" tools/usbimg/build.sh'
[ $fail = 0 ] && echo "RESULT ALL OK" || echo "RESULT $fail FAIL"; exit $((fail>0))
