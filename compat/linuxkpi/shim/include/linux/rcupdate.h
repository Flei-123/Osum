/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_RCUPDATE_H
#define LKPI_LINUX_RCUPDATE_H
#include <linux/atomic.h>
#include <linux/lockdep.h>
struct rcu_head { struct rcu_head *next; void (*func)(struct rcu_head *); };
#define rcu_read_lock() do { } while (0)
#define rcu_read_unlock() do { } while (0)
#define rcu_dereference(p) READ_ONCE(p)
#define rcu_dereference_raw(p) READ_ONCE(p)
#define rcu_dereference_check(p, c) READ_ONCE(p)
#define rcu_dereference_protected(p, c) (p)
#define rcu_access_pointer(p) READ_ONCE(p)
#define rcu_assign_pointer(p, v) do { smp_wmb(); WRITE_ONCE(p, v); } while (0)
#define RCU_INIT_POINTER(p, v) do { WRITE_ONCE(p, v); } while (0)
#define rcu_pointer_handoff(p) (p)
#define rcu_head_init(h) do { (h)->func = NULL; } while (0)
void synchronize_rcu(void);
void call_rcu(struct rcu_head *head, void (*func)(struct rcu_head *));
#define kfree_rcu(p, f) do { synchronize_rcu(); kfree(p); } while (0)
#endif
