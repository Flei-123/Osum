#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
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
PROGS="sh ls cat echo opk explorer"
finish() { echo "EXPLORERPKG: $pass passed, $fail failed"; [ "$fail" = 0 ]; exit $?; }

mkdir -p "$T/bin" "$T/src" "$T/h/bau"
python3 tools/sdk/osdk.py check pakete/explorer/INFO --strict --system > "$T/lint.txt" 2>&1 && ok "package INFO passes the system lint" || { bad "INFO lint"; cat "$T/lint.txt"; }
python3 tools/sdk/osdk.py check pakete/explorer/INFO --strict > "$T/lint2.txt" 2>&1 && bad "lint without --system must refuse the name" || ok "lint without --system refuses the name (collision guard)"
bash tools/sync/build.sh "$T/bin" 0 $PROGS > "$T/b.txt" 2>&1 && ok "programs build" || { bad "programs build"; head -15 "$T/b.txt"; finish; }
./tools/build-kernel.sh "$T/k0.img" --stufe 0 > "$T/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel build"; finish; }

cp "$T/bin/explorer.elf" "$T/h/bau/explorer.elf"
cp pakete/explorer/INFO "$T/h/INFO"
python3 tools/k15/mksymbol.py pakete/explorer "$T/h/bau/symbol" > /dev/null
for v in 2.0.0 2.0.1; do
    sed "s/^version=.*/version=$v/" pakete/explorer/rezept > "$T/h/rezept"
    sed -i "s#bau/#$T/h/bau/#; s#^datei=INFO INFO#datei=INFO $T/h/INFO#" "$T/h/rezept"
    python3 "$OPK" bauen "$T/h/rezept" -o "$T/src/explorer-$v.opk" > "$T/pk-$v.txt" 2>&1 || { bad "package $v builds"; cat "$T/pk-$v.txt"; finish; }
done
ok "explorer-2.0.0.opk and 2.0.1 build"
python3 "$OPK" schluessel "$T/keys" > /dev/null 2>&1
python3 "$OPK" quelle "$T/src" --schluessel "$T/keys/geheim.key" > /dev/null 2>&1
for v in 2.0.0 2.0.1; do python3 tools/update/signpak.py "$T/keys/geheim.key" "$T/src/explorer-$v.opk" > /dev/null 2>&1; done

cat > "$T/s0.sh" <<'EOS'
echo ==A==
opk install /t/explorer-2.0.0.opk
opk trial ok
opk rebuild
ls /apps
cat /apps/explorer.osp/INFO
echo ==B==
opk install /t/explorer-2.0.1.opk
opk trial ok
opk rebuild
cat /apps/explorer.osp/INFO
echo ==C==
opk remove explorer
opk rebuild
ls /apps
echo ==END==
sleep 3
EOS
cat > "$T/s1.sh" <<'EOS'
echo ==D==
opk install /t/explorer-2.0.1.opk
opk rebuild
ls /apps
cat /apps/explorer.osp/INFO
opk remove explorer
opk rebuild
ls /apps
cat /apps/explorer.osp/INFO
echo ==END==
sleep 3
EOS
cat > "$T/s2.sh" <<'EOS'
echo ==E==
opk install /t/explorer-2.0.1.opk
opk remove explorer
opk rebuild
ls /apps
echo ==END==
sleep 3
EOS

bundle_files() {
    local with_system=$1
    echo "/apps/explorer.osp/INFO=$T/base/INFO" "/apps/explorer.osp/start@/bin/explorer"
    [ "$with_system" = 1 ] && echo "/apps/explorer.osp/SYSTEM=$T/base/SYSTEM"
}
mkdir -p "$T/base"
sed 's/^version=.*/version=2.0.0/' assets/apps/explorer.osp/INFO > "$T/base/INFO"
printf 'shipped with the OrientOS image\n' > "$T/base/SYSTEM"
run_guest() {
    local name=$1 with_bundle=$2 with_system=$3 script=$4
    local extra=""
    [ "$with_bundle" = 1 ] && extra="/apps/explorer.osp/ $(bundle_files "$with_system")"
    bash tools/mkfsfi/mkfs.sh build "$T/$name.img" 200000 /bin/ /t/ /system/ /apps/ /store/ /tmp/ /proc/ /dev/ /etc/ /var/ \
        $(for p in $PROGS; do echo "/bin/$p=$T/bin/$p.elf"; done) \
        "/system/schluessel.pub=$T/src/oeffentlich.key" \
        "/t/explorer-2.0.0.opk=$T/src/explorer-2.0.0.opk" "/t/explorer-2.0.0.opk.sig=$T/src/explorer-2.0.0.opk.sig" \
        "/t/explorer-2.0.1.opk=$T/src/explorer-2.0.1.opk" "/t/explorer-2.0.1.opk.sig=$T/src/explorer-2.0.1.opk.sig" \
        "/t/s.sh=$T/$script" $extra > "$T/$name.mkfs" 2>&1 || tail -3 "$T/$name.mkfs"
    local acc=tcg; [ -e /dev/kvm ] && acc=kvm
    timeout 600 qemu-system-x86_64 -accel "$acc" -smp 1 -kernel "$T/k0.img" -m 512 \
        -append "osum vfs nokbd script=sh /t/s.sh;exit" \
        -serial "file:$T/$name.txt" -display none -no-reboot \
        -drive "file=$T/$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$T/$name.txt" > "$T/$name.klar"
    cp "$T/$name.klar" "${EXPLORERPKG_OUT:-/dev/null}.$name" 2>/dev/null
    rm -f "$T/$name.img"
}
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$T/$1.klar" > "$T/$1.$2"; }

run_guest plain 0 0 s0.sh
part plain A B; part plain B C; part plain C END
has "$T/plain.A" "opk: installed explorer" "A: the package installs on an image without the bundle"
has "$T/plain.A" "explorer.osp" "A: /apps/explorer.osp is linked"
has "$T/plain.A" "version=2.0.0" "A: version 2.0.0"
has "$T/plain.B" "version=2.0.1" "B: update to 2.0.1 without a reboot"
hasnot "$T/plain.B" "version=2.0.0" "B: the old version is gone"
hasnot "$T/plain.C" "explorer.osp" "C: opk remove takes the package away again"
grep -aiqE 'panic|kernel fault|page fault|exception' "$T/plain.klar" && bad "fault on the serial line (plain)" || ok "0 faults (plain)"

run_guest sys 1 1 s1.sh
part sys D END
has "$T/sys.D" "explorer.osp" "D: with the system bundle /apps/explorer.osp is there"
has "$T/sys.D" "version=2.0.0" "D: the shipped bundle wins over the package (system bundle is never replaced)"
hasnot "$T/sys.D" "version=2.0.1" "D: the package does not overlay the shipped bundle"
[ "$(grep -ac 'explorer.osp' "$T/sys.D")" -ge 2 ] && ok "D: still present after opk remove + rebuild (safety net)" || bad "D: bundle missing after remove"
grep -aiqE 'panic|kernel fault|page fault|exception' "$T/sys.klar" && bad "fault on the serial line (sys)" || ok "0 faults (sys)"

run_guest nosys 1 0 s2.sh
part nosys E END
hasnot "$T/nosys.E" "explorer.osp" "E: counter-proof: without SYSTEM the rebuild removes the bundle"
finish
