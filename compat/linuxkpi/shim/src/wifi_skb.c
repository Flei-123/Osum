#include <linux/skbuff.h>
#include <osum/lkpi80211.h>
#include <linux/mm.h>
#include <linux/dma-mapping.h>

#define SKB_LIVE_MAX 64
#define SKB_DATA_BYTES 2048
#define SKB_MAGIC_LIVE 0x5b6b0001u
#define SKB_MAGIC_FREED 0x5b6bdead
#define SKB_HEAD_ALIGN 16

static u32 live;
static u32 errors;

struct sk_buff *alloc_skb(unsigned int size, gfp_t priority)
{
	struct sk_buff *skb;
	u8 *base;

	(void)priority;
	if (size > SKB_DATA_BYTES || live >= SKB_LIVE_MAX) {
		errors++;
		return NULL;
	}
	skb = kzalloc(sizeof(*skb) + SKB_HEAD_ALIGN + size, GFP_KERNEL);
	if (!skb) {
		errors++;
		return NULL;
	}
	base = (u8 *)ALIGN((u64)(skb + 1), SKB_HEAD_ALIGN);
	skb->head = base;
	skb->data = base;
	skb->tail = base;
	skb->end = base + size;
	skb->in_use = 1;
	skb->magic = SKB_MAGIC_LIVE;
	live++;
	return skb;
}

struct sk_buff *dev_alloc_skb(unsigned int length)
{
	return alloc_skb(length, 0);
}

void kfree_skb(struct sk_buff *skb)
{
	unsigned int i;

	if (!skb)
		return;
	if (!skb->in_use || skb->magic != SKB_MAGIC_LIVE) {
		errors++;
		return;
	}
	skb->in_use = 0;
	skb->magic = SKB_MAGIC_FREED;
	live--;
	for (i = 0; i < skb_shinfo(skb)->nr_frags; i++)
		put_page(skb_shinfo(skb)->frags[i].page);
	kfree(skb->head_alloc);
	kfree(skb);
}

void dev_kfree_skb(struct sk_buff *skb)
{
	kfree_skb(skb);
}

void skb_reserve(struct sk_buff *skb, int len)
{
	if (len < 0 || skb->len != 0 || skb->data + len > skb->end) {
		errors++;
		return;
	}
	skb->data += len;
	skb->tail += len;
}

void *skb_put(struct sk_buff *skb, unsigned int len)
{
	u8 *old = skb->tail;

	if (skb->tail + len > skb->end) {
		errors++;
		return NULL;
	}
	skb->tail += len;
	skb->len += len;
	return old;
}

void *skb_push(struct sk_buff *skb, unsigned int len)
{
	if (skb->data - len < skb->head) {
		errors++;
		return NULL;
	}
	skb->data -= len;
	skb->len += len;
	return skb->data;
}

void *skb_pull(struct sk_buff *skb, unsigned int len)
{
	if (len > skb->len) {
		errors++;
		return NULL;
	}
	skb->len -= len;
	skb->data += len;
	return skb->data;
}

unsigned int skb_headroom(const struct sk_buff *skb)
{
	return skb->data - skb->head;
}

unsigned int skb_tailroom(const struct sk_buff *skb)
{
	return skb->end - skb->tail;
}

void skb_queue_head_init(struct sk_buff_head *list)
{
	list->first = NULL;
	list->last = NULL;
	list->qlen = 0;
}

void __skb_queue_tail(struct sk_buff_head *list, struct sk_buff *skb)
{
	skb->next = NULL;
	if (list->last)
		list->last->next = skb;
	else
		list->first = skb;
	list->last = skb;
	list->qlen++;
}

struct sk_buff *__skb_dequeue(struct sk_buff_head *list)
{
	struct sk_buff *skb = list->first;

	if (!skb)
		return NULL;
	list->first = skb->next;
	if (!list->first)
		list->last = NULL;
	skb->next = NULL;
	list->qlen--;
	return skb;
}

u32 skb_queue_len(const struct sk_buff_head *list)
{
	return list->qlen;
}

u32 lkpi_skb_free_count(void)
{
	return SKB_LIVE_MAX - live;
}

u32 lkpi_skb_pool_size(void)
{
	return SKB_LIVE_MAX;
}

u32 lkpi_skb_error_count(void)
{
	return errors;
}

void skb_queue_tail(struct sk_buff_head *list, struct sk_buff *skb)
{
	__skb_queue_tail(list, skb);
}

struct sk_buff *skb_dequeue(struct sk_buff_head *list)
{
	return __skb_dequeue(list);
}

void __skb_queue_purge(struct sk_buff_head *list)
{
	struct sk_buff *skb;

	while ((skb = __skb_dequeue(list)))
		kfree_skb(skb);
}

void skb_queue_purge(struct sk_buff_head *list)
{
	__skb_queue_purge(list);
}

void skb_queue_splice_init(struct sk_buff_head *list, struct sk_buff_head *head)
{
	if (!list->first)
		return;
	list->last->next = head->first;
	if (!head->first)
		head->last = list->last;
	head->first = list->first;
	head->qlen += list->qlen;
	__skb_queue_head_init(list);
}

void *skb_put_data(struct sk_buff *skb, const void *data, unsigned int len)
{
	void *dst = skb_put(skb, len);

	if (dst)
		memcpy(dst, data, len);
	return dst;
}

void *skb_put_zero(struct sk_buff *skb, unsigned int len)
{
	void *dst = skb_put(skb, len);

	if (dst)
		memset(dst, 0, len);
	return dst;
}

void *skb_frag_address(const skb_frag_t *frag)
{
	return (u8 *)page_address(frag->page) + frag->offset;
}

dma_addr_t skb_frag_dma_map(struct device *dev, const skb_frag_t *frag, size_t offset, size_t size,
			    enum dma_data_direction dir)
{
	return dma_map_page(dev, frag->page, frag->offset + offset, size, dir);
}

void skb_add_rx_frag(struct sk_buff *skb, int i, struct page *page, int off, int size, unsigned int truesize)
{
	skb_frag_t *frag;

	(void)truesize;
	if (i < 0 || i >= MAX_SKB_FRAGS) {
		errors++;
		return;
	}
	frag = &skb_shinfo(skb)->frags[i];
	frag->page = page;
	frag->offset = off;
	frag->size = size;
	skb_shinfo(skb)->nr_frags = i + 1;
	skb->len += size;
	skb->data_len += size;
}

static u8 *gather_frags(const struct sk_buff *skb, u8 *dst)
{
	unsigned int i;

	for (i = 0; i < skb_shinfo(skb)->nr_frags; i++) {
		const skb_frag_t *frag = &skb_shinfo(skb)->frags[i];

		memcpy(dst, skb_frag_address(frag), frag->size);
		dst += frag->size;
	}
	return dst;
}

int pskb_expand_head(struct sk_buff *skb, int nhead, int ntail, gfp_t gfp)
{
	u32 old_size = skb->end - skb->head;
	u32 size = old_size + nhead + ntail;
	u8 *base;

	(void)gfp;
	if (nhead < 0 || ntail < 0 || size > SKB_DATA_BYTES + SKB_HEAD_ALIGN) {
		errors++;
		return -EINVAL;
	}
	base = kzalloc(size, GFP_KERNEL);
	if (!base) {
		errors++;
		return -ENOMEM;
	}
	memcpy(base + nhead, skb->head, old_size);
	skb->data = base + nhead + (skb->data - skb->head);
	skb->tail = base + nhead + (skb->tail - skb->head);
	skb->mac_header += nhead;
	skb->transport_header += nhead;
	kfree(skb->head_alloc);
	skb->head_alloc = base;
	skb->head = base;
	skb->end = base + size;
	return 0;
}

int __skb_linearize(struct sk_buff *skb)
{
	unsigned int need = skb->data_len;
	unsigned int i;
	int rc;

	if (!need)
		return 0;
	if (skb_tailroom(skb) < need) {
		rc = pskb_expand_head(skb, 0, need - skb_tailroom(skb), GFP_ATOMIC);
		if (rc)
			return rc;
	}
	skb->tail = gather_frags(skb, skb->tail);
	for (i = 0; i < skb_shinfo(skb)->nr_frags; i++)
		put_page(skb_shinfo(skb)->frags[i].page);
	skb_shinfo(skb)->nr_frags = 0;
	skb->data_len = 0;
	return 0;
}

struct sk_buff *skb_copy(const struct sk_buff *skb, gfp_t gfp)
{
	struct sk_buff *copy = alloc_skb(skb_headroom(skb) + skb->len + skb_tailroom(skb), gfp);
	u8 *dst;

	if (!copy)
		return NULL;
	skb_reserve(copy, skb_headroom(skb));
	dst = skb_put(copy, skb->len);
	memcpy(dst, skb->data, skb_headlen(skb));
	gather_frags(skb, dst + skb_headlen(skb));
	memcpy(copy->cb, skb->cb, sizeof(copy->cb));
	copy->protocol = skb->protocol;
	copy->queue_mapping = skb->queue_mapping;
	copy->ip_summed = skb->ip_summed;
	copy->csum = skb->csum;
	copy->mac_header = skb->mac_header;
	copy->transport_header = skb->transport_header;
	skb_shinfo(copy)->tx_flags = skb_shinfo(skb)->tx_flags;
	skb_shinfo(copy)->gso_size = skb_shinfo(skb)->gso_size;
	skb_shinfo(copy)->gso_segs = skb_shinfo(skb)->gso_segs;
	skb_shinfo(copy)->gso_type = skb_shinfo(skb)->gso_type;
	return copy;
}
