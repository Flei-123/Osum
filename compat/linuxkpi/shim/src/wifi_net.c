#include "wifi.h"
#include <linux/etherdevice.h>
#include <linux/random.h>

#define LKPI_NAPI_DEFAULT_WEIGHT 64
#define LKPI_NAPI_ENABLED 1UL
#define LKPI_NAPI_SCHEDULED 2UL
#define LKPI_RATELIMIT_BURST 10U
#define LKPI_RATELIMIT_WINDOW (5UL * HZ)

static struct list_head scheduled = LIST_HEAD_INIT(scheduled);

static bool napi_queued(const struct napi_struct *napi)
{
	return napi->poll_list.next && !list_empty(&napi->poll_list);
}

static void napi_unqueue(struct napi_struct *napi)
{
	if (napi_queued(napi))
		list_del_init(&napi->poll_list);
}

void netif_napi_add_weight(struct net_device *dev, struct napi_struct *napi,
			   int (*poll)(struct napi_struct *, int), int weight)
{
	napi->dev = dev;
	napi->poll = poll;
	napi->weight = weight;
	napi->state = 0;
	INIT_LIST_HEAD(&napi->poll_list);
}

void netif_napi_add(struct net_device *dev, struct napi_struct *napi, int (*poll)(struct napi_struct *, int))
{
	netif_napi_add_weight(dev, napi, poll, LKPI_NAPI_DEFAULT_WEIGHT);
}

void netif_napi_del(struct napi_struct *napi)
{
	napi_unqueue(napi);
	napi->poll = NULL;
	napi->state = 0;
}

void napi_enable(struct napi_struct *napi)
{
	napi->state |= LKPI_NAPI_ENABLED;
}

void napi_disable(struct napi_struct *napi)
{
	napi_unqueue(napi);
	napi->state &= ~(LKPI_NAPI_ENABLED | LKPI_NAPI_SCHEDULED);
}

bool napi_schedule_prep(struct napi_struct *napi)
{
	if (!(napi->state & LKPI_NAPI_ENABLED) || (napi->state & LKPI_NAPI_SCHEDULED))
		return false;
	napi->state |= LKPI_NAPI_SCHEDULED;
	return true;
}

void __napi_schedule(struct napi_struct *napi)
{
	if (!napi_queued(napi))
		list_add_tail(&napi->poll_list, &scheduled);
}

bool napi_schedule(struct napi_struct *napi)
{
	if (!napi_schedule_prep(napi))
		return false;
	__napi_schedule(napi);
	return true;
}

bool napi_complete_done(struct napi_struct *napi, int work_done)
{
	(void)work_done;
	napi_unqueue(napi);
	napi->state &= ~LKPI_NAPI_SCHEDULED;
	return true;
}

void napi_synchronize(const struct napi_struct *napi)
{
	(void)napi;
}

void napi_gro_receive(struct napi_struct *napi, struct sk_buff *skb)
{
	(void)napi;
	kfree_skb(skb);
}

void lkpi_napi_run(void)
{
	struct list_head batch = LIST_HEAD_INIT(batch);
	struct napi_struct *napi;

	while (!list_empty(&scheduled)) {
		napi = list_first_entry(&scheduled, struct napi_struct, poll_list);
		list_move_tail(&napi->poll_list, &batch);
	}
	while (!list_empty(&batch)) {
		napi = list_first_entry(&batch, struct napi_struct, poll_list);
		list_del_init(&napi->poll_list);
		if (!napi->poll || !(napi->state & LKPI_NAPI_SCHEDULED))
			continue;
		if (napi->poll(napi, napi->weight) >= napi->weight)
			__napi_schedule(napi);
	}
}

struct net_device *alloc_netdev_dummy(int sizeof_priv)
{
	struct net_device *dev;
	size_t head = ALIGN(sizeof(*dev), NETDEV_ALIGN);

	if (sizeof_priv < 0)
		return NULL;
	dev = kzalloc(head + sizeof_priv, GFP_KERNEL);
	if (!dev)
		return NULL;
	dev->priv = (u8 *)dev + head;
	dev->mtu = ETH_DATA_LEN;
	return dev;
}

void free_netdev(struct net_device *dev)
{
	kfree(dev);
}

void *netdev_priv(const struct net_device *dev)
{
	return dev->priv;
}

void synchronize_net(void)
{
	lkpi_napi_run();
}

int net_ratelimit(void)
{
	static unsigned long window_start;
	static unsigned int sent;

	if (time_after(jiffies, window_start + LKPI_RATELIMIT_WINDOW)) {
		window_start = jiffies;
		sent = 0;
	}
	return sent++ < LKPI_RATELIMIT_BURST;
}

void netdev_rss_key_fill(void *buffer, size_t len)
{
	get_random_bytes(buffer, len);
}
