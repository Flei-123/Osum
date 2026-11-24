/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_SLAB_H
#define LKPI_LINUX_SLAB_H
#include <linux/kernel.h>
#define SLAB_HWCACHE_ALIGN 0x2000U
#define SLAB_ACCOUNT 0U
struct kmem_cache;
struct kmem_cache *kmem_cache_create(const char *name, unsigned int size, unsigned int align, unsigned long flags, void (*ctor)(void *));
void kmem_cache_destroy(struct kmem_cache *cache);
void *kmem_cache_alloc(struct kmem_cache *cache, gfp_t flags);
void *kmem_cache_zalloc(struct kmem_cache *cache, gfp_t flags);
void kmem_cache_free(struct kmem_cache *cache, void *obj);
#define kmalloc_array(n, size, flags) kcalloc((n), (size), (flags))
#define kzalloc_obj(p, flags) kzalloc(sizeof(*(p)), (flags))
void *kmemdup(const void *src, size_t len, gfp_t flags);
#define kfree_sensitive(p) kfree(p)
#endif
