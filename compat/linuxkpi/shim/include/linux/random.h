/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_RANDOM_H
#define LKPI_LINUX_RANDOM_H
#include <linux/types.h>
void get_random_bytes(void *buf, size_t len);
u32 get_random_u32(void);
u32 get_random_u32_inclusive(u32 floor, u32 ceil);
#endif
