#include "wifi.h"

static struct lkpi_wifi_hw *owner(struct ieee80211_vif *vif)
{
	return (struct lkpi_wifi_hw *)((u8 *)vif - __builtin_offsetof(struct lkpi_wifi_hw, vif));
}

void ieee80211_rx_napi(struct ieee80211_hw *hw, struct ieee80211_sta *sta, struct sk_buff *skb, void *napi)
{
	struct lkpi_wifi_hw *w = lkpi_wifi_of(hw);

	(void)sta;
	(void)napi;
	if (!w->upcalls.rx || !w->state.started) {
		kfree_skb(skb);
		return;
	}
	w->upcalls.rx(w->upcall_ctx, skb);
}

void ieee80211_tx_status_skb(struct ieee80211_hw *hw, struct sk_buff *skb)
{
	struct lkpi_wifi_hw *w = lkpi_wifi_of(hw);

	if (!w->upcalls.tx_status) {
		kfree_skb(skb);
		return;
	}
	w->upcalls.tx_status(w->upcall_ctx, skb, true);
}

void ieee80211_free_txskb(struct ieee80211_hw *hw, struct sk_buff *skb)
{
	struct lkpi_wifi_hw *w = lkpi_wifi_of(hw);

	if (w->upcalls.tx_status)
		w->upcalls.tx_status(w->upcall_ctx, skb, false);
	else
		kfree_skb(skb);
}

void ieee80211_scan_completed(struct ieee80211_hw *hw, struct cfg80211_scan_info *info)
{
	struct lkpi_wifi_hw *w = lkpi_wifi_of(hw);

	if (!w->state.scanning)
		return;
	w->state.scanning = 0;
	if (w->upcalls.scan_done)
		w->upcalls.scan_done(w->upcall_ctx, info->aborted);
}

void ieee80211_beacon_loss(struct ieee80211_vif *vif)
{
	struct lkpi_wifi_hw *w = owner(vif);

	if (w->upcalls.beacon_loss && w->state.sta_state >= IEEE80211_STA_ASSOC)
		w->upcalls.beacon_loss(w->upcall_ctx);
}

void ieee80211_connection_loss(struct ieee80211_vif *vif)
{
	struct lkpi_wifi_hw *w = owner(vif);

	if (w->upcalls.connection_loss && w->state.sta_state >= IEEE80211_STA_AUTH)
		w->upcalls.connection_loss(w->upcall_ctx);
}

void ieee80211_restart_hw(struct ieee80211_hw *hw)
{
	struct lkpi_wifi_hw *w = lkpi_wifi_of(hw);

	if (w->upcalls.restart)
		w->upcalls.restart(w->upcall_ctx);
}
