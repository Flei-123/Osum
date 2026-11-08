#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT; fi
mkdir -p "$OUT"
export DESIGNBUILD="${DESIGNBUILD:-$OUT/build}"
export AUDIT_TIMEOUT="${AUDIT_TIMEOUT:-1700}"
MAX_PARALLEL=3
HALT_SECONDS=200
WIDE_RES=1920x1080
NARROW_RES=1280x800
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  OK    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
MUT="$OUT/mutant"
mkdir -p "$MUT"
cp -a kernel/user "$MUT/user"
python3 -I - "$MUT/user/settings/setcore.fi" "$MUT/en-messages" <<'PY'
import sys
source, messages = sys.argv[1], sys.argv[2]
text = open(source, encoding="utf-8").read()
tail = "        i = i + 1\n    }\n}\n\nfn map_read()"
trimmed = "        i = i + 1\n    }\n    if a > 0 {\n        setbase.d_modes[(a - 1) as usize] = 0 as u8\n    }\n}\n\nfn map_read()"
if tail not in text:
    sys.exit("mutant anchor missing")
open(source, "w", encoding="utf-8").write(text.replace(tail, trimmed, 1))
lines = []
for line in open("locale/en/messages", encoding="utf-8"):
    if line.startswith("settings.display.depth = "):
        line = "settings.display.depth = Colour depth: 32\n"
    elif line.startswith("settings.display.depth3 = "):
        line = "settings.display.depth3 = 8/15/16/24; this kernel draws only 32.\n"
    lines.append(line)
open(messages, "w", encoding="utf-8").write("".join(lines))
PY
if [ $? -ne 0 ] || cmp -s kernel/user/settings/setcore.fi "$MUT/user/settings/setcore.fi"; then
    bad "mutant source is identical to the real source"; echo "SETTINGSDISPLAY: $pass passed, $fail failed"; exit 1
fi
if vendor/firn/bin/firnc -c "$MUT/user/settings.fi" -o "$MUT/settings.o" > "$MUT/cc.log" 2>&1 \
   && ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" -o "$MUT/settings.elf" "$MUT/settings.o" 2>>"$MUT/cc.log"; then
    strip --strip-all "$MUT/settings.elf"
    ok "mutant settings (mode list trims its last row) builds"
else
    bad "mutant settings does not build: $(head -5 "$MUT/cc.log")"; echo "SETTINGSDISPLAY: $pass passed, $fail failed"; exit 1
fi

run_case() {
    local name=$1 scale=$2 res=$3 list_point=$4 details_point=$5 builddir=${6:-$DESIGNBUILD} extra=${7:--} card_word=${8:-disp}
    local yres=${res#*x}
    local CARD_WORD_ARG=()
    [ "$card_word" = none ] || CARD_WORD_ARG=(extra=$card_word)
    local dir="$OUT/$name" dreh="$OUT/$name.txt"
    mkdir -p "$dir"
    {
        echo "warte 12"
        echo "klick 24,$((yres-20))"; echo "warte 3"
        echo "klickauf start_Settings"; echo "warte 12"
        echo "warteauf settings: nav route=settings://personalization page=0 || 90"
        echo "taste ctrl-f"; echo "tippe display"; echo "warte 3"
        echo "taste ret"; echo "warte 4"
        echo "klick $list_point"; echo "warte 1"
        echo "taste end"; echo "warte 2"
        echo "foto display"
        echo "taste ctrl-f"; echo "taste ctrl-a"; echo "tippe network"; echo "warte 3"
        echo "taste ret"; echo "warte 4"
        echo "foto network"
        echo "klick $details_point"; echo "warte 4"
        echo "foto details"
    } > "$dreh"
    DESIGNBUILD="$builddir" AUDIT_MKFS_EXTRA="${extra#-}" \
        bash tools/design/audit.sh "$dir" accel=kvm uitrace=yes "${CARD_WORD_ARG[@]}" uiscale="$scale" res="$res" halt=$HALT_SECONDS drehbuch="$dreh" > "$OUT/$name.audit.log" 2>&1
}

MUT_BUILD="$OUT/build-mut"
run_case real1 1 $NARROW_RES 434,300 350,273
cp -a "$DESIGNBUILD" "$MUT_BUILD"
cp "$MUT/settings.elf" "$MUT_BUILD/settings.elf"
SLOW=(
    "real2 2 $WIDE_RES 830,600 700,546"
    "mut1 1 $NARROW_RES 434,300 350,273 $MUT_BUILD /usr/share/locale/en/messages=$MUT/en-messages"
    "nocard1 1 $NARROW_RES 434,300 350,273 $DESIGNBUILD - none"
)
running=0
for spec in "${SLOW[@]}"; do
    run_case $spec &
    running=$((running+1))
    if [ "$running" -ge "$MAX_PARALLEL" ]; then wait -n; running=$((running-1)); fi
done
wait

judge() {
    local name=$1 shot_name=$2 kind=$3 label=$4 expect=$5
    local shot="$OUT/$name/$shot_name.ppm"
    if [ ! -f "$shot" ]; then bad "$label: no screenshot ($name/$shot_name)"; return; fi
    local line status
    line=$(python3 -I tools/settingsdisplay/check.py "$kind" "$shot")
    status=$?
    if [ "$expect" = green ] && [ $status -eq 0 ]; then ok "$label: $line"
    elif [ "$expect" = red ] && [ $status -ne 0 ]; then ok "$label: $line"
    else bad "$label: expected $expect ($line)"; fi
}

judge real1 display display "display page, scale 1: last mode 2560 x 1600 visible, 32 bit, no 328" green
judge real2 display display "display page, scale 2: last mode 2560 x 1600 visible, 32 bit, no 328" green
judge nocard1 display nocard "display page without card word: empty list shows (no card found), card not probed" green
judge real1 network network "network page, scale 1: Related row Connection details" green
judge real2 network network "network page, scale 2: Related row Connection details" green
judge real1 details details "click on Related row opens the details page, scale 1" green
judge real2 details details "click on Related row opens the details page, scale 2" green
mut_line=$(python3 -I tools/settingsdisplay/check.py display "$OUT/mut1/display.ppm" 2>/dev/null)
case "$mut_line" in
    *last_mode=False*) ok "counter-probe: trimmed mode list loses 2560 x 1600 ($mut_line)" ;;
    *) bad "counter-probe: trimmed mode list still shows 2560 x 1600 ($mut_line)" ;;
esac
case "$mut_line" in
    *glued=True*) ok "counter-probe: old depth text reads 328" ;;
    *) bad "counter-probe: old depth text not detected ($mut_line)" ;;
esac

for n in real1 real2 mut1; do
    c=$(grep -acE 'CRASH|EXCEPTION' "$OUT/$n/serial.txt" 2>/dev/null; true)
    [ "${c:-0}" = 0 ] || bad "$n: crash lines $c"
done
echo "SETTINGSDISPLAY: $pass passed, $fail failed"
[ "$fail" = 0 ]
