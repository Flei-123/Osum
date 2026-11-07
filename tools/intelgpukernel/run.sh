#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
. tools/lib/qemu.sh
. tools/lib/summary.sh
. tools/lib/pidkill.sh

export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
BASE_REF=${INTELGPU_BASE_REF:-0f667ef51}
BASE_WORDS="osum nokbd noproc nofs noring3"
DONE_LINE='^smp: gs-basis'
NO_DEVICE='^intelgpu: no device$'
ANY_LINE='^intelgpu:'

TMPD=$(mktemp -d)
summary_begin INTELGPU-KERNEL
trap 'summary_guard; rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

build_kernel() {
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

boot() {
    local kernel=$1 name=$2 words=$3 log="$TMPD/$2.txt" pid i
    rm -f "$log"
    $QEMU_X86 -kernel "$kernel" -m 256 -smp 2 -append "$BASE_WORDS $words" \
        -serial "file:$log" -display none -no-reboot >/dev/null 2>&1 &
    pid=$!
    for i in $(seq 1 300); do
        grep -aq "$DONE_LINE" "$log" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.2
    done
    osum_kill_tree "$pid"
    wait "$pid" 2>/dev/null
}

has() { grep -aq "$2" "$TMPD/$1.txt"; }
count() { grep -ac "$2" "$TMPD/$1.txt"; }

[ -x "$FIRNC" ] || bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
mkdir -p "$TMPD/base"
git archive "$BASE_REF" kernel lib | tar -x -C "$TMPD/base"
ln -s "$ROOT/vendor" "$TMPD/base/vendor"

build_kernel "$ROOT" "$TMPD/new.mb" && ok "kernel with the driver builds" || bad "kernel with the driver does not build"
build_kernel "$TMPD/base" "$TMPD/base.mb" && ok "kernel before the driver ($BASE_REF) builds" || bad "base kernel does not build"

if [ -f "$TMPD/new.mb" ] && [ -f "$TMPD/base.mb" ]; then
    boot "$TMPD/new.mb" plain ""
    boot "$TMPD/new.mb" gpu "intelgpu"
    boot "$TMPD/new.mb" edid "intelgpuedid"
    boot "$TMPD/new.mb" both "intelgpu intelgpuedid"
    boot "$TMPD/new.mb" near "intelgpux intelgpuedidx"
    boot "$TMPD/base.mb" oldgpu "intelgpu intelgpuedid"

    for n in plain gpu edid both near oldgpu; do
        has "$n" "$DONE_LINE" && ok "$n: boot completes" || bad "$n: boot did not complete"
        has "$n" 'EXCEPTION\|kernel halted\|panic:' && bad "$n: fault line" || ok "$n: no fault line"
    done
    [ "$(count plain "$ANY_LINE")" = 0 ] && ok "no word: no intelgpu line" || bad "no word: intelgpu line printed"
    for n in gpu edid both; do
        [ "$(count $n "$NO_DEVICE")" = 1 ] && ok "$n: one 'no device' line without hardware" || bad "$n: 'no device' line count $(count $n "$NO_DEVICE")"
        has "$n" '^intelgpu: bound' && bad "$n: bound line without hardware" || ok "$n: no bound line without hardware"
        has "$n" '^intelgpu: edid' && bad "$n: edid line without hardware" || ok "$n: no edid line without hardware"
    done
    [ "$(count near "$ANY_LINE")" = 0 ] && ok "near words are not words (whole-word match)" || bad "near words enabled the driver"
    [ "$(count oldgpu "$ANY_LINE")" = 0 ] && ok "counter-proof: kernel without the driver prints no intelgpu line" || bad "counter-proof: old kernel printed an intelgpu line"
fi

summary_emit "$pass" "$fail" 10
