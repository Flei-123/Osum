#ifndef LKPI_LINUX_SKBUFF_H
#define LKPI_LINUX_SKBUFF_H

#include <linux/types.h>
#include <linux/kernel.h>
#include <linux/in6.h>

#define SKB_CB_SIZE 48

struct sk_buff;
static inline __wsum csum_unfold(__sum16 n) { return (__wsum)n; }
typedef struct skb_frag { struct page *page; u32 offset; u32 size; } skb_frag_t;
#define MAX_SKB_FRAGS 17
struct skb_shared_hwtstamps { ktime_t hwtstamp; };
struct skb_shared_info { struct skb_shared_hwtstamps hwtstamps; u8 tx_flags; u8 nr_frags; u16 gso_size; u16 gso_segs; u32 gso_type; skb_frag_t frags[MAX_SKB_FRAGS]; struct sk_buff *frag_list; };
#define skb_walk_frags(skb, iter) for (iter = skb_shinfo(skb)->frag_list; iter; iter = iter->next)
struct sk_buff {
	struct sk_buff *next;
	u8 *head;
	u8 *data;
	u8 *tail;
	u8 *end;
	u32 len;
	u32 data_len;
	u8 ip_summed;
	__wsum csum;
	__be16 protocol;
	u16 queue_mapping;
	u8 in_use;
	u32 magic;
	char cb[SKB_CB_SIZE] __attribute__((aligned(8)));
	struct skb_shared_info shinfo;
};

struct sk_buff_head {
	struct sk_buff *first;
	struct sk_buff *last;
	u32 qlen;
};

#define CHECKSUM_NONE 0
#define CHECKSUM_UNNECESSARY 1
#define CHECKSUM_COMPLETE 2
#define CHECKSUM_PARTIAL 3
#define skb_hwtstamps(skb) (&skb_shinfo(skb)->hwtstamps)
#define skb_shinfo(skb) (&(skb)->shinfo)
struct sk_buff *alloc_skb(unsigned int size, gfp_t priority);
struct sk_buff *dev_alloc_skb(unsigned int length);
void kfree_skb(struct sk_buff *skb);
void dev_kfree_skb(struct sk_buff *skb);
void skb_reserve(struct sk_buff *skb, int len);
void *skb_put(struct sk_buff *skb, unsigned int len);
void *skb_push(struct sk_buff *skb, unsigned int len);
void *skb_pull(struct sk_buff *skb, unsigned int len);
unsigned int skb_headroom(const struct sk_buff *skb);
unsigned int skb_tailroom(const struct sk_buff *skb);
void skb_queue_head_init(struct sk_buff_head *list);
#define skb_queue_walk(queue, skb) for (skb = (queue)->first; skb; skb = skb->next)
#define skb_queue_walk_safe(queue, skb, tmp) for (skb = (queue)->first, tmp = skb ? skb->next : NULL; skb; skb = tmp, tmp = skb ? skb->next : NULL)
void __skb_queue_tail(struct sk_buff_head *list, struct sk_buff *skb);
struct sk_buff *__skb_dequeue(struct sk_buff_head *list);
u32 skb_queue_len(const struct sk_buff_head *list);

#endif
