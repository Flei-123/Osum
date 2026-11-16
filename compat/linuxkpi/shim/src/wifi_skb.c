#include <linux/skbuff.h>
#include <osum/lkpi80211.h>

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
	if (!skb)
		return;
	if (!skb->in_use || skb->magic != SKB_MAGIC_LIVE) {
		errors++;
		return;
	}
	skb->in_use = 0;
	skb->magic = SKB_MAGIC_FREED;
	live--;
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
