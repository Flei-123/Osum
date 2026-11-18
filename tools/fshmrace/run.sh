#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
CORES=${1:-4}
MEM=${FSHMRACE_MEM:-3072}
WD=${FSHMRACE_WD:-/root/fxhp}
T=${FSHMRACE_DIR:-$(mktemp -d)}; mkdir -p "$T"
[ -n "${FSHMRACE_KEEP:-}" ] || trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
CHECKS="fshmrace.no_crash fshmrace.workers_ok"
[ -r "$WD/fxrun/spec.txt" ] || { echo "FSHMRACE: no Alpine root in $WD (tools/linuxapps/prep-firefox.sh), skipped"; exit 0; }

musl-gcc -O2 -s -static -o "$T/t_fshmrace" tools/unterbau/t_fshmrace.c -Itools/unterbau || { echo "FSHMRACE: t_fshmrace does not build"; exit 1; }
printf 'echo "FX start"\n/bin/t_fshmrace 2>&1\necho FX-END\n' > "$T/guest.sh"
KNEW=${FSHMRACE_KERNEL:-$T/k-new.mb}
if [ -z "${FSHMRACE_KERNEL:-}" ]; then
    bash tools/build-kernel.sh "$KNEW" --stufe 0 > "$T/kernel.log" 2>&1 || { echo "FSHMRACE: kernel build failed"; tail -5 "$T/kernel.log"; exit 1; }
fi

verdict() { awk -v n="$2" '$1 == "T" && $2 == n {print $3; f=1; exit} END {if (!f) print "MISSING"}' "$1"; }
run_case() {
    SMP=$CORES KERNEL="$3" BLOCKS=1000000 TMO=300 DONE=FX-END MEM=$MEM EXTRA="/bin/t_fshmrace=$T/t_fshmrace@755" \
        KARGS="osum vfs nokbd nosched noproc nofs smpfrueh $2" \
        bash tools/linuxapps/run.sh "$WD" "$T/guest.sh" "$T/$1" > "$T/$1.log" 2>&1
    rm -f "$T/$1/disk.img"
    grep -a "^T fshmrace\." "$T/$1/ser.txt" 2>/dev/null | sed 's/^/        /' | head -12
}
race_shown() {
    local n v
    for n in $CHECKS; do
        v=$(verdict "$T/$1/ser.txt" "$n")
        { [ "$v" = FAIL ] || [ "$v" = MISSING ]; } && return 0
    done
    return 1
}

echo "== fix: $CORES cores, ${MEM} MiB, smpfrueh =="
run_case fix "" "$KNEW"
for n in $CHECKS; do
    v=$(verdict "$T/fix/ser.txt" "$n")
    if [ "$v" = PASS ]; then ok "$n"; else bad "$n $v"; fi
done

if [ -n "${FSHMRACE_OLD:-}" ]; then
    echo "== old kernel: $FSHMRACE_OLD =="
    run_case old "" "$FSHMRACE_OLD"
    if race_shown old; then ok "old kernel: race shown"; else bad "old kernel: race not shown"; fi
fi
echo "FSHMRACE: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
