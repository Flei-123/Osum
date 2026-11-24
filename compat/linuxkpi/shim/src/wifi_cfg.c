#include "wifi.h"
#include <linux/ieee80211.h>

#define KHZ_PER_MHZ 1000U
#define WIPHY_WORK_BUDGET 64U

const u8 rfc1042_header[6] = { 0xaa, 0xaa, 0x03, 0x00, 0x00, 0x00 };

static struct list_head wiphy_pending = LIST_HEAD_INIT(wiphy_pending);
static struct wiphy *wiphy_active;
static struct work_struct wiphy_runner;
static bool runner_ready;

static void wiphy_run(struct work_struct *work)
{
	unsigned int budget = WIPHY_WORK_BUDGET;

	(void)work;
	while (!list_empty(&wiphy_pending) && budget--) {
		struct wiphy_work *item = list_first_entry(&wiphy_pending, struct wiphy_work, entry);

		list_del_init(&item->entry);
		item->func(wiphy_active, item);
	}
}

static bool work_queued(const struct wiphy_work *work)
{
	return work->entry.next && !list_empty(&work->entry);
}

void wiphy_work_queue(struct wiphy *wiphy, struct wiphy_work *work)
{
	if (!runner_ready) {
		INIT_WORK(&wiphy_runner, wiphy_run);
		runner_ready = true;
	}
	wiphy_active = wiphy;
	if (!work_queued(work))
		list_add_tail(&work->entry, &wiphy_pending);
	schedule_work(&wiphy_runner);
}

void wiphy_work_cancel(struct wiphy *wiphy, struct wiphy_work *work)
{
	(void)wiphy;
	if (work_queued(work))
		list_del_init(&work->entry);
}

void wiphy_work_flush(struct wiphy *wiphy, struct wiphy_work *work)
{
	if (!work_queued(work))
		return;
	list_del_init(&work->entry);
	work->func(wiphy, work);
}

void wiphy_delayed_work_timer(struct timer_list *timer)
{
	struct wiphy_delayed_work *dwork = container_of(timer, struct wiphy_delayed_work, timer);

	wiphy_work_queue(dwork->wiphy, &dwork->work);
}

void wiphy_delayed_work_queue(struct wiphy *wiphy, struct wiphy_delayed_work *dwork, unsigned long delay)
{
	if (!delay) {
		wiphy_work_queue(wiphy, &dwork->work);
		return;
	}
	dwork->wiphy = wiphy;
	mod_timer(&dwork->timer, jiffies + delay);
}

void wiphy_delayed_work_cancel(struct wiphy *wiphy, struct wiphy_delayed_work *dwork)
{
	del_timer_sync(&dwork->timer);
	wiphy_work_cancel(wiphy, &dwork->work);
}

struct ieee80211_hw *wiphy_to_ieee80211_hw(struct wiphy *wiphy)
{
	return *(struct ieee80211_hw **)wiphy->priv;
}

void wiphy_rfkill_set_hw_state_reason(struct wiphy *wiphy, bool blocked, enum rfkill_hard_block_reasons reason)
{
	(void)reason;
	lkpi_wifi_of(wiphy_to_ieee80211_hw(wiphy))->hw_blocked = blocked;
}

int regulatory_set_wiphy_regd(struct wiphy *wiphy, struct ieee80211_regdomain *rd)
{
	(void)wiphy;
	return rd ? 0 : -EINVAL;
}

int regulatory_set_wiphy_regd_sync(struct wiphy *wiphy, struct ieee80211_regdomain *rd)
{
	return regulatory_set_wiphy_regd(wiphy, rd);
}

int reg_query_regdb_wmm(char *alpha2, int freq, struct ieee80211_reg_rule *rule)
{
	(void)alpha2;
	(void)freq;
	(void)rule;
	return -ENOENT;
}

int nl80211_chan_width_to_mhz(enum nl80211_chan_width width)
{
	switch (width) {
	case NL80211_CHAN_WIDTH_5:
		return 5;
	case NL80211_CHAN_WIDTH_10:
		return 10;
	case NL80211_CHAN_WIDTH_20_NOHT:
	case NL80211_CHAN_WIDTH_20:
		return 20;
	case NL80211_CHAN_WIDTH_40:
		return 40;
	case NL80211_CHAN_WIDTH_80P80:
	case NL80211_CHAN_WIDTH_80:
		return 80;
	case NL80211_CHAN_WIDTH_160:
		return 160;
	case NL80211_CHAN_WIDTH_320:
		return 320;
	default:
		return -1;
	}
}

void cfg80211_chandef_create(struct cfg80211_chan_def *chandef, struct ieee80211_channel *chan,
			     enum nl80211_channel_type chantype)
{
	memset(chandef, 0, sizeof(*chandef));
	chandef->chan = chan;
	chandef->freq1_offset = chan->freq_offset;
	chandef->center_freq1 = chan->center_freq;
	chandef->width = NL80211_CHAN_WIDTH_20;
	switch (chantype) {
	case NL80211_CHAN_NO_HT:
		chandef->width = NL80211_CHAN_WIDTH_20_NOHT;
		break;
	case NL80211_CHAN_HT40PLUS:
		chandef->width = NL80211_CHAN_WIDTH_40;
		chandef->center_freq1 += 10;
		break;
	case NL80211_CHAN_HT40MINUS:
		chandef->width = NL80211_CHAN_WIDTH_40;
		chandef->center_freq1 -= 10;
		break;
	default:
		break;
	}
}

const struct element *cfg80211_find_elem_match(u8 eid, const u8 *ies, unsigned int len, const u8 *match,
					       unsigned int match_len, unsigned int match_offset)
{
	const struct element *elem;

	if ((!match_len && match_offset) || (match_len && match_offset < 2))
		return NULL;
	for_each_element_id(elem, eid, ies, len) {
		if (elem->datalen >= match_offset - 2 + match_len &&
		    !memcmp(elem->data + match_offset - 2, match, match_len))
			return elem;
	}
	return NULL;
}

const struct wiphy_iftype_ext_capab *cfg80211_get_iftype_ext_capa(struct wiphy *wiphy, enum nl80211_iftype type)
{
	unsigned int i;

	for (i = 0; i < wiphy->num_iftype_ext_capab; i++) {
		if (wiphy->iftype_ext_capab[i].iftype == type)
			return &wiphy->iftype_ext_capab[i];
	}
	return NULL;
}

void cfg80211_bss_flush(struct wiphy *wiphy)
{
	(void)wiphy;
}

void cfg80211_bss_iter(struct wiphy *wiphy, struct cfg80211_chan_def *chandef,
		       void (*iter)(struct wiphy *wiphy, struct cfg80211_bss *bss, void *data), void *iter_data)
{
	(void)wiphy;
	(void)chandef;
	(void)iter;
	(void)iter_data;
}

void cfg80211_pmsr_complete(struct wireless_dev *wdev, struct cfg80211_pmsr_request *req, gfp_t gfp)
{
	(void)wdev;
	(void)req;
	(void)gfp;
}

void cfg80211_pmsr_report(struct wireless_dev *wdev, struct cfg80211_pmsr_request *req,
			  struct cfg80211_pmsr_result *result, gfp_t gfp)
{
	(void)wdev;
	(void)req;
	(void)result;
	(void)gfp;
}

void cfg80211_rx_unprot_mlme_mgmt(struct net_device *dev, const u8 *buf, size_t len)
{
	(void)dev;
	(void)buf;
	(void)len;
}

u32 ieee80211_channel_to_freq_khz(int chan, enum nl80211_band band)
{
	if (chan <= 0)
		return 0;
	switch (band) {
	case NL80211_BAND_2GHZ:
	case NL80211_BAND_S1GHZ:
		if (chan == 14)
			return 2484 * KHZ_PER_MHZ;
		if (chan < 14)
			return (2407 + chan * 5) * KHZ_PER_MHZ;
		break;
	case NL80211_BAND_5GHZ:
		if (chan >= 182 && chan <= 196)
			return (4000 + chan * 5) * KHZ_PER_MHZ;
		return (5000 + chan * 5) * KHZ_PER_MHZ;
	case NL80211_BAND_6GHZ:
		if (chan == 2)
			return 5935 * KHZ_PER_MHZ;
		if (chan <= 233)
			return (5950 + chan * 5) * KHZ_PER_MHZ;
		break;
	case NL80211_BAND_60GHZ:
		if (chan < 7)
			return (56160 + chan * 2160) * KHZ_PER_MHZ;
		break;
	default:
		break;
	}
	return 0;
}

int ieee80211_freq_khz_to_channel(u32 freq_khz)
{
	u32 freq = freq_khz / KHZ_PER_MHZ;

	if (freq == 2484)
		return 14;
	if (freq < 2484)
		return (freq - 2407) / 5;
	if (freq >= 4910 && freq <= 4980)
		return (freq - 4000) / 5;
	if (freq < 5925)
		return (freq - 5000) / 5;
	if (freq == 5935)
		return 2;
	if (freq <= 45000)
		return (freq - 5950) / 5;
	if (freq >= 58320 && freq <= 70200)
		return (freq - 56160) / 2160;
	return 0;
}

struct ieee80211_channel *ieee80211_get_channel_khz(struct wiphy *wiphy, u32 freq)
{
	int band;
	int i;

	for (band = 0; band < NUM_NL80211_BANDS; band++) {
		struct ieee80211_supported_band *sband = wiphy->bands[band];

		if (!sband)
			continue;
		for (i = 0; i < sband->n_channels; i++) {
			if (ieee80211_channel_to_khz(&sband->channels[i]) == freq)
				return &sband->channels[i];
		}
	}
	return NULL;
}
