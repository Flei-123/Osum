#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
mkdir -p "$TMPD/bin" "$TMPD/binold" "$TMPD/srcold" "$TMPD/bd"
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
PROGS="sh ls cat echo opk"

echo "== 1. build =="
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1; then ok "programs build"
else bad "programs do not build"; tail -8 "$TMPD/b.txt"; echo "STARTFRESH: $pass passed, $fail failed"; exit 1; fi
cp -a kernel/user/. "$TMPD/srcold/"
sed -i 's|^    apps_clear()$|    remove((\&P_APPS[0 as usize]) as u64)|' "$TMPD/srcold/opk.fi"
if grep -q '^    apps_clear()$' "$TMPD/srcold/opk.fi"; then bad "counter-proof patch did not apply"; fi
if USRC="$TMPD/srcold" bash tools/sync/build.sh "$TMPD/binold" 0 opk > "$TMPD/bo.txt" 2>&1; then ok "counter-proof opk (old rebuild: wipe /apps) builds"
else bad "counter-proof opk does not build"; tail -8 "$TMPD/bo.txt"; fi
if ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1; then ok "kernel builds"
else bad "kernel does not build"; tail -5 "$TMPD/k.txt"; echo "STARTFRESH: $pass passed, $fail failed"; exit 1; fi

HA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
printf 'name=Base\nkeys=base\nfassung=1\n' > "$TMPD/bd/base.info"
printf 'name=Alpha\nkeys=alpha\nfassung=1\n' > "$TMPD/bd/alpha.info"
printf '00000001\n' > "$TMPD/bd/AKTUELL"
printf 'alpha\t%s\n' "$HA" > "$TMPD/bd/PLAN"
printf 'new\n' > "$TMPD/bd/GRUND"
printf 'root:x:0:0:root:/:/bin/sh\n' > "$TMPD/passwd"
{
  echo "echo ==A0=="; echo "ls /apps"
  echo "opk rebuild"
  echo "echo ==A1=="; echo "ls /apps"; echo "cat /apps/base.osp/INFO"; echo "cat /apps/alpha.osp/INFO"
  echo "opk remove alpha"
  echo "echo ==A2=="; echo "ls /apps"; echo "cat /apps/base.osp/INFO"
  echo "echo ==FERTIG=="
} > "$TMPD/g.sh"

ACC=(); [ -w /dev/kvm ] && ACC=(-accel kvm -cpu host)
run_guest() {
  local opkelf=$1 ser=$2
  local A=(build "$TMPD/d.img" 16384 /lib/ /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /var/ /var/log/ /etc/ /apps/ /data/
     "/etc/passwd=$TMPD/passwd" /system/generations/ /system/generations/1/
     "/system/AKTUELL=$TMPD/bd/AKTUELL" "/system/generations/1/PLAN=$TMPD/bd/PLAN" "/system/generations/1/GRUND=$TMPD/bd/GRUND" /store/
     "/t/g.sh=$TMPD/g.sh"
     "/apps/base.osp/" "/apps/base.osp/INFO=$TMPD/bd/base.info"
     "/store/${HA:0:20}/" "/store/${HA:0:20}/INFO=$TMPD/bd/alpha.info")
  for p in $PROGS; do
    if [ "$p" = opk ]; then A+=("/bin/opk=$opkelf"); else A+=("/bin/$p=$TMPD/bin/$p.elf"); fi
  done
  python3 tools/osum/mkfs.py "${A[@]}" > "$TMPD/mkfs.txt" 2>&1 || { bad "mkfs"; tail -3 "$TMPD/mkfs.txt"; return 1; }
  rm -f "$ser"
  timeout 240 qemu-system-x86_64 "${ACC[@]}" -kernel "$TMPD/k0.img" -m 256 \
    -append "osum vfs bus script=sh /t/g.sh;exit" \
    -serial "file:$ser" -display none -no-reboot \
    -drive "file=$TMPD/d.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/qemu.txt" 2>&1
  tr -cd '\11\12\15\40-\176' < "$ser" > "$ser.clean"
}
section() { awk -v a="$2" -v b="$3" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1"; }

echo "== 2. guest: /apps keeps the bundled programs =="
run_guest "$TMPD/bin/opk.elf" "$TMPD/new.txt"
N="$TMPD/new.txt.clean"
grep -aq '==FERTIG==' "$N" && ok "guest script ran to the end" || { bad "guest script did not finish"; tail -12 "$N"; }
section "$N" '==A0==' '==A1==' | grep -aq 'base.osp' && ok "before: base.osp is in /apps" || bad "before: base.osp missing"
section "$N" '==A1==' '==A2==' | grep -aq 'alpha.osp' && ok "after rebuild: alpha.osp (from the plan) is in /apps" || bad "after rebuild: alpha.osp missing"
section "$N" '==A1==' '==A2==' | grep -aq 'base.osp' && ok "after rebuild: bundled base.osp is STILL in /apps" || bad "after rebuild: bundled base.osp is gone"
section "$N" '==A1==' '==A2==' | grep -aq 'name=Base' && ok "after rebuild: base.osp/INFO is readable" || bad "after rebuild: base.osp/INFO unreadable"
section "$N" '==A2==' '==FERTIG==' | grep -aq 'alpha.osp' && bad "after remove: alpha.osp is still in /apps" || ok "after remove: alpha.osp is gone"
section "$N" '==A2==' '==FERTIG==' | grep -aq 'base.osp' && ok "after remove: bundled base.osp is still there" || bad "after remove: bundled base.osp is gone"

echo "== 3. counter-proof: old rebuild (wipe /apps) =="
run_guest "$TMPD/binold/opk.elf" "$TMPD/old.txt"
O="$TMPD/old.txt.clean"
if section "$O" '==A1==' '==A2==' | grep -aq 'base.osp'; then bad "old opk kept base.osp -- the check is blind"; else ok "old opk wipes the bundled base.osp (the HP state): the check sees the bug"; fi

if [ "${STARTFRESH_GUI:-1}" = 1 ]; then
  echo "== 4. launcher reloads /apps when the menu is shown =="
  D="$TMPD/gui"
  bash tools/design/eh6.sh "$D" res=1280x800 accel=kvm drehbuch=tools/startfresh/dreh.txt > "$TMPD/gui.log" 2>&1
  S="$D/serial.txt"
  grep -aqE 'launcher: apps reloaded [0-9]+' "$S" && ok "the launcher reloaded the app list after a bundle appeared" || bad "no 'launcher: apps reloaded' after the bundle was created"
  grep -aq 'launcher: treffer i=[0-9]* name=\[ZzFresh\]' "$S" && ok "search finds the fresh app 'ZzFresh'" || bad "search does not find 'ZzFresh'"
  echo "== 5. counter-proof: refresh=off =="
  D2="$TMPD/gui2"
  bash tools/design/eh6.sh "$D2" res=1280x800 accel=kvm drehbuch=tools/startfresh/dreh.txt "xfile=/etc/startmenu.conf=$ROOT/tools/startfresh/off.conf" > "$TMPD/gui2.log" 2>&1
  grep -aq 'launcher: treffer i=[0-9]* name=\[ZzFresh\]' "$D2/serial.txt" && bad "refresh=off still finds ZzFresh -- the check is blind" || ok "refresh=off: the stale list does not find ZzFresh (the HP state)"
fi
echo
echo "STARTFRESH: $pass passed, $fail failed"
[ "$fail" = 0 ]
