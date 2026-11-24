/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_NET_IP6_CHECKSUM_H
#define LKPI_NET_IP6_CHECKSUM_H
#include <net/ipv6.h>
__sum16 csum_ipv6_magic(const struct in6_addr *saddr, const struct in6_addr *daddr, __u32 len, __u8 proto, __wsum csum);
#endif
