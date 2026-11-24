/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_TIMEKEEPING_H
#define LKPI_LINUX_TIMEKEEPING_H
#include <linux/ktime.h>
ktime_t ktime_get(void);
ktime_t ktime_get_boottime(void);
ktime_t ktime_get_real(void);
u64 ktime_get_ns(void);
u64 ktime_get_boottime_ns(void);
u64 ktime_get_real_ns(void);
time64_t ktime_get_real_seconds(void);
time64_t ktime_get_boottime_seconds(void);
void ktime_get_real_ts64(struct timespec64 *ts);
void ktime_get_boottime_ts64(struct timespec64 *ts);
#endif
