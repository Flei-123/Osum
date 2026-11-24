#include "wifi.h"
#include <osum/osum_if.h>

#define GLUE_RX_MAX 64
#define GLUE_SCAN_IDLE 0
#define GLUE_SCAN_RUNNING 1
#define GLUE_SCAN_DONE 2
#define GLUE_SCAN_ABORTED 3
#define GLUE_RSSI_DEFAULT (-55LL)
#define GLUE_TAG 0x6c6b7769ULL

struct glue {
	struct ieee80211_hw *hw;
	struct sk_buff_head rx;
	void (*poll)(struct ieee80211_hw *hw);
	u32 scan;
	u32 rx_dropped;
	u32 tx_failed;
	u32 losses;
	u32 restarts;
};

static struct glue *glue;

static void up_rx(void *ctx, struct sk_buff *skb)
{
	struct glue *g = ctx;

	if (skb_queue_len(&g->rx) >= GLUE_RX_MAX) {
		g->rx_dropped++;
		kfree_skb(skb);
		return;
	}
	__skb_queue_tail(&g->rx, skb);
}

static void up_tx_status(void *ctx, struct sk_buff *skb, bool acked)
{
	struct glue *g = ctx;

	if (!acked)
		g->tx_failed++;
	kfree_skb(skb);
}

static void up_scan_done(void *ctx, bool aborted)
{
	struct glue *g = ctx;

	g->scan = aborted ? GLUE_SCAN_ABORTED : GLUE_SCAN_DONE;
}

static void up_loss(void *ctx)
{
	((struct glue *)ctx)->losses++;
}

static void up_restart(void *ctx)
{
	((struct glue *)ctx)->restarts++;
}

static const struct lkpi80211_upcalls upcalls = {
	.rx = up_rx,
	.tx_status = up_tx_status,
	.scan_done = up_scan_done,
	.beacon_loss = up_loss,
	.connection_loss = up_loss,
	.restart = up_restart,
};

static long long glue_tx(u64 frame, u64 len)
{
	struct sk_buff *skb;
	int rc;

	if (!glue || !len)
		return -1;
	skb = alloc_skb(len, GFP_KERNEL);
	if (!skb)
		return -1;
	memcpy(skb_put(skb, len), (const void *)frame, len);
	rc = lkpi80211_tx(glue->hw, skb);
	if (rc) {
		kfree_skb(skb);
		return rc;
	}
	return len;
}

static long long glue_rx_take(u64 dst, u64 room)
{
	struct sk_buff *skb;
	long long len;

	if (!glue)
		return -1;
	lkpi_time_tick();
	lkpi_irq_poll();
	lkpi_napi_run();
	if (!skb_queue_len(&glue->rx) && glue->poll)
		glue->poll(glue->hw);
	skb = __skb_dequeue(&glue->rx);
	if (!skb)
		return 0;
	len = skb->len;
	if ((u64)len > room) {
		glue->rx_dropped++;
		kfree_skb(skb);
		return 0;
	}
	memcpy((void *)dst, skb->data, len);
	kfree_skb(skb);
	return len;
}

static long long glue_set_channel(u64 channel, u64 band)
{
	(void)channel;
	(void)band;
	return glue ? 0 : -1;
}

static long long glue_op(u64 op, u64 arg)
{
	struct lkpi_wifi_hw *w;
	int rc;

	if (!glue)
		return LKPI80211_EPROTO;
	w = lkpi_wifi_of(glue->hw);
	rc = lkpi_wifi_op(w, op, arg);
	if (rc) {
		_printk("lkpi: wifi op %u failed (%d)\n", (unsigned int)op, rc);
		return rc;
	}
	if (op == MACPLAN_OP_HW_SCAN)
		glue->scan = GLUE_SCAN_RUNNING;
	if (op == MACPLAN_OP_CANCEL_HW_SCAN)
		glue->scan = GLUE_SCAN_IDLE;
	return 0;
}

static long long glue_bssid_set(u64 addr)
{
	struct lkpi_wifi_hw *w;

	if (!glue)
		return -1;
	w = lkpi_wifi_of(glue->hw);
	memcpy(w->bssid, (const void *)addr, ETH_ALEN);
	w->vif.vif.bss_conf.bssid = w->bssid;
	memcpy(w->sta.sta.addr, (const void *)addr, ETH_ALEN);
	return 0;
}

static long long glue_addr_set(u64 addr)
{
	if (!glue)
		return -1;
	memcpy(lkpi_wifi_of(glue->hw)->vif.vif.addr, (const void *)addr, ETH_ALEN);
	return 0;
}

static long long glue_aid_set(u64 aid)
{
	if (!glue)
		return -1;
	lkpi_wifi_of(glue->hw)->vif.vif.cfg.aid = aid;
	return 0;
}

static long long glue_scan_state(void)
{
	return glue ? glue->scan : GLUE_SCAN_IDLE;
}

static long long glue_rssi(void)
{
	return GLUE_RSSI_DEFAULT;
}

static const struct osum_wifi_ops table = {
	.ready = 1,
	.tx = (u64)glue_tx,
	.rx_take = (u64)glue_rx_take,
	.set_channel = (u64)glue_set_channel,
	.op = (u64)glue_op,
	.bssid_set = (u64)glue_bssid_set,
	.addr_set = (u64)glue_addr_set,
	.aid_set = (u64)glue_aid_set,
	.scan_state = (u64)glue_scan_state,
	.rssi = (u64)glue_rssi,
	.tag = GLUE_TAG,
};

int lkpi_wifi_glue_attach(struct ieee80211_hw *hw, void (*poll)(struct ieee80211_hw *hw))
{
	if (glue)
		return LKPI80211_EINVAL;
	glue = kzalloc(sizeof(*glue), GFP_KERNEL);
	if (!glue)
		return LKPI80211_EINVAL;
	glue->hw = hw;
	glue->poll = poll;
	skb_queue_head_init(&glue->rx);
	lkpi80211_set_upcalls(hw, &upcalls, glue);
	if (!k_wifi_register(&table)) {
		kfree(glue);
		glue = NULL;
		return LKPI80211_EINVAL;
	}
	return 0;
}

void lkpi_wifi_glue_detach(void)
{
	struct sk_buff *skb;

	if (!glue)
		return;
	k_wifi_unregister(GLUE_TAG);
	while ((skb = __skb_dequeue(&glue->rx)))
		kfree_skb(skb);
	kfree(glue);
	glue = NULL;
}

int lkpi_wifi_glue_attach_when_ready(unsigned int rounds)
{
	struct ieee80211_hw *hw;

	while (rounds--) {
		hw = lkpi_wifi_registered_hw();
		if (hw)
			return lkpi_wifi_glue_attach(hw, NULL);
		if (lkpi_driver_released())
			return LKPI80211_EPROTO;
		lkpi_time_tick();
		lkpi_irq_poll();
		lkpi_napi_run();
	}
	return LKPI80211_EPROTO;
}
