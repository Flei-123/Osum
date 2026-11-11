#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
MODE=${1:-light}
SCALE=${EXPLORERCLIP_SCALE:-1}
OUT=$(mktemp -d)
trap '[ -n "${EXPLORERCLIP_KEEP:-}" ] && cp -r "$OUT" "$EXPLORERCLIP_KEEP"; rm -rf "$OUT"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
SAMPLE="$OUT/a.txt"
printf 'clip me\n' > "$SAMPLE"

guest() {
    local tree=$1 out=$2 script=$3 progs=$4
    ( cd "$tree" && export EH_MKFS_EXTRA="/proc/ /clipsrc/ /clipsrc/a.txt=$SAMPLE@0644" && bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
      DESIGNREBUILD=1 DESIGNBUILD="$out.build" bash tools/design/eh6.sh "$out" res=1920x1080 accel=kvm \
        mode="$MODE" uiscale="$SCALE" "extra=vfs lang=en nostart wigapp=/bin/explorer,/clipsrc" drehbuch="$ROOT/tools/explorerclip/$script" moreprogs="$progs" ) > "$out.log" 2>&1
    rm -rf "$out.build"
    [ -s "$out/serial.txt" ] && grep -aq "explorer: ready" "$out/serial.txt"
}

verdicts() {
    python3 -I "$ROOT/tools/explorerclip/check.py" "$1/serial.txt" > "$1.checks" 2>&1
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

run_main() {
    local label=$1 script=$2 progs=$3 kind=$4 want=$5
    if guest "$ROOT" "$OUT/$label" "$script" "$progs"; then
        ok "$label guest script ran"
        verdicts "$OUT/$label" "$kind"
        while read -r _ name state note; do
            if [ "$state" = ok ]; then ok "$name"; else bad "$name -- $note"; fi
        done < "$OUT/$label.checks"
        [ "$(wc -l < "$OUT/$label.checks")" -ge "$want" ] && ok "$label: all check groups reported" || bad "$label: check groups missing"
    else
        bad "$label guest run failed"; tail -n 12 "$OUT/$label.log"
    fi
}

WANT=${EXPLORERCLIP_ONLY:-}
echo "== 1. explorer copy, cut and paste over the clipboard file list (scale $SCALE) =="
[ -n "$WANT" ] || run_main clip script.txt "" clip 6

[ -n "${EXPLORERCLIP_NOMUT:-}" ] && [ -z "$WANT" ] && { echo "EXPLORERCLIP: $pass passed, $fail failed"; [ "$fail" = 0 ]; exit; }
echo
echo "== 3. COUNTER-PROBES: mutated trees =="
mutant() {
    local name=$1 file=$2 expr=$3 script=$4 progs=$5 kind=$6
    shift 6
    [ -n "$WANT" ] && [ "$WANT" != "$name" ] && return
    local T="$OUT/mut-$name"
    mkdir -p "$T"
    tar -C "$ROOT" --exclude=.git -cf - . | tar -C "$T" -xf -
    sed -i "$expr" "$T/$file"
    if cmp -s "$T/$file" "$ROOT/$file"; then bad "mutant $name: the sed expression changed nothing"; rm -rf "$T"; return; fi
    if guest "$T" "$OUT/m-$name" "$script" "$progs"; then
        ok "mutant $name booted"
        verdicts "$OUT/m-$name" "$kind"
        local c
        for c in "$@"; do expect "$OUT/m-$name" "$c" fail; done
    else
        bad "mutant $name did not run"
    fi
    rm -rf "$T"
}
mutant nocopy kernel/user/services/svcosum.fi 's/xfer.is_error(xfer.set(xfer.SEL_CLIPBOARD, kinds, uris, n))/xfer.is_error(0)/' \
    script.txt "" clip paste_from_service copy_stays_on_clipboard
mutant nocut kernel/user/services/svcosum.fi 's/kinds = kinds | cut_mask()/kinds = kinds/' \
    script.txt "" clip cut_paste_consumes cut_clears_clipboard

echo "EXPLORERCLIP: $pass passed, $fail failed"
[ "$fail" = 0 ]
