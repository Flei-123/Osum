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
HALT_SECONDS=200
WIDE_RES=1920x1080
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  OK    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
MUT="$OUT/mutant"
mkdir -p "$MUT"
cp -a kernel/user "$MUT/user"
sed -i 's/let title: u64 = setroute.page_title(p)/let title: u64 = 0/' "$MUT/user/settings/setpages.fi"
if cmp -s kernel/user/settings/setpages.fi "$MUT/user/settings/setpages.fi"; then
    bad "mutant source is identical to the real source"; echo "SETTINGSNAMES: $pass passed, $fail failed"; exit 1
fi
if vendor/firn/bin/firnc -c "$MUT/user/settings.fi" -o "$MUT/settings.o" > "$MUT/cc.log" 2>&1 \
   && ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" -o "$MUT/settings.elf" "$MUT/settings.o" 2>>"$MUT/cc.log"; then
    strip --strip-all "$MUT/settings.elf"
    ok "mutant settings (page names from the old tab catalogue) builds"
else
    bad "mutant settings does not build: $(head -5 "$MUT/cc.log")"; echo "SETTINGSNAMES: $pass passed, $fail failed"; exit 1
fi

run_case() {
    local name=$1 lang=$2 scale=$3 builddir=${4:-$DESIGNBUILD} res=${5:-1280x800}
    local yres=${res#*x}
    local dir="$OUT/$name" dreh="$OUT/$name.txt"
    mkdir -p "$dir"
    {
        echo "warte 12"
        echo "klick 24,$((yres-20))"; echo "warte 3"
        echo "klickauf start_Settings"; echo "warte 12"
        echo "warteauf settings: nav route=settings://personalization page=0 || 90"
        echo "warte 3"
        echo "foto names"
    } > "$dreh"
    DESIGNBUILD="$builddir" bash tools/design/audit.sh "$dir" accel=kvm uitrace=yes lang="$lang" uiscale="$scale" res="$res" halt=$HALT_SECONDS drehbuch="$dreh" > "$OUT/$name.audit.log" 2>&1
}

run_case en1 en 1
MUT_BUILD="$OUT/build-mut"
cp -a "$DESIGNBUILD" "$MUT_BUILD"
cp "$MUT/settings.elf" "$MUT_BUILD/settings.elf"
run_case de2 de 2 "$DESIGNBUILD" "$WIDE_RES" &
run_case mut1 en 1 "$MUT_BUILD" &
wait

judge() {
    local name=$1 label=$2 lang=$3 tess=$4 want=$5
    local shot="$OUT/$name/names.ppm"
    if [ ! -f "$shot" ]; then bad "$label: no screenshot ($name)"; return; fi
    local line rc
    line=$(python3 -I tools/settingsnames/check.py "$OUT/$name/serial.txt" "locale/$lang/messages" kernel/user/settings.d/settings.pagemap "$shot" "$tess")
    rc=$?
    if [ "$want" = green ] && [ "$rc" = 0 ]; then ok "$label: $line"
    elif [ "$want" = red ] && [ "$rc" != 0 ]; then ok "$label: $line"
    else bad "$label: unexpected judge result ($line)"; fi
}
judge en1 "English: sidebar and tab names equal the route titles, scale 1" en eng green
judge de2 "German: sidebar and tab names equal the route titles, scale 2" de deu green
judge mut1 "counter-probe: names from the old tab catalogue fail the judge" en eng red

for n in en1 de2 mut1; do
    c=$(grep -acE 'CRASH|EXCEPTION' "$OUT/$n/serial.txt" 2>/dev/null; true)
    [ "${c:-0}" = 0 ] || bad "$n: crash lines $c"
done
echo "SETTINGSNAMES: $pass passed, $fail failed"
[ "$fail" = 0 ]
