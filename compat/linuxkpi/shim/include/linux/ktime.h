/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_KTIME_H
#define LKPI_LINUX_KTIME_H
#include <linux/time.h>
#define ktime_set(secs, nsecs) ((ktime_t)(secs) * NSEC_PER_SEC + (nsecs))
static inline s64 ktime_to_ns(ktime_t k) { return k; }
static inline s64 ktime_to_us(ktime_t k) { return k / NSEC_PER_USEC; }
static inline s64 ktime_to_ms(ktime_t k) { return k / NSEC_PER_MSEC; }
static inline ktime_t ns_to_ktime(u64 ns) { return ns; }
static inline ktime_t ms_to_ktime(u64 ms) { return ms * NSEC_PER_MSEC; }
static inline ktime_t ktime_sub(ktime_t a, ktime_t b) { return a - b; }
static inline ktime_t ktime_add(ktime_t a, ktime_t b) { return a + b; }
static inline ktime_t ktime_add_ms(ktime_t a, u64 ms) { return a + ms * NSEC_PER_MSEC; }
static inline s64 ktime_us_delta(ktime_t a, ktime_t b) { return (a - b) / NSEC_PER_USEC; }
static inline s64 ktime_ms_delta(ktime_t a, ktime_t b) { return (a - b) / NSEC_PER_MSEC; }
static inline bool ktime_before(ktime_t a, ktime_t b) { return a < b; }
#include <linux/timekeeping.h>
#endif
