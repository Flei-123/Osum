#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/trustdlg/run.sh -- the trusted confirmation dialog (kernel, wm.fi td_*) in a real guest.
#
#   bash tools/trustdlg/run.sh [workdir]        KERNEL_REF=<git ref> builds the kernel from an older tree
#
# An agent (client "helper") asks for a critical change; the window server draws its own dialog.
# Checks: the serial layout line (body end <= hint row < button row < dialog bottom: no overlap),
# the default focus is "Ablehnen" (Enter alone = no), Tab moves the focus, Enter on "Erlauben" =
# yes, the change happens only after yes, a rejected one is not done. Photos in the workdir.
# Counter-proof: KERNEL_REF=<commit before the layout rework> must FAIL (no layout line).
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1"; }

TMPD=${1:-$(mktemp -d)}
mkdir -p "$TMPD/bin"
PROGS="sh ls cat echo sleep orientbus act settingsd settings"
echo "== 1. build =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1 && ok "programs build" \
    || { bad "programs do not build"; tail -8 "$TMPD/b.txt"; echo "TRUSTDLG: $pass passed, $fail failed"; exit 1; }
KSRC=$ROOT
if [ -n "${KERNEL_REF:-}" ]; then
    KSRC="$TMPD/kref"; mkdir -p "$KSRC"
    git archive "$KERNEL_REF" | tar -x -C "$KSRC"
    mkdir -p "$KSRC/vendor/firn"; cp -a vendor/firn/. "$KSRC/vendor/firn/" 2>/dev/null
    echo "        kernel from $KERNEL_REF"
fi
(cd "$KSRC" && ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0) > "$TMPD/k.txt" 2>&1 && ok "kernel builds" \
    || { bad "kernel does not build"; tail -5 "$TMPD/k.txt"; echo "TRUSTDLG: $pass passed, $fail failed"; exit 1; }

printf '# /etc/sperre.conf\nleerlauf=300\n' > "$TMPD/sperre.conf"
printf 'root:x:0:0:root:/:/bin/sh\n' > "$TMPD/passwd"
printf 'lang=de\n' > "$TMPD/locale.conf"
printf '# /etc/theme.conf\nscheme=day\nmode=light\naccent=\nshape=classic\n' > "$TMPD/theme.conf"
cat > "$TMPD/g.sh" <<'EOS'
orientbus serve 0 &
sleep -m 300
settingsd serve 0 &
sleep 1
settings debug page=11 &
sleep 6
echo ==T1==
act call settings.set key=lock.idle value=600 --as helper
sleep 14
act call settings.get key=lock.idle
echo ==T2==
act call settings.set key=lock.idle value=900 --as helper
sleep 14
act call settings.get key=lock.idle
echo ==TEND==
act stat
act stop
echo ==FERTIG==
EOS
A=(build "$TMPD/disk.img" 32768 /lib/ "/lib/mono.ttf=assets/osum-mono.ttf"
   "/lib/sans.ttf=assets/osum-sans.ttf" /bin/ /t/ /tmp/ /var/ /var/log/
   /etc/ /etc/actions.d/ /etc/orientbus/ /apps/
   "/etc/settings.schema=etc/settings.schema"
   "/etc/actions.d/settings.actions=etc/actions.d/settings.actions"
   "/etc/orientbus/policy=etc/orientbus/policy"
   "/etc/sperre.conf=$TMPD/sperre.conf" "/etc/theme.conf=$TMPD/theme.conf"
   "/etc/passwd=$TMPD/passwd" "/etc/locale.conf=$TMPD/locale.conf"
   /usr/ /usr/share/ /usr/share/locale/ /usr/share/locale/de/ /usr/share/locale/en/
   "/usr/share/locale/de/messages=locale/de/messages"
   "/usr/share/locale/en/messages=locale/en/messages"
   "/t/g.sh=$TMPD/g.sh")
[ -f assets/osum-icons.ttf ] && A+=("/lib/icons.ttf=assets/osum-icons.ttf")
[ -f assets/osum-sans-bold.ttf ] && A+=("/lib/bold.ttf=assets/osum-sans-bold.ttf")
A+=(/etc/schemas/)
for s in assets/schemes/*.scheme; do A+=("/etc/schemas/$(basename "$s" .scheme)=$s"); done
for p in $PROGS; do A+=("/bin/$p=$TMPD/bin/$p.elf"); done
python3 tools/osum/mkfs.py "${A[@]}" > "$TMPD/mkfs.txt" 2>&1 && ok "disk built" \
    || { bad "mkfs"; tail -3 "$TMPD/mkfs.txt"; echo "TRUSTDLG: $pass passed, $fail failed"; exit 1; }

echo "== 2. boot =="
SOCK="$TMPD/mon.sock"; rm -f "$SOCK"
ACC=(); [ -w /dev/kvm ] && ACC=(-accel kvm -cpu host)
timeout 300 qemu-system-x86_64 "${ACC[@]}" -kernel "$TMPD/k0.img" -m 512 \
    -append "gfx disp wm wmdauer wmshell osum vfs bus script=sh /t/g.sh;exit" \
    -serial "file:$TMPD/ser.txt" -display none -no-reboot -vga std \
    -monitor "unix:$SOCK,server,nowait" \
    -drive "file=$TMPD/disk.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/qemu.txt" 2>&1 &
QPID=$!
waitfor() { local i=0; while [ $i -lt $(( $2 * 5 )) ]; do
        grep -qaF -- "$1" "$TMPD/ser.txt" 2>/dev/null && return 0
        kill -0 "$QPID" 2>/dev/null || return 1; sleep 0.2; i=$((i + 1)); done; return 1; }
nup() { local c; c=$(grep -ac 'wm: trusted dialog up no=' "$TMPD/ser.txt" 2>/dev/null); echo "${c:-0}"; }
waitn() { local i=0; while [ $i -lt $(( $1 * 5 )) ]; do [ "$(nup)" -ge "$2" ] && return 0; sleep 0.2; i=$((i + 1)); done; return 1; }
shot() { python3 tools/gfx/screenshot.py "$SOCK" "$1" 5 > /dev/null 2>&1; }
key() { echo "sendkey $1" > "$TMPD/kk.txt"; python3 tools/wm/monitor.py "$SOCK" "$TMPD/kk.txt" > /dev/null 2>&1; sleep 0.7; }

if waitn 120 1; then
    sleep 1.5; shot "$TMPD/1-up.ppm"
    key ret; sleep 1                       # default focus = Ablehnen -> Enter = no
    if ! grep -qaF 'wm: trusted dialog answer=2' "$TMPD/ser.txt"; then key ret; fi
fi
if waitn 60 2; then
    sleep 1.5; shot "$TMPD/2-up.ppm"
    L2=$(tr -cd '\11\12\15\40-\176' < "$TMPD/ser.txt" | grep -a 'wm: trusted dialog layout' | tail -1)
    FX=$(echo "$L2" | sed -nE 's/.* x=([0-9]+) w=([0-9]+).*/\1/p'); FW=$(echo "$L2" | sed -nE 's/.* x=([0-9]+) w=([0-9]+).*/\2/p')
    FY=$(echo "$L2" | sed -nE 's/.*layout y=([0-9]+).*/\1/p'); FH=$(echo "$L2" | sed -nE 's/.* h=([0-9]+).*/\1/p')
    if [ -n "$FX" ] && [ -n "$FY" ]; then
        python3 tools/trustdlg/flicker.py "$SOCK" "$TMPD" "$FX" "$FY" "$FW" "$FH" 20 > "$TMPD/flicker.txt" 2>&1
    fi
    key tab; shot "$TMPD/3-tab.ppm"        # focus -> Erlauben
    key ret
    sleep 2; shot "$TMPD/4-done.ppm"
fi
waitfor "==FERTIG==" 60 || echo "        no FERTIG before the time limit"
printf 'quit\n' | socat - "UNIX-CONNECT:$SOCK" >/dev/null 2>&1
wait "$QPID" 2>/dev/null
tr -cd '\11\12\15\40-\176' < "$TMPD/ser.txt" > "$TMPD/ser.klar"; G="$TMPD/ser.klar"
for q in "$TMPD"/*.ppm; do [ -s "$q" ] && python3 -c "from PIL import Image; Image.open('$q').save('${q%.ppm}.png')" 2>/dev/null; done

echo "== 3. checks =="
n=$(grep -ac 'wm: trusted dialog up no=' "$G")
[ "$n" -ge 2 ] && ok "dialog shown $n times" || bad "dialog shown $n times"
L=$(grep -a 'wm: trusted dialog layout' "$G" | head -1)
if [ -z "$L" ]; then bad "no layout line (old dialog)"; else
  eval "$(echo "$L" | sed -E 's/.*layout y=([0-9]+) body=([0-9]+)-([0-9]+) hint=([0-9]+) btn=([0-9]+) h=([0-9]+).*/Y=\1 B0=\2 B1=\3 H=\4 BT=\5 HH=\6/')"
  [ -n "${Y:-}" ] && echo "        $L"
  [ "${B1:-0}" -le "${H:-0}" ] && [ "${H:-0}" -lt "${BT:-0}" ] && ok "layout: body end $B1 <= hint $H < buttons $BT (no overlap)" || bad "layout overlaps: $L"
  [ "${BT:-0}" -lt $(( ${Y:-0} + ${HH:-0} )) ] && ok "buttons inside the dialog (bottom $((Y+HH)))" || bad "buttons outside the dialog: $L"
fi
part "$G" T1 T2 > "$TMPD/p1.txt"; part "$G" T2 TEND > "$TMPD/p2.txt"
has "$G" "wm: trusted dialog answer=2" "Enter on the default focus = Ablehnen (no)"
has "$TMPD/p1.txt" "value=300" "rejected: lock.idle stays 300"
has "$G" "wm: trusted dialog answer=1" "Tab + Enter = Erlauben (yes)"
has "$TMPD/p2.txt" "value=900" "after yes the change is done (900)"
if [ -s "$TMPD/flicker.txt" ]; then
  FL=$(grep -a '^flicker:' "$TMPD/flicker.txt" | tail -1); echo "        $FL"
  O=$(echo "$FL" | sed -nE 's/.*odd=([0-9]+).*/\1/p'); S=$(echo "$FL" | sed -nE 's/.*samples=([0-9]+).*/\1/p')
  [ "${S:-0}" -ge 10 ] && [ "${O:-1}" -eq 0 ] && ok "no flicker: $S screendumps, dialog area identical" || bad "flicker / too few samples: $FL"
else bad "no flicker measurement"; fi
for f in 1-up 2-up 3-tab 4-done; do [ -s "$TMPD/$f.png" ] && ok "photo $TMPD/$f.png" || bad "no photo $f"; done
echo "TRUSTDLG: $pass passed, $fail failed"
[ "$fail" = 0 ]
