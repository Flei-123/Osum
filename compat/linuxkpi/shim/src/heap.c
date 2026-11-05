#include "lkpi.h"

#define ARENA_MAX 16
#define ARENA_FRAMES 64ULL
#define FRAME_BYTES 4096ULL
#define RUN_FRAMES_MAX 1024ULL
#define BLOCK_ALIGN 16ULL
#define SPLIT_MIN 32ULL

struct block {
	u64 size;
	u64 used;
};

struct arena {
	u64 base;
	u64 frames;
};

static struct arena arenas[ARENA_MAX];
static unsigned int arena_count;

static u64 arena_end(const struct arena *a)
{
	return a->base + a->frames * FRAME_BYTES;
}

static struct block *block_next(const struct block *b)
{
	return (struct block *)((u64)b + b->size);
}

static struct block *find_free(const struct arena *a, u64 need)
{
	struct block *b = (struct block *)a->base;

	while ((u64)b < arena_end(a)) {
		if (b->size < sizeof(*b))
			return NULL;
		if (!b->used && b->size >= need)
			return b;
		b = block_next(b);
	}
	return NULL;
}

static void *take(struct block *b, u64 need)
{
	if (b->size - need >= SPLIT_MIN) {
		struct block *rest = (struct block *)((u64)b + need);

		rest->size = b->size - need;
		rest->used = 0;
		b->size = need;
	}
	b->used = 1;
	return b + 1;
}

static void coalesce(const struct arena *a)
{
	struct block *b = (struct block *)a->base;

	while ((u64)b < arena_end(a)) {
		struct block *next;

		if (b->size < sizeof(*b))
			return;
		next = block_next(b);
		if (!b->used && (u64)next < arena_end(a) && !next->used)
			b->size += next->size;
		else
			b = next;
	}
}

static bool arena_is_empty(const struct arena *a)
{
	const struct block *b = (const struct block *)a->base;

	return !b->used && b->size == a->frames * FRAME_BYTES;
}

void *kmalloc(size_t size, gfp_t flags)
{
	u64 need;
	u64 frames;
	u64 base;
	unsigned int i;
	struct block *b;

	(void)flags;
	if (size == 0)
		size = 1;
	if (size > RUN_FRAMES_MAX * FRAME_BYTES - sizeof(struct block))
		return NULL;
	need = ALIGN((u64)size + sizeof(struct block), BLOCK_ALIGN);
	for (i = 0; i < arena_count; i++) {
		b = find_free(&arenas[i], need);
		if (b)
			return take(b, need);
	}
	if (arena_count == ARENA_MAX)
		return NULL;
	frames = (need + FRAME_BYTES - 1) / FRAME_BYTES;
	if (frames < ARENA_FRAMES)
		frames = ARENA_FRAMES;
	base = k_frames(frames);
	if (!base)
		return NULL;
	arenas[arena_count].base = base;
	arenas[arena_count].frames = frames;
	arena_count++;
	b = (struct block *)base;
	b->size = frames * FRAME_BYTES;
	b->used = 0;
	return take(b, need);
}

void *kzalloc(size_t size, gfp_t flags)
{
	void *ptr = kmalloc(size, flags);

	if (ptr)
		memset(ptr, 0, size);
	return ptr;
}

void *kcalloc(size_t count, size_t size, gfp_t flags)
{
	if (size && count > (size_t)-1 / size)
		return NULL;
	return kzalloc(count * size, flags);
}

void *krealloc(void *ptr, size_t size, gfp_t flags)
{
	size_t old;
	void *fresh;

	if (!ptr)
		return kmalloc(size, flags);
	if (size == 0) {
		kfree(ptr);
		return NULL;
	}
	old = ((struct block *)ptr - 1)->size - sizeof(struct block);
	if (size <= old)
		return ptr;
	fresh = kmalloc(size, flags);
	if (!fresh)
		return NULL;
	memcpy(fresh, ptr, old);
	kfree(ptr);
	return fresh;
}

void kfree(const void *ptr)
{
	struct block *b;
	unsigned int i;

	if (!ptr)
		return;
	b = (struct block *)ptr - 1;
	for (i = 0; i < arena_count; i++) {
		if ((u64)b < arenas[i].base || (u64)b >= arena_end(&arenas[i]))
			continue;
		if (!b->used) {
			_printk("lkpi: double free %p\n", ptr);
			return;
		}
		b->used = 0;
		coalesce(&arenas[i]);
		if (i != 0 && arena_is_empty(&arenas[i])) {
			k_frames_free(arenas[i].base, arenas[i].frames);
			arenas[i] = arenas[arena_count - 1];
			arena_count--;
		}
		return;
	}
	_printk("lkpi: free of unknown pointer %p\n", ptr);
}

size_t lkpi_heap_used(void)
{
	size_t total = 0;
	unsigned int i;

	for (i = 0; i < arena_count; i++) {
		const struct block *b = (const struct block *)arenas[i].base;

		while ((u64)b < arena_end(&arenas[i]) && b->size >= sizeof(*b)) {
			if (b->used)
				total += b->size;
			b = block_next(b);
		}
	}
	return total;
}

void lkpi_heap_release(void)
{
	unsigned int i;

	for (i = 0; i < arena_count; i++)
		k_frames_free(arenas[i].base, arenas[i].frames);
	arena_count = 0;
}
