#include "wifi.h"

static struct ieee80211_hw *registered_hw;

struct ieee80211_hw *lkpi_wifi_registered_hw(void)
{
	return registered_hw;
}

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
	w->vif.vif.bss_conf.vif = &w->vif.vif;
	w->vif.vif.link_conf[0] = &w->vif.vif.bss_conf;
	w->sta.sta.link[0] = &w->sta.sta.deflink;
	w->sta.sta.deflink.sta = &w->sta.sta;
	return &w->hw;
}

void ieee80211_free_hw(struct ieee80211_hw *hw)
{
	if (!hw)
		return;
	lkpi_txq_release(lkpi_wifi_of(hw));
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
	if (lkpi_txq_attach(w))
		return LKPI80211_EINVAL;
	w->state.registered = 1;
	if (!registered_hw)
		registered_hw = hw;
	return 0;
}

void ieee80211_unregister_hw(struct ieee80211_hw *hw)
{
	lkpi_wifi_of(hw)->state.registered = 0;
	if (registered_hw == hw)
		registered_hw = NULL;
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
	struct ieee80211_tx_info *info = IEEE80211_SKB_CB(skb);

	if (!w->state.started)
		return LKPI80211_EPROTO;
	memset(info, 0, sizeof(*info));
	info->band = w->join_band;
	info->control.vif = &w->vif.vif;
	if (w->vif.vif.type == NL80211_IFTYPE_STATION && w->state.sta_state >= IEEE80211_STA_NONE &&
	    lkpi_txq_enqueue(w, skb))
		return 0;
	if (w->state.sta_state >= IEEE80211_STA_NONE)
		control.sta = &w->sta.sta;
	w->ops->tx(hw, &control, skb);
	return 0;
}
