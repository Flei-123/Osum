#ifndef LKPI_LINUX_TYPES_H
#define LKPI_LINUX_TYPES_H

typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;
typedef unsigned long long u64;
typedef signed char s8;
typedef short s16;
typedef int s32;
typedef long long s64;
typedef u8 uint8_t;
typedef u16 uint16_t;
typedef u32 uint32_t;
typedef u64 uint64_t;
typedef __SIZE_TYPE__ size_t;
typedef long ssize_t;
typedef __UINTPTR_TYPE__ uintptr_t;
typedef u64 resource_size_t;
typedef u64 phys_addr_t;
typedef u64 dma_addr_t;
typedef unsigned int gfp_t;
typedef __builtin_va_list va_list;

#define va_start(ap, last) __builtin_va_start(ap, last)
#define va_end(ap) __builtin_va_end(ap)
#define va_copy(dst, src) __builtin_va_copy(dst, src)
#define va_arg(ap, type) __builtin_va_arg(ap, type)

typedef u8 __u8;
typedef u16 __u16;
typedef u32 __u32;
typedef u64 __u64;
typedef s8 __s8;
typedef s16 __s16;
typedef s32 __s32;
typedef s64 __s64;
typedef u16 __le16;
typedef u32 __le32;
typedef u64 __le64;
typedef u16 __be16;
typedef u32 __be32;
typedef u64 __be64;
typedef u16 __sum16;
typedef u32 __wsum;
typedef int pid_t;
typedef long long loff_t;
typedef s64 ktime_t;
typedef struct { int counter; } atomic_t;
typedef struct { s64 counter; } atomic64_t;
#define __packed __attribute__((packed))
#define __aligned(x) __attribute__((aligned(x)))
#define __maybe_unused __attribute__((unused))
#define __always_unused __attribute__((unused))
#define __must_check __attribute__((warn_unused_result))
#define __cold __attribute__((cold))
#define __rcu
#define __bitwise
#define __acquires(x)
#define __releases(x)
#define __must_hold(x)
#define fallthrough __attribute__((fallthrough))
#define __counted_by(m)
#define __nonstring
#define __read_mostly
#define __section(s) __attribute__((section(s)))
#define noinline __attribute__((noinline))
#define bool _Bool
#define true 1
#define false 0
#define NULL ((void *)0)

#define __iomem
#define __init
#define __exit
#define __user
#define __force
#define __always_inline inline __attribute__((always_inline))
#define __printf(a, b) __attribute__((format(printf, a, b)))

#endif
