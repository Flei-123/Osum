#include <osum/lkpi80211.h>
#include <osum/macplan_ops.h>

#define LOG_MAX 64
#define LINE_MAX_BYTES 1024
#define SYS_READ 0
#define SYS_WRITE 1
#define SYS_EXIT 60
#define MAX_TOKENS 40
#define FRAME_BYTES 64
#define HEADROOM 32
#define EV_SCAN_DONE 3

struct log_entry {
	u32 op;
	u64 arg;
};

struct fake {
	struct log_entry log[LOG_MAX];
	u32 count;
	u32 sta_state;
	u32 keys_pairwise;
	u32 keys_group;
	u32 contract_errors;
	u32 tx_calls;
	u32 vif_assoc_wrong;
	int fail_op;
	int fail_rc;
};

static struct fake fake;
static struct ieee80211_vif *seen_vif;
static u32 rx_seen, tx_acked, tx_dropped, scan_done_seen, beacon_loss_seen, conn_loss_seen, restart_seen;

static long sys3(long nr, long a, long b, long c)
{
	long ret;

	__asm__ volatile("syscall" : "=a"(ret) : "0"(nr), "D"(a), "S"(b), "d"(c) : "rcx", "r11", "memory");
	return ret;
}

static void out(const char *s)
{
	u32 n = 0;

	while (s[n])
		n++;
	sys3(SYS_WRITE, 1, (long)s, n);
}

static void out_num(const char *label, u64 v)
{
	char buf[32];
	int i = 31;

	buf[i] = 0;
	if (!v)
		buf[--i] = '0';
	while (v) {
		buf[--i] = '0' + v % 10;
		v /= 10;
	}
	out(label);
	out(buf + i);
	out("\n");
}

static void record(u32 op, u64 arg)
{
	if (fake.count < LOG_MAX) {
		fake.log[fake.count].op = op;
		fake.log[fake.count].arg = arg;
	}
	fake.count++;
}

static int op_fails(u32 op)
{
	return fake.fail_op == (int)op ? fake.fail_rc : 0;
}

static int f_start(struct ieee80211_hw *hw)
{
	record(MACPLAN_OP_START, 0);
	return op_fails(MACPLAN_OP_START);
}

static void f_stop(struct ieee80211_hw *hw, bool suspend)
{
	record(MACPLAN_OP_STOP, 0);
}

static int f_add_interface(struct ieee80211_hw *hw, struct ieee80211_vif *vif)
{
	seen_vif = vif;
	record(MACPLAN_OP_ADD_INTERFACE, 0);
	return 0;
}

static void f_remove_interface(struct ieee80211_hw *hw, struct ieee80211_vif *vif)
{
	record(MACPLAN_OP_REMOVE_INTERFACE, 0);
}

static int f_hw_scan(struct ieee80211_hw *hw, struct ieee80211_vif *vif, struct ieee80211_scan_request *req)
{
	record(MACPLAN_OP_HW_SCAN, 0);
	return 0;
}

static void f_cancel_hw_scan(struct ieee80211_hw *hw, struct ieee80211_vif *vif)
{
	record(MACPLAN_OP_CANCEL_HW_SCAN, 0);
}

static int f_add_chanctx(struct ieee80211_hw *hw, struct ieee80211_chanctx_conf *ctx)
{
	record(MACPLAN_OP_ADD_CHANCTX, 0);
	return 0;
}

static void f_remove_chanctx(struct ieee80211_hw *hw, struct ieee80211_chanctx_conf *ctx)
{
	record(MACPLAN_OP_REMOVE_CHANCTX, 0);
}

static int f_assign(struct ieee80211_hw *hw, struct ieee80211_vif *vif, struct ieee80211_bss_conf *conf,
		    struct ieee80211_chanctx_conf *ctx)
{
	record(MACPLAN_OP_ASSIGN_VIF_CHANCTX, 0);
	return 0;
}

static void f_unassign(struct ieee80211_hw *hw, struct ieee80211_vif *vif, struct ieee80211_bss_conf *conf,
		       struct ieee80211_chanctx_conf *ctx)
{
	record(MACPLAN_OP_UNASSIGN_VIF_CHANCTX, 0);
}

static int f_sta_state(struct ieee80211_hw *hw, struct ieee80211_vif *vif, struct ieee80211_sta *sta,
		       enum ieee80211_sta_state old_state, enum ieee80211_sta_state new_state)
{
	if (old_state != fake.sta_state || (new_state != old_state + 1 && new_state + 1 != old_state))
		fake.contract_errors++;
	record(MACPLAN_OP_STA_STATE, new_state);
	fake.sta_state = new_state;
	return op_fails(MACPLAN_OP_STA_STATE);
}

static void f_prepare(struct ieee80211_hw *hw, struct ieee80211_vif *vif, struct ieee80211_prep_tx_info *info)
{
	record(MACPLAN_OP_MGD_PREPARE_TX, 0);
}

static void f_complete(struct ieee80211_hw *hw, struct ieee80211_vif *vif, struct ieee80211_prep_tx_info *info)
{
	record(MACPLAN_OP_MGD_COMPLETE_TX, 0);
}

static void f_bss_info(struct ieee80211_hw *hw, struct ieee80211_vif *vif, struct ieee80211_bss_conf *info,
		       u64 changed)
{
	u64 arg = changed == BSS_CHANGED_BSSID ? MACPLAN_BSS_BSSID : changed == BSS_CHANGED_QOS ? MACPLAN_BSS_QOS : 0xFFFF;

	record(MACPLAN_OP_BSS_INFO_CHANGED, arg);
}

static void f_vif_cfg(struct ieee80211_hw *hw, struct ieee80211_vif *vif, u64 changed)
{
	if (changed != BSS_CHANGED_ASSOC || vif->bss_conf.assoc != (fake.sta_state >= IEEE80211_STA_ASSOC))
		fake.vif_assoc_wrong++;
	record(MACPLAN_OP_VIF_CFG_CHANGED, 0);
}

static int f_conf_tx(struct ieee80211_hw *hw, struct ieee80211_vif *vif, unsigned int link_id, u16 ac,
		     const struct ieee80211_tx_queue_params *params)
{
	if (!params->aifs || !params->cw_min || params->cw_max < params->cw_min)
		fake.contract_errors++;
	record(MACPLAN_OP_CONF_TX, ac);
	return 0;
}

static int f_set_key(struct ieee80211_hw *hw, enum set_key_cmd cmd, struct ieee80211_vif *vif,
		     struct ieee80211_sta *sta, struct ieee80211_key_conf *key)
{
	bool pairwise = key->flags & IEEE80211_KEY_FLAG_PAIRWISE;
	u32 *slot = pairwise ? &fake.keys_pairwise : &fake.keys_group;
	u64 arg;

	if (pairwise != (sta != NULL) || !key->keylen)
		fake.contract_errors++;
	if (cmd == SET_KEY) {
		(*slot)++;
		arg = pairwise ? MACPLAN_KEY_SET_PAIRWISE : MACPLAN_KEY_SET_GROUP;
	} else {
		if (!*slot)
			fake.contract_errors++;
		(*slot)--;
		arg = pairwise ? MACPLAN_KEY_DEL_PAIRWISE : MACPLAN_KEY_DEL_GROUP;
	}
	record(MACPLAN_OP_SET_KEY, arg);
	return 0;
}

static void f_flush(struct ieee80211_hw *hw, struct ieee80211_vif *vif, u32 queues, bool drop)
{
	record(MACPLAN_OP_FLUSH, 0);
}

static void f_tx(struct ieee80211_hw *hw, struct ieee80211_tx_control *control, struct sk_buff *skb)
{
	fake.tx_calls++;
	ieee80211_tx_status_skb(hw, skb);
}

static const struct ieee80211_ops fake_ops = {
	.tx = f_tx, .start = f_start, .stop = f_stop, .add_interface = f_add_interface,
	.remove_interface = f_remove_interface, .hw_scan = f_hw_scan, .cancel_hw_scan = f_cancel_hw_scan,
	.add_chanctx = f_add_chanctx, .remove_chanctx = f_remove_chanctx, .assign_vif_chanctx = f_assign,
	.unassign_vif_chanctx = f_unassign, .sta_state = f_sta_state, .mgd_prepare_tx = f_prepare,
	.mgd_complete_tx = f_complete, .bss_info_changed = f_bss_info, .vif_cfg_changed = f_vif_cfg,
	.conf_tx = f_conf_tx, .set_key = f_set_key, .flush = f_flush,
};

static const struct ieee80211_ops bare_ops = { .tx = f_tx };

static void up_rx(void *ctx, struct sk_buff *skb)
{
	rx_seen++;
	kfree_skb(skb);
}

static void up_tx_status(void *ctx, struct sk_buff *skb, bool acked)
{
	if (acked)
		tx_acked++;
	else
		tx_dropped++;
	kfree_skb(skb);
}

static void up_scan_done(void *ctx, bool aborted) { scan_done_seen++; }
static void up_beacon_loss(void *ctx) { beacon_loss_seen++; }
static void up_conn_loss(void *ctx) { conn_loss_seen++; }
static void up_restart(void *ctx) { restart_seen++; }

static const struct lkpi80211_upcalls upcalls = {
	up_rx, up_tx_status, up_scan_done, up_beacon_loss, up_conn_loss, up_restart,
};

static u32 checks, failures;

static void zero(void *ptr, u32 size)
{
	u8 *p = ptr;

	while (size--)
		*p++ = 0;
}

static void check(int ok, const char *what)
{
	checks++;
	if (ok)
		return;
	failures++;
	out("FAIL ");
	out(what);
	out("\n");
}

static int read_line(char *buf)
{
	u32 n = 0;
	char c;

	while (n < LINE_MAX_BYTES - 1 && sys3(SYS_READ, 0, (long)&c, 1) == 1) {
		if (c == '\n')
			break;
		buf[n++] = c;
	}
	buf[n] = 0;
	return n;
}

static int tokenize(char *line, long *tok)
{
	int n = 0;
	char *p = line;

	while (*p && n < MAX_TOKENS) {
		long v = 0;
		int neg = 0;

		while (*p == ' ')
			p++;
		if (*p == '-') {
			neg = 1;
			p++;
		}
		if (*p < '0' || *p > '9')
			break;
		while (*p >= '0' && *p <= '9')
			v = v * 10 + (*p++ - '0');
		tok[n++] = neg ? -v : v;
	}
	return n;
}

static u64 norm(u32 op, u64 arg)
{
	return op == MACPLAN_OP_VIF_CFG_CHANGED ? 0 : arg;
}

static int log_matches(const long *want, int n)
{
	int i;

	if (fake.count != (u32)n)
		return 0;
	for (i = 0; i < n; i++) {
		u32 op = want[i] & MACPLAN_OP_MASK;
		u64 arg = (u64)want[i] >> MACPLAN_ARG_SHIFT;

		if (fake.log[i].op != op || fake.log[i].arg != norm(op, arg))
			return 0;
	}
	return 1;
}

static u32 expected_sta;

static void track_expected(const long *want, int n)
{
	int i;

	for (i = 0; i < n; i++)
		if ((want[i] & MACPLAN_OP_MASK) == MACPLAN_OP_STA_STATE)
			expected_sta = (u64)want[i] >> MACPLAN_ARG_SHIFT;
}

static void traffic(struct ieee80211_hw *hw)
{
	struct sk_buff *skb = alloc_skb(FRAME_BYTES + HEADROOM, 0);
	struct lkpi80211_state st;

	lkpi80211_state_get(hw, &st);
	if (!skb)
		return;
	skb_reserve(skb, HEADROOM);
	skb_put(skb, FRAME_BYTES);
	if (st.started) {
		lkpi80211_tx(hw, skb);
		skb = alloc_skb(FRAME_BYTES, 0);
		if (skb)
			ieee80211_rx_napi(hw, NULL, skb, NULL);
	} else
		kfree_skb(skb);
}

static void replay(struct ieee80211_hw *hw)
{
	char line[LINE_MAX_BYTES];
	long tok[MAX_TOKENS];
	u32 events = 0, applied = 0, refused = 0, last_phase_ok = 1;

	while (read_line(line)) {
		int n = tokenize(line + 3, tok);
		struct lkpi80211_state st;
		int rc;
		u64 ops[MAX_TOKENS];
		int i;

		if (n < 2)
			continue;
		events++;
		if (tok[1] < 0) {
			refused++;
			continue;
		}
		fake.count = 0;
		for (i = 0; i < tok[1]; i++)
			ops[i] = tok[2 + i];
		rc = lkpi80211_apply(hw, ops, tok[1]);
		applied++;
		if (tok[0] == EV_SCAN_DONE) {
			struct cfg80211_scan_info info = { false };

			ieee80211_scan_completed(hw, &info);
		}
		if ((rc || !log_matches(tok + 2, tok[1])) && last_phase_ok) {
			out_num("mismatch at event ", events);
			out_num("rc=", (u64)(long)rc);
			out_num("logged=", fake.count);
			out_num("expected=", tok[1]);
			last_phase_ok = 0;
		}
		track_expected(tok + 2, tok[1]);
		lkpi80211_state_get(hw, &st);
		if (st.sta_state != expected_sta || fake.sta_state != expected_sta)
			last_phase_ok = 0;
		if (st.started && st.iface && (events % 7) == 0)
			traffic(hw);
	}
	check(last_phase_ok, "fuzz replay: driver op log equals planner ops, sta state tracked");
	check(applied > 3000, "fuzz replay: enough accepted events");
	check(fake.contract_errors == 0, "fuzz replay: fake driver saw no contract violation");
	check(fake.vif_assoc_wrong == 0, "fuzz replay: vif assoc flag consistent");
	out_num("events=", events);
	out_num("applied=", applied);
	out_num("refused=", refused);
	out_num("tx_calls=", fake.tx_calls);
	out_num("rx_seen=", rx_seen);
}

static void refusals(struct ieee80211_hw *hw)
{
	struct lkpi80211_state st;
	u64 sta_auth[1] = { MACPLAN_OP_STA_STATE | (IEEE80211_STA_AUTH << MACPLAN_ARG_SHIFT) };
	u64 add_ctx[1] = { MACPLAN_OP_ADD_CHANCTX };
	u64 start[1] = { MACPLAN_OP_START };
	u64 up[2] = { MACPLAN_OP_START, MACPLAN_OP_ADD_INTERFACE };
	u64 bad[1] = { 99 };
	u64 chain[3] = { MACPLAN_OP_ADD_CHANCTX, MACPLAN_OP_ASSIGN_VIF_CHANCTX,
			 MACPLAN_OP_STA_STATE | (IEEE80211_STA_AUTH << MACPLAN_ARG_SHIFT) };
	u64 key[1] = { MACPLAN_OP_SET_KEY | (MACPLAN_KEY_SET_PAIRWISE << MACPLAN_ARG_SHIFT) };
	u64 down[5] = { MACPLAN_OP_UNASSIGN_VIF_CHANCTX, MACPLAN_OP_REMOVE_CHANCTX,
			MACPLAN_OP_REMOVE_INTERFACE, MACPLAN_OP_STOP, MACPLAN_OP_STOP };

	check(lkpi80211_apply(hw, sta_auth, 1) == LKPI80211_EPROTO, "refusal: sta_state before start/chanctx");
	check(lkpi80211_apply(hw, add_ctx, 1) == LKPI80211_EPROTO, "refusal: chanctx without interface");
	check(lkpi80211_apply(hw, up, 2) == 0, "start + add_interface accepted");
	check(lkpi80211_apply(hw, start, 1) == LKPI80211_EPROTO, "refusal: double start");
	check(lkpi80211_apply(hw, bad, 1) == LKPI80211_EINVAL, "refusal: unknown op");
	check(lkpi80211_apply(hw, chain, 3) == LKPI80211_EPROTO, "refusal: sta_state skipping NONE stops the chain");
	lkpi80211_state_get(hw, &st);
	check(st.chanctx && st.assigned && st.sta_state == 0, "chain applied up to the refused step");
	check(lkpi80211_apply(hw, key, 1) == LKPI80211_EPROTO, "refusal: key before association");
	fake.count = 0;
	fake.fail_op = MACPLAN_OP_STA_STATE;
	fake.fail_rc = -5;
	chain[2] = MACPLAN_OP_STA_STATE | (IEEE80211_STA_NONE << MACPLAN_ARG_SHIFT);
	check(lkpi80211_apply(hw, chain + 2, 1) == -5, "driver error is returned");
	lkpi80211_state_get(hw, &st);
	check(st.sta_state == 0, "failed sta_state does not advance the shim state");
	fake.fail_op = 0;
	check(lkpi80211_apply(hw, down, 5) == LKPI80211_EPROTO, "refusal: second stop after ordered teardown");
}

static void bare_driver(void)
{
	struct ieee80211_hw *hw = ieee80211_alloc_hw(16, &bare_ops);

	check(hw != NULL, "bare driver allocates");
	check(ieee80211_register_hw(hw) == LKPI80211_EINVAL, "register refuses driver without mandatory ops");
	ieee80211_free_hw(hw);
	check(ieee80211_alloc_hw(9000, &fake_ops) == NULL, "oversized priv refused");
}

static void upcall_paths(struct ieee80211_hw *hw)
{
	struct cfg80211_scan_info info = { false };
	struct sk_buff *skb;
	struct lkpi80211_state st;
	u64 up[3] = { MACPLAN_OP_START, MACPLAN_OP_ADD_INTERFACE, MACPLAN_OP_HW_SCAN };
	u64 stop_scan[1] = { MACPLAN_OP_CANCEL_HW_SCAN };

	check(lkpi80211_apply(hw, up, 3) == 0, "upcalls: start, interface, scan");
	ieee80211_scan_completed(hw, &info);
	check(scan_done_seen == 1, "upcall scan_done delivered once");
	ieee80211_scan_completed(hw, &info);
	check(scan_done_seen == 1, "spurious scan_completed ignored");
	lkpi80211_state_get(hw, &st);
	check(!st.scanning, "scan flag cleared by completion");
	check(lkpi80211_apply(hw, stop_scan, 1) == LKPI80211_EPROTO, "cancel_hw_scan without scan refused");
	skb = alloc_skb(FRAME_BYTES, 0);
	ieee80211_free_txskb(hw, skb);
	check(tx_dropped == 1, "free_txskb reports an unacked frame");
	skb = alloc_skb(FRAME_BYTES, 0);
	ieee80211_rx_napi(hw, NULL, skb, NULL);
	check(rx_seen > 0, "rx upcall delivered");
}

static void skb_pool(void)
{
	struct sk_buff *held[80];
	u32 got = 0, i, pool = lkpi_skb_pool_size(), errors = lkpi_skb_error_count();
	struct sk_buff *skb;
	struct sk_buff_head q;

	for (i = 0; i < 80; i++) {
		held[i] = alloc_skb(128, 0);
		if (held[i])
			got++;
	}
	check(got == lkpi_skb_pool_size() - (pool - got) && got <= pool, "pool hands out at most its size");
	check(lkpi_skb_free_count() == pool - got, "free counter follows allocations");
	check(lkpi_skb_error_count() > errors, "exhaustion is counted");
	for (i = 0; i < 80; i++)
		if (held[i])
			kfree_skb(held[i]);
	check(lkpi_skb_free_count() == pool, "every skb returned");
	errors = lkpi_skb_error_count();
	skb = alloc_skb(100, 0);
	kfree_skb(skb);
	kfree_skb(skb);
	check(lkpi_skb_error_count() == errors + 1 && lkpi_skb_free_count() == pool, "double free detected, no counter inflation");
	skb = alloc_skb(100, 0);
	skb_reserve(skb, 20);
	check(skb_headroom(skb) == 20 && skb_tailroom(skb) == 80, "reserve moves headroom");
	check(skb_put(skb, 60) != NULL && skb->len == 60 && skb_tailroom(skb) == 20, "put grows len");
	check(skb_put(skb, 21) == NULL, "put beyond end refused");
	check(skb_push(skb, 20) != NULL && skb->len == 80 && skb_headroom(skb) == 0, "push uses headroom");
	check(skb_push(skb, 1) == NULL, "push beyond head refused");
	check(skb_pull(skb, 80) != NULL && skb->len == 0, "pull shrinks len");
	check(skb_pull(skb, 1) == NULL, "pull beyond len refused");
	skb_queue_head_init(&q);
	__skb_queue_tail(&q, skb);
	check(skb_queue_len(&q) == 1 && __skb_dequeue(&q) == skb && __skb_dequeue(&q) == NULL, "queue order and empty dequeue");
	kfree_skb(skb);
	check(alloc_skb(4096, 0) == NULL, "oversized skb refused");
	check(lkpi_skb_free_count() == pool, "pool whole after the tests");
}

static void upcall_guards(struct ieee80211_hw *hw)
{
	struct lkpi80211_state st;
	u64 join[5] = { MACPLAN_OP_ADD_CHANCTX, MACPLAN_OP_ASSIGN_VIF_CHANCTX,
			MACPLAN_OP_BSS_INFO_CHANGED | (MACPLAN_BSS_BSSID << MACPLAN_ARG_SHIFT),
			MACPLAN_OP_STA_STATE | (IEEE80211_STA_NONE << MACPLAN_ARG_SHIFT),
			MACPLAN_OP_STA_STATE | (IEEE80211_STA_AUTH << MACPLAN_ARG_SHIFT) };
	u64 unassign[1] = { MACPLAN_OP_UNASSIGN_VIF_CHANCTX };
	u64 assoc[1] = { MACPLAN_OP_STA_STATE | (IEEE80211_STA_ASSOC << MACPLAN_ARG_SHIFT) };

	check(lkpi80211_apply(hw, join, 5) == 0, "join to AUTH accepted");
	lkpi80211_state_get(hw, &st);
	check(st.sta_state == IEEE80211_STA_AUTH, "shim sta state AUTH");
	ieee80211_beacon_loss(seen_vif);
	check(beacon_loss_seen == 0, "beacon loss before association ignored");
	ieee80211_connection_loss(seen_vif);
	check(conn_loss_seen == 1, "connection loss at AUTH delivered");
	check(lkpi80211_apply(hw, unassign, 1) == LKPI80211_EPROTO, "refusal: unassign while the station exists");
	check(lkpi80211_apply(hw, assoc, 1) == 0, "assoc step accepted");
	ieee80211_beacon_loss(seen_vif);
	check(beacon_loss_seen == 1, "beacon loss when associated delivered");
	ieee80211_restart_hw(hw);
	check(restart_seen == 1, "restart upcall delivered");
}

int main_entry(void)
{
	struct ieee80211_hw *hw = ieee80211_alloc_hw(64, &fake_ops);
	u32 pool_before = lkpi_skb_free_count();

	check(hw != NULL, "hw allocated");
	hw->sta_data_size = 32;
	check(ieee80211_register_hw(hw) == 0, "hw registered");
	lkpi80211_set_upcalls(hw, &upcalls, NULL);
	skb_pool();
	bare_driver();
	refusals(hw);
	ieee80211_unregister_hw(hw);
	ieee80211_free_hw(hw);

	hw = ieee80211_alloc_hw(64, &fake_ops);
	check(ieee80211_register_hw(hw) == 0, "second hw registered");
	lkpi80211_set_upcalls(hw, &upcalls, NULL);
	upcall_paths(hw);
	upcall_guards(hw);
	ieee80211_unregister_hw(hw);
	ieee80211_free_hw(hw);

	zero(&fake, sizeof(fake));
	rx_seen = tx_acked = tx_dropped = scan_done_seen = 0;
	hw = ieee80211_alloc_hw(64, &fake_ops);
	ieee80211_register_hw(hw);
	lkpi80211_set_upcalls(hw, &upcalls, NULL);
	replay(hw);
	ieee80211_unregister_hw(hw);
	ieee80211_free_hw(hw);
	check(lkpi_skb_free_count() == pool_before, "no skb leaked over the whole run");
	out_num("checks=", checks);
	out_num("failures=", failures);
	return failures ? 1 : 0;
}

void _start(void)
{
	sys3(SYS_EXIT, main_entry(), 0, 0);
	for (;;)
		;
}
