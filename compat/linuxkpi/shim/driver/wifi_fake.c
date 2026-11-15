#include "../src/lkpi.h"
#include <osum/lkpi80211.h>

#define FAKE_FRAME_MAX 1600
#define FAKE_ADDR1_OFFSET 4
#define FAKE_ADDR1_END 10

struct fake_priv {
	u8 bssid[ETH_ALEN];
	u32 filtered;
	u32 scan_pending;
	u32 started;
	u32 keys;
	u32 tx_frames;
};

static struct ieee80211_hw *fake_hw;

static void fake_deliver(struct ieee80211_hw *hw, u64 len, u64 frame)
{
	struct sk_buff *skb;

	if (!len || len > FAKE_FRAME_MAX)
		return;
	skb = alloc_skb(len, GFP_KERNEL);
	if (!skb)
		return;
	memcpy(skb_put(skb, len), (const void *)frame, len);
	ieee80211_rx_napi(hw, NULL, skb, NULL);
}

static bool fake_addressed_to_bssid(struct fake_priv *priv, const struct sk_buff *skb)
{
	return skb->len >= FAKE_ADDR1_END && !memcmp(skb->data + FAKE_ADDR1_OFFSET, priv->bssid, ETH_ALEN);
}

static void fake_tx(struct ieee80211_hw *hw, struct ieee80211_tx_control *control, struct sk_buff *skb)
{
	struct fake_priv *priv = hw->priv;
	u8 buf[FAKE_FRAME_MAX];
	u64 count = k_wifi_hw(OSUM_WIFI_HW_TX, (u64)skb->data, skb->len, 0);
	u64 i;

	if (!fake_addressed_to_bssid(priv, skb)) {
		priv->filtered++;
		ieee80211_free_txskb(hw, skb);
		return;
	}
	priv->tx_frames++;
	for (i = 0; i < count; i++) {
		u64 len = k_wifi_hw(OSUM_WIFI_HW_RESP, i, (u64)buf, sizeof(buf));

		fake_deliver(hw, len, (u64)buf);
	}
	ieee80211_tx_status_skb(hw, skb);
}

static int fake_start(struct ieee80211_hw *hw)
{
	struct fake_priv *priv = hw->priv;

	k_wifi_hw(OSUM_WIFI_HW_RESET, 1, 0, 0);
	priv->started = 1;
	return 0;
}

static void fake_stop(struct ieee80211_hw *hw, bool suspend)
{
	struct fake_priv *priv = hw->priv;

	priv->started = 0;
	priv->scan_pending = 0;
}

static int fake_add_interface(struct ieee80211_hw *hw, struct ieee80211_vif *vif)
{
	return 0;
}

static void fake_remove_interface(struct ieee80211_hw *hw, struct ieee80211_vif *vif)
{
}

static int fake_hw_scan(struct ieee80211_hw *hw, struct ieee80211_vif *vif, struct ieee80211_scan_request *req)
{
	struct fake_priv *priv = hw->priv;

	priv->scan_pending = 1;
	return 0;
}

static void fake_cancel_hw_scan(struct ieee80211_hw *hw, struct ieee80211_vif *vif)
{
	struct fake_priv *priv = hw->priv;

	priv->scan_pending = 0;
}

static void fake_bss_info_changed(struct ieee80211_hw *hw, struct ieee80211_vif *vif,
				  struct ieee80211_bss_conf *info, u64 changed)
{
	struct fake_priv *priv = hw->priv;

	if (changed & BSS_CHANGED_BSSID)
		memcpy(priv->bssid, info->bssid, ETH_ALEN);
}

static int fake_sta_state(struct ieee80211_hw *hw, struct ieee80211_vif *vif, struct ieee80211_sta *sta,
			  enum ieee80211_sta_state old_state, enum ieee80211_sta_state new_state)
{
	struct fake_priv *priv = hw->priv;

	if (new_state == IEEE80211_STA_NONE && memcmp(sta->addr, priv->bssid, ETH_ALEN))
		return -22;
	return 0;
}

static int fake_set_key(struct ieee80211_hw *hw, enum set_key_cmd cmd, struct ieee80211_vif *vif,
			struct ieee80211_sta *sta, struct ieee80211_key_conf *key)
{
	struct fake_priv *priv = hw->priv;

	if (cmd == SET_KEY)
		priv->keys++;
	else if (priv->keys)
		priv->keys--;
	return 0;
}

static const struct ieee80211_ops fake_ops = {
	.tx = fake_tx,
	.start = fake_start,
	.stop = fake_stop,
	.add_interface = fake_add_interface,
	.remove_interface = fake_remove_interface,
	.hw_scan = fake_hw_scan,
	.cancel_hw_scan = fake_cancel_hw_scan,
	.sta_state = fake_sta_state,
	.bss_info_changed = fake_bss_info_changed,
	.set_key = fake_set_key,
};

static void fake_poll(struct ieee80211_hw *hw)
{
	struct fake_priv *priv = hw->priv;
	struct cfg80211_scan_info info = { .aborted = false };
	u8 buf[FAKE_FRAME_MAX];
	u64 nets, i;

	if (!priv->scan_pending)
		return;
	priv->scan_pending = 0;
	nets = k_wifi_hw(OSUM_WIFI_HW_NETS, 0, 0, 0);
	for (i = 0; i < nets; i++) {
		u64 len = k_wifi_hw(OSUM_WIFI_HW_BEACON, i, (u64)buf, 0);

		fake_deliver(hw, len, (u64)buf);
	}
	ieee80211_scan_completed(hw, &info);
}

int lkpi_wifi_fake_init(void)
{
	int rc;

	fake_hw = ieee80211_alloc_hw(sizeof(struct fake_priv), &fake_ops);
	if (!fake_hw)
		return -12;
	rc = ieee80211_register_hw(fake_hw);
	if (!rc)
		rc = lkpi_wifi_glue_attach(fake_hw, fake_poll);
	if (rc) {
		ieee80211_free_hw(fake_hw);
		fake_hw = NULL;
		return rc;
	}
	_printk("lkpi: wifi fake radio registered\n");
	return 0;
}

void lkpi_wifi_fake_exit(void)
{
	if (!fake_hw)
		return;
	lkpi_wifi_glue_detach();
	ieee80211_unregister_hw(fake_hw);
	ieee80211_free_hw(fake_hw);
	fake_hw = NULL;
}
