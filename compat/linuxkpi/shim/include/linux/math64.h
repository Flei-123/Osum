/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_MATH64_H
#define LKPI_LINUX_MATH64_H
#include <linux/types.h>
#define div_u64(a, b) ((u64)(a) / (u32)(b))
#define div64_u64(a, b) ((u64)(a) / (u64)(b))
#define div_s64(a, b) ((s64)(a) / (s32)(b))
#define div64_s64(a, b) ((s64)(a) / (s64)(b))
#define do_div(n, base) ({ u32 _r = (u64)(n) % (u32)(base); (n) = (u64)(n) / (u32)(base); _r; })
#define mul_u64_u32_div(a, mul, div) ((u64)(((unsigned __int128)(a) * (mul)) / (div)))
#endif
