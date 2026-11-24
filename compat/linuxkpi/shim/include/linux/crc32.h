/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_CRC32_H
#define LKPI_LINUX_CRC32_H
#include <linux/types.h>
u32 crc32_le(u32 crc, const unsigned char *p, size_t len);
#define crc32(seed, data, len) crc32_le(seed, data, len)
#endif
