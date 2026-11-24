#include "wifi.h"
#include <linux/scatterlist.h>

#define SG_FLAG_MASK (SG_CHAIN | SG_END)

void sg_init_table(struct scatterlist *sgl, unsigned int nents)
{
	memset(sgl, 0, nents * sizeof(*sgl));
	if (nents)
		sgl[nents - 1].page_link = SG_END;
}

void sg_set_page(struct scatterlist *sg, struct page *page, unsigned int len, unsigned int offset)
{
	sg->page_link = (sg->page_link & SG_FLAG_MASK) | (unsigned long)page;
	sg->offset = offset;
	sg->length = len;
}

void sg_chain(struct scatterlist *prv, unsigned int prv_nents, struct scatterlist *sgl)
{
	prv[prv_nents - 1].offset = 0;
	prv[prv_nents - 1].length = 0;
	prv[prv_nents - 1].page_link = ((unsigned long)sgl | SG_CHAIN) & ~SG_END;
}

struct scatterlist *sg_next(struct scatterlist *sg)
{
	if (sg_is_last(sg))
		return NULL;
	sg++;
	if (sg_is_chain(sg))
		sg = sg_chain_ptr(sg);
	return sg;
}

int sg_nents(struct scatterlist *sg)
{
	int nents = 0;

	for (; sg; sg = sg_next(sg))
		nents++;
	return nents;
}

size_t sg_pcopy_from_buffer(struct scatterlist *sgl, unsigned int nents, const void *buf, size_t buflen, loff_t skip)
{
	struct scatterlist *sg = sgl;
	size_t copied = 0;
	unsigned int i;

	for (i = 0; sg && i < nents && copied < buflen; i++, sg = sg_next(sg)) {
		size_t room = sg->length;
		size_t chunk;

		if ((size_t)skip >= room) {
			skip -= room;
			continue;
		}
		chunk = min(room - (size_t)skip, buflen - copied);
		memcpy((u8 *)page_address(sg_page(sg)) + sg->offset + skip, (const u8 *)buf + copied, chunk);
		copied += chunk;
		skip = 0;
	}
	return copied;
}

static void free_table_arrays(struct scatterlist *first)
{
	struct scatterlist *iter = first;
	struct scatterlist *array = first;
	struct scatterlist *next;

	while (iter) {
		if (sg_page(iter))
			__free_pages(sg_page(iter), 0);
		next = sg_next(iter);
		if (next != iter + 1) {
			kfree(array);
			array = next;
		}
		iter = next;
	}
}

void sgl_free(struct scatterlist *sgl)
{
	if (sgl)
		free_table_arrays(sgl);
}

int dma_map_sgtable(struct device *dev, struct sg_table *sgt, enum dma_data_direction dir, unsigned long attrs)
{
	struct scatterlist *sg;
	unsigned int i;

	(void)dev;
	(void)dir;
	(void)attrs;
	for_each_sg(sgt->sgl, sg, sgt->orig_nents, i)
		sg->dma_address = (dma_addr_t)(unsigned long)((u8 *)page_address(sg_page(sg)) + sg->offset);
	sgt->nents = sgt->orig_nents;
	return 0;
}

void dma_unmap_sgtable(struct device *dev, struct sg_table *sgt, enum dma_data_direction dir, unsigned long attrs)
{
	(void)dev;
	(void)sgt;
	(void)dir;
	(void)attrs;
}

void _devcd_free_sgtable(void *data)
{
	free_table_arrays(data);
}

void dev_coredumpsg(struct device *dev, struct scatterlist *table, size_t datalen, gfp_t gfp)
{
	(void)dev;
	(void)datalen;
	(void)gfp;
	_devcd_free_sgtable(table);
}
