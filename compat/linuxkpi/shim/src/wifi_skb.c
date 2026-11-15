#include <linux/skbuff.h>
#include <osum/lkpi80211.h>

#define SKB_POOL_COUNT 64
#define SKB_DATA_BYTES 2048

static struct sk_buff pool[SKB_POOL_COUNT];
static u8 pool_data[SKB_POOL_COUNT][SKB_DATA_BYTES] __attribute__((aligned(16)));
static u32 pool_free = SKB_POOL_COUNT;
static u32 errors;

struct sk_buff *alloc_skb(unsigned int size, gfp_t priority)
{
	u32 i;

	(void)priority;
	if (size > SKB_DATA_BYTES) {
		errors++;
		return NULL;
	}
	for (i = 0; i < SKB_POOL_COUNT; i++) {
		struct sk_buff *skb = &pool[i];

		if (skb->in_use)
			continue;
		skb->next = NULL;
		skb->head = pool_data[i];
		skb->data = skb->head;
		skb->tail = skb->head;
		skb->end = skb->head + size;
		skb->len = 0;
		skb->queue_mapping = 0;
		skb->in_use = 1;
		for (u32 c = 0; c < SKB_CB_SIZE; c++)
			skb->cb[c] = 0;
		pool_free--;
		return skb;
	}
	errors++;
	return NULL;
}

struct sk_buff *dev_alloc_skb(unsigned int length)
{
	return alloc_skb(length, 0);
}

void kfree_skb(struct sk_buff *skb)
{
	if (!skb)
		return;
	if (!skb->in_use) {
		errors++;
		return;
	}
	skb->in_use = 0;
	pool_free++;
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
	return pool_free;
}

u32 lkpi_skb_pool_size(void)
{
	return SKB_POOL_COUNT;
}

u32 lkpi_skb_error_count(void)
{
	return errors;
}
