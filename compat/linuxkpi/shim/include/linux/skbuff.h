#ifndef LKPI_LINUX_SKBUFF_H
#define LKPI_LINUX_SKBUFF_H

#include <linux/types.h>
#include <linux/kernel.h>
#include <linux/in6.h>
#include <linux/dma-direction.h>
struct device;
struct page;

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
	u8 *head_alloc;
	u16 mac_header;
	u16 transport_header;
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
void skb_queue_tail(struct sk_buff_head *list, struct sk_buff *skb);
struct sk_buff *skb_dequeue(struct sk_buff_head *list);
void skb_queue_purge(struct sk_buff_head *list);
void __skb_queue_purge(struct sk_buff_head *list);
void skb_queue_splice_init(struct sk_buff_head *list, struct sk_buff_head *head);
void *skb_put_data(struct sk_buff *skb, const void *data, unsigned int len);
void *skb_put_zero(struct sk_buff *skb, unsigned int len);
struct sk_buff *skb_copy(const struct sk_buff *skb, gfp_t gfp);
int pskb_expand_head(struct sk_buff *skb, int nhead, int ntail, gfp_t gfp);
int __skb_linearize(struct sk_buff *skb);
void skb_add_rx_frag(struct sk_buff *skb, int i, struct page *page, int off, int size, unsigned int truesize);
void *skb_frag_address(const skb_frag_t *frag);
dma_addr_t skb_frag_dma_map(struct device *dev, const skb_frag_t *frag, size_t offset, size_t size, enum dma_data_direction dir);
static inline unsigned int skb_frag_size(const skb_frag_t *frag) { return frag->size; }
static inline void __skb_queue_head_init(struct sk_buff_head *list) { list->first = NULL; list->last = NULL; list->qlen = 0; }
static inline int skb_queue_empty(const struct sk_buff_head *list) { return list->first == NULL; }
static inline unsigned int skb_headlen(const struct sk_buff *skb) { return skb->len - skb->data_len; }
static inline int skb_is_nonlinear(const struct sk_buff *skb) { return skb->data_len != 0; }
static inline int skb_is_gso(const struct sk_buff *skb) { return skb_shinfo(skb)->gso_size != 0; }
static inline unsigned char *skb_tail_pointer(const struct sk_buff *skb) { return skb->tail; }
static inline unsigned char *skb_mac_header(const struct sk_buff *skb) { return skb->head + skb->mac_header; }
static inline unsigned char *skb_transport_header(const struct sk_buff *skb) { return skb->head + skb->transport_header; }
static inline void skb_set_mac_header(struct sk_buff *skb, int offset) { skb->mac_header = (u16)(skb->data - skb->head) + offset; }
static inline void skb_postpush_rcsum(struct sk_buff *skb, const void *start, unsigned int len) { (void)skb; (void)start; (void)len; }

#endif
