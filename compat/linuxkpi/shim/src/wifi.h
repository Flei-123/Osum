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
	struct wiphy *wiphy;
	struct wireless_dev wdev;
	u8 hw_blocked;
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
struct lkpi_wifi_hw *lkpi_wifi_of_vif(const struct ieee80211_vif *vif);
struct lkpi_wifi_hw *lkpi_wifi_of_sta(const struct ieee80211_sta *sta);
int lkpi_wifi_op(struct lkpi_wifi_hw *w, u32 op, u64 arg);
void lkpi_timers_run(unsigned long now);
void lkpi_work_run(void);
#define LKPI_NS_PER_JIFFY (NSEC_PER_SEC / HZ)
#define LKPI_WAIT_BUDGET_TICKS (30UL * HZ)
void lkpi_time_advance_ns(u64 ns, bool sleeping);
void lkpi_time_sleep_ns(u64 ns);
void lkpi_time_tick(void);
u64 lkpi_time_ns(void);
void lkpi_napi_run(void);
void lkpi_irq_poll(void);
int lkpi_firmware_register(const char *name, const void *data, size_t size);
void lkpi_firmware_clear(void);
void *lkpi_devres_alloc(struct device *dev, size_t size, void (*release)(void *payload));
void lkpi_devres_release(struct device *dev);

#endif
