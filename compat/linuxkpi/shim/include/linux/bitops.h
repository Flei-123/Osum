/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_BITOPS_H
#define LKPI_LINUX_BITOPS_H
#include <linux/kernel.h>
#define BITS_PER_LONG 64
#define BITS_PER_BYTE 8
#define BIT_ULL(n) (1ULL << (n))
#define BIT_MASK(n) (1UL << ((n) % BITS_PER_LONG))
#define BIT_WORD(n) ((n) / BITS_PER_LONG)
#define BITS_TO_LONGS(n) (((n) + BITS_PER_LONG - 1) / BITS_PER_LONG)
#define GENMASK(h, l) (((~0UL) >> (BITS_PER_LONG - 1 - (h))) & (~0UL << (l)))
#define GENMASK_ULL(h, l) (((~0ULL) >> (63 - (h))) & (~0ULL << (l)))
#define DECLARE_BITMAP(name, bits) unsigned long name[BITS_TO_LONGS(bits)]
static inline void set_bit(long nr, volatile unsigned long *addr) { __atomic_fetch_or(&addr[BIT_WORD(nr)], BIT_MASK(nr), __ATOMIC_SEQ_CST); }
static inline void clear_bit(long nr, volatile unsigned long *addr) { __atomic_fetch_and(&addr[BIT_WORD(nr)], ~BIT_MASK(nr), __ATOMIC_SEQ_CST); }
static inline bool test_bit(long nr, const volatile unsigned long *addr) { return (addr[BIT_WORD(nr)] >> (nr % BITS_PER_LONG)) & 1; }
static inline bool test_and_set_bit(long nr, volatile unsigned long *addr) { return (__atomic_fetch_or(&addr[BIT_WORD(nr)], BIT_MASK(nr), __ATOMIC_SEQ_CST) & BIT_MASK(nr)) != 0; }
static inline bool test_and_clear_bit(long nr, volatile unsigned long *addr) { return (__atomic_fetch_and(&addr[BIT_WORD(nr)], ~BIT_MASK(nr), __ATOMIC_SEQ_CST) & BIT_MASK(nr)) != 0; }
#define __set_bit(nr, addr) ((addr)[BIT_WORD(nr)] |= BIT_MASK(nr))
#define __clear_bit(nr, addr) ((addr)[BIT_WORD(nr)] &= ~BIT_MASK(nr))
static inline int fls(unsigned int x) { return x ? 32 - __builtin_clz(x) : 0; }
static inline int ffs(int x) { return __builtin_ffs(x); }
static inline unsigned long __ffs(unsigned long x) { return __builtin_ctzl(x); }
static inline unsigned long __fls(unsigned long x) { return 63 - __builtin_clzl(x); }
static inline int fls64(u64 x) { return x ? 64 - __builtin_clzll(x) : 0; }
#define hweight8(x) __builtin_popcount((u8)(x))
#define hweight16(x) __builtin_popcount((u16)(x))
#define hweight32(x) __builtin_popcount((u32)(x))
#define hweight64(x) __builtin_popcountll((u64)(x))
#define hweight_long(x) __builtin_popcountl(x)
unsigned long find_next_bit(const unsigned long *addr, unsigned long size, unsigned long offset);
unsigned long find_next_zero_bit(const unsigned long *addr, unsigned long size, unsigned long offset);
#define find_first_bit(addr, size) find_next_bit((addr), (size), 0)
#define find_first_zero_bit(addr, size) find_next_zero_bit((addr), (size), 0)
#define for_each_set_bit(bit, addr, size) \
	for ((bit) = find_first_bit((addr), (size)); (bit) < (size); (bit) = find_next_bit((addr), (size), (bit) + 1))
#endif
