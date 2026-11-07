#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
#
#
#
# Verwendung:  bash tools/hidpunkte/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  \033[32mok\033[0m   %s\n' "$*"; }
bad() { fail=$((fail+1)); printf '  \033[31mNEIN\033[0m %s\n' "$*"; }
is()  { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: $2 (erwartet $3)"; fi; }
gt()  { if [ -n "$2" ] && [ -n "$3" ] && [ "$2" -gt "$3" ] 2>/dev/null
        then ok "$1: $2 > $3"; else bad "$1: $2, sollte groesser als $3 sein"; fi; }
hat() { grep -qa -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "HIDPUNKTE: skipped, qemu-system-x86_64 is missing"; exit 0
fi
if ! qemu-system-x86_64 -device help 2>&1 | grep -q 'qemu-xhci'; then
    echo "HIDPUNKTE: skipped, this QEMU does not know qemu-xhci"; exit 0
fi

echo "== 1. bauen =="
bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "fetch-firnc.sh faellt"; exit 1; }
bash tools/build-kernel.sh "$TMPD/k0.mb" --stufe 0 > "$TMPD/b0.log" 2>&1 \
    && ok "der Kern baut ($(stat -c%s "$TMPD/k0.mb") Oktette)" \
    || { bad "the kernel does not build"; sed 's/^/        /' "$TMPD/b0.log" | head -12; exit 1; }

PROGS="desktop taskbar settings launcher dhcp explorer widgetdemo locate sh echo ls cat edit"
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s assembliert nicht"
for p in $PROGS; do
    UPROF=""; UCRT="$TMPD/crt.o"
    grep -qa '^profile app' "kernel/user/$p.fi" && { UPROF=--profile=app; UCRT=""; }
    vendor/firn/bin/firnc $UPROF -c "kernel/user/$p.fi" -o "$TMPD/$p.o" > "$TMPD/e$p" 2>&1 || {
        bad "firnc uebersetzt $p.fi nicht"; sed 's/^/        /' "$TMPD/e$p" | head -5; continue; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
        -o "$TMPD/$p.elf" $UCRT "$TMPD/$p.o" 2>/dev/null || continue
    strip --strip-all "$TMPD/$p.elf"
done
python3 tools/k15/tree.py "$TMPD/baum" > "$TMPD/baum.log" 2>&1
printf '# taskbar.conf\nedge=0\nheight=28\nwidth=100\nautohide=0\nontop=1\n' > "$TMPD/tb.conf"
ARGS=(build "$TMPD/root.img" 32768 /lib/
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" /bin/)
for p in $PROGS; do ARGS+=("/bin/$p=$TMPD/$p.elf"); done
ARGS+=("/bin/files@/bin/explorer" /etc/ "/etc/theme=$TMPD/baum/theme" "/etc/taskbar.conf=$TMPD/tb.conf")
while read -r z; do ARGS+=("$z"); done < <(python3 tools/k15/bundle.py assets/apps "$TMPD/buendel" nur="$PROGS")
while read -r z; do ARGS+=("$z"); done < "$TMPD/baum/liste"
bash tools/mkfsfi/mkfs.sh "${ARGS[@]}" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "the root image is ready" || bad "mkfs.py faellt"

dd if=/dev/zero of="$TMPD/stick.img" bs=1M count=8 2>/dev/null

JUSTIN="-device qemu-xhci,id=x0 \
 -drive if=none,id=stk,format=raw,file=$TMPD/stick.img \
 -device usb-storage,bus=x0.0,drive=stk \
 -device usb-tablet,bus=x0.0 \
 -device nec-usb-xhci,id=x1 -device usb-kbd,bus=x1.0 -device usb-mouse,bus=x1.0"
UMGEKEHRT="-device qemu-xhci,id=x0 -device usb-kbd,bus=x0.0 -device usb-mouse,bus=x0.0 \
 -device nec-usb-xhci,id=x1 -device usb-tablet,bus=x1.0"

cat > "$TMPD/befehle" <<'EOM'
warte 3.0
sendkey a
sendkey b
sendkey c
warte 1.0
mouse_move 60 0
mouse_move 60 0
mouse_move 0 60
mouse_move 0 60
mouse_move 40 20
warte 1.0
mouse_button 1
mouse_button 0
warte 3.0
EOM

lauf() { # name topologie kommandozeile sek [vga]
    local name=$1 topo=$2 app=$3 sek=$4 vga=${5:--vga std}
    local sock="$TMPD/mon-$name.sock" out="$TMPD/$name.txt"
    rm -f "$out" "$sock"
    ( timeout "$sek" $QEMU_X86 -kernel "$TMPD/k0.mb" -m 1024 -append "$app" \
        -serial "file:$out" -display none -no-reboot $vga \
        -monitor "unix:$sock,server,nowait" -initrd "$TMPD/root.img" \
        $topo -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1 ) &
    local pid=$! i=0
    while [ $i -lt 2000 ]; do
        grep -qa 'eingabe:' "$out" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.05; i=$((i+1))
    done
    python3 tools/wm/monitor.py "$sock" "${BEFEHLE:-$TMPD/befehle}" > "$TMPD/$name.mon" 2>&1
    sleep 2
    if [ -n "${SHOT:-}" ] && command -v socat >/dev/null 2>&1; then
        printf 'screendump %s\n' "$SHOT" | timeout 20 socat - "UNIX-CONNECT:$sock" >/dev/null 2>&1
        sleep 2
    fi
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    rm -f "$sock"
}
feld() { grep -a 'eingabe: ber=' "$1" | tail -1 | sed -n "s/.*[ :]$2=\([0-9]*\).*/\1/p"; }

BASE="modfs osum gfx wm wig desk wmshell wmdauer usb hidgen nosched noproc nofs"

echo
echo "== 2. JUSTIN'S SETUP: the input hangs on the SECOND controller =="
lauf justin "$JUSTIN" "$BASE" 120
hat "$TMPD/justin.txt" 'usb: choice' "die Wahl steht im Bericht (usb: choice ...)"
W=$(grep -a '^usb: choice' "$TMPD/justin.txt" | tail -1)
echo "        $W"
is "der Regler mit Tastatur und Maus gewinnt" \
   "$(echo "$W" | sed -n 's/.*-> hc\([0-9]*\).*/\1/p')" 1
gt "der Gewinner hat mehr Punkte als der Regler mit dem Stick" \
   "$(echo "$W" | sed -n 's/.*hc1=\([0-9]*\).*/\1/p')" \
   "$(echo "$W" | sed -n 's/.*hc0=\([0-9]*\).*/\1/p')"
gt "TASTEN kommen im Schreibtisch an (ta=)"  "$(feld "$TMPD/justin.txt" ta)"  0
gt "LOSLASSEN kommt an (lo=)"                "$(feld "$TMPD/justin.txt" lo)"  0
gt "MAUSBEWEGUNGEN kommen an (bew=)"         "$(feld "$TMPD/justin.txt" bew)" 0
gt "der Zeiger bewegt sich wirklich (pk=)"   "$(feld "$TMPD/justin.txt" pk)"  0
gt "der Fensterserver holt sie ab (wm=)"     "$(feld "$TMPD/justin.txt" wm)"  0

echo
echo "== 3. GEGENPROBE: dieselbe Aufstellung UMGEKEHRT =="
echo "   input on the FIRST controller, the weak HID on the second. Without"
echo "   this probe a fixed choice would only have become another one."
lauf umgek "$UMGEKEHRT" "$BASE" 120
W2=$(grep -a '^usb: choice' "$TMPD/umgek.txt" | tail -1)
echo "        $W2"
is "jetzt gewinnt hc0" "$(echo "$W2" | sed -n 's/.*-> hc\([0-9]*\).*/\1/p')" 0
gt "und die Tasten kommen genauso an" "$(feld "$TMPD/umgek.txt" ta)" 0
gt "und die Maus auch"                "$(feld "$TMPD/umgek.txt" bew)" 0

echo
echo "== 4. THE ULTRAWIDE SCREEN: bar, pointer, measuring bar =="
echo "   Justin's Huawei is wider than anything that ever ran here. At"
echo "   1280x800 all three faults are invisible."
SHOTS=docs/shots/hidpunkte
mkdir -p "$SHOTS"
cat > "$TMPD/befehle-still" <<'EOM'
warte 6.0
EOM
BEFEHLE="$TMPD/befehle-still" SHOT="$TMPD/uw.ppm" lauf uw \
    "-device qemu-xhci,id=x0 -device usb-kbd,bus=x0.0 -device usb-mouse,bus=x0.0" \
    "modfs osum gfx fbres=3440x1440 wm wig desk wmshell wmdauer usb hidgen nosched noproc nofs" \
    150 "-device VGA,edid=off,vgamem_mb=64"
hat "$TMPD/uw.txt" 'fb: 3440x1440' "der Schirm ist wirklich 3440x1440"
R=$(grep -a '^taskbar: size' "$TMPD/uw.txt" | tail -1 | sed -n 's/.*rc=\(-*[0-9]*\).*/\1/p')
is "die Taskleiste bekommt ihre volle Breite (rc=)" "$R" 0

if [ -f "$TMPD/uw.ppm" ]; then
    python3 - "$TMPD/uw.ppm" "$SHOTS" > "$TMPD/bild.txt" <<'PY'
import sys
d=open(sys.argv[1],'rb').read()
p=d.split(b'\n',3); w,h=map(int,p[1].split()); px=p[3]
def at(x,y):
    i=(y*w+x)*3; return (px[i],px[i+1],px[i+2])
y=h-30; b=at(w-1,y)
xs=[x for x in range(w) if at(x,y)!=b]
print("LEISTE %d %d"%(min(xs) if xs else -1, max(xs) if xs else -1))
gruen=sum(1 for x in range(0,w,3) for yy in range(2,40) if at(x,yy)==(0,255,102))
print("MESSLEISTE %d"%gruen)
best=[(x,y) for y in range(h//2-120,h//2+120) for x in range(w//2-120,w//2+120)
      if at(x,y)[0]>200 and at(x,y)[1]>200 and at(x,y)[2]>200]
if best:
    xs2=[q[0] for q in best]; ys2=[q[1] for q in best]
    print("ZEIGER %d %d"%(max(xs2)-min(xs2)+1, max(ys2)-min(ys2)+1))
    x0,y0=min(xs2)-2,min(ys2)-2
    out=[]
    for yy in range(y0,min(y0+40,h)):
        line=''
        for xx in range(x0,min(x0+26,w)):
            c=at(xx,yy)
            line += '#' if (c[0]>200 and c[1]>200) else ('.' if sum(c)<30 else ' ')
        out.append(line)
    open(sys.argv[2]+'/zeiger.txt','w').write('\n'.join(out)+'\n')
else:
    print("ZEIGER 0 0")
PY
    L0=$(sed -n 's/^LEISTE \([0-9-]*\) .*/\1/p' "$TMPD/bild.txt")
    L1=$(sed -n 's/^LEISTE [0-9-]* \([0-9-]*\)/\1/p' "$TMPD/bild.txt")
    echo "        bar in the IMAGE: x $L0 .. $L1 of 3440"
    gt "die Leiste ist im BILD breiter als 3000 Bildpunkte" "$((L1 - L0))" 3000
    G=$(sed -n 's/^MESSLEISTE \([0-9]*\)/\1/p' "$TMPD/bild.txt")
    gt "die Messleiste steht oben im BILD (gruene Punkte)" "$G" 20
    ZW=$(sed -n 's/^ZEIGER \([0-9]*\) .*/\1/p' "$TMPD/bild.txt")
    ZH=$(sed -n 's/^ZEIGER [0-9]* \([0-9]*\)/\1/p' "$TMPD/bild.txt")
    echo "        pointer in the IMAGE: ${ZW}x${ZH}"
    gt "der Zeiger waechst mit der Tafel (breiter als 12)" "$ZW" 12
    gt "und hoeher als 18"                                 "$ZH" 18
    if [ -f "$SHOTS/zeiger.txt" ]; then
        echo
        echo "   THE ARROW, cut out of the real screenshot:"
        sed 's/^/        /' "$SHOTS/zeiger.txt"
    fi
else
    bad "no screenshot -- is socat there?"
fi

echo
echo "HIDPUNKTE: $pass gehalten, $fail gefallen"
[ "$fail" -eq 0 ]
