/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_IF_ARP_H
#define LKPI_LINUX_IF_ARP_H
#include <linux/skbuff.h>
struct arphdr { __be16 ar_hrd; __be16 ar_pro; unsigned char ar_hln; unsigned char ar_pln; __be16 ar_op; };
#define ARPHRD_ETHER 1
#define ARPOP_REQUEST 1
#define ARPOP_REPLY 2
static inline struct arphdr *arp_hdr(const struct sk_buff *skb) { return (struct arphdr *)skb->data; }
#endif
