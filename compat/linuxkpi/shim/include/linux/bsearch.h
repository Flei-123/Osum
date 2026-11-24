/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_BSEARCH_H
#define LKPI_LINUX_BSEARCH_H
#include <linux/types.h>
void *bsearch(const void *key, const void *base, size_t num, size_t size, int (*cmp)(const void *key, const void *elt));
#endif
