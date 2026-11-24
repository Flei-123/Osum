/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_NET_CFG80211_H
#define LKPI_NET_CFG80211_H
#include <linux/types.h>
#include <linux/kernel.h>
#include <linux/list.h>
#include <linux/netdevice.h>
#include <linux/skbuff.h>
#include <linux/ieee80211.h>
#include <linux/nl80211.h>
#include <linux/workqueue.h>
#include <linux/mutex.h>
#include <linux/rcupdate.h>
#include <net/regulatory.h>

enum ieee80211_channel_flags {
	IEEE80211_CHAN_DISABLED = 1 << 0, IEEE80211_CHAN_NO_IR = 1 << 1, IEEE80211_CHAN_RADAR = 1 << 3,
	IEEE80211_CHAN_NO_HT40PLUS = 1 << 4, IEEE80211_CHAN_NO_HT40MINUS = 1 << 5, IEEE80211_CHAN_NO_OFDM = 1 << 6,
	IEEE80211_CHAN_NO_80MHZ = 1 << 7, IEEE80211_CHAN_NO_160MHZ = 1 << 8, IEEE80211_CHAN_INDOOR_ONLY = 1 << 9,
	IEEE80211_CHAN_IR_CONCURRENT = 1 << 10, IEEE80211_CHAN_NO_20MHZ = 1 << 11, IEEE80211_CHAN_NO_10MHZ = 1 << 12,
	IEEE80211_CHAN_NO_HE = 1 << 13, IEEE80211_CHAN_1MHZ = 1 << 14, IEEE80211_CHAN_2MHZ = 1 << 15,
	IEEE80211_CHAN_4MHZ = 1 << 16, IEEE80211_CHAN_8MHZ = 1 << 17, IEEE80211_CHAN_16MHZ = 1 << 18,
	IEEE80211_CHAN_NO_320MHZ = 1 << 19, IEEE80211_CHAN_NO_EHT = 1 << 20, IEEE80211_CHAN_DFS_CONCURRENT = 1 << 21,
	IEEE80211_CHAN_NO_6GHZ_VLP_CLIENT = 1 << 22, IEEE80211_CHAN_NO_6GHZ_AFC_CLIENT = 1 << 23, IEEE80211_CHAN_CAN_MONITOR = 1 << 24,
	IEEE80211_CHAN_ALLOW_6GHZ_VLP_AP = 1 << 25,
};
#define IEEE80211_CHAN_NO_HT40 (IEEE80211_CHAN_NO_HT40MINUS | IEEE80211_CHAN_NO_HT40PLUS)

struct ieee80211_channel {
	enum nl80211_band band;
	u32 center_freq;
	u16 freq_offset;
	u16 hw_value;
	u32 flags;
	int max_antenna_gain;
	int max_power;
	int max_reg_power;
	bool beacon_found;
	u32 orig_flags;
	int orig_mag, orig_mpwr;
	enum nl80211_dfs_state dfs_state;
	unsigned long dfs_state_entered;
	unsigned int dfs_cac_ms;
	s8 psd;
};

enum ieee80211_rate_flags {
	IEEE80211_RATE_SHORT_PREAMBLE = 1 << 0, IEEE80211_RATE_MANDATORY_A = 1 << 1, IEEE80211_RATE_MANDATORY_B = 1 << 2,
	IEEE80211_RATE_MANDATORY_G = 1 << 3, IEEE80211_RATE_ERP_G = 1 << 4, IEEE80211_RATE_SUPPORTS_5MHZ = 1 << 5,
	IEEE80211_RATE_SUPPORTS_10MHZ = 1 << 6,
};

struct ieee80211_rate {
	u32 flags;
	u16 bitrate;
	u16 hw_value, hw_value_short;
};

struct ieee80211_sta_ht_cap {
	u16 cap;
	bool ht_supported;
	u8 ampdu_factor;
	u8 ampdu_density;
	struct ieee80211_mcs_info mcs;
};

struct ieee80211_sta_vht_cap {
	bool vht_supported;
	u32 cap;
	struct ieee80211_vht_mcs_info vht_mcs;
};

#define IEEE80211_HE_PPE_THRES_MAX_LEN 25
#define IEEE80211_EHT_PPE_THRES_MAX_LEN 32

struct ieee80211_sta_he_cap {
	bool has_he;
	struct ieee80211_he_cap_elem he_cap_elem;
	struct ieee80211_he_mcs_nss_supp he_mcs_nss_supp;
	u8 ppe_thres[IEEE80211_HE_PPE_THRES_MAX_LEN];
};

struct ieee80211_eht_mcs_nss_supp {
	union {
		struct ieee80211_eht_mcs_nss_supp_20mhz_only only_20mhz;
		struct { struct ieee80211_eht_mcs_nss_supp_bw _80, _160, _320; } __packed bw;
	} __packed;
} __packed;

struct ieee80211_sta_eht_cap {
	bool has_eht;
	struct ieee80211_eht_cap_elem_fixed eht_cap_elem;
	struct ieee80211_eht_mcs_nss_supp eht_mcs_nss_supp;
	u8 eht_ppe_thres[IEEE80211_EHT_PPE_THRES_MAX_LEN];
};

struct ieee80211_sband_iftype_data {
	u16 types_mask;
	struct ieee80211_sta_he_cap he_cap;
	struct ieee80211_he_6ghz_capa he_6ghz_capa;
	struct ieee80211_sta_eht_cap eht_cap;
	struct { const u8 *data; unsigned int len; } vendor_elems;
};

struct ieee80211_sta_s1g_cap { bool s1g; u8 cap[10]; u8 nss_mcs[5]; };
struct ieee80211_edmg { u8 channels; int bw_config; };

struct ieee80211_supported_band {
	struct ieee80211_channel *channels;
	struct ieee80211_rate *bitrates;
	enum nl80211_band band;
	int n_channels;
	int n_bitrates;
	struct ieee80211_sta_ht_cap ht_cap;
	struct ieee80211_sta_vht_cap vht_cap;
	struct ieee80211_sta_s1g_cap s1g_cap;
	struct ieee80211_edmg edmg_cap;
	u16 n_iftype_data;
	const struct ieee80211_sband_iftype_data *iftype_data;
};

static inline const struct ieee80211_sband_iftype_data *
ieee80211_get_sband_iftype_data(const struct ieee80211_supported_band *sband, u8 iftype)
{
	int i;

	for (i = 0; i < sband->n_iftype_data; i++)
		if (sband->iftype_data[i].types_mask & (1 << iftype))
			return &sband->iftype_data[i];
	return NULL;
}

static inline const struct ieee80211_sta_he_cap *
ieee80211_get_he_iftype_cap(const struct ieee80211_supported_band *sband, u8 iftype)
{
	const struct ieee80211_sband_iftype_data *data = ieee80211_get_sband_iftype_data(sband, iftype);

	return data && data->he_cap.has_he ? &data->he_cap : NULL;
}

struct wiphy;
#define IEEE80211_NUM_ACS 4
struct ieee80211_freq_range { u32 start_freq_khz; u32 end_freq_khz; u32 max_bandwidth_khz; };
struct ieee80211_power_rule { u32 max_antenna_gain; u32 max_eirp; };
struct ieee80211_wmm_ac { u16 cw_min; u16 cw_max; u16 cot; u8 aifsn; };
struct ieee80211_wmm_rule { struct ieee80211_wmm_ac client[IEEE80211_NUM_ACS]; struct ieee80211_wmm_ac ap[IEEE80211_NUM_ACS]; };
struct ieee80211_reg_rule {
	struct ieee80211_freq_range freq_range;
	struct ieee80211_power_rule power_rule;
	struct ieee80211_wmm_rule wmm_rule;
	u32 flags;
	u32 dfs_cac_ms;
	bool has_wmm;
	s8 psd;
};
struct ieee80211_regdomain {
	struct rcu_head rcu_head;
	u32 n_reg_rules;
	char alpha2[3];
	enum nl80211_dfs_regions dfs_region;
	struct ieee80211_reg_rule reg_rules[];
};
struct wireless_dev { struct wiphy *wiphy; int iftype; struct net_device *netdev; u8 address[ETH_ALEN]; };
struct cfg80211_chan_def {
	struct ieee80211_channel *chan;
	enum nl80211_chan_width width;
	u32 center_freq1;
	u32 center_freq2;
	u16 punctured;
};

#define IEEE80211_CHAN_NO_HE_BAND 0
int ieee80211_channel_to_frequency(int chan, enum nl80211_band band);
int ieee80211_frequency_to_channel(int freq);
struct ieee80211_channel *ieee80211_get_channel_khz(struct wiphy *wiphy, u32 freq);
#define ieee80211_get_channel(wiphy, freq) ieee80211_get_channel_khz(wiphy, (freq) * 1000)
#endif
