#include "lkpi.h"

void *memset(void *dst, int value, size_t count)
{
	u8 *d = dst;

	while (count--)
		*d++ = (u8)value;
	return dst;
}

void *memcpy(void *dst, const void *src, size_t count)
{
	u8 *d = dst;
	const u8 *s = src;

	while (count--)
		*d++ = *s++;
	return dst;
}

void *memmove(void *dst, const void *src, size_t count)
{
	u8 *d = dst;
	const u8 *s = src;

	if (d == s || count == 0)
		return dst;
	if (d < s) {
		while (count--)
			*d++ = *s++;
	} else {
		d += count;
		s += count;
		while (count--)
			*--d = *--s;
	}
	return dst;
}

int memcmp(const void *a, const void *b, size_t count)
{
	const u8 *x = a;
	const u8 *y = b;

	while (count--) {
		if (*x != *y)
			return *x < *y ? -1 : 1;
		x++;
		y++;
	}
	return 0;
}

size_t strlen(const char *text)
{
	size_t length = 0;

	while (text[length])
		length++;
	return length;
}

int strcmp(const char *a, const char *b)
{
	while (*a && *a == *b) {
		a++;
		b++;
	}
	return (u8)*a - (u8)*b;
}

int strncmp(const char *a, const char *b, size_t count)
{
	while (count && *a && *a == *b) {
		a++;
		b++;
		count--;
	}
	if (!count)
		return 0;
	return (u8)*a - (u8)*b;
}
