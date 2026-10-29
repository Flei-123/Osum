#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -aqF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
OPK=${OPK:-$(python3 tools/lib/opkpfad.py)}
PROGS="sh ls cat echo mkdir shasum opk"
mkdir -p "$T/bin" "$T/h/payload/bin" "$T/h/payload/sub" "$T/src"
bash tools/sync/build.sh "$T/bin" 0 $PROGS > "$T/b.txt" 2>&1 && ok "programs build" || { bad "programs build"; head -15 "$T/b.txt"; echo "OPKPACK: $pass passed, $fail failed"; exit 1; }
./tools/build-kernel.sh "$T/k0.img" --stufe 0 > "$T/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel build"; echo "OPKPACK: $pass passed, $fail failed"; exit 1; }
printf 'alpha\n' > "$T/h/payload/a.txt"
printf 'beta beta\n' > "$T/h/payload/sub/b.txt"
printf 'run me\n' > "$T/h/payload/start"
cp "$T/bin/echo.elf" "$T/h/payload/bin/prog"
cat > "$T/h/p.rezept" <<'EOS'
# comment line
name = demo
fassung = 1.0.0
titel = Demo # trailing comment
info=Demo package
braucht=zeta
braucht=alpha
handle=text/x-demo
kind=tool
datei sub/b.txt payload/sub/b.txt
datei a.txt payload/a.txt
datei start payload/start
datei bin/prog payload/bin/prog
EOS
printf 'name=broken\nfassung=1\ndatei x.txt payload/missing.txt\n' > "$T/h/bad.rezept"
printf 'name=kernel\nfassung=1\ndatei x.txt payload/a.txt\n' > "$T/h/res.rezept"
cp "$T/h/p.rezept" "$T/h/q.rezept"; echo 'datei extra.txt payload/a.txt' >> "$T/h/q.rezept"
python3 "$OPK" schluessel "$T/keys" > /dev/null 2>&1
python3 "$OPK" bauen "$T/h/p.rezept" -o "$T/src/demo-1.0.0.opk" > "$T/host-build.txt" 2>&1 || { bad "host build"; cat "$T/host-build.txt"; }
python3 "$OPK" bauen "$T/h/q.rezept" -o "$T/other.opk" > /dev/null 2>&1
python3 "$OPK" quelle "$T/src" --schluessel "$T/keys/geheim.key" > /dev/null 2>&1
python3 tools/update/signpak.py "$T/keys/geheim.key" "$T/src/demo-1.0.0.opk" > /dev/null 2>&1
sum() { sha256sum < "$1" | cut -c1-64; }
H_PKG=$(sum "$T/src/demo-1.0.0.opk"); H_OTHER=$(sum "$T/other.opk"); H_IDX=$(sum "$T/src/INDEX")
H_ISIG=$(sum "$T/src/INDEX.sig"); H_SIG=$(sum "$T/src/demo-1.0.0.opk.sig"); H_PUB=$(sum "$T/src/oeffentlich.key")
cp "$T/src/demo-1.0.0.opk" "$T/corrupt.opk"
printf 'X' | dd of="$T/corrupt.opk" bs=1 seek=200 conv=notrunc 2> /dev/null
cat > "$T/s0.sh" <<'EOS'
echo ==A==
opk build /t/p.rezept -o /tmp/src/demo-1.0.0.opk
shasum /tmp/src/demo-1.0.0.opk
opk show /tmp/src/demo-1.0.0.opk
echo ==B==
opk source /tmp/src --key /t/key
opk sign /tmp/src/demo-1.0.0.opk --key /t/key
shasum /tmp/src/INDEX /tmp/src/INDEX.sig /tmp/src/demo-1.0.0.opk.sig /tmp/src/oeffentlich.key
echo ==C==
opk build /t/bad.rezept -o /tmp/bad.opk
opk build /t/res.rezept -o /tmp/res.opk
opk sign /tmp/src/demo-1.0.0.opk --key /t/p.rezept
opk show /t/corrupt.opk
ls /tmp
echo ==END==
EOS
python3 tools/osum/mkfs.py build "$T/d.img" 20000 /bin/ /t/ /tmp/ /tmp/src/ /proc/ /dev/ /etc/ /var/ /t/payload/ /t/payload/bin/ /t/payload/sub/ \
    $(for p in $PROGS; do echo "/bin/$p=$T/bin/$p.elf"; done) \
    "/t/p.rezept=$T/h/p.rezept" "/t/bad.rezept=$T/h/bad.rezept" "/t/res.rezept=$T/h/res.rezept" "/t/key=$T/keys/geheim.key" "/t/corrupt.opk=$T/corrupt.opk" "/t/s0.sh=$T/s0.sh" \
    "/t/payload/a.txt=$T/h/payload/a.txt" "/t/payload/start=$T/h/payload/start" "/t/payload/sub/b.txt=$T/h/payload/sub/b.txt" "/t/payload/bin/prog=$T/bin/echo.elf" > "$T/mkfs.txt" 2>&1 || tail -3 "$T/mkfs.txt"
ACC=tcg; [ -e /dev/kvm ] && ACC=kvm
timeout 400 qemu-system-x86_64 -accel "$ACC" -smp 1 -kernel "$T/k0.img" -m 512 \
    -append "osum vfs nokbd script=sh /t/s0.sh;exit" \
    -serial "file:$T/o.txt" -display none -no-reboot \
    -drive "file=$T/d.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
tr -cd '\11\12\15\40-\176' < "$T/o.txt" > "$T/o.klar"
cp "$T/o.klar" "${OPKPACK_OUT:-/dev/null}" 2>/dev/null
part() { awk -v a="==$1==" -v b="==$2==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$T/o.klar" > "$T/p.$1"; }
part A B; part B C; part C END
has "$T/p.A" "$H_PKG  /tmp/src/demo-1.0.0.opk" "A: guest package = host package (same bytes)"
grep -aqF -- "$H_OTHER" "$T/p.A" && bad "A: guest package equals a DIFFERENT host package" || ok "A: control: a different recipe gives a different hash"
has "$T/p.A" "name demo" "A: show prints the name"
has "$T/p.A" "arch x86_64" "A: arch measured out of the ELF"
has "$T/p.A" "braucht alpha" "A: show lists braucht"
has "$T/p.B" "$H_IDX  /tmp/src/INDEX" "B: INDEX equals host INDEX"
has "$T/p.B" "$H_ISIG  /tmp/src/INDEX.sig" "B: INDEX.sig equals host INDEX.sig"
has "$T/p.B" "$H_SIG  /tmp/src/demo-1.0.0.opk.sig" "B: package .sig equals host signpak"
has "$T/p.B" "$H_PUB  /tmp/src/oeffentlich.key" "B: public key equals host key"
has "$T/p.C" "opk: the recipe names a missing file" "C: missing source refused"
has "$T/p.C" "reserved PLAN type" "C: reserved package name refused"
has "$T/p.C" "exactly 32 octets" "C: a key of the wrong length refused"
has "$T/p.C" "checksum wrong" "C: corrupt package refused by show"
grep -aq 'bad.opk\|res.opk' "$T/p.C" && bad "C: a refused build left an output file" || ok "C: refused builds leave no output"
grep -aiqE 'panic|kernel fault|page fault|exception' "$T/o.klar" && bad "fault on the serial line" || ok "0 faults"
grep -aq '^kernel: done' "$T/o.klar" && ok "the kernel finished" || bad "kernel did not finish"
echo "OPKPACK: $pass passed, $fail failed"
[ "$fail" = 0 ]
