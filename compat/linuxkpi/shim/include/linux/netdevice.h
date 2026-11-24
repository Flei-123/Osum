/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_NETDEVICE_H
#define LKPI_LINUX_NETDEVICE_H
#include <linux/skbuff.h>
#include <linux/hrtimer.h>
#include <linux/string.h>
#include <linux/device.h>
#include <linux/spinlock.h>
#include <linux/rcupdate.h>
#include <linux/etherdevice.h>
#include <linux/workqueue.h>
#include <linux/jiffies.h>
#include <linux/mm.h>
#include <linux/sched.h>
#include <linux/cpu.h>
typedef u64 netdev_features_t;
#define NETIF_F_SG (1ULL << 0)
#define NETIF_F_IP_CSUM (1ULL << 1)
#define NETIF_F_HW_CSUM (1ULL << 3)
#define NETIF_F_IPV6_CSUM (1ULL << 4)
#define NETIF_F_HIGHDMA (1ULL << 5)
#define NETIF_F_RXCSUM (1ULL << 29)
#define NETIF_F_GRO (1ULL << 14)
#define NETIF_F_TSO (1ULL << 34)
#define NETIF_F_TSO6 (1ULL << 36)
#define NETIF_F_GSO (1ULL << 40)
#define NETDEV_ALIGN 32
#define IFNAMSIZ 16
#define NAPI_POLL_WEIGHT 64
#define MAX_ADDR_LEN 32
struct net_device;
struct napi_struct { struct net_device *dev; int (*poll)(struct napi_struct *, int); int weight; unsigned long state; struct list_head poll_list; int napi_id; };
struct net_device_stats { unsigned long rx_packets, tx_packets, rx_bytes, tx_bytes, rx_errors, tx_errors, rx_dropped, tx_dropped; };
struct netdev_hw_addr { struct netdev_hw_addr *next; unsigned char addr[MAX_ADDR_LEN]; };
struct netdev_hw_addr_list { struct netdev_hw_addr *first; int count; };
#define netdev_hw_addr_list_for_each(ha, l) for (ha = (l)->first; ha; ha = ha->next)
#define netdev_hw_addr_list_count(l) ((l)->count)
struct net_device { char name[IFNAMSIZ]; struct device dev; unsigned long state; unsigned int mtu; unsigned char dev_addr[MAX_ADDR_LEN]; unsigned int flags; void *priv; struct wireless_dev *ieee80211_ptr; };
void *netdev_priv(const struct net_device *dev);
struct net_device *alloc_netdev_dummy(int sizeof_priv);
void free_netdev(struct net_device *dev);
void netif_napi_add(struct net_device *dev, struct napi_struct *napi, int (*poll)(struct napi_struct *, int));
void netif_napi_add_weight(struct net_device *dev, struct napi_struct *napi, int (*poll)(struct napi_struct *, int), int weight);
void netif_napi_del(struct napi_struct *napi);
void napi_enable(struct napi_struct *napi);
void napi_disable(struct napi_struct *napi);
bool napi_schedule(struct napi_struct *napi);
bool napi_complete_done(struct napi_struct *napi, int work_done);
void napi_synchronize(const struct napi_struct *napi);
void napi_gro_receive(struct napi_struct *napi, struct sk_buff *skb);
int netif_receive_skb(struct sk_buff *skb);
void netif_rx(struct sk_buff *skb);
void netif_tx_stop_all_queues(struct net_device *dev);
void synchronize_net(void);
#define DEFINE_PER_CPU(type, name) __typeof__(type) name
#define this_cpu_ptr(p) (p)
#define per_cpu_ptr(p, cpu) (p)
#define alloc_percpu(type) ((type *)kzalloc(sizeof(type), GFP_KERNEL))
#define free_percpu(p) kfree(p)
#endif
