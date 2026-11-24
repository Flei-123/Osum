/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_SORT_H
#define LKPI_LINUX_SORT_H
#include <linux/types.h>
void sort(void *base, size_t num, size_t size, int (*cmp)(const void *, const void *), void (*swap)(void *, void *, int));
#endif
