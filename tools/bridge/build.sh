#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
W=${1:?arbeitsverzeichnis}
S=${2:-0}
mkdir -p "$W"

. tools/lib/firnenv.sh
firnenv_need_firnc1
FC1=$FIRNC1
LDSCRIPT=kernel/kernel.ld
ULD=kernel/user/user.ld
PROGS=${BRIDGE_PROGS:-"sh ls cat echo chmod jsig jarvisctl"}
BLOCKS=${BRIDGE_BLOCKS:-16384}

if [ "$S" = 0 ]; then CC="$FIRNC"; else CC="$FC1"; fi
[ -x "$CC" ] || { echo "the compiler $CC is missing"; exit 1; }

for f in boot isr switch smp hv; do
    as --64 -o "$W/$f.o" "kernel/arch/x86_64/$f.s" || exit 1
done
as --64 -o "$W/crt.o" kernel/user/crt.s || exit 1

"$CC" kernel/kmain.fi -o "$W/k.o" > "$W/build.log" 2>&1 || {
    echo "kmain.fi uebersetzt nicht"; tail -20 "$W/build.log"; exit 1; }
"$CC" kernel/uprog.fi -o "$W/u.o" >> "$W/build.log" 2>&1 || {
    echo "uprog.fi uebersetzt nicht"; tail -20 "$W/build.log"; exit 1; }
ld -n -T "$LDSCRIPT" \
    --defsym=KERNEL_MAIN="_F$S.kernel_main" \
    --defsym=KERNEL_TRAP="_F$S.trap__entry" \
    --defsym=KERNEL_SYSCALL="_F$S.sys__entry" \
    --defsym=KERNEL_TASK_MAIN="_F$S.tasks__main" \
    --defsym=KERNEL_USER_START="_F$S.proc__user_start" \
    --defsym=KERNEL_AP_MAIN="_F$S.smp__ap_main" \
    --defsym=USER_MAIN="_F$S.u_enter" \
    -o "$W/k.elf" "$W/boot.o" "$W/isr.o" "$W/switch.o" "$W/smp.o" \
    "$W/hv.o" "$W/k.o" "$W/u.o" 2>"$W/ld.err" || {
    echo "ld failed on the kernel"; head -10 "$W/ld.err"; exit 1; }
objcopy -O elf32-i386 "$W/k.elf" "$W/k.mb" || exit 1

SPEC="/bin/ /etc/ /etc/ssl/ /etc/jarvis/ /var/ /var/log/ /var/jarvis/"
for p in $PROGS; do
    "$CC" "kernel/user/$p.fi" -o "$W/$p.o" >> "$W/build.log" 2>&1 || {
        echo "$p.fi uebersetzt nicht"; tail -10 "$W/build.log"; exit 1; }
    ld -T "$ULD" --defsym=USER_ENTRY="_F$S.u_start" \
        -o "$W/$p.elf" "$W/crt.o" "$W/$p.o" 2>/dev/null || {
        echo "ld ist an $p gescheitert"; exit 1; }
    strip --strip-all "$W/$p.elf"
    SPEC="$SPEC /bin/$p=$W/$p.elf"
done

FIRNLIB="$ROOT/lib" "$CC" -c --profile=app \
    -o "$W/jarvisd.o" kernel/app/jarvisd.fi >> "$W/build.log" 2>&1 || {
    echo "jarvisd.fi uebersetzt nicht"; tail -20 "$W/build.log"; exit 1; }
ld -T "$ULD" -o "$W/jarvisd.elf" "$W/jarvisd.o" 2>"$W/ldj.err" || {
    echo "ld ist an jarvisd gescheitert"; head -5 "$W/ldj.err"; exit 1; }
strip --strip-all "$W/jarvisd.elf"
SPEC="$SPEC /bin/jarvisd=$W/jarvisd.elf"

echo "bridge/build: $W/k.mb, $(echo $PROGS | wc -w) Programme + jarvisd" \
     "($(stat -c%s "$W/jarvisd.elf") Oktette)"
echo "$SPEC" > "$W/spec.txt"
