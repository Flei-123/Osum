#include "wifi.h"
#include <linux/delay.h>
#include <linux/time.h>
#include <linux/timekeeping.h>
#include <osum/osum_if.h>

#define LKPI_REAL_EPOCH_SECONDS 1767225600ULL

volatile unsigned long jiffies;
u64 jiffies_64;
static u64 sub_tick_ns;
static bool advancing;
static u64 kernel_clock_base_ns;
static bool kernel_clock_seen;

static u64 virtual_ns(void)
{
	return (u64)jiffies * LKPI_NS_PER_JIFFY + sub_tick_ns;
}

static u64 kernel_elapsed_ns(void)
{
	u64 now = k_clock_ns();

	if (!kernel_clock_seen) {
		kernel_clock_base_ns = now;
		kernel_clock_seen = true;
	}
	return now - kernel_clock_base_ns;
}

u64 lkpi_time_ns(void)
{
	u64 virt = virtual_ns();
	u64 real = kernel_elapsed_ns();

	return real > virt ? real : virt;
}

void lkpi_time_advance_ns(u64 ns, bool sleeping)
{
	u64 virt = virtual_ns();
	u64 target = virt + ns;
	u64 real = kernel_elapsed_ns();
	u64 total;
	u64 ticks;

	if (real > target)
		target = real;
	total = sub_tick_ns + (target - virt);
	ticks = total / LKPI_NS_PER_JIFFY;
	sub_tick_ns = total % LKPI_NS_PER_JIFFY;
	if (!ticks || advancing)
		return;
	advancing = true;
	jiffies += ticks;
	jiffies_64 = jiffies;
	lkpi_timers_run(jiffies);
	if (sleeping)
		lkpi_work_run();
	advancing = false;
}

void lkpi_time_sleep_ns(u64 ns)
{
	lkpi_time_advance_ns(ns, true);
}

void lkpi_time_tick(void)
{
	lkpi_time_advance_ns(LKPI_NS_PER_JIFFY, true);
}

void udelay(unsigned long usecs)
{
	lkpi_time_advance_ns((u64)usecs * NSEC_PER_USEC, false);
}

void mdelay(unsigned long msecs)
{
	lkpi_time_advance_ns((u64)msecs * NSEC_PER_MSEC, false);
}

void msleep(unsigned int msecs)
{
	lkpi_time_sleep_ns((u64)msecs * NSEC_PER_MSEC);
}

void usleep_range(unsigned long min, unsigned long max)
{
	(void)max;
	lkpi_time_sleep_ns((u64)min * NSEC_PER_USEC);
}

unsigned long round_jiffies(unsigned long j)
{
	return ((j + HZ - 1) / HZ) * HZ;
}

unsigned long round_jiffies_relative(unsigned long j)
{
	return round_jiffies(jiffies + j) - jiffies;
}

ktime_t ktime_get(void)
{
	return lkpi_time_ns();
}

ktime_t ktime_get_boottime(void)
{
	return lkpi_time_ns();
}

ktime_t ktime_get_real(void)
{
	return lkpi_time_ns() + LKPI_REAL_EPOCH_SECONDS * NSEC_PER_SEC;
}

u64 ktime_get_ns(void)
{
	return lkpi_time_ns();
}

u64 ktime_get_boottime_ns(void)
{
	return lkpi_time_ns();
}

u64 ktime_get_real_ns(void)
{
	return ktime_get_real();
}

time64_t ktime_get_real_seconds(void)
{
	return ktime_get_real_ns() / NSEC_PER_SEC;
}

time64_t ktime_get_boottime_seconds(void)
{
	return lkpi_time_ns() / NSEC_PER_SEC;
}

struct timespec64 ns_to_timespec64(s64 nsec)
{
	struct timespec64 ts = { nsec / NSEC_PER_SEC, nsec % NSEC_PER_SEC };

	return ts;
}

void ktime_get_real_ts64(struct timespec64 *ts)
{
	*ts = ns_to_timespec64(ktime_get_real_ns());
}

void ktime_get_boottime_ts64(struct timespec64 *ts)
{
	*ts = ns_to_timespec64(lkpi_time_ns());
}
