/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_DMA_MAPPING_H
#define LKPI_LINUX_DMA_MAPPING_H
#include <linux/device.h>
#include <linux/dma-direction.h>
#define DMA_BIT_MASK(n) (((n) == 64) ? ~0ULL : ((1ULL << (n)) - 1))

#define DMA_ATTR_SKIP_CPU_SYNC (1UL << 5)
#define DMA_MAPPING_ERROR (~(dma_addr_t)0)
struct page;
void *dma_alloc_coherent(struct device *dev, size_t size, dma_addr_t *handle, gfp_t gfp);
void dma_free_coherent(struct device *dev, size_t size, void *cpu_addr, dma_addr_t handle);
dma_addr_t dma_map_single(struct device *dev, void *ptr, size_t size, enum dma_data_direction dir);
void dma_unmap_single(struct device *dev, dma_addr_t addr, size_t size, enum dma_data_direction dir);
dma_addr_t dma_map_page(struct device *dev, struct page *page, size_t offset, size_t size, enum dma_data_direction dir);
dma_addr_t dma_map_page_attrs(struct device *dev, struct page *page, size_t offset, size_t size, enum dma_data_direction dir, unsigned long attrs);
void dma_unmap_page(struct device *dev, dma_addr_t addr, size_t size, enum dma_data_direction dir);
void dma_unmap_page_attrs(struct device *dev, dma_addr_t addr, size_t size, enum dma_data_direction dir, unsigned long attrs);
int dma_mapping_error(struct device *dev, dma_addr_t addr);
int dma_set_mask(struct device *dev, u64 mask);
int dma_set_coherent_mask(struct device *dev, u64 mask);
int dma_set_mask_and_coherent(struct device *dev, u64 mask);
void dma_sync_single_for_cpu(struct device *dev, dma_addr_t addr, size_t size, enum dma_data_direction dir);
struct sg_table;
int dma_map_sgtable(struct device *dev, struct sg_table *sgt, enum dma_data_direction dir, unsigned long attrs);
void dma_unmap_sgtable(struct device *dev, struct sg_table *sgt, enum dma_data_direction dir, unsigned long attrs);
void dma_sync_single_for_device(struct device *dev, dma_addr_t addr, size_t size, enum dma_data_direction dir);
#endif
