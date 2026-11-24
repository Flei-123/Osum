/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_INTERRUPT_H
#define LKPI_LINUX_INTERRUPT_H
#include <linux/kernel.h>
#include <linux/atomic.h>
#include <linux/cpu.h>
#include <linux/device.h>
typedef int irqreturn_t;
typedef irqreturn_t (*irq_handler_t)(int, void *);
#define IRQ_NONE 0
#define IRQ_HANDLED 1
#define IRQ_WAKE_THREAD 2
#define IRQF_SHARED 0x00000080
#define IRQF_ONESHOT 0x00002000
#define IRQF_NO_SUSPEND 0x00004000
struct tasklet_struct { void (*func)(unsigned long); unsigned long data; int scheduled; };
#define tasklet_init(t, f, d) do { (t)->func = (f); (t)->data = (d); (t)->scheduled = 0; } while (0)
void tasklet_schedule(struct tasklet_struct *t);
void tasklet_kill(struct tasklet_struct *t);
int request_threaded_irq(unsigned int irq, irq_handler_t handler, irq_handler_t thread_fn, unsigned long flags, const char *name, void *dev);
void free_irq(unsigned int irq, void *dev);
void disable_irq(unsigned int irq);
void enable_irq(unsigned int irq);
void synchronize_irq(unsigned int irq);
int devm_request_threaded_irq(struct device *dev, unsigned int irq, irq_handler_t handler, irq_handler_t thread_fn, unsigned long flags, const char *name, void *dev_id);
int irq_set_affinity_hint(unsigned int irq, const void *mask);
#endif
