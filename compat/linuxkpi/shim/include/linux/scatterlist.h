/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_SCATTERLIST_H
#define LKPI_LINUX_SCATTERLIST_H
#include <linux/mm.h>
struct scatterlist { unsigned long page_link; unsigned int offset; unsigned int length; dma_addr_t dma_address; };
struct sg_table { struct scatterlist *sgl; unsigned int nents; unsigned int orig_nents; };
void sg_init_table(struct scatterlist *sgl, unsigned int nents);
void sg_chain(struct scatterlist *prv, unsigned int prv_nents, struct scatterlist *sgl);
void sg_set_page(struct scatterlist *sg, struct page *page, unsigned int len, unsigned int offset);
struct scatterlist *sg_next(struct scatterlist *sg);
int sg_nents(struct scatterlist *sg);
size_t sg_pcopy_from_buffer(struct scatterlist *sgl, unsigned int nents, const void *buf, size_t buflen, loff_t skip);
void sgl_free(struct scatterlist *sgl);
#define SG_CHAIN 0x01UL
#define SG_END 0x02UL
#define sg_page(sg) ((struct page *)((sg)->page_link & ~(SG_CHAIN | SG_END)))
#define sg_is_chain(sg) ((sg)->page_link & SG_CHAIN)
#define sg_is_last(sg) ((sg)->page_link & SG_END)
#define sg_chain_ptr(sg) ((struct scatterlist *)((sg)->page_link & ~(SG_CHAIN | SG_END)))
#define sg_dma_address(sg) ((sg)->dma_address)
#define sg_dma_len(sg) ((sg)->length)
#define for_each_sg(sglist, sg, nr, i) for ((i) = 0, (sg) = (sglist); (i) < (nr); (i)++, (sg) = sg_next(sg))
#endif
