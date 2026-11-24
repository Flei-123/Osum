/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_VMALLOC_H
#define LKPI_LINUX_VMALLOC_H
#include <linux/mm.h>
void *vmalloc(unsigned long size);
void *vzalloc(unsigned long size);
void vfree(const void *addr);
#endif
