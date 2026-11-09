#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
MODE=${1:-light}
SCALE=${NOTEPAD_SCALE:-1}
OUT=$(mktemp -d)
trap '[ -n "${NOTEPAD_KEEP:-}" ] && cp -r "$OUT" "$NOTEPAD_KEEP"; rm -rf "$OUT"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

guest() {
    local tree=$1 out=$2
    ( cd "$tree" && bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
      DESIGNREBUILD=1 DESIGNBUILD="$out.build" bash tools/design/eh6.sh "$out" res=1920x1080 accel=kvm \
        mode="$MODE" uiscale="$SCALE" lang=en drehbuch="$ROOT/tools/notepad/script.txt" moreprogs="dialogd notepad" ) > "$out.log" 2>&1
    rm -rf "$out.build"
    [ -s "$out/serial.txt" ] && grep -aq "notepad: ready" "$out/serial.txt"
}

verdicts() {
    python3 -I "$ROOT/tools/notepad/check.py" "$1/serial.txt" > "$1.checks" 2>&1
}

expect() {
    local line
    line=$(grep -a "^CHECK $2 " "$1.checks" | head -1)
    case "$3:$line" in
        ok:*" ok "*) ok "$2" ;;
        fail:*" fail "*) ok "counter-probe: $2 turns red" ;;
        *) bad "$2 -- expected $3, got: ${line:-missing}" ;;
    esac
}

echo "== 1. notepad in the guest (scale $SCALE): save, autosave, delete confirm, reopen =="
if guest "$ROOT" "$OUT/main"; then
    ok "guest script ran"
    verdicts "$OUT/main"
    while read -r _ name state note; do
        if [ "$state" = ok ]; then ok "$name"; else bad "$name -- $note"; fi
    done < "$OUT/main.checks"
    [ "$(wc -l < "$OUT/main.checks")" -ge 12 ] && ok "all check groups reported" || bad "check groups missing"
else
    bad "guest run failed"; tail -n 12 "$OUT/main.log"
fi

[ -n "${NOTEPAD_NOMUT:-}" ] && { echo "NOTEPAD: $pass passed, $fail failed"; [ "$fail" = 0 ]; exit; }
echo
echo "== 2. COUNTER-PROBES: mutated trees =="
mutant() {
    local name=$1 file=$2 expr=$3
    shift 3
    local T="$OUT/mut-$name"
    mkdir -p "$T"
    tar -C "$ROOT" --exclude=.git -cf - . | tar -C "$T" -xf -
    sed -i "$expr" "$T/$file"
    if cmp -s "$T/$file" "$ROOT/$file"; then bad "mutant $name: the sed expression changed nothing"; rm -rf "$T"; return; fi
    if guest "$T" "$OUT/m-$name"; then
        ok "mutant $name booted"
        verdicts "$OUT/m-$name"
        local c
        for c in "$@"; do expect "$OUT/m-$name" "$c" fail; done
    else
        bad "mutant $name did not run"
    fi
    rm -rf "$T"
}
mutant noconfirm kernel/user/notepad/npactions.fi 's/(status == svcrules.OK \&\& answer == dlgproto.ANSWER_OK)/(status == svcrules.OK)/' \
    delete_cancel
mutant noautosave kernel/user/notepad/npactions.fi '/^fn pad_autosave/,/^}/ s/if !npdoc.pad_is_dirty() {/if true {/' \
    autosave

echo "NOTEPAD: $pass passed, $fail failed"
[ "$fail" = 0 ]
