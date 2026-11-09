#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { [ -s "$1" ] && grep -aqF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { [ -s "$1" ] && ! grep -aqF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' present or no output"; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
OPK=${OPK:-$(python3 tools/lib/opkpfad.py)}
PAYLOAD_MIB=${OPKBIG_MIB:-10}
PROGS="sh ls cat echo shasum opk"
IMAGE_PROGS="sh ls cat echo shasum"
finish() { echo "OPKBIG: $pass passed, $fail failed"; [ "$fail" = 0 ]; exit $?; }

mkdir -p "$T/bin" "$T/bin-old" "$T/h/payload" "$T/src" "$T/user-old"
bash tools/sync/build.sh "$T/bin" 0 $PROGS > "$T/b.txt" 2>&1 && ok "programs build" || { bad "programs build"; head -15 "$T/b.txt"; finish; }
cp -r kernel/user/. "$T/user-old/"
sed -i 's/^const PKT_MAX: u64 = [0-9]*/const PKT_MAX: u64 = 8388608/; s/^static mut PKT: \[u8; [0-9]*\] = \[0 as u8; [0-9]*\]/static mut PKT: [u8; 8388608] = [0 as u8; 8388608]/' "$T/user-old/opk.fi"
USRC="$T/user-old" bash tools/sync/build.sh "$T/bin-old" 0 opk > "$T/bo.txt" 2>&1 && ok "mutant opk (8 MiB buffer) builds" || { bad "mutant build"; head -10 "$T/bo.txt"; finish; }
./tools/build-kernel.sh "$T/k0.img" --stufe 0 > "$T/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel build"; finish; }

head -c $((PAYLOAD_MIB * 1048576)) /dev/urandom > "$T/h/payload/blob.bin"
H_BLOB=$(sha256sum < "$T/h/payload/blob.bin" | cut -c1-64)
cat > "$T/h/big.rezept" <<'EOS'
name = bigpkg
version = 1.0.0
titel = Big
info = Package above the old 8 MiB buffer
kind = tool
datei = blob.bin payload/blob.bin
EOS
python3 "$OPK" schluessel "$T/keys" > /dev/null 2>&1
python3 "$OPK" bauen "$T/h/big.rezept" -o "$T/src/bigpkg-1.0.0.opk" > "$T/host-build.txt" 2>&1 || { bad "host build"; cat "$T/host-build.txt"; finish; }
python3 "$OPK" quelle "$T/src" --schluessel "$T/keys/geheim.key" > /dev/null 2>&1
python3 tools/update/signpak.py "$T/keys/geheim.key" "$T/src/bigpkg-1.0.0.opk" > /dev/null 2>&1
BIG_SIZE=$(stat -c%s "$T/src/bigpkg-1.0.0.opk")
[ "$BIG_SIZE" -gt 8388608 ] && ok "host package is $BIG_SIZE octets (> 8 MiB)" || bad "host package only $BIG_SIZE octets"
cp "$T/src/bigpkg-1.0.0.opk" "$T/bad.opk"
cp "$T/src/bigpkg-1.0.0.opk.sig" "$T/bad.opk.sig"
printf 'X' | dd of="$T/bad.opk" bs=1 seek=$((BIG_SIZE / 2)) conv=notrunc 2> /dev/null

cat > "$T/s0.sh" <<'EOS'
echo ==A==
opk install /t/bad.opk
opk list
echo ==B==
opk install /t/big.opk
opk list
ls /apps
echo ==END==
sleep 3
EOS

run_guest() {
    local name=$1 opkelf=$2
    bash tools/mkfsfi/mkfs.sh build "$T/$name.img" 200000 /bin/ /t/ /system/ /apps/ /store/ /tmp/ /proc/ /dev/ /etc/ /var/ \
        $(for p in $IMAGE_PROGS; do echo "/bin/$p=$T/bin/$p.elf"; done) "/bin/opk=$opkelf" \
        "/system/schluessel.pub=$T/src/oeffentlich.key" \
        "/t/big.opk=$T/src/bigpkg-1.0.0.opk" "/t/big.opk.sig=$T/src/bigpkg-1.0.0.opk.sig" \
        "/t/bad.opk=$T/bad.opk" "/t/bad.opk.sig=$T/bad.opk.sig" "/t/s0.sh=$T/s0.sh" > "$T/$name.mkfs" 2>&1 || tail -3 "$T/$name.mkfs"
    local acc=tcg; [ -e /dev/kvm ] && acc=kvm
    timeout 600 qemu-system-x86_64 -accel "$acc" -smp 1 -kernel "$T/k0.img" -m 512 \
        -append "osum vfs nokbd script=sh /t/s0.sh;exit" \
        -serial "file:$T/$name.txt" -display none -no-reboot \
        -drive "file=$T/$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$T/$name.txt" > "$T/$name.klar"
    cp "$T/$name.klar" "${OPKBIG_OUT:-/dev/null}.$name" 2>/dev/null
    rm -f "$T/$name.img"
}
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$T/$1.klar" > "$T/$1.$2"; }

run_guest new "$T/bin/opk.elf"
part new A B; part new B END
has "$T/new.A" "SIGNATURE WRONG" "corrupt big package refused by the signature check"
hasnot "$T/new.A" "opk: installed" "corrupt big package not installed"
has "$T/new.B" "opk: installed bigpkg" "big package installed"
has "$T/new.B" "bigpkg" "big package listed"
hasnot "$T/new.B" "does not fit the buffer" "no size refusal for the big package"
grep -aiqE 'panic|kernel fault|page fault|exception' "$T/new.klar" && bad "fault on the serial line" || ok "0 faults"
grep -aq '^kernel: done' "$T/new.klar" && ok "the kernel finished" || bad "kernel did not finish"

run_guest old "$T/bin-old/opk.elf"
part old B END
has "$T/old.B" "does not fit the buffer" "counter-proof: the 8 MiB opk refuses the big package"
hasnot "$T/old.B" "opk: installed bigpkg" "counter-proof: the 8 MiB opk installs nothing"
finish
