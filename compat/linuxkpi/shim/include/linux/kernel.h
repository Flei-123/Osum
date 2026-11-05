#ifndef LKPI_LINUX_KERNEL_H
#define LKPI_LINUX_KERNEL_H

#include <linux/types.h>

#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define min(a, b) ({ __typeof__(a) _a = (a); __typeof__(b) _b = (b); _a < _b ? _a : _b; })
#define max(a, b) ({ __typeof__(a) _a = (a); __typeof__(b) _b = (b); _a > _b ? _a : _b; })
#define container_of(ptr, type, member) \
	((type *)((char *)(ptr) - __builtin_offsetof(type, member)))
#define likely(x) __builtin_expect(!!(x), 1)
#define unlikely(x) __builtin_expect(!!(x), 0)
#define BIT(n) (1UL << (n))
#define PAGE_SHIFT 12
#define PAGE_SIZE (1UL << PAGE_SHIFT)
#define ALIGN(x, a) (((x) + ((__typeof__(x))(a) - 1)) & ~((__typeof__(x))(a) - 1))
#define PAGE_ALIGN(x) ALIGN(x, PAGE_SIZE)

#define ENOENT 2
#define EIO 5
#define ENOMEM 12
#define EFAULT 14
#define EBUSY 16
#define ENODEV 19
#define EINVAL 22
#define ENOSPC 28
#define ERANGE 34
#define ENOSYS 38
#define MAX_ERRNO 4095

static inline void *ERR_PTR(long error)
{
	return (void *)error;
}

static inline long PTR_ERR(const void *ptr)
{
	return (long)ptr;
}

static inline bool IS_ERR(const void *ptr)
{
	return (unsigned long)ptr >= (unsigned long)-MAX_ERRNO;
}

#define GFP_KERNEL 0U
#define GFP_ATOMIC 0U
#define __GFP_ZERO 1U

#define KERN_ERR ""
#define KERN_WARNING ""
#define KERN_INFO ""
#define KERN_DEBUG ""

int _printk(const char *fmt, ...) __printf(1, 2);
int vsnprintf(char *buf, size_t size, const char *fmt, va_list args);
int snprintf(char *buf, size_t size, const char *fmt, ...) __printf(3, 4);

#define printk(fmt, ...) _printk(fmt, ##__VA_ARGS__)
#define pr_err(fmt, ...) _printk("lkpi: " fmt, ##__VA_ARGS__)
#define pr_warn(fmt, ...) _printk("lkpi: " fmt, ##__VA_ARGS__)
#define pr_info(fmt, ...) _printk("lkpi: " fmt, ##__VA_ARGS__)
#define no_printk(fmt, ...) do { if (0) _printk(fmt, ##__VA_ARGS__); } while (0)
#define pr_debug(fmt, ...) no_printk(fmt, ##__VA_ARGS__)

#define WARN_ON(cond) ({ \
	int _warned = !!(cond); \
	if (_warned) \
		_printk("lkpi: WARNING %s:%d\n", __FILE__, __LINE__); \
	_warned; })
#define WARN_ON_ONCE(cond) ({ \
	static bool _seen; \
	int _warned = !!(cond); \
	if (_warned && !_seen) { \
		_seen = true; \
		_printk("lkpi: WARNING %s:%d\n", __FILE__, __LINE__); \
	} \
	_warned; })
#define BUG_ON(cond) do { if (cond) lkpi_halt(__FILE__, __LINE__); } while (0)

void lkpi_halt(const char *file, int line) __attribute__((noreturn));

void *memset(void *dst, int value, size_t count);
void *memcpy(void *dst, const void *src, size_t count);
void *memmove(void *dst, const void *src, size_t count);
int memcmp(const void *a, const void *b, size_t count);
size_t strlen(const char *text);
int strcmp(const char *a, const char *b);
int strncmp(const char *a, const char *b, size_t count);

void *kmalloc(size_t size, gfp_t flags);
void *kzalloc(size_t size, gfp_t flags);
void *kcalloc(size_t count, size_t size, gfp_t flags);
void *krealloc(void *ptr, size_t size, gfp_t flags);
void kfree(const void *ptr);

#endif
