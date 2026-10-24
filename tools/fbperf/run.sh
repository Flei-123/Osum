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
# Runs C-E: MTRR write-combining range (fbmtrrsim = MTRRs switched on with default UC, 4 cores: range programmed on all, md=15; fbnomtrr = skipped; fbmtrrstrict = no gain in KVM -> reverted).
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
EH_SMP=4 run_one c "vfs lang=en fbmtrrsim" &
run_one d "vfs lang=en fbmtrrsim fbnomtrr" &
run_one e "vfs lang=en fbmtrrsim fbmtrrstrict" &
wait
SA="$TMPD/a/o/serial.txt"; SB="$TMPD/b/o/serial.txt"
if [ -n "${FBPERF_OUT:-}" ]; then
    mkdir -p "$FBPERF_OUT"
    for t in a b c d e; do cp "$TMPD/$t/o/serial.txt" "$FBPERF_OUT/serial-$t.txt" 2>/dev/null; done
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

mtrr_run() { # <tag> <serial> <state> <reason> <mtrr_type> <min count> <expect md or ->
    local t=$1 s=$2 est=$3 ers=$4 ety=$5 ecnt=$6 emd=$7
    local fl; fl=$(grep -a 'fbperf: .*mtrr_wc_st=' "$s" | head -1 | sed 's/^ *//')
    if [ -z "$fl" ]; then bad "$t: no mtrr_wc fields on the fbperf line"; return; fi
    local st rs ty cnt
    st=$(num " $fl" mtrr_wc_st); rs=$(num " $fl" mtrr_wc_rs); ty=$(num " $fl" mtrr_type); cnt=$(num " $fl" mtrr_wc_n)
    [ "$st" = "$est" ] && ok "$t: mtrr_wc_st=$st" || bad "$t: mtrr_wc_st=$st (want $est)"
    [ "$rs" = "$ers" ] && ok "$t: mtrr_wc_rs=$rs" || bad "$t: mtrr_wc_rs=$rs (want $ers)"
    [ "$ty" = "$ety" ] && ok "$t: mtrr_type=$ty" || bad "$t: mtrr_type=$ty (want $ety)"
    [ "${cnt:-0}" -ge "$ecnt" ] && ok "$t: mtrr_wc_n=$cnt" || bad "$t: mtrr_wc_n=$cnt (want >= $ecnt)"
    if [ "$emd" != "-" ]; then
        local stl md; stl=$(grep -a 'fpsov: stat peak=' "$s" | tail -1)
        md=$(num " $stl" md)
        [ "$md" = "$emd" ] && ok "$t: every core programmed the range (md=$md)" || bad "$t: md='$md' (want $emd)"
    fi
    grep -aiqE 'panic|kernel fault' "$s" && bad "$t: panic on the serial line" || ok "$t: no panic"
}
mtrr_run A-natural "$SA" 3 2 0 0 -
mtrr_run C-sim4 "$TMPD/c/o/serial.txt" 2 0 1 1 15
mtrr_run D-nomtrr "$TMPD/d/o/serial.txt" 3 8 0 0 -
mtrr_run E-strict "$TMPD/e/o/serial.txt" 4 9 0 0 -
echo; echo "FBPERF: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
