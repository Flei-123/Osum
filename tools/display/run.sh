#!/usr/bin/env bash
#
# Usage:  bash tools/display/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/brand.sh
marke_laden . || exit 1
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
. tools/lib/firnenv.sh
firnenv_need_firnc1
FC1=$FIRNC1
ULD=kernel/user/user.ld
BLOCKS=4096
PROGS="sh echo cat ls dispctl"

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

num() { # name value op expected
    if [ -z "${2:-}" ]; then bad "$1: no number found (expected $3 $4)"; return; fi
    if [ "$2" -"$3" "$4" ] 2>/dev/null; then ok "$1: $2"
    else bad "$1: $2, expected $3 $4"; fi
}
same() { if [ "$2" = "$3" ]; then ok "$1 ($3)"; else bad "$1 -- want '$2', got '$3'"; fi; }
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' is missing"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' is there and should not be" || ok "$3"; }

kw() { grep -ao "^disp:.*[ =]$2=[0-9a-fx]*" "$1" 2>/dev/null | head -1 \
       | grep -ao "$2=[0-9a-fx]*" | head -1 | sed 's/.*=//' | tr -d '\r\000'; }
uw()  { grep -a -m1 "^dispctl: $2=" "$1" 2>/dev/null | sed 's/^[^=]*=//' | tr -d '\r\000'; }
uwl() { grep -a "^dispctl: $2=" "$1" 2>/dev/null | tail -1 | sed 's/^[^=]*=//' | tr -d '\r\000'; }

look() { local name=$1; shift; local aus rc
    aus=$(python3 tools/gfx/checkshot.py "$@" 2>&1); rc=$?
    if [ "$rc" -eq 0 ]; then ok "$name ($aus)"; else bad "$name -- $aus"; fi; }
lookno() { local name=$1; shift; local aus rc
    aus=$(python3 tools/gfx/checkshot.py "$@" 2>&1); rc=$?
    if [ "$rc" -ne 0 ]; then ok "$name ($aus)"; else bad "$name -- passed: $aus"; fi; }

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "DISPLAY: skipped, qemu-system-x86_64 is not there"; exit 0
fi

# ============================================== 1. the sources

echo "== 1. the sources: two files, one truth =="

for r in VBE_INDEX VBE_DATA VBE_ID VBE_XRES VBE_YRES VBE_BPP VBE_ENABLE \
         VBE_BANK VBE_VWIDTH VBE_VHEIGHT VBE_XOFF VBE_YOFF \
         VBE_DISABLED VBE_ENABLED VBE_LFB VBE_ID_LO VBE_ID_HI; do
    a=$(grep -aE "^const $r: (u16|u64) = " <(bash tools/structure/srcview.sh kernel/gfx/fb.fi) | sed 's/.*= //; s/ *\/\/.*//')
    b=$(grep -aE "^const $r: (u16|u64) = " kernel/gfx/vmode.fi | sed 's/.*= //; s/ *\/\/.*//')
    if [ -n "$a" ] && [ "$a" = "$b" ]; then ok "$r is the same in fb.fi and vmode.fi ($a)"
    else bad "$r: fb.fi='$a', vmode.fi='$b'"; fi
done
v64=$(grep -aE '^const VBE_VRAM64K' kernel/gfx/vmode.fi | sed 's/.*= //; s/ *\/\/.*//')
same "VBE_VIDEO_MEMORY_64K is index 10 (0x0A)" "10" "$v64"

d1=$(grep -aE '^const DISP_OFF' kernel/lib/kstate.fi | sed 's/.*= //')
d2=$(grep -aE '^const DLUT_OFF' kernel/lib/kstate.fi | sed 's/.*= //')
[ -n "$d1" ] && ok "the kdata side of the mode driver is in kstate.fi: $d1" \
             || bad "DISP_OFF is missing in kernel/lib/kstate.fi"
[ -n "$d2" ] && ok "the kdata side of the lookup table is next to it: $d2" \
             || bad "DLUT_OFF is missing in kernel/lib/kstate.fi"
same "and it directly follows the mode driver" \
    "$(printf '0x%X' $(( $d1 + 0x1000 )))" "$(printf '0x%X' $(( $d2 )))"
foreign=$(grep -ran --include='*.fi' -E '^const SYS_[A-Za-z0-9_]+: u64 = 181[0-9]' kernel/ \
    | grep -v -e '^kernel/sys/sys.fi' -e '^kernel/user/dispctl.fi' \
              -e '^kernel/user/settings.fi' -e '^kernel/user/settings/' -e '^kernel/user/qs.fi' \
              -e '^kernel/user/snip.fi' -e '^kernel/user/wmd.fi' -e '^kernel/user/modeapply.fi' -e '^kernel/user/powerd.fi' -e '^kernel/user/qsmodes.fi' -e '^kernel/user/snipgrab.fi' || true)
[ -z "$foreign" ] && ok "no call number from 1810..1819 lies outside the files of this round" \
                || bad "call numbers from 1810..1819 also appear in: $(echo $foreign | tr '\n' ' ')"
eigen=$(grep -ahE '^const SYS_[A-Za-z0-9_]+: u64 = 181[0-9]' kernel/sys/sys.fi | wc -l | tr -d ' ')
same "kernel/sys/sys.fi holds exactly three numbers from the reserve" "3" "$eigen"

if python3 tools/kernel/memmap.py kernel > "$TMPD/karte.txt" 2>&1; then
    ok "the kdata memory map: $(tail -1 "$TMPD/karte.txt")"
else
    bad "tools/kernel/memmap.py reports collisions"; sed 's/^/        /' "$TMPD/karte.txt" | head -8
fi

# ============================================== 2. build

echo "== 2. the kernel and the programs =="
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || { echo "as fails"; exit 1; }
rc=0
bash tools/build-kernel.sh "$TMPD/k0.mb" > "$TMPD/k0.log" 2>&1 || {
    bad "the kernel cannot be built"; tail -8 "$TMPD/k0.log" | sed 's/^/        /'; rc=1; }
for p in $PROGS; do
    "$FIRNC" "kernel/user/$p.fi" -o "$TMPD/$p.o" > "$TMPD/$p.err" 2>&1 || {
        bad "firnc cannot compile $p.fi"; head -6 "$TMPD/$p.err"; rc=1; continue; }
    ld -T "$ULD" --defsym=USER_ENTRY=_F0.u_start -o "$TMPD/$p.elf" \
        "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null || { bad "ld fails on $p"; rc=1; continue; }
    strip --strip-all "$TMPD/$p.elf"
done
[ "$rc" = 0 ] && ok "the kernel and $(echo $PROGS | wc -w) programs are built"
[ -f "$TMPD/k0.mb" ] || { echo "DISPLAY: nothing goes on without the kernel"; echo "DISPLAY: $pass passed, $((fail+1)) failed"; exit 1; }

UPROF=""; UCRT="$TMPD/crt.o"
grep -qa '^profile app' kernel/user/settings.fi && { UPROF=--profile=app; UCRT=""; }
if "$FIRNC" $UPROF -c kernel/user/settings.fi -o "$TMPD/eins.o" > "$TMPD/eins.err" 2>&1 \
    && ld -T "$ULD" --defsym=USER_ENTRY=_F0.u_start -o "$TMPD/eins.elf" \
        $UCRT "$TMPD/eins.o" 2>/dev/null; then
    u=$(nm -u "$TMPD/eins.elf" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
    [ -z "$u" ] && ok "the settings program with the new display page builds cleanly" \
                || bad "settings.elf has undefined symbols: $u"
else
    bad "settings.fi cannot be built"; head -8 "$TMPD/eins.err" | sed 's/^/        /'
fi
for f in locale/de/messages locale/en/messages; do
    hasnot "$f" "kann dieser Kernel ihn nicht wechseln" \
        "the untrue sentence is not in $f"
    hasnot "$f" "this kernel cannot change it" \
        "and not in its English version in $f"
done
grep -v '^\s*//' <(bash tools/structure/catprog.sh kernel/user/settings.fi) > "$TMPD/eins-code.fi"
hasnot "$TMPD/eins-code.fi" "kann dieser Kernel ihn nicht wechseln" \
    "the sentence 'this kernel cannot change it while running' is gone from the program"
has <(bash tools/structure/catprog.sh kernel/user/settings.fi) "SYS_DISPSET" \
    "the settings program really calls the kernel and no longer writes a file"

if bash tools/build-kernel.sh "$TMPD/k1.mb" --stufe 1 > "$TMPD/k1.log" 2>&1; then
    ok "firnc1 builds this round too (the compiler in Firn)"
else
    bad "firnc1 does not build this round"; tail -5 "$TMPD/k1.log" | sed 's/^/        /'
fi

MKARGS=""
for p in $PROGS; do MKARGS="$MKARGS /bin/$p=$TMPD/$p.elf"; done
bash tools/mkfsfi/mkfs.sh build "$TMPD/root.img" "$BLOCKS" /bin/ $MKARGS \
    > "$TMPD/mkfs.log" 2>&1 && ok "the disk is ready: $(tail -1 "$TMPD/mkfs.log")" \
    || bad "mkfs.py fails"

# --------------------------------------------------------------- runs

GRUND="nokbd nosched noproc nofs noring3"

VGA_STD=${VGA_STD:-"-vga std -global VGA.edid=off"}

lauf() { # name cmdline [timelimit]
    local name=$1 zeile=$2 t=${3:-180}
    rm -f "$TMPD/$name.txt"
    timeout "$t" $QEMU_X86 -kernel "$TMPD/k0.mb" -m 256 -append "$zeile" \
        -serial "file:$TMPD/$name.txt" -display none -no-reboot $VGA_STD \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    echo $?
}

RC=0
foto() { # name cmdline
    local name=$1 zeile=$2
    local sock="$TMPD/mon-$name.sock" aus="$TMPD/$name.txt" ppm="$TMPD/$name.ppm"
    rm -f "$aus" "$ppm" "$sock"
    timeout 200 $QEMU_X86 -kernel "$TMPD/k0.mb" -m 256 -append "$zeile" \
        -serial "file:$aus" -display none -no-reboot $VGA_STD \
        -monitor "unix:$sock,server,nowait" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1 &
    local pid=$! i=0
    while [ $i -lt 1500 ]; do
        grep -qa '^fb: hold' "$aus" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1; i=$((i + 1))
    done
    sleep 0.4
    python3 tools/gfx/screenshot.py "$sock" "$ppm" 25 > "$TMPD/$name.shot" 2>&1
    wait "$pid"; RC=$?
    rm -f "$sock"
}

lauf_platte() { # name cmdline
    local name=$1 zeile=$2
    rm -f "$TMPD/$name.txt"
    cp -f "$TMPD/root.img" "$TMPD/live-$name.img"
    timeout 200 $QEMU_X86 -kernel "$TMPD/k0.mb" -m 256 -append "$zeile" \
        -serial "file:$TMPD/$name.txt" -display none -no-reboot $VGA_STD \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    echo $?
}

# ============================================== 3. the list

echo "== 3. the mode list: what QEMU really accepts =="
rc=$(lauf liste "gfx disp $GRUND")
num "the run ends cleanly (21 = the kernel stopped itself)" "$rc" eq 21
L="$TMPD/liste.txt"
vram=$(kw "$L" vram)
num "the card reports its video memory through VBE_VIDEO_MEMORY_64K (KiB)" "$vram" ge 1024
probed=$(kw "$L" probed)
num "candidates were asked, not guessed" "$probed" ge 20
anz=$(grep -a -m1 '^disp: modes ' "$L" | sed 's/.*modes //' | tr -d '\r\000')
num "the list is longer than the two constants of round K7" "$anz" gt 2
num "and shorter than the candidate list -- it was really filtered" "$anz" lt "$probed"
ref=$(kw "$L" refused); tb=$(kw "$L" toobig); um=$(kw "$L" unmappable)
ok "asked $probed · accepted $anz · register rejected $ref · too large for the frame buffer $tb · not mappable $um"
s=$((anz + ref + tb + um))
same "the four numbers add up" "$probed" "$s"
has "$L" "disp:   800x600x 32" "800x600 is in the list (what round K7 could do)"
has "$L" "disp:   1024x768x 32" "1024x768 is in the list (what round K7 could also do)"
has "$L" "disp:   1920x1080x 32" "1920x1080 is in the list (what round K7 could NOT do)"
n_out=$(grep -ac '^disp: out ' "$L")
same "every excluded candidate is reported with a reason" "$((ref + tb + um))" "$n_out"
lim=$(kw "$L" maplimit)
num "this kernel's limit (eight 2 MiB window slots) is given as a number" "$lim" ge 4194304
st=$(grep -ao 'disp: selftest [0-9]*' "$L" | head -1 | grep -o '[0-9]*$')
same "the mode driver's promises about itself" "15" "$st"
st2=$(grep -ao 'fb: selftest2 [0-9]*' "$L" | head -1 | grep -o '[0-9]*$')
same "the promises about rotation, scaling and table" "11" "$st2"
st1=$(grep -ao 'fb: selftest [0-9]*' "$L" | head -1 | grep -o '[0-9]*$')
same "and the thirteen from round K7 are unchanged" "13" "$st1"

# ============================================== 4. EDID

echo "== 4. EDID: what the screen says about itself =="
rc=$(VGA_STD="-vga std" lauf edid "gfx disp dispedid $GRUND")
num "the run ends cleanly" "$rc" eq 21
E="$TMPD/edid.txt"
if grep -qa '^disp: edid ok' "$E"; then
    ok "a valid EDID block was read (id and checksum are right)"
    has "$E" "ven=RHT" "the vendor is in there -- QEMU reports itself as RHT (Red Hat)"
    has "$E" "mod=QEMU Monitor" "and the model name"
    nat=$(grep -ao 'nat=[0-9]*x[0-9]*' "$E" | head -1 | sed 's/nat=//')
    [ -n "$nat" ] && ok "the native resolution from the first timing set: $nat" \
                  || bad "no native resolution in the EDID block"
    roh=$(grep -a -m1 '^disp: edid 0x' "$E" | sed 's/^disp: edid //' | tr -d '\r\000')
    python3 - "$roh" <<'PY' > "$TMPD/edid.chk" 2>&1
import sys, re
b = [int(x, 16) for x in re.findall(r'0x([0-9a-fA-F]+)', sys.argv[1])]
assert len(b) == 128, f"expected 128 octets, got {len(b)}"
assert b[0:8] == [0,255,255,255,255,255,255,0], "the EDID signature is wrong"
assert sum(b) % 256 == 0, f"checksum {sum(b)%256}, expected 0"
m = (b[8] << 8) | b[9]
ven = "".join(chr(64 + ((m >> s) & 31)) for s in (10, 5, 0))
w = b[56] | ((b[58] >> 4) << 8)
h = b[59] | ((b[61] >> 4) << 8)
print(f"{ven} {w}x{h} version {b[18]}.{b[19]}")
PY
    if [ $? -eq 0 ]; then ok "the raw block checks out: $(cat "$TMPD/edid.chk")"
    else bad "the raw EDID block does not add up: $(cat "$TMPD/edid.chk")"; fi
else
    why=$(kw "$E" why)
    ok "no EDID block on this machine, reason $why -- the fallback to the mode list holds"
    num "and the list really carries it" "$(grep -a -m1 '^disp: modes ' "$E" | sed 's/.*modes //')" gt 2
fi

# ============================================== 5. the switch

echo "== 5. the switch at run time, in the picture =="

foto vorher "gfx disp nocursor fbtest fbhold $GRUND"
num "the run ends cleanly" "$RC" eq 21
look "BEFORE: the photo is 800x600" size "$TMPD/vorher.ppm" 800 600
look "BEFORE: field 1 is pure red" area "$TMPD/vorher.ppm" 0 0 100 100 255 0 0
look "BEFORE: the text line is pixel-exact" \
    text "$TMPD/vorher.ppm" kernel/gfx/font.fi 14 0 "$MARKE_PRODUKT K7 FRAMEBUFFER 01234"

foto nachher "gfx disp dispbig nocursor fbtest fbhold $GRUND"
num "the run ends cleanly" "$RC" eq 21
N="$TMPD/nachher.txt"
has "$N" "fb: 800x600x32" "the kernel starts in 800x600"
sw=$(grep -a -m1 '^disp: switch 800x600 -> 1024x768' "$N")
[ -n "$sw" ] && ok "the switch is in the recording: $sw" || bad "no switch reported"
rcsw=$(echo "$sw" | grep -ao 'rc=[0-9]*' | sed 's/rc=//')
same "the switch reports success" "0" "$rcsw"
us=$(echo "$sw" | grep -ao 'us=[0-9]*' | sed 's/us=//')
[ -n "$us" ] && ok "it took $us microseconds (register set, remapping, second buffer, redraw)" \
             || bad "no time measured"
look "AFTER: the photo is 1024x768 -- the mode REALLY changed" \
    size "$TMPD/nachher.ppm" 1024 768
look "AFTER: the test image is redrawn, field 1 is red again" \
    area "$TMPD/nachher.ppm" 0 0 100 100 255 0 0
look "AFTER: field 4 is white" area "$TMPD/nachher.ppm" 300 0 100 100 255 255 255
look "AFTER: the text line is pixel-exact in the NEW mode" \
    text "$TMPD/nachher.ppm" kernel/gfx/font.fi 14 0 "$MARKE_PRODUKT K7 FRAMEBUFFER 01234"
look "AFTER: the corner at (1023,767) exists now and is black" \
    pixel "$TMPD/nachher.ppm" 1023 767 0 0 0
lookno "BEFORE this corner did NOT exist" pixel "$TMPD/vorher.ppm" 1023 767 0 0 0

foto zurueck "gfx disp dispbig dispback nocursor fbtest fbhold $GRUND"
num "the run ends cleanly" "$RC" eq 21
Z="$TMPD/zurueck.txt"
has "$Z" "disp: switch 1024x768 -> 800x600" "the way back is in the recording"
swz=$(grep -a -m1 '^disp: sw=' "$Z" | grep -ao 'sw=[0-9]*' | sed 's/sw=//')
same "two switches in one run" "2" "$swz"
look "BACK: the photo is 800x600 again" size "$TMPD/zurueck.ppm" 800 600
look "BACK: and the test image is there again" \
    text "$TMPD/zurueck.ppm" kernel/gfx/font.fi 14 0 "$MARKE_PRODUKT K7 FRAMEBUFFER 01234"

# ============================================== 6. the failure case

echo "== 6. the failure case: no black screen =="
foto schlecht "gfx disp dispbad nocursor fbtest fbhold $GRUND"
num "the run ends cleanly -- the rejected mode does NOT stop the kernel" "$RC" eq 21
S="$TMPD/schlecht.txt"
sb=$(grep -a -m1 '^disp: switch 800x600 -> 4096x4096' "$S")
[ -n "$sb" ] && ok "the attempt is in the recording: $sb" || bad "no attempt reported"
rcb=$(echo "$sb" | grep -ao 'rc=[0-9]*' | sed 's/rc=//')
num "it is rejected (2 = the mode is in no list)" "$rcb" eq 2
has "$S" "panel=800x600" "and the panel is unchanged afterwards"
fb_=$(grep -a -m1 '^disp: sw=' "$S" | grep -ao 'fail=[0-9]*' | sed 's/fail=//')
num "the counter of rejected switches is set" "$fb_" ge 1
swb=$(grep -a -m1 '^disp: sw=' "$S" | grep -ao 'sw=[0-9]*' | sed 's/sw=//')
same "and NO switch took place" "0" "$swb"
look "the photo is 800x600 -- the video mode is still there" size "$TMPD/schlecht.ppm" 800 600
look "field 1 is red -- the screen is NOT black" \
    area "$TMPD/schlecht.ppm" 0 0 100 100 255 0 0
look "and the text line is pixel-exact, as if nothing had happened" \
    text "$TMPD/schlecht.ppm" kernel/gfx/font.fi 14 0 "$MARKE_PRODUKT K7 FRAMEBUFFER 01234"
lookno "a black screen would have no red here" \
    area "$TMPD/schlecht.ppm" 0 0 100 100 0 0 0

# ============================================== 7. the deadline

echo "== 7. the confirmation question: whoever says nothing gets the old mode =="
rc=$(lauf frist "gfx disp dispconfirm $GRUND" 260)
num "the run ends cleanly" "$rc" eq 21
F="$TMPD/frist.txt"
has "$F" "disp: switch 800x600 -> 1024x768" "it switched"
cf1=$(grep -a -m1 '^disp: confirm pend=' "$F" | grep -ao 'pend=[0-9]*' | sed 's/pend=//')
same "afterwards a deadline is open" "1" "$cf1"
left=$(grep -a -m1 '^disp: confirm pend=' "$F" | grep -ao 'left=[0-9]*' | sed 's/left=//')
num "and it counts down in seconds (15, like Windows)" "$left" ge 14
cf2=$(grep -a -m2 '^disp: confirm pend=' "$F" | tail -1)
p2=$(echo "$cf2" | grep -ao 'pend=[0-9]*' | sed 's/pend=//')
a2=$(echo "$cf2" | grep -ao 'after=[0-9]*' | sed 's/after=//')
same "after it runs out the deadline is gone" "0" "$p2"
same "and the kernel switched back by ITSELF" "1" "$a2"
case "$cf2" in
    *panel=800x600*) ok "the table is back on the old mode" ;;
    *) bad "the table is not back on 800x600: $cf2" ;;
esac
rv=$(grep -a -m1 '^disp: sw=' "$F" | grep -ao 'rev=[0-9]*' | sed 's/rev=//')
num "the counter of reversions is set" "$rv" ge 1

# ============================================== 8. the rotation

echo "== 8. the rotation: in the picture and not only in the number =="
foto dreh "gfx disp disprot nocursor fbtest fbhold $GRUND"
num "the run ends cleanly" "$RC" eq 21
D="$TMPD/dreh.txt"
has "$D" "disp: rot=90" "the kernel reports the quarter turn"
has "$D" "img=600x800" "the IMAGE is 600x800 afterwards ..."
has "$D" "panel=800x600" "... and the PANEL stays 800x600"
look "the photo is 800x600 -- the rotation happens while transferring, not in the card" \
    size "$TMPD/dreh.ppm" 800 600
look "field 1 (red) is at the top right after the rotation" \
    pixel "$TMPD/dreh.ppm" 749 50 255 0 0
look "field 2 (green) is below it" pixel "$TMPD/dreh.ppm" 749 150 0 255 0
lookno "and it is not at the top left, where it would be UNROTATED" \
    pixel "$TMPD/dreh.ppm" 50 50 255 0 0

# ============================================== 9. the cost

echo "== 9. the cost of the conversion, measured =="
rc=$(lauf kosten "gfx disp dispbench $GRUND" 260)
num "the run ends cleanly" "$rc" eq 21
B="$TMPD/kosten.txt"
bz=$(grep -a -m1 '^disp: bench [0-9]' "$B")
[ -n "$bz" ] && ok "measured: $bz" || bad "no measurement"
px=$(echo "$bz" | grep -ao 'px=[0-9]*' | sed 's/px=//')
d_fl=$(echo "$bz" | grep -ao 'flush=[0-9]*' | sed 's/flush=//')
d_lu=$(echo "$bz" | grep -ao 'lut=[0-9]*' | sed 's/lut=//')
d_ln=$(echo "$bz" | grep -ao 'lutline=[0-9]*' | sed 's/lutline=//')
d_ro=$(echo "$bz" | grep -ao 'rot90=[0-9]*' | sed 's/rot90=//')
num "measured at the LARGEST resolution of the list (pixels)" "$px" ge 1000000
num "the fast path of round K7 is still there (microseconds per frame)" "$d_fl" gt 0
num "the lookup table costs more than the fast path" "$d_lu" gt "$d_fl"
num "a TEXT LINE through the table costs clearly less than a full frame" \
    "$d_ln" lt "$((d_lu / 4))"
num "the quarter turn costs a full frame" "$d_ro" gt 0
ok "per pixel: flush $((d_fl * 1000 / px)) ns · table $((d_lu * 1000 / px)) ns · rotation $((d_ro * 1000 / px)) ns (QEMU/TCG, no KVM)"

# ============================================== 10. ring 3

echo "== 10. the same numbers from ring 3, via 1800..1802 =="
rc=$(VGA_STD="-vga std" lauf_platte ring3 "osum gfx disp nokbd nosched noproc script=dispctl test;dispctl raw")
num "the run with /bin/dispctl ends cleanly" "$rc" eq 21
R="$TMPD/ring3.txt"
has "$R" "osum\$ dispctl" "the program has started"
t3=$(grep -ao 'dispctl: test [0-9]*' "$R" | head -1 | grep -o '[0-9]*$')
same "the promises from ring 3" "12" "$t3"
wig=$(grep -aE '^const WIG_BASE' kernel/sys/sys.fi | sed 's/.*= //')
dg=$(grep -aE '^const SYS_OSUM_DISPGET' kernel/sys/sys.fi | sed 's/.*= //')
if [ "$dg" -gt "$((wig + 9))" ]; then
    ok "the call numbers of this round ($dg..) lie behind the widget block ($wig..$((wig+9)))"
else
    bad "the call numbers collide with WIG_BASE: disp=$dg, wig=$wig"
fi

for f in vram:vram maplimit:maplimit probed:probed refused:refused toobig:toobig; do
    kn=${f%%:*}; un=${f##*:}
    a=$(kw "$L" "$kn"); b=$(uw "$R" "$un")
    if [ "$kn" = vram ]; then a=$((a * 1024)); fi
    same "$kn: the kernel message and ring 3 say the same" "$a" "$b"
done
u_anz=$(uw "$R" count)
same "also the length of the list" "$anz" "$u_anz"
#
k_panel=$(grep -ao '^disp: own .* panel=[0-9]*x[0-9]*' "$R" 2>/dev/null \
    | tail -1 | grep -ao 'panel=[0-9]*' | sed 's/panel=//')
[ -n "$k_panel" ] || k_panel=$(grep -ao '^fb: [0-9]*x[0-9]*' "$R" 2>/dev/null \
    | head -1 | sed 's/^fb: //' | cut -dx -f1)
same "the panel -- the same width the kernel reports in the same run" \
    "$k_panel" "$(uw "$R" panelw)"
same "and the image is just as wide unrotated" "$k_panel" "$(uw "$R" imgw)"
same "32 bits per pixel" "32" "$(uw "$R" bpp)"
same "ring 3 saw the EDID too" "1" "$(uw "$R" edidok)"
has "$R" "dispctl: vendor=RHT" "the vendor name arrives in ring 3 through osum_dispstr"
has "$R" "dispctl: model=QEMU Monitor" "the model name too"
n_modes=$(grep -ac '^dispctl: mode ' "$R")
same "and the list comes out line by line" "$anz" "$n_modes"

rc=$(lauf_platte ring3b "osum gfx disp nokbd nosched noproc script=dispctl set 1024 768;dispctl keep;dispctl raw")
num "the run ends cleanly" "$rc" eq 21
R2="$TMPD/ring3b.txt"
same "a program in ring 3 switched the panel" "1024" "$(uwl "$R2" panelw)"
same "and the height" "768" "$(uwl "$R2" panelh)"
same "the line length moved along" "4096" "$(uwl "$R2" pitch)"
same "the kernel counts exactly one switch" "1" "$(uwl "$R2" switches)"
same "right after the switch the confirmation deadline runs" "1" "$(uw "$R2" pending)"
same "after confirming it is closed" "0" "$(uwl "$R2" pending)"
same "and the kernel counted the confirmation" "1" "$(uwl "$R2" confirms)"

# ============================================== 11. the negative test

echo "== 11. THE NEGATIVE TEST: the same kernel without the word'disp' =="
rc=$(lauf ohne "gfx $GRUND")
num "the run ends cleanly" "$rc" eq 21
O="$TMPD/ohne.txt"
hasnot "$O" "disp: vram=" "without 'disp' nothing is probed"
hasnot "$O" "disp: modes" "and there is no list"
hasnot "$O" "disp: edid" "and no EDID"
has "$O" "fb: 800x600x32" "the screen of round K7 is unchanged"
has "$O" "fb: selftest 13 / 13" "and so are its thirteen promises"
rc=$(lauf_platte ohne3 "osum gfx nokbd nosched noproc script=dispctl raw;dispctl test")
num "the run ends cleanly" "$rc" eq 21
O3="$TMPD/ohne3.txt"
has "$O3" "dispctl: there is no screen" "/bin/dispctl says so and does not compute further"
same "and every number is a dash and not a zero" "-" "$(uw "$O3" vram)"
same "also the length of the list" "-" "$(uw "$O3" count)"
same "also EDID" "-" "$(uw "$O3" edidok)"

echo
echo "DISPLAY: $pass passed, $fail failed"
[ "$fail" = 0 ]
