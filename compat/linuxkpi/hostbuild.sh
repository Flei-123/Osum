#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
. tools/lib/tmpdir.sh
D=$(mktemp -d); osum_tmp_guard "" "$D"
fin() { echo "LINUXKPI-HOST: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }
CC="${CC:-gcc-12}"; command -v "$CC" >/dev/null 2>&1 || CC=gcc
INC=compat/linuxkpi/shim/include
HDR=$INC/osum/osum_if.h
B="$D/b"
bash compat/linuxkpi/build.sh "$B" > "$D/build.txt" 2>&1 && ok "shim and driver build, closure ok, modules signed" || { bad "build"; tail -5 "$D/build.txt"; fin; }
objcopy --redefine-sym module_init=shim_module_init --redefine-sym module_exit=shim_module_exit "$B/linuxkpi.o" "$D/h_kpi.o"
objcopy --redefine-sym module_init=driver_module_init --redefine-sym module_exit=driver_module_exit "$B/bochs_drv.o" "$D/h_drv.o"
"$CC" -O1 -ffreestanding -fno-builtin -nostdlib -static -no-pie -fno-pic -fno-stack-protector -Wall -Wextra -Werror "-I$INC" \
    compat/linuxkpi/hosttest/harness.c "$D/h_kpi.o" "$D/h_drv.o" -o "$D/harness" > "$D/hc.txt" 2>&1 && ok "harness links against the unmodified shim and driver objects" || { bad "harness build"; tail -5 "$D/hc.txt"; fin; }
for v in ok rev1 badid bar0small bar0min badvendor abi2; do timeout 60 "$D/harness" $v > "$D/r-$v.txt" 2>&1; done
GOOD="xres=1024 yres=768 bpp=32 enable=65 vwidth=1024 vheight=4096 xoff=0 yoff=0"
NONE="xres=0 yres=0 bpp=0 enable=0 vwidth=0 vheight=0 xoff=0 yoff=0"
has "$D/r-ok.txt" "harness: result ok shim_rc=0 drv_rc=0 $GOOD endian=1 cmd=3 pixbad=0 guard=0 found=1 modeset=1 denied=0" "ok: 1024x768 modeset, registers, pixels, endianness"
has "$D/r-ok.txt" "harness: exit ok open=0 freedenied=0" "ok: every frame returned after both exits"
has "$D/r-rev1.txt" "endian=0 cmd=3 pixbad=0" "rev1: no qemu-ext endian write on revision 1"
has "$D/r-badid.txt" "harness: result badid shim_rc=0 drv_rc=-19 $NONE endian=0 cmd=3 pixbad=-1 guard=0 found=0 modeset=0 denied=0" "badid: probe refused, no mode set"
has "$D/r-bar0small.txt" "harness: result bar0small shim_rc=0 drv_rc=-12 $NONE" "bar0small: 2 MiB BAR refused by the driver"
has "$D/r-bar0min.txt" "xres=800 yres=600 bpp=32 enable=65" "bar0min: 4 MiB BAR gets 800x600, never 1024x768"
has "$D/r-bar0min.txt" "pixbad=0 guard=0 found=1 modeset=0" "bar0min: pixels right, nothing written beyond the BAR"
has "$D/r-badvendor.txt" "harness: result badvendor shim_rc=0 drv_rc=-19 $NONE" "badvendor: no matching device, no mode set"
has "$D/r-abi2.txt" "harness: result abi2 shim_rc=-38 drv_rc=-38 $NONE" "abi2: both modules refuse a foreign kernel ABI"
for v in badid bar0small badvendor abi2; do has "$D/r-$v.txt" "open=0 freedenied=0" "$v: no frame left after exit"; done
cl() { python3 -I compat/linuxkpi/closure.py --header "${3:-$HDR}" --ksym kernel/lib/ksym.fi "${1:-$B/linuxkpi.o}" "${2:-$B/bochs_drv.o}" > "$D/c.txt" 2>&1; }
mutant() { local rc=$? name=$1 want=$2; if [ "$rc" -ne 0 ] && grep -qF -- "$want" "$D/c.txt"; then ok "closure mutant $name rejected"; else bad "closure mutant $name not rejected"; fi; }
cl; [ $? -eq 0 ] && ok "closure baseline accepted" || bad "closure baseline"
objcopy --redefine-sym drm_dev_put=drm_dev_put_gone "$B/bochs_drv.o" "$D/m1.o"; cl "" "$D/m1.o"; mutant missing-driver-symbol "undefined symbol drm_dev_put_gone"
objcopy --redefine-sym k_puts=k_puts_gone "$B/linuxkpi.o" "$D/m2.o"; cl "$D/m2.o"; mutant missing-kernel-symbol "undefined symbol k_puts_gone"
args=(); for i in $(seq 1 55); do args+=(--add-section ".lkx$i=/dev/null"); done
objcopy "${args[@]}" "$B/linuxkpi.o" "$D/m3.o"; cl "$D/m3.o"; mutant too-many-sections "loader limit 64"
long=$(printf 'x%.0s' $(seq 1 70))
objcopy --redefine-sym "lkpi_heap_release=$long" "$B/linuxkpi.o" "$D/m4.o"; cl "$D/m4.o"; mutant long-export-name "export name longer than 63"
sed 's/k_frames_free/k_frames_gone/g' "$HDR" > "$D/bad_if.h"; cl "" "" "$D/bad_if.h"; mutant kernel-symbol-not-in-ksym "k_frames_gone is not in the kernel symbol table"
fin
