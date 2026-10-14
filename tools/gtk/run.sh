#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/gtk/run.sh -- PROOF STONES glib + GTK4 (r729): a GLib main-loop probe and a GTK4 hello (Wayland backend, cairo renderer) on wayd.
#
#   /root/jarvis/bin/heavy bash tools/unterbau/build-gtk-stones.sh /root/stones-gtk     (once; heavy; writes /root/stones-gtk/gtk/)
#   /root/jarvis/bin/heavy bash tools/gtk/run.sh [<work dir>]
#
# Boots wayd, runs glib-hello (main loop, pipe watch, signal source, thread, file monitor, spawn) and then gtk4-hello and checks the serial markers
# and the window pixels. KARGS=fremdtrace shows ENOSYS / failed mmap/brk/clone.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }
has()    { grep -qaF -- "$2" <<< "$1" && ok "$3" || { bad "$3 -- '$2' missing"; }; }

STONES=${STONES:-/root/stones}
GS=${GTK_STONES:-/root/stones-gtk}
TMPD=${1:-$(mktemp -d)}
[ -n "${1:-}" ] || trap 'rm -rf "$TMPD"' EXIT
mkdir -p "$TMPD/bin"
[ -r "$GS/gtk/manifest.txt" ] && [ -r "$STONES/foot/manifest.txt" ] && [ -r "$STONES/busybox" ] || { echo "GTK: no gtk/foot stones ($GS, $STONES), skipped"; exit 0; }
LDREAL=$(readlink -f /lib/ld-musl-x86_64.so.1 2>/dev/null || true)
[ -r "$LDREAL" ] || LDREAL=/usr/lib/x86_64-linux-musl/libc.so
PROGS="sh sleep echo cat ls wayd"

echo "== 1. build =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
python3 tools/wayland/genkeys.py --keymaps "$TMPD/km" 2>"$TMPD/km.txt" && ok "keymaps compiled" || bad "keymap generation: $(cat "$TMPD/km.txt")"
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1; then ok "firnc0 builds $(echo $PROGS | wc -w) programs"
else bad "the programs do not build"; tail -15 "$TMPD/b.txt" | sed 's/^/        /'; echo "GTK: $pass passed, $fail failed"; exit 1; fi
if ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1; then ok "the kernel builds"
else bad "the kernel does not build"; tail -5 "$TMPD/k.txt" | sed 's/^/        /'; echo "GTK: $pass passed, $fail failed"; exit 1; fi

cat > "$TMPD/g.sh" <<'EOS'
echo ==G-START==
export XDG_RUNTIME_DIR=/tmp HOME=/root FONTCONFIG_FILE=/etc/fonts/fonts.conf
glib-hello
echo ==G-GLIBDONE==
wayd /tmp/wayland-0 2000000000 &
sleep 2
busybox sh /t/launch.sh &
sleep GTK_WAIT
echo ==G-READY==
busybox ls /var/crash
busybox cat /var/crash/*
sleep 400
echo ==FERTIG==
EOS
cat > "$TMPD/launch.sh" <<'EOS'
export XDG_RUNTIME_DIR=/tmp HOME=/root FONTCONFIG_FILE=/etc/fonts/fonts.conf WAYLAND_DISPLAY=/tmp/wayland-0 GDK_BACKEND=wayland GSK_RENDERER=cairo GTK_A11Y=none GTK_HELLO_SECS=300
exec /usr/bin/gtk4-hello
EOS
sed -i "s/GTK_WAIT/${GTK_WAIT:-60}/" "$TMPD/g.sh"
printf 'root:x:0:0:root:/root:/bin/sh\n' > "$TMPD/passwd"; printf '127.0.0.1 localhost\n' > "$TMPD/hosts"
A=(build "$TMPD/disk.img" ${GTK_BLOCKS:-131072} --v3 --inodes=2048 /lib/ "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf"
   /bin/ /t/ /tmp/ /var/ /var/log/ /etc/ /etc/fonts/ /usr/ /usr/bin/ /usr/lib/ /usr/share/ /usr/share/fonts/ /usr/share/glib-2.0/ /usr/share/glib-2.0/schemas/ /usr/share/wayd/ /usr/share/X11/ /usr/share/X11/xkb/ /root/ /dev/ /proc/ /run/
   "/lib/ld-musl-x86_64.so.1=$LDREAL" "/bin/busybox=$STONES/busybox" "/etc/passwd=$TMPD/passwd" "/etc/hosts=$TMPD/hosts"
   "/usr/share/wayd/keymap-us.xkb=$TMPD/km/keymap-us.xkb" "/usr/share/wayd/keymap-de.xkb=$TMPD/km/keymap-de.xkb" "/t/g.sh=$TMPD/g.sh" "/t/launch.sh=$TMPD/launch.sh")
[ -f assets/osum-icons.ttf ] && A+=("/lib/icons.ttf=assets/osum-icons.ttf")
for p in sh sleep echo cat ls wayd; do A+=("/bin/$p=$TMPD/bin/$p.elf"); done
# the foot stones bring fonts.conf + the xkb data; the gtk manifest brings the libraries, the probes and the compiled gsettings schemas
# a guest path in both manifests (libffi, libxkbcommon ...): the gtk build wins (mkfs refuses a path twice)
declare -A GTKG=()
while IFS== read -r g h; do case $g in /usr/lib/*|/usr/bin/*|/usr/share/glib-2.0/*) GTKG[$g]=1;; esac; done < "$GS/gtk/manifest.txt"
while IFS== read -r g h; do case $g in /usr/lib/*|/usr/share/X11/*|/etc/*|/usr/share/fonts/*) [ -n "${GTKG[$g]:-}" ] || A+=("$g=$h");; esac; done < "$STONES/foot/manifest.txt" 2>/dev/null
while IFS== read -r g h; do case $g in /usr/lib/*|/usr/bin/*|/usr/share/glib-2.0/*) A+=("$g=$h");; esac; done < "$GS/gtk/manifest.txt"
python3 tools/osum/mkfs.py "${A[@]}" > "$TMPD/mkfs.txt" 2>&1 && ok "the disk: $(stat -c%s "$TMPD/disk.img") octets" \
    || { bad "mkfs"; tail -3 "$TMPD/mkfs.txt" | sed 's/^/        /'; echo "GTK: $pass passed, $fail failed"; exit 1; }

echo "== 2. boot: glib-hello, then wayd + gtk4-hello =="
SOCK="$TMPD/mon.sock"; rm -f "$SOCK"
ACC=(); [ -w /dev/kvm ] && ACC=(-accel kvm -cpu host)
timeout 700 qemu-system-x86_64 "${ACC[@]}" -kernel "$TMPD/k0.img" -m 1536 \
    -append "gfx disp wm wmdauer wmshell osum vfs bus ${KARGS:-} script=sh /t/g.sh;exit" \
    -serial "file:$TMPD/ser.txt" -display none -no-reboot -vga std \
    -monitor "unix:$SOCK,server,nowait" \
    -drive "file=$TMPD/disk.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/qemu.txt" 2>&1 &
QPID=$!
waitfor() { local i=0; while [ $i -lt $(( $2 * 5 )) ]; do grep -qaF -- "$1" "$TMPD/ser.txt" 2>/dev/null && return 0; kill -0 "$QPID" 2>/dev/null || return 1; sleep 0.2; i=$((i + 1)); done; return 1; }
clean() { tr -cd '\11\12\15\40-\176' < "$TMPD/ser.txt" | tr -d '\r'; }
shot() { printf 'screendump %s\n' "$1" | timeout 20 socat - "UNIX-CONNECT:$SOCK" >/dev/null 2>&1; sleep 3; }
waitfor "==G-GLIBDONE==" 240 && ok "glib-hello ran to its end" || bad "glib-hello did not finish"
if waitfor "==G-READY==" 300; then ok "the script got to the end of the wait"; else bad "the script did not get ready"; fi
sleep 3
clean > "$TMPD/ser.clean"
G=$(sed -n 's/.*GLIB-RESULT \(.*\)/\1/p' "$TMPD/ser.clean" | head -1)
note "glib result: ${G:-none}"
has "$(cat "$TMPD/ser.clean")" "GLIB-START" "glib main loop probe started"
has "$G" "ticks=6" "glib timeouts fired 6 times"
has "$G" "pipe=1" "glib io watch on a pipe fired (epoll)"
has "$G" "sig=1" "glib UNIX signal source fired (signalfd/self-pipe)"
has "$G" "thread=1" "glib thread ran"
has "$(cat "$TMPD/ser.clean")" "GLIB-DGRAMPAIR" "socketpair(SOCK_DGRAM) works (GLib/GDBus need it)"
has "$(cat "$TMPD/ser.clean")" "GLIB-SPAWN spawnok" "g_spawn_command_line_sync works (fork/exec/pipe)"
has "$(cat "$TMPD/ser.clean")" "GLIB-DONE" "glib-hello exits cleanly"
has "$(cat "$TMPD/ser.clean")" "GTK4-ACTIVATE" "GTK4 application activated (display opened)"
has "$(cat "$TMPD/ser.clean")" "GTK4-PRESENT" "GTK4 window presented"
shot "$TMPD/gtk.ppm"
PX=$(python3 - "$TMPD/gtk.ppm" <<'PY' 2>/dev/null
import sys
d=open(sys.argv[1],'rb').read()
# P6 w h 255
parts=d.split(b'\n',3); w,h=map(int,parts[1].split()); px=parts[3]
seen={}
for i in range(0,len(px)-2,3*7):
    seen[px[i:i+3]]=seen.get(px[i:i+3],0)+1
print("colours=%d top=%d"%(len(seen),max(seen.values())*100//(len(px)//21)))
PY
)
note "screenshot: ${PX:-unreadable}"
[ -s "$TMPD/gtk.ppm" ] && ok "a screenshot was taken" || bad "no screenshot"
if [ -n "${KEEP_OUT:-}" ]; then cp "$TMPD/ser.clean" "$KEEP_OUT.ser"; cp "$TMPD/gtk.ppm" "$KEEP_OUT.ppm" 2>/dev/null; fi
! grep -aq 'Protocol error\|: error [0-9]*: wl_' "$TMPD/ser.clean" && ok "wayd sent gtk no protocol error" || bad "gtk got a wayd protocol error: $(grep -a -m1 ': error [0-9]*: wl_' "$TMPD/ser.clean")"
NFAULT=$(grep -ac 'user fault' "$TMPD/ser.clean")
[ "$NFAULT" -eq 0 ] && ok "no user fault" || bad "$NFAULT user fault(s)"
note "serial lines: $(wc -l < "$TMPD/ser.clean"); interesting lines:"
grep -a -i 'gtk\|glib\|wayd\|err\|warn\|fault\|ENOSYS\|fremd' "$TMPD/ser.clean" | head -${GTK_LOGLINES:-60} | sed 's/^/        | /'
printf 'quit\n' | socat - "UNIX-CONNECT:$SOCK" >/dev/null 2>&1
wait "$QPID" 2>/dev/null
echo "GTK: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
