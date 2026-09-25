#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/usbimg/live.sh -- ROUND LIVE: THE ACCEPTANCE OF THE PUBLIC STICK.
#
#   bash tools/usbimg/live.sh [workdir]
#   BAU=<dir with orientos-usb.img from IMAGE_PROFILE=public> bash tools/usbimg/live.sh
#
# The public download image must behave like a Linux live stick. This run
# measures exactly that, on the image file itself:
#
#   1. WHAT IS IN IT. No personal account: /etc/passwd, /etc/shadow,
#      /etc/group and /users/ name root (locked) and `live` and nobody
#      else, the bridge is off (tools/usbimg/pubcheck.py). The menu has
#      "... Live (try without installing)" first and "Install ..." second,
#      the installer is pinned in the taskbar.
#   2. THE LIVE DESKTOP. Entry 1, under UEFI, with an empty disk attached:
#      glogin signs `live` in by itself (uid 1000), the desktop comes, no
#      sign-in screen. Afterwards the STICK AND THE DISK ARE BIT FOR BIT
#      WHAT THEY WERE -- the live system wrote nothing anywhere.
#   3. CHANGES ARE GONE AFTER A RESTART. The "Command line" entry of the
#      SAME stick copy, twice: in the first boot a file is written into
#      the root and read back; in the second boot it is not there. The
#      stick is unchanged in between.
#   4. THE INSTALL ENTRY. Entry 2 opens the installer on top of the live
#      desktop; it finds the disk and writes nothing without the two
#      questions being answered.
#
# The installation itself (GPT, copy, boot from the disk without the
# stick, a file survives a restart) is tools/install/abnahme.sh, run with
# BAU pointing at a public build -- see docs/LIVE-STICK.md.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
TMPD=${1:-/tmp/osum-live}
mkdir -p "$TMPD"

pass=0; fail=0
ok()  { pass=$((pass + 1)); printf '  OK    %s\n' "$*"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$*"; }
hat() { grep -qaF "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 -- '$2' not in $(basename "$1")"; }
nicht() { grep -qaF "$2" "$1" 2>/dev/null && bad "$3 -- '$2' IS in $(basename "$1")" || ok "$3"; }

OVMF_CODE=""; OVMF_VARS=""
for c in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd; do
    [ -f "$c" ] && { OVMF_CODE=$c; break; }; done
for v in /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd; do
    [ -f "$v" ] && { OVMF_VARS=$v; break; }; done
KVM=()
[ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)

echo "== 0. the public image =="
BAU=${BAU:-$TMPD/bau}
if [ -z "${SCHNELL:-}" ] || [ ! -f "$BAU/orientos-usb.img" ]; then
    IMAGE_PROFILE=public PARTTAB=${PARTTAB:-mbr} bash tools/usbimg/build.sh "$BAU" \
        > "$TMPD/build.txt" 2>&1 || { tail -20 "$TMPD/build.txt"; echo "LIVE: build failed"; exit 1; }
fi
IMG="$BAU/orientos-usb.img"
[ -f "$IMG" ] && ok "public image built: $(stat -c%s "$IMG") octets" || { bad "no $IMG"; exit 1; }

echo "== 1. what is in it =="
if python3 tools/usbimg/pubcheck.py "$IMG" > "$TMPD/pubcheck.txt" 2>&1; then
    ok "$(cat "$TMPD/pubcheck.txt")"
else
    bad "pubcheck: $(tr '\n' ' ' < "$TMPD/pubcheck.txt")"
fi
# The COUNTER-CHECK: the personal build of the same tree must FAIL the
# check -- a checker that passes everything would pass the old image too.
if [ -n "${PERSONAL_IMG:-}" ] && [ -f "$PERSONAL_IMG" ]; then
    if python3 tools/usbimg/pubcheck.py "$PERSONAL_IMG" > "$TMPD/pubcheck-neg.txt" 2>&1; then
        bad "COUNTER-CHECK: pubcheck passes the personal image"
    else
        ok "COUNTER-CHECK: pubcheck rejects the personal image ($(grep -c 'NOT FIT' "$TMPD/pubcheck-neg.txt") reasons)"
    fi
fi
mcopy -o -i "$IMG@@1M" ::/limine.conf "$TMPD/limine.conf" >/dev/null 2>&1
t1=$(grep -E '^/[^/]' "$TMPD/limine.conf" | sed -n 1p)
t2=$(grep -E '^/[^/]' "$TMPD/limine.conf" | sed -n 2p)
case "$t1" in *"Live (try without installing)") ok "menu entry 1: '${t1#/}'" ;; *) bad "menu entry 1 is '$t1'" ;; esac
case "$t2" in /Install*) ok "menu entry 2: '${t2#/}'" ;; *) bad "menu entry 2 is '$t2'" ;; esac
grep -A5 "^$t2\$" "$TMPD/limine.conf" | grep -q 'wigapp=/bin/installer' \
    && ok "entry 2 opens /bin/installer" || bad "entry 2 does not start the installer"
grep -q '^default_entry: 1' "$TMPD/limine.conf" && ok "default entry is the live system" \
    || bad "default entry is not 1"
python3 - "$IMG" > "$TMPD/etc.txt" 2>&1 <<'PY'
import os, subprocess, sys, tempfile
sys.path.insert(0, 'tools/osum')
import mkfs
with tempfile.TemporaryDirectory() as w:
    r = os.path.join(w, 'root.img')
    subprocess.run(['mcopy', '-o', '-i', sys.argv[1] + '@@1M', '::/root.img', r], check=True)
    fs = mkfs.load(r)
    for p in ('/etc/taskbar.conf', '/etc/sperre.conf', '/etc/autologin'):
        ino = fs.resolve(p)
        print('==', p)
        print(fs.read_at(ino, 0, fs.iget(ino, mkfs.I_SIZE)).decode())
PY
grep -q '^pins=installer' "$TMPD/etc.txt" && ok "the installer is pinned first in the taskbar" \
    || bad "no 'pins=installer' in /etc/taskbar.conf"
grep -q '^leerlauf=0' "$TMPD/etc.txt" && ok "the live session does not lock itself" \
    || bad "/etc/sperre.conf locks the live session"

# ---------------------------------------------------------------------
# One entry of the shipped menu as the ONLY entry of a copy, timeout 0
# (the stick run's way, tools/stick/run.sh: typed arrow keys get lost).
eintrag_conf() { # <img> <title substring>
    local img=$1 titel=$2 c="$TMPD/eintrag.conf"
    mcopy -o -i "$img@@1M" ::/limine.conf "$c.orig" >/dev/null 2>&1 || return 1
    python3 - "$c.orig" "$c" "$titel" <<'PY' || return 1
import sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
start = next((i for i, l in enumerate(lines)
              if l.startswith("/") and not l.startswith("//") and sys.argv[3] in l), None)
if start is None:
    sys.exit(1)
end = next((j for j in range(start + 1, len(lines)) if lines[j].startswith("/")), len(lines))
open(sys.argv[2], "w", encoding="utf-8").write(
    "timeout: 0\ndefault_entry: 1\n\n" + "\n".join(lines[start:end]) + "\n")
PY
    mcopy -o -i "$img@@1M" "$c" ::/limine.conf >/dev/null 2>&1 || return 1
    mcopy -o -i "$img@@1M" "$c" ::/boot/limine.conf >/dev/null 2>&1 || return 1
}
warte_auf() { # file pattern seconds pid
    local i=0
    while [ $i -lt $(( $3 * 5 )) ]; do
        grep -qaF "$2" "$1" 2>/dev/null && return 0
        kill -0 "$4" 2>/dev/null || return 1
        sleep 0.2; i=$((i + 1))
    done
    return 1
}
schuss() { # monitor.sock out.png
    local ppm="$TMPD/shot.ppm"
    rm -f "$ppm"
    printf 'screendump %s\n' "$ppm" | socat - "UNIX-CONNECT:$1" >/dev/null 2>&1
    sleep 2
    [ -s "$ppm" ] && python3 -c "from PIL import Image; Image.open('$ppm').save('$2')" 2>/dev/null
}
tinte() {
    python3 -c "
from PIL import Image
from collections import Counter
im=Image.open('$1').convert('RGB'); px=im.load(); W,H=im.size
c=Counter(px[x,y] for y in range(0,H,2) for x in range(0,W,2))
print(int(100*(sum(c.values())-c.most_common(1)[0][1])/sum(c.values())))" 2>/dev/null || echo 0
}
# Boot a stick copy under UEFI with an empty disk, serial to a file.
gui_lauf() { # name stickcopy disk
    local d="$TMPD/$1"
    cp -f "$OVMF_VARS" "$d/vars.fd"
    rm -f "$d/ser.txt" "$d/mon.sock"
    timeout 400 qemu-system-x86_64 "${KVM[@]}" -m 2048 -smp 2 \
        -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF_CODE" \
        -drive "if=pflash,format=raw,unit=1,file=$d/vars.fd" \
        -device qemu-xhci,id=xhci \
        -drive "file=$2,format=raw,if=none,id=stick" \
        -device usb-storage,bus=xhci.0,drive=stick \
        -drive "file=$3,format=raw,if=ide,index=0" \
        -vga std -display none -no-reboot -net none \
        -serial "file:$d/ser.txt" \
        -monitor "unix:$d/mon.sock,server,nowait" > "$d/qemu.txt" 2>&1 &
    QPID=$!
}

if [ -z "$OVMF_CODE" ] || [ -z "$OVMF_VARS" ]; then
    bad "no OVMF on this machine -- the boot runs cannot run"
    echo "LIVE: $pass passed, $fail failed"; exit 1
fi

echo "== 2. the live desktop (entry 1, UEFI, an empty disk attached) =="
D="$TMPD/l1"; rm -rf "$D"; mkdir -p "$D"
cp -f "$IMG" "$D/stick.img"
eintrag_conf "$D/stick.img" "Live (try without installing)" || bad "entry 1 not written into the copy"
truncate -s 256M "$D/disk.img"
S0=$(sha256sum < "$D/stick.img" | cut -c1-64); P0=$(sha256sum < "$D/disk.img" | cut -c1-64)
gui_lauf l1 "$D/stick.img" "$D/disk.img"
warte_auf "$D/ser.txt" 'glogin: desktop pid=' 180 "$QPID" || true
sleep 30
schuss "$D/mon.sock" "$D/live-desktop.png"
printf 'quit\n' | socat - "UNIX-CONNECT:$D/mon.sock" >/dev/null 2>&1
wait "$QPID" 2>/dev/null
hat "$D/ser.txt" 'glogin: autologin live' "glogin signs 'live' in by itself"
hat "$D/ser.txt" 'glogin: uid=1000' "the session runs as uid 1000, not as root"
# `desktop: ready` is only said with /etc/uitrace; what the window
# server reports every few seconds is the desktop's own window: layer 0,
# the whole screen.
grep -aqE 'glogin: desktop pid=[0-9]' "$D/ser.txt" && ok "glogin started the desktop" \
    || bad "glogin did not start the desktop ($(grep -ao 'glogin: desktop pid=[-0-9]*' "$D/ser.txt" | tail -1))"
grep -aqE 'wm: fen i=[0-9]+ id=[0-9]+ x=0 y=0 w=[0-9]+ h=[0-9]+ lay=0 ' "$D/ser.txt" \
    && ok "the window server shows the desktop window (layer 0, full screen)" \
    || bad "no desktop window (layer 0) in the window server report"
nicht "$D/ser.txt" 'glogin: bereit' "no sign-in screen was shown"
nicht "$D/ser.txt" 'justin' "the word 'justin' appears nowhere on the serial line"
if [ -s "$D/live-desktop.png" ]; then
    ink=$(tinte "$D/live-desktop.png")
    [ "${ink:-0}" -ge 3 ] && ok "photo of the live desktop: $ink % ink ($D/live-desktop.png)" \
        || bad "photo of the live desktop is empty ($ink % ink)"
else
    bad "no photo of the live desktop"
fi
S1=$(sha256sum < "$D/stick.img" | cut -c1-64); P1=$(sha256sum < "$D/disk.img" | cut -c1-64)
[ "$S0" = "$S1" ] && ok "the stick is bit for bit unchanged after the live session" \
    || bad "the live session WROTE to the stick"
[ "$P0" = "$P1" ] && ok "the disk is bit for bit unchanged -- nothing installed, nothing written" \
    || bad "the live session WROTE to the disk"
cp -f "$D/live-desktop.png" "$TMPD/" 2>/dev/null

echo "== 3. changes are gone after a restart (same stick copy, two boots) =="
D="$TMPD/l2"; rm -rf "$D"; mkdir -p "$D"
cp -f "$IMG" "$D/stick.img"
eintrag_conf "$D/stick.img" "Command line" || bad "'Command line' not written into the copy"
truncate -s 64M "$D/disk.img"
S0=$(sha256sum < "$D/stick.img" | cut -c1-64)
konsole() { # name console.py-args...
    local n=$1; shift
    timeout 300 qemu-system-x86_64 "${KVM[@]}" -m 1024 \
        -drive "file=$D/stick.img,format=raw,if=ide,index=0" \
        -drive "file=$D/disk.img,format=raw,if=ide,index=1" \
        -display none -no-reboot -vga std -net none \
        -serial "unix:$D/$n.sock,server,nowait" > "$D/$n.qemu" 2>&1 &
    local q=$!
    python3 tools/server/console.py "$D/$n.sock" "$D/$n.log" "$@" > "$D/$n.out" 2>&1
    kill "$q" 2>/dev/null; wait "$q" 2>/dev/null
}
konsole b1 --frist 150 --erwarte 'sh: ready' \
    --sende 'echo live-probe-4711 > /users/live/probe.txt\n' --frist 20 --erwarte 'echo -> ' \
    --sende 'cat /users/live/probe.txt\n' --frist 20 --erwarte 'cat -> ' \
    --sende 'sync\n' --frist 20 --erwarte 'sync -> '
grep -aq '^live-probe-4711' "$D/b1.log" || grep -aq 'live-probe-4711$' "$D/b1.log"
if [ "$(grep -ac 'live-probe-4711' "$D/b1.log")" -ge 2 ]; then
    ok "boot 1: a file written into the root reads back ('live-probe-4711')"
else
    bad "boot 1: the probe file did not read back"; tail -15 "$D/b1.log" | sed 's/^/       /'
fi
konsole b2 --frist 150 --erwarte 'sh: ready' \
    --sende 'cat /users/live/probe.txt\n' --frist 20 --erwarte 'cat -> ' \
    --sende 'ls /users/live\n' --frist 20 --erwarte 'ls -> '
if grep -aq 'sh: ready' "$D/b2.log"; then
    if grep -aqE 'live-probe-4711$|^live-probe-4711' "$D/b2.log"; then
        bad "boot 2: the file from boot 1 is STILL there"
    else
        ok "boot 2: the file from boot 1 is gone ($(grep -aoE 'cat -> [0-9-]+' "$D/b2.log" | head -1))"
    fi
else
    bad "boot 2: no shell"
fi
S1=$(sha256sum < "$D/stick.img" | cut -c1-64)
[ "$S0" = "$S1" ] && ok "the stick is unchanged after two boots with writes" \
    || bad "the stick changed between the boots"

echo "== 4. the install entry (entry 2) =="
D="$TMPD/l3"; rm -rf "$D"; mkdir -p "$D"
cp -f "$IMG" "$D/stick.img"
eintrag_conf "$D/stick.img" "Install " || bad "entry 2 not written into the copy"
truncate -s 256M "$D/disk.img"
P0=$(sha256sum < "$D/disk.img" | cut -c1-64)
gui_lauf l3 "$D/stick.img" "$D/disk.img"
warte_auf "$D/ser.txt" 'installer: ready' 200 "$QPID" || true
sleep 20
schuss "$D/mon.sock" "$D/live-installer.png"
printf 'quit\n' | socat - "UNIX-CONNECT:$D/mon.sock" >/dev/null 2>&1
wait "$QPID" 2>/dev/null
hat "$D/ser.txt" 'glogin: autologin live' "entry 2: the live user is signed in as well"
hat "$D/ser.txt" 'installer: ready' "entry 2: the installer is open"
# `installer: ready n=<disks>` and not `installer: disk /dev/hda`: the
# second line is torn by other programs on the serial line (measured:
# "installer: disk /dev/helf: start 17 ...").
grep -aqE 'installer: ready n=[1-9]' "$D/ser.txt" \
    && ok "the installer sees the empty disk ($(grep -aoE 'installer: ready n=[0-9]+' "$D/ser.txt" | tail -1))" \
    || bad "the installer found no disk ($(grep -aoE 'installer: ready n=[0-9]+' "$D/ser.txt" | tail -1))"
if [ -s "$D/live-installer.png" ]; then
    ok "photo of the installer on the live desktop: $(tinte "$D/live-installer.png") % ink"
    cp -f "$D/live-installer.png" "$TMPD/"
else
    bad "no photo of the installer"
fi
P1=$(sha256sum < "$D/disk.img" | cut -c1-64)
[ "$P0" = "$P1" ] && ok "without the two answers the installer wrote nothing" \
    || bad "the disk changed although nobody confirmed"
rm -f "$TMPD"/l?/stick.img "$TMPD"/l?/disk.img "$TMPD"/l?/vars.fd

echo "LIVE: $pass passed, $fail failed"
[ "$fail" = 0 ]
