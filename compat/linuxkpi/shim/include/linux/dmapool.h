/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_DMAPOOL_H
#define LKPI_LINUX_DMAPOOL_H
#include <linux/dma-mapping.h>
struct dma_pool;
struct dma_pool *dma_pool_create(const char *name, struct device *dev, size_t size, size_t align, size_t boundary);
void dma_pool_destroy(struct dma_pool *pool);
void *dma_pool_alloc(struct dma_pool *pool, gfp_t flags, dma_addr_t *handle);
void dma_pool_free(struct dma_pool *pool, void *vaddr, dma_addr_t addr);
static inline void *dma_pool_zalloc(struct dma_pool *pool, gfp_t flags, dma_addr_t *handle)
{
	void *p = dma_pool_alloc(pool, flags, handle);
	if (p) memset(p, 0, 1);
	return p;
}
#endif
