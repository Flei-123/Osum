/* SPDX-License-Identifier: GPL-2.0-only
 * tools/unterbau/t.h -- tiny check helper for the OrientOS "Unterbau" tests.
 * Every check prints ONE line:  T <test>.<name> PASS|FAIL|GAP <detail>
 *   PASS = works, FAIL = wrong answer, GAP = the call/feature is missing (ENOSYS, ENOENT, ...).
 * Lines go out with write(2) straight to fd 1, so a crash later does not lose earlier lines.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#ifndef TNAME
#define TNAME "t"
#endif

static void t_emit(const char *name, const char *verdict, const char *fmt, ...)
{
    char buf[400];
    int n = snprintf(buf, sizeof buf, "T %s.%s %s ", TNAME, name, verdict);
    va_list ap;
    va_start(ap, fmt);
    if (n < (int)sizeof buf)
        n += vsnprintf(buf + n, sizeof buf - n, fmt, ap);
    va_end(ap);
    if (n > (int)sizeof buf - 2)
        n = sizeof buf - 2;
    buf[n++] = '\n';
    (void)!write(1, buf, n);
}
#define PASS(name, ...)  t_emit(name, "PASS", "" __VA_ARGS__)
#define FAIL(name, ...)  t_emit(name, "FAIL", __VA_ARGS__)
#define GAP(name, ...)   t_emit(name, "GAP", __VA_ARGS__)
/* ok(name, cond, "detail on failure %d", x) */
#define CHECK(name, cond, ...) do { if (cond) PASS(name); else FAIL(name, __VA_ARGS__); } while (0)
/* a call that returns -1 with errno: ENOSYS/ENOENT/EINVAL ... counts as a GAP when the call is missing */
#define CHECKC(name, cond, ...) do { if (cond) PASS(name); else if (errno == ENOSYS || errno == ENOENT || errno == ENODEV || errno == ENOTSUP || errno == EOPNOTSUPP || errno == EAFNOSUPPORT) GAP(name, "errno=%d %s", errno, strerror(errno)); else FAIL(name, "errno=%d %s", errno, strerror(errno)); } while (0)
