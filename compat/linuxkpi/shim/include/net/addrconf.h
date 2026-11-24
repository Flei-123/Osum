/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_NET_ADDRCONF_H
#define LKPI_NET_ADDRCONF_H
#include <net/ipv6.h>
void addrconf_addr_solict_mult(const struct in6_addr *addr, struct in6_addr *solicited);
#endif
