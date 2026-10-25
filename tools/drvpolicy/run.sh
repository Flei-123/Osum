#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there" || ok "$3"; }
D=$(mktemp -d); [ -z "${DRVPOLICY_KEEP:-}" ] && trap 'rm -rf "$D"' EXIT
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
fin() { echo "DRVPOLICY: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }

python3 tools/module/mkpolicy.py lib/modpolicy/policydata.fi --check > "$D/chk.txt" 2>&1 && ok "checked-in policydata matches keys.default + banfloor.txt" || { bad "policydata stale"; cat "$D/chk.txt"; }
DEVPUB=$(python3 -c "import sys;sys.path.insert(0,'tools/module');import mkomod;print(mkomod.pubkey(open('tools/module/pruef.seed','rb').read()).hex())")
grep -q "^$DEVPUB" tools/module/keys.default && ok "keys.default has the development key" || bad "keys.default lacks the development key"
grep -q "^$DEVPUB" tools/module/keys.release && bad "keys.release contains the development key" || ok "keys.release has no development key"
[ "$(grep -vc '^#' tools/module/keys.release)" -eq 1 ] && ok "keys.release has exactly one key" || bad "keys.release key count"
if [ -r /root/.osum-secrets/osum-delivery.seed ]; then
    DELPUB=$(python3 -c "import sys;sys.path.insert(0,'tools/module');import mkomod;print(mkomod.pubkey(open('/root/.osum-secrets/osum-delivery.seed','rb').read()).hex())")
    grep -q "^$DELPUB" tools/module/keys.release && grep -q "^$DELPUB" tools/module/keys.default && ok "delivery public key matches the private seed" || bad "delivery public key mismatch"
fi
echo "zz" > "$D/badkeys"; python3 tools/module/mkpolicy.py "$D/o.fi" --keys "$D/badkeys" > /dev/null 2>&1 && bad "bad key line accepted" || ok "mkpolicy rejects a bad key line"
printf '%s\n' "$DEVPUB" > "$D/devkey"; echo "abcd" > "$D/badfloor"
python3 tools/module/mkpolicy.py "$D/o.fi" --keys "$D/devkey" --floor "$D/badfloor" > /dev/null 2>&1 && bad "bad floor line accepted" || ok "mkpolicy rejects a bad floor line"
: > "$D/nokeys"; python3 tools/module/mkpolicy.py "$D/o.fi" --keys "$D/nokeys" > /dev/null 2>&1 && bad "empty key list accepted" || ok "mkpolicy rejects an empty key list"

python3 - "$D" <<'EOS'
import os, sys
sys.path.insert(0, "tools/module")
import mkomod
d = sys.argv[1]
seed = os.urandom(32)
open(d + "/test.seed", "wb").write(seed)
open(d + "/keys.test", "w").write(mkomod.pubkey(seed).hex() + "\n")
open(d + "/keys.both", "w").write(mkomod.pubkey(open("tools/module/pruef.seed", "rb").read()).hex() + "\n" + mkomod.pubkey(seed).hex() + "\n")
EOS
bash tools/module/build.sh "$D/dev.omod" --quelle module/store/edudemo.fi > "$D/m1.txt" 2>&1 && ok "edudemo signed with the development key" || { bad "dev module"; tail -3 "$D/m1.txt"; fin; }
bash tools/module/build.sh "$D/tst.omod" --quelle module/store/edudemo.fi --seed "$D/test.seed" > "$D/m2.txt" 2>&1 && ok "edudemo signed with the test delivery key" || { bad "test module"; tail -3 "$D/m2.txt"; fin; }
python3 -c "import sys;d=open('$D/dev.omod','rb').read();print(d[-64:].hex())" > "$D/floor.txt"
python3 -c "import sys;d=open('$D/tst.omod','rb').read();print(d[-64:].hex())" > "$D/floor-tst.txt"
[ "$(cat $D/floor.txt)" != "$(cat $D/floor-tst.txt)" ] && ok "the two signed files have different signatures" || bad "signatures equal"

mkdir -p "$D/bin" "$D/pk-dev" "$D/pk-tst"
PROGS="sh cat echo drvctl"
bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/b.txt" 2>&1 && ok "programs build" || { bad "programs"; head -10 "$D/b.txt"; fin; }
python3 tools/drvstore/mkpkg.py build "$D/pk-dev" --module "$D/dev.omod" --name edudemo --match "pci 1234:11e8" --rights mmio > /dev/null
python3 tools/drvstore/mkpkg.py build "$D/pk-tst" --module "$D/tst.omod" --name edudemo --match "pci 1234:11e8" --rights mmio --seed "$D/test.seed" > /dev/null
kb() { local n=$1; shift; ./tools/build-kernel.sh "$D/k-$n.img" --stufe 0 "$@" > "$D/kb-$n.txt" 2>&1; }
kb def &
P1=$!
kb test --module-keys "$D/keys.test" &
P2=$!
kb both --module-keys "$D/keys.both" &
P3=$!
kb floor --ban-floor "$D/floor.txt" --module-keys "$D/keys.both" &
P4=$!
for pair in "def:$P1" "test:$P2" "both:$P3" "floor:$P4"; do
    n=${pair%%:*}; pid=${pair##*:}
    wait "$pid" && ok "kernel $n builds" || { bad "kernel $n"; tail -4 "$D/kb-$n.txt"; }
done
[ "$fail" -eq 0 ] || fin
cat > "$D/s.sh" <<'EOS'
echo ==DRIVERS==
cat /proc/drivers
echo ==END==
EOS
mkimg() {
    local name=$1 pk=$2
    local files="/lib/drivers/edudemo/"
    for f in $(ls "$D/$pk/edudemo"); do files="$files /lib/drivers/edudemo/$f=$D/$pk/edudemo/$f"; done
    python3 tools/osum/mkfs.py build "$D/d-$name.img" 20000 /lib/ /lib/drivers/ \
        "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
        /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ \
        $(for p in $PROGS; do echo "/bin/$p=$D/bin/$p.elf"; done) \
        "/t/s.sh=$D/s.sh" $files > "$D/mkfs-$name.txt" 2>&1 || tail -3 "$D/mkfs-$name.txt"
}
mkimg dev pk-dev
mkimg tst pk-tst
runvm() {
    local name=$1 kern=$2 img=$3 words=$4; shift 4
    cp "$D/d-$img.img" "$D/r-$name.img"
    timeout 150 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 -kernel "$D/k-$kern.img" -m 512 \
        -append "osum vfs $words script=sh /t/s.sh;exit" \
        -serial "file:$D/o-$name.txt" -display none -no-reboot \
        -drive "file=$D/r-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 "$@" >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$D/o-$name.txt" > "$D/$name.klar"
}
runvm def-dev def dev "" -device edu &
runvm def-tst def tst "" -device edu &
runvm test-tst test tst "" -device edu &
runvm test-dev test dev "" -device edu &
wait
runvm both-dev both dev "" -device edu &
runvm both-tst both tst "" -device edu &
runvm floor-dev floor dev "" -device edu &
runvm floor-tst floor tst "" -device edu &
wait
runvm un1 def dev drvunload -device edu &
runvm un2 def dev drvunload -device edu -device edu &
runvm un0 def dev "" -device edu &
wait

has "$D/def-dev.klar" "drvstore: pkg edudemo ok" "default kernel: development-signed package accepted"
has "$D/def-dev.klar" "drv=edudemo src=store bind=bound" "default kernel: development-signed driver bound"
has "$D/def-tst.klar" "drvstore: pkg edudemo rejected 20" "default kernel: package signed with an untrusted key rejected"
hasnot "$D/def-tst.klar" "edudemo: ven" "counter-proof: untrusted-key module never ran"
has "$D/test-tst.klar" "drvstore: pkg edudemo ok" "delivery-only kernel: delivery-signed package accepted"
has "$D/test-tst.klar" "drv=edudemo src=store bind=bound" "delivery-only kernel: delivery-signed driver bound"
has "$D/test-tst.klar" "edudemo: ven=4660" "delivery-only kernel: module ran"
has "$D/test-dev.klar" "drvstore: pkg edudemo rejected 20" "delivery-only kernel: development-signed package rejected"
hasnot "$D/test-dev.klar" "edudemo: ven" "counter-proof: development-signed module never ran on the delivery-only kernel"
has "$D/both-dev.klar" "drv=edudemo src=store bind=bound" "two-key kernel: first key works"
has "$D/both-tst.klar" "drv=edudemo src=store bind=bound" "two-key kernel: second key works"
has "$D/floor-dev.klar" "drvstore: pkg edudemo ok" "floor kernel: package itself is valid"
has "$D/floor-dev.klar" "fail: gesperrt" "floor kernel: revoked module refused without any list file on disk"
hasnot "$D/floor-dev.klar" "edudemo: ven" "floor kernel: revoked module never ran"
has "$D/floor-dev.klar" "bound=0 failed=1" "floor kernel: bind counted as failed"
has "$D/floor-tst.klar" "drv=edudemo src=store bind=bound" "floor kernel: a different signed file is not affected"
has "$D/un1.klar" "drvstore: unload edudemo refused refs=1" "refcount: unload refused while a device holds the module"
has "$D/un1.klar" "drvstore: unload edudemo ok" "refcount: unload works after the reference is released"
has "$D/un2.klar" "drvstore: unload edudemo refused refs=2" "refcount: two devices hold two references"
has "$D/un2.klar" "drvstore: unload edudemo ok" "refcount: unload works after both are released"
hasnot "$D/un0.klar" "drvstore: unload" "counter-proof: no unload attempt without the word"
for n in def-dev def-tst test-tst test-dev both-dev both-tst floor-dev floor-tst un1 un2; do
    hasnot "$D/$n.klar" "EXCEPTION" "$n: no kernel exception"
done
fin
