# SPDX-License-Identifier: GPL-2.0-only
LKPI_SHIM_SOURCES="heap string printk resource pci drm_core drm_kms drm_vram drm_fbdev drm_backend shim_main"
LKPI_WIFI_SOURCES="wifi_skb wifi_mem wifi_hw wifi_dispatch wifi_upcall"
LKPI_WIFI_MODULE_SOURCES="heap string printk bitops pci wifi_skb wifi_mem wifi_slab wifi_time wifi_rand wifi_sg wifi_dev wifi_cfg wifi_mac wifi_lib wifi_pci wifi_irq wifi_sched wifi_net wifi_hw wifi_dispatch wifi_upcall wifi_glue shim_main"
LKPI_WIFI_RT_SOURCES="bitops wifi_skb wifi_mem wifi_slab wifi_time wifi_rand wifi_sched wifi_net wifi_sg wifi_dev wifi_irq"
LKPI_WIFI_DRIVER_SOURCES="wifi_fake wifi_drvmain"
LKPI_CC="${CC:-gcc-12}"
command -v "$LKPI_CC" >/dev/null 2>&1 || LKPI_CC=gcc

lkpi_flags() {
	LKPI_CFLAGS=(-O2 -ffreestanding -nostdinc -fno-pic -mcmodel=small -mno-red-zone -mgeneral-regs-only
		-fno-stack-protector -fno-asynchronous-unwind-tables -fno-common -fcf-protection=none
		-fno-tree-loop-distribute-patterns -Wall -Wextra -Werror -Wno-unused-parameter "-I$1/include")
	[ -z "${LKPI_INC:-}" ] || LKPI_CFLAGS+=(-isystem "$LKPI_INC")
}

lkpi_driver_headers() {
	LKPI_DRIVER_HEADERS=""
	case "$1" in
		iwlwifi|wifi) LKPI_DRIVER_HEADERS="hdr-wifi" ;;
	esac
}

lkpi_fetch_headers() {
	local set=$1 work=$2 hdr path
	[ -z "${LKPI_INC:-}" ] || return 0
	if [ -z "${LINUXKPI_TARBALL:-}" ]; then
		local cached="${LINUXKPI_CACHE:-/root/lkpi-src/dl612}/linux-6.12.101.tar.xz"
		[ -f "$cached" ] && export LINUXKPI_TARBALL="$cached"
	fi
	lkpi_driver_headers "$set"
	mkdir -p "$work/inc/linux"
	for hdr in $LKPI_DRIVER_HEADERS; do
		path=$(bash compat/linuxkpi/fetch.sh "$hdr" "$work/$hdr") || return 1
		cp -r "$path/include/net" "$work/inc/"
		cp "$path"/include/linux/*.h "$path"/include/uapi/linux/*.h "$work/inc/linux/"
	done
	LKPI_INC="$work/inc"
}

lkpi_driver_flags() {
	LKPI_DRIVER_FLAGS=()
	case "$1" in
		bochs) LKPI_DRIVER_FLAGS=(-Wno-pointer-sign) ;;
		iwlwifi) LKPI_DRIVER_FLAGS=(-Wno-error -w -D__KERNEL__ -DKBUILD_MODNAME='"iwlwifi"' -DLKPI_MULTI_INIT -include osum/kconfig_iwlwifi.h) ;;
	esac
}
