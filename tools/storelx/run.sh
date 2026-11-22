#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/pidkill.sh
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
. tools/lib/qemu.sh

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there and should not be" || ok "$3"; }
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1"; }

for t in qemu-system-x86_64 python3 musl-gcc; do
    command -v "$t" >/dev/null 2>&1 || { echo "STORELX: skipped, $t is missing"; exit 0; }
done
python3 -c 'import cryptography' 2>/dev/null || { echo "STORELX: skipped, python3-cryptography is missing"; exit 0; }

TMPD=$(mktemp -d)
SRVPIDS=""
cleanup() { for p in $SRVPIDS; do kill "$p" 2>/dev/null; done; [ -n "${STORELX_KEEP:-}" ] || rm -rf "$TMPD"; }
trap cleanup EXIT
BLOCKS=${BLOCKS:-30000}
export OSUM_CPU=${OSUM_CPU:-Haswell}
PROGS="sh ls cat echo sleep mkdir cp chmod rm orientbus act su stored opk ota xfx xfxstub tar lxapp xfxt"
SRV_PORT=${STORELX_PORT:-$(( 19000 + ($$ % 900) ))}
OPK=$(python3 tools/lib/opkpfad.py)
ULD=kernel/user/user.ld

echo "== 1. build =="
. tools/lib/firnenv.sh
mkdir -p "$TMPD/bin" "$TMPD/src"
cp -r kernel/user/. "$TMPD/src/"
cp tools/xfx/xfxstub.fi tools/xfx/xfxt.fi "$TMPD/src/"
if USRC="$TMPD/src" bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1; then
    ok "firnc0 builds $(echo $PROGS | wc -w) programs"
else
    bad "the programs do not build"; head -20 "$TMPD/b.txt" | sed 's/^/        /'
    echo "STORELX: $pass passed, $fail failed"; exit 1
fi
if "$FIRNC" -c --profile=app -o "$TMPD/fetch.o" kernel/app/fetch.fi > "$TMPD/fe.txt" 2>&1 \
        && ld -T "$ULD" -o "$TMPD/bin/fetch.elf" "$TMPD/fetch.o" 2>>"$TMPD/fe.txt"; then
    strip --strip-all "$TMPD/bin/fetch.elf"; ok "/bin/fetch builds"
else
    bad "fetch does not build"; head -5 "$TMPD/fe.txt"; echo "STORELX: $pass passed, $fail failed"; exit 1
fi
if ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1; then ok "the kernel builds"; else
    bad "the kernel does not build"; tail -5 "$TMPD/k.txt" | sed 's/^/        /'; echo "STORELX: $pass passed, $fail failed"; exit 1; fi
musl-gcc -static -O2 -nostartfiles -T tools/foreign/osum.ld -Wl,--build-id=none \
    -o "$TMPD/setsess" tools/foreign/start.s tools/foreign/osum_main.c tools/actionbus/setsess.c 2>"$TMPD/ss.txt" && ok "setsess builds" || bad "setsess does not build"

echo "== 2. signed Linux app source =="
mkdir -p "$TMPD/pk" "$TMPD/fix" "$TMPD/srv"
python3 "$OPK" schluessel "$TMPD/pk" > "$TMPD/key.log" 2>&1
cp "$TMPD/pk/oeffentlich.key" "$TMPD/pk/schluessel.pub"
cp "$TMPD/bin/xfxstub.elf" "$TMPD/fix/xfxstub.elf"
python3 -I tools/lxapp/mkfixtures.py "$TMPD/fix" || bad "fixtures"
python3 -I tools/storelx/mkstore.py --fixtures "$TMPD/fix" --launcher "$TMPD/bin/lxapp.elf" --out "$TMPD/srv/good" --key "$TMPD/pk/geheim.key" > "$TMPD/mk.log" 2>&1 \
    && ok "good source built" || { bad "mkstore"; tail -5 "$TMPD/mk.log"; }
python3 "$OPK" zeigen "$TMPD/srv/good/stubapp-1.opk" > "$TMPD/show.txt" 2>&1
for f in lx.app lx.manifest lx.files store.meta symbol start; do
    grep -qE "^  f $f " "$TMPD/show.txt" && ok "package holds $f" || bad "package misses $f"
done
cp -r "$TMPD/srv/good" "$TMPD/srv/flippart"
python3 - "$TMPD/srv/flippart/stubapp.tar.part000" <<'PY'
import sys
d = bytearray(open(sys.argv[1], "rb").read()); d[len(d) // 2] ^= 1; open(sys.argv[1], "wb").write(d)
PY
python3 tools/ota/mkcerts.py "$TMPD/certs" ota.test 10.0.2.2 > "$TMPD/certs.log" 2>&1 && ok "certificates" || bad "mkcerts"
serve() {
    python3 tools/ota/server.py --wurzel "$TMPD/srv/$1" --port "$2" --cert "$TMPD/certs/srv.pem" --key "$TMPD/certs/srv.key" \
        --log "$TMPD/srv-$1.log" > "$TMPD/srv-$1.out" 2>&1 &
    SRVPIDS="$SRVPIDS $!"
    local i
    for i in $(seq 1 40); do grep -qa "^START port=$2 " "$TMPD/srv-$1.log" 2>/dev/null && return 0; sleep 0.2; done
    return 1
}
P0=$SRV_PORT
serve good $P0 && serve flippart $((P0+1)) && ok "two HTTPS sources are up" || bad "a source does not start"

echo "== 3. the guest =="
printf 'installieren=admin\nentfernen=admin\nadmins=1000\n' > "$TMPD/conf.admin"
printf 'dryfirst jarvis\n' > "$TMPD/policy"
for n in 0 1; do
    printf 'quelle=https://10.0.2.2:%s\nname=ota.test\nabstand=3600\nauto=nein\nfrist=15\n' "$((P0+n))" > "$TMPD/ota.conf.$n"
done
printf 'root:x:0:0:root:/:/bin/sh\njustin:x:1000:1000:Justin:/home/justin:/bin/sh\n' > "$TMPD/passwd"
printf 'root:x:0:\njustin:x:1000:\n' > "$TMPD/group"
cat > "$TMPD/s.sh" <<'EOS'
mkdir /users/justin
orientbus serve 600000 &
sleep -m 300
stored serve 600000 &
sleep 1
setsess 1000
cp /etc/ota.conf.1 /etc/ota.conf
act call store.refresh
act confirm last
sleep 6
act call store.install name=stubapp
act confirm last
sleep 30
echo ==FLIP==
act call store.status
opk list
ls /usr/bin
ls /usr/share/lx
cp /etc/ota.conf.0 /etc/ota.conf
act call store.refresh
act confirm last
sleep 6
echo ==LIST==
act call store.list
act call store.install name=stubapp
act confirm last
sleep 40
echo ==INSTALLED==
act call store.status
opk list
ls /usr/bin
ls /usr/share/lx
ls /apps
/bin/lxapp stubapp status
/bin/lxapp stubapp start
echo rc=$?
sleep 3
echo ==RUNNING==
/bin/lxapp stubapp status
/bin/xfxt procs
/bin/lxapp stubapp stop
act call store.remove name=stubapp
act confirm last
sleep 10
echo ==REMOVED==
act call store.status
opk list
ls /usr/bin
ls /usr/share/lx
ls /apps
/bin/xfxt procs
echo ==FERTIG==
EOS
BASE=(build "$TMPD/g.img" $BLOCKS --v3 --inodes=512 --karten=64 /lib/
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf"
    /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /etc/actions.d/ /etc/orientbus/ /etc/ssl/ /store/ /apps/ /users/ /var/ /var/log/ /run/ /usr/ /usr/bin/ /usr/share/ /usr/share/lx/ /home/@755:0:0 /home/justin/@700:1000:1000)
for p in $PROGS fetch; do BASE+=("/bin/$p=$TMPD/bin/$p.elf"); done
BASE+=("/bin/wayd=$TMPD/bin/xfxstub.elf" "/bin/setsess=$TMPD/setsess"
    "/etc/passwd=$TMPD/passwd" "/etc/group=$TMPD/group"
    "/etc/actions.d/store.actions=etc/actions.d/store.actions"
    "/etc/orientbus/policy=$TMPD/policy"
    "/etc/store.conf=$TMPD/conf.admin"
    "/etc/ota.conf=$TMPD/ota.conf.0" "/etc/ssl/roots.pem=$TMPD/certs/ca.pem"
    "/system/schluessel.pub=$TMPD/pk/schluessel.pub"
    "/t/s.sh=$TMPD/s.sh")
for n in 0 1; do BASE+=("/etc/ota.conf.$n=$TMPD/ota.conf.$n"); done
bash tools/mkfsfi/mkfs.sh "${BASE[@]}" > "$TMPD/mkfs.txt" 2>&1 || { echo "mkfs failed"; tail -3 "$TMPD/mkfs.txt"; }
ACCEL="-cpu $OSUM_CPU"
[ -r /dev/kvm ] && [ -w /dev/kvm ] && ACCEL="-accel kvm -cpu host"
QEMU_LIMIT=${STORELX_TIMEOUT:-900}
timeout "$QEMU_LIMIT" qemu-system-x86_64 $ACCEL -smp 1 -kernel "$TMPD/k0.img" -m 768 \
    -append "osum vfs nokbd bus nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0 script=sh /t/s.sh;exit" \
    -serial "file:$TMPD/g.txt" -display none -no-reboot \
    -netdev user,id=n0 -device e1000,netdev=n0,mac=52:54:00:0a:0b:0c \
    -drive "file=$TMPD/g.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
QPID=$!
for _ in $(seq 1 $((QEMU_LIMIT / 2))); do
    grep -qa "==FERTIG==" "$TMPD/g.txt" 2>/dev/null && break
    kill -0 "$QPID" 2>/dev/null || break
    sleep 2
done
sleep 2
osum_kill_tree "$QPID"
wait "$QPID" 2>/dev/null
tr -cd '\11\12\15\40-\176' < "$TMPD/g.txt" > "$TMPD/g.klar" 2>/dev/null || true
G="$TMPD/g.klar"
grep -qa '==FERTIG==' "$G" || { bad "the guest did not finish"; tail -25 "$G" | sed 's/^/        /'; }

echo "== 4. flipped part: refused, nothing left =="
part "$G" FLIP LIST > "$TMPD/p.txt"
has "$TMPD/p.txt" "phase=failed" "flipped part: the store reports the failure"
hasnot "$TMPD/p.txt" "  stubapp -> " "flipped part: stubapp is not in the package list"
hasnot "$TMPD/p.txt" "stubapp.installed" "flipped part: no install marker"

echo "== 5. install, start, remove =="
part "$G" INSTALLED RUNNING > "$TMPD/p.txt"
has "$TMPD/p.txt" "phase=done" "install through the store: done"
has "$TMPD/p.txt" "  stubapp -> " "stubapp is in the package list"
has "$TMPD/p.txt" "stubapp" "the payload binary is under /usr/bin"
has "$TMPD/p.txt" "stubapp.installed" "install marker written"
has "$TMPD/p.txt" "linuxrt.installed" "the runtime came with it"
has "$TMPD/p.txt" "installed=yes" "lxapp says installed"
part "$G" RUNNING REMOVED > "$TMPD/p.txt"
has "$TMPD/p.txt" "state=running" "the app is running"
has "$TMPD/p.txt" "proc stubapp" "the app process exists"
has "$TMPD/p.txt" "proc wayd" "wayd (window server) runs for the app"
grep -qaE "proc (stubapp|wayd) +uid=0" "$TMPD/p.txt" && bad "app or wayd runs as root" || ok "app and wayd do not run as root"
grep -qaE "proc stubapp +uid=1000" "$TMPD/p.txt" && ok "the app runs as the session user" || bad "the app does not run as uid 1000"
part "$G" REMOVED FERTIG > "$TMPD/p.txt"
has "$TMPD/p.txt" "msg=entfernt" "remove through the store: done"
hasnot "$TMPD/p.txt" "  stubapp -> " "stubapp is gone from the package list"
hasnot "$TMPD/p.txt" "stubapp.osp" "/apps/stubapp.osp is gone"
hasnot "$TMPD/p.txt" "stubapp.installed" "install marker removed"
hasnot "$TMPD/p.txt" "proc stubapp" "the app process is gone"
awk '/^==REMOVED==/{f=1} f' "$G" | sed -n '1,40p' | grep -qx "stubapp" && bad "payload binary still under /usr/bin" || ok "payload binary removed from /usr/bin"

echo "STORELX: $pass passed, $fail failed"
[ "$fail" = 0 ] || { echo "-- guest log (tail) --"; grep -av "^fetch:" "$G" | tail -n "${STORELX_TAIL:-300}" | cut -c1-200; }
[ "$fail" = 0 ]
