#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/wayland/foot.sh -- PROOF STONE foot (r701): the real foot 1.19.0 terminal (musl, dynamic, 9 libraries) runs on wayd.
#
#   bash tools/unterbau/build-foot-stones.sh /root/stones      (once; heavy)
#   /root/jarvis/bin/heavy bash tools/wayland/foot.sh [<work dir>]
#
# Boots the window server with wayd, starts /usr/bin/foot (libwayland-client, fcft, freetype, fontconfig, pixman, xkbcommon) with
# busybox sh as its child on a PTY (/dev/ptmx), and checks: foot opens its window (wayd log), the PTY child runs, the screenshot has
# foot's background colour AND text pixels in the window, a key typed on the host reaches the shell in foot and the shell's answer shows.
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
TMPD=${1:-$(mktemp -d)}
[ -n "${1:-}" ] || trap 'rm -rf "$TMPD"' EXIT
mkdir -p "$TMPD/bin"
[ -r "$STONES/foot/manifest.txt" ] && [ -r "$STONES/busybox" ] || { echo "FOOT: no foot stones in $STONES (tools/unterbau/build-foot-stones.sh), skipped"; exit 0; }
LDREAL=$(readlink -f /lib/ld-musl-x86_64.so.1 2>/dev/null || true)
[ -r "$LDREAL" ] || LDREAL=/usr/lib/x86_64-linux-musl/libc.so
PROGS="sh sleep echo cat ls wayd"

echo "== 1. build =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
python3 tools/wayland/genkeys.py --keymaps "$TMPD/km" 2>"$TMPD/km.txt" && ok "keymaps compiled" || bad "keymap generation: $(cat "$TMPD/km.txt")"
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1; then ok "firnc0 builds $(echo $PROGS | wc -w) programs"
else bad "the programs do not build"; tail -15 "$TMPD/b.txt" | sed 's/^/        /'; echo "FOOT: $pass passed, $fail failed"; exit 1; fi
if ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1; then ok "the kernel builds"
else bad "the kernel does not build"; tail -5 "$TMPD/k.txt" | sed 's/^/        /'; echo "FOOT: $pass passed, $fail failed"; exit 1; fi

cat > "$TMPD/g.sh" <<'EOS'
wayd /tmp/wayland-0 2000000000 &
sleep 2
busybox sh /t/launch.sh &
sleep FOOT_WAIT
echo ==F-READY==
busybox cat /tmp/foot.marker
sleep KEY_WAIT
echo ==KEYS==
busybox cat /tmp/key.marker
sleep 400
echo ==FERTIG==
EOS
cat > "$TMPD/launch.sh" <<'EOS'
export XDG_RUNTIME_DIR=/tmp HOME=/root TERM=xterm-256color SHELL=/bin/busybox FONTCONFIG_FILE=/etc/fonts/fonts.conf WAYLAND_DISPLAY=/tmp/wayland-0
# The kernel has 16 descriptors per process (file.MAX_FD): foot needs ~17, so stdin/stdout go (logs stay on stderr).
exec /usr/bin/foot -d info -f monospace:size=12 /bin/busybox sh /t/child.sh <&- >&-
EOS
cat > "$TMPD/child.sh" <<'EOS'
echo FOOT-CHILD-UP > /tmp/foot.marker
export PS1='osum# '
exec /bin/busybox sh
EOS
# One SHM object of this kernel holds at most 1 MiB (kernel/fs/unixsock.fi SHM_PAGES_MAX): foot's default is a sparse 512 MiB pool, so ask
# for one buffer per pool and a window that fits in it.
cat > "$TMPD/foot.ini" <<'EOS'
[main]
initial-window-size-pixels=560x340
pad=4x4
[tweak]
max-shm-pool-size-mb=0
EOS
[ -z "${FOOT_GS:-}" ] || cp "$FOOT_GS" "$TMPD/g.sh"
sed -i "s/FOOT_WAIT/${FOOT_WAIT:-25}/; s/KEY_WAIT/${KEY_WAIT:-30}/" "$TMPD/g.sh"
printf 'root:x:0:0:root:/root:/bin/sh\n' > "$TMPD/passwd"; printf '127.0.0.1 localhost\n' > "$TMPD/hosts"
A=(build "$TMPD/disk.img" ${FOOT_BLOCKS:-98304} --v3 --inodes=1024 /lib/ "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf"
   /bin/ /t/ /tmp/ /var/ /var/log/ /etc/ /etc/fonts/ /usr/ /usr/bin/ /usr/lib/ /usr/share/ /usr/share/fonts/ /usr/share/wayd/ /usr/share/X11/ /usr/share/X11/xkb/ /root/ /root/.config/ /root/.config/foot/ /dev/ /proc/ /run/
   "/lib/ld-musl-x86_64.so.1=$LDREAL" "/bin/busybox=$STONES/busybox" "/etc/passwd=$TMPD/passwd" "/etc/hosts=$TMPD/hosts"
   "/usr/share/wayd/keymap-us.xkb=$TMPD/km/keymap-us.xkb" "/usr/share/wayd/keymap-de.xkb=$TMPD/km/keymap-de.xkb" "/t/g.sh=$TMPD/g.sh" "/t/child.sh=$TMPD/child.sh" "/t/launch.sh=$TMPD/launch.sh" "/root/.config/foot/foot.ini=$TMPD/foot.ini")
[ -f assets/osum-icons.ttf ] && A+=("/lib/icons.ttf=assets/osum-icons.ttf")
[ -f assets/osum-sans-bold.ttf ] && A+=("/lib/bold.ttf=assets/osum-sans-bold.ttf")
for p in sh sleep echo cat ls wayd; do A+=("/bin/$p=$TMPD/bin/$p.elf"); done
while IFS== read -r g h; do A+=("$g=$h"); done < "$STONES/foot/manifest.txt"
python3 tools/osum/mkfs.py "${A[@]}" > "$TMPD/mkfs.txt" 2>&1 && ok "the disk: $(stat -c%s "$TMPD/disk.img") octets" \
    || { bad "mkfs"; tail -3 "$TMPD/mkfs.txt" | sed 's/^/        /'; echo "FOOT: $pass passed, $fail failed"; exit 1; }

echo "== 2. boot: wayd + foot =="
SOCK="$TMPD/mon.sock"; rm -f "$SOCK"
ACC=(); [ -w /dev/kvm ] && ACC=(-accel kvm -cpu host)
timeout 700 qemu-system-x86_64 "${ACC[@]}" -kernel "$TMPD/k0.img" -m 768 \
    -append "gfx disp wm wmdauer wmshell osum vfs bus ${KARGS:-} script=sh /t/g.sh;exit" \
    -serial "file:$TMPD/ser.txt" -display none -no-reboot -vga std \
    -monitor "unix:$SOCK,server,nowait" \
    -drive "file=$TMPD/disk.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/qemu.txt" 2>&1 &
QPID=$!
waitfor() { local i=0; while [ $i -lt $(( $2 * 5 )) ]; do grep -qaF -- "$1" "$TMPD/ser.txt" 2>/dev/null && return 0; kill -0 "$QPID" 2>/dev/null || return 1; sleep 0.2; i=$((i + 1)); done; return 1; }
clean() { tr -cd '\11\12\15\40-\176' < "$TMPD/ser.txt" | tr -d '\r'; }
shot() { printf 'screendump %s\n' "$1" | timeout 20 socat - "UNIX-CONNECT:$SOCK" >/dev/null 2>&1; sleep 3; }
mon()  { printf '%s\n' "$1" | timeout 10 socat - "UNIX-CONNECT:$SOCK" >/dev/null 2>&1; sleep 0.15; }
keys() { local c k; for ((n = 0; n < ${#1}; n++)); do c=${1:n:1}
    case "$c" in ' ') k=spc ;; '>') k=shift-dot ;; '/') k=slash ;; '.') k=dot ;; '-') k=minus ;; '#') k=shift-3 ;; [a-z0-9]) k=$c ;; [A-Z]) k=shift-${c,,} ;; *) continue ;; esac
    mon "sendkey $k"; done; mon "sendkey ret"; }
if waitfor "==F-READY==" 300; then ok "the script got to the end of the wait"; else bad "the script did not get ready"; fi
sleep 3
clean > "$TMPD/ser.clean"
shot "$TMPD/foot.ppm"
note "foot prompt screen: $(python3 tools/wayland/footpix.py "$TMPD/foot.ppm" 2>&1)"
P1=$(python3 tools/wayland/footpix.py "$TMPD/foot.ppm" 2>/dev/null)
pv() { sed -n "s/.*\b$2=\([0-9-]*\).*/\1/p" <<< "$1"; }
[ "$(pv "$P1" bg)" -ge 20000 ] 2>/dev/null && ok "foot's background (#242424) fills the terminal grid: $(pv "$P1" bg) px" || bad "no foot background in the screenshot"
[ "$(pv "$P1" text)" -ge 20 ] 2>/dev/null && ok "text pixels in the grid (prompt/cursor): $(pv "$P1" text)" || bad "no text pixels in the foot window"
[ "$(pv "$P1" dist)" -ge 3 ] 2>/dev/null && ok "the grid is not a flat fill ($(pv "$P1" dist) colours)" || bad "the grid is a flat fill"
echo "== 3. keyboard echo =="
keys "echo footkeyok > /tmp/key.marker"
sleep 4
shot "$TMPD/foot2.ppm"
P2=$(python3 tools/wayland/footpix.py "$TMPD/foot2.ppm" 2>/dev/null)
note "foot after typing:  $P2"
[ "$(pv "$P2" text)" -gt "$(( $(pv "$P1" text) + 60 ))" ] 2>/dev/null && ok "typed text is drawn: text pixels $(pv "$P1" text) -> $(pv "$P2" text)" || bad "typing changed no pixels ($(pv "$P1" text) -> $(pv "$P2" text))"
waitfor "==KEYS==" 120 || true
sleep 2
clean > "$TMPD/ser.clean"
grep -aq '^footkeyok' "$TMPD/ser.clean" && ok "the shell inside foot received the keys and ran the command" || bad "the keys did not reach the shell (no footkeyok)"
if [ -n "${KEEP_OUT:-}" ]; then cp "$TMPD/ser.clean" "$KEEP_OUT.ser"; cp "$TMPD/foot.ppm" "$KEEP_OUT.ppm" 2>/dev/null; cp "$TMPD/foot2.ppm" "$KEEP_OUT.2.ppm" 2>/dev/null; fi
note "serial lines: $(wc -l < "$TMPD/ser.clean"); foot lines:"
grep -a -i 'foot\|wayd\|err\|warn\|fault' "$TMPD/ser.clean" | head -${FOOT_LOGLINES:-40} | sed 's/^/        | /'
printf 'quit\n' | socat - "UNIX-CONNECT:$SOCK" >/dev/null 2>&1
wait "$QPID" 2>/dev/null
echo "FOOT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
