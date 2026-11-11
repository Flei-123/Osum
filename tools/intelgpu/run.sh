#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
. tools/lib/firnenv.sh
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }


for m in ids regs bits mode timing edid aux snap dump flip ggtt dbuf backbuf confirm modeset flushpol flushstat engregs fwake micmd ring lrc elsp ereset engine submit; do
    printf 'import gpu.intel.%s\nfn main() -> i32 {\n    return 0\n}\n' "$m" > "$T/k_$m.fi"
    "$FIRNC" --profile=kernel -c "$T/k_$m.fi" -o "$T/k_$m.o" 2> "$T/k.err" \
        && ok "gpu.intel.$m compiles with --profile=kernel" \
        || { bad "gpu.intel.$m does not compile with --profile=kernel"; head -5 "$T/k.err"; }
done

"$FIRNC" tools/intelgpu/oracle.fi -o "$T/oracle" 2> "$T/o.err" \
    && ok "oracle builds" || { bad "oracle does not build"; head -10 "$T/o.err"; }

if [ -x "$T/oracle" ]; then
    "$T/oracle" > "$T/out.txt" 2>&1
    rc=$?
    nok=$(grep -c '^OK' "$T/out.txt")
    nbad=$(grep -c '^FAIL' "$T/out.txt")
    sed -n 's/^FAIL /  FAIL  oracle: /p' "$T/out.txt"
    [ "$rc" = 0 ] && ok "oracle exits 0" || bad "oracle exit code $rc"
    [ "$nbad" = 0 ] && ok "oracle: no FAIL line" || bad "oracle: $nbad FAIL lines"
    [ "$nok" -ge 150 ] && ok "oracle: $nok promises OK (>= 150)" || bad "oracle: only $nok OK (< 150)"
    pass=$((pass+nok))
fi

"$FIRNC" tools/intelgpu/phase2.fi -o "$T/phase2" 2> "$T/p2.err" \
    && ok "phase 2 oracle builds" || { bad "phase 2 oracle does not build"; head -10 "$T/p2.err"; }

if [ -x "$T/phase2" ]; then
    "$T/phase2" > "$T/out2.txt" 2>&1
    rc=$?
    nok=$(grep -c '^OK' "$T/out2.txt")
    nbad=$(grep -c '^FAIL' "$T/out2.txt")
    sed -n 's/^FAIL /  FAIL  phase2: /p' "$T/out2.txt"
    [ "$rc" = 0 ] && ok "phase 2 oracle exits 0" || bad "phase 2 oracle exit code $rc"
    [ "$nbad" = 0 ] && ok "phase 2 oracle: no FAIL line" || bad "phase 2 oracle: $nbad FAIL lines"
    [ "$nok" -ge 90 ] && ok "phase 2 oracle: $nok promises OK (>= 90)" || bad "phase 2 oracle: only $nok OK (< 90)"
    pass=$((pass+nok))
fi

"$FIRNC" tools/intelgpu/flush.fi -o "$T/flush" 2> "$T/f.err" \
    && ok "flush oracle builds" || { bad "flush oracle does not build"; head -10 "$T/f.err"; }

if [ -x "$T/flush" ]; then
    "$T/flush" > "$T/out3.txt" 2>&1
    rc=$?
    nok=$(grep -c '^OK' "$T/out3.txt")
    nbad=$(grep -c '^FAIL' "$T/out3.txt")
    sed -n 's/^FAIL /  FAIL  flush: /p' "$T/out3.txt"
    [ "$rc" = 0 ] && ok "flush oracle exits 0" || bad "flush oracle exit code $rc"
    [ "$nbad" = 0 ] && ok "flush oracle: no FAIL line" || bad "flush oracle: $nbad FAIL lines"
    [ "$nok" -ge 45 ] && ok "flush oracle: $nok promises OK (>= 45)" || bad "flush oracle: only $nok OK (< 45)"
    sed -n 's/^INFO /  INFO  /p' "$T/out3.txt"
    pass=$((pass+nok))
fi

"$FIRNC" tools/intelgpu/engine.fi -o "$T/engine" 2> "$T/e.err" \
    && ok "engine oracle builds" || { bad "engine oracle does not build"; head -10 "$T/e.err"; }

if [ -x "$T/engine" ]; then
    "$T/engine" > "$T/out4.txt" 2>&1
    rc=$?
    nok=$(grep -c '^OK' "$T/out4.txt")
    nbad=$(grep -c '^FAIL' "$T/out4.txt")
    sed -n 's/^FAIL /  FAIL  engine: /p' "$T/out4.txt"
    [ "$rc" = 0 ] && ok "engine oracle exits 0" || bad "engine oracle exit code $rc"
    [ "$nbad" = 0 ] && ok "engine oracle: no FAIL line" || bad "engine oracle: $nbad FAIL lines"
    [ "$nok" -ge 105 ] && ok "engine oracle: $nok promises OK (>= 105)" || bad "engine oracle: only $nok OK (< 105)"
    pass=$((pass+nok))
fi

ORACLE=tools/intelgpu/oracle.fi

mutate() {
    local name=$1 file=$2 expr=$3
    local L="$T/lib-$name"
    mkdir -p "$L/gpu/intel"
    for d in lib/*; do
        [ "$(basename "$d")" = gpu ] || ln -s "$ROOT/$d" "$L/$(basename "$d")"
    done
    for d in lib/gpu/*; do
        [ "$(basename "$d")" = intel ] || ln -s "$ROOT/$d" "$L/gpu/$(basename "$d")"
    done
    for f in lib/gpu/intel/*.fi; do
        cp "$f" "$L/gpu/intel/$(basename "$f")"
    done
    sed -i -e "$expr" "$L/gpu/intel/$file.fi"
    if cmp -s "lib/gpu/intel/$file.fi" "$L/gpu/intel/$file.fi"; then
        bad "control $name: the mutation did not change the file"
        return
    fi
    if ! FIRNLIB="$L" "$FIRNC" "$ORACLE" -o "$T/o-$name" 2>/dev/null; then
        bad "control $name: mutated oracle does not build"
        return
    fi
    local out nf rc
    out=$("$T/o-$name" 2>&1)
    rc=$?
    nf=$(printf '%s\n' "$out" | grep -c '^FAIL')
    if [ "$nf" -gt 0 ] || [ "$rc" != 0 ]; then
        ok "control $name: oracle goes red (FAIL=$nf rc=$rc)"
    else
        bad "control $name: oracle stays green on a broken lib"
    fi
}

mutate id_mask       ids    's/0x2c042cca6cec4c44/0x2c042cca6cec4c45/'
mutate id_extra      ids    's/device == KBL_EXTRA/device == 0x87c1/'
mutate id_vendor     ids    's/if vendor != VENDOR_INTEL {/if false {/'
mutate off_cdclk     regs   's/CDCLK_CTL: u64 = 0x46000/CDCLK_CTL: u64 = 0x46004/'
mutate off_link_m    regs   's/T_LINK_M1: u64 = 0x40/T_LINK_M1: u64 = 0x30/'
mutate off_htotal    regs   's/T_HTOTAL: u64 = 0x0/T_HTOTAL: u64 = 0x8/'
mutate off_aux_data  regs   's/AUX_DATA_A: u64 = 0x64014/AUX_DATA_A: u64 = 0x64018/'
mutate plus_one      timing 's/return (v \& LOW16) + 1/return (v \& LOW16)/'
mutate mn_rounding   timing 's/(link_m \* symbol_khz + link_n \/ 2) \/ link_n/(link_m * symbol_khz) \/ link_n/'
mutate mn_swapped    timing 's/(link_m \* symbol_khz + link_n \/ 2) \/ link_n/(link_n * symbol_khz + link_m \/ 2) \/ link_m/'
mutate pll_shift     timing 's/DPLL_FIELD_BITS: u64 = 6/DPLL_FIELD_BITS: u64 = 5/'
mutate tu_field      timing 's/TU_SHIFT: u64 = 25/TU_SHIFT: u64 = 24/'
mutate rate_table    timing 's/return 270000/return 270001/'
mutate refresh_unit  mode   's/KHZ_TO_MHZ_REFRESH: u64 = 1000000/KHZ_TO_MHZ_REFRESH: u64 = 100000/'
mutate edid_sum      edid   's/return (sum \& 0xff) == 0/return true/'
mutate edid_header   edid   's/if octets.ld8(p, 0) != 0 || octets.ld8(p, 7) != 0 {/if false {/'
mutate edid_fill     edid   's/if octets.ld8(p, i) != HEADER_FILL {/if false {/'
mutate edid_hact     edid   's/octets.ld8(p, d + 4) \& 0xf0) << 4)/octets.ld8(p, d + 4) \& 0xf0) << 3)/'
mutate edid_letters  edid   's/LETTER_BASE: u64 = 64/LETTER_BASE: u64 = 65/'
mutate edid_pclk     edid   's/PCLK_UNIT_KHZ: u64 = 10/PCLK_UNIT_KHZ: u64 = 100/'
mutate edid_size     edid   's/CM_TO_MM: u64 = 10/CM_TO_MM: u64 = 1/'
mutate send_word     bits   's/AUX_CLOCK_BITS: u64 = 0x23f/AUX_CLOCK_BITS: u64 = 0x23e/'
mutate send_timeout  bits   's/AUX_TIMEOUT_MAX: u64 = 0x3/AUX_TIMEOUT_MAX: u64 = 0x2/'
mutate pack_order    aux    's/v = v << 8/v = (v >> 8) | (v << 24)/'
mutate recv_pause    aux    's/us(RECV_ERR_PAUSE_US)//'
mutate nack_ok       aux    's/    return E_NACK/    return E_OK/'
mutate defer_nack    aux    's/if (code \& REPLY_DEFER_MASK) != 0 {/if false {/'
mutate defer_retry   aux    's/MAX_DEFER_RETRIES: u64 = 7/MAX_DEFER_RETRIES: u64 = 1/'
mutate send_retry    aux    's/MAX_SEND_RETRIES: u64 = 5/MAX_SEND_RETRIES: u64 = 1/'
mutate no_mot        aux    's/REQ_I2C_READ | REQ_MOT$/REQ_I2C_READ/'
mutate no_offset_mot aux    's/REQ_I2C_WRITE | REQ_MOT/REQ_I2C_WRITE/'
mutate size_check    aux    's/if size == 0 || size > MAX_MSG {/if false {/'
mutate busy_check    aux    's/return E_BUSY/return E_OK/'
mutate short_reply   aux    's/var take: u64 = got - 1/var take: u64 = chunk/'
mutate cdclk_table   snap   's/return 450000$/return 450001/'
mutate bpc_table     snap   's/return 6$/return 7/'
mutate lanes_plus    snap   's/bits.DDI_LANES_MASK) + 1/bits.DDI_LANES_MASK)/'
mutate stride_unit   bits   's/PLANE_STRIDE_UNIT: u64 = 0x40/PLANE_STRIDE_UNIT: u64 = 0x20/'
mutate pp_shift      bits   's/PP_DELAY_SHIFT: u64 = 0x10/PP_DELAY_SHIFT: u64 = 0x11/'
mutate flip_align   flip   's/(surf \& PAGE_OFFSET_MASK) == 0/true/'
mutate flip_wide    flip   's/ \&\& surf <= bits.PLANE_SURF_MASK//'
mutate flip_nowait  flip   's/while n < LIVE_POLLS {/while n < 0 {/'
mutate flip_always  flip   's/    return F_TIMEOUT$/    return F_OK/'
mutate flip_nofall  flip   's/    wr(regs.PLANE_SURF_1_A, fallback)//'
mutate flip_rb_ok   flip   's/    return F_ROLLED_BACK/    return F_TIMEOUT/'
mutate flip_reg     regs   's/PLANE_SURFLIVE_1_A: u64 = 0x701ac/PLANE_SURFLIVE_1_A: u64 = 0x701a8/'

ORACLE=tools/intelgpu/phase2.fi
mutate pte_valid     ggtt   's/PTE_VALID: u64 = 1$/PTE_VALID: u64 = 3/'
mutate pte_mask      ggtt   's/PTE_PHYS_MASK: u64 = 0x7ffffff000/PTE_PHYS_MASK: u64 = 0x7fffffff00/'
mutate pte_base      ggtt   's/GGTT_BASE_OFFSET: u64 = 0x800000/GGTT_BASE_OFFSET: u64 = 0x400000/'
mutate pte_stride    ggtt   's/PTE_BYTES: u64 = 8$/PTE_BYTES: u64 = 4/'
mutate ggtt_noalign  ggtt   's/if (ggtt_off \& PAGE_MASK) != 0 || (phys \& PAGE_MASK) != 0 {/if false {/'
mutate ggtt_nolimit  ggtt   's/pages > MAX_PAGES {/false {/'
mutate ggtt_noverify ggtt   's/if !mapped_linear(rd64, ggtt_off, phys, pages) {/if false {/'
mutate ggtt_phys_adv ggtt   's/pte_encode(phys + i \* PAGE_SIZE))$/pte_encode(phys))/'
mutate ggtt_zero     ggtt   's/if pages == 0 || pages > MAX_PAGES {/if pages > MAX_PAGES {/'
mutate dbuf_nofront  dbuf   's/if !ggtt.mapped_linear(rd64, front_off, front_phys, pages) {/if false {/'
mutate dbuf_overlap  dbuf   's/if back_off < front_off + pages \* ggtt.PAGE_SIZE \&\& front_off < back_off + pages \* ggtt.PAGE_SIZE {/if false {/'
mutate dbuf_noswap   dbuf   's/(\*d).cur = 1 - (\*d).cur/(*d).cur = (*d).cur/'
mutate dbuf_nofall   dbuf   's/flip.flip_checked(rd, wr, us, target, shown(d))/flip.flip(rd, wr, us, target)/'
mutate dbuf_rbcount  dbuf   's/(\*d).rollbacks = (\*d).rollbacks + 1//'
mutate dbuf_rb_swap  dbuf   's/    if r == flip.F_ROLLED_BACK {/    if r == flip.F_ROLLED_BACK {\n        (*d).cur = 1 - (*d).cur/'
mutate dbuf_restore  dbuf   's/    (\*d).cur = 0\n    return D_OK/    return D_OK/;/^fn restore_front/,/^}/{s/    (\*d).cur = 0$//}'
mutate dbuf_mapfail  dbuf   's/if ggtt.map_linear(rd64, wr64, back_off, back_phys, pages) != ggtt.G_OK {/if false {/'
mutate wd_noarm      confirm 's/    (\*w).state = W_ARMED$/    (*w).state = W_IDLE/'
mutate wd_deadline   confirm 's/(\*w).deadline_ms = now_ms + timeout_ms/(*w).deadline_ms = timeout_ms/'
mutate wd_early      confirm 's/now_ms < (\*w).deadline_ms {/now_ms + 1 < (*w).deadline_ms {/'
mutate wd_norevert   confirm 's/^    revert()$//'
mutate wd_twice      confirm 's/if timeout_ms == 0 || (\*w).state == W_ARMED {/if timeout_ms == 0 {/'
mutate wd_confirm    confirm 's/if (\*w).state != W_ARMED {$/if false {/'
mutate wd_after      confirm 's/    (\*w).state = W_REVERTED/    (*w).state = W_IDLE/'
mutate ms_noroll     modeset 's/        revert(wr, s)$//'
mutate ms_nocheck    modeset 's/    if !matches(rd, m) || !running(rd) {/    if false {/'
mutate ms_norun      modeset 's/    if !running(rd) {$/    if false {/'
mutate ms_nomismatch modeset 's/    if !matches(rd, m) {$/    if false {/'
mutate ms_pack       modeset 's/((low - 1) \& LOW16)/(low \& LOW16)/'
mutate ms_shift      modeset 's/HIGH_SHIFT: u64 = 16/HIGH_SHIFT: u64 = 15/'
mutate ms_nosave     modeset 's/    (\*s).valid = true//'
mutate ms_vsync      modeset 's/rd(base + regs.T_VSYNC)$/rd(base + regs.T_VBLANK)/'
mutate ms_planeck    modeset 's/ \&\& (rd(regs.PLANE_CTL_1_A) \& bits.ENABLE) != 0//'
mutate bb_noarm      backbuf 's/    (\*b).mode = B_DOUBLE$/    (*b).mode = B_OFF/'
mutate bb_drawshown  backbuf 's/return dbuf.hidden(d) == (\*d).back_off/return dbuf.shown(d) == (*d).back_off/'
mutate bb_noreset    backbuf 's/^        (\*b).misses = 0$//'
mutate bb_maxmiss    backbuf 's/MAX_MISSES: u64 = 3/MAX_MISSES: u64 = 1/'
mutate bb_nocopy     backbuf 's/    if drawn_back {/    if false {/'
mutate bb_nostuck    backbuf 's/(\*b).mode = B_SINGLE$/(*b).mode = B_OFF/'
mutate bb_idle       backbuf 's/    if (\*b).mode != B_DOUBLE {/    if false {/'
mutate bb_nocount    backbuf 's/(\*b).presented = (\*b).presented + 1//'
mutate bb_singledraw backbuf 's/        return shown_is_back(d)$/        return false/'
mutate bb_norbwait   backbuf 's/        if (\*b).misses < MAX_MISSES {/        if false {/'
mutate bb_stillon    backbuf 's/    (\*b).mode = B_OFF$/    (*b).mode = B_DOUBLE/'
ORACLE=tools/intelgpu/flush.fi
mutate fp_nowc       flushpol 's/    if wc_target {/    if false {/'
mutate fp_noopt      flushpol 's/    if has_clflushopt {/    if false {/'
mutate fp_noclf      flushpol 's/    if has_clflush {/    if true {/'
mutate fp_badline    flushpol 's/    if !line_valid(line) {/    if false {/'
mutate fp_unit       flushpol 's/LINE_UNIT: u64 = 8/LINE_UNIT: u64 = 4/'
mutate fp_shift      flushpol 's/LINE_SHIFT: u64 = 8/LINE_SHIFT: u64 = 7/'
mutate fp_pow2       flushpol 's/ \&\& (line \& (line - 1)) == 0//'
mutate fp_min        flushpol 's/LINE_MIN: u64 = 16/LINE_MIN: u64 = 4/'
mutate fp_max        flushpol 's/LINE_MAX: u64 = 256/LINE_MAX: u64 = 512/'
mutate fp_needs      flushpol 's/return policy != P_WC/return true/'
mutate fp_floor      flushpol 's/return addr \& (~(line - 1))/return addr/'
mutate fp_lastbyte   flushpol 's/first_line(addr + bytes - 1, line)/first_line(addr + bytes, line)/'
mutate fp_plusone    flushpol 's/(last - first) \/ line + 1/(last - first) \/ line/'
mutate fp_zero       flushpol 's/if bytes == 0 || !line_valid(line) {/if false {/'
mutate fp_nofence1   flushpol '0,/^    fence()$/{s/^    fence()$//}'
mutate fp_nofence2   flushpol ':a;N;$!ba;s/    fence()\n    return n/    return n/'
mutate fp_noflush    flushpol 's/^        flush_line(p)$//'
mutate fp_step       flushpol 's/p = p + line$/p = p + line + line/'
mutate fp_firstline  flushpol 's/var p: u64 = first_line(addr, line)/var p: u64 = addr/'
mutate fs_nomax      flushstat 's/if cycles > (\*s).max {/if false {/'
mutate fs_sum        flushstat 's/(\*s).sum = (\*s).sum + cycles/(*s).sum = cycles/'
mutate fs_last       flushstat 's/(\*s).last = cycles//'
mutate fs_lines      flushstat 's/(\*s).lines = (\*s).lines + lines//'
mutate fs_count      flushstat 's/(\*s).count = (\*s).count + 1//'
ORACLE=tools/intelgpu/engine.fi
mutate en_lri_posted  micmd   's/h = h | MI_LRI_POSTED/h = h/'
mutate en_store_ggtt  micmd   's/return mi(OP_STORE_DWORD_IMM, STORE_LEN_FIELD) | MI_USE_GGTT/return mi(OP_STORE_DWORD_IMM, STORE_LEN_FIELD)/'
mutate en_masked      engregs 's/return ((bits \& LOW16) << MASK_SHIFT) | (bits \& LOW16)/return bits \& LOW16/'
mutate en_ringctl     ring    's/((bytes - PAGE) \& RING_NR_PAGES) | RING_VALID/(bytes \& RING_NR_PAGES) | RING_VALID/'
mutate en_gap         ring    's/RING_GAP: u64 = 8/RING_GAP: u64 = 0/'
mutate en_pad         ring    's/emit(r, micmd.MI_NOOP)/(*r).tail = (*r).tail/'
mutate en_desc_valid  lrc     's/| DESC_LEGACY_32B | DESC_PRIVILEGE | DESC_VALID/| DESC_LEGACY_32B | DESC_PRIVILEGE/'
mutate en_ctxctl      lrc     's/CTRL_INHIBIT_SYN_SWITCH | CTRL_RESTORE_INHIBIT)/CTRL_INHIBIT_SYN_SWITCH)/'
mutate en_lrc_base    lrc     's/put(state, i, base + octets.ld64(regs, n \* 8))/put(state, i, octets.ld64(regs, n * 8))/'
mutate en_elsp_order  elsp    's/wr(port, desc >> 32)/wr(port, desc \& LOW32)/'
mutate en_csb_ack     elsp    's/^    ack(wr, base, (\*c).read)$//'
mutate en_csb_reset   elsp    's/if p >= engregs.CSB_ENTRIES {/if false {/'
mutate en_ack_bit     fwake   's/FORCEWAKE_KERNEL) == want/FORCEWAKE_KERNEL) != 2/'
mutate en_noack_keep  fwake   '0,/wr(req, engregs.masked_off(engregs.FORCEWAKE_KERNEL))/{s/wr(req, engregs.masked_off(engregs.FORCEWAKE_KERNEL))/us(0)/}'
mutate en_reset_skip  ereset  's/wr(engregs.GDRST, domain)/wr(engregs.GDRST, 0)/'
mutate en_reset_keep  ereset  's/wr(ctl, engregs.masked_off(engregs.RESET_REQUEST))//'
mutate en_stuck_ok    ereset  's/return R_STUCK/return R_OK/'
mutate en_mode_check  engine  's/\& engregs.RUN_LIST_ENABLE) == 0 {/\& 0) != 0 {/'
mutate en_seqno_off   engine  's/SEQNO_OFFSET: u64 = 0x400/SEQNO_OFFSET: u64 = 0x404/'
mutate en_align       engine  's/return ((\*l).ring_ggtt \& PAGE_MASK) == 0 \&\& /return /'
mutate en_skip_head   submit  's/lrc.set_head(engine.state_page(e), (\*e).ring.tail)//'
mutate en_reenable    submit  's/if !engine.enable_execlists(rd, wr, e) {/if false {/'
mutate en_dead_guard  submit  's/if (\*e).status != engine.E_READY {/if false {/'
mutate en_fw_put      submit  's/^    fwake.put(rd, wr, us, engregs.FORCEWAKE_GT, engregs.FORCEWAKE_ACK_GT)$//'
mutate en_wait_long   submit  's/WAIT_POLLS: u64 = 100/WAIT_POLLS: u64 = 1000000/'
mutate en_fits        submit  's/if !ring.fits(/if false \&\& !ring.fits(/'
mutate en_size_cap    submit  's/if n > MAX_USER_DWORDS {/if false {/'
ORACLE=tools/intelgpu/oracle.fi

echo "INTELGPU: $pass passed, $fail failed"
[ "$fail" = 0 ]
