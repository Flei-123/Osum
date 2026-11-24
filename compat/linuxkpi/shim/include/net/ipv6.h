/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_NET_IPV6_H
#define LKPI_NET_IPV6_H
#include <linux/in6.h>
#include <linux/string.h>
#include <linux/skbuff.h>
struct ipv6hdr { __u8 priority:4, version:4; __u8 flow_lbl[3]; __be16 payload_len; __u8 nexthdr; __u8 hop_limit; struct in6_addr saddr; struct in6_addr daddr; };
static inline struct ipv6hdr *ipv6_hdr(const struct sk_buff *skb) { return (struct ipv6hdr *)skb->data; }
static inline bool ipv6_addr_equal(const struct in6_addr *a, const struct in6_addr *b) { return !memcmp(a, b, sizeof(*a)); }
static inline bool ipv6_addr_any(const struct in6_addr *a) { return !(a->s6_addr32[0] | a->s6_addr32[1] | a->s6_addr32[2] | a->s6_addr32[3]); }
static inline void ipv6_addr_copy(struct in6_addr *d, const struct in6_addr *s) { memcpy(d, s, sizeof(*d)); }
#define NEXTHDR_TCP 6
#define NEXTHDR_UDP 17
#define NEXTHDR_ICMP 58
#endif
