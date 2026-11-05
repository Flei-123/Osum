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
#define va_arg(ap, type) __builtin_va_arg(ap, type)

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
