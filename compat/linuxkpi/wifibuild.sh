# SPDX-License-Identifier: GPL-2.0-only
build_wifi() {
    local shim=$1 out=$2 n objs=()
    lkpi_flags "$shim"
    for n in $LKPI_WIFI_SOURCES; do
        "$LKPI_CC" "${LKPI_CFLAGS[@]}" -c "$shim/src/$n.c" -o "$out.$n.o" || return 1
        objs+=("$out.$n.o")
    done
    "$LKPI_CC" "${LKPI_CFLAGS[@]}" -I"$shim/src" -c compat/linuxkpi/hosttest/wifi_harness.c -o "$out.harness.o" || return 1
    "$LKPI_CC" "${LKPI_CFLAGS[@]}" -c compat/linuxkpi/hosttest/wifi_heap_stub.c -o "$out.heap.o" || return 1
    ld -static -nostdlib -e _start -o "$out" "$out.harness.o" "$out.heap.o" "${objs[@]}"
}

build_wifi_rt() {
    local shim=$1 out=$2 n objs=()
    lkpi_flags "$shim"
    for n in $LKPI_WIFI_RT_SOURCES; do
        "$LKPI_CC" "${LKPI_CFLAGS[@]}" -I"$shim/src" -c "$shim/src/$n.c" -o "$out.$n.o" || return 1
        objs+=("$out.$n.o")
    done
    "$LKPI_CC" "${LKPI_CFLAGS[@]}" -I"$shim/src" -c compat/linuxkpi/hosttest/wifi_rt_harness.c -o "$out.harness.o" || return 1
    "$LKPI_CC" "${LKPI_CFLAGS[@]}" -c compat/linuxkpi/hosttest/wifi_heap_stub.c -o "$out.heap.o" || return 1
    ld -static -nostdlib -e _start -o "$out" "$out.harness.o" "$out.heap.o" "${objs[@]}"
}
