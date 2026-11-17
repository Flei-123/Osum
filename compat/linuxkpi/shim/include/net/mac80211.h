#ifndef LKPI_NET_MAC80211_H
#define LKPI_NET_MAC80211_H

#include <linux/types.h>
#include <linux/kernel.h>
#include <linux/skbuff.h>

#define ETH_ALEN 6
#define IEEE80211_NUM_ACS 4
#define IEEE80211_KEY_FLAG_PAIRWISE BIT(3)
#define BSS_CHANGED_ASSOC BIT(0)
#define BSS_CHANGED_BSSID BIT(7)
#define BSS_CHANGED_QOS BIT(9)

enum ieee80211_sta_state {
	IEEE80211_STA_NOTEXIST,
	IEEE80211_STA_NONE,
	IEEE80211_STA_AUTH,
	IEEE80211_STA_ASSOC,
	IEEE80211_STA_AUTHORIZED,
};

enum set_key_cmd {
	SET_KEY,
	DISABLE_KEY,
};

struct ieee80211_hw;
struct ieee80211_vif;
struct ieee80211_sta;

struct ieee80211_key_conf {
	u32 cipher;
	u32 flags;
	u8 keyidx;
	u8 keylen;
	u8 key[32];
};

struct ieee80211_chanctx_conf {
	u32 freq;
	u8 drv_priv[] __attribute__((aligned(8)));
};

struct ieee80211_bss_conf {
	u8 bssid[ETH_ALEN];
	bool qos;
	bool assoc;
	u16 aid;
};

struct ieee80211_vif {
	u8 addr[ETH_ALEN];
	struct ieee80211_bss_conf bss_conf;
	u8 drv_priv[] __attribute__((aligned(8)));
};

struct ieee80211_sta {
	u8 addr[ETH_ALEN];
	u8 drv_priv[] __attribute__((aligned(8)));
};

struct ieee80211_tx_queue_params {
	u16 txop;
	u16 cw_min;
	u16 cw_max;
	u8 aifs;
};

struct ieee80211_tx_control {
	struct ieee80211_sta *sta;
};

struct ieee80211_scan_request {
	u32 n_channels;
};

struct cfg80211_scan_info {
	bool aborted;
};

struct ieee80211_prep_tx_info {
	u16 duration;
	bool success;
};

struct ieee80211_ops {
	void (*tx)(struct ieee80211_hw *hw, struct ieee80211_tx_control *control, struct sk_buff *skb);
	int (*start)(struct ieee80211_hw *hw);
	void (*stop)(struct ieee80211_hw *hw, bool suspend);
	int (*add_interface)(struct ieee80211_hw *hw, struct ieee80211_vif *vif);
	void (*remove_interface)(struct ieee80211_hw *hw, struct ieee80211_vif *vif);
	int (*hw_scan)(struct ieee80211_hw *hw, struct ieee80211_vif *vif, struct ieee80211_scan_request *req);
	void (*cancel_hw_scan)(struct ieee80211_hw *hw, struct ieee80211_vif *vif);
	int (*add_chanctx)(struct ieee80211_hw *hw, struct ieee80211_chanctx_conf *ctx);
	void (*remove_chanctx)(struct ieee80211_hw *hw, struct ieee80211_chanctx_conf *ctx);
	int (*assign_vif_chanctx)(struct ieee80211_hw *hw, struct ieee80211_vif *vif,
				  struct ieee80211_bss_conf *link_conf, struct ieee80211_chanctx_conf *ctx);
	void (*unassign_vif_chanctx)(struct ieee80211_hw *hw, struct ieee80211_vif *vif,
				     struct ieee80211_bss_conf *link_conf, struct ieee80211_chanctx_conf *ctx);
	int (*sta_state)(struct ieee80211_hw *hw, struct ieee80211_vif *vif, struct ieee80211_sta *sta,
			 enum ieee80211_sta_state old_state, enum ieee80211_sta_state new_state);
	void (*mgd_prepare_tx)(struct ieee80211_hw *hw, struct ieee80211_vif *vif, struct ieee80211_prep_tx_info *info);
	void (*mgd_complete_tx)(struct ieee80211_hw *hw, struct ieee80211_vif *vif, struct ieee80211_prep_tx_info *info);
	void (*bss_info_changed)(struct ieee80211_hw *hw, struct ieee80211_vif *vif,
				 struct ieee80211_bss_conf *info, u64 changed);
	void (*vif_cfg_changed)(struct ieee80211_hw *hw, struct ieee80211_vif *vif, u64 changed);
	int (*conf_tx)(struct ieee80211_hw *hw, struct ieee80211_vif *vif, unsigned int link_id, u16 ac,
		       const struct ieee80211_tx_queue_params *params);
	int (*set_key)(struct ieee80211_hw *hw, enum set_key_cmd cmd, struct ieee80211_vif *vif,
		       struct ieee80211_sta *sta, struct ieee80211_key_conf *key);
	void (*flush)(struct ieee80211_hw *hw, struct ieee80211_vif *vif, u32 queues, bool drop);
};

struct ieee80211_hw {
	const struct ieee80211_ops *ops;
	void *priv;
	size_t vif_data_size;
	size_t sta_data_size;
	size_t chanctx_data_size;
	u16 queues;
};

struct ieee80211_hw *ieee80211_alloc_hw(size_t priv_data_len, const struct ieee80211_ops *ops);
void ieee80211_free_hw(struct ieee80211_hw *hw);
int ieee80211_register_hw(struct ieee80211_hw *hw);
void ieee80211_unregister_hw(struct ieee80211_hw *hw);
void ieee80211_rx_napi(struct ieee80211_hw *hw, struct ieee80211_sta *sta, struct sk_buff *skb, void *napi);
void ieee80211_tx_status_skb(struct ieee80211_hw *hw, struct sk_buff *skb);
void ieee80211_free_txskb(struct ieee80211_hw *hw, struct sk_buff *skb);
void ieee80211_scan_completed(struct ieee80211_hw *hw, struct cfg80211_scan_info *info);
void ieee80211_beacon_loss(struct ieee80211_vif *vif);
void ieee80211_connection_loss(struct ieee80211_vif *vif);
void ieee80211_restart_hw(struct ieee80211_hw *hw);

#endif
