#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/fbperf/run.sh -- HWPERF gate: framebuffer bench + cache-mode probe (kernel/ui/kgui.fi fbperf, kernel/gfx/fb.fi mtrr_probe).
#
#   /root/jarvis/bin/heavy bash tools/fbperf/run.sh
#
# Run A (default): the boot bench prints `fbperf: fb_write_mbs= fb_copy_mbs= ram_write_mbs= cache_mode= pat_wc= mtrr_type=`.
#   - all three rates > 0, cache_mode=1 (wc), pat_wc=1
#   - the overlay (Ctrl+Shift+F) reads /proc/frames and echoes `fbw= fbc= cm=` on its `fpsov: stat` line:
#     fbw equals the boot value (same kstate source), cm=1 (wc), no panic
# Run B (counter-proof, word `fbuc`): cache_mode=0 (uc), pat_wc=0 and the overlay reports cm=0.
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

cat > "$TMPD/dreh.txt" <<'EOT'
warteauf 'taskbar: steht|taskbar: geom' || 120
warte 8
taste ctrl-shift-f
warte 12
foto 01-on
EOT

run_one() { # <name> <extra words>
    mkdir -p "$TMPD/$1"
    EH_MKFS_EXTRA="/proc/" DESIGNBUILD="$TMPD/$1/build" bash tools/design/eh6.sh "$TMPD/$1/o" res=1280x800 accel=kvm tafel=nein moreprogs=term "extra=$2" \
        drehbuch="$TMPD/dreh.txt" > "$TMPD/$1/o.log" 2>&1
    rm -rf "$TMPD/$1/build"
}
num() { echo "$1" | sed -nE "s/.* $2=([0-9]+).*/\1/p"; }

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
run_one a "vfs lang=en" &
run_one b "vfs lang=en fbuc" &
wait
SA="$TMPD/a/o/serial.txt"; SB="$TMPD/b/o/serial.txt"
if [ -n "${FBPERF_OUT:-}" ]; then
    mkdir -p "$FBPERF_OUT"; cp "$SA" "$FBPERF_OUT/serial-a.txt" 2>/dev/null; cp "$SB" "$FBPERF_OUT/serial-b.txt" 2>/dev/null
fi
[ -s "$SA" ] && [ -s "$SB" ] || { bad "no serial output: $(tail -n 3 "$TMPD/a/o.log" | tr '\n' ' ')"; echo "FBPERF: $pass passed, $fail failed"; exit 1; }

check_run() { # <tag> <serial> <expect cache_mode> <expect pat_wc> <expect cm>
    local t=$1 s=$2 ecm=$3 epat=$4 ecmn=$5
    local fl; fl=$(grep -a 'fbperf: .*fb_write_mbs=' "$s" | head -1 | sed 's/^ *//')
    if [ -z "$fl" ]; then bad "$t: no 'fbperf:' line"; return; fi
    local w c r cmode pat
    w=$(num " $fl" fb_write_mbs); c=$(num " $fl" fb_copy_mbs); r=$(num " $fl" ram_write_mbs)
    cmode=$(num " $fl" cache_mode); pat=$(num " $fl" pat_wc)
    [ "${w:-0}" -gt 0 ] && [ "${c:-0}" -gt 0 ] && [ "${r:-0}" -gt 0 ] && ok "$t: rates fb_write=$w fb_copy=$c ram_write=$r MB/s" || bad "$t: a rate is zero: $fl"
    [ "$cmode" = "$ecm" ] && ok "$t: cache_mode=$cmode" || bad "$t: cache_mode=$cmode (want $ecm)"
    [ "$pat" = "$epat" ] && ok "$t: pat_wc=$pat" || bad "$t: pat_wc=$pat (want $epat)"
    local st; st=$(grep -a 'fpsov: stat peak=' "$s" | tail -1 | sed 's/.*fpsov: stat/fpsov: stat/')
    if [ -z "$st" ]; then bad "$t: no 'fpsov: stat' line"; else
        local ow cm; ow=$(num " $st" fbw); cm=$(num " $st" cm)
        [ -n "$ow" ] && [ "$ow" = "$w" ] && ok "$t: /proc/frames fb_write_mbs=$ow equals the boot value" || bad "$t: /proc/frames fb_write_mbs '$ow' != boot '$w'"
        [ "$cm" = "$ecmn" ] && ok "$t: /proc/frames fb_cache_mode code cm=$cm" || bad "$t: cm='$cm' (want $ecmn)"
    fi
    grep -aiqE 'panic|kernel fault' "$s" && bad "$t: panic on the serial line" || ok "$t: no panic"
}
check_run A "$SA" 1 1 1
check_run B "$SB" 0 0 0
echo; echo "FBPERF: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
