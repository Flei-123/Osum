/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_JIFFIES_H
#define LKPI_LINUX_JIFFIES_H
#include <linux/types.h>
#define HZ 250
#define MSEC_PER_SEC 1000L
#define USEC_PER_SEC 1000000L
#define NSEC_PER_SEC 1000000000L
#define USEC_PER_MSEC 1000L
#define NSEC_PER_MSEC 1000000L
#define NSEC_PER_USEC 1000L
#define INITIAL_JIFFIES ((unsigned long)-300 * HZ)
extern volatile unsigned long jiffies;
extern u64 jiffies_64;
#define time_after(a, b) ((long)((b) - (a)) < 0)
#define time_before(a, b) time_after(b, a)
#define time_after_eq(a, b) ((long)((a) - (b)) >= 0)
#define time_before_eq(a, b) time_after_eq(b, a)
static inline unsigned long msecs_to_jiffies(unsigned int m) { return ((unsigned long)m * HZ + MSEC_PER_SEC - 1) / MSEC_PER_SEC; }
static inline unsigned long usecs_to_jiffies(unsigned int u) { return ((unsigned long)u * HZ + USEC_PER_SEC - 1) / USEC_PER_SEC; }
static inline unsigned int jiffies_to_msecs(unsigned long j) { return j * (MSEC_PER_SEC / HZ); }
static inline unsigned int jiffies_to_usecs(unsigned long j) { return j * (USEC_PER_SEC / HZ); }
#endif
