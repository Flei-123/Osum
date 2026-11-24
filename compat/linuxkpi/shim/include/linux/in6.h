/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_IN6_H
#define LKPI_LINUX_IN6_H
#include <linux/types.h>
struct in6_addr { union { __u8 u6_addr8[16]; __be16 u6_addr16[8]; __be32 u6_addr32[4]; } in6_u; };
#define s6_addr in6_u.u6_addr8
#define s6_addr16 in6_u.u6_addr16
#define s6_addr32 in6_u.u6_addr32
struct in_addr { __be32 s_addr; };
#define IPPROTO_ICMP 1
#define IPPROTO_TCP 6
#define IPPROTO_UDP 17
#define IPPROTO_ICMPV6 58
#endif
