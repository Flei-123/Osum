#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/sdk/gui.sh -- THE SDK GUI TEMPLATE, MEASURED (TOOLKIT-PLAN T1, docs/SDK.md).
#   /root/jarvis/bin/heavy bash tools/sdk/gui.sh [workdir]      (~3 min, one QEMU boot)
# 1 `osdk new --kind gui` -> check -> build (profile app, scene tree, gc-sections); a broken source and a
#   src file that shadows a scene module are refused
# 2 guest: the SDK-built window is in the a11y tree (label, field, main button, label); a press through the
#   tree reaches the program (Count: 0 -> Count: 1); without a press it stays 0 (counter-proof)
# 3 the tree dump of the SDK app renders on the host (tools/preview/axpng.py): the button is where the tree says
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1"; }
fin() { echo "SDK-GUI: $pass passed, $fail failed"; [ "$fail" = 0 ]; exit; }
if [ -n "${1:-}" ]; then TMPD=$1; mkdir -p "$TMPD"; else TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT; fi
O="python3 tools/sdk/osdk.py"
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1

echo "== 1. new / check / build =="
$O new org.example.counter --kind gui --dir "$TMPD/counter" > /dev/null && ok "osdk new --kind gui" || { bad "new gui"; fin; }
grep -q '^profile app' "$TMPD/counter/src/main.fi" && ok "template is a scene program (profile app)" || bad "profile app missing"
$O check "$TMPD/counter" > /dev/null && ok "manifest passes" || bad "manifest refused"
$O build "$TMPD/counter" --out "$TMPD/out" > "$TMPD/b.txt" 2>&1 && ok "gui app builds: $(tail -1 "$TMPD/b.txt" | cut -c1-100)" || { bad "gui build"; head -15 "$TMPD/b.txt"; fin; }
sz=$(stat -c %s "$TMPD/out/bin/counter.elf")
[ "$sz" -lt 1500000 ] && ok "size $sz octets (scene host, gc-sections applied; without: 3.0 MB)" || bad "size $sz: gc-sections not applied?"
cp -r "$TMPD/counter" "$TMPD/broken"; printf '\nfn broken_on_purpose( {\n' >> "$TMPD/broken/src/main.fi"
$O build "$TMPD/broken" --out "$TMPD/ob" > "$TMPD/bb.txt" 2>&1 && bad "broken gui source built" || ok "broken source -> build refused"
cp -r "$TMPD/counter" "$TMPD/shadow"; printf 'x' > "$TMPD/shadow/src/fuiscene.fi"
out=$($O build "$TMPD/shadow" --out "$TMPD/os" 2>&1); echo "$out" | grep -qF "shadows an SDK module" && ok "src/fuiscene.fi (shadowing a scene module) refused" || bad "shadowing a scene module accepted"

echo "== 2. guest =="
mkdir -p "$TMPD/bin"
PROGS="sh ls cat echo sleep orientbus act axd"
bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/bb2.txt" 2>&1 && ok "guest tools build" || { bad "guest tools"; head "$TMPD/bb2.txt"; fin; }
./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel"; tail -4 "$TMPD/k.txt"; fin; }
cat > "$TMPD/g.sh" <<'EOS'
orientbus serve 0 &
sleep -m 300
axd serve 0 &
sleep 1
/apps/counter.osp/start &
sleep 12
echo ==T0==
act call a11y.tree window=Counter
sleep 3
echo ==T1==
act call a11y.tree window=Counter
echo ==P==
act call a11y.press name=Count! window=Counter
sleep 6
echo ==T2==
act call a11y.tree window=Counter
echo ==END==
act stop
echo ==FERTIG==
EOS
A=(build "$TMPD/disk.img" 32768 /lib/ "/lib/mono.ttf=assets/osum-mono.ttf"
   "/lib/sans.ttf=assets/osum-sans.ttf" /bin/ /t/ /tmp/ /var/ /var/log/
   /etc/ /etc/actions.d/ /etc/orientbus/
   "/etc/actions.d/a11y.actions=etc/actions.d/a11y.actions"
   "/etc/orientbus/policy=etc/orientbus/policy"
   "/t/g.sh=$TMPD/g.sh")
[ -f assets/osum-icons.ttf ] && A+=("/lib/icons.ttf=assets/osum-icons.ttf")
[ -f assets/osum-sans-bold.ttf ] && A+=("/lib/bold.ttf=assets/osum-sans-bold.ttf")
printf '# /etc/theme.conf\nscheme=day\nmode=light\naccent=\nshape=classic\n' > "$TMPD/theme.conf"
A+=("/etc/theme.conf=$TMPD/theme.conf" /etc/schemas/)
for s in assets/schemes/*.scheme; do A+=("/etc/schemas/$(basename "$s" .scheme)=$s"); done
for p in $PROGS; do A+=("/bin/$p=$TMPD/bin/$p.elf"); done
while read -r l; do A+=("$l"); done < "$TMPD/out/mkfs.lines"
python3 tools/osum/mkfs.py "${A[@]}" > "$TMPD/mkfs.txt" 2>&1 && ok "disk with /apps/counter.osp" || { bad "mkfs"; tail -3 "$TMPD/mkfs.txt"; fin; }
SOCK="$TMPD/mon.sock"; rm -f "$SOCK"
ACC=(); [ -w /dev/kvm ] && ACC=(-accel kvm -cpu host)
timeout 300 qemu-system-x86_64 "${ACC[@]}" -kernel "$TMPD/k0.img" -m 768 \
    -append "gfx disp wm wmdauer wmshell osum vfs bus script=sh /t/g.sh;exit" \
    -serial "file:$TMPD/ser.txt" -display none -no-reboot -vga std \
    -monitor "unix:$SOCK,server,nowait" \
    -drive "file=$TMPD/disk.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/qemu.txt" 2>&1 &
QPID=$!
i=0
while [ $i -lt 1000 ]; do
    grep -qaF -- "==FERTIG==" "$TMPD/ser.txt" 2>/dev/null && break
    kill -0 "$QPID" 2>/dev/null || break
    sleep 0.3; i=$((i + 1))
done
printf 'quit\n' | socat - "UNIX-CONNECT:$SOCK" >/dev/null 2>&1
wait "$QPID" 2>/dev/null
tr -cd '\11\12\15\40-\176' < "$TMPD/ser.txt" > "$TMPD/ser.klar"
perl -0pi -e 's/wm: fen i=[^\n]*? tka=\d+\r?\n//g' "$TMPD/ser.klar"
G="$TMPD/ser.klar"
part "$G" T0 T1 > "$TMPD/t0.txt"; part "$G" T1 P > "$TMPD/t1.txt"; part "$G" T2 END > "$TMPD/t2.txt"
grep -qaE '=window win[0-9]+ .*"Counter"' "$TMPD/t1.txt" && ok "the window is in the a11y tree, named by the title" || { bad "no window Counter"; head -5 "$TMPD/t1.txt"; }
grep -qaE '=button .*"Count!" act=|=button .*"Count!"' "$TMPD/t1.txt" && ok "main button Count! (role button)" || bad "no button Count!"
grep -qaE '=entry .*"Hello"' "$TMPD/t1.txt" && ok "text field with its text" || bad "no entry Hello"
grep -qaF '"Count: 0"' "$TMPD/t1.txt" && ok "label Count: 0 before the press" || bad "no label Count: 0"
grep -qaF '"Count: 1"' "$TMPD/t1.txt" && bad "counter moved WITHOUT a press (counter-proof)" || ok "no press -> still 0 (counter-proof)"
grep -qaF '"Count: 1"' "$TMPD/t2.txt" && ok "press through the tree reaches the app: Count: 1" || { bad "press did not count"; grep -a "Count" "$TMPD/t2.txt" | head -3; }

echo "== 3. host preview of the SDK app =="
cp "$TMPD/t1.txt" "$TMPD/counter.tree"
python3 -I tools/preview/axpng.py "$TMPD/counter.tree" --window Counter -o "$TMPD/counter.png" > "$TMPD/pv.txt" 2>&1 && ok "preview PNG: $(cat "$TMPD/pv.txt")" || { bad "preview failed"; cat "$TMPD/pv.txt"; }
python3 -I - "$TMPD/counter.tree" "$TMPD/counter.png" <<'EOF' && ok "button face drawn at the node rect of the guest tree" || bad "button not where the tree puts it"
import re, sys
from PIL import Image
t = open(sys.argv[1], "rb").read().decode("latin-1")
m = re.search(r'=window win\d+ (-?\d+),(-?\d+) .*\n(?:.*\n)*?node\.\d+=button win\d+ (-?\d+),(-?\d+) (\d+)x(\d+)', t)
wx, wy, bx, by, bw, bh = map(int, m.groups())
im = Image.open(sys.argv[2]).convert("RGB")
px = im.getpixel((bx - wx + 8 + bw // 2, by - wy + 8 + bh // 2 + 8))
assert px == (253, 253, 253), px
EOF
fin
