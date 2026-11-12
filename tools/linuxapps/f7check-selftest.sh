#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
pass=0
fail=0
expect() {
    local name=$1 want=$2 got
    got=$(python3 -I tools/linuxapps/f7check.py "$D/log" 2>&1)
    if [ "${got%% *}" = "$want" ]; then pass=$((pass + 1)); echo "  OK    $name"; else fail=$((fail + 1)); echo "  FAIL  $name: $got"; fi
}
full() { printf 'FXLOAD 1 h=6042\nFXINPUT a\nFXKEY a\nFXWHEEL 114 mode=0\nFXSCROLL 457\nFXCLICK 391,158\nFXNAV ?nav\nFXURL ?u\n'; }
full > "$D/log"; expect "all events present" green
for name in FXLOAD FXINPUT FXKEY FXWHEEL FXSCROLL FXCLICK FXNAV FXURL; do
    full | grep -v "^$name " > "$D/log"; expect "missing $name" red
done
full | sed 's/^FXSCROLL 457/FXSCROLL 0/' > "$D/log"; expect "scroll stuck at 0" red
{ full; echo "MOZ_CRASH at x"; } > "$D/log"; expect "crash marker" red
: > "$D/log"; expect "empty log" red
pix() {
    local name=$1 want=$2 got
    got=$(python3 -I tools/linuxapps/f7pix.py "$D/shot.ppm" 00c800 2>&1)
    if [ "${got%% *}" = "$want" ]; then pass=$((pass + 1)); echo "  OK    $name"; else fail=$((fail + 1)); echo "  FAIL  $name: $got"; fi
}
ppm() { python3 -I -c 'import sys; r, g, b = map(int, sys.argv[1:4]); sys.stdout.buffer.write(b"P6\n200 200\n255\n" + bytes((r, g, b)) * 40000)' "$@" > "$D/shot.ppm"; }
ppm 0 200 0; pix "green box pixels" green
ppm 0 0 200; pix "no green pixels" red
ppm 3 196 5; pix "tolerance" green
printf 'garbage' > "$D/shot.ppm"; pix "unreadable screenshot" red
echo "F7CHECK-SELFTEST: $pass ok, $fail failed"
[ "$fail" -eq 0 ]
