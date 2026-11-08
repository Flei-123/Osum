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

MUT2="$OUT/mutant2"
mkdir -p "$MUT2"
cp -a kernel/user "$MUT2/user"
sed -i 's/fuiscene.text_role_fit(/fuiscene.text_role(/' "$MUT2/user/navview.fi"
if cmp -s kernel/user/navview.fi "$MUT2/user/navview.fi"; then
    bad "ellipsis mutant source is identical to the real source"; echo "SETTINGSNAMES: $pass passed, $fail failed"; exit 1
fi
if vendor/firn/bin/firnc -c "$MUT2/user/settings.fi" -o "$MUT2/settings.o" > "$MUT2/cc.log" 2>&1 \
   && ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" -o "$MUT2/settings.elf" "$MUT2/settings.o" 2>>"$MUT2/cc.log"; then
    strip --strip-all "$MUT2/settings.elf"
    ok "mutant settings (sidebar text clipped without ellipsis) builds"
else
    bad "ellipsis mutant settings does not build: $(head -5 "$MUT2/cc.log")"; echo "SETTINGSNAMES: $pass passed, $fail failed"; exit 1
fi

run_case() {
    local name=$1 lang=$2 scale=$3 builddir=${4:-$DESIGNBUILD} res=${5:-1280x800}
    local yres=${res#*x}
    local entry=start_Settings
    [ "$lang" = de ] && entry=start_Einstellungen
    local dir="$OUT/$name" dreh="$OUT/$name.txt"
    mkdir -p "$dir"
    {
        echo "warte 12"
        echo "klick 24,$((yres-20))"; echo "warte 3"
        echo "klickauf $entry"; echo "warte 12"
        echo "warteauf settings: nav route=settings://personalization page=0 || 90"
        echo "warte 3"
        echo "foto names"
        echo "klickauf srectwdu"; echo "warte 1"
        echo "tippe monitor"; echo "warte 3"
        echo "foto search"
    } > "$dreh"
    DESIGNBUILD="$builddir" bash tools/design/audit.sh "$dir" accel=kvm uitrace=yes lang="$lang" uiscale="$scale" res="$res" halt=$HALT_SECONDS drehbuch="$dreh" > "$OUT/$name.audit.log" 2>&1
}

run_case en1 en 1
MUT_BUILD="$OUT/build-mut"
cp -a "$DESIGNBUILD" "$MUT_BUILD"
cp "$MUT/settings.elf" "$MUT_BUILD/settings.elf"
MUT2_BUILD="$OUT/build-mut2"
cp -a "$DESIGNBUILD" "$MUT2_BUILD"
cp "$MUT2/settings.elf" "$MUT2_BUILD/settings.elf"
run_case de2 de 2 "$DESIGNBUILD" "$WIDE_RES" &
run_case mut1 en 1 "$MUT_BUILD" &
run_case mut2 en 1 "$MUT2_BUILD" &
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

judge_ellipsis() {
    local shot=$1 label=$2 lang=$3 pattern=$4 want=$5
    local line rc
    if [ ! -f "$shot" ]; then bad "$label: no screenshot"; return; fi
    line=$(python3 -I tools/settingsnames/check.py ellipsis "$shot" "$lang" "$pattern")
    rc=$?
    if [ "$want" = green ] && [ "$rc" = 0 ]; then ok "$label: $line"
    elif [ "$want" = red ] && [ "$rc" != 0 ]; then ok "$label: $line"
    else bad "$label: unexpected ellipsis result ($line)"; fi
}
judge_ellipsis "$OUT/en1/search.ppm" "English: the long search result row ends in an ellipsis, scale 1" eng 'monitors and screen[a-z ]{0,10}\.{2,3}' green
judge_ellipsis "$OUT/de2/names.ppm" "German: the long sidebar title ends in an ellipsis, scale 2" deu 'bildschirm[a-z]{0,4}\.{2,3}' green
judge_ellipsis "$OUT/mut2/search.ppm" "counter-probe: without the ellipsis the row is cut silently" eng 'monitors and screen[a-z ]{0,10}\.{2,3}' red

for n in en1 de2 mut1 mut2; do
    c=$(grep -acE 'CRASH|EXCEPTION' "$OUT/$n/serial.txt" 2>/dev/null; true)
    [ "${c:-0}" = 0 ] || bad "$n: crash lines $c"
done
echo "SETTINGSNAMES: $pass passed, $fail failed"
[ "$fail" = 0 ]
