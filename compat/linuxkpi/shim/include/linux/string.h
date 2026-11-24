/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_STRING_H
#define LKPI_LINUX_STRING_H
#include <linux/kernel.h>
size_t strscpy(char *dst, const char *src, size_t size);
ssize_t strscpy_pad(char *dst, const char *src, size_t size);
size_t strnlen(const char *text, size_t max);
size_t strlcpy(char *dst, const char *src, size_t size);
char *strchr(const char *s, int c);
char *strstr(const char *haystack, const char *needle);
void *memchr(const void *s, int c, size_t n);
#define memset_after(obj, v, member) memset((u8 *)(obj) + __builtin_offsetof(__typeof__(*(obj)), member) + sizeof((obj)->member), (v), sizeof(*(obj)) - __builtin_offsetof(__typeof__(*(obj)), member) - sizeof((obj)->member))
#define memset_startat(obj, v, member) memset((u8 *)(obj) + __builtin_offsetof(__typeof__(*(obj)), member), (v), sizeof(*(obj)) - __builtin_offsetof(__typeof__(*(obj)), member))
#endif
