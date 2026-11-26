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


for m in ids regs bits mode timing edid aux snap dump flip ggtt dbuf backbuf confirm modeset flushpol flushstat engregs fwake micmd ring lrc elsp ereset engine submit blt blit blitpool rcsparse vblank ppgtt flipdone pace modelist outputs rcsbatch rcsrun; do
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
    [ "$nok" -ge 205 ] && ok "engine oracle: $nok promises OK (>= 205)" || bad "engine oracle: only $nok OK (< 205)"
    pass=$((pass+nok))
fi

run_oracle() {
    local name=$1 file=$2 min=$3 rc nok nbad
    "$FIRNC" "$file" -o "$T/$name" 2> "$T/$name.err" \
        && ok "$name oracle builds" || { bad "$name oracle does not build"; head -10 "$T/$name.err"; return; }
    "$T/$name" > "$T/$name.txt" 2>&1
    rc=$?
    nok=$(grep -c '^OK' "$T/$name.txt")
    nbad=$(grep -c '^FAIL' "$T/$name.txt")
    sed -n "s/^FAIL /  FAIL  $name: /p" "$T/$name.txt"
    [ "$rc" = 0 ] && ok "$name oracle exits 0" || bad "$name oracle exit code $rc"
    [ "$nbad" = 0 ] && ok "$name oracle: no FAIL line" || bad "$name oracle: $nbad FAIL lines"
    [ "$nok" -ge "$min" ] && ok "$name oracle: $nok promises OK (>= $min)" || bad "$name oracle: only $nok OK (< $min)"
    pass=$((pass+nok))
}

run_oracle rcs tools/intelgpu/rcs.fi 36
run_oracle vblank tools/intelgpu/vblank.fi 33
run_oracle ppgtt tools/intelgpu/ppgtt.fi 91
run_oracle display tools/intelgpu/display.fi 140
run_oracle rcsrun tools/intelgpu/rcsrun.fi 68

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
mutate bl_fill_op     blt     's/CMD_XY_COLOR_BLT: u64 = 0x54300005/CMD_XY_COLOR_BLT: u64 = 0x54200005/'
mutate bl_copy_len    blt     's/CMD_XY_SRC_COPY_BLT: u64 = 0x54f00008/CMD_XY_SRC_COPY_BLT: u64 = 0x54f00007/'
mutate bl_flush_cmd   blt     's/CMD_MI_FLUSH_DW: u64 = 0x13204001/CMD_MI_FLUSH_DW: u64 = 0x13200001/'
mutate bl_flush_gtt   blt     's/FLUSH_USE_GTT: u64 = 0x4/FLUSH_USE_GTT: u64 = 0x0/'
mutate bl_rop_fill    blt     's/ROP_COLOR_COPY: u64 = 0xf00000/ROP_COLOR_COPY: u64 = 0xcc0000/'
mutate bl_rop_copy    blt     's/ROP_SRC_COPY: u64 = 0xcc0000/ROP_SRC_COPY: u64 = 0xf00000/'
mutate bl_depth       blt     's/DEPTH_32: u64 = 0x3000000/DEPTH_32: u64 = 0x2000000/'
mutate bl_xy_swap     blt     's/return (y << COORD_SHIFT) | x/return (x << COORD_SHIFT) | y/'
mutate bl_addr_hi     blt     's/put(out, 5, dst >> 32)/put(out, 5, 0)/'
mutate bl_color       blt     's/put(out, 6, color)/put(out, 6, 0)/'
mutate bl_src_pitch   blt     's/put(out, 7, src_pitch)/put(out, 7, dst_pitch)/'
mutate bl_src_addr    blt     's/put(out, 8, src)/put(out, 8, dst)/'
mutate bl_rect_x      blt     's/if x2 \* PIXEL_BYTES > pitch {/if false {/'
mutate bl_rect_y      blt     's/return y2 \* pitch <= bytes/return true/'
mutate bl_rect_empty  blt     's/if x2 <= x1 || y2 <= y1 || /if /'
mutate bl_pitch_align blt     's/ || (pitch \& ADDR_ALIGN_MASK) != 0//'
mutate bl_disjoint    blt     's/return ax2 <= bx1 || bx2 <= ax1 || ay2 <= by1 || by2 <= ay1/return true/'
mutate bt_noflush     blit    's/let total: u64 = n + blt.flush((\*b).buf + n \* 4, (\*b).scratch)/let total: u64 = n/'
mutate bt_fill_count  blit    's/(\*b).fills = (\*b).fills + 1//'
mutate bt_copy_count  blit    's/(\*b).copies = (\*b).copies + 1//'
mutate bt_reject_cnt  blit    's/(\*b).rejects = (\*b).rejects + 1//'
mutate bt_error_cnt   blit    's/(\*b).errors = (\*b).errors + 1//'
mutate bt_surface_ok  blit    's/return (\*s).ggtt != 0 \&\& ((\*s).ggtt \& ADDR_ALIGN_MASK) == 0/return true/'
mutate bt_overlap     blit    's/if (\*d).ggtt == (\*src).ggtt \&\& !blt.rects_disjoint/if false \&\& !blt.rects_disjoint/'
mutate bt_src_check   blit    's/ || !blt.rect_ok((\*src).pitch, (\*src).bytes, sx, sy, sx + w, sy + h)//'
mutate bp_full_reset  blitpool 's/ \&\& (value \& ~engregs.GRDOM_BLT) == 0//'
mutate bp_layout_ctx  blitpool 's/CTX_AT: u64 = 0x1000/CTX_AT: u64 = 0x2000/'
mutate bp_scratch     blitpool 's/SCRATCH_OFFSET: u64 = 0x440/SCRATCH_OFFSET: u64 = 0x400/'
mutate bp_forcewake   blitpool 's/if off == engregs.FORCEWAKE_GT {/if off == engregs.FORCEWAKE_RENDER {/'
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
ORACLE=tools/intelgpu/rcs.fi
mutate rp_arb_op      rcsparse 's/MI_ARB_ON_OFF: u64 = 0x08/MI_ARB_ON_OFF: u64 = 0x09/'
mutate rp_bbe_op      rcsparse 's/MI_BATCH_BUFFER_END: u64 = 0x0a/MI_BATCH_BUFFER_END: u64 = 0x0b/'
mutate rp_sba_client  rcsparse 's/return mode == MODE_KERNEL/return true/'
mutate rp_pc_post     rcsparse 's/return (octets.ld32(batch, (at + 1) \* DWORD) \& PIPE_CONTROL_POST_SYNC_MASK) != 0/return false/'
mutate rp_pc_kernel   rcsparse 's/if class != GFX_PIPE_CONTROL || mode == MODE_KERNEL {/if class != GFX_PIPE_CONTROL {/'
mutate rp_len_bias    rcsparse 's/GFX_LEN_BIAS: u64 = 2/GFX_LEN_BIAS: u64 = 1/'
mutate rp_psel_len    rcsparse 's/    if class == GFX_PIPELINE_SELECT {/    if false {/'
mutate rp_trunc       rcsparse 's/            if at + len > dwords {/            if false {/'
mutate rp_range       rcsparse 's/ || dwords > MAX_DWORDS//'
mutate rp_cap         rcsparse 's/if packets >= MAX_PACKETS {/if false {/'
mutate rp_mi_gate     rcsparse 's/            if !mi_single(op) {/            if false {/'
mutate rp_aux_class   rcsparse 's/class == GFX_STATE_AUX || //'
mutate rp_count       rcsparse 's/return finish(res, packets + 1, at + 1, W_OK)/return finish(res, packets, at + 1, W_OK)/'
mutate rp_words       rcsparse 's/octets.st64(res, R_WORDS, at)/octets.st64(res, R_WORDS, 0)/'
mutate rp_bad_at      rcsparse 's/octets.st64(res, R_BAD_AT, at)/octets.st64(res, R_BAD_AT, 0)/'
mutate rp_no_end      rcsparse 's/    return finish(res, packets, at, W_NO_END)/    return finish(res, packets, at, W_OK)/'
mutate rp_len_mask    rcsparse 's/GFX_LEN_MASK: u64 = 0xff/GFX_LEN_MASK: u64 = 0x7f/'
mutate rp_blitter     rcsparse 's/TYPE_GFX: u64 = 3/TYPE_GFX: u64 = 2/'
ORACLE=tools/intelgpu/vblank.fi
mutate vb_frm_off     vblank 's/FRMCOUNT_A: u64 = 0x70040/FRMCOUNT_A: u64 = 0x70044/'
mutate vb_stride      vblank 's/PIPE_STRIDE: u64 = 0x1000/PIPE_STRIDE: u64 = 0x2000/'
mutate vb_master_bit  vblank 's/MASTER_PIPE_SHIFT: u64 = 16/MASTER_PIPE_SHIFT: u64 = 15/'
mutate vb_imr_off     vblank 's/IMR_OFFSET: u64 = 4/IMR_OFFSET: u64 = 8/'
mutate vb_ier_off     vblank 's/IER_OFFSET: u64 = 12/IER_OFFSET: u64 = 8/'
mutate vb_wrap        vblank 's/(frame_count(rd, pipe) + FRMCOUNT_SPAN - start)/(frame_count(rd, pipe) + FRMCOUNT_SPAN - start - 1)/'
mutate vb_noimr       vblank 's/    wr(pipe_imr(pipe), rd(pipe_imr(pipe)) \& (~PIPE_VBLANK) \& ALL_BITS)//'
mutate vb_noier       vblank 's/    wr(pipe_ier(pipe), rd(pipe_ier(pipe)) | PIPE_VBLANK)//'
mutate vb_nomaster    vblank 's/    wr(MASTER_IRQ, rd(MASTER_IRQ) | MASTER_ENABLE)//'
mutate vb_clobber_imr vblank 's/rd(pipe_imr(pipe)) \& (~PIPE_VBLANK) \& ALL_BITS)/0)/'
mutate vb_noargs      vblank 's/    if !valid(pipe) || frames == 0 {/    if false {/'
mutate vb_pend_master vblank 's/    if (rd(MASTER_IRQ) \& master_pipe_bit(pipe)) == 0 {/    if false {/'
mutate vb_status_bit  vblank 's/PIPE_VBLANK: u64 = 1$/PIPE_VBLANK: u64 = 2/'
mutate vb_dis_ier     vblank 's/    wr(pipe_ier(pipe), rd(pipe_ier(pipe)) \& (~PIPE_VBLANK) \& ALL_BITS)//'
mutate vb_pipes       vblank 's/MAX_PIPES: u64 = 3/MAX_PIPES: u64 = 4/'
mutate vb_ack_noop    vblank 's/^    wr(pipe_iir(pipe), PIPE_VBLANK)\n    return V_OK$/    return V_OK/;/^fn irq_ack/,/^}/{s/    wr(pipe_iir(pipe), PIPE_VBLANK)//}'
ORACLE=tools/intelgpu/ppgtt.fi
mutate pp_pwt         ppgtt 's/PPAT_UNCACHED: u64 = 0x18/PPAT_UNCACHED: u64 = 0x08/'
mutate pp_wt          ppgtt 's/PPAT_WT: u64 = 0x10/PPAT_WT: u64 = 0x08/'
mutate pp_wb          ppgtt 's/PPAT_WB: u64 = 0x80/PPAT_WB: u64 = 0x40/'
mutate pp_readonly    ppgtt 's/        pte = pte \& (~RW)/        pte = pte/'
mutate pp_phys_mask   ppgtt 's/PTE_PHYS_MASK: u64 = 0x7ffffff000/PTE_PHYS_MASK: u64 = 0xfffffffff000/'
mutate pp_pdp_shift   ppgtt 's/PDP_SHIFT: u64 = 30/PDP_SHIFT: u64 = 29/'
mutate pp_pd_shift    ppgtt 's/PD_SHIFT: u64 = 21/PD_SHIFT: u64 = 20/'
mutate pp_pt_shift    ppgtt 's/PT_SHIFT: u64 = 12/PT_SHIFT: u64 = 13/'
mutate pp_limit       ppgtt 's/VA_LIMIT: u64 = 0x100000000/VA_LIMIT: u64 = 0x200000000/'
mutate pp_pd_fill     ppgtt 's/        fill(pd, scratch_pde_pt(st))//'
mutate pp_exists      ppgtt 's/    if octets.ld64(at, 0) != scratch_pte(st) {/    if false {/'
mutate pp_nomem       ppgtt 's/    if used >= slot(st, S_POOL_PAGES) {/    if false {/'
mutate pp_unmap_clear ppgtt 's/    octets.st64(at, 0, scratch_pte(st))/    octets.st64(at, 0, 0)/'
mutate pp_count       ppgtt 's/    octets.st64(st, S_MAPPED, slot(st, S_MAPPED) + 1)//'
mutate pp_uncount     ppgtt 's/    octets.st64(st, S_MAPPED, slot(st, S_MAPPED) - 1)//'
mutate pp_ensure      ppgtt 's/    if pt != slot(st, S_SCRATCH_PT) {/    if true {/'
mutate pp_pt_fill     ppgtt 's/    fill(fresh, scratch_pte(st))//'
mutate pp_audit_pool  ppgtt 's/ || in_pool(st, pte \& PTE_PHYS_MASK)//'
mutate pp_audit_win   ppgtt 's/ || allowed(pte \& PTE_PHYS_MASK) == 0//'
mutate pp_audit_pde   ppgtt 's/ || !in_pool(st, pt)//'
mutate pp_ctx_ldw     ppgtt 's/CTX_LDW_AFTER_UDW: u64 = 2/CTX_LDW_AFTER_UDW: u64 = 1/'
mutate pp_ctx_step    ppgtt 's/CTX_PDP_STEP: u64 = 4/CTX_PDP_STEP: u64 = 2/'
mutate pp_ctx_low     ppgtt 's/ADDR_LOW_MASK: u64 = 0xffffffff/ADDR_LOW_MASK: u64 = 0xfffff/'
mutate pp_cache_range ppgtt 's/ || cache > CACHE_WB//'
mutate pp_va_align    ppgtt 's/ \&\& (va \& PAGE_MASK) == 0 \&\& (phys/ \&\& (phys/'
mutate pp_phys_align  ppgtt 's/ \&\& (phys \& PAGE_MASK) == 0 \&\& phys <=/ \&\& phys <=/'
mutate pp_phys_limit  ppgtt 's/ \&\& phys <= PTE_PHYS_MASK$//'
mutate pp_min_pool    ppgtt 's/ || pool_pages < MIN_POOL_PAGES//'
mutate pp_pool_align  ppgtt 's/ || (pool \& PAGE_MASK) != 0//'
mutate pp_pdp_range   ppgtt 's/    if n >= PDP_COUNT {/    if false {/'
ORACLE=tools/intelgpu/display.fi
mutate fd_bit       flipdone 's/FLIP_DONE_BIT: u64 = 8/FLIP_DONE_BIT: u64 = 16/'
mutate fd_cnt_off   flipdone 's/FLIPCOUNT_A: u64 = 0x70044/FLIPCOUNT_A: u64 = 0x70048/'
mutate fd_stamp_off flipdone 's/FLIPTMSTMP_A: u64 = 0x7004c/FLIPTMSTMP_A: u64 = 0x70050/'
mutate fd_moved     flipdone 's/COUNT_MASK) != 0 {/COUNT_MASK) > 1 {/'
mutate fd_noack     flipdone 's/^            ack(wr, pipe)$//'
mutate fd_master    flipdone 's/    if (rd(vblank.MASTER_IRQ) \& vblank.master_pipe_bit(pipe)) == 0 {/    if false {/'
mutate fd_noimr     flipdone 's/    wr(vblank.pipe_imr(pipe), rd(vblank.pipe_imr(pipe)) \& (~FLIP_DONE_BIT) \& ALL_BITS)//'
mutate fd_noier     flipdone 's/    wr(vblank.pipe_ier(pipe), rd(vblank.pipe_ier(pipe)) | FLIP_DONE_BIT)//'
mutate fd_pipes     flipdone 's/    return pipe < vblank.MAX_PIPES/    return pipe < 4/'
mutate pc_period    pace     's/MHZ_TO_PERIOD_US \/ refresh_mhz/MHZ_TO_PERIOD_US \/ (refresh_mhz + 1000)/'
mutate pc_fifo      pace     's/    if (\*p).mode == MODE_FIFO {/    if false {/'
mutate pc_drop      pace     's/    (\*p).dropped = (\*p).dropped + 1//'
mutate pc_missed    pace     's/(\*p).missed = (\*p).missed + gap - 1/(*p).missed = (*p).missed + gap/'
mutate pc_busy      pace     's/    (\*p).busy = false/    (*p).busy = true/'
mutate pc_late      pace     's/return wait_us(p, since_vblank_us) < budget_us/return false/'
mutate pc_refresh   pace     's/MAX_REFRESH_MHZ: u64 = 500000/MAX_REFRESH_MHZ: u64 = 900000/'
mutate ml_vic       modelist 's/if vic == 95 {/if vic == 96 {/'
mutate ml_rb_fp     modelist 's/RB_H_FPORCH: u64 = 48/RB_H_FPORCH: u64 = 40/'
mutate ml_clock     modelist 's/RB_CLOCK_STEP_KHZ: u64 = 250/RB_CLOCK_STEP_KHZ: u64 = 1/'
mutate ml_dedupe    modelist 's/    if n >= cap || known(list, n, m) {/    if n >= cap {/'
mutate ml_link      modelist 's/return pclk_khz \* bpp \/ BPP_DIV <= lanes \* symbol_khz/return true/'
mutate ml_cdclk     modelist 's/MAX_CDCLK_KHZ: u64 = 675000/MAX_CDCLK_KHZ: u64 = 700000/'
mutate ml_pref      modelist 's/    if n > 0 \&\& fits(list, 0, max_w, max_h, max_pclk) {/    if false {/'
mutate ml_aspect    modelist 's/ASPECT_16_10: u64 = 0/ASPECT_16_10: u64 = 5/'
mutate ml_vsync     modelist 's/^        return 7$/        return 8/'
mutate ml_est       modelist 's/(octets.ld8(p, O_ESTABLISHED + 1) \& 0x08) != 0/(octets.ld8(p, O_ESTABLISHED + 1) \& 0x10) != 0/'
mutate ml_blocks    modelist 's/MAX_BLOCKS: u64 = 4/MAX_BLOCKS: u64 = 8/'
mutate ml_cta_tag   modelist 's/CTA_TAG: u64 = 0x02/CTA_TAG: u64 = 0x70/'
mutate ml_dtd       edid     's/hact + hso + hsw/hact + hso/'
mutate ol_hpd_b     outputs  's/SDE_B_BIT: u64 = 21/SDE_B_BIT: u64 = 20/'
mutate ol_hpd_e     outputs  's/SDE_E_BIT: u64 = 25/SDE_E_BIT: u64 = 24/'
mutate ol_hpd_a     outputs  's/DE_PORT_A_BIT: u64 = 3/DE_PORT_A_BIT: u64 = 4/'
mutate ol_debounce  outputs  's/DEBOUNCE_SAMPLES: u64 = 3/DEBOUNCE_SAMPLES: u64 = 2/'
mutate ol_max       outputs  's/OUT_MAX: u64 = 3/OUT_MAX: u64 = 4/'
mutate ol_extend_x  outputs  's/        x = x + m.hactive/        x = x + 0/'
mutate ol_fbw       outputs  's/    if right > max_fb_w {/    if false {/'
mutate ol_fbh       outputs  's/    if bottom > max_fb_h {/    if false {/'
mutate ol_clk       outputs  's/        if !modelist.cdclk_ok(m.pclk_khz) {/        if false {/'
mutate ol_nomode    outputs  's/        if field(t, i, F_MODE) == modelist.NONE {/        if false {/'
mutate ol_mirror    outputs  's/        if area > best_area \&\& /        if area > 0 \&\& /'
mutate ol_port_e    outputs  's/PORT_E: u64 = 4/PORT_E: u64 = 5/'
ORACLE=tools/intelgpu/rcsrun.fi
mutate rb_prim_len  rcsbatch 's/PRIMITIVE: u64 = 0x7b000005/PRIMITIVE: u64 = 0x7b000004/'
mutate rb_topo      rcsbatch 's/TOPO_TRILIST: u64 = 4/TOPO_TRILIST: u64 = 5/'
mutate rb_stride    rcsbatch 's/ || stride == 0//'
mutate rb_rect      rcsbatch 's/w <= RECT_MAX \&\& //'
mutate rb_vb_hdr    rcsbatch 's/VERTEX_BUFFERS: u64 = 0x78080003/VERTEX_BUFFERS: u64 = 0x78080002/'
mutate rb_cap       rcsbatch 's/MAX_BATCH_DWORDS: u64 = 32/MAX_BATCH_DWORDS: u64 = 8/'
mutate rr_walk      rcsrun   's/    if rcsparse.walk((\*b).cpu, (\*b).dwords, rcsparse.MODE_CLIENT, (\*b).walk) != rcsparse.W_OK {/    if false {/'
mutate rr_align     rcsrun   's/    if ((\*b).ggtt \& ADDR_ALIGN_MASK) != 0 {/    if false {/'
mutate rr_op        rcsrun   's/OP_BATCH_BUFFER_START: u64 = 0x31/OP_BATCH_BUFFER_START: u64 = 0x30/'
mutate rr_fw        rcsrun   's/^    fwake.put(rd, wr, us, engregs.FORCEWAKE_RENDER, engregs.FORCEWAKE_ACK_RENDER)$//'
mutate rr_hi        rcsrun   's/octets.st32(out, 8, ggtt >> ADDR_HIGH_SHIFT)/octets.st32(out, 8, 0)/'
mutate rr_rcs_base  engregs  's/RCS_BASE: u64 = 0x2000/RCS_BASE: u64 = 0x2400/'
ORACLE=tools/intelgpu/oracle.fi

echo "INTELGPU: $pass passed, $fail failed"
[ "$fail" = 0 ]
