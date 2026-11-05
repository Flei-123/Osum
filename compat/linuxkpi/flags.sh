# SPDX-License-Identifier: GPL-2.0-only
LKPI_SHIM_SOURCES="heap string printk resource pci drm_core drm_kms drm_vram drm_fbdev shim_main"
LKPI_CC="${CC:-gcc-12}"
command -v "$LKPI_CC" >/dev/null 2>&1 || LKPI_CC=gcc

lkpi_flags() {
	LKPI_CFLAGS=(-O2 -ffreestanding -nostdinc -fno-pic -mcmodel=small -mno-red-zone -mgeneral-regs-only
		-fno-stack-protector -fno-asynchronous-unwind-tables -fno-common -fcf-protection=none
		-fno-tree-loop-distribute-patterns -Wall -Wextra -Werror -Wno-unused-parameter "-I$1/include")
}

lkpi_driver_flags() {
	LKPI_DRIVER_FLAGS=()
	case "$1" in
		bochs) LKPI_DRIVER_FLAGS=(-Wno-pointer-sign) ;;
	esac
}
