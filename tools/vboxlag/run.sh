#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/vboxlag/run.sh -- pointer-move lag measurement (16.10.2026, boss: VirtualBox desktop lags/flickers when the mouse moves).
#
#   IMG=<personal image> [RES=1920x1080] [EXTRA="words"] [OUT=<dir>] bash tools/vboxlag/run.sh
#
# Boots the image like VirtualBox sees it (pc/BIOS/Limine, VGA std, 3 CPUs, PS/2 mouse), adds the kernel word `phases`, logs in,
# and prints per phase (idle / pointer over desktop / pointer over taskbar / 1 px moves) the composed frames, the frame time
# and what the copies to the card cost (count, microseconds, OCTETS). Start through /root/jarvis/bin/heavy.
set -uo pipefail
cd "$(dirname "$0")/../.."
HERE=$(pwd)/tools/vboxlag
IMG=${IMG:?set IMG=<personal image>}
RES=${RES:-1920x1080}
EXTRA="${EXTRA-phases}"
if [ -n "${OUT:-}" ]; then mkdir -p "$OUT"; else OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT; fi
D="$OUT/m"; mkdir -p "$D"
cp "$IMG" "$D/s.img"
off=$((2048*512))
mcopy -o -i "$D/s.img@@$off" ::/limine.conf "$D/l.orig" || exit 1
python3 - "$D/l.orig" "$D/l.conf" "$RES" "$EXTRA" <<'PY'
import sys
L=open(sys.argv[1]).read().splitlines()
st=[i for i,l in enumerate(L) if l.startswith('/') and not l.startswith('//')][0]
en=next((j for j in range(st+1,len(L)) if L[j].startswith('/')),len(L))
blk=L[st:en]
out=[]
for l in blk:
    out.append(l)
    if l.strip().startswith('module_path'):
        out.append('    resolution: '+sys.argv[3])
    if l.strip().startswith('cmdline:'):
        out[-1]=l+' '+sys.argv[4]
open(sys.argv[2],'w').write('timeout: 0\ndefault_entry: 1\n\n'+'\n'.join(out)+'\n')
PY
mcopy -o -i "$D/s.img@@$off" "$D/l.conf" ::/limine.conf
mcopy -o -i "$D/s.img@@$off" "$D/l.conf" ::/boot/limine.conf
accel=()
[ -w /dev/kvm ] && accel=(-accel kvm -cpu host)
qemu-system-x86_64 -m 2048 "${accel[@]}" -smp 3 -M pc -vga std \
    -drive file="$D/s.img",format=raw,if=none,id=stick -device ide-hd,drive=stick \
    -nic user,model=e1000 -serial file:"$OUT/serial.txt" -display none -no-reboot \
    -monitor unix:"$D/mon",server,nowait &
qp=$!
python3 -I "$HERE/drive.py" "$D/mon" "$OUT/serial.txt" "$OUT" 300 | tee "$OUT/result.txt"
kill $qp 2>/dev/null; wait $qp 2>/dev/null
rm -f "$D/s.img"
# verdict (thresholds of the 16.10.2026 diff-flush round): pointer phases <= 64 KB per frame, idle < 100 KB/s. With `nodiff` in EXTRA the
# numbers are the counter-proof and the verdict is expected to FAIL.
python3 -I - "$OUT/result.txt" <<'PY'
import re, sys
bad = 0; n = 0
for l in open(sys.argv[1]):
    m = re.match(r"PH (\w+)\s+secs=([\d.]+) frames=(\d+).*okt=(\d+) okt_per_frame=(\d+)", l)
    if not m:
        continue
    n += 1
    name, secs, okt, opf = m.group(1), float(m.group(2)), int(m.group(4)), int(m.group(5))
    if name == "idle":
        ok = okt / max(secs, 0.1) < 100 * 1024
        print("CHECK idle %.0f KB/s (< 100) %s" % (okt / max(secs, 0.1) / 1024, "OK" if ok else "FAIL"))
    else:
        ok = opf <= 64 * 1024
        print("CHECK %s %.1f KB/frame (<= 64) %s" % (name, opf / 1024, "OK" if ok else "FAIL"))
    bad += 0 if ok else 1
print("VERDICT %d phases, %d FAIL" % (n, bad))
PY
