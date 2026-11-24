#include "wifi.h"
#include <linux/random.h>

#define PRNG_SEED 0x9E3779B97F4A7C15ULL

static u64 prng_state = PRNG_SEED;

static u64 prng_next(void)
{
	prng_state ^= prng_state << 13;
	prng_state ^= prng_state >> 7;
	prng_state ^= prng_state << 17;
	prng_state ^= lkpi_time_ns();
	return prng_state;
}

void get_random_bytes(void *buf, size_t len)
{
	u8 *out = buf;

	while (len--)
		*out++ = (u8)(prng_next() >> 24);
}

u32 get_random_u32(void)
{
	return (u32)(prng_next() >> 16);
}

u32 get_random_u32_inclusive(u32 floor, u32 ceil)
{
	return floor + get_random_u32() % (ceil - floor + 1);
}
