/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_TCP_H
#define LKPI_LINUX_TCP_H
#include <linux/skbuff.h>
struct tcphdr { __be16 source; __be16 dest; __be32 seq; __be32 ack_seq; __u16 res1:4, doff:4, fin:1, syn:1, rst:1, psh:1, ack:1, urg:1, ece:1, cwr:1; __be16 window; __sum16 check; __be16 urg_ptr; };
static inline struct tcphdr *tcp_hdr(const struct sk_buff *skb) { return (struct tcphdr *)skb->data; }
static inline unsigned int tcp_hdrlen(const struct sk_buff *skb) { return tcp_hdr(skb)->doff * 4; }
#endif
