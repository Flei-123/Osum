#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
. tools/lib/firnenv.sh
ULD=kernel/user/user.ld
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
seg() { awk -v n="@@$2" '/^@@/{on=($0==n);next} on' "$1" | tr -d '\r'; }
has() { seg "$1" "$2" | grep -qaE -- "$3" && ok "$4" || bad "$4 -- '$3' missing in @@$2"; }
hasnot() { seg "$1" "$2" | grep -qaE -- "$3" && bad "$4 -- '$3' present in @@$2" || ok "$4"; }

[ -x "$FIRNC" ] || { echo "firnc missing: $FIRNC"; exit 1; }
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "LXAPP: skipped, qemu-system-x86_64 missing"; exit 0; }
ACCEL=""
[ -r /dev/kvm ] && [ -w /dev/kvm ] && ACCEL="-accel kvm -cpu host"

echo "== 1. build =="
bash tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/b0.txt" 2>&1 && ok "kernel builds" || { bad "kernel build failed"; head -12 "$TMPD/b0.txt"; }
[ -f "$TMPD/k0.img" ] || { echo "LXAPP: $pass passed, $((fail+1)) failed"; exit 1; }
SRC="$TMPD/src"
mkdir -p "$SRC"
cp -r kernel/user/. "$SRC/"; cp tools/xfx/*.fi "$SRC/"
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s does not assemble"
PROGS="sh echo cat sleep tar lxapp xfxt xfxstub"
for p in $PROGS; do
    "$FIRNC" "$SRC/$p.fi" -o "$TMPD/$p.o" >"$TMPD/e$p" 2>&1 || { bad "firnc fails on $p.fi"; head -6 "$TMPD/e$p"; continue; }
    ld -T "$ULD" --defsym=USER_ENTRY="_F0.u_start" -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null || { bad "ld fails on $p"; continue; }
    strip --strip-all "$TMPD/$p.elf"
done
[ -f "$TMPD/lxapp.elf" ] && [ -f "$TMPD/xfxstub.elf" ] && ok "programs built: $PROGS" || bad "programs missing"
undef=$(nm -u "$TMPD/lxapp.elf" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
[ -z "$undef" ] && ok "lxapp has no undefined symbols" || bad "lxapp undefined: $undef"

echo "== 2. images =="
python3 -I tools/lxapp/mkfixtures.py "$TMPD" || bad "fixture generation failed"
[ -f "$TMPD/stubapp.manifest" ] && ok "fixtures written" || bad "fixtures missing"

cat > "$TMPD/main.sh" <<'SCRIPT'
echo @@usage
/bin/lxapp
echo rc=$?
/bin/lxapp nosuch status
echo rc=$?
/bin/lxapp stubapp bogus
echo rc=$?
echo @@fresh
/bin/lxapp stubapp status
/bin/lxapp stubapp start
echo rc=$?
echo @@install
/bin/lxapp stubapp install
/bin/xfxt waitfor /run/lx-stubapp.install done 120
/bin/lxapp stubapp status
/bin/xfxt exists /usr/bin/stubapp
/bin/xfxt exists /usr/share/lx/stubapp.tar
/bin/xfxt exists /usr/share/lx/stubapp.tar.part000
/bin/xfxt exists /usr/share/lx/stubapp.tar.part001
echo @@noruntime
/bin/xfxt sess 1000
/bin/lxapp stubapp start
echo rc=$?
/bin/lxapp linuxrt install
/bin/xfxt waitfor /run/lx-linuxrt.install done 120
/bin/lxapp linuxrt status
/bin/lxapp linuxrt start
echo rc=$?
echo @@start
/bin/lxapp stubapp start
echo rc=$?
/bin/lxapp stubapp status
/bin/xfxt procs
/bin/xfxt exists /run/lx-stubapp.app
echo @@twice
/bin/lxapp stubapp start
echo rc=$?
echo @@stop
/bin/lxapp stubapp stop
echo rc=$?
/bin/lxapp stubapp status
/bin/xfxt procs
echo @@restart
/bin/lxapp stubapp start
echo rc=$?
/bin/lxapp stubapp stop
echo @@bad
/bin/lxapp badapp install
/bin/xfxt waitfor /run/lx-badapp.install failed 120
/bin/lxapp badapp status
/bin/xfxt exists /usr/bin/badapp
/bin/xfxt exists /usr/share/lx/badapp.installed
/bin/lxapp badapp start
echo rc=$?
echo @@log
cat /var/log/lx-stubapp.log
echo @@end
SCRIPT

DIRS="/bin/ /etc/ /run/ /tmp/ /t/ /var/ /var/log/ /usr/ /usr/bin/ /usr/share/ /usr/share/lx/ /lib/ /apps/ /apps/stubapp.osp/ /apps/linuxrt.osp/ /apps/badapp.osp/ /home/@755:0:0 /home/justin/@700:1000:1000"
BASE=""
for p in sh echo cat sleep tar lxapp xfxt; do BASE="$BASE /bin/$p=$TMPD/$p.elf"; done
BASE="$BASE /bin/wayd=$TMPD/xfxstub.elf /etc/passwd=$TMPD/passwd@644:0:0 /etc/group=$TMPD/group@644:0:0"
PKG=""
for app in stubapp linuxrt badapp; do
    PKG="$PKG /apps/$app.osp/lx.app=$TMPD/$app.lx.app@644:0:0 /apps/$app.osp/lx.manifest=$TMPD/$app.manifest@644:0:0"
    for part in "$TMPD"/$app.part*; do PKG="$PKG /usr/share/lx/$app.tar.${part##*.}=$part@644:0:0"; done
done
bash tools/mkfsfi/mkfs.sh build "$TMPD/main.img" 16384 $DIRS $BASE $PKG "/t/run.sh=$TMPD/main.sh@644:0:0" > "$TMPD/mkfs.txt" 2>&1 && ok "image built" || { bad "mkfs failed"; head -5 "$TMPD/mkfs.txt"; }

echo "== 3. run =="
timeout 400 qemu-system-x86_64 $ACCEL -kernel "$TMPD/k0.img" -m 512 -append "osum nokbd nosched noproc nofs noring3 vfs script=sh /t/run.sh" \
    -serial "file:$TMPD/main.txt" -display none -no-reboot -drive "file=$TMPD/main.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
M="$TMPD/main.txt"
[ -n "${LXAPP_KEEP:-}" ] && cp "$M" "$LXAPP_KEEP/lxapp-serial.txt"
grep -qa '^@@end' "$M" && ok "script ran to the end" || bad "script did not finish"
has "$M" usage 'usage: lxapp <name>' "no argument prints usage"
has "$M" usage '^rc=2' "usage returns 2"
has "$M" usage 'lx: no lx.app for package' "unknown package is named"
has "$M" fresh 'installed=no install=idle state=stopped' "fresh status"
has "$M" fresh 'not installed' "start refuses without installation"
has "$M" install 'install started' "install returns at once"
has "$M" install 'waitfor=ok' "install reaches done"
has "$M" install 'installed=yes install=done state=stopped' "status after install"
[ "$(seg "$M" install | grep -ac 'exists=yes')" = 1 ] && ok "binary extracted, tar and parts removed" || bad "wrong set of files after install"
has "$M" noruntime 'no desktop session|runtime not installed' "start refused before the runtime exists"
hasnot "$M" noruntime 'lx: started' "app does not start without the runtime"
has "$M" noruntime 'installed=yes install=done' "runtime installs like an app"
has "$M" noruntime 'a runtime has no window' "a runtime cannot be started"
has "$M" start 'lx: started uid=1000' "start reports uid 1000"
has "$M" start 'installed=yes install=done state=running pid=[0-9]+' "status running"
has "$M" start 'proc stubapp +uid=1000' "app runs as the session user"
has "$M" start 'proc wayd +uid=1000' "wayd runs as the session user"
hasnot "$M" start 'proc (stubapp|wayd) +uid=0' "nothing runs as root"
has "$M" start 'exists=yes' "pid file written"
has "$M" twice 'already running' "second start refused"
has "$M" stop 'lx: stopped' "stop reports stopped"
has "$M" stop 'state=stopped' "status after stop"
hasnot "$M" stop 'proc (stubapp|wayd) ' "app and wayd gone after stop"
has "$M" restart 'lx: started uid=1000' "restart works"
has "$M" bad 'waitfor=ok' "tampered package ends in failed"
has "$M" bad 'installed=no install=failed' "failed status"
[ "$(seg "$M" bad | grep -ac 'exists=no')" = 2 ] && ok "tampered package extracted nothing" || bad "tampered package left files"
has "$M" bad 'not installed' "tampered package cannot start"
has "$M" log 'xfxstub: wayd uid=1000' "wayd logged under the app log"
has "$M" log 'xfxstub: stubapp uid=1000 home=/home/justin xdg=/run/xfx-1000 args=3' "app got argv from lx.app and the session env"
echo "LXAPP: $pass passed, $fail failed"
[ "$fail" = 0 ]
