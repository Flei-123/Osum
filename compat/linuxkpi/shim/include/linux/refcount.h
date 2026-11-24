/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_REFCOUNT_H
#define LKPI_LINUX_REFCOUNT_H
#include <linux/atomic.h>
typedef struct { atomic_t refs; } refcount_t;
#define REFCOUNT_INIT(n) { .refs = ATOMIC_INIT(n) }
#define refcount_set(r, n) atomic_set(&(r)->refs, n)
#define refcount_read(r) atomic_read(&(r)->refs)
#define refcount_inc(r) atomic_inc(&(r)->refs)
#define refcount_dec(r) atomic_dec(&(r)->refs)
#define refcount_dec_and_test(r) atomic_dec_and_test(&(r)->refs)
#define refcount_inc_not_zero(r) atomic_inc_not_zero(&(r)->refs)
#endif
