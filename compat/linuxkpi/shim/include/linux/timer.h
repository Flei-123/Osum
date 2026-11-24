/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_TIMER_H
#define LKPI_LINUX_TIMER_H
#include <linux/jiffies.h>
#include <linux/list.h>
struct timer_list { struct list_head entry; unsigned long expires; void (*function)(struct timer_list *); u32 flags; };
#define TIMER_DEFERRABLE 0x00080000u
#define timer_setup(t, cb, f) do { (t)->function = (cb); (t)->flags = (f); (t)->expires = 0; INIT_LIST_HEAD(&(t)->entry); } while (0)
#define from_timer(var, callback_timer, timer_fieldname) container_of(callback_timer, __typeof__(*var), timer_fieldname)
int mod_timer(struct timer_list *timer, unsigned long expires);
int del_timer(struct timer_list *timer);
int del_timer_sync(struct timer_list *timer);
int timer_pending(const struct timer_list *timer);
#define timer_delete(t) del_timer(t)
#define timer_delete_sync(t) del_timer_sync(t)
#endif
