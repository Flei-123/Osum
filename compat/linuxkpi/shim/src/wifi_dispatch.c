#include "wifi.h"

#define KEY_CIPHER_CCMP 0x000FAC04
#define KEY_BYTES 16
#define EDCA_CW_MIN 15
#define EDCA_CW_MAX 1023
#define EDCA_AIFS 2
#define FLUSH_ALL_QUEUES 0xFFFFFFFFu
#define DEFAULT_BEACON_INT 100
#define DEFAULT_DTIM_PERIOD 1

static int op_start(struct lkpi_wifi_hw *w)
{
	int rc;

	if (w->state.started)
		return LKPI80211_EPROTO;
	rc = w->ops->start(&w->hw);
	if (!rc)
		w->state.started = 1;
	return rc;
}

static int op_stop(struct lkpi_wifi_hw *w)
{
	if (!w->state.started || w->state.iface)
		return LKPI80211_EPROTO;
	w->ops->stop(&w->hw, false);
	w->state.started = 0;
	return 0;
}

static int op_add_interface(struct lkpi_wifi_hw *w)
{
	int rc;

	if (!w->state.started || w->state.iface)
		return LKPI80211_EPROTO;
	w->vif.vif.type = NL80211_IFTYPE_STATION;
	rc = w->ops->add_interface(&w->hw, &w->vif.vif);
	if (!rc)
		w->state.iface = 1;
	return rc;
}

static int op_remove_interface(struct lkpi_wifi_hw *w)
{
	if (!w->state.iface || w->state.sta_state != IEEE80211_STA_NOTEXIST || w->state.chanctx)
		return LKPI80211_EPROTO;
	w->ops->remove_interface(&w->hw, &w->vif.vif);
	w->state.iface = 0;
	return 0;
}

static void fill_scan_request(struct lkpi_wifi_hw *w)
{
	struct ieee80211_supported_band *band = w->wiphy->bands[NL80211_BAND_2GHZ];
	struct cfg80211_scan_request *req = &w->scan.request.req;
	int i;

	memset(&w->scan, 0, sizeof(w->scan));
	req->wiphy = w->wiphy;
	req->wdev = &w->wdev;
	if (!band)
		return;
	for (i = 0; i < band->n_channels && req->n_channels < LKPI_SCAN_CHANNELS; i++) {
		if (band->channels[i].flags & IEEE80211_CHAN_DISABLED)
			continue;
		req->channels[req->n_channels++] = &band->channels[i];
	}
}

static int op_hw_scan(struct lkpi_wifi_hw *w)
{
	int rc;

	if (!w->state.iface || w->state.scanning)
		return LKPI80211_EPROTO;
	if (!w->ops->hw_scan)
		return LKPI80211_ENOSYS;
	fill_scan_request(w);
	rc = w->ops->hw_scan(&w->hw, &w->vif.vif, &w->scan.request);
	if (!rc)
		w->state.scanning = 1;
	return rc;
}

static int op_cancel_hw_scan(struct lkpi_wifi_hw *w)
{
	if (!w->state.scanning)
		return LKPI80211_EPROTO;
	if (w->ops->cancel_hw_scan)
		w->ops->cancel_hw_scan(&w->hw, &w->vif.vif);
	w->state.scanning = 0;
	return 0;
}

static struct ieee80211_channel *find_join_channel(struct lkpi_wifi_hw *w)
{
	struct ieee80211_channel *first = NULL;
	int b, i;

	for (b = 0; b < NUM_NL80211_BANDS; b++) {
		struct ieee80211_supported_band *band = w->wiphy->bands[b];

		for (i = 0; band && i < band->n_channels; i++) {
			if (band->channels[i].flags & IEEE80211_CHAN_DISABLED)
				continue;
			if (band->channels[i].hw_value == w->join_channel)
				return &band->channels[i];
			if (!first)
				first = &band->channels[i];
		}
	}
	return first;
}

static int fill_chanctx(struct lkpi_wifi_hw *w)
{
	struct ieee80211_chanctx_conf *ctx = &w->chanctx.ctx;
	struct ieee80211_channel *chan = find_join_channel(w);

	if (!chan)
		return LKPI80211_EINVAL;
	cfg80211_chandef_create(&ctx->def, chan, NL80211_CHAN_NO_HT);
	ctx->min_def = ctx->def;
	ctx->rx_chains_static = 1;
	ctx->rx_chains_dynamic = 1;
	w->join_band = chan->band;
	w->vif.vif.bss_conf.chanreq.oper = ctx->def;
	return 0;
}

static int op_add_chanctx(struct lkpi_wifi_hw *w)
{
	int rc = 0;

	if (!w->state.iface || w->state.chanctx)
		return LKPI80211_EPROTO;
	rc = fill_chanctx(w);
	if (rc)
		return rc;
	if (w->ops->add_chanctx)
		rc = w->ops->add_chanctx(&w->hw, &w->chanctx.ctx);
	if (!rc)
		w->state.chanctx = 1;
	return rc;
}

static int op_remove_chanctx(struct lkpi_wifi_hw *w)
{
	if (!w->state.chanctx || w->state.assigned)
		return LKPI80211_EPROTO;
	if (w->ops->remove_chanctx)
		w->ops->remove_chanctx(&w->hw, &w->chanctx.ctx);
	w->state.chanctx = 0;
	return 0;
}

static int op_assign(struct lkpi_wifi_hw *w)
{
	int rc = 0;

	if (!w->state.chanctx || w->state.assigned)
		return LKPI80211_EPROTO;
	w->vif.vif.bss_conf.chanctx_conf = &w->chanctx.ctx;
	if (w->ops->assign_vif_chanctx)
		rc = w->ops->assign_vif_chanctx(&w->hw, &w->vif.vif, &w->vif.vif.bss_conf, &w->chanctx.ctx);
	if (!rc)
		w->state.assigned = 1;
	return rc;
}

static int op_unassign(struct lkpi_wifi_hw *w)
{
	if (!w->state.assigned || w->state.sta_state != IEEE80211_STA_NOTEXIST)
		return LKPI80211_EPROTO;
	if (w->ops->unassign_vif_chanctx)
		w->ops->unassign_vif_chanctx(&w->hw, &w->vif.vif, &w->vif.vif.bss_conf, &w->chanctx.ctx);
	w->vif.vif.bss_conf.chanctx_conf = NULL;
	w->state.assigned = 0;
	return 0;
}

static int op_sta_state(struct lkpi_wifi_hw *w, u64 arg)
{
	u32 old = w->state.sta_state;
	int rc;

	if (arg > IEEE80211_STA_AUTHORIZED || !w->state.assigned)
		return LKPI80211_EPROTO;
	if (arg != old + 1 && arg + 1 != old)
		return LKPI80211_EPROTO;
	if (old == IEEE80211_STA_NOTEXIST)
		w->sta.sta.deflink.smps_mode = IEEE80211_SMPS_OFF;
	rc = w->ops->sta_state(&w->hw, &w->vif.vif, &w->sta.sta, old, arg);
	if (!rc)
		w->state.sta_state = arg;
	return rc;
}

static int op_prep_tx(struct lkpi_wifi_hw *w, bool complete)
{
	struct ieee80211_prep_tx_info info = { 0 };

	if (!w->state.assigned)
		return LKPI80211_EPROTO;
	if (complete && w->ops->mgd_complete_tx)
		w->ops->mgd_complete_tx(&w->hw, &w->vif.vif, &info);
	if (!complete && w->ops->mgd_prepare_tx)
		w->ops->mgd_prepare_tx(&w->hw, &w->vif.vif, &info);
	return 0;
}

static int op_bss_info(struct lkpi_wifi_hw *w, u64 arg)
{
	u64 changed = 0;

	if (!w->state.assigned)
		return LKPI80211_EPROTO;
	if (arg == MACPLAN_BSS_BSSID) {
		changed = BSS_CHANGED_BSSID;
		w->vif.vif.bss_conf.beacon_int = DEFAULT_BEACON_INT;
		w->vif.vif.bss_conf.dtim_period = DEFAULT_DTIM_PERIOD;
	} else if (arg == MACPLAN_BSS_QOS) {
		changed = BSS_CHANGED_QOS;
		w->vif.vif.bss_conf.qos = true;
	} else
		return LKPI80211_EINVAL;
	if (w->ops->bss_info_changed)
		w->ops->bss_info_changed(&w->hw, &w->vif.vif, &w->vif.vif.bss_conf, changed);
	return 0;
}

static int op_vif_cfg(struct lkpi_wifi_hw *w)
{
	if (!w->state.assigned)
		return LKPI80211_EPROTO;
	w->vif.vif.cfg.assoc = w->state.sta_state >= IEEE80211_STA_ASSOC;
	if (w->ops->vif_cfg_changed)
		w->ops->vif_cfg_changed(&w->hw, &w->vif.vif, BSS_CHANGED_ASSOC);
	return 0;
}

static int op_conf_tx(struct lkpi_wifi_hw *w, u64 arg)
{
	struct ieee80211_tx_queue_params params = { .txop = 0, .cw_min = EDCA_CW_MIN, .cw_max = EDCA_CW_MAX, .aifs = EDCA_AIFS };

	if (arg >= IEEE80211_NUM_ACS || !w->state.assigned)
		return LKPI80211_EPROTO;
	if (!w->ops->conf_tx)
		return 0;
	return w->ops->conf_tx(&w->hw, &w->vif.vif, 0, arg, &params);
}

static int op_set_key(struct lkpi_wifi_hw *w, u64 arg)
{
	bool pairwise = arg == MACPLAN_KEY_SET_PAIRWISE || arg == MACPLAN_KEY_DEL_PAIRWISE;
	bool set = arg == MACPLAN_KEY_SET_PAIRWISE || arg == MACPLAN_KEY_SET_GROUP;
	struct ieee80211_key_conf *key = pairwise ? &w->pairwise : &w->group;
	int rc;

	if (arg < MACPLAN_KEY_SET_PAIRWISE || arg > MACPLAN_KEY_DEL_GROUP || !w->ops->set_key)
		return LKPI80211_ENOSYS;
	if (set && w->state.sta_state < IEEE80211_STA_ASSOC)
		return LKPI80211_EPROTO;
	if (set == (key->cipher != 0))
		return LKPI80211_EPROTO;
	if (set) {
		key->cipher = KEY_CIPHER_CCMP;
		key->keylen = KEY_BYTES;
		key->keyidx = pairwise ? 0 : 1;
		key->flags = pairwise ? IEEE80211_KEY_FLAG_PAIRWISE : 0;
	}
	rc = w->ops->set_key(&w->hw, set ? SET_KEY : DISABLE_KEY, &w->vif.vif,
				pairwise ? &w->sta.sta : NULL, key);
	if (rc)
		return rc;
	if (set) {
		w->state.keys++;
		return 0;
	}
	key->cipher = 0;
	w->state.keys--;
	return 0;
}

static int op_flush(struct lkpi_wifi_hw *w)
{
	if (w->ops->flush)
		w->ops->flush(&w->hw, &w->vif.vif, FLUSH_ALL_QUEUES, false);
	return 0;
}

int lkpi_wifi_op(struct lkpi_wifi_hw *w, u32 op, u64 arg)
{
	switch (op) {
	case MACPLAN_OP_START: return op_start(w);
	case MACPLAN_OP_STOP: return op_stop(w);
	case MACPLAN_OP_ADD_INTERFACE: return op_add_interface(w);
	case MACPLAN_OP_REMOVE_INTERFACE: return op_remove_interface(w);
	case MACPLAN_OP_HW_SCAN: return op_hw_scan(w);
	case MACPLAN_OP_CANCEL_HW_SCAN: return op_cancel_hw_scan(w);
	case MACPLAN_OP_ADD_CHANCTX: return op_add_chanctx(w);
	case MACPLAN_OP_REMOVE_CHANCTX: return op_remove_chanctx(w);
	case MACPLAN_OP_ASSIGN_VIF_CHANCTX: return op_assign(w);
	case MACPLAN_OP_UNASSIGN_VIF_CHANCTX: return op_unassign(w);
	case MACPLAN_OP_STA_STATE: return op_sta_state(w, arg);
	case MACPLAN_OP_MGD_PREPARE_TX: return op_prep_tx(w, false);
	case MACPLAN_OP_MGD_COMPLETE_TX: return op_prep_tx(w, true);
	case MACPLAN_OP_BSS_INFO_CHANGED: return op_bss_info(w, arg);
	case MACPLAN_OP_VIF_CFG_CHANGED: return op_vif_cfg(w);
	case MACPLAN_OP_CONF_TX: return op_conf_tx(w, arg);
	case MACPLAN_OP_SET_KEY: return op_set_key(w, arg);
	case MACPLAN_OP_FLUSH: return op_flush(w);
	}
	return LKPI80211_EINVAL;
}

int lkpi80211_apply(struct ieee80211_hw *hw, const u64 *ops, u32 count)
{
	struct lkpi_wifi_hw *w = lkpi_wifi_of(hw);
	u32 i;
	int rc;

	if (!w->state.registered)
		return LKPI80211_EPROTO;
	for (i = 0; i < count; i++) {
		rc = lkpi_wifi_op(w, ops[i] & MACPLAN_OP_MASK, ops[i] >> MACPLAN_ARG_SHIFT);
		if (rc)
			return rc;
	}
	return 0;
}
