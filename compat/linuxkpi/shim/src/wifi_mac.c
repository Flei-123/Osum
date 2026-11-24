#include "wifi.h"
#include <linux/ieee80211.h>

#define TKIP_IV_EXT_FLAG (1U << 5)
#define TKIP_IV_KEYID_SHIFT 6
#define TKIP_IV_HIGH_MASK 0x7fU
#define TKIP_IV_HIGH_SET 0x20U
#define TKIP_EXT_IV_LEN 4
#define IE_HEADER_LEN 2
#define VHT_NSS_MAX 8
#define VHT_MCS_BITS 2
#define VHT_MCS_MASK 3U
#define VHT_MAP_NONE 0xffffU

static const struct rate_control_ops *rate_control;

static bool id_in_list(const u8 *ids, int n_ids, u8 id)
{
	int i;

	for (i = 0; i < n_ids; i++) {
		if (ids[i] == id)
			return true;
	}
	return false;
}

unsigned int ieee80211_hdrlen(__le16 fc)
{
	unsigned int hdrlen = 24;

	if (ieee80211_is_ext(fc))
		return 4;
	if (ieee80211_is_data(fc)) {
		if (ieee80211_has_a4(fc))
			hdrlen = 30;
		if (ieee80211_is_data_qos(fc)) {
			hdrlen += IEEE80211_QOS_CTL_LEN;
			if (ieee80211_has_order(fc))
				hdrlen += IEEE80211_HT_CTL_LEN;
		}
		return hdrlen;
	}
	if (ieee80211_is_mgmt(fc))
		return ieee80211_has_order(fc) ? hdrlen + IEEE80211_HT_CTL_LEN : hdrlen;
	if (ieee80211_is_ctl(fc)) {
		if (ieee80211_is_cts(fc) || ieee80211_is_ack(fc))
			return 10;
		return 16;
	}
	return hdrlen;
}

size_t ieee80211_ie_split_ric(const u8 *ies, size_t ielen, const u8 *ids, int n_ids, const u8 *after_ric,
			      int n_after_ric, size_t offset)
{
	size_t pos = offset;

	while (pos < ielen && id_in_list(ids, n_ids, ies[pos])) {
		if (ies[pos] == WLAN_EID_RIC_DATA && n_after_ric) {
			pos += IE_HEADER_LEN + ies[pos + 1];
			while (pos < ielen && !id_in_list(after_ric, n_after_ric, ies[pos]))
				pos += IE_HEADER_LEN + ies[pos + 1];
		} else {
			pos += IE_HEADER_LEN + ies[pos + 1];
		}
	}
	return pos;
}

u8 *ieee80211_tkip_add_iv(u8 *pos, struct ieee80211_key_conf *keyconf, u64 pn)
{
	u16 iv16 = pn & 0xffff;
	u32 iv32 = pn >> 16;

	*pos++ = iv16 >> 8;
	*pos++ = ((iv16 >> 8) | TKIP_IV_HIGH_SET) & TKIP_IV_HIGH_MASK;
	*pos++ = iv16 & 0xff;
	*pos++ = (keyconf->keyidx << TKIP_IV_KEYID_SHIFT) | TKIP_IV_EXT_FLAG;
	put_unaligned_le32(iv32, pos);
	return pos + TKIP_EXT_IV_LEN;
}

int ieee80211_get_vht_max_nss(struct ieee80211_vht_cap *cap, enum ieee80211_vht_chanwidth bw, int mcs,
			      bool ext_nss_bw_capable, unsigned int max_vht_nss)
{
	u16 map = le16_to_cpu(cap->supp_mcs.rx_mcs_map);
	unsigned int wanted = mcs <= 7 ? IEEE80211_VHT_MCS_SUPPORT_0_7 :
			      mcs == 8 ? IEEE80211_VHT_MCS_SUPPORT_0_8 : IEEE80211_VHT_MCS_SUPPORT_0_9;
	int nss;

	(void)bw;
	(void)ext_nss_bw_capable;
	if (map == VHT_MAP_NONE)
		return 0;
	for (nss = VHT_NSS_MAX; nss > 0; nss--) {
		unsigned int level = (map >> ((nss - 1) * VHT_MCS_BITS)) & VHT_MCS_MASK;

		if (level != IEEE80211_VHT_MCS_NOT_SUPPORTED && level >= wanted)
			return max_vht_nss && (unsigned int)nss > max_vht_nss ? (int)max_vht_nss : nss;
	}
	return 0;
}

void ieee80211_iterate_interfaces(struct ieee80211_hw *hw, u32 iter_flags,
				  void (*iterator)(void *data, u8 *mac, struct ieee80211_vif *vif), void *data)
{
	struct lkpi_wifi_hw *w = lkpi_wifi_of(hw);

	(void)iter_flags;
	if (w->state.iface)
		iterator(data, w->vif.vif.addr, &w->vif.vif);
}

void ieee80211_iterate_active_interfaces_atomic(struct ieee80211_hw *hw, u32 iter_flags,
						void (*iterator)(void *data, u8 *mac, struct ieee80211_vif *vif),
						void *data)
{
	ieee80211_iterate_interfaces(hw, iter_flags, iterator, data);
}

void ieee80211_iterate_stations_atomic(struct ieee80211_hw *hw, void (*iterator)(void *data, struct ieee80211_sta *sta),
				       void *data)
{
	struct lkpi_wifi_hw *w = lkpi_wifi_of(hw);

	if (w->state.sta_state > IEEE80211_STA_NOTEXIST)
		iterator(data, &w->sta.sta);
}

void ieee80211_iter_keys(struct ieee80211_hw *hw, struct ieee80211_vif *vif,
			 void (*iter)(struct ieee80211_hw *hw, struct ieee80211_vif *vif, struct ieee80211_sta *sta,
				      struct ieee80211_key_conf *key, void *data), void *iter_data)
{
	struct lkpi_wifi_hw *w = lkpi_wifi_of(hw);

	if (w->pairwise.keylen)
		iter(hw, vif, &w->sta.sta, &w->pairwise, iter_data);
	if (w->group.keylen)
		iter(hw, vif, NULL, &w->group, iter_data);
}

void ieee80211_iter_keys_rcu(struct ieee80211_hw *hw, struct ieee80211_vif *vif,
			     void (*iter)(struct ieee80211_hw *hw, struct ieee80211_vif *vif, struct ieee80211_sta *sta,
					  struct ieee80211_key_conf *key, void *data), void *iter_data)
{
	ieee80211_iter_keys(hw, vif, iter, iter_data);
}

struct ieee80211_sta *ieee80211_find_sta(struct ieee80211_vif *vif, const u8 *addr)
{
	struct lkpi_wifi_hw *w = lkpi_wifi_of_vif(vif);

	if (w->state.sta_state > IEEE80211_STA_NOTEXIST && ether_addr_equal(addr, w->sta.sta.addr))
		return &w->sta.sta;
	return NULL;
}

struct ieee80211_sta *ieee80211_find_sta_by_ifaddr(struct ieee80211_hw *hw, const u8 *addr, const u8 *localaddr)
{
	struct lkpi_wifi_hw *w = lkpi_wifi_of(hw);

	if (localaddr && !ether_addr_equal(localaddr, w->vif.vif.addr))
		return NULL;
	return ieee80211_find_sta(&w->vif.vif, addr);
}

struct wireless_dev *ieee80211_vif_to_wdev(struct ieee80211_vif *vif)
{
	return &lkpi_wifi_of_vif(vif)->wdev;
}

void ieee80211_rx_irqsafe(struct ieee80211_hw *hw, struct sk_buff *skb)
{
	ieee80211_rx_napi(hw, NULL, skb, NULL);
}

void ieee80211_tx_status_ext(struct ieee80211_hw *hw, struct ieee80211_tx_status *status)
{
	if (status->skb)
		ieee80211_tx_status_skb(hw, status->skb);
}

struct sk_buff *ieee80211_tx_dequeue(struct ieee80211_hw *hw, struct ieee80211_txq *txq)
{
	(void)hw;
	(void)txq;
	return NULL;
}

struct sk_buff *ieee80211_beacon_get_template(struct ieee80211_hw *hw, struct ieee80211_vif *vif,
					      struct ieee80211_mutable_offsets *offs, unsigned int link_id)
{
	(void)hw;
	(void)vif;
	(void)offs;
	(void)link_id;
	return NULL;
}

void ieee80211_cqm_beacon_loss_notify(struct ieee80211_vif *vif, gfp_t gfp)
{
	(void)gfp;
	ieee80211_beacon_loss(vif);
}

void ieee80211_disconnect(struct ieee80211_vif *vif, bool reconnect)
{
	(void)reconnect;
	ieee80211_connection_loss(vif);
}

void ieee80211_hw_restart_disconnect(struct ieee80211_vif *vif)
{
	ieee80211_connection_loss(vif);
}

void ieee80211_channel_switch_disconnect(struct ieee80211_vif *vif)
{
	ieee80211_connection_loss(vif);
}

int ieee80211_rate_control_register(const struct rate_control_ops *ops)
{
	if (rate_control)
		return -EBUSY;
	rate_control = ops;
	return 0;
}

void ieee80211_rate_control_unregister(const struct rate_control_ops *ops)
{
	if (rate_control == ops)
		rate_control = NULL;
}

int ieee80211_start_tx_ba_session(struct ieee80211_sta *sta, u16 tid, u16 timeout)
{
	(void)sta;
	(void)tid;
	(void)timeout;
	return -EINVAL;
}

int ieee80211_stop_tx_ba_session(struct ieee80211_sta *sta, u16 tid)
{
	(void)sta;
	(void)tid;
	return -EINVAL;
}

int ieee80211_reserve_tid(struct ieee80211_sta *sta, u8 tid)
{
	(void)sta;
	(void)tid;
	return 0;
}

int ieee80211_sta_ps_transition(struct ieee80211_sta *sta, bool start)
{
	(void)sta;
	(void)start;
	return 0;
}

int ieee80211_set_active_links(struct ieee80211_vif *vif, u16 active_links)
{
	(void)vif;
	(void)active_links;
	return 0;
}

bool ieee80211_beacon_cntdwn_is_complete(struct ieee80211_vif *vif, unsigned int link_id)
{
	(void)vif;
	(void)link_id;
	return false;
}

u8 ieee80211_beacon_update_cntdwn(struct ieee80211_vif *vif, unsigned int link_id)
{
	(void)vif;
	(void)link_id;
	return 0;
}

void ieee80211_get_key_rx_seq(struct ieee80211_key_conf *keyconf, int tid, struct ieee80211_key_seq *seq)
{
	(void)keyconf;
	(void)tid;
	memset(seq, 0, sizeof(*seq));
}

void ieee80211_get_tkip_p2k(struct ieee80211_key_conf *keyconf, struct sk_buff *skb, u8 *p2k)
{
	(void)keyconf;
	(void)skb;
	memset(p2k, 0, 16);
}

void ieee80211_get_tkip_rx_p1k(struct ieee80211_key_conf *keyconf, const u8 *ta, u32 iv32, u16 *p1k)
{
	(void)keyconf;
	(void)ta;
	(void)iv32;
	memset(p1k, 0, 5 * sizeof(*p1k));
}

#define LKPI_NOOP_VIF(name) void name(struct ieee80211_vif *vif) { (void)vif; }
#define LKPI_NOOP_HW(name) void name(struct ieee80211_hw *hw) { (void)hw; }
#define LKPI_NOOP_STA(name) void name(struct ieee80211_sta *sta) { (void)sta; }

LKPI_NOOP_HW(ieee80211_ready_on_channel)
LKPI_NOOP_HW(ieee80211_remain_on_channel_expired)
LKPI_NOOP_HW(ieee80211_sched_scan_results)
LKPI_NOOP_HW(ieee80211_sched_scan_stopped)
LKPI_NOOP_HW(ieee80211_stop_queues)
LKPI_NOOP_HW(ieee80211_wake_queues)
LKPI_NOOP_STA(ieee80211_sta_eosp)
LKPI_NOOP_STA(ieee80211_sta_pspoll)
LKPI_NOOP_STA(ieee80211_sta_recalc_aggregates)

void ieee80211_key_mic_failure(struct ieee80211_key_conf *keyconf)
{
	(void)keyconf;
}

void ieee80211_key_replay(struct ieee80211_key_conf *keyconf)
{
	(void)keyconf;
}

void ieee80211_unreserve_tid(struct ieee80211_sta *sta, u8 tid)
{
	(void)sta;
	(void)tid;
}

void ieee80211_beacon_set_cntdwn(struct ieee80211_vif *vif, u8 counter)
{
	(void)vif;
	(void)counter;
}

void ieee80211_csa_finish(struct ieee80211_vif *vif, unsigned int link_id)
{
	(void)vif;
	(void)link_id;
}

void ieee80211_chswitch_done(struct ieee80211_vif *vif, bool success, unsigned int link_id)
{
	(void)vif;
	(void)success;
	(void)link_id;
}

void ieee80211_cqm_rssi_notify(struct ieee80211_vif *vif, enum nl80211_cqm_rssi_threshold_event rssi_event,
			       s32 rssi_level, gfp_t gfp)
{
	(void)vif;
	(void)rssi_event;
	(void)rssi_level;
	(void)gfp;
}

void ieee80211_mark_rx_ba_filtered_frames(struct ieee80211_sta *pubsta, u8 tid, u16 ssn, u64 filtered,
					  u16 received_mpdus)
{
	(void)pubsta;
	(void)tid;
	(void)ssn;
	(void)filtered;
	(void)received_mpdus;
}

void ieee80211_request_smps(struct ieee80211_vif *vif, unsigned int link_id, enum ieee80211_smps_mode smps_mode)
{
	(void)vif;
	(void)link_id;
	(void)smps_mode;
}

void ieee80211_rx_ba_timer_expired(struct ieee80211_vif *vif, const u8 *addr, unsigned int tid)
{
	(void)vif;
	(void)addr;
	(void)tid;
}

void ieee80211_send_eosp_nullfunc(struct ieee80211_sta *pubsta, int tid)
{
	(void)pubsta;
	(void)tid;
}

void ieee80211_set_active_links_async(struct ieee80211_vif *vif, u16 active_links)
{
	(void)vif;
	(void)active_links;
}

void ieee80211_sta_block_awake(struct ieee80211_hw *hw, struct ieee80211_sta *pubsta, bool block)
{
	(void)hw;
	(void)pubsta;
	(void)block;
}

void ieee80211_sta_set_buffered(struct ieee80211_sta *sta, u8 tid, bool buffered)
{
	(void)sta;
	(void)tid;
	(void)buffered;
}

void ieee80211_sta_uapsd_trigger(struct ieee80211_sta *sta, u8 tid)
{
	(void)sta;
	(void)tid;
}

void ieee80211_start_tx_ba_cb_irqsafe(struct ieee80211_vif *vif, const u8 *ra, u16 tid)
{
	(void)vif;
	(void)ra;
	(void)tid;
}

void ieee80211_stop_tx_ba_cb_irqsafe(struct ieee80211_vif *vif, const u8 *ra, u16 tid)
{
	(void)vif;
	(void)ra;
	(void)tid;
}

void ieee80211_tdls_oper_request(struct ieee80211_vif *vif, const u8 *peer, enum nl80211_tdls_operation oper,
				 u16 reason_code, gfp_t gfp)
{
	(void)vif;
	(void)peer;
	(void)oper;
	(void)reason_code;
	(void)gfp;
}

void ieee80211_update_mu_groups(struct ieee80211_vif *vif, unsigned int link_id, const u8 *membership,
				const u8 *position)
{
	(void)vif;
	(void)link_id;
	(void)membership;
	(void)position;
}
