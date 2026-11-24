/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_WAIT_H
#define LKPI_LINUX_WAIT_H
#include <linux/spinlock.h>
#include <linux/list.h>
#include <linux/jiffies.h>
typedef struct wait_queue_head { spinlock_t lock; struct list_head head; } wait_queue_head_t;
#define DECLARE_WAIT_QUEUE_HEAD(n) wait_queue_head_t n = { .lock = { 0 }, .head = LIST_HEAD_INIT(n.head) }
#define init_waitqueue_head(q) do { spin_lock_init(&(q)->lock); INIT_LIST_HEAD(&(q)->head); } while (0)
long lkpi_wait_slice(wait_queue_head_t *q, long timeout);
void wake_up(wait_queue_head_t *q);
#define wake_up_all(q) wake_up(q)
#define wake_up_interruptible(q) wake_up(q)
#define wake_up_interruptible_all(q) wake_up(q)
#define wait_event_timeout(q, cond, to) ({ \
	long __left = (to); \
	while (!(cond) && __left > 0) __left = lkpi_wait_slice(&(q), __left); \
	(cond) ? (__left > 0 ? __left : 1) : 0; })
#define wait_event_interruptible_timeout(q, cond, to) wait_event_timeout(q, cond, to)
#define wait_event(q, cond) do { while (!(cond)) lkpi_wait_slice(&(q), 1); } while (0)
#define wait_event_interruptible(q, cond) ({ wait_event(q, cond); 0; })
#endif
