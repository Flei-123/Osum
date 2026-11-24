#include "wifi.h"
#include <linux/interrupt.h>

#define LKPI_IRQ_MAX 16

struct irq_slot {
	unsigned int irq;
	irq_handler_t handler;
	irq_handler_t thread_fn;
	void *dev_id;
	bool used;
};

struct irq_claim {
	unsigned int irq;
	void *dev_id;
};

static struct irq_slot slots[LKPI_IRQ_MAX];

int request_threaded_irq(unsigned int irq, irq_handler_t handler, irq_handler_t thread_fn, unsigned long flags,
			 const char *name, void *dev)
{
	unsigned int i;

	(void)flags;
	(void)name;
	if (!handler && !thread_fn)
		return -EINVAL;
	for (i = 0; i < LKPI_IRQ_MAX; i++) {
		if (slots[i].used)
			continue;
		slots[i].irq = irq;
		slots[i].handler = handler;
		slots[i].thread_fn = thread_fn;
		slots[i].dev_id = dev;
		slots[i].used = true;
		return 0;
	}
	return -ENOSPC;
}

void free_irq(unsigned int irq, void *dev)
{
	unsigned int i;

	for (i = 0; i < LKPI_IRQ_MAX; i++) {
		if (slots[i].used && slots[i].irq == irq && slots[i].dev_id == dev)
			slots[i].used = false;
	}
}

static void claim_release(void *payload)
{
	struct irq_claim *claim = payload;

	free_irq(claim->irq, claim->dev_id);
}

int devm_request_threaded_irq(struct device *dev, unsigned int irq, irq_handler_t handler, irq_handler_t thread_fn,
			      unsigned long flags, const char *name, void *dev_id)
{
	struct irq_claim *claim;
	int rc = request_threaded_irq(irq, handler, thread_fn, flags, name, dev_id);

	if (rc)
		return rc;
	claim = lkpi_devres_alloc(dev, sizeof(*claim), claim_release);
	if (!claim) {
		free_irq(irq, dev_id);
		return -ENOMEM;
	}
	claim->irq = irq;
	claim->dev_id = dev_id;
	return 0;
}

void disable_irq(unsigned int irq)
{
	(void)irq;
}

void enable_irq(unsigned int irq)
{
	(void)irq;
}

void synchronize_irq(unsigned int irq)
{
	(void)irq;
}

int irq_set_affinity_hint(unsigned int irq, const void *mask)
{
	(void)irq;
	(void)mask;
	return 0;
}

void lkpi_irq_poll(void)
{
	static bool polling;
	unsigned int i;

	if (polling)
		return;
	polling = true;
	for (i = 0; i < LKPI_IRQ_MAX; i++) {
		struct irq_slot slot = slots[i];
		irqreturn_t result = IRQ_WAKE_THREAD;

		if (!slot.used)
			continue;
		if (slot.handler)
			result = slot.handler(slot.irq, slot.dev_id);
		if (result == IRQ_WAKE_THREAD && slot.thread_fn)
			slot.thread_fn(slot.irq, slot.dev_id);
	}
	polling = false;
}
