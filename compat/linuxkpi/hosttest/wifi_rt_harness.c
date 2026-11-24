#include "wifi.h"
#include <linux/dma-mapping.h>
#include <linux/timer.h>
#include <linux/workqueue.h>
#include <linux/scatterlist.h>
#include <linux/firmware.h>
#include <linux/delay.h>
#include <linux/timekeeping.h>
#include <osum/osum_if.h>

#define SYS_WRITE 1
#define SYS_EXIT 60
#define TEST_DELAY 5
#define TEST_BYTES 256
#define ALIGNED_ROUNDS 24
#define TEST_FRAME_BYTES 4096
#define TEST_FW_BYTES 64
#define TEST_NS_PER_MS 1000000ULL
#define TEST_ABSORBED_JIFFIES 9
#define LKPI_REAL_EPOCH_SECONDS_MIN 1700000000LL

int __popcountdi2(long long value);
int __popcountsi2(int value);

static u32 checks, failures, work_runs, timer_runs, devres_released, fw_requests, fw_frees;
static u64 fake_clock_ns;
static u8 fw_frame[TEST_FRAME_BYTES] __attribute__((aligned(TEST_FRAME_BYTES)));
static const u8 fw_payload[TEST_FW_BYTES] = { 0xde, 0xad, 0xbe, 0xef };
static const u8 fw_hash[32] = { 1 };
static unsigned char fw_hash_seen;

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

u64 k_clock_ns(void)
{
	return fake_clock_ns;
}

u64 k_frames(u64 count)
{
	return count == 1 ? (u64)(unsigned long)fw_frame : 0;
}

void k_frames_free(u64 addr, u64 count)
{
	(void)count;
	if (addr == (u64)(unsigned long)fw_frame)
		fw_frees++;
}

u64 k_fwreq(const char *name, const unsigned char *hash, u64 dst, u64 cap)
{
	fw_requests++;
	fw_hash_seen = hash ? hash[0] : 0;
	if (name[0] != 'f' || cap < TEST_FW_BYTES)
		return 0;
	memcpy((void *)(unsigned long)dst, fw_payload, TEST_FW_BYTES);
	return TEST_FW_BYTES;
}

int _printk(const char *fmt, ...)
{
	(void)fmt;
	return 0;
}

int vsnprintf(char *buf, size_t size, const char *fmt, va_list args)
{
	(void)buf;
	(void)size;
	(void)fmt;
	(void)args;
	return -1;
}

int strcmp(const char *a, const char *b)
{
	for (; *a && *a == *b; a++, b++)
		;
	return (unsigned char)*a - (unsigned char)*b;
}

static void count_release(void *payload)
{
	(void)payload;
	devres_released++;
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

static void aligned_stress(void)
{
	void *keep[ALIGNED_ROUNDS];
	void *small[ALIGNED_ROUNDS];
	bool ok = true;
	size_t before = lkpi_heap_used();
	int i;

	for (i = 0; i < ALIGNED_ROUNDS; i++) {
		keep[i] = lkpi_alloc_aligned(64 + 100 * i, PAGE_SIZE);
		small[i] = kzalloc(24 + i, GFP_KERNEL);
		ok = ok && keep[i] && small[i] && ((unsigned long)keep[i] & (PAGE_SIZE - 1)) == 0;
	}
	check(ok, "aligned and plain allocations interleave, all aligned ones page aligned");
	for (i = 0; i < ALIGNED_ROUNDS; i++) {
		kfree(keep[i]);
		kfree(small[i]);
	}
	check(lkpi_heap_used() == before, "aligned blocks coalesce back to the original heap use");
}

static void dma_paths(void)
{
	dma_addr_t handle = 0;
	u8 *buf = dma_alloc_coherent(NULL, TEST_BYTES, &handle, GFP_KERNEL);
	dma_addr_t big_handle = 0;
	u8 *big;
	struct page *page = alloc_pages(GFP_KERNEL, 1);

	check(buf && handle == (dma_addr_t)(unsigned long)buf && buf[TEST_BYTES - 1] == 0, "coherent buffer zeroed and mapped");
	check((handle & (PAGE_SIZE - 1)) == 0, "small coherent buffer is page aligned");
	check(dma_map_single(NULL, buf, TEST_BYTES, DMA_TO_DEVICE) == handle, "single mapping equals coherent address");
	check(dma_mapping_error(NULL, DMA_MAPPING_ERROR) && !dma_mapping_error(NULL, handle), "mapping error detected");
	check(dma_set_mask_and_coherent(NULL, ~0ULL) == 0 && dma_set_mask(NULL, 0) != 0, "dma mask accepted and refused");
	dma_free_coherent(NULL, TEST_BYTES, buf, handle);
	big = dma_alloc_coherent(NULL, PAGE_SIZE, &big_handle, GFP_KERNEL);
	check(big && (big_handle & (PAGE_SIZE - 1)) == 0 && big[PAGE_SIZE - 1] == 0, "page-sized coherent buffer is page aligned and zeroed");
	dma_free_coherent(NULL, PAGE_SIZE, big, big_handle);
	check(page && page_address(page) && page_count(page) == 1, "page allocated with one reference");
	check(page && ((unsigned long)page_address(page) & (PAGE_SIZE - 1)) == 0, "allocated page is page aligned");
	aligned_stress();
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

static void time_paths(void)
{
	u64 before;
	unsigned long j0;

	before = ktime_get_ns();
	fake_clock_ns = before + 50 * TEST_NS_PER_MS;
	check(ktime_get_ns() == fake_clock_ns, "kernel clock ahead of shim time wins");
	check(ktime_get_boottime_ns() == ktime_get_ns(), "boottime equals monotonic");
	check(ktime_get_real_seconds() > LKPI_REAL_EPOCH_SECONDS_MIN, "real time sits on top of the epoch base");
	j0 = jiffies;
	fake_clock_ns = ktime_get_ns() + 40 * TEST_NS_PER_MS;
	msleep(1);
	check(jiffies >= j0 + TEST_ABSORBED_JIFFIES, "sleep absorbs elapsed kernel time into jiffies");
	check(ktime_get_ns() >= fake_clock_ns, "shim time has caught up with the kernel clock");
	j0 = jiffies;
	udelay(1);
	check(jiffies == j0, "short delay stays below one jiffy");
	before = ktime_get_ns();
	mdelay(10);
	check(ktime_get_ns() >= before + 10 * TEST_NS_PER_MS, "delay advances virtual time without kernel time");
	before = ktime_get_ns();
	check(ktime_get_ns() >= before, "time never runs backwards");
}

static void sg_paths(void)
{
	struct scatterlist a[2], b[2];
	struct page *page = alloc_pages(GFP_KERNEL, 0);
	u8 data[TEST_BYTES];
	u8 *mem;
	u32 i;

	sg_init_table(a, 2);
	sg_init_table(b, 2);
	check(sg_nents(a) == 2 && sg_nents(b) == 2, "sg table counts its entries");
	sg_set_page(&a[0], page, 100, 0);
	sg_set_page(&b[0], page, 100, 300);
	sg_set_page(&b[1], page, 50, 500);
	sg_chain(a, 2, b);
	check(sg_next(&a[0]) == &b[0] && sg_next(&b[1]) == NULL, "sg_next follows the chain and ends");
	check(sg_nents(a) == 3, "chained table counts through the link");
	for (i = 0; i < TEST_BYTES; i++)
		data[i] = i;
	check(sg_pcopy_from_buffer(a, 3, data, 200, 10) == 200, "sg copy honours the skip and the buffer");
	mem = page_address(page);
	check(mem[9] == 0 && mem[10] == 0 && mem[99] == 89 && mem[300] == 90 && mem[399] == 189 && mem[500] == 190,
	      "sg copy lands across the chain");
	check(sg_pcopy_from_buffer(a, 3, data, 20, 110) == 20, "sg copy skips whole entries");
	check(mem[111] == 0 && mem[309] == 99 && mem[310] == 0 && mem[329] == 19 && mem[330] == 120, "skipped bytes stay and the rest lands after the skip");
	__free_pages(page, 0);
}

static void devres_paths(void)
{
	struct device dev1, dev2;
	void *p1, *p2, *p3;

	memset(&dev1, 0, sizeof(dev1));
	memset(&dev2, 0, sizeof(dev2));
	p1 = lkpi_devres_alloc(&dev1, 32, count_release);
	p2 = lkpi_devres_alloc(&dev2, 32, count_release);
	p3 = devm_kzalloc(&dev1, 16, GFP_KERNEL);
	check(p1 && p2 && p3 && p3 != p1, "devres allocations succeed");
	lkpi_devres_release(&dev1);
	check(devres_released == 1, "release runs the callback of that device only");
	lkpi_devres_release(&dev1);
	check(devres_released == 1, "second release of the same device is a no-op");
	lkpi_devres_release(&dev2);
	check(devres_released == 2, "other device released on its own call");
}

static void firmware_paths(void)
{
	const struct firmware *fw = NULL;
	struct device dev;

	memset(&dev, 0, sizeof(dev));
	check(request_firmware(&fw, "fw.bin", &dev) == -ENOENT && !fw, "unregistered firmware is refused");
	check(lkpi_firmware_load("fw.bin", fw_hash, TEST_FW_BYTES) == 0 && fw_requests == 1 && fw_hash_seen == 1, "kernel serves firmware with the pinned hash");
	check(request_firmware(&fw, "fw.bin", &dev) == 0 && fw && fw->size == TEST_FW_BYTES, "firmware found after the load");
	check(fw && ((const u8 *)fw->data)[0] == 0xde && ((const u8 *)fw->data)[3] == 0xef, "firmware bytes are the served ones");
	release_firmware(fw);
	check(lkpi_firmware_load("bad.bin", fw_hash, TEST_FW_BYTES) == -ENOENT && fw_frees == 1, "refused firmware frees its frames");
	lkpi_firmware_clear();
	check(fw_frees == 2 && request_firmware(&fw, "fw.bin", &dev) == -ENOENT, "clear frees frames and forgets names");
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
	time_paths();
	sg_paths();
	devres_paths();
	firmware_paths();
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
