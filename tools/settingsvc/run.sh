#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
. tools/lib/firnenv.sh
MODE=${1:-light}
SCALE=${SETTINGSVC_SCALE:-1}
OUT=$(mktemp -d)
trap '[ -n "${SETTINGSVC_KEEP:-}" ] && cp -r "$OUT" "$SETTINGSVC_KEEP"; rm -rf "$OUT"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

guest() {
    local tree=$1 out=$2
    local apps="$out.apps"
    rm -rf "$apps"; cp -a "$tree/assets/apps" "$apps"
    printf 'perm=notify\n' >> "$apps/charmap.osp/INFO"
    ( cd "$tree" && export APPS_DIR="$apps" BUNDLE_USER_APPS=charmap.osp EH_MKFS_EXTRA=/proc/ && firnenv_prepare_old_tree .
      DESIGNREBUILD=1 DESIGNBUILD="$out.build" bash tools/design/eh6.sh "$out" res=1920x1080 accel=kvm \
        mode="$MODE" uiscale="$SCALE" "extra=vfs lang=en" drehbuch="$ROOT/tools/settingsvc/script.txt" moreprogs="dialogd apprights charmap" ) > "$out.log" 2>&1
    rm -rf "$out.build" "$apps"
    [ -s "$out/serial.txt" ] && grep -aq "settings: ready" "$out/serial.txt"
}

verdicts() {
    python3 -I "$ROOT/tools/settingsvc/check.py" "$1/serial.txt" > "$1.checks" 2>&1
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

WANT=${SETTINGSVC_ONLY:-}
echo "== 1. settings in the guest (scale $SCALE): last page, uninstall confirm =="
if [ -n "$WANT" ]; then
    :
elif guest "$ROOT" "$OUT/main"; then
    ok "guest script ran"
    verdicts "$OUT/main"
    while read -r _ name state note; do
        if [ "$state" = ok ]; then ok "$name"; else bad "$name -- $note"; fi
    done < "$OUT/main.checks"
    [ "$(wc -l < "$OUT/main.checks")" -ge 9 ] && ok "all check groups reported" || bad "check groups missing"
else
    bad "guest run failed"; tail -n 12 "$OUT/main.log"
fi

[ -n "${SETTINGSVC_NOMUT:-}" ] && [ -z "$WANT" ] && { echo "SETTINGSVC: $pass passed, $fail failed"; [ "$fail" = 0 ]; exit; }
echo
echo "== 2. COUNTER-PROBES: mutated trees =="
mutant() {
    local name=$1 file=$2 expr=$3
    shift 3
    [ -n "$WANT" ] && [ "$WANT" != "$name" ] && return
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
mutant noconfirm kernel/user/settings/setdevice.fi 's/let verdict: u64 = setsvc.confirm_uninstall()/let verdict: u64 = setsvc.VERDICT_GO/' \
    confirm_cancel confirm_accept cancel_keeps_app
mutant norestore kernel/user/settings.fi 's/^    setsvc.restore_start_page()$//' \
    page_restored reopened_on_page

echo "SETTINGSVC: $pass passed, $fail failed"
[ "$fail" = 0 ]
