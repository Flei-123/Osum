#include "wifi.h"
#include <linux/bsearch.h>
#include <linux/crc32.h>
#include <linux/rtnetlink.h>
#include <linux/rcupdate.h>
#include <linux/ptp_clock_kernel.h>

#define CRC32_LE_POLY 0xEDB88320U
#define BITS_PER_WORD (8 * sizeof(unsigned long))
#define HEX_DUMP_LINE_MAX 3
#define U128_BITS 128
#define LKPI_HEX_LINE_MAX 128

typedef unsigned __int128 lkpi_u128;

static int rtnl_depth;

void *bsearch(const void *key, const void *base, size_t num, size_t size, int (*cmp)(const void *key, const void *elt))
{
	size_t low = 0;
	size_t high = num;

	while (low < high) {
		size_t mid = low + (high - low) / 2;
		const void *elt = (const u8 *)base + mid * size;
		int order = cmp(key, elt);

		if (order == 0)
			return (void *)elt;
		if (order < 0)
			high = mid;
		else
			low = mid + 1;
	}
	return NULL;
}

u32 crc32_le(u32 crc, const unsigned char *p, size_t len)
{
	unsigned int bit;

	while (len--) {
		crc ^= *p++;
		for (bit = 0; bit < 8; bit++)
			crc = (crc >> 1) ^ ((crc & 1) ? CRC32_LE_POLY : 0);
	}
	return crc;
}

unsigned long find_next_bit(const unsigned long *addr, unsigned long size, unsigned long offset)
{
	for (; offset < size; offset++) {
		if (addr[offset / BITS_PER_WORD] & (1UL << (offset % BITS_PER_WORD)))
			return offset;
	}
	return size;
}

lkpi_u128 __udivti3(lkpi_u128 numerator, lkpi_u128 denominator)
{
	lkpi_u128 quotient = 0;
	lkpi_u128 remainder = 0;
	int bit;

	if (!denominator)
		return 0;
	for (bit = U128_BITS - 1; bit >= 0; bit--) {
		remainder = (remainder << 1) | ((numerator >> bit) & 1);
		if (remainder >= denominator) {
			remainder -= denominator;
			quotient |= (lkpi_u128)1 << bit;
		}
	}
	return quotient;
}

void print_hex_dump(const char *level, const char *prefix_str, int prefix_type, int rowsize, int groupsize,
		    const void *buf, size_t len, bool ascii)
{
	const u8 *bytes = buf;
	char line[LKPI_HEX_LINE_MAX];
	size_t row;
	size_t col;
	size_t used;

	(void)level;
	(void)prefix_type;
	(void)groupsize;
	(void)ascii;
	for (row = 0; row < len; row += rowsize) {
		used = 0;
		for (col = 0; col < (size_t)rowsize && row + col < len && used + HEX_DUMP_LINE_MAX < sizeof(line); col++)
			used += snprintf(line + used, sizeof(line) - used, "%02x ", bytes[row + col]);
		_printk("lkpi: %s%s\n", prefix_str, line);
	}
}

void dump_stack(void)
{
	_printk("lkpi: dump_stack\n");
}

void rtnl_lock(void)
{
	rtnl_depth++;
}

void rtnl_unlock(void)
{
	if (rtnl_depth)
		rtnl_depth--;
}

int rtnl_is_locked(void)
{
	return rtnl_depth != 0;
}

void synchronize_rcu(void)
{
	lkpi_work_run();
}

struct ptp_clock *ptp_clock_register(struct ptp_clock_info *info, struct device *parent)
{
	(void)info;
	(void)parent;
	return NULL;
}

void ptp_clock_unregister(struct ptp_clock *ptp)
{
	(void)ptp;
}

int ptp_clock_index(struct ptp_clock *ptp)
{
	(void)ptp;
	return -1;
}
