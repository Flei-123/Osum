#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/pidkill.sh
export FIRNLIB="$(pwd)/lib"
. tools/lib/firnenv.sh
firnenv_need_firnc1

ULD=kernel/user/user.ld
BLOCKS=8192
PROGS="init svc sh ls cat echo sleep cp mkdir rm true chmod"
OPK=${OPK:-$(python3 tools/lib/opkpfad.py)}
OLD_REF=${PKGSVC_OLD_REF:-origin/main}

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
is()  { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', expected '$3'"; fi; }
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' present" || ok "$3"; }
col() { grep -aE "^$2 (running|stopped|done|waiting|failed) [0-9]+ [0-9]+ [0-9]+ [0-9]+ [a-z,]+" "$1" | tail -1 | awk -v c="$3" '{print $c}'; }

command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "PKGSVC: skipped, qemu missing"; exit 0; }
[ -f "$OPK" ] || { echo "PKGSVC: skipped, opk.py missing"; exit 0; }

if [ -n "${PKGSVC_KEEP:-}" ]; then T=$PKGSVC_KEEP; mkdir -p "$T"; else T=$(mktemp -d); fi
OLD_PROBE=kernel/user/init_old_probe.fi
trap 'rm -rf "$OLD_PROBE"; [ -n "${PKGSVC_KEEP:-}" ] || rm -rf "$T"' EXIT

echo "== 1. package build and layout =="
"$FIRNC" -c --profile=app -o "$T/jd.o" kernel/app/jarvisd.fi > "$T/jd.log" 2>&1 \
    && ld -T "$ULD" -o "$T/jarvisd" "$T/jd.o" 2>/dev/null \
    && strip --strip-all "$T/jarvisd"
[ -s "$T/jarvisd" ] && ok "jarvisd builds as a standalone ELF ($(stat -c%s "$T/jarvisd") octets)" || { bad "jarvisd build failed"; head -5 "$T/jd.log"; }
python3 tools/sdk/osdk.py check pakete/jarvisd/INFO --strict > "$T/osdk.txt" 2>&1
[ $? = 0 ] && ok "INFO passes osdk --strict" || bad "INFO lint failed"
mkdir -p "$T/pkg/bau"
cp pakete/jarvisd/INFO pakete/jarvisd/rezept pakete/jarvisd/INITTAB "$T/pkg/"
cp "$T/jarvisd" "$T/pkg/bau/jarvisd"
python3 tools/k15/mksymbol.py pakete/jarvisd "$T/pkg/bau/symbol" > /dev/null
(cd "$T/pkg" && python3 "$OPK" bauen rezept -o "$T/out.opk") > "$T/pack.txt" 2>&1
[ -s "$T/out.opk" ] && ok "opk builds the package from the recipe" || { bad "opk build failed"; head -5 "$T/pack.txt"; }
python3 "$OPK" zeigen "$T/out.opk" > "$T/show.txt" 2>&1
for f in INFO INITTAB bin/jarvisd symbol; do
    grep -qE "^  f $f " "$T/show.txt" && ok "package holds $f" || bad "package misses $f"
done
mkdir -p "$T/root"
python3 "$OPK" installieren --wurzel "$T/root" "$T/out.opk" > "$T/inst.txt" 2>&1
[ -f "$T/root/apps/jarvisd.osp/INITTAB" ] && ok "install puts INITTAB at /apps/jarvisd.osp" || bad "INITTAB not installed"
[ -f "$T/root/apps/jarvisd.osp/bin/jarvisd" ] && ok "install puts the helper at /apps/jarvisd.osp/bin" || bad "helper not installed"
python3 "$OPK" entfernen --wurzel "$T/root" jarvisd > "$T/rm.txt" 2>&1
[ ! -e "$T/root/apps/jarvisd.osp" ] && ok "remove leaves no bundle behind" || bad "bundle still there after remove"
line=$(cat pakete/jarvisd/INITTAB)
case "$line" in
    jarvisd:grafik:respawn:/apps/jarvisd.osp/bin/jarvisd:*unless=/bin/jarvisd*) ok "INITTAB line starts the packaged helper unless the image has its own";;
    *) bad "INITTAB line unexpected: $line";;
esac

echo "== 2. kernel and programs =="
bash tools/build-kernel.sh "$T/k0.img" --stufe 0 > "$T/b0.txt" 2>&1 \
    && ok "kernel builds" || { bad "kernel build failed"; tail -5 "$T/b0.txt"; }
as --64 -o "$T/crt.o" kernel/user/crt.s
build_prog() { # source out
    "$FIRNC" "$1" -o "$T/p.o" > "$T/e.txt" 2>&1 \
        && ld -T "$ULD" --defsym=USER_ENTRY="_F0.u_start" -o "$2" "$T/crt.o" "$T/p.o" 2>/dev/null \
        && strip --strip-all "$2"
}
built=0
for p in $PROGS; do
    if build_prog "kernel/user/$p.fi" "$T/$p.elf"; then built=$((built+1)); else bad "build $p failed"; head -4 "$T/e.txt"; fi
done
is "programs built" "$built" "$(echo $PROGS | wc -w)"
git show "$OLD_REF:kernel/user/init.fi" > "$OLD_PROBE" 2>/dev/null
build_prog "$OLD_PROBE" "$T/init_old.elf" && ok "old init ($OLD_REF) builds for the counter-probe" || bad "old init build failed"
rm -f "$OLD_PROBE"

echo "== 3. images =="
printf 'sh:*:ctrl:/bin/sh\n' > "$T/inittab"
printf 'grafik\n' > "$T/ziel"
printf 'demo:*:respawn:/apps/demo.osp/bin/sleep 60\n' > "$T/demo.tab"
printf 'evil1:*:respawn:/bin/sleep 60\nevil2:*:ctrl:/apps/evil.osp/bin/sleep 60\n# comment\n' > "$T/evil.tab"
printf 'yieldA:*:respawn:/apps/yield.osp/bin/sleep 60:unless=/bin/true\nyieldB:*:respawn:/apps/yield.osp/bin/sleep 60:unless=/bin/nonexistent\n' > "$T/yield.tab"
printf 'late:*:respawn:/apps/late.osp/bin/sleep 60\n' > "$T/late.tab"
cat > "$T/run.sh" <<'SCRIPT'
echo ==BEGIN==
sleep 3
svc status
echo --JARVISD--
/bin/chmod 755 /apps/jarvisd.osp/bin/jarvisd
/apps/jarvisd.osp/bin/jarvisd -n
echo --LATE--
mkdir /apps/late.osp
mkdir /apps/late.osp/bin
cp /bin/sleep /apps/late.osp/bin/sleep
cp /t/late.tab /apps/late.osp/INITTAB
svc rescan
sleep 2
svc status
echo --GONE--
rm /apps/late.osp/INITTAB
svc rescan
sleep 2
svc status
echo ==END==
SCRIPT
cat > "$T/short.sh" <<'SCRIPT'
echo ==BEGIN==
sleep 3
svc status
echo ==END==
SCRIPT

image() { # out init-elf [extra spec...]
    local out=$1 init=$2; shift 2
    local spec="" p src
    for p in $PROGS; do
        src="$T/$p.elf"
        [ "$p" = init ] && src=$init
        spec="$spec /bin/$p=$src@755:0:0"
    done
    bash tools/mkfsfi/mkfs.sh build "$out" $BLOCKS /bin/ /etc/ /etc/jarvis/ /run/ /var/ /var/log/ /t/ /apps/ \
        /apps/demo.osp/ /apps/demo.osp/bin/ /apps/evil.osp/ /apps/yield.osp/ /apps/yield.osp/bin/ \
        /apps/jarvisd.osp/ /apps/jarvisd.osp/bin/ \
        $spec \
        "/etc/inittab=$T/inittab@644:0:0" "/etc/ziel=$T/ziel@644:0:0" \
        "/t/run.sh=$T/run.sh@644:0:0" "/t/short.sh=$T/short.sh@644:0:0" "/t/late.tab=$T/late.tab@644:0:0" \
        "/apps/demo.osp/INITTAB=$T/demo.tab@644:0:0" "/apps/demo.osp/bin/sleep=$T/sleep.elf@644:0:0" \
        "/apps/evil.osp/INITTAB=$T/evil.tab@644:0:0" \
        "/apps/yield.osp/INITTAB=$T/yield.tab@644:0:0" "/apps/yield.osp/bin/sleep=$T/sleep.elf@755:0:0" \
        "/apps/jarvisd.osp/INITTAB=pakete/jarvisd/INITTAB@644:0:0" "/apps/jarvisd.osp/bin/jarvisd=$T/jarvisd@644:0:0" \
        "$@" > "$T/mkfs.txt" 2>&1
}
image "$T/a.img" "$T/init.elf" && ok "image A: packages with INITTAB, no /bin/jarvisd" || { bad "mkfs A failed"; tail -3 "$T/mkfs.txt"; }
image "$T/b.img" "$T/init.elf" "/bin/jarvisd=$T/jarvisd@755:0:0" && ok "image B: same, plus the image's own /bin/jarvisd" || bad "mkfs B failed"
image "$T/c.img" "$T/init_old.elf" && ok "image C: old init" || bad "mkfs C failed"

run_case() { # name image script
    cp "$2" "$T/live-$1.img"
    timeout 300 qemu-system-x86_64 -kernel "$T/k0.img" -m 256 \
        -append "osum nokbd nosched noproc nofs noring3 script=sh $3" \
        -serial "file:$T/$1.txt" -display none -no-reboot \
        -drive "file=$T/live-$1.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    rm -f "$T/live-$1.img"
}

echo "== 4. boot with package drop-ins =="
run_case a "$T/a.img" /t/run.sh
F="$T/a.txt"
has "$F" "init: dienste=5" "init merges /etc/inittab with the INITTAB of 4 bundles (5 services)"
is "demo (INITTAB of a bundle) runs" "$(col "$F" demo 2)" "running"
is "a drop-in line without the bundle path is refused (evil1)" "$(grep -ac '^evil1 ' "$F")" "0"
is "a drop-in ctrl line is refused (evil2)" "$(grep -ac '^evil2 ' "$F")" "0"
is "unless=<existing file> keeps the service stopped" "$(col "$F" yieldA 2)" "stopped"
is "and it was never started" "$(col "$F" yieldA 4)" "0"
is "unless=<missing file> lets it run" "$(col "$F" yieldB 2)" "running"
is "the real jarvisd INITTAB waits for the network" "$(col "$F" jarvisd 2)" "waiting"
has "$F" "jarvisd: /etc/jarvis/permissions.conf missing" "the packaged helper runs from /apps/jarvisd.osp/bin"

echo "== 5. install and remove while running =="
awk '/--LATE--/{f=1} /--GONE--/{f=0} f' "$F" > "$T/late.txt"
is "after install + svc rescan the new service runs" "$(col "$T/late.txt" late 2)" "running"
awk '/--GONE--/{f=1} f' "$F" > "$T/gone.txt"
g=$(col "$T/gone.txt" late 2)
case "$g" in done|stopped) ok "after remove + svc rescan the service is stopped ($g)";; *) bad "service state after remove: '$g'";; esac
is "services of the image are untouched by the rescan" "$(col "$T/gone.txt" demo 2)" "running"

echo "== 6. the image's own /bin/jarvisd wins =="
run_case b "$T/b.img" /t/short.sh
is "packaged jarvisd stays stopped when /bin/jarvisd exists" "$(col "$T/b.txt" jarvisd 2)" "stopped"
is "and has zero starts" "$(col "$T/b.txt" jarvisd 4)" "0"

echo "== 7. counter-probe: old init =="
run_case c "$T/c.img" /t/short.sh
has "$T/c.txt" "init: dienste=1" "old init sees only /etc/inittab"
is "and starts no bundle service" "$(grep -ac '^demo ' "$T/c.txt")" "0"

echo "PKGSVC: $pass passed, $fail failed"
[ "$fail" = 0 ]
