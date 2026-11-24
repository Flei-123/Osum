/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_TIME_H
#define LKPI_LINUX_TIME_H
#include <linux/jiffies.h>
typedef s64 time64_t;
struct timespec64 { time64_t tv_sec; long tv_nsec; };
struct timespec64 ns_to_timespec64(s64 nsec);
struct timeval { long tv_sec; long tv_usec; };
#endif
