#ifndef OSUM_LKPI80211_H
#define OSUM_LKPI80211_H

#include <net/mac80211.h>

#define LKPI80211_ENOSYS (-38)
#define LKPI80211_EINVAL (-22)
#define LKPI80211_EPROTO (-71)

struct lkpi80211_upcalls {
	void (*rx)(void *ctx, struct sk_buff *skb);
	void (*tx_status)(void *ctx, struct sk_buff *skb, bool acked);
	void (*scan_done)(void *ctx, bool aborted);
	void (*beacon_loss)(void *ctx);
	void (*connection_loss)(void *ctx);
	void (*restart)(void *ctx);
};

struct lkpi80211_state {
	u32 sta_state;
	u32 keys;
	u8 started;
	u8 iface;
	u8 chanctx;
	u8 assigned;
	u8 scanning;
	u8 registered;
};

void lkpi80211_set_upcalls(struct ieee80211_hw *hw, const struct lkpi80211_upcalls *upcalls, void *ctx);
int lkpi80211_apply(struct ieee80211_hw *hw, const u64 *ops, u32 count);
int lkpi80211_tx(struct ieee80211_hw *hw, struct sk_buff *skb);
void lkpi80211_state_get(const struct ieee80211_hw *hw, struct lkpi80211_state *out);
u32 lkpi_skb_free_count(void);
u32 lkpi_skb_pool_size(void);
u32 lkpi_skb_error_count(void);

#endif
