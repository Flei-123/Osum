#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/fullhd/run.sh -- r1226: Full HD (1920x1080 / 1920x1200 / 1366x768 / 1024x768) on the vmware card: the desktop AND the taskbar fill the
# WHOLE screen, and the stride (pitch) is width*4. Boss bug: "vmsvga draws only a small rectangle at 1920x1080/1920x1200, 1024x768 works"
# (VirtualBox kept the OLD stride, cbLine 0x1000, after a live WIDTH/HEIGHT change; fix: ENABLE=0 + PITCHLOCK=w*4, r1197). No laptop needed.
# QEMU stick image, `-vga none -device vmware-svga,vgamem_mb=64`, kernel words:
#   vmsvgahints vmsvgafull  -- boot fit plays 1920x1080 (like a VMMDev hint at boot), then the hint player: 1920x1200, 1366x768, 1024x768, 1920x1080
#   vmsvgastale             -- emulates VirtualBox's stale BYTES_PER_LINE register + takes the VirtualBox path (ENABLE=0, PITCHLOCK, serial `lock=`)
# Case "fix"   (vmsvgastale):             every picture has the expected size, all four quadrants + the last 56 rows + the right third of the
#                                         taskbar are populated, no stale-stride repeat; serial `vmsvga: mode WxH ... lock=L` has L == W*4 each time
# Case "plain" (no stale emulation):      the QEMU path, same picture checks (no `lock=` expected)
# Case "old"   (vmsvgastale vmsvgaold):   COUNTER-PROOF, the pre-fix set_mode trusts the stale register -> must go RED (picture check) and print no lock=
# Selftest: the judge is run on synthetic pictures: a full one is green, the bug picture (1024x768 rectangle in a black 1920x1080) is red.
# Usage: [STICK_DIR=<dir with orientos-usb.img>] [IMG=<file>] [SETTLE=9] [KEEP=<dir>] bash tools/fullhd/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
HERE=$(pwd)/tools/fullhd
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
SETTLE=${SETTLE:-9}
echo "== judge selftest (synthetic pictures)"
python3 -I "$HERE/fullhd.py" --selftest >"$T/self.txt" 2>&1; rc=$?
cat "$T/self.txt"
[ "$rc" = 0 ] && ok "judge: full picture green, small-rectangle + shifted-bar pictures red" || bad "judge selftest (rc=$rc)"
if [ -n "${IMG:-}" ]; then
    IMAGE=$IMG
elif [ -n "${STICK_DIR:-}" ] && [ -f "$STICK_DIR/orientos-usb.img" ]; then
    IMAGE=$STICK_DIR/orientos-usb.img
else
    mkdir -p "$T/build"
    PARTTAB=mbr bash tools/usbimg/build.sh "$T/build" >"$T/build.log" 2>&1 || { echo "stick build failed"; tail -15 "$T/build.log"; exit 1; }
    IMAGE=$T/build/orientos-usb.img
fi
KVM=(-accel tcg)
[ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)
off=$((2048 * 512))
run_one() { # <tag> <extra words> [video memory MiB]  (blocking: call with &)
    local tag=$1 words=$2 vram=${3:-64} D=$T/$1
    mkdir -p "$D"
    cp -f "$IMAGE" "$D/stick.img"
    mcopy -o -i "$D/stick.img@@$off" ::/limine.conf "$D/l.conf" || return 1
    sed -i 's/^timeout: .*/timeout: 1/' "$D/l.conf"
    awk -v ex="$words" 'BEGIN{d=0} /^ *cmdline:/ && d==0 { d=1; print $0 " " ex; next } { print }' "$D/l.conf" >"$D/l2.conf"
    mcopy -o -i "$D/stick.img@@$off" "$D/l2.conf" ::/limine.conf
    timeout 700 qemu-system-x86_64 "${KVM[@]}" -m 2048 -smp 4 \
        -device qemu-xhci,id=xhci \
        -drive if=none,id=stick,format=raw,file="$D/stick.img" \
        -device usb-storage,bus=xhci.0,drive=stick,bootindex=1 \
        -netdev user,id=n0 -device e1000e,netdev=n0 \
        -vga none -device vmware-svga,vgamem_mb=$vram -vnc "unix:$D/vnc.sock" -display none -no-reboot \
        -serial file:"$D/serial.txt" \
        -monitor unix:"$D/mon.sock",server,nowait >"$D/qemu.txt" 2>&1 &
    local pid=$!
    python3 -I "$HERE/fullhd.py" "$D/mon.sock" "$D/vnc.sock" "$D/o" "$D/serial.txt" "$SETTLE" 4 >"$D/py.txt" 2>&1 || true
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    rm -f "$D/stick.img"
    [ -n "${KEEP:-}" ] && mkdir -p "$KEEP/$tag" && cp -f "$D"/o.*.ppm "$D/serial.txt" "$D/py.txt" "$D/o.res" "$KEEP/$tag"/ 2>/dev/null
    return 0
}
run_one fix "vmsvgahints vmsvgafull vmsvgastale" &
run_one plain "vmsvgahints vmsvgafull" &
run_one old "vmsvgahints vmsvgafull vmsvgastale vmsvgaold" &
run_one vram8 "vmsvgahints vmsvgafull vmsvgastale" 8 &
wait
# lockcheck <serial> -> "<lines with lock>/<bad lines>"
lockcheck() {
    awk '/^vmsvga: mode /{split($3,a,"x"); l=0; for(i=1;i<=NF;i++) if ($i ~ /^lock=/) {l=substr($i,6)+0}; if (l>0) {n++; if (l!=a[1]*4) b++}} END{print n+0 "/" b+0}' "$1"
}
# judge_case <tag> -> prints OK/FAIL lines for every picture, returns the number of RED pictures (stdout of the python judge)
judge_case() {
    python3 -I - "$T/$1/o.res" <<'PYEOF'
import sys, importlib.util, os
spec = importlib.util.spec_from_file_location("fullhd", os.environ["HERE_PY"])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
n = red = 0
try:
    lines = open(sys.argv[1]).read().split("\n")
except OSError:
    lines = []
for ln in lines:
    f = ln.split()
    if len(f) < 14:
        continue
    i, w, h, ew, eh = (int(x) for x in f[:5])
    q = [float(x) for x in f[5:9]]; bar = float(f[9]); ink = int(f[10]); dup = float(f[11]); last = float(f[12]); rough = float(f[13])
    why = []
    if (w, h) != (ew, eh):
        why.append("screen %dx%d, expected %dx%d" % (w, h, ew, eh))
    why += m.verdict((*q, bar, ink, dup, last, rough))
    n += 1
    tag = "step %d %dx%d" % (i, ew, eh)
    nums = "q=%.2f/%.2f/%.2f/%.2f bar=%.2f ink=%d dup=%.2f rough=%.1f" % (q[0], q[1], q[2], q[3], bar, ink, dup, rough)
    if why:
        red += 1
        print("  RED   %s: %s [%s]" % (tag, "; ".join(why), nums))
    else:
        print("  GREEN %s [%s]" % (tag, nums))
print("JUDGED %d %d" % (n, red))
PYEOF
}
export HERE_PY=$HERE/fullhd.py
sizes_ok() { # <res file> -> the expected sizes seen (without step 0) joined
    awk '$1>=1 {printf "%sx%s ", $4, $5}' "$1" 2>/dev/null
}
for c in fix plain; do
    D=$T/$c
    echo "== case $c"
    [ "$(cat "$D/o.login" 2>/dev/null)" = 1 ] && ok "$c: logged in" || { bad "$c: login"; tail -3 "$D/py.txt"; }
    out=$(judge_case "$c"); echo "$out" | grep -v '^JUDGED'
    read -r jn jred < <(echo "$out" | awk '/^JUDGED/{print $2, $3}')
    jn=${jn:-0}; jred=${jred:-9}
    [ "$jn" -ge 5 ] && ok "$c: $jn pictures judged (boot + 4 hints)" || bad "$c: only $jn pictures judged (need 5)"
    [ "$jred" = 0 ] && [ "$jn" -ge 5 ] && ok "$c: every picture fills the whole screen (quadrants, taskbar rows, taskbar right third, no stride repeat)" || bad "$c: $jred picture(s) red"
    seen=$(sizes_ok "$D/o.res")
    want="1920x1200 1366x768 1024x768 1920x1080 "  # step 0 (boot, 1920x1080) is not in this list
    [ "$seen" = "$want" ] && ok "$c: sizes played $seen" || bad "$c: sizes '$seen', wanted '$want'"
    bl=$(grep -a '^vmsvga: bootfit  *1024x768 hint 1920x1080' "$D/serial.txt" | head -1)
    ba=$(grep -a '^vmsvga: bootfit  *-> 1920x1080 rc=0' "$D/serial.txt" | head -1)
    [ -n "$bl" ] && [ -n "$ba" ] && ok "$c: boot fit straight to 1920x1080 (rc=0)" || bad "$c: boot fit lines missing ('$bl' / '$ba')"
    if [ -f "$D/o.res" ] && awk '$1==0{f=1} END{exit !f}' "$D/o.res"; then
        ok "$c: the boot mode itself (step 0, before any hint) was judged"
    else
        bad "$c: no step-0 picture (the boot mode was not judged before the first hint)"
    fi
    lc=$(lockcheck "$D/serial.txt")
    if [ "$c" = fix ]; then
        # boot fit + 4 hints -> at least 5 mode sets with a lock
        [ "${lc%/*}" -ge 5 ] && [ "${lc#*/}" = 0 ] && ok "$c: pitch lock = width*4 on every mode change ($lc)" || bad "$c: pitch lock lines/bad $lc (need >= 5 / 0)"
    else
        [ "${lc%/*}" = 0 ] && ok "$c: QEMU path writes no pitch lock ($lc)" || bad "$c: unexpected lock lines $lc"
    fi
    grep -a '^vmsvga: mode ' "$D/serial.txt" | sed 's/^/  NOTE  /' | head -6
done
echo "== case vram8 (card with 8 MiB video memory: 1920x1080 does not fit -> a SHRUNK, working mode, never black / a small rectangle)"
D=$T/vram8
[ "$(cat "$D/o.login" 2>/dev/null)" = 1 ] && ok "vram8: logged in" || bad "vram8: login"
out=$(judge_case vram8); echo "$out" | grep -v '^JUDGED'
read -r jn jred < <(echo "$out" | awk '/^JUDGED/{print $2, $3}')
jn=${jn:-0}; jred=${jred:-9}
[ "$jn" -ge 5 ] && [ "$jred" = 0 ] && ok "vram8: $jn pictures, all fill the screen of the size the kernel reports" || bad "vram8: $jn pictures, $jred red"
awk '$1>=0 && ($2*$3*4 > 8388608 || $2 < 1000) {bad=1} END{exit bad}' "$D/o.res" 2>/dev/null && ok "vram8: every mode fits 8 MiB and is >= 1000 px wide (no collapse to a tiny size)" || bad "vram8: a mode does not fit 8 MiB or collapsed"
echo "== case old (COUNTER-PROOF: must go red)"
D=$T/old
[ "$(cat "$D/o.login" 2>/dev/null)" = 1 ] && ok "old: logged in" || bad "old: login"
out=$(judge_case old); echo "$out" | grep -v '^JUDGED' | head -8
read -r jn jred < <(echo "$out" | awk '/^JUDGED/{print $2, $3}')
jn=${jn:-0}; jred=${jred:-0}
[ "$jn" -ge 5 ] && [ "$jred" -ge 1 ] && ok "old: pre-fix set_mode goes red ($jred of $jn pictures)" || bad "old: counter-proof did not go red ($jred of $jn pictures red)"
lc=$(lockcheck "$D/serial.txt")
[ "${lc%/*}" = 0 ] && ok "old: no pitch lock written (counter-proof, $lc)" || bad "old: still locks $lc"
echo "fullhd: $pass ok, $fail fail"
[ "$fail" = 0 ]
