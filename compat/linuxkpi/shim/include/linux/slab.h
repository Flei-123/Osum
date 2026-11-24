/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_SLAB_H
#define LKPI_LINUX_SLAB_H
#include <linux/kernel.h>
#define kmalloc_array(n, size, flags) kcalloc((n), (size), (flags))
#define kzalloc_obj(p, flags) kzalloc(sizeof(*(p)), (flags))
void *kmemdup(const void *src, size_t len, gfp_t flags);
#define kfree_sensitive(p) kfree(p)
#endif
