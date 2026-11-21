#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/xrdisp/run.sh -- X-Remote display requests: modes file, size request, native request, rejected size.
#   bash tools/xrdisp/run.sh [workdir]     SET_SIZE=800x600 picks the middle size
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1"; }
screen_of() { grep -a '^XR-SCREEN' "$1" | tail -1 | sed -nE 's/.*width=([0-9]+) height=([0-9]+).*/\1x\2/p'; }
field_of() { grep -a "^$2=" "$1" | tail -1 | sed "s/^$2=//" | tr -d '\r'; }

TMPD=${1:-$(mktemp -d)}
. tools/lib/tmpdir.sh
osum_tmp_guard "${1:-}" "$TMPD"
. tools/lib/firnenv.sh
SET_SIZE=${SET_SIZE:-800x600}
PROGS="sh ls cat echo sleep xremoted xrcli desktop taskbar"
mkdir -p "$TMPD/bin"
bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1 && ok "programs build" \
    || { bad "programs do not build"; tail -8 "$TMPD/b.txt"; echo "XRDISP: $pass passed, $fail failed"; exit 1; }
musl-gcc -static -O2 -nostartfiles -T tools/foreign/osum.ld -Wl,--build-id=none \
    -o "$TMPD/bin/xrprobe" tools/foreign/start.s tools/foreign/osum_main.c tools/xremote/probe.c 2> "$TMPD/cc.txt" \
    && ok "xrprobe builds" || { bad "xrprobe does not build"; head -5 "$TMPD/cc.txt"; echo "XRDISP: $pass passed, $fail failed"; exit 1; }
./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1 && ok "kernel builds" \
    || { bad "kernel does not build"; tail -5 "$TMPD/k.txt"; echo "XRDISP: $pass passed, $fail failed"; exit 1; }

cat > "$TMPD/svc.sh" <<EOS
xremoted nosession &
sleep 4
xrprobe screen
xremote display
echo ==T1==
sleep 5
xrprobe screen
echo ==T2==
xremote display set $SET_SIZE
sleep 8
xrprobe screen
xremote display
echo ==T3==
sleep 6
xremote display set 1234x567
sleep 6
xrprobe screen
xremote display
echo ==T4==
xremote display native
sleep 8
xrprobe screen
xremote display
echo ==T5==
sleep 6
echo ==FERTIG==
EOS
cat > "$TMPD/nosvc.sh" <<EOS
sleep 3
xrprobe screen
echo ==T1==
xremote display set $SET_SIZE
sleep 9
xrprobe screen
cat /run/xremote.dispreq
echo ==T2==
echo ==FERTIG==
EOS
printf 'root:x:0:0:root:/:/bin/sh\n' > "$TMPD/passwd"
printf 'lang=en\n' > "$TMPD/locale.conf"
printf '# /etc/theme.conf\nscheme=night\nmode=dark\naccent=\nshape=classic\n' > "$TMPD/theme.conf"
A=(build "$TMPD/disk.img" 32768 /lib/ "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf"
   /bin/ /t/ /tmp/ /var/ /var/log/ /run/ /etc/ /apps/
   "/etc/theme.conf=$TMPD/theme.conf" "/etc/passwd=$TMPD/passwd" "/etc/locale.conf=$TMPD/locale.conf"
   /usr/ /usr/share/ /usr/share/locale/ /usr/share/locale/en/ "/usr/share/locale/en/messages=locale/en/messages"
   "/t/svc.sh=$TMPD/svc.sh" "/t/nosvc.sh=$TMPD/nosvc.sh")
[ -f assets/osum-icons.ttf ] && A+=("/lib/icons.ttf=assets/osum-icons.ttf")
A+=(/etc/schemas/)
for sc in assets/schemes/*.scheme; do A+=("/etc/schemas/$(basename "$sc" .scheme)=$sc"); done
for p in $PROGS; do A+=("/bin/$p=$TMPD/bin/$p.elf"); done
A+=("/bin/xremote=$TMPD/bin/xrcli.elf" "/bin/xrprobe=$TMPD/bin/xrprobe")
bash tools/mkfsfi/mkfs.sh "${A[@]}" > "$TMPD/mkfs.txt" 2>&1 && ok "disk built" \
    || { bad "mkfs"; tail -3 "$TMPD/mkfs.txt"; echo "XRDISP: $pass passed, $fail failed"; exit 1; }

ACC=(); [ -w /dev/kvm ] && ACC=(-accel kvm -cpu host)
boot() {
    local name=$1 script=$2 sock="$TMPD/$1.sock"
    rm -f "$sock" "$TMPD/$name.ser"
    timeout 200 qemu-system-x86_64 "${ACC[@]}" -kernel "$TMPD/k0.img" -m 512 \
        -append "gfx disp wm wmdauer wmshell osum vfs bus uiscale=1 script=sh $script;exit" \
        -serial "file:$TMPD/$name.ser" -display none -no-reboot -vga std -global VGA.edid=off \
        -monitor "unix:$sock,server,nowait" \
        -drive "file=$TMPD/disk.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/$name.qemu" 2>&1 &
    QPID=$!
    waitmark() { local i=0; while [ $i -lt $(( $2 * 5 )) ]; do
            grep -qaF -- "$1" "$TMPD/$name.ser" 2>/dev/null && return 0
            kill -0 "$QPID" 2>/dev/null || return 1; sleep 0.2; i=$((i + 1)); done; return 1; }
    shot() { python3 tools/gfx/screenshot.py "$sock" "$TMPD/$name-$1.ppm" 5 > /dev/null 2>&1; }
    if [ "$name" = svc ]; then
        waitmark "==T1==" 90 && { sleep 1; shot t1; }
        waitmark "==T3==" 60 && { sleep 1; shot t3; }
        waitmark "==T5==" 60 && { sleep 1; shot t5; }
    fi
    waitmark "==FERTIG==" 90 || echo "        $name: no FERTIG in time"
    printf 'quit\n' | socat - "UNIX-CONNECT:$sock" > /dev/null 2>&1
    wait "$QPID" 2>/dev/null
    tr -cd '\11\12\15\40-\176' < "$TMPD/$name.ser" > "$TMPD/$name.klar"
}
boot svc /t/svc.sh
boot nosvc /t/nosvc.sh
G="$TMPD/svc.klar"; N="$TMPD/nosvc.klar"

echo "== checks =="
sed -n '1,/==T1==/p' "$G" > "$TMPD/p_start.txt"
part "$G" T1 T2 > "$TMPD/p_t1.txt"; part "$G" T2 T3 > "$TMPD/p_t3.txt"; part "$G" T3 T4 > "$TMPD/p_t4.txt"; part "$G" T4 T5 > "$TMPD/p_t5.txt"
S0=$(screen_of "$TMPD/p_start.txt")
[ -n "$S0" ] && ok "start: grab size $S0" || bad "no start grab size"
has "$TMPD/p_start.txt" "last=none" "display file written at start with last=none"
NAT=$(field_of "$TMPD/p_start.txt" native)
MODES=$(field_of "$TMPD/p_start.txt" modes)
[ -n "$NAT" ] && ok "host reports native size $NAT" || bad "no native size in the display file"
case ",$MODES," in *",$SET_SIZE,"*) ok "mode list contains $SET_SIZE ($MODES)";; *) bad "mode list lacks $SET_SIZE: $MODES";; esac
case ",$MODES," in *",$NAT,"*) ok "native size is one of the listed modes";; *) bad "native $NAT not in the list";; esac
[ "$(screen_of "$TMPD/p_t1.txt")" = "$S0" ] && ok "control: grab size unchanged without a request" || bad "grab size changed by itself"
[ "$(screen_of "$TMPD/p_t3.txt")" = "$SET_SIZE" ] && ok "request $SET_SIZE: grab size is $SET_SIZE" || bad "grab size after $SET_SIZE request: $(screen_of "$TMPD/p_t3.txt")"
has "$TMPD/p_t3.txt" "current=$SET_SIZE" "display file: current=$SET_SIZE"
has "$TMPD/p_t3.txt" "last=ok" "display file: last=ok"
[ "$(screen_of "$TMPD/p_t4.txt")" = "$SET_SIZE" ] && ok "unsupported 1234x567: grab size unchanged" || bad "grab size after unsupported request: $(screen_of "$TMPD/p_t4.txt")"
has "$TMPD/p_t4.txt" "last=rejected" "unsupported size reported as rejected"
[ "$(screen_of "$TMPD/p_t5.txt")" = "$NAT" ] && ok "native request: grab size is $NAT" || bad "grab size after native request: $(screen_of "$TMPD/p_t5.txt") want $NAT"
has "$TMPD/p_t5.txt" "last=ok" "native request: last=ok"
for pair in "t1:$S0" "t3:$SET_SIZE" "t5:$NAT"; do
    f="$TMPD/svc-${pair%%:*}.ppm"; sz=${pair#*:}
    if [ -s "$f" ]; then
        python3 -I tools/xrdisp/check.py "$f" "${sz%x*}" "${sz#*x}" > "$TMPD/chk-${pair%%:*}.txt" 2>&1
        [ $? = 0 ] && ok "screendump ${pair%%:*}: $(cat "$TMPD/chk-${pair%%:*}.txt")" || bad "screendump ${pair%%:*}: $(cat "$TMPD/chk-${pair%%:*}.txt")"
    else bad "no screendump ${pair%%:*}"; fi
done
SN=$(screen_of "$N")
sed -n '1,/==T1==/p' "$N" > "$TMPD/n_start.txt"
[ -n "$SN" ] && [ "$SN" = "$(screen_of "$TMPD/n_start.txt")" ] && ok "counter-proof (no xremoted): request leaves the size at $SN" || bad "counter-proof: size changed without the service"
has "$N" "$SET_SIZE" "counter-proof: the request file stays unprocessed"
echo "XRDISP: $pass passed, $fail failed"
[ "$fail" = 0 ]
