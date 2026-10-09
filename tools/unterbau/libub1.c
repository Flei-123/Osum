/* foreign test library 1: constructor, relocated data pointer, bss, libc calls */
#include <stdio.h>
#include <string.h>
static int ctor_ran;
static const char *msg = "libub1 string";   /* R_X86_64_RELATIVE in .data.rel.ro / .data */
int ub1_bss[1024];                          /* bss, must be zero */
int ub1_data = 41;
__attribute__((constructor)) static void c(void) { ctor_ran = 1; }
int ub1_ctor(void) { return ctor_ran; }
int ub1_add(int a, int b) { return a + b + (ub1_data - 41); }
const char *ub1_msg(void) { return msg; }
int ub1_bss_sum(void) { int s = 0; for (int i = 0; i < 1024; i++) s += ub1_bss[i]; return s; }
int ub1_fmt(char *out, int n) { return snprintf(out, n, "%s/%d", msg, (int)strlen(msg)); }
