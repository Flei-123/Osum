#include "wifi.h"

struct lkpi_wifi_hw *lkpi_wifi_of(const struct ieee80211_hw *hw)
{
	return (struct lkpi_wifi_hw *)hw;
}

struct lkpi_wifi_hw *lkpi_wifi_of_vif(const struct ieee80211_vif *vif)
{
	return container_of(vif, struct lkpi_wifi_hw, vif.vif);
}

struct lkpi_wifi_hw *lkpi_wifi_of_sta(const struct ieee80211_sta *sta)
{
	return container_of(sta, struct lkpi_wifi_hw, sta.sta);
}

struct ieee80211_hw *ieee80211_alloc_hw_nm(size_t priv_data_len, const struct ieee80211_ops *ops, const char *requested_name)
{
	struct lkpi_wifi_hw *w;

	if (!ops || priv_data_len > LKPI_WIFI_PRIV_MAX)
		return NULL;
	w = kzalloc(sizeof(*w), GFP_KERNEL);
	if (!w)
		return NULL;
	w->used = 1;
	w->ops = ops;
	w->wiphy = kzalloc(sizeof(*w->wiphy) + sizeof(struct ieee80211_hw *), GFP_KERNEL);
	if (!w->wiphy) {
		kfree(w);
		return NULL;
	}
	*(struct ieee80211_hw **)w->wiphy->priv = &w->hw;
	w->hw.wiphy = w->wiphy;
	w->wdev.wiphy = w->wiphy;
	w->hw.priv = w->priv;
	w->hw.queues = 1;
	return &w->hw;
}

void ieee80211_free_hw(struct ieee80211_hw *hw)
{
	if (!hw)
		return;
	kfree(lkpi_wifi_of(hw)->wiphy);
	kfree(lkpi_wifi_of(hw));
}

int ieee80211_register_hw(struct ieee80211_hw *hw)
{
	struct lkpi_wifi_hw *w = lkpi_wifi_of(hw);

	if (w->state.registered)
		return LKPI80211_EINVAL;
	if (hw->vif_data_size > LKPI_WIFI_OBJ_PRIV_MAX || hw->sta_data_size > LKPI_WIFI_OBJ_PRIV_MAX ||
	    hw->chanctx_data_size > LKPI_WIFI_OBJ_PRIV_MAX)
		return LKPI80211_EINVAL;
	if (!w->ops->start || !w->ops->stop || !w->ops->add_interface || !w->ops->remove_interface ||
	    !w->ops->sta_state || !w->ops->tx)
		return LKPI80211_EINVAL;
	w->state.registered = 1;
	return 0;
}

void ieee80211_unregister_hw(struct ieee80211_hw *hw)
{
	lkpi_wifi_of(hw)->state.registered = 0;
}

void lkpi80211_set_upcalls(struct ieee80211_hw *hw, const struct lkpi80211_upcalls *upcalls, void *ctx)
{
	struct lkpi_wifi_hw *w = lkpi_wifi_of(hw);

	w->upcalls = *upcalls;
	w->upcall_ctx = ctx;
}

void lkpi80211_state_get(const struct ieee80211_hw *hw, struct lkpi80211_state *out)
{
	*out = lkpi_wifi_of(hw)->state;
}

int lkpi80211_tx(struct ieee80211_hw *hw, struct sk_buff *skb)
{
	struct lkpi_wifi_hw *w = lkpi_wifi_of(hw);
	struct ieee80211_tx_control control = { 0 };

	if (!w->state.started)
		return LKPI80211_EPROTO;
	if (w->state.sta_state >= IEEE80211_STA_AUTH)
		control.sta = &w->sta.sta;
	w->ops->tx(hw, &control, skb);
	return 0;
}
