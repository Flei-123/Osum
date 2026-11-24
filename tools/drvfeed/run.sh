#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
. tools/lib/qemu.sh
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there" || ok "$3"; }
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1"; }
for t in qemu-system-x86_64 python3 musl-gcc curl; do
    command -v "$t" >/dev/null 2>&1 || { echo "DRVFEED: skipped, $t is missing"; exit 0; }
done
python3 -c 'import cryptography' 2>/dev/null || { echo "DRVFEED: skipped, python3-cryptography is missing"; exit 0; }
D=${DRVFEED_DIR:-$(mktemp -d)}; mkdir -p "$D"
SRVPIDS=""
cleanup() { for p in $SRVPIDS; do kill "$p" 2>/dev/null; done; [ -n "${DRVFEED_KEEP:-}" ] || rm -rf "$D"; }
trap cleanup EXIT
export OSUM_CPU=${OSUM_CPU:-Haswell}
. tools/lib/firnenv.sh
PORT=${DRVFEED_PORT:-$(( 21000 + ($$ % 900) ))}

echo "== 1. build =="
bash tools/module/build.sh "$D/fwdemo.omod" --quelle module/store/fwdemo.fi > "$D/m.txt" 2>&1 && ok "fwdemo module builds and is signed" || { bad "fwdemo module"; tail -3 "$D/m.txt"; }
bash tools/module/build.sh "$D/edudemo.omod" --quelle module/store/edudemo.fi > "$D/m2.txt" 2>&1 && ok "edudemo module builds and is signed" || bad "edudemo module"
PROGS="sh cat echo ls cp rm mkdir drvctl drvfeed ota"
mkdir -p "$D/bin"
bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/b.txt" 2>&1 && ok "programs build ($PROGS)" || { bad "programs"; head -10 "$D/b.txt"; echo "DRVFEED: $pass passed, $fail failed"; exit 1; }
if "$FIRNC" -c --profile=app -o "$D/fetch.o" kernel/app/fetch.fi > "$D/fe.txt" 2>&1 && ld -T kernel/user/user.ld -o "$D/bin/fetch.elf" "$D/fetch.o" 2>>"$D/fe.txt"; then
    strip --strip-all "$D/bin/fetch.elf"; ok "/bin/fetch builds"
else bad "fetch does not build"; head -5 "$D/fe.txt"; echo "DRVFEED: $pass passed, $fail failed"; exit 1; fi
./tools/build-kernel.sh "$D/k0.img" --stufe 0 > "$D/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel"; tail -5 "$D/k.txt"; echo "DRVFEED: $pass passed, $fail failed"; exit 1; }

echo "== 2. packages and feeds =="
FWBLOB="Osum fw demo blob xyz"
FWHASH=$(printf '%s\n' "$FWBLOB" | sha256sum | cut -d" " -f1)
printf '%s\n' "$FWBLOB" > "$D/fwdemo.bin"
mkpkg() { python3 tools/drvstore/mkpkg.py build "$D/pk" --module "$1" "${@:2}" > /dev/null; }
mkpkg "$D/fwdemo.omod" --name fwdemo --match "pci 1234:11e8" --rights mmio,fw --fw "fwdemo.bin:$FWHASH"
mkpkg "$D/edudemo.omod" --name lkpitest --match "pci 1234:11e8" --rights mmio --tier compat --rank 9
mkpkg "$D/edudemo.omod" --name unrelated --match "pci 8086:ffff" --rights mmio
mkpkg "$D/fwdemo.omod" --name badsigpkg --match "pci 1234:11e8" --rights mmio,fw --fw "fwdemo.bin:$FWHASH" --bad-sig
python3 -c 'import os,sys; sys.stdout.buffer.write(os.urandom(32))' > "$D/cat.seed"
python3 -c 'import os,sys; sys.stdout.buffer.write(os.urandom(32))' > "$D/foreign.seed"
python3 - "$D/cat.seed" "$D/cat.pub" <<'PY'
import sys
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization
k = Ed25519PrivateKey.from_private_bytes(open(sys.argv[1], "rb").read())
open(sys.argv[2], "wb").write(k.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw))
PY
feed() { local name=$1; shift; python3 tools/drvfeed/mkfeed.py "$D/srv/$name" --seed "${SEED:-$D/cat.seed}" --pkg "$D/pk/fwdemo" --pkg "$D/pk/lkpitest" --pkg "$D/pk/unrelated" --fw "fwdemo.bin=$D/fwdemo.bin" "$@" > "$D/feed-$name.txt" 2>&1; }
mkdir -p "$D/srv"
feed good && ok "good feed: $(cat "$D/feed-good.txt")" || { bad "good feed"; cat "$D/feed-good.txt"; }
SEED="$D/foreign.seed" feed foreign
feed badcat --tamper-catalog
feed badfw --tamper-fw
feed badbundle
python3 - "$D/srv/badbundle/drv-fwdemo-1.drv" <<'PY'
import sys
d = bytearray(open(sys.argv[1], "rb").read()); d[-3] ^= 1; open(sys.argv[1], "wb").write(d)
PY
python3 tools/drvfeed/bundle.py list "$D/srv/good/drv-fwdemo-1.drv" > "$D/list.txt" 2>&1
has "$D/list.txt" "driver.inf.sig 64" "bundle holds the signed manifest"
python3 tools/drvfeed/bundle.py pack "$D/pk/fwdemo" "$D/fwdemo-local.drv" --fw "fwdemo.bin=$D/fwdemo.bin" && ok "local .drv with firmware built"
python3 tools/drvfeed/bundle.py pack "$D/pk/badsigpkg" "$D/badsig.drv" --fw "fwdemo.bin=$D/fwdemo.bin" && ok "local .drv with bad signature built"
cp "$D/fwdemo-local.drv" "$D/tfw.drv"
python3 - "$D/tfw.drv" "$FWBLOB" <<'PY'
import sys
d = open(sys.argv[1], "rb").read()
d = d.replace((sys.argv[2] + "\n").encode(), b"Tampered fw demo blob\n"[:len(sys.argv[2]) + 1].ljust(len(sys.argv[2]) + 1, b"x"))
open(sys.argv[1], "wb").write(d)
PY
python3 tools/ota/mkcerts.py "$D/certs" ota.test 10.0.2.2 > "$D/certs.log" 2>&1 && ok "certificates" || bad "mkcerts"
i=0
for n in good foreign badcat badfw badbundle; do
    python3 tools/ota/server.py --wurzel "$D/srv/$n" --port $((PORT+i)) --cert "$D/certs/srv.pem" --key "$D/certs/srv.key" --log "$D/srv-$n.log" > "$D/srv-$n.out" 2>&1 &
    SRVPIDS="$SRVPIDS $!"
    i=$((i+1))
done
sleep 2
CV=$(curl -s --cacert "$D/certs/ca.pem" --resolve "ota.test:$PORT:127.0.0.1" -o /dev/null -w '%{http_code}' "https://ota.test:$PORT/drivers.tsv" 2>/dev/null)
[ "$CV" = 200 ] && ok "curl reads the good catalog: 200" || bad "curl: '$CV'"
for n in good foreign badcat badfw badbundle; do :; done
idx=0
for n in good foreign badcat badfw badbundle; do
    printf 'source=https://10.0.2.2:%s\nname=ota.test\nabstand=3600\nauto=nein\nfrist=15\n' $((PORT+idx)) > "$D/ota.$n"
    idx=$((idx+1))
done

echo "== 3. guest =="
cat > "$D/a.sh" <<'EOS'
sleep 3
echo ==L0==
drvfeed list
echo ==FOREIGN==
cp /etc/ota.foreign /etc/ota.conf
drvfeed refresh
echo rc=$?
echo ==BADCAT==
cp /etc/ota.badcat /etc/ota.conf
drvfeed refresh
echo rc=$?
drvfeed list
echo ==BADFW==
cp /etc/ota.badfw /etc/ota.conf
drvfeed refresh
echo rc=$?
drvfeed install fwdemo
echo rc=$?
drvctl list
ls /lib/firmware
echo ==BADBUNDLE==
cp /etc/ota.badbundle /etc/ota.conf
drvfeed refresh
drvfeed install fwdemo
echo rc=$?
drvctl list
echo ==COMPAT==
cp /etc/ota.good /etc/ota.conf
drvfeed refresh
echo rc=$?
drvfeed list
drvfeed install lkpitest
echo rc=$?
drvctl list
echo ==GOOD==
drvfeed install fwdemo
echo rc=$?
drvfeed list
drvctl list
ls /lib/firmware
cat /proc/drivers
echo ==LOCALBAD==
drvctl remove fwdemo
drvfeed install-file /t/badsig.drv
echo rc=$?
drvfeed install-file /t/tfw.drv
echo rc=$?
drvctl list
echo ==LOCALGOOD==
drvfeed install-file /t/fwdemo-local.drv
echo rc=$?
drvctl list
echo ==END==
EOS
cat > "$D/b.sh" <<'EOS'
sleep 3
echo ==ABSENT==
drvfeed refresh
echo rc=$?
drvfeed list
drvfeed mode auto
drvfeed auto
echo rc=$?
drvctl list
echo ==END==
EOS
cat > "$D/c.sh" <<'EOS'
sleep 3
echo ==AUTO==
drvfeed mode
drvfeed mode auto
drvfeed mode
drvfeed auto
echo rc=$?
drvctl list
cat /proc/drivers
echo ==END==
EOS
image() {
    local img=$1 script=$2
    local -a A=(build "$img" 30000 --v3 --inodes=512 --karten=64 /lib/ /lib/drivers/ /lib/firmware/
        "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf"
        /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /etc/ssl/ /var/ /var/store/)
    local p
    for p in $PROGS fetch; do A+=("/bin/$p=$D/bin/$p.elf"); done
    A+=("/etc/ota.conf=$D/ota.good" "/etc/ota.good=$D/ota.good" "/etc/ota.foreign=$D/ota.foreign" "/etc/ota.badcat=$D/ota.badcat"
        "/etc/ota.badfw=$D/ota.badfw" "/etc/ota.badbundle=$D/ota.badbundle" "/etc/ssl/roots.pem=$D/certs/ca.pem"
        "/etc/store.catalog.pub=$D/cat.pub" "/t/s.sh=$script"
        "/t/badsig.drv=$D/badsig.drv" "/t/tfw.drv=$D/tfw.drv" "/t/fwdemo-local.drv=$D/fwdemo-local.drv")
    bash tools/mkfsfi/mkfs.sh "${A[@]}" > "$D/mkfs.txt" 2>&1 || { echo "mkfs failed"; tail -3 "$D/mkfs.txt"; }
}
runvm() {
    local img=$1 nm=$2; shift 2
    timeout 400 $QEMU_X86 -cpu "$OSUM_CPU" -smp 1 -kernel "$D/k0.img" -m 512 \
        -append "osum vfs nokbd bus nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0 script=sh /t/s.sh;exit" \
        -serial "file:$D/$nm.txt" -display none -no-reboot \
        -netdev user,id=n0 -device e1000,netdev=n0,mac=52:54:00:0a:0b:0c \
        -drive "file=$img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 "$@" >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$D/$nm.txt" > "$D/$nm.klar" 2>/dev/null || true
}
image "$D/ia.img" "$D/a.sh"; image "$D/ib.img" "$D/b.sh"; image "$D/ic.img" "$D/c.sh"
runvm "$D/ia.img" a -device edu
runvm "$D/ib.img" b
runvm "$D/ic.img" c -device edu
for n in a b c; do has "$D/$n.klar" "==END==" "$n: script reached its end"; done

echo "== 4. checks =="
S="$D/a.klar"
part "$S" L0 FOREIGN > "$D/p.l0"
has "$D/p.l0" "dev pci 1234:11e8 drv=none state=missing" "no catalog: the device is listed as missing"
has "$D/p.l0" "no catalog loaded" "no catalog: client says so"
part "$S" FOREIGN BADCAT > "$D/p.foreign"
has "$D/p.foreign" "catalog rejected" "foreign catalog key: refused"
has "$D/p.foreign" "rc=2" "foreign catalog key: exit code 2"
part "$S" BADCAT BADFW > "$D/p.badcat"
has "$D/p.badcat" "catalog rejected" "tampered catalog: refused"
has "$D/p.badcat" "no catalog loaded" "tampered catalog: nothing was stored"
part "$S" BADFW BADBUNDLE > "$D/p.badfw"
has "$D/p.badfw" "firmware hash mismatch" "bad firmware hash: refused"
has "$D/p.badfw" "rc=7" "bad firmware hash: exit code 7"
hasnot "$D/p.badfw" "pkg fwdemo version" "bad firmware hash: no package installed"
hasnot "$D/p.badfw" "fwdemo.bin " "bad firmware hash: no firmware file installed"
part "$S" BADBUNDLE COMPAT > "$D/p.badbundle"
has "$D/p.badbundle" "package hash mismatch" "tampered package: refused"
has "$D/p.badbundle" "rc=5" "tampered package: exit code 5"
hasnot "$D/p.badbundle" "pkg fwdemo version" "tampered package: nothing installed"
part "$S" COMPAT GOOD > "$D/p.compat"
has "$D/p.compat" "catalog ok n=3" "good catalog accepted (3 packages)"
has "$D/p.compat" "state=available pkg=fwdemo" "device without driver: catalog offers the package"
has "$D/p.compat" "compat tier refused by policy" "compat package under native policy: refused"
has "$D/p.compat" "rc=4" "compat package under native policy: exit code 4"
hasnot "$D/p.compat" "pkg lkpitest version" "compat package under native policy: not installed"
part "$S" GOOD LOCALBAD > "$D/p.good"
has "$D/p.good" "drvfeed: installed fwdemo" "good package: installed from the feed"
has "$D/p.good" "drvfeed: bound now" "good package: bound at run time (no reboot)"
has "$D/p.good" "fwdemo.bin" "good package: firmware file installed"
has "$S" "fwdemo: fw len=" "good package: module got the pinned firmware from the kernel"
has "$D/p.good" "drv=fwdemo src=store bind=bound" "good package: /proc/drivers shows the device bound"
has "$D/p.good" "state=installed pkg=fwdemo" "good package: client lists it as installed"
part "$S" LOCALBAD LOCALGOOD > "$D/p.lbad"
has "$D/p.lbad" "manifest signature check failed" "local file with bad signature: refused"
has "$D/p.lbad" "rc=9" "local file with bad signature: exit code 9"
has "$D/p.lbad" "firmware hash mismatch" "local file with wrong firmware: refused"
hasnot "$D/p.lbad" "pkg fwdemo version" "local bad files: nothing installed"
part "$S" LOCALGOOD END > "$D/p.lgood"
has "$D/p.lgood" "drvfeed: installed fwdemo" "local file with firmware: installed without a terminal feed"
has "$D/p.lgood" "pkg fwdemo version" "local file: package is in /lib/drivers"
part "$D/b.klar" ABSENT END > "$D/p.absent"
hasnot "$D/p.absent" "dev pci 1234:11e8" "no device: nothing is listed"
hasnot "$D/p.absent" "drvfeed: installed" "no device: auto installs nothing"
hasnot "$D/p.absent" "pkg fwdemo version" "no device: /lib/drivers stays empty"
part "$D/c.klar" AUTO END > "$D/p.auto"
has "$D/p.auto" "mode=auto" "auto mode switch is stored"
has "$D/p.auto" "drvfeed: installed fwdemo" "auto mode: installs the offered package"
has "$D/p.auto" "drv=fwdemo src=store bind=bound" "auto mode: device bound"
hasnot "$D/c.klar" "EXCEPTION" "no kernel exception"
echo "DRVFEED: $pass passed, $fail failed"
[ "$fail" = 0 ]
