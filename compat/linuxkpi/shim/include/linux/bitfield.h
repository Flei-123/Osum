/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_BITFIELD_H
#define LKPI_LINUX_BITFIELD_H
#include <linux/bitops.h>
#define __bf_shf(x) (__builtin_ffsll(x) - 1)
#define FIELD_PREP(mask, val) ((__typeof__(mask))(((u64)(val) << __bf_shf(mask)) & (mask)))
#define FIELD_GET(mask, reg) ((__typeof__(mask))(((reg) & (mask)) >> __bf_shf(mask)))
#define FIELD_FIT(mask, val) (!((((u64)(val)) << __bf_shf(mask)) & ~(u64)(mask)))
#define FIELD_MAX(mask) ((__typeof__(mask))((mask) >> __bf_shf(mask)))
#define u8_encode_bits(v, field) ((u8)FIELD_PREP(field, v))
#define u8_get_bits(v, field) ((u8)FIELD_GET(field, v))
#define u16_encode_bits(v, field) ((u16)FIELD_PREP(field, v))
#define u16_get_bits(v, field) ((u16)FIELD_GET(field, v))
#define u32_encode_bits(v, field) ((u32)FIELD_PREP(field, v))
#define u32_get_bits(v, field) ((u32)FIELD_GET(field, v))
#define le16_encode_bits(v, field) cpu_to_le16(FIELD_PREP(field, v))
#define le16_get_bits(v, field) FIELD_GET(field, le16_to_cpu(v))
#define le32_encode_bits(v, field) cpu_to_le32(FIELD_PREP(field, v))
#define le32_get_bits(v, field) FIELD_GET(field, le32_to_cpu(v))
#endif
