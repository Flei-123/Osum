/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_IF_ETHER_H
#define LKPI_LINUX_IF_ETHER_H
#include <linux/types.h>
#define ETH_ALEN 6
#define ETH_HLEN 14
#define ETH_TLEN 2
#define ETH_DATA_LEN 1500
#define ETH_FRAME_LEN 1514
#define ETH_P_8021Q 0x8100
#define ETH_P_8021AD 0x88A8
#define ETH_P_IP 0x0800
#define ETH_P_ARP 0x0806
#define ETH_P_IPV6 0x86DD
#define ETH_P_PAE 0x888E
#define ETH_P_TDLS 0x890D
#define ETH_P_80221 0x8917
#define ETH_P_802_3_MIN 0x0600
struct ethhdr { unsigned char h_dest[ETH_ALEN]; unsigned char h_source[ETH_ALEN]; __be16 h_proto; } __attribute__((packed));
#endif
