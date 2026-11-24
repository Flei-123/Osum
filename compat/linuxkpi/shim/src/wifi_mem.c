#include "wifi.h"
#include <linux/dma-mapping.h>

static void *dma_page_align(void *raw)
{
	unsigned long aligned = ((unsigned long)raw + sizeof(void *) + PAGE_SIZE - 1) & ~((unsigned long)PAGE_SIZE - 1);

	((void **)aligned)[-1] = raw;
	return (void *)aligned;
}

void *dma_alloc_coherent(struct device *dev, size_t size, dma_addr_t *handle, gfp_t gfp)
{
	void *ptr;

	(void)dev;
	(void)gfp;
	if (size < PAGE_SIZE) {
		ptr = kzalloc(size, GFP_KERNEL);
	} else {
		void *raw = kzalloc(size + PAGE_SIZE, GFP_KERNEL);

		ptr = raw ? dma_page_align(raw) : NULL;
	}
	if (!ptr)
		return NULL;
	*handle = (dma_addr_t)(unsigned long)ptr;
	return ptr;
}

void dma_free_coherent(struct device *dev, size_t size, void *cpu_addr, dma_addr_t handle)
{
	(void)dev;
	(void)handle;
	kfree(size < PAGE_SIZE ? cpu_addr : ((void **)cpu_addr)[-1]);
}

dma_addr_t dma_map_single(struct device *dev, void *ptr, size_t size, enum dma_data_direction dir)
{
	(void)dev;
	(void)size;
	(void)dir;
	return (dma_addr_t)(unsigned long)ptr;
}

void dma_unmap_single(struct device *dev, dma_addr_t addr, size_t size, enum dma_data_direction dir)
{
	(void)dev;
	(void)addr;
	(void)size;
	(void)dir;
}

dma_addr_t dma_map_page_attrs(struct device *dev, struct page *page, size_t offset, size_t size,
			      enum dma_data_direction dir, unsigned long attrs)
{
	(void)attrs;
	return dma_map_single(dev, (u8 *)page_address(page) + offset, size, dir);
}

dma_addr_t dma_map_page(struct device *dev, struct page *page, size_t offset, size_t size,
			enum dma_data_direction dir)
{
	return dma_map_page_attrs(dev, page, offset, size, dir, 0);
}

void dma_unmap_page_attrs(struct device *dev, dma_addr_t addr, size_t size, enum dma_data_direction dir,
			  unsigned long attrs)
{
	(void)attrs;
	dma_unmap_single(dev, addr, size, dir);
}

void dma_unmap_page(struct device *dev, dma_addr_t addr, size_t size, enum dma_data_direction dir)
{
	dma_unmap_single(dev, addr, size, dir);
}

int dma_mapping_error(struct device *dev, dma_addr_t addr)
{
	(void)dev;
	return addr == DMA_MAPPING_ERROR;
}

int dma_set_mask(struct device *dev, u64 mask)
{
	(void)dev;
	return mask ? 0 : -EIO;
}

int dma_set_coherent_mask(struct device *dev, u64 mask)
{
	return dma_set_mask(dev, mask);
}

int dma_set_mask_and_coherent(struct device *dev, u64 mask)
{
	return dma_set_mask(dev, mask);
}

void dma_sync_single_for_cpu(struct device *dev, dma_addr_t addr, size_t size, enum dma_data_direction dir)
{
	(void)dev;
	(void)addr;
	(void)size;
	(void)dir;
}

void dma_sync_single_for_device(struct device *dev, dma_addr_t addr, size_t size, enum dma_data_direction dir)
{
	dma_sync_single_for_cpu(dev, addr, size, dir);
}

struct page *alloc_pages(gfp_t gfp, unsigned int order)
{
	struct page *page;

	(void)gfp;
	page = kzalloc(sizeof(*page), GFP_KERNEL);
	if (!page)
		return NULL;
	page->virtual = kzalloc(PAGE_SIZE << order, GFP_KERNEL);
	if (!page->virtual) {
		kfree(page);
		return NULL;
	}
	page->refcount.counter = 1;
	return page;
}

void __free_pages(struct page *page, unsigned int order)
{
	(void)order;
	if (!page)
		return;
	kfree(page->virtual);
	kfree(page);
}

void *page_address(const struct page *page)
{
	return page->virtual;
}

void get_page(struct page *page)
{
	page->refcount.counter++;
}

void put_page(struct page *page)
{
	if (--page->refcount.counter == 0)
		__free_pages(page, 0);
}

int page_count(struct page *page)
{
	return page->refcount.counter;
}

int get_order(unsigned long size)
{
	int order = 0;

	while ((PAGE_SIZE << order) < size)
		order++;
	return order;
}
