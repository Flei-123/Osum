#ifndef LKPI_WIFI_H
#define LKPI_WIFI_H

#include <linux/kernel.h>
#include <osum/lkpi80211.h>
#include <osum/macplan_ops.h>

#define LKPI_WIFI_PRIV_MAX 8192
#define LKPI_WIFI_OBJ_PRIV_MAX 256

struct lkpi_wifi_hw {
	struct ieee80211_hw hw;
	const struct ieee80211_ops *ops;
	u8 bssid[ETH_ALEN];
	struct lkpi80211_state state;
	struct lkpi80211_upcalls upcalls;
	void *upcall_ctx;
	u8 used;
	u8 priv[LKPI_WIFI_PRIV_MAX] __attribute__((aligned(16)));
	struct {
		struct ieee80211_vif vif;
		u8 priv[LKPI_WIFI_OBJ_PRIV_MAX];
	} vif __attribute__((aligned(16)));
	struct {
		struct ieee80211_sta sta;
		u8 priv[LKPI_WIFI_OBJ_PRIV_MAX];
	} sta __attribute__((aligned(16)));
	struct {
		struct ieee80211_chanctx_conf ctx;
		u8 priv[LKPI_WIFI_OBJ_PRIV_MAX];
	} chanctx __attribute__((aligned(16)));
	struct ieee80211_key_conf pairwise;
	struct ieee80211_key_conf group;
};

struct lkpi_wifi_hw *lkpi_wifi_of(const struct ieee80211_hw *hw);
int lkpi_wifi_op(struct lkpi_wifi_hw *w, u32 op, u64 arg);
void lkpi_timers_run(unsigned long now);
void lkpi_work_run(void);

#endif
