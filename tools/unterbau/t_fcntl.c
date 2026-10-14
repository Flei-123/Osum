/* fcntl(F_DUPFD / F_DUPFD_CLOEXEC) must honour the minimum-descriptor argument (r727): the result is the lowest FREE descriptor >= min,
 * the clone shares the open file, EINVAL for an out-of-range minimum, EBADF for a bad source. */
#define TNAME "fcntl"
#include "t.h"
#include <fcntl.h>

int main(void)
{
    int src = open("/dev/null", O_RDONLY);
    int a = fcntl(src, F_DUPFD, 20);
    CHECK("dupfd_min", a == 20, "got %d, want 20", a);
    int b = fcntl(src, F_DUPFD, 20);
    CHECK("dupfd_skips_used", b == 21, "got %d, want 21", b);
    int c = fcntl(src, F_DUPFD, 0);
    CHECK("dupfd_zero_lowest_free", c >= 0 && c < 20, "got %d", c);
    int d = fcntl(src, F_DUPFD, src + 1);
    CHECK("dupfd_above_source", d > src && d != a && d != b && d != c, "got %d src=%d", d, src);
    int e = fcntl(src, F_DUPFD_CLOEXEC, 30);
    CHECK("dupfd_cloexec_min", e == 30 && (fcntl(e, F_GETFD) & FD_CLOEXEC), "got %d", e);
    CHECK("dupfd_plain_no_cloexec", !(fcntl(a, F_GETFD) & FD_CLOEXEC), "flags=%d", fcntl(a, F_GETFD));
    errno = 0;
    int r = fcntl(src, F_DUPFD, 100000);
    CHECK("dupfd_huge_einval", r == -1 && errno == EINVAL, "r=%d errno=%d", r, errno);
    errno = 0;
    r = fcntl(src, F_DUPFD, -1);
    CHECK("dupfd_negative_einval", r == -1 && errno == EINVAL, "r=%d errno=%d", r, errno);
    errno = 0;
    r = fcntl(999, F_DUPFD, 5);
    CHECK("dupfd_badf", r == -1 && errno == EBADF, "r=%d errno=%d", r, errno);
    /* shared open file: a seek through the clone is visible through the source */
    int f = open("/etc/passwd", O_RDONLY);
    int g = fcntl(f, F_DUPFD, 40);
    char ch;
    (void)!read(g, &ch, 1);
    CHECK("dupfd_shares_offset", g == 40 && lseek(f, 0, SEEK_CUR) == 1, "g=%d pos=%ld", g, (long)lseek(f, 0, SEEK_CUR));
    return 0;
}
