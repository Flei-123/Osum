/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_ATOMIC_H
#define LKPI_LINUX_ATOMIC_H
#include <linux/types.h>
#define ATOMIC_INIT(i) { (i) }
#define atomic_read(v) __atomic_load_n(&(v)->counter, __ATOMIC_RELAXED)
#define atomic_set(v, i) __atomic_store_n(&(v)->counter, (i), __ATOMIC_RELAXED)
#define atomic_inc(v) ((void)__atomic_add_fetch(&(v)->counter, 1, __ATOMIC_SEQ_CST))
#define atomic_dec(v) ((void)__atomic_sub_fetch(&(v)->counter, 1, __ATOMIC_SEQ_CST))
#define atomic_add(i, v) ((void)__atomic_add_fetch(&(v)->counter, (i), __ATOMIC_SEQ_CST))
#define atomic_sub(i, v) ((void)__atomic_sub_fetch(&(v)->counter, (i), __ATOMIC_SEQ_CST))
#define atomic_inc_return(v) __atomic_add_fetch(&(v)->counter, 1, __ATOMIC_SEQ_CST)
#define atomic_dec_return(v) __atomic_sub_fetch(&(v)->counter, 1, __ATOMIC_SEQ_CST)
#define atomic_add_return(i, v) __atomic_add_fetch(&(v)->counter, (i), __ATOMIC_SEQ_CST)
#define atomic_dec_and_test(v) (atomic_dec_return(v) == 0)
#define atomic_inc_not_zero(v) ({ int _o = atomic_read(v); _o ? (atomic_inc(v), 1) : 0; })
#define atomic_cmpxchg(v, o, n) ({ int _o = (o); __atomic_compare_exchange_n(&(v)->counter, &_o, (n), 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST); _o; })
#define atomic_xchg(v, n) __atomic_exchange_n(&(v)->counter, (n), __ATOMIC_SEQ_CST)
#define atomic64_read(v) __atomic_load_n(&(v)->counter, __ATOMIC_RELAXED)
#define atomic64_set(v, i) __atomic_store_n(&(v)->counter, (i), __ATOMIC_RELAXED)
#define atomic64_inc(v) ((void)__atomic_add_fetch(&(v)->counter, 1, __ATOMIC_SEQ_CST))
#define atomic64_inc_return(v) __atomic_add_fetch(&(v)->counter, 1, __ATOMIC_SEQ_CST)
#define smp_mb() __atomic_thread_fence(__ATOMIC_SEQ_CST)
#define smp_wmb() __atomic_thread_fence(__ATOMIC_RELEASE)
#define smp_rmb() __atomic_thread_fence(__ATOMIC_ACQUIRE)
#define mb() smp_mb()
#define wmb() smp_wmb()
#define rmb() smp_rmb()
#define smp_mb__before_atomic() smp_mb()
#define smp_mb__after_atomic() smp_mb()
#define READ_ONCE(x) (*(const volatile __typeof__(x) *)&(x))
#define WRITE_ONCE(x, v) (*(volatile __typeof__(x) *)&(x) = (v))
#endif
