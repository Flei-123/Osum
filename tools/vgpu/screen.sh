#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh >/dev/null 2>&1
K=${VGPU_KERNEL:?VGPU_KERNEL setzen}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
bash tools/mkfsfi/mkfs.sh build "$T/d.img" 4096 /lib/ \
    /lib/mono.ttf=assets/osum-mono.ttf /lib/sans.ttf=assets/osum-sans.ttf >/dev/null 2>&1
cp -f "$T/d.img" "$T/l.img"
S="$T/mon.sock"
timeout 120 $QEMU_X86 -kernel "$K" -m 256 \
    -append "gfx wm wig desk wmhold wiglong vsync wighalt=8 nokbd noproc nofs" \
    -serial "file:$T/o.txt" -display none -no-reboot \
    -vga std -device virtio-gpu-pci,id=vg -global VGA.edid=off \
    -monitor "unix:$S,server,nowait" \
    -drive "file=$T/l.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
pid=$!
i=0
while [ $i -lt 600 ]; do
    grep -qaE '^wm: hold' "$T/o.txt" 2>/dev/null && break
    kill -0 $pid 2>/dev/null || break
    sleep 0.15; i=$((i+1))
done
python3 - "$S" <<'PYEOF'
import socket, sys, time
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); time.sleep(0.4)
try: s.recv(65536)
except OSError: pass
for c in ("info block", "info qtree"):
    s.sendall((c+"\n").encode()); time.sleep(0.3)
    try: s.recv(200000)
    except OSError: pass
s.close()
PYEOF
wait $pid 2>/dev/null
echo "--- what the kernel saw ---"
grep -a '^vgpu:' "$T/o.txt" | tail -2
cp -f "$T/o.txt" /tmp/vgpu-schirm.txt
