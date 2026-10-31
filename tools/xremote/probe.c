#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/syscall.h>

#define SYS_OSUM_SHOT 1841
#define SYS_OSUM_TIPP 1843

static long shot(long what, long a, long b) { return syscall(SYS_OSUM_SHOT, what, a, b); }
static long tipp(long what, long a, long b) { return syscall(SYS_OSUM_TIPP, what, a, b); }

static int cmd_screen(void)
{
    printf("XR-SCREEN ready=%ld width=%ld height=%ld frames=%ld\n", shot(0, 0, 0), shot(0, 1, 0), shot(0, 2, 0), shot(0, 14, 0));
    return 0;
}

static int cmd_input(void)
{
    printf("XR-INPUT total=%ld denied=%ld arms=%ld locked=%ld\n", tipp(0, 3, 0), tipp(0, 4, 0), tipp(0, 5, 0), tipp(0, 9, 0));
    return 0;
}

static int cmd_grab(void)
{
    long w = shot(0, 1, 0), h = shot(0, 2, 0), rb = shot(0, 3, 0), rows = shot(0, 5, 0);
    if (w <= 0 || h <= 0 || rb <= 0 || rows <= 0)
        return 1;
    if (shot(1, 0, 0) < 0)
        return 2;
    unsigned char *chunk = malloc((size_t)rows * rb);
    long y = 0, lit = 0, sum = 0;
    while (y < h) {
        long got = shot(2, (long)chunk, rows * rb);
        if (got <= 0)
            return 3;
        long n = got / rb;
        for (long i = 0; i < n * rb; i++) {
            sum += chunk[i];
            if (chunk[i])
                lit++;
        }
        y += n;
    }
    printf("XR-GRAB width=%ld height=%ld lit=%ld sum=%ld\n", w, h, lit, sum);
    return 0;
}

int main(int argc, char **argv)
{
    if (argc < 2)
        return 64;
    if (!strcmp(argv[1], "screen"))
        return cmd_screen();
    if (!strcmp(argv[1], "input"))
        return cmd_input();
    if (!strcmp(argv[1], "grab"))
        return cmd_grab();
    return 64;
}
