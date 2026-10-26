#ifndef BOOTREG_UTIL_H
#define BOOTREG_UTIL_H

#include "efi.h"

void *memcpy(void *dst, const void *src, u64 n);
void *memset(void *dst, int c, u64 n);
int memcmp(const void *a, const void *b, u64 n);

int guid_equal(const guid_t *a, const guid_t *b);
u64 str_len(const char *s);
u64 u16_len(const u16 *s);
int u16_equal_ascii(const u16 *s, const char *ascii);
u64 ascii_to_u16(u16 *dst, const char *src, u64 max);
u64 u16_to_ascii(char *dst, const u16 *src, u64 max);

void log_init(system_table_t *st);
void log_str(const char *s);
void log_flush(void);
void log_u16(const u16 *s);
void log_hex(u64 v, int digits);
void log_status(u64 status);
void log_dp(const u8 *dp);

void boot_name(u16 *out, u16 number);

#endif
