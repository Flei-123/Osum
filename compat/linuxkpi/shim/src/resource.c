#include "lkpi.h"

#define CLAIM_MAX 16
#define MAPPING_MAX 8

struct claim {
	struct resource res;
	struct resource *parent;
	bool used;
};

struct mapping {
	resource_size_t phys;
	unsigned long size;
	u64 virt;
};

struct resource ioport_resource = { 0, 0xffff, "PCI IO", IORESOURCE_IO };
struct resource iomem_resource = { 0, ~0ULL, "PCI mem", IORESOURCE_MEM };

static struct claim claims[CLAIM_MAX];
static struct mapping mappings[MAPPING_MAX];
static unsigned int mapping_count;

struct resource *__request_region(struct resource *parent, resource_size_t start,
				  resource_size_t count, const char *name, int flags)
{
	resource_size_t end = start + count - 1;
	unsigned int i;
	struct claim *free_slot = NULL;

	(void)flags;
	if (count == 0)
		return NULL;
	for (i = 0; i < CLAIM_MAX; i++) {
		struct claim *c = &claims[i];

		if (!c->used) {
			if (!free_slot)
				free_slot = c;
			continue;
		}
		if (c->parent == parent && start <= c->res.end && end >= c->res.start)
			return NULL;
	}
	if (!free_slot)
		return NULL;
	free_slot->used = true;
	free_slot->parent = parent;
	free_slot->res.start = start;
	free_slot->res.end = end;
	free_slot->res.name = name;
	free_slot->res.flags = parent->flags;
	return &free_slot->res;
}

void __release_region(struct resource *parent, resource_size_t start, resource_size_t count)
{
	resource_size_t end = start + count - 1;
	unsigned int i;

	for (i = 0; i < CLAIM_MAX; i++) {
		struct claim *c = &claims[i];

		if (c->used && c->parent == parent && c->res.start == start && c->res.end == end) {
			c->used = false;
			return;
		}
	}
}

void __iomem *ioremap(resource_size_t phys, unsigned long size)
{
	u64 virt;
	unsigned int i;

	for (i = 0; i < mapping_count; i++) {
		const struct mapping *m = &mappings[i];

		if (phys >= m->phys && phys + size <= m->phys + m->size)
			return (void __iomem *)(m->virt + (phys - m->phys));
	}
	virt = k_ioremap(phys, size);
	if (!virt)
		return NULL;
	if (mapping_count < MAPPING_MAX) {
		mappings[mapping_count].phys = phys;
		mappings[mapping_count].size = size;
		mappings[mapping_count].virt = virt;
		mapping_count++;
	}
	return (void __iomem *)virt;
}

void iounmap(volatile void __iomem *addr)
{
	(void)addr;
}
