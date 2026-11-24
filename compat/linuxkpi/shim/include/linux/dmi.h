/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_DMI_H
#define LKPI_LINUX_DMI_H
#include <linux/kernel.h>
enum dmi_field { DMI_NONE, DMI_BIOS_VENDOR, DMI_BIOS_VERSION, DMI_BIOS_DATE, DMI_SYS_VENDOR, DMI_PRODUCT_NAME, DMI_PRODUCT_VERSION,
	DMI_PRODUCT_SERIAL, DMI_PRODUCT_UUID, DMI_PRODUCT_SKU, DMI_PRODUCT_FAMILY, DMI_BOARD_VENDOR, DMI_BOARD_NAME, DMI_BOARD_VERSION };
struct dmi_strmatch { unsigned char slot; char substr[79]; };
struct dmi_system_id { int (*callback)(const struct dmi_system_id *); const char *ident; struct dmi_strmatch matches[4]; void *driver_data; };
#define DMI_MATCH(a, b) { .slot = a, .substr = b }
#define DMI_EXACT_MATCH(a, b) { .slot = a, .substr = b }
const char *dmi_get_system_info(int field);
int dmi_check_system(const struct dmi_system_id *list);
bool dmi_match(enum dmi_field f, const char *str);
#endif
