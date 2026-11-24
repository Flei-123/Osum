/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_UNALIGNED_H
#define LKPI_LINUX_UNALIGNED_H
#include <asm/byteorder.h>
#define __get_unaligned_t(type, ptr) ({ type _v; __builtin_memcpy(&_v, (ptr), sizeof(_v)); _v; })
#define __put_unaligned_t(type, val, ptr) do { type _v = (val); __builtin_memcpy((ptr), &_v, sizeof(_v)); } while (0)
#define get_unaligned(ptr) __get_unaligned_t(__typeof__(*(ptr)), (ptr))
#define put_unaligned(val, ptr) __put_unaligned_t(__typeof__(*(ptr)), (val), (ptr))
static inline u16 get_unaligned_le16(const void *p) { return __get_unaligned_t(u16, p); }
static inline u32 get_unaligned_le32(const void *p) { return __get_unaligned_t(u32, p); }
static inline u64 get_unaligned_le64(const void *p) { return __get_unaligned_t(u64, p); }
static inline u16 get_unaligned_be16(const void *p) { return __builtin_bswap16(__get_unaligned_t(u16, p)); }
static inline u32 get_unaligned_be32(const void *p) { return __builtin_bswap32(__get_unaligned_t(u32, p)); }
static inline void put_unaligned_le16(u16 v, void *p) { __put_unaligned_t(u16, v, p); }
static inline void put_unaligned_le32(u32 v, void *p) { __put_unaligned_t(u32, v, p); }
static inline void put_unaligned_le64(u64 v, void *p) { __put_unaligned_t(u64, v, p); }
static inline void put_unaligned_be16(u16 v, void *p) { __put_unaligned_t(u16, __builtin_bswap16(v), p); }
static inline void put_unaligned_be32(u32 v, void *p) { __put_unaligned_t(u32, __builtin_bswap32(v), p); }
static inline u32 get_unaligned_le24(const void *p) { const u8 *b = p; return b[0] | b[1] << 8 | (u32)b[2] << 16; }
static inline void put_unaligned_le24(u32 v, void *p) { u8 *b = p; b[0] = v; b[1] = v >> 8; b[2] = v >> 16; }
#endif
