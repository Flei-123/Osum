#include "wifi.h"
#include <linux/dma-mapping.h>
#include <linux/timer.h>
#include <linux/workqueue.h>

#define SYS_WRITE 1
#define SYS_EXIT 60
#define TEST_DELAY 5
#define TEST_BYTES 256

int __popcountdi2(long long value);
int __popcountsi2(int value);

static u32 checks, failures, work_runs, timer_runs;

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
	for (; v; v /= 10)
		buf[--i] = '0' + v % 10;
	out(label);
	out(buf + i);
	out("\n");
}

static void check(bool ok, const char *what)
{
	checks++;
	if (ok)
		return;
	failures++;
	out("FAIL ");
	out(what);
	out("\n");
}

static void count_work(struct work_struct *work)
{
	(void)work;
	work_runs++;
}

static void count_timer(struct timer_list *timer)
{
	(void)timer;
	timer_runs++;
}

static void dma_paths(void)
{
	dma_addr_t handle = 0;
	u8 *buf = dma_alloc_coherent(NULL, TEST_BYTES, &handle, GFP_KERNEL);
	struct page *page = alloc_pages(GFP_KERNEL, 1);

	check(buf && handle == (dma_addr_t)(unsigned long)buf && buf[TEST_BYTES - 1] == 0, "coherent buffer zeroed and mapped");
	check(dma_map_single(NULL, buf, TEST_BYTES, DMA_TO_DEVICE) == handle, "single mapping equals coherent address");
	check(dma_mapping_error(NULL, DMA_MAPPING_ERROR) && !dma_mapping_error(NULL, handle), "mapping error detected");
	check(dma_set_mask_and_coherent(NULL, ~0ULL) == 0 && dma_set_mask(NULL, 0) != 0, "dma mask accepted and refused");
	dma_free_coherent(NULL, TEST_BYTES, buf, handle);
	check(page && page_address(page) && page_count(page) == 1, "page allocated with one reference");
	get_page(page);
	check(page_count(page) == 2, "page reference taken");
	put_page(page);
	check(page_count(page) == 1, "page reference dropped");
	__free_pages(page, 1);
	check(get_order(1) == 0 && get_order(PAGE_SIZE) == 0 && get_order(PAGE_SIZE + 1) == 1, "page order");
}

static void work_paths(void)
{
	struct work_struct work;
	struct delayed_work dwork;

	INIT_WORK(&work, count_work);
	check(queue_work(system_wq, &work) && !queue_work(system_wq, &work), "queue_work refuses a queued item");
	flush_workqueue(system_wq);
	check(work_runs == 1, "queued work ran once");
	queue_work(system_wq, &work);
	check(cancel_work_sync(&work) && !cancel_work_sync(&work), "cancelled work reported once");
	lkpi_work_run();
	check(work_runs == 1, "cancelled work never ran");
	INIT_DELAYED_WORK(&dwork, count_work);
	check(queue_delayed_work(system_wq, &dwork, TEST_DELAY), "delayed work queued");
	lkpi_timers_run(TEST_DELAY - 1);
	lkpi_work_run();
	check(work_runs == 1, "delayed work waits for its time");
	lkpi_timers_run(TEST_DELAY);
	lkpi_work_run();
	check(work_runs == 2, "delayed work ran at its time");
	queue_delayed_work(system_wq, &dwork, TEST_DELAY);
	check(cancel_delayed_work(&dwork), "delayed work cancelled");
	lkpi_timers_run(TEST_DELAY * 4);
	lkpi_work_run();
	check(work_runs == 2, "cancelled delayed work never ran");
}

static void timer_paths(void)
{
	struct timer_list timer;

	timer_setup(&timer, count_timer, 0);
	check(!timer_pending(&timer) && mod_timer(&timer, 100) == 0 && timer_pending(&timer), "timer armed");
	check(mod_timer(&timer, 200) == 1, "re-arming reports pending");
	lkpi_timers_run(199);
	check(timer_runs == 0, "timer waits for its time");
	lkpi_timers_run(200);
	check(timer_runs == 1 && !timer_pending(&timer), "timer fired once");
	mod_timer(&timer, 300);
	check(del_timer(&timer) == 1 && del_timer(&timer) == 0, "timer deleted");
	lkpi_timers_run(400);
	check(timer_runs == 1, "deleted timer never fired");
}

static void napi_paths(void)
{
	struct napi_struct napi;

	netif_napi_add(NULL, &napi, NULL);
	check(!napi_schedule(&napi), "disabled napi refuses schedule");
	napi_enable(&napi);
	check(napi_schedule(&napi) && !napi_schedule(&napi), "enabled napi schedules once");
	napi_complete_done(&napi, 0);
	check(napi_schedule(&napi), "napi schedules again after completion");
	napi_disable(&napi);
	check(!napi_schedule(&napi), "disabled napi refuses again");
}

static void skb_paths(void)
{
	struct sk_buff *skb = alloc_skb(TEST_BYTES, GFP_KERNEL);

	check(skb != NULL, "skb allocated");
	check(skb_shinfo(skb)->nr_frags == 0 && skb_shinfo(skb)->frag_list == NULL &&
	      skb_hwtstamps(skb)->hwtstamp == 0 && skb->data_len == 0 && skb->ip_summed == CHECKSUM_NONE,
	      "fresh skb has a null shared info");
	kfree_skb(skb);
}

static void bit_paths(void)
{
	check(__popcountdi2(0) == 0 && __popcountdi2(-1) == 64 && __popcountsi2(0xf0f0) == 8, "popcount helpers");
}

int main_entry(void)
{
	dma_paths();
	work_paths();
	timer_paths();
	napi_paths();
	skb_paths();
	bit_paths();
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
