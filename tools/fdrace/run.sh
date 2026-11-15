#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
CORES=${1:-4}
T=${FDRACE_DIR:-$(mktemp -d)}; mkdir -p "$T"
[ -n "${FDRACE_KEEP:-}" ] || trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
RACE_CHECKS="fdrace.procs_own_files fdrace.threads_open_read fdrace.threads_held_fd fdrace.threads_socketpair fdrace.threads_rename"
ALL_CHECKS="fdrace.procs_started fdrace.procs_rounds fdrace.threads_started fdrace.threads_rounds fdrace.stdout_alive $RACE_CHECKS"
verdict() { awk -v n="$2" '$1 == n {print $2; f=1; exit} END {if (!f) print "MISSING"}' "$1"; }
run_case() {
    ONLY="t_fdrace" SMP=$CORES KARGS="$2" TMO=240 ${3:+KERNEL="$3"} UB_OUT="$T/$1" KEEP=1 UB_RESULT="$T/$1.res" \
        bash tools/unterbau/run.sh > "$T/$1.log" 2>&1
    grep -a "^T fdrace\." "$T/$1/new-t_fdrace.ser" 2>/dev/null | sed 's/^/        /' | head -14
}
race_shown() {
    local n v
    for n in $RACE_CHECKS; do
        v=$(verdict "$T/$1.res" "$n")
        { [ "$v" = FAIL ] || [ "$v" = MISSING ]; } && return 0
    done
    return 1
}

echo "== fix: $CORES cores, smpfrueh =="
run_case fix "smpfrueh" "${FDRACE_KERNEL:-}"
for n in $ALL_CHECKS; do
    v=$(verdict "$T/fix.res" "$n")
    if [ "$v" = PASS ]; then ok "$n"; else bad "$n $v"; fi
done

KNEW=${FDRACE_KERNEL:-$T/fix/k-new.mb}
echo "== counter: nofdlock =="
if [ -r "$KNEW" ]; then
    run_case ctl "smpfrueh nofdlock" "$KNEW"
    if race_shown ctl; then ok "counter: fd lock off -> race shown"; else bad "counter: fd lock off, race not shown"; fi
else
    bad "no kernel image from the fix run"
fi

if [ -n "${FDRACE_OLD:-}" ]; then
    echo "== old kernel: $FDRACE_OLD =="
    run_case old "smpfrueh" "$FDRACE_OLD"
    if race_shown old; then ok "old kernel: race shown"; else bad "old kernel: race not shown"; fi
fi
echo "FDRACE: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
