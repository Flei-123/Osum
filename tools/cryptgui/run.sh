#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/cryptgui/run.sh -- K-019 gate: the installer WINDOW with the "encrypt" box ticked.
#   1. window started with `now,cryptpw=<pw>` (test runner: box ticked + both fields filled)
#   2. install runs to the end and says "installer: encrypted root"
#   3. host: OSUMCRYPT header on the disk, the account file text is not readable
#   4. boot with the right passphrase -> "crypt: unlocked"; with a wrong one -> "crypt: locked"
#   5. counter-check: window WITHOUT cryptpw writes NO header (plain install)
# Run under heavy: /root/jarvis/bin/heavy bash tools/cryptgui/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  OK    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }
BAU="$OUT/bau"
bash tools/usbimg/build.sh "$BAU" > "$OUT/bau.log" 2>&1 || { echo "build failed"; tail -5 "$OUT/bau.log"; exit 1; }
PW=geheim123
run_window() { # <name> <extra wigapp args>
    local n=$1 extra=$2
    dd if=/dev/zero of="$OUT/$n.img" bs=1M count=0 seek=320 status=none
    timeout 1500 $QEMU_X86 -m 512 -kernel "$BAU/osum.mb" -initrd "$BAU/root.img" \
        -append "modfs osum vfs gfx wm wig wmhold wmdauer wighalt=1200 nokbd nosched noproc nofs lang=de uiscale=1 wigapp=/bin/installer,now$extra" \
        -serial "file:$OUT/$n.txt" -display none -no-reboot \
        -device VGA,edid=on,xres=1280,yres=800,vgamem_mb=32 \
        -drive "file=$OUT/$n.img,format=raw,if=ide,index=0" > /dev/null 2>&1 &
    local qp=$! i=0
    while [ $i -lt 1400 ]; do
        grep -aq 'installer: done\|installer: ERROR' "$OUT/$n.txt" 2>/dev/null && break
        kill -0 "$qp" 2>/dev/null || break
        sleep 1; i=$((i+1))
    done
    sleep 3; kill "$qp" 2>/dev/null; wait "$qp" 2>/dev/null
}
run_window c ",cryptpw=$PW"
grep -aq 'installer: encrypted root' "$OUT/c.txt" && ok "window reports encrypted root" || bad "window reports encrypted root"
grep -aq 'installer: done' "$OUT/c.txt" && ok "install finished" || bad "install finished"
python3 - "$OUT/c.img" <<'PY' && ok "host: OSUMCRYPT header present, no plain account text" || bad "host view of the disk"
import sys
d=open(sys.argv[1],'rb').read()
assert b'OSUMCRYPT' in d
assert b'root:' not in d[70000*512:]
PY
for t in "right:$PW:crypt: unlocked" "wrong:falsch:crypt: locked"; do
    n=${t%%:*}; r=${t#*:}; pw=${r%%:*}; want=${r#*:}
    timeout 240 $QEMU_X86 -machine pc -cpu max -m 512 -kernel "$BAU/osum.mb" \
        -append "osum vfs nokbd nosched noproc nofs noring3 kryptopw=$pw script=exit" \
        -serial "file:$OUT/b-$n.txt" -display none -no-reboot \
        -drive "file=$OUT/c.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    grep -aq "$want" "$OUT/b-$n.txt" && ok "boot $n passphrase: $want" || bad "boot $n passphrase: $want"
done
run_window p ""
grep -aq 'installer: done' "$OUT/p.txt" && ok "plain install finished" || bad "plain install finished"
grep -aq 'installer: encrypted root' "$OUT/p.txt" && bad "plain install must not encrypt" || ok "plain install is not encrypted"
python3 - "$OUT/p.img" <<'PY' && ok "host: plain disk has no OSUMCRYPT header" || bad "plain disk has a header"
import sys
assert b'OSUMCRYPT' not in open(sys.argv[1],'rb').read()
PY
echo "CRYPTGUI: $pass ok, $fail fail"
[ "$fail" = 0 ]
