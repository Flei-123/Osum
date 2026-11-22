#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/xrkeep/run.sh -- the xremote host is a fixed part of the system and survives package operations and the trash.
#
#   /root/jarvis/bin/heavy bash tools/xrkeep/run.sh
#
#   A  the system folders (/apps ...) cannot be moved into the trash, a normal file can (trash itself still works)
#   B  the staged Store package xremote (package record under /store + /system, no SYSTEM marker) is still there after `opk install` + `opk rebuild`
#   C  counter-proof: the same files without the package record are removed by `opk rebuild` (the record is what keeps them)
#   D  counter-proof: a trash build without the guard moves /apps into the trash
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
PROGS="sh ls cat echo opk trashbin"
finish() { echo "XRKEEP: $pass passed, $fail failed"; [ "$fail" = 0 ]; exit $?; }

mkdir -p "$T/bin" "$T/user-old" "$T/bin-old" "$T/src" "$T/h/payload"
bash tools/sync/build.sh "$T/bin" 0 $PROGS > "$T/b.txt" 2>&1 && ok "programs build" || { bad "programs build"; head -15 "$T/b.txt"; finish; }
cp -r kernel/user/. "$T/user-old/"
sed -i 's/if trashguard.is_protected(abs) {/if false {/' "$T/user-old/trash.fi"
USRC="$T/user-old" bash tools/sync/build.sh "$T/bin-old" 0 trashbin > "$T/bo.txt" 2>&1 && ok "mutant trashbin (no guard) builds" || { bad "mutant build"; head -10 "$T/bo.txt"; finish; }
./tools/build-kernel.sh "$T/k0.img" --stufe 0 > "$T/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel build"; finish; }
bash tools/xremote/stage.sh "$T/xr" > "$T/stage.txt" 2>&1 && ok "xremote bundle stages" || { bad "xremote stage"; cat "$T/stage.txt"; finish; }
XB="$T/xr/apps/xremote.osp"

echo "extra" > "$T/h/payload/extra.txt"
cat > "$T/h/extra.rezept" <<'EOS'
name = extra
version = 1.0.0
titel = Extra
info = Package installed next to the shipped bundle
kind = tool
datei = extra.txt payload/extra.txt
EOS
python3 "$OPK" schluessel "$T/keys" > /dev/null 2>&1
python3 "$OPK" bauen "$T/h/extra.rezept" -o "$T/src/extra-1.0.0.opk" > "$T/host-build.txt" 2>&1 || { bad "host build"; cat "$T/host-build.txt"; finish; }
python3 "$OPK" quelle "$T/src" --schluessel "$T/keys/geheim.key" > /dev/null 2>&1
python3 tools/update/signpak.py "$T/keys/geheim.key" "$T/src/extra-1.0.0.opk" > /dev/null 2>&1

cat > "$T/s0.sh" <<'EOS'
echo ==A==
trashbin put /apps
trashbin put /system/
trashbin put /
ls /apps
echo note > /t/note.txt
trashbin put /t/note.txt
trashbin list
echo ==B==
opk install /t/extra.opk
opk rebuild
ls /apps
ls /apps/xremote.osp/bin
ls /apps/xremote.osp/lib
echo ==D==
trashmut put /apps
ls /apps
echo ==END==
sleep 3
EOS
cat > "$T/s1.sh" <<'EOS'
echo ==C==
opk install /t/extra.opk
opk rebuild
ls /apps
echo ==END==
sleep 3
EOS

dirs="/bin/ /t/ /system/ /apps/ /store/ /tmp/ /proc/ /dev/ /etc/ /var/"
bundle_files() {
    local with_record=$1
    if [ "$with_record" = 1 ]; then
        python3 tools/xremote/mkfsargs.py "$T/xr"
        return
    fi
    echo "/apps/xremote.osp/" "/apps/xremote.osp/bin/" "/apps/xremote.osp/lib/"
    echo "/apps/xremote.osp/INFO=$XB/INFO" "/apps/xremote.osp/symbol=$XB/symbol" "/apps/xremote.osp/bin/freeviewer-host=$XB/bin/freeviewer-host@755" \
         "/apps/xremote.osp/lib/ld-musl-x86_64.so.1=$XB/lib/ld-musl-x86_64.so.1@755" "/apps/xremote.osp/lib/libgcc_s.so.1=$XB/lib/libgcc_s.so.1"
}
run_guest() {
    local name=$1 with_record=$2 script=$3
    bash tools/mkfsfi/mkfs.sh build "$T/$name.img" 200000 $dirs \
        $(for p in $PROGS; do echo "/bin/$p=$T/bin/$p.elf"; done) "/bin/trashmut=$T/bin-old/trashbin.elf" \
        "/system/schluessel.pub=$T/src/oeffentlich.key" \
        "/t/extra.opk=$T/src/extra-1.0.0.opk" "/t/extra.opk.sig=$T/src/extra-1.0.0.opk.sig" "/t/s.sh=$T/$script" \
        $(bundle_files "$with_record") > "$T/$name.mkfs" 2>&1 || tail -3 "$T/$name.mkfs"
    local acc=tcg; [ -e /dev/kvm ] && acc=kvm
    timeout 600 qemu-system-x86_64 -accel "$acc" -smp 1 -kernel "$T/k0.img" -m 512 \
        -append "osum vfs nokbd script=sh /t/s.sh;exit" \
        -serial "file:$T/$name.txt" -display none -no-reboot \
        -drive "file=$T/$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$T/$name.txt" > "$T/$name.klar"
    cp "$T/$name.klar" "${XRKEEP_OUT:-/dev/null}.$name" 2>/dev/null
    rm -f "$T/$name.img"
}
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$T/$1.klar" > "$T/$1.$2"; }

run_guest main 1 s0.sh
part main A B; part main B D; part main D END
has "$T/main.A" "trashbin: failed: /apps" "A: /apps is refused by the trash"
has "$T/main.A" "trashbin: failed: /system/" "A: /system/ (trailing slash) is refused"
[ -z "${XRKEEP_OUT:-}" ] || cp "$T"/main.* "$XRKEEP_OUT/"
has "$T/main.A" "trashbin: failed: /" "A: the root is refused"
has "$T/main.A" "xremote.osp" "A: /apps still lists xremote.osp"
has "$T/main.A" "note.txt" "A: a normal file still goes into the trash"
has "$T/main.B" "opk: installed extra" "B: a package installs next to the shipped bundle"
has "$T/main.B" "extra.osp" "B: the new package is linked after the rebuild"
has "$T/main.B" "xremote.osp" "B: xremote.osp survives opk install + rebuild through its package record"
has "$T/main.B" "freeviewer-host" "B: the host binary is still in place"
has "$T/main.B" "libgcc_s.so.1" "B: the host libraries are still in place"
has "$T/main.D" "ls: cannot list /apps" "D: counter-proof: without the guard /apps is gone"
grep -aiqE 'panic|kernel fault|page fault|exception' "$T/main.klar" && bad "fault on the serial line" || ok "0 faults"
grep -aq '^kernel: done' "$T/main.klar" && ok "the kernel finished" || bad "kernel did not finish"

run_guest norecord 0 s1.sh
part norecord C END
has "$T/norecord.C" "extra.osp" "C: counter-proof run: rebuild linked the package"
hasnot "$T/norecord.C" "xremote.osp" "C: counter-proof: without the package record the rebuild removes the bundle"
finish
