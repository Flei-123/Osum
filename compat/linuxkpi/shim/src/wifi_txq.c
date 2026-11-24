#include "wifi.h"

#define TXQ_COUNT (IEEE80211_NUM_TIDS + 1)
#define MGMT_TID IEEE80211_NUM_TIDS
#define QOS_TID_MASK 7

static const u8 ac_of_tid[QOS_TID_MASK + 1] = {
	IEEE80211_AC_BE, IEEE80211_AC_BK, IEEE80211_AC_BK, IEEE80211_AC_BE,
	IEEE80211_AC_VI, IEEE80211_AC_VI, IEEE80211_AC_VO, IEEE80211_AC_VO,
};

void lkpi_txq_release(struct lkpi_wifi_hw *w)
{
	int i;

	for (i = 0; i < TXQ_COUNT; i++) {
		skb_queue_purge(&w->txq_queue[i]);
		kfree(w->sta.sta.txq[i]);
		w->sta.sta.txq[i] = NULL;
	}
}

int lkpi_txq_attach(struct lkpi_wifi_hw *w)
{
	size_t size = sizeof(struct ieee80211_txq) + w->hw.txq_data_size;
	int i;

	for (i = 0; i < TXQ_COUNT; i++) {
		struct ieee80211_txq *txq = kzalloc(size, GFP_KERNEL);

		if (!txq) {
			lkpi_txq_release(w);
			return LKPI80211_EINVAL;
		}
		txq->vif = &w->vif.vif;
		txq->sta = &w->sta.sta;
		txq->tid = i;
		txq->ac = i == MGMT_TID ? IEEE80211_AC_VO : ac_of_tid[i & QOS_TID_MASK];
		skb_queue_head_init(&w->txq_queue[i]);
		w->sta.sta.txq[i] = txq;
	}
	return 0;
}

static int txq_index_of(struct sk_buff *skb)
{
	struct ieee80211_hdr *hdr = (struct ieee80211_hdr *)skb->data;

	if (ieee80211_is_mgmt(hdr->frame_control))
		return MGMT_TID;
	if (ieee80211_is_data_qos(hdr->frame_control))
		return *ieee80211_get_qos_ctl(hdr) & QOS_TID_MASK;
	if (ieee80211_is_data(hdr->frame_control))
		return 0;
	return -1;
}

bool lkpi_txq_enqueue(struct lkpi_wifi_hw *w, struct sk_buff *skb)
{
	int index;

	if (!w->ops->wake_tx_queue || !w->sta.sta.txq[0] || skb->len < sizeof(struct ieee80211_hdr_3addr))
		return false;
	index = txq_index_of(skb);
	if (index < 0)
		return false;
	__skb_queue_tail(&w->txq_queue[index], skb);
	w->ops->wake_tx_queue(&w->hw, w->sta.sta.txq[index]);
	return true;
}

struct sk_buff *ieee80211_tx_dequeue(struct ieee80211_hw *hw, struct ieee80211_txq *txq)
{
	return __skb_dequeue(&lkpi_wifi_of(hw)->txq_queue[txq->tid]);
}
