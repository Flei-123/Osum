#include <linux/kernel.h>

#define ARENA_BYTES (1u << 22)
#define MIN_CLASS 5
#define MAX_CLASS 20

struct block {
	u64 class;
	struct block *next;
};

static u8 arena[ARENA_BYTES] __attribute__((aligned(16)));
static u64 used;
static struct block *free_list[MAX_CLASS + 1];

void *kzalloc(size_t size, gfp_t flags)
{
	u64 class = MIN_CLASS;
	struct block *b;
	u8 *p;
	u64 i;

	(void)flags;
	while (((u64)1 << class) < size + sizeof(*b) && class <= MAX_CLASS)
		class++;
	if (class > MAX_CLASS)
		return NULL;
	b = free_list[class];
	if (b)
		free_list[class] = b->next;
	else {
		if (used + ((u64)1 << class) > ARENA_BYTES)
			return NULL;
		b = (struct block *)(arena + used);
		used += (u64)1 << class;
		b->class = class;
	}
	p = (u8 *)(b + 1);
	for (i = 0; i < ((u64)1 << class) - sizeof(*b); i++)
		p[i] = 0;
	return p;
}

void kfree(const void *ptr)
{
	struct block *b;

	if (!ptr)
		return;
	b = (struct block *)ptr - 1;
	b->next = free_list[b->class];
	free_list[b->class] = b;
}

void *memcpy(void *dst, const void *src, size_t count)
{
	u8 *to = dst;
	const u8 *from = src;

	while (count--)
		*to++ = *from++;
	return dst;
}

void *memset(void *dst, int value, size_t count)
{
	u8 *to = dst;

	while (count--)
		*to++ = (u8)value;
	return dst;
}
