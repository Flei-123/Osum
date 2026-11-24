#include "wifi.h"
#include <linux/dmapool.h>
#include <linux/dma-mapping.h>
#include <linux/vmalloc.h>

struct dma_pool {
	size_t size;
	bool managed;
};

struct kmem_cache {
	size_t size;
	void (*ctor)(void *object);
};

struct dma_pool *dma_pool_create(const char *name, struct device *dev, size_t size, size_t align, size_t boundary)
{
	struct dma_pool *pool;

	(void)name;
	(void)dev;
	(void)align;
	(void)boundary;
	pool = kzalloc(sizeof(*pool), GFP_KERNEL);
	if (pool)
		pool->size = size;
	return pool;
}

static void managed_pool_release(void *payload)
{
	(void)payload;
}

struct dma_pool *dmam_pool_create(const char *name, struct device *dev, size_t size, size_t align, size_t boundary)
{
	struct dma_pool *pool = lkpi_devres_alloc(dev, sizeof(*pool), managed_pool_release);

	(void)name;
	(void)align;
	(void)boundary;
	if (pool) {
		pool->size = size;
		pool->managed = true;
	}
	return pool;
}

void dma_pool_destroy(struct dma_pool *pool)
{
	if (pool && !pool->managed)
		kfree(pool);
}

void *dma_pool_alloc(struct dma_pool *pool, gfp_t flags, dma_addr_t *handle)
{
	return dma_alloc_coherent(NULL, pool->size, handle, flags);
}

void dma_pool_free(struct dma_pool *pool, void *vaddr, dma_addr_t addr)
{
	dma_free_coherent(NULL, pool->size, vaddr, addr);
}

struct kmem_cache *kmem_cache_create(const char *name, unsigned int size, unsigned int align, unsigned long flags,
				     void (*ctor)(void *))
{
	struct kmem_cache *cache;

	(void)name;
	(void)align;
	(void)flags;
	cache = kzalloc(sizeof(*cache), GFP_KERNEL);
	if (cache) {
		cache->size = size;
		cache->ctor = ctor;
	}
	return cache;
}

void kmem_cache_destroy(struct kmem_cache *cache)
{
	kfree(cache);
}

void *kmem_cache_alloc(struct kmem_cache *cache, gfp_t flags)
{
	void *object = kmalloc(cache->size, flags);

	if (object && cache->ctor)
		cache->ctor(object);
	return object;
}

void *kmem_cache_zalloc(struct kmem_cache *cache, gfp_t flags)
{
	return kzalloc(cache->size, flags);
}

void kmem_cache_free(struct kmem_cache *cache, void *object)
{
	(void)cache;
	kfree(object);
}

void *kmemdup(const void *src, size_t len, gfp_t flags)
{
	void *copy = kmalloc(len, flags);

	if (copy)
		memcpy(copy, src, len);
	return copy;
}

void *kvmemdup(const void *src, size_t len, gfp_t flags)
{
	return kmemdup(src, len, flags);
}

void *kvmalloc(size_t size, gfp_t flags)
{
	return kmalloc(size, flags);
}

void *kvzalloc(size_t size, gfp_t flags)
{
	return kzalloc(size, flags);
}

void kvfree(const void *ptr)
{
	kfree(ptr);
}

void *vmalloc(unsigned long size)
{
	return kmalloc(size, GFP_KERNEL);
}

void *vzalloc(unsigned long size)
{
	return kzalloc(size, GFP_KERNEL);
}

void vfree(const void *addr)
{
	kfree(addr);
}

unsigned long __get_free_pages(gfp_t gfp, unsigned int order)
{
	void *ptr = kzalloc(PAGE_SIZE << order, gfp);

	return (unsigned long)ptr;
}

void free_pages(unsigned long addr, unsigned int order)
{
	(void)order;
	kfree((void *)addr);
}
