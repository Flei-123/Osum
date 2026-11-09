#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
MODE=${1:-light}
OUT=$(mktemp -d)
trap '[ -n "${DIALOGD_KEEP:-}" ] && cp -r "$OUT" "$DIALOGD_KEEP"; rm -rf "$OUT"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

guest() {
    local tree=$1 out=$2 scale=$3
    ( cd "$tree" && DESIGNREBUILD=1 DESIGNBUILD="$out.build" bash tools/design/eh6.sh "$out" res=1920x1080 accel=kvm \
        mode="$MODE" uiscale="$scale" lang=en drehbuch="$ROOT/tools/dialogd/script.txt" moreprogs="dialogd dialogdemo" ) > "$out.log" 2>&1
    rm -rf "$out.build"
    [ -f "$out/msg.ppm" ] && [ -s "$out/serial.txt" ]
}

verdicts() {
    python3 -I "$ROOT/tools/dialogd/check.py" "$1" "$1/serial.txt" "$2" > "$1.checks" 2>&1
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

echo "== 1. host test: protocol and directory model =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || bad "fetch-firnc.sh failed"
if FIRNLIB="$ROOT/lib" vendor/firn/bin/firnc --profile=app tools/dialogd/host.fi -o "$OUT/host" > "$OUT/host.build" 2>&1 && "$OUT/host" > "$OUT/host.txt"; then
    ok "host test green ($(tail -1 "$OUT/host.txt"))"
else
    bad "host test failed"; grep -v '^warning' "$OUT/host.build" | head -5; grep '^FAIL' "$OUT/host.txt" | head -5
fi

for scale in 1 2; do
    echo
    echo "== 2.$scale guest dialogs, scale $scale =="
    if guest "$ROOT" "$OUT/s$scale" "$scale"; then
        ok "guest script ran, photos taken"
        verdicts "$OUT/s$scale" "$scale"
        while read -r _ name state note; do
            if [ "$state" = ok ]; then ok "$name"; else bad "$name -- $note"; fi
        done < "$OUT/s$scale.checks"
        [ "$(wc -l < "$OUT/s$scale.checks")" -ge 20 ] && ok "all check groups reported" || bad "check groups missing"
    else
        bad "guest run failed (scale $scale)"; tail -n 12 "$OUT/s$scale.log"
    fi
done

echo
echo "== 3. COUNTER-PROBES: mutated trees =="
mutant() {
    local name=$1 file=$2 expr=$3 scale=${MUTANT_SCALE:-1}
    shift 3
    local T="$OUT/mut-$name"
    mkdir -p "$T"
    tar -C "$ROOT" --exclude=.git -cf - . | tar -C "$T" -xf -
    sed -i "$expr" "$T/$file"
    if cmp -s "$T/$file" "$ROOT/$file"; then bad "mutant $name: the sed expression changed nothing"; rm -rf "$T"; return; fi
    if guest "$T" "$OUT/m-$name" "$scale"; then
        ok "mutant $name booted"
        verdicts "$OUT/m-$name" "$scale"
        local c
        for c in "$@"; do expect "$OUT/m-$name" "$c" fail; done
    else
        bad "mutant $name did not run"
    fi
    rm -rf "$T"
}
mutant escyes kernel/user/dialogd.fi 's/} else if busy.confirm(title, body) {/} else if busy.confirm(title, body) || true {/' \
    confirm_esc_no
mutant pathname kernel/user/dialogd/dlgpicker.fi 's/remember_name(dlgdir.name_of(row))/remember_name(dlgdir.path_of(row))/' \
    open_plain_name_and_content
MUTANT_SCALE=2 mutant nofit kernel/user/dialogd/dlgpicker.fi 's/let over: u64 = fuiscene.work_overflow()/let over: u64 = 0/' \
    button_fully_visible_open_start button_fully_visible_save_start

echo "DIALOGD: $pass passed, $fail failed"
[ "$fail" = 0 ]
