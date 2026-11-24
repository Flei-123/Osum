#ifndef LKPI_LINUX_KERNEL_H
#define LKPI_LINUX_KERNEL_H

#include <linux/types.h>
#include <linux/overflow.h>
#include <linux/limits.h>

#define static_assert(expr, ...) _Static_assert(expr, "" __VA_ARGS__)
#define __attribute_const__ __attribute__((const))
#define roundup_pow_of_two(n) ((n) <= 1 ? 1UL : 1UL << (64 - __builtin_clzl((unsigned long)(n) - 1)))
#define TRUE 1
#define FALSE 0
#define ilog2(n) ((n) < 2 ? 0 : 63 - __builtin_clzll((unsigned long long)(n)))
#define IS_ERR_OR_NULL(ptr) (!(ptr) || IS_ERR(ptr))
#define PTR_ERR_OR_ZERO(ptr) (IS_ERR(ptr) ? PTR_ERR(ptr) : 0)
#define abs(x) ({ __typeof__(x) _x = (x); _x < 0 ? -_x : _x; })
#define upper_32_bits(n) ((u32)(((n) >> 16) >> 16))
#define lower_32_bits(n) ((u32)((n) & 0xffffffffU))
#define round_down(x, y) ((x) & ~((__typeof__(x))(y) - 1))
#define roundup(x, y) ((((x) + ((y) - 1)) / (y)) * (y))
#define is_power_of_2(n) ((n) != 0 && (((n) & ((n) - 1)) == 0))
#define rounddown_pow_of_two(n) (1UL << (63 - __builtin_clzl((unsigned long)(n))))
#define HWEIGHT32(w) __builtin_popcount((u32)(w))
#define BUILD_BUG_ON(cond) ((void)sizeof(char[1 - 2 * !!(cond)]))
#define BUILD_BUG_ON_MSG(cond, msg) BUILD_BUG_ON(cond)
#define BUILD_BUG_ON_ZERO(e) ((int)sizeof(struct { int : (-!!(e)); }))
#define ____cacheline_aligned __attribute__((aligned(64)))
#define ____cacheline_aligned_in_smp ____cacheline_aligned
#define SMP_CACHE_BYTES 64
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
#define min_t(t, a, b) ((t)(a) < (t)(b) ? (t)(a) : (t)(b))
#define max_t(t, a, b) ((t)(a) > (t)(b) ? (t)(a) : (t)(b))
#define DIV_ROUND_UP(n, d) (((n) + (d) - 1) / (d))
#define clamp(v, lo, hi) min(max(v, lo), hi)
#define swap(a, b) do { __typeof__(a) _t = (a); (a) = (b); (b) = _t; } while (0)
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
#define E2BIG 7
#define ERANGE 34
#define ENOSYS 38
#define MAX_ERRNO 4095
#define ERFKILL 132
#define ENODATA 61
#define ENXIO 6
#define EBADF 9
#define ECONNRESET 104
#define ENOTSUP 95
#define ENOMSG 42
#define EPFNOSUPPORT 96
#define EAGAIN 11
#define EEXIST 17
#define EPERM 1
#define ETIMEDOUT 110
#define EOPNOTSUPP 95
#define ENOTSUPP 524
#define EOVERFLOW 75
#define EALREADY 114
#define EPROTO 71
#define ENOBUFS 105
#define ERESTARTSYS 512
#define EINPROGRESS 115
#define ESHUTDOWN 108
#define EHOSTUNREACH 113
#define EACCES 13
#define EHOSTDOWN 112
#define ENOTCONN 107
#define EMSGSIZE 90
#define EBADMSG 74

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

#define DUMP_PREFIX_NONE 0
#define DUMP_PREFIX_ADDRESS 1
#define DUMP_PREFIX_OFFSET 2
void print_hex_dump(const char *level, const char *prefix_str, int prefix_type, int rowsize, int groupsize, const void *buf, size_t len, bool ascii);
#define KERN_ERR ""
#define KERN_WARNING ""
#define KERN_INFO ""
#define KERN_DEBUG ""

struct va_format { const char *fmt; va_list *va; };
int _printk(const char *fmt, ...) __printf(1, 2);
int vsnprintf(char *buf, size_t size, const char *fmt, va_list args);
int snprintf(char *buf, size_t size, const char *fmt, ...) __printf(3, 4);
int scnprintf(char *buf, size_t size, const char *fmt, ...) __printf(3, 4);
int sprintf(char *buf, const char *fmt, ...) __printf(2, 3);
void dump_stack(void);

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
#define WARN(cond, fmt, ...) ({ \
	int _warned = !!(cond); \
	if (_warned) \
		_printk("lkpi: WARNING " fmt, ##__VA_ARGS__); \
	_warned; })
#define WARN_ONCE(cond, fmt, ...) ({ \
	static bool _seen; \
	int _warned = !!(cond); \
	if (_warned && !_seen) { \
		_seen = true; \
		_printk("lkpi: WARNING " fmt, ##__VA_ARGS__); \
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

#include <linux/random.h>
#include <linux/math64.h>

#endif
