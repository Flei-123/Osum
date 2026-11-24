/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_IP_H
#define LKPI_LINUX_IP_H
#include <linux/skbuff.h>
struct iphdr { __u8 ihl:4, version:4; __u8 tos; __be16 tot_len; __be16 id; __be16 frag_off; __u8 ttl; __u8 protocol; __sum16 check; __be32 saddr; __be32 daddr; };
static inline struct iphdr *ip_hdr(const struct sk_buff *skb) { return (struct iphdr *)skb->data; }
static inline unsigned int ip_hdrlen(const struct sk_buff *skb) { return ip_hdr(skb)->ihl * 4; }
#endif
