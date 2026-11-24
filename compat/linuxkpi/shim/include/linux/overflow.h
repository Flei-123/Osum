/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_OVERFLOW_H
#define LKPI_LINUX_OVERFLOW_H
#include <linux/types.h>
#define check_add_overflow(a, b, d) __builtin_add_overflow(a, b, d)
#define check_sub_overflow(a, b, d) __builtin_sub_overflow(a, b, d)
#define check_mul_overflow(a, b, d) __builtin_mul_overflow(a, b, d)
static inline size_t size_add(size_t a, size_t b) { size_t r; return __builtin_add_overflow(a, b, &r) ? (size_t)-1 : r; }
static inline size_t size_mul(size_t a, size_t b) { size_t r; return __builtin_mul_overflow(a, b, &r) ? (size_t)-1 : r; }
#define array_size(a, b) size_mul(a, b)
#define flex_array_size(p, member, count) size_mul(count, sizeof(*(p)->member) + __must_be_array_stub(0))
#define __must_be_array_stub(x) (x)
#define struct_size(p, member, count) size_add(sizeof(*(p)), flex_array_size(p, member, count))
#define struct_size_t(type, member, count) size_add(sizeof(type), size_mul(count, sizeof(((type *)0)->member[0])))
#endif
