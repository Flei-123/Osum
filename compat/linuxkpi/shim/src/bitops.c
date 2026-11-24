#include <linux/types.h>

int __popcountdi2(long long value)
{
	unsigned long long bits = (unsigned long long)value;
	int count = 0;

	for (; bits; bits &= bits - 1)
		count++;
	return count;
}

int __popcountsi2(int value)
{
	return __popcountdi2((unsigned int)value);
}
