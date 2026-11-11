#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
. tools/lib/userprog.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
. tools/lib/firnenv.sh
ULD=kernel/user/user.ld
PROGS="sh vdec"

TMPD=$(mktemp -d)
. tools/lib/summary.sh; summary_begin VIDEO
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
for w in ffmpeg ffprobe python3 sha256sum qemu-system-x86_64; do
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
MKARGS=""
for p in $PROGS; do
    if up_build "$FIRNC" "$p" "$TMPD/$p.o" "$TMPD/$p.elf" "$TMPD/crt.o" "$ULD" 0 "$TMPD/e$p"; then
        MKARGS="$MKARGS /bin/$p=$TMPD/$p.elf"
    else
        bad "$p does not build"; grep -viE 'GNU-stack|RWX' "$TMPD/e$p" | head -8 | sed 's/^/        /'
    fi
done
ok "programs built: $PROGS"

echo "== 2. test material from the host (ffmpeg + x264) =="
MED="$TMPD/m"
bash tools/video/mkmedia.sh "$MED" > "$TMPD/med.log" 2>&1 \
    && ok "$(tail -1 "$TMPD/med.log")" \
    || { bad "mkmedia.sh failed"; tail -5 "$TMPD/med.log" | sed 's/^/        /'; summary_emit "$pass" "$fail" 0; exit 1; }

python3 - "$MED/av.mov" "$MED/p_moov_end.mp4" "$TMPD" <<'EOF'
import sys, struct, random
av, mp4, out = sys.argv[1:4]
d = bytearray(open(mp4, 'rb').read())
def find(buf, kind, start, end):
    p = start
    while p + 8 <= end:
        size = struct.unpack('>I', buf[p:p+4])[0]
        if buf[p+4:p+8] == kind:
            return p, size
        if size < 8: break
        p += size
    return None
moov = find(d, b'moov', 0, len(d))
def inner(buf, path, start, end):
    for k in path:
        r = find(buf, k, start, end)
        if r is None: return None
        start, end = r[0] + 8, r[0] + r[1]
    return start, end
trak = inner(d, [b'trak', b'mdia', b'minf', b'stbl'], moov[0] + 8, moov[0] + moov[1])
stco = find(d, b'stco', trak[0], trak[1])
p = stco[0] + 16
v = struct.unpack('>I', d[p:p+4])[0]
d[p:p+4] = struct.pack('>I', v + 7)
open(out + '/stco_shifted.mp4', 'wb').write(d)
EOF
[ -s "$TMPD/stco_shifted.mp4" ] && ok "a copy with a shifted chunk offset exists (counter-proof material)" || bad "stco patch failed"

echo "== 3. root disk =="
FILES=""
for f in "$MED"/*.mp4 "$MED"/*.mov "$TMPD"/stco_shifted.mp4; do
    FILES="$FILES /v/$(basename "$f")=$f"
done
head -c 300 "$MED/p_moov_end.mp4" > "$TMPD/cut_head.mp4"
sz=$(stat -c%s "$MED/p_moov_end.mp4")
head -c $((sz / 2)) "$MED/p_moov_end.mp4" > "$TMPD/cut_half.mp4"
sz2=$(stat -c%s "$MED/p_faststart.mp4")
head -c $((sz2 * 6 / 10)) "$MED/p_faststart.mp4" > "$TMPD/cut_fast.mp4"
head -c 4096 /dev/urandom > "$TMPD/garbage.mp4"
for f in cut_head cut_half cut_fast garbage; do FILES="$FILES /v/$f.mp4=$TMPD/$f.mp4"; done
python3 - "$MED/p_moov_end.mp4" "$TMPD" <<'EOF'
import sys, random
src, out = sys.argv[1:3]
d = open(src, 'rb').read()
for seed in range(1, 13):
    r = random.Random(seed)
    b = bytearray(d)
    for _ in range(6):
        i = r.randrange(len(b) - 1500, len(b))
        b[i] ^= 1 << r.randrange(8)
    open('%s/flip%d.mp4' % (out, seed), 'wb').write(b)
EOF
for s in 1 2 3 4 5 6 7 8 9 10 11 12; do FILES="$FILES /v/flip$s.mp4=$TMPD/flip$s.mp4"; done
bash tools/mkfsfi/mkfs.sh build "$TMPD/root.img" 32768 --inodes=128 /bin/ /v/ $MKARGS $FILES \
    > "$TMPD/mkfs.log" 2>&1 \
    && ok "root disk ready" \
    || { bad "mkfs failed"; tail -5 "$TMPD/mkfs.log" | sed 's/^/        /'; }

run_guest() {
    local name=$1 path=$2 t=${3:-240}
    cp --sparse=always "$TMPD/root.img" "$TMPD/live-$name.img"
    local cpuarg=""
    [ "$OSUM_QEMU_ACCEL" = kvm ] && cpuarg="-cpu host"
    # shellcheck disable=SC2086
    timeout "$t" $QEMU_X86 $cpuarg -kernel "$TMPD/k.mb" -m 512 \
        -append "osum nokbd script=vdec $path" \
        -serial "file:$TMPD/$name.txt" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" >/dev/null 2>&1
    echo $?
    rm -f "$TMPD/live-$name.img"
}

echo "== 4. video: every frame against ffmpeg, the sample table against ffprobe =="
total=0; equal=0
while read -r name w h nf ext; do
    rc=$(run_guest "$name" "/v/$name.$ext")
    D="$TMPD/$name.txt"
    if [ "$rc" != 21 ]; then bad "[$name] kernel did not exit by itself (rc=$rc)"; continue; fi
    python3 tools/codec/mkyuvsha.py "$MED/$name.yuv" "$w" "$h" > "$TMPD/$name.want" 2>/dev/null
    all=1
    while read -r i want; do
        total=$((total+1))
        got=$(grep -a -m1 "^vdec: sha $i = " "$D" | sed 's/.* = //' | tr -d '\r\000')
        if [ "$got" = "$want" ]; then equal=$((equal+1)); else all=0
            printf '        frame %s want %s got %s\n' "$i" "$want" "${got:-(missing)}"; fi
    done < "$TMPD/$name.want"
    fr=$(val "$D" frames); er=$(val "$D" err); me=$(val "$D" merr)
    if [ "$all" = 1 ] && [ "$fr" = "$nf" ] && [ "$er" = 0 ] && [ "$me" = 0 ]; then
        ok "[$name] ${w}x${h}, $fr frames bit-identical, $(val "$D" ms) ms"
    else
        bad "[$name] frames=$fr of $nf err=$er merr=$me"
    fi
    if python3 tools/video/check_table.py "$MED/$name.$ext" "$D" > "$TMPD/$name.tab" 2>&1; then
        ok "[$name] sample table = ffprobe ($(tail -1 "$TMPD/$name.tab"))"
    else
        bad "[$name] sample table differs from ffprobe"; head -4 "$TMPD/$name.tab" | sed 's/^/        /'
    fi
done < "$MED/list.txt"
same "all frames of all clips" "$total" "$equal"

echo "== 5. audio: PCM bytes against ffmpeg =="
rc=$(run_guest av "/v/av.mov")
same "[av] kernel exits" "21" "$rc"
want=$(sha256sum < "$MED/av.pcm" | cut -d' ' -f1)
same "[av] PCM hash" "$want" "$(val "$TMPD/av.txt" asha)"
same "[av] PCM bytes" "$(stat -c%s "$MED/av.pcm")" "$(val "$TMPD/av.txt" abytes)"
grep -aq '^vdec: audio 22050 2 16 1 ' "$TMPD/av.txt" && ok "[av] audio track: 22050 Hz, 2 ch, 16 bit, PCM LE" || bad "[av] audio track line wrong"
rc=$(run_guest ao "/v/audio_only.mov")
same "[audio_only] kernel exits" "21" "$rc"
want=$(sha256sum < "$MED/audio_only.pcm" | cut -d' ' -f1)
same "[audio_only] PCM hash" "$want" "$(val "$TMPD/ao.txt" asha)"
same "[audio_only] no video frames reported" "" "$(val "$TMPD/ao.txt" frames)"

echo "== 6. counter-proofs and rejects =="
rc=$(run_guest shifted "/v/stco_shifted.mp4")
python3 tools/codec/mkyuvsha.py "$MED/p_moov_end.yuv" 176 144 > "$TMPD/shift.want" 2>/dev/null
miss=0
while read -r i want; do
    got=$(grep -a -m1 "^vdec: sha $i = " "$TMPD/shifted.txt" | sed 's/.* = //' | tr -d '\r\000')
    [ "$got" = "$want" ] || miss=$((miss+1))
done < "$TMPD/shift.want"
[ "$miss" -gt 0 ] && ok "COUNTER-PROOF: a shifted chunk offset breaks $miss frames (the comparison sees it)" \
    || bad "COUNTER-PROOF: shifted chunk offset not noticed"
if python3 tools/video/check_table.py "$MED/p_moov_end.mp4" "$TMPD/shifted.txt" >/dev/null 2>&1; then
    bad "COUNTER-PROOF: table check accepts a shifted table"
else
    ok "COUNTER-PROOF: table check rejects a shifted table"
fi

rc=$(run_guest high "/v/x_high.mp4")
same "[high] kernel exits" "21" "$rc"
same "[high] High profile rejected (err=2)" "2" "$(val "$TMPD/high.txt" err)"
same "[high] no frame" "0" "$(val "$TMPD/high.txt" frames)"
rc=$(run_guest big "/v/x_big.mp4")
same "[big] kernel exits" "21" "$rc"
same "[big] 1920x1080 rejected (err=4)" "4" "$(val "$TMPD/big.txt" err)"
for f in cut_head cut_half garbage; do
    rc=$(run_guest "$f" "/v/$f.mp4")
    me=$(val "$TMPD/$f.txt" merr)
    if [ "$rc" = 21 ] && { [ "$me" = 2 ] || [ "$me" = 3 ]; }; then ok "[$f] rejected cleanly (merr=$me)"
    else bad "[$f] rc=$rc merr=${me:-none}"; fi
done
rc=$(run_guest cut_fast "/v/cut_fast.mp4")
fr=$(val "$TMPD/cut_fast.txt" frames)
me=$(val "$TMPD/cut_fast.txt" merr)
if [ "$rc" = 21 ] && { [ "$me" = 3 ] || [ "${fr:-0}" -lt 9 ]; }; then ok "[cut_fast] media data cut off: no hang (merr=$me frames=$fr)"
else bad "[cut_fast] rc=$rc merr=${me:-none} frames=${fr:-none}"; fi

echo "== 6b. counter-proof: decoder without the end-of-slice peek fix =="
OLD="$TMPD/old"
mkdir -p "$OLD/kernel"
cp -a kernel/user "$OLD/kernel/user"
python3 - "$OLD/kernel/user/h264.fi" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
a = "    bs_p = save\n    bs_over = save_over\n"
assert a in s
s = s.replace(a, "    bs_p = save\n")
open(p, 'w').write(s)
PYEOF
if (cd "$OLD" && . "$ROOT/tools/lib/userprog.sh" \
    && up_build "$ROOT/$FIRNC" vdec "$TMPD/vold.o" "$TMPD/vold.elf" "$TMPD/crt.o" "$ROOT/$ULD" 0 "$TMPD/evold"); then
    bash tools/mkfsfi/mkfs.sh build "$TMPD/rootold.img" 32768 --inodes=128 /bin/ /v/ \
        /bin/sh="$TMPD/sh.elf" /bin/vdec="$TMPD/vold.elf" /v/p_long.mp4="$MED/p_long.mp4" > "$TMPD/mkfsold.log" 2>&1
    cp --sparse=always "$TMPD/rootold.img" "$TMPD/live-old.img"
    cpuarg=""; [ "$OSUM_QEMU_ACCEL" = kvm ] && cpuarg="-cpu host"
    # shellcheck disable=SC2086
    timeout 240 $QEMU_X86 $cpuarg -kernel "$TMPD/k.mb" -m 512 \
        -append "osum nokbd script=vdec /v/p_long.mp4" \
        -serial "file:$TMPD/old.txt" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        -drive "file=$TMPD/live-old.img,format=raw,if=ide,index=0" >/dev/null 2>&1
    rm -f "$TMPD/live-old.img"
    oerr=$(val "$TMPD/old.txt" err); ofr=$(val "$TMPD/old.txt" frames)
    if [ "${oerr:-0}" = 5 ] && [ "${ofr:-12}" -lt 12 ]; then
        ok "COUNTER-PROOF: without the fix p_long stops at frame $ofr with err=5"
    else
        bad "COUNTER-PROOF: old decoder did not fail (err=${oerr:-none} frames=${ofr:-none})"
    fi
else
    bad "COUNTER-PROOF: old decoder does not build"; head -5 "$TMPD/evold" | sed 's/^/        /'
fi

echo "== 7. corrupted container bytes =="
flip_ok=0; flip_bad=0
for s in 1 2 3 4 5 6 7 8 9 10 11 12; do
    rc=$(run_guest "flip$s" "/v/flip$s.mp4")
    if [ "$rc" = 21 ] && grep -aq '^vdec: done' "$TMPD/flip$s.txt"; then flip_ok=$((flip_ok+1)); else
        flip_bad=$((flip_bad+1)); printf '        flip%s: rc=%s\n' "$s" "$rc"; fi
done
same "corrupted files that end cleanly (of 12)" "12" "$flip_ok"

echo
summary_emit "$pass" "$fail" 36 || exit 1
[ "$fail" = 0 ] || exit 1
exit 0
