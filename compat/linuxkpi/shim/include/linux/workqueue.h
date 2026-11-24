/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_WORKQUEUE_H
#define LKPI_LINUX_WORKQUEUE_H
#include <linux/timer.h>
struct workqueue_struct;
struct work_struct { void (*func)(struct work_struct *); unsigned long data; struct list_head entry; struct workqueue_struct *wq; };
struct delayed_work { struct work_struct work; struct timer_list timer; struct workqueue_struct *wq; };
typedef void (*work_func_t)(struct work_struct *);
#define WQ_UNBOUND 2
#define WQ_MEM_RECLAIM 8
#define WQ_HIGHPRI 16
#define INIT_WORK(w, f) do { (w)->func = (f); (w)->data = 0; (w)->wq = NULL; INIT_LIST_HEAD(&(w)->entry); } while (0)
#define INIT_DELAYED_WORK(d, f) do { INIT_WORK(&(d)->work, f); timer_setup(&(d)->timer, NULL, 0); (d)->wq = NULL; } while (0)
#define DECLARE_WORK(n, f) struct work_struct n = { .func = (f) }
#define DECLARE_DELAYED_WORK(n, f) struct delayed_work n = { .work = { .func = (f) } }
#define to_delayed_work(w) container_of(w, struct delayed_work, work)
#define work_pending(w) (!list_empty(&(w)->entry))
extern struct workqueue_struct *system_wq;
extern struct workqueue_struct *system_long_wq;
extern struct workqueue_struct *system_unbound_wq;
struct workqueue_struct *alloc_workqueue(const char *fmt, unsigned int flags, int max_active, ...);
#define alloc_ordered_workqueue(fmt, flags, args...) alloc_workqueue(fmt, (flags) | WQ_UNBOUND, 1, ##args)
void destroy_workqueue(struct workqueue_struct *wq);
bool queue_work(struct workqueue_struct *wq, struct work_struct *work);
bool queue_delayed_work(struct workqueue_struct *wq, struct delayed_work *dwork, unsigned long delay);
bool mod_delayed_work(struct workqueue_struct *wq, struct delayed_work *dwork, unsigned long delay);
bool schedule_work(struct work_struct *work);
bool schedule_delayed_work(struct delayed_work *dwork, unsigned long delay);
bool cancel_work_sync(struct work_struct *work);
bool cancel_delayed_work(struct delayed_work *dwork);
bool cancel_delayed_work_sync(struct delayed_work *dwork);
bool flush_work(struct work_struct *work);
bool flush_delayed_work(struct delayed_work *dwork);
void flush_workqueue(struct workqueue_struct *wq);
#endif
