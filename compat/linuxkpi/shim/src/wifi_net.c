#include "wifi.h"

#define LKPI_NAPI_DEFAULT_WEIGHT 64
#define LKPI_NAPI_ENABLED 1UL
#define LKPI_NAPI_SCHEDULED 2UL

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
	napi->poll = NULL;
	napi->state = 0;
}

void napi_enable(struct napi_struct *napi)
{
	napi->state |= LKPI_NAPI_ENABLED;
}

void napi_disable(struct napi_struct *napi)
{
	napi->state &= ~(LKPI_NAPI_ENABLED | LKPI_NAPI_SCHEDULED);
}

bool napi_schedule(struct napi_struct *napi)
{
	if (!(napi->state & LKPI_NAPI_ENABLED) || (napi->state & LKPI_NAPI_SCHEDULED))
		return false;
	napi->state |= LKPI_NAPI_SCHEDULED;
	return true;
}

bool napi_complete_done(struct napi_struct *napi, int work_done)
{
	(void)work_done;
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
