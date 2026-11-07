#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
. tools/lib/userprog.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
ULD=kernel/user/user.ld

TMPD=$(mktemp -d)
. tools/lib/summary.sh; summary_begin BFRAMES
trap 'summary_guard; rm -rf "$TMPD"; summary_exit_status || exit 1' EXIT
trap 'exit 1' HUP INT TERM

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
same() {
    if [ "$2" = "$3" ]; then ok "$1"; else
        bad "$1"; printf '        want: %s\n        got : %s\n' "$2" "$3"; fi
}
val() { grep -a -m1 "^vdec: $2 = " "$1" 2>/dev/null | sed 's/.* = //' | tr -d '\r\000'; }

echo "== 0. preconditions =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || { echo "fetch-firnc.sh failed"; exit 1; }
for w in ffmpeg ffprobe python3 qemu-system-x86_64; do
    command -v "$w" >/dev/null 2>&1 || { summary_note "skipped, $w is missing"; exit 0; }
done
ffmpeg -hide_banner -encoders > "$TMPD/enc.txt" 2>/dev/null || true
grep -q libx264 "$TMPD/enc.txt" || { summary_note "skipped, ffmpeg has no libx264"; exit 0; }
ok "host tools are present"

echo "== 1. build =="
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s cannot be assembled"
bash tools/build-kernel.sh "$TMPD/k.mb" --stufe 0 > "$TMPD/k.log" 2>&1 \
    && ok "kernel built" \
    || { bad "kernel build failed"; tail -8 "$TMPD/k.log" | sed 's/^/        /'; summary_emit "$pass" "$fail" 0; exit 1; }
build_prog() {
    local tree=$1 prog=$2 tag=$3
    (cd "$tree" && . "$ROOT/tools/lib/userprog.sh" \
        && up_build "$ROOT/$FIRNC" "$prog" "$TMPD/$tag.o" "$TMPD/$tag.elf" "$TMPD/crt.o" "$ROOT/$ULD" 0 "$TMPD/e$tag")
}
build_prog "$ROOT" sh sh && ok "sh built" || bad "sh does not build"
build_prog "$ROOT" vdec vdec && ok "vdec built" || { bad "vdec does not build"; grep -viE 'GNU-stack|RWX' "$TMPD/evdec" | head -8 | sed 's/^/        /'; }

mutant() {
    local tag=$1 file=$2
    shift 2
    local tree="$TMPD/mut_$tag"
    mkdir -p "$tree/kernel"
    cp -a kernel/user "$tree/kernel/user"
    python3 -I - "$tree/kernel/user/$file" "$@" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
pairs = sys.argv[2:]
for a, b in zip(pairs[::2], pairs[1::2]):
    assert a in s, a
    s = s.replace(a, b)
open(p, 'w').write(s)
PYEOF
    [ $? = 0 ] || { bad "mutant $tag does not apply"; return 1; }
    build_prog "$tree" vdec "v$tag" && ok "mutant $tag built" || { bad "mutant $tag does not build"; return 1; }
}
mutant noreorder h264.fi \
    "if pop_output(s_reorder) { return true }" "if pop_output(0) { return true }" \
    "if r == 1 && pop_output(s_reorder) { return true }" "if r == 1 && pop_output(0) { return true }"
mutant nomsb h264poc.fi "cur_msb = h264b.poc_msb(prev_msb, prev_lsb, cur_lsb, max_lsb)" "cur_msb = 0"
mutant nodefault h264.fi "if s_poctype != 2 { s_reorder = 2 }" "if s_poctype != 2 { s_reorder = 0 }"
mutant nobipred h264.fi "if p_bipred != 2 { return 32 }" "if p_bipred != 3 { return 32 }"
mutant nocolzero h264direct.fi "+ cy * 4 + cx)) as usize] != (0 as u8)" "+ cy * 4 + cx)) as usize] == (7 as u8)"
mutant noc8 h264.fi "if nb8 > cur_b8 {" "if nb8 > 9 {"
mutant nobsmotion h264.fi "if pic_has_b { return bs_motion(mP * 16 + iP, mQ * 16 + iQ) }" ""
mutant nol1order h264refs.fi "len1 = fill_list(1, cur, false)" "len1 = fill_list(1, cur, true)"
mutant nomodify h264.fi \
    "h264refs.refs_modify(sl_frame_num as i64, (1 << s_log2fn) as i64, sl_nref0, 0)" ""
mutant novui h264.fi "        un(32)
        un(32)
        u1()
    }" "        un(32)
        u1()
    }"

echo "== 2. test material from the host (ffmpeg + x264) =="
MED="$TMPD/m"
bash tools/bframes/mkmedia.sh "$MED" > "$TMPD/med.log" 2>&1 \
    && ok "$(tail -1 "$TMPD/med.log")" \
    || { bad "mkmedia.sh failed"; tail -5 "$TMPD/med.log" | sed 's/^/        /'; summary_emit "$pass" "$fail" 0; exit 1; }

echo "== 3. root disk =="
FILES=""
for f in "$MED"/*.mp4; do FILES="$FILES /v/$(basename "$f")=$f"; done
PROGS="/bin/sh=$TMPD/sh.elf /bin/vdec=$TMPD/vdec.elf"
for m in vnoreorder vnodefault vnovui vnomsb vnobipred vnocolzero vnoc8 vnobsmotion vnol1order vnomodify; do
    [ -f "$TMPD/$m.elf" ] && PROGS="$PROGS /bin/$m=$TMPD/$m.elf"
done
bash tools/mkfsfi/mkfs.sh build "$TMPD/root.img" 32768 --inodes=128 /bin/ /v/ $PROGS $FILES \
    > "$TMPD/mkfs.log" 2>&1 \
    && ok "root disk ready" \
    || { bad "mkfs failed"; tail -5 "$TMPD/mkfs.log" | sed 's/^/        /'; }

run_guest() {
    local name=$1 script=$2 t=${3:-240}
    cp --sparse=always "$TMPD/root.img" "$TMPD/live-$name.img"
    local cpuarg=""
    [ "$OSUM_QEMU_ACCEL" = kvm ] && cpuarg="-cpu host"
    # shellcheck disable=SC2086
    timeout "$t" $QEMU_X86 $cpuarg -kernel "$TMPD/k.mb" -m 512 \
        -append "osum nokbd script=$script" \
        -serial "file:$TMPD/$name.txt" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" >/dev/null 2>&1
    echo $?
    rm -f "$TMPD/live-$name.img"
}

echo "== 4. reordered output: every frame and tag =="
while read -r name w h nf ext; do
    case "$name" in ro_*) ;; *) continue ;; esac
    rc=$(run_guest "$name" "vdec /v/$name.$ext main")
    D="$TMPD/$name.txt"
    if [ "$rc" != 21 ]; then bad "[$name] kernel did not exit by itself (rc=$rc)"; continue; fi
    fr=$(val "$D" frames); er=$(val "$D" err)
    if python3 -I tools/bframes/check.py "$D" "$MED/$name.order" "$MED/$name.yuv" "$MED/$name.src.yuv" "$w" "$h" "$MED/$name.meta" > "$TMPD/$name.chk" 2>&1 \
        && [ "$fr" = "$nf" ] && [ "$er" = 0 ]; then
        ok "[$name] $fr frames in display order, bit-identical to ffmpeg ($(tail -1 "$TMPD/$name.chk"))"
    else
        bad "[$name] frames=$fr of $nf err=$er"; tail -3 "$TMPD/$name.chk" | sed 's/^/        /'
    fi
    if python3 -I tools/video/check_table.py "$MED/$name.$ext" "$D" > "$TMPD/$name.tab" 2>&1; then
        ok "[$name] sample table with ctts = ffprobe"
    else
        bad "[$name] sample table differs from ffprobe"; head -3 "$TMPD/$name.tab" | sed 's/^/        /'
    fi
done < "$MED/list.txt"

echo "== 4b. B-slice clips: every frame bit-identical to ffmpeg =="
while read -r name w h nf ext; do
    case "$name" in b_*) ;; *) continue ;; esac
    rc=$(run_guest "$name" "vdec /v/$name.$ext main" 480)
    D="$TMPD/$name.txt"
    if [ "$rc" != 21 ]; then bad "[$name] kernel did not exit by itself (rc=$rc)"; continue; fi
    if python3 -I tools/bframes/checkb.py "$D" "$MED/$name.yuv" "$w" "$h" > "$TMPD/$name.chk" 2>&1 \
        && [ "$(val "$D" err)" = 0 ]; then
        ok "[$name] $(tail -1 "$TMPD/$name.chk")"
    else
        bad "[$name] err=$(val "$D" err) $(tail -1 "$TMPD/$name.chk")"
    fi
done < "$MED/list.txt"

echo "== 5. gate and rejects =="
rc=$(run_guest ro_off "vdec /v/ro_min.mp4")
same "[ro_min without the word] kernel exits" "21" "$rc"
same "[ro_min without the word] Main profile rejected (err=2)" "2" "$(val "$TMPD/ro_off.txt" err)"
same "[ro_min without the word] no frame" "0" "$(val "$TMPD/ro_off.txt" frames)"
rc=$(run_guest b_off "vdec /v/b_main.mp4")
same "[b_main without the word] err=2" "2" "$(val "$TMPD/b_off.txt" err)"

echo "== 6. counter-proofs =="
for m in nobipred nocolzero noc8 nobsmotion nol1order nomodify; do
    clip=b_noise
    [ "$m" = nobipred ] && clip=b_main
    [ "$m" = noc8 ] && clip=b_part
    [ "$m" = nol1order ] && clip=b_pyr
    [ "$m" = nomodify ] && clip=b_pyr
    if [ ! -f "$TMPD/v$m.elf" ]; then bad "COUNTER-PROOF $m: mutant missing"; continue; fi
    rc=$(run_guest "cp_$m" "v$m /v/$clip.mp4 main" 480)
    if python3 -I tools/bframes/checkb.py "$TMPD/cp_$m.txt" "$MED/$clip.yuv" 176 144 >/dev/null 2>&1; then
        bad "COUNTER-PROOF $m: the mutant still passes"
    else
        ok "COUNTER-PROOF $m: the comparison sees the broken decoder"
    fi
done
for m in noreorder nodefault novui nomsb; do
    clip=ro_min
    [ "$m" = nodefault ] && clip=ro_none
    [ "$m" = novui ] && clip=ro_full
    [ "$m" = nomsb ] && clip=ro_wrap
    if [ ! -f "$TMPD/v$m.elf" ]; then bad "COUNTER-PROOF $m: mutant missing"; continue; fi
    rc=$(run_guest "cp_$m" "v$m /v/$clip.mp4 main")
    read -r w h nf ext < <(awk -v n="$clip" '$1==n {print $2, $3, $4, $5}' "$MED/list.txt")
    if python3 -I tools/bframes/check.py "$TMPD/cp_$m.txt" "$MED/$clip.order" "$MED/$clip.yuv" "$MED/$clip.src.yuv" "$w" "$h" "$MED/$clip.meta" >/dev/null 2>&1; then
        bad "COUNTER-PROOF $m: the mutant still passes"
    else
        ok "COUNTER-PROOF $m: the comparison sees the broken decoder"
    fi
done

echo
summary_emit "$pass" "$fail" 27 || exit 1
[ "$fail" = 0 ] || exit 1
exit 0
