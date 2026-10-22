#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/gpustat/run.sh -- GPU-4 gate: /proc/gpu (kernel/fs/procfs.fi, doors in kernel/gfx/gfx.fi).
#
# Fast image like tools/bench/inos.sh (kernel + few programs + odbd on COM2). The host runs `odbc exec cat /proc/gpu`
# under three display devices and checks the text:
#   std     plain framebuffer: gpu.count 1, kind 0, name fb, util_pm -1 (never 0), util_src 0, vram bytes known
#   virtio  virtio-gpu-pci: kind 1, name virtio, vram_total -1 (host memory), present_bytes > 0 after frames
#   vmsvga  -vga vmware: kind 1, name vmsvga, vram_total > 0
#   counter-proof: the kernel of origin/main has no /proc/gpu (cat fails)
# Rules in every run: integers only except gpu0.name; a value that cannot be measured is -1, never 0.
#
#   /root/jarvis/bin/heavy bash tools/gpustat/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
PROGS="sh ls cat echo id whoami sleep wc true false seq svc init ps kill reboot shutdown cp rm mkdir mount odbd"
BLOCKS=16384
ODBC="python3 -I $ROOT/tools/odbc/odbc.py"

TMPD=$(mktemp -d)
QPID=""
cleanup() {
    [ -n "$QPID" ] && kill "$QPID" 2>/dev/null
    rm -rf "$TMPD"
}
trap cleanup EXIT

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }
finish() { echo "GPUSTAT: $pass passed, $fail failed"; [ "$fail" = 0 ]; exit $?; }

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "fetch-firnc.sh failed"; exit 1; }
[ -x "$FIRNC" ] || { echo "firnc missing"; exit 1; }
command -v qemu-system-x86_64 >/dev/null || { echo "GPUSTAT: skipped, no qemu"; exit 0; }
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then ACCEL="-accel kvm"; else ACCEL="-accel tcg"; fi

# ---------------------------------------------------------------- build
B=${GPUSTAT_KEEP:-$TMPD/b}
mkdir -p "$B"

build_kernel() { # srcroot out.mb
    local src=$1 out=$2 w
    w=$(mktemp -d "$TMPD/bk.XXXXXX")
    ( cd "$src" || exit 1
      for f in boot isr switch smp hv; do as --64 -o "$w/$f.o" "kernel/arch/x86_64/$f.s" 2>/dev/null || exit 1; done
      FIRNLIB="$src/lib" "$ROOT/$FIRNC" kernel/kmain.fi -o "$w/k.o" >"$w/e" 2>&1 \
          && FIRNLIB="$src/lib" "$ROOT/$FIRNC" kernel/uprog.fi -o "$w/u.o" >>"$w/e" 2>&1 || { head -8 "$w/e"; exit 1; }
      ld -n -T kernel/kernel.ld --defsym=KERNEL_MAIN="_F0.kernel_main" --defsym=KERNEL_TRAP="_F0.trap__entry" \
          --defsym=KERNEL_SYSCALL="_F0.sys__entry" --defsym=KERNEL_TASK_MAIN="_F0.tasks__main" \
          --defsym=KERNEL_USER_START="_F0.proc__user_start" --defsym=KERNEL_AP_MAIN="_F0.smp__ap_main" \
          --defsym=USER_MAIN="_F0.u_enter" -o "$w/k.elf" "$w/boot.o" "$w/isr.o" "$w/switch.o" "$w/smp.o" "$w/hv.o" \
          "$w/k.o" "$w/u.o" 2>"$w/ld.err" || { head -5 "$w/ld.err"; exit 1; }
      objcopy -O elf32-i386 "$w/k.elf" "$out" 2>/dev/null )
}

echo "== 1. build: kernel + $(echo $PROGS | wc -w) programs =="
if [ ! -f "$B/k0.mb" ]; then
    build_kernel "$ROOT" "$B/k0.mb" || { bad "kernel does not compile"; finish; }
fi
as --64 -o "$B/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s"
for p in $PROGS; do
    [ -f "$B/$p.elf" ] && continue
    "$FIRNC" "kernel/user/$p.fi" -o "$B/$p.o" >"$B/e$p" 2>&1 \
        || { bad "$p.fi does not compile"; head -6 "$B/e$p" | sed 's/^/        /'; finish; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" -o "$B/$p.elf" "$B/crt.o" "$B/$p.o" 2>/dev/null || { bad "ld $p"; finish; }
    strip --strip-all "$B/$p.elf"
done

# kernel of origin/main without /proc/gpu (counter-proof)
if [ ! -f "$B/kold.mb" ]; then
    mkdir -p "$TMPD/old"
    git archive "${GPUSTAT_OLD_REF:-origin/main}" kernel lib 2>/dev/null | tar -x -C "$TMPD/old" 2>/dev/null
    build_kernel "$TMPD/old" "$B/kold.mb" >"$TMPD/old.err" 2>&1 || { bad "old kernel does not compile"; head -5 "$TMPD/old.err"; }
fi
ok "built (kernel $(stat -c%s "$B/k0.mb") octets)"

# ---------------------------------------------------------------- image
TOKEN=$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')
printf '%s' "$TOKEN" > "$TMPD/token"
printf 'root:x:0:0:root:/:/bin/sh\n' > "$TMPD/passwd"
printf 'odbd:respawn:/sbin/odbd\nende:ctrl:/bin/sleep 600\n' > "$TMPD/inittab"
printf 'enable=1\n' > "$TMPD/conf_on"
printf 'none /dev devfs\nnone /proc proc\n' > "$TMPD/fstab"
SPEC=""
for p in $PROGS; do
    case $p in
        init) SPEC="$SPEC /sbin/init=$B/$p.elf@755:0:0" ;;
        odbd) SPEC="$SPEC /sbin/odbd=$B/$p.elf@755:0:0" ;;
        *)    SPEC="$SPEC /bin/$p=$B/$p.elf" ;;
    esac
done
DIRS="/bin/ /sbin/ /etc/ /dev/ /proc/ /run/@755:0:0 /d/ /tmp/@777:0:0 /var/ /var/crash/"
python3 tools/osum/mkfs.py build "$TMPD/on.img" $BLOCKS $DIRS $SPEC \
    /etc/passwd=$TMPD/passwd@644:0:0 /etc/inittab=$TMPD/inittab@644:0:0 \
    /etc/fstab=$TMPD/fstab@644:0:0 /etc/odb.token=$TMPD/token@600:0:0 /etc/odb.conf=$TMPD/conf_on@644:0:0 \
    >"$TMPD/mkfs.txt" 2>&1 || { bad "mkfs.py failed"; head -5 "$TMPD/mkfs.txt"; finish; }

# ---------------------------------------------------------------- qemu
SOCK="$TMPD/odb.sock"
start_qemu() { # kernel image comlog extra-args...
    local k=$1 img=$2 log=$3
    shift 3
    rm -f "$SOCK"
    timeout 300 qemu-system-x86_64 $ACCEL -kernel "$k" -m 512 -smp 2 \
        -append "osum vfs nokbd gfx disp ${GWORDS:-}" -display none "$@" \
        -drive "file=$img,format=raw,if=ide,index=0" \
        -serial "file:$log" \
        -chardev "socket,id=odb,path=$SOCK,server=on,wait=off" -serial chardev:odb \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    QPID=$!
    local i=0
    while [ $i -lt 50 ] && [ ! -S "$SOCK" ]; do sleep 0.1; i=$((i+1)); done
    [ -S "$SOCK" ]
}
stop_qemu() { [ -n "$QPID" ] && kill "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null; QPID=""; }
od() { timeout "${ODB_T:-60}" $ODBC --port "unix:$SOCK" --token-file "$TMPD/token" "$@"; }

# grab kernel tag extra-args... -> $TMPD/<tag>.gpu (two reads, 3 s apart); rc 1 = setup failure
grab() {
    local k=$1 tag=$2
    shift 2
    cp "$TMPD/on.img" "$TMPD/$tag.img"
    start_qemu "$k" "$TMPD/$tag.img" "$TMPD/$tag.com1" "$@" || { bad "$tag: qemu did not start"; return 1; }
    if ! ODB_T=90 od wait 80 >"$TMPD/$tag.wait" 2>&1; then
        bad "$tag: agent did not answer"; tr -d '\000' < "$TMPD/$tag.com1" | tail -10 | sed 's/^/        /'
        stop_qemu; return 1
    fi
    ODB_T=30 od exec "cat /proc/gpu" >"$TMPD/$tag.gpu" 2>&1
    sleep 3
    ODB_T=30 od exec "cat /proc/gpu" >"$TMPD/$tag.gpu2" 2>&1
    stop_qemu
    return 0
}
val() { grep -a "^$2 " "$TMPD/$1.gpu" | head -1 | cut -d' ' -f2; }
val2() { grep -a "^$2 " "$TMPD/$1.gpu2" | head -1 | cut -d' ' -f2; }
isnum() { case "$1" in ''|*[!0-9-]*|-) return 1 ;; esac; return 0; }

echo "== 2. std VGA framebuffer =="
if grab "$B/k0.mb" std -vga std; then
    sed 's/^/        /' "$TMPD/std.gpu"
    [ "$(val std gpu.count)" = 1 ] && ok "std: gpu.count 1" || bad "std: gpu.count"
    [ "$(val std gpu0.kind)" = 0 ] && ok "std: kind 0 (framebuffer only)" || bad "std: kind"
    [ "$(val std gpu0.name)" = fb ] && ok "std: name fb" || bad "std: name"
    [ "$(val std gpu0.util_pm)" = -1 ] && ok "std: util_pm -1 (not measurable, not 0)" || bad "std: util_pm"
    [ "$(val std gpu0.util_src)" = 0 ] && ok "std: util_src 0" || bad "std: util_src"
    v=$(val std gpu0.vram_total_bytes); isnum "$v" && [ "$v" != 0 ] && ok "std: vram_total_bytes $v (never 0)" || bad "std: vram_total_bytes '$v'"
    v=$(val std gpu0.present_bytes); [ "$v" = -1 ] && ok "std: present_bytes -1 (not counted)" || bad "std: present_bytes '$v'"
    v=$(val std gpu0.frames); isnum "$v" && ok "std: frames is a number ($v)" || bad "std: frames '$v'"
    v=$(val std gpu0.hw_cursor); [ "$v" = 0 ] && ok "std: hw_cursor 0" || bad "std: hw_cursor '$v'"
fi

echo "== 3. virtio-gpu =="
if grab "$B/k0.mb" vio -device virtio-gpu-pci; then
    sed 's/^/        /' "$TMPD/vio.gpu"
    [ "$(val vio gpu0.name)" = virtio ] && ok "virtio: name virtio" || bad "virtio: name '$(val vio gpu0.name)'"
    [ "$(val vio gpu0.kind)" = 1 ] && ok "virtio: kind 1 (paravirtual)" || bad "virtio: kind"
    [ "$(val vio gpu0.util_pm)" = -1 ] && ok "virtio: util_pm -1" || bad "virtio: util_pm"
    [ "$(val vio gpu0.vram_total_bytes)" = -1 ] && ok "virtio: vram_total_bytes -1 (host memory)" || bad "virtio: vram_total_bytes"
    v=$(val vio gpu0.present_bytes); isnum "$v" && [ "$v" != -1 ] && ok "virtio: present_bytes $v" || bad "virtio: present_bytes '$v'"
    v=$(val vio gpu0.frames); isnum "$v" && [ "$v" != -1 ] && ok "virtio: frames $v" || bad "virtio: frames '$v'"
    a=$(val vio gpu0.present_bytes); b=$(val2 vio gpu0.present_bytes)
    isnum "$a" && isnum "$b" && [ "$b" -ge "$a" ] && ok "virtio: present_bytes does not go backwards ($a -> $b)" || bad "virtio: present_bytes monotonic ($a -> $b)"
fi

echo "== 4. VMSVGA =="
if GWORDS=vmsvgahw grab "$B/k0.mb" vmw -vga vmware; then
    sed 's/^/        /' "$TMPD/vmw.gpu"
    [ "$(val vmw gpu0.name)" = vmsvga ] && ok "vmsvga: name vmsvga" || bad "vmsvga: name '$(val vmw gpu0.name)'"
    [ "$(val vmw gpu0.kind)" = 1 ] && ok "vmsvga: kind 1" || bad "vmsvga: kind"
    [ "$(val vmw gpu0.util_pm)" = -1 ] && ok "vmsvga: util_pm -1" || bad "vmsvga: util_pm"
    v=$(val vmw gpu0.vram_total_bytes); isnum "$v" && [ "$v" -gt 0 ] && ok "vmsvga: vram_total_bytes $v" || bad "vmsvga: vram_total_bytes '$v'"
    v=$(val vmw gpu0.vram_used_bytes); isnum "$v" && [ "$v" -gt 0 ] && ok "vmsvga: vram_used_bytes $v" || bad "vmsvga: vram_used_bytes '$v'"
    v=$(val vmw gpu0.frames); isnum "$v" && [ "$v" != -1 ] && ok "vmsvga: frames $v" || bad "vmsvga: frames '$v'"
fi

echo "== 5. format rules =="
for t in std vio vmw; do
    [ -s "$TMPD/$t.gpu" ] || continue
    bad_lines=$(grep -avE '^(gpu\.count|gpu0\.[a-z_]+) (-1|[0-9]+|fb|virtio|vmsvga)$' "$TMPD/$t.gpu" | wc -l)
    [ "$bad_lines" = 0 ] && ok "$t: every line is 'key value', integers or -1 (name aside)" || bad "$t: $bad_lines malformed lines"
done

echo "== 6. counter-proof: kernel without /proc/gpu =="
if [ -f "$B/kold.mb" ] && grab "$B/kold.mb" old -vga std; then
    if grep -aq "^gpu" "$TMPD/old.gpu"; then bad "old kernel prints gpu lines (counter-proof broken)"; else ok "old kernel: no /proc/gpu lines (gate would be red)"; fi
fi
finish
