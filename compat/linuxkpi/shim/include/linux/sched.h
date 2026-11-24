/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_SCHED_H
#define LKPI_LINUX_SCHED_H
#include <linux/kernel.h>
#include <linux/jiffies.h>
#include <linux/rcupdate.h>
#include <linux/wait.h>
#include <linux/completion.h>
struct task_struct { int pid; char comm[16]; };
extern struct task_struct *current;
#define TASK_INTERRUPTIBLE 1
#define TASK_UNINTERRUPTIBLE 2
#define MAX_SCHEDULE_TIMEOUT 0x7fffffffffffffffL
void schedule(void);
long schedule_timeout(long timeout);
int cond_resched(void);
int signal_pending(struct task_struct *task);
#define set_current_state(s) do { } while (0)
#define in_interrupt() 0
#define in_softirq() 0
#define in_atomic() 0
#define in_task() 1
#endif
