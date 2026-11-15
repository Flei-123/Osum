#ifndef LKPI_LINUX_SKBUFF_H
#define LKPI_LINUX_SKBUFF_H

#include <linux/types.h>
#include <linux/kernel.h>

#define SKB_CB_SIZE 48

struct sk_buff {
	struct sk_buff *next;
	u8 *head;
	u8 *data;
	u8 *tail;
	u8 *end;
	u32 len;
	u16 queue_mapping;
	u8 in_use;
	char cb[SKB_CB_SIZE] __attribute__((aligned(8)));
};

struct sk_buff_head {
	struct sk_buff *first;
	struct sk_buff *last;
	u32 qlen;
};

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
void __skb_queue_tail(struct sk_buff_head *list, struct sk_buff *skb);
struct sk_buff *__skb_dequeue(struct sk_buff_head *list);
u32 skb_queue_len(const struct sk_buff_head *list);

#endif
