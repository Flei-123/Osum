#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
MODE=${1:-light}
SCALE=${EXPLORERPICK_SCALE:-1}
OUT=$(mktemp -d)
trap '[ -n "${EXPLORERPICK_KEEP:-}" ] && cp -r "$OUT" "$EXPLORERPICK_KEEP"; rm -rf "$OUT"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

guest() {
    local tree=$1 out=$2
    ( cd "$tree" && bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
      DESIGNREBUILD=1 DESIGNBUILD="$out.build" bash tools/design/eh6.sh "$out" res=1920x1080 accel=kvm \
        mode="$MODE" uiscale="$SCALE" "extra=vfs lang=en nostart wigapp=/bin/pickdemo" drehbuch="$ROOT/tools/explorerpick/script.txt" moreprogs="pickdemo" ) > "$out.log" 2>&1
    rm -rf "$out.build"
    [ -s "$out/serial.txt" ] && grep -aq "pickdemo: done" "$out/serial.txt"
}

verdicts() {
    python3 -I "$ROOT/tools/explorerpick/check.py" "$1/serial.txt" > "$1.checks" 2>&1
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

echo "== 1. explorer --pick answers pickdemo over svcosum.pick_open (scale $SCALE) =="
if guest "$ROOT" "$OUT/main"; then
    ok "pick guest script ran"
    verdicts "$OUT/main"
    while read -r _ name state note; do
        if [ "$state" = ok ]; then ok "$name"; else bad "$name -- $note"; fi
    done < "$OUT/main.checks"
    [ "$(wc -l < "$OUT/main.checks")" -ge 17 ] && ok "all check groups reported" || bad "check groups missing"
else
    bad "pick guest run failed"; tail -n 12 "$OUT/main.log"
fi

[ -n "${EXPLORERPICK_NOMUT:-}" ] && { echo "EXPLORERPICK: $pass passed, $fail failed"; [ "$fail" = 0 ]; exit; }
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
mutant nofilter kernel/user/explorer/exppick.fi 's/return dlgproto.ext_matches(accept_ptr(), name, text.length(name))/return true/' \
    accept_filter_skips_bin
mutant nocancel kernel/user/explorer/exppick.fi 's/store(dlgproto.ANSWER_CANCEL, 0)/store(dlgproto.ANSWER_OK, 0)/' \
    close_is_cancel
mutant nosavewrite kernel/user/services/dlgreply.fi 's/let wrote: u64 = io.write_all(fd, data, len)/let wrote: u64 = len/' \
    save_writes_staged_content
mutant notitle kernel/user/explorer/exppick.fi 's/if enabled \&\& text.length((&title_buf\[0 as usize\]) as u64) > 0 {/if false {/' \
    save_window_title open_window_title
mutant smallcap kernel/user/explorer/exppick.fi 's/const CONTENT_CAP: u64 = 131072/const CONTENT_CAP: u64 = 65536/' \
    big_file_over_64k_picked
mutant noreplaceask kernel/user/explorer/exppick.fi 's/let allowed: bool = busy.confirm(/let allowed: bool = true || busy.confirm(/' \
    replace_declined_then_accepted
mutant replaceignoresno kernel/user/explorer/exppick.fi 's/^    return allowed$/    return true/' \
    replace_declined_then_accepted

echo "EXPLORERPICK: $pass passed, $fail failed"
[ "$fail" = 0 ]
