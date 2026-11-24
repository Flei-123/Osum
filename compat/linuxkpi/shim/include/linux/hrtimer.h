/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_HRTIMER_H
#define LKPI_LINUX_HRTIMER_H
#include <linux/types.h>
#define CLOCK_REALTIME 0
#define CLOCK_MONOTONIC 1
#define CLOCK_BOOTTIME 7
enum hrtimer_mode { HRTIMER_MODE_ABS, HRTIMER_MODE_REL };
enum hrtimer_restart { HRTIMER_NORESTART, HRTIMER_RESTART };
struct hrtimer {
	enum hrtimer_restart (*function)(struct hrtimer *timer);
	ktime_t expires;
	int clock_id;
	int mode;
};
void hrtimer_init(struct hrtimer *timer, int clock_id, enum hrtimer_mode mode);
void hrtimer_start(struct hrtimer *timer, ktime_t tim, enum hrtimer_mode mode);
int hrtimer_cancel(struct hrtimer *timer);
#endif
