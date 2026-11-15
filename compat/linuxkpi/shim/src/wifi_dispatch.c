#include "wifi.h"

#define KEY_CIPHER_CCMP 0x000FAC04
#define KEY_BYTES 16
#define EDCA_CW_MIN 15
#define EDCA_CW_MAX 1023
#define EDCA_AIFS 2
#define FLUSH_ALL_QUEUES 0xFFFFFFFFu

static int op_start(struct lkpi_wifi_hw *w)
{
	int rc;

	if (w->state.started)
		return LKPI80211_EPROTO;
	rc = w->hw.ops->start(&w->hw);
	if (!rc)
		w->state.started = 1;
	return rc;
}

static int op_stop(struct lkpi_wifi_hw *w)
{
	if (!w->state.started || w->state.iface)
		return LKPI80211_EPROTO;
	w->hw.ops->stop(&w->hw, false);
	w->state.started = 0;
	return 0;
}

static int op_add_interface(struct lkpi_wifi_hw *w)
{
	int rc;

	if (!w->state.started || w->state.iface)
		return LKPI80211_EPROTO;
	rc = w->hw.ops->add_interface(&w->hw, &w->vif.vif);
	if (!rc)
		w->state.iface = 1;
	return rc;
}

static int op_remove_interface(struct lkpi_wifi_hw *w)
{
	if (!w->state.iface || w->state.sta_state != IEEE80211_STA_NOTEXIST || w->state.chanctx)
		return LKPI80211_EPROTO;
	w->hw.ops->remove_interface(&w->hw, &w->vif.vif);
	w->state.iface = 0;
	return 0;
}

static int op_hw_scan(struct lkpi_wifi_hw *w)
{
	struct ieee80211_scan_request req = { 0 };
	int rc;

	if (!w->state.iface || w->state.scanning)
		return LKPI80211_EPROTO;
	if (!w->hw.ops->hw_scan)
		return LKPI80211_ENOSYS;
	rc = w->hw.ops->hw_scan(&w->hw, &w->vif.vif, &req);
	if (!rc)
		w->state.scanning = 1;
	return rc;
}

static int op_cancel_hw_scan(struct lkpi_wifi_hw *w)
{
	if (!w->state.scanning)
		return LKPI80211_EPROTO;
	if (w->hw.ops->cancel_hw_scan)
		w->hw.ops->cancel_hw_scan(&w->hw, &w->vif.vif);
	w->state.scanning = 0;
	return 0;
}

static int op_add_chanctx(struct lkpi_wifi_hw *w)
{
	int rc = 0;

	if (!w->state.iface || w->state.chanctx)
		return LKPI80211_EPROTO;
	if (w->hw.ops->add_chanctx)
		rc = w->hw.ops->add_chanctx(&w->hw, &w->chanctx.ctx);
	if (!rc)
		w->state.chanctx = 1;
	return rc;
}

static int op_remove_chanctx(struct lkpi_wifi_hw *w)
{
	if (!w->state.chanctx || w->state.assigned)
		return LKPI80211_EPROTO;
	if (w->hw.ops->remove_chanctx)
		w->hw.ops->remove_chanctx(&w->hw, &w->chanctx.ctx);
	w->state.chanctx = 0;
	return 0;
}

static int op_assign(struct lkpi_wifi_hw *w)
{
	int rc = 0;

	if (!w->state.chanctx || w->state.assigned)
		return LKPI80211_EPROTO;
	if (w->hw.ops->assign_vif_chanctx)
		rc = w->hw.ops->assign_vif_chanctx(&w->hw, &w->vif.vif, &w->vif.vif.bss_conf, &w->chanctx.ctx);
	if (!rc)
		w->state.assigned = 1;
	return rc;
}

static int op_unassign(struct lkpi_wifi_hw *w)
{
	if (!w->state.assigned || w->state.sta_state != IEEE80211_STA_NOTEXIST)
		return LKPI80211_EPROTO;
	if (w->hw.ops->unassign_vif_chanctx)
		w->hw.ops->unassign_vif_chanctx(&w->hw, &w->vif.vif, &w->vif.vif.bss_conf, &w->chanctx.ctx);
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
	rc = w->hw.ops->sta_state(&w->hw, &w->vif.vif, &w->sta.sta, old, arg);
	if (!rc)
		w->state.sta_state = arg;
	return rc;
}

static int op_prep_tx(struct lkpi_wifi_hw *w, bool complete)
{
	struct ieee80211_prep_tx_info info = { 0 };

	if (!w->state.assigned)
		return LKPI80211_EPROTO;
	if (complete && w->hw.ops->mgd_complete_tx)
		w->hw.ops->mgd_complete_tx(&w->hw, &w->vif.vif, &info);
	if (!complete && w->hw.ops->mgd_prepare_tx)
		w->hw.ops->mgd_prepare_tx(&w->hw, &w->vif.vif, &info);
	return 0;
}

static int op_bss_info(struct lkpi_wifi_hw *w, u64 arg)
{
	u64 changed = 0;

	if (!w->state.assigned)
		return LKPI80211_EPROTO;
	if (arg == MACPLAN_BSS_BSSID)
		changed = BSS_CHANGED_BSSID;
	else if (arg == MACPLAN_BSS_QOS) {
		changed = BSS_CHANGED_QOS;
		w->vif.vif.bss_conf.qos = true;
	} else
		return LKPI80211_EINVAL;
	if (w->hw.ops->bss_info_changed)
		w->hw.ops->bss_info_changed(&w->hw, &w->vif.vif, &w->vif.vif.bss_conf, changed);
	return 0;
}

static int op_vif_cfg(struct lkpi_wifi_hw *w)
{
	if (!w->state.assigned)
		return LKPI80211_EPROTO;
	w->vif.vif.bss_conf.assoc = w->state.sta_state >= IEEE80211_STA_ASSOC;
	if (w->hw.ops->vif_cfg_changed)
		w->hw.ops->vif_cfg_changed(&w->hw, &w->vif.vif, BSS_CHANGED_ASSOC);
	return 0;
}

static int op_conf_tx(struct lkpi_wifi_hw *w, u64 arg)
{
	struct ieee80211_tx_queue_params params = { 0, EDCA_CW_MIN, EDCA_CW_MAX, EDCA_AIFS };

	if (arg >= IEEE80211_NUM_ACS || !w->state.assigned)
		return LKPI80211_EPROTO;
	if (!w->hw.ops->conf_tx)
		return 0;
	return w->hw.ops->conf_tx(&w->hw, &w->vif.vif, 0, arg, &params);
}

static int op_set_key(struct lkpi_wifi_hw *w, u64 arg)
{
	bool pairwise = arg == MACPLAN_KEY_SET_PAIRWISE || arg == MACPLAN_KEY_DEL_PAIRWISE;
	bool set = arg == MACPLAN_KEY_SET_PAIRWISE || arg == MACPLAN_KEY_SET_GROUP;
	struct ieee80211_key_conf *key = pairwise ? &w->pairwise : &w->group;
	int rc;

	if (arg < MACPLAN_KEY_SET_PAIRWISE || arg > MACPLAN_KEY_DEL_GROUP || !w->hw.ops->set_key)
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
	rc = w->hw.ops->set_key(&w->hw, set ? SET_KEY : DISABLE_KEY, &w->vif.vif,
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
	if (w->hw.ops->flush)
		w->hw.ops->flush(&w->hw, &w->vif.vif, FLUSH_ALL_QUEUES, false);
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
