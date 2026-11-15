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
full() { printf 'FXLOAD 1 h=6042\nFXSIZE 1256x824\nFXRESIZE 1900x1000\nFXDRAG alpha be\nFXDBL alpha\nFXINPUT a\nFXINPUT abxc\nFXKEY a shift=false\nFXKEY D shift=true\nFXKEY Backspace shift=false\nFXCTX 5,5\nFXWHEEL 114 mode=0\nFXSCROLL 457\nFXCLICK 391,158\nFXSEL c2\nFXSEL b1\nFXNAV ?nav\nFXURL ?u\n'; }
full > "$D/log"; expect "all events present" green
for name in FXLOAD FXINPUT FXKEY FXWHEEL FXSCROLL FXCLICK FXNAV FXURL FXCTX; do
    full | grep -v "^$name " > "$D/log"; expect "missing $name" red
done
export FX7_POINTER=0
full | grep -v "^FX\(DRAG\|DBL\|SIZE\|RESIZE\) " > "$D/log"; expect "pointer probes absent when disabled" green
unset FX7_POINTER
full | grep -v "^FX\(DRAG\|DBL\|SIZE\|RESIZE\) " > "$D/log"; expect "pointer probes absent by default" red
full | grep -v "^FXSEL " > "$D/log"; expect "popup: select choice never reached the page" red
full | grep -v "^FXSEL c2" > "$D/log"; expect "popup: keyboard choice missing" red
full | grep -v "^FXSEL b1" > "$D/log"; expect "popup: click choice missing" red
export FX7_POPUP=0
full | grep -v "^FXSEL " > "$D/log"; expect "popup probe absent when disabled" green
unset FX7_POPUP
for name in FXDRAG FXDBL; do
    full | grep -v "^$name " > "$D/log"; expect "pointer: missing $name" red
done
full | sed 's/^FXRESIZE 1900x1000/FXRESIZE 1256x824/' > "$D/log"; expect "pointer: window did not grow" red
full | sed 's/^FXDRAG alpha be/FXDRAG alpha/' > "$D/log"; expect "pointer: drag selected one word" red
full | grep -v "^FXKEY D" > "$D/log"; expect "missing shifted key" red
full | grep -v "^FXINPUT abxc" > "$D/log"; expect "missing cursor edit" red
full | grep -v "^FXKEY Backspace" > "$D/log"; expect "missing backspace" red
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
