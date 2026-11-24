/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_MOD_DEVICETABLE_H
#define LKPI_LINUX_MOD_DEVICETABLE_H
#include <linux/types.h>
#define PCI_ANY_ID (~0U)
typedef unsigned long kernel_ulong_t;
struct pci_device_id {
	u32 vendor;
	u32 device;
	u32 subvendor;
	u32 subdevice;
	u32 class;
	u32 class_mask;
	unsigned long driver_data;
};
#endif
