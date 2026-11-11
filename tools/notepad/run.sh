#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/firnenv.sh
ROOT=$(pwd)
MODE=${1:-light}
SCALES=${NOTEPAD_SCALES:-1 2}
OUT=$(mktemp -d)
trap '[ -n "${NOTEPAD_KEEP:-}" ] && cp -r "$OUT" "$NOTEPAD_KEEP"; rm -rf "$OUT"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

use_scale() {
    SCALE=$1
    case "$SCALE" in
        1) LIST0=180,518; LIST1=180,546; EDITOR=540,700; TERM=50,700 ;;
        2) LIST0=360,613; LIST1=360,669; EDITOR=1000,800; TERM=100,700 ;;
        *) echo "NOTEPAD: unsupported scale $SCALE"; exit 2 ;;
    esac
    sed -e "s/@LIST0@/$LIST0/" -e "s/@LIST1@/$LIST1/" -e "s/@EDITOR@/$EDITOR/" -e "s/@TERM@/$TERM/" \
        "$ROOT/tools/notepad/script.txt" > "$OUT/script.txt"
}

guest() {
    local tree=$1 out=$2
    ( cd "$tree" && firnenv_prepare_old_tree . >/dev/null 2>&1
      DESIGNREBUILD=1 DESIGNBUILD="$out.build" bash tools/design/eh6.sh "$out" res=1920x1080 accel=kvm \
        mode="$MODE" uiscale="$SCALE" lang=en drehbuch="$OUT/script.txt" moreprogs="dialogd notepad" ) > "$out.log" 2>&1
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

for scale in $SCALES; do
    use_scale "$scale"
    echo "== 1.$SCALE notepad in the guest (scale $SCALE): save, autosave, delete confirm, reopen =="
    if guest "$ROOT" "$OUT/s$SCALE"; then
        ok "guest script ran"
        verdicts "$OUT/s$SCALE"
        while read -r _ name state note; do
            if [ "$state" = ok ]; then ok "$name"; else bad "$name -- $note"; fi
        done < "$OUT/s$SCALE.checks"
        [ "$(wc -l < "$OUT/s$SCALE.checks")" -ge 12 ] && ok "all check groups reported" || bad "check groups missing"
    else
        bad "guest run failed"; tail -n 12 "$OUT/s$SCALE.log"
    fi
done
use_scale 1

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
use_scale 2
mutant norowh kernel/user/notepad.fi '/table_row_height(npdoc.PAD_K_LIST/d' \
    list_row_scaled

echo "NOTEPAD: $pass passed, $fail failed"
[ "$fail" = 0 ]
