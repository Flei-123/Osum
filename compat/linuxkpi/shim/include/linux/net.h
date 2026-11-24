/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_NET_H
#define LKPI_LINUX_NET_H
#include <linux/types.h>
struct net;
typedef struct { struct net *net; } possible_net_t;
#endif
