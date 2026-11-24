#include "wifi.h"
#include <linux/completion.h>
#include <linux/cpu.h>
#include <linux/sched.h>
#include <linux/timer.h>
#include <linux/wait.h>
#include <linux/workqueue.h>

struct workqueue_struct { int unused; };

static struct workqueue_struct wq_system, wq_long, wq_unbound;
struct workqueue_struct *system_wq = &wq_system;
struct workqueue_struct *system_long_wq = &wq_long;
struct workqueue_struct *system_unbound_wq = &wq_unbound;

static struct list_head pending = LIST_HEAD_INIT(pending);
static struct list_head armed = LIST_HEAD_INIT(armed);

static bool linked(const struct list_head *entry)
{
	return entry->next && entry->next != entry;
}

static void unlink(struct list_head *entry)
{
	if (linked(entry))
		list_del_init(entry);
}

struct workqueue_struct *alloc_workqueue(const char *fmt, unsigned int flags, int max_active, ...)
{
	(void)fmt;
	(void)flags;
	(void)max_active;
	return kzalloc(sizeof(struct workqueue_struct), GFP_KERNEL);
}

void destroy_workqueue(struct workqueue_struct *wq)
{
	flush_workqueue(wq);
	kfree(wq);
}

bool queue_work(struct workqueue_struct *wq, struct work_struct *work)
{
	if (linked(&work->entry))
		return false;
	work->wq = wq;
	list_add_tail(&work->entry, &pending);
	return true;
}

bool schedule_work(struct work_struct *work)
{
	return queue_work(system_wq, work);
}

static void delayed_fire(struct timer_list *timer)
{
	struct delayed_work *dwork = container_of(timer, struct delayed_work, timer);

	queue_work(dwork->wq, &dwork->work);
}

bool queue_delayed_work(struct workqueue_struct *wq, struct delayed_work *dwork, unsigned long delay)
{
	if (linked(&dwork->work.entry) || linked(&dwork->timer.entry))
		return false;
	dwork->wq = wq;
	if (!delay)
		return queue_work(wq, &dwork->work);
	dwork->timer.function = delayed_fire;
	mod_timer(&dwork->timer, jiffies + delay);
	return true;
}

bool mod_delayed_work(struct workqueue_struct *wq, struct delayed_work *dwork, unsigned long delay)
{
	cancel_delayed_work(dwork);
	return queue_delayed_work(wq, dwork, delay);
}

bool schedule_delayed_work(struct delayed_work *dwork, unsigned long delay)
{
	return queue_delayed_work(system_wq, dwork, delay);
}

bool cancel_work_sync(struct work_struct *work)
{
	bool was_pending = linked(&work->entry);

	unlink(&work->entry);
	return was_pending;
}

bool cancel_delayed_work(struct delayed_work *dwork)
{
	bool was_pending = linked(&dwork->work.entry) || linked(&dwork->timer.entry);

	unlink(&dwork->work.entry);
	unlink(&dwork->timer.entry);
	return was_pending;
}

bool cancel_delayed_work_sync(struct delayed_work *dwork)
{
	return cancel_delayed_work(dwork);
}

static void run_work(struct work_struct *work)
{
	unlink(&work->entry);
	work->func(work);
}

bool flush_work(struct work_struct *work)
{
	if (!linked(&work->entry))
		return false;
	run_work(work);
	return true;
}

bool flush_delayed_work(struct delayed_work *dwork)
{
	if (linked(&dwork->timer.entry)) {
		unlink(&dwork->timer.entry);
		queue_work(dwork->wq, &dwork->work);
	}
	return flush_work(&dwork->work);
}

void flush_workqueue(struct workqueue_struct *wq)
{
	(void)wq;
	while (linked(&pending))
		run_work(list_first_entry(&pending, struct work_struct, entry));
}

int mod_timer(struct timer_list *timer, unsigned long expires)
{
	int was_pending = linked(&timer->entry);

	unlink(&timer->entry);
	timer->expires = expires;
	list_add_tail(&timer->entry, &armed);
	return was_pending;
}

int del_timer(struct timer_list *timer)
{
	int was_pending = linked(&timer->entry);

	unlink(&timer->entry);
	return was_pending;
}

int del_timer_sync(struct timer_list *timer)
{
	return del_timer(timer);
}

int timer_shutdown_sync(struct timer_list *timer)
{
	int was_pending = del_timer_sync(timer);

	timer->function = NULL;
	return was_pending;
}

int timer_pending(const struct timer_list *timer)
{
	return linked(&timer->entry);
}

void lkpi_timers_run(unsigned long now)
{
	struct timer_list *timer, *next;

	jiffies = now;
	jiffies_64 = now;
	list_for_each_entry_safe(timer, next, &armed, entry) {
		if (time_after(timer->expires, now))
			continue;
		unlink(&timer->entry);
		timer->function(timer);
	}
}

void lkpi_work_run(void)
{
	flush_workqueue(NULL);
}

void wake_up(wait_queue_head_t *q)
{
	(void)q;
}

long lkpi_wait_slice(wait_queue_head_t *q, long timeout)
{
	(void)q;
	lkpi_time_sleep_ns(LKPI_NS_PER_JIFFY);
	lkpi_irq_poll();
	lkpi_napi_run();
	return timeout > 0 ? timeout - 1 : 0;
}

void wait_for_completion(struct completion *c)
{
	unsigned long budget = LKPI_WAIT_BUDGET_TICKS;

	while (!c->done && budget--)
		lkpi_wait_slice(&c->wait, 1);
	if (c->done && c->done != ~0U / 2)
		c->done--;
}

void complete(struct completion *c)
{
	c->done++;
	wake_up(&c->wait);
}

void complete_all(struct completion *c)
{
	c->done = ~0U / 2;
	wake_up(&c->wait);
}

bool completion_done(struct completion *c)
{
	return c->done != 0;
}

int cond_resched(void)
{
	return 0;
}

int num_online_cpus(void)
{
	return 1;
}

int smp_processor_id(void)
{
	return 0;
}
