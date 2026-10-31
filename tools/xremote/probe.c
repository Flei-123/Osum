#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdint.h>
#include <sys/syscall.h>

#define SYS_OSUM_SHOT 1841
#define SYS_OSUM_TIPP 1843
#define SYS_OSUM_BUS 1960

static long shot(long what, long a, long b) { return syscall(SYS_OSUM_SHOT, what, a, b); }
static long tipp(long what, long a, long b) { return syscall(SYS_OSUM_TIPP, what, a, b); }

static long bus(long op, long a, long b, long c, long d) { return syscall(SYS_OSUM_BUS, op, a, b, c, d); }

static int cmd_screen(void)
{
    printf("XR-SCREEN ready=%ld width=%ld height=%ld frames=%ld\n", shot(0, 0, 0), shot(0, 1, 0), shot(0, 2, 0), shot(0, 14, 0));
    return 0;
}

static int cmd_heads(void)
{
    long n = shot(0, 15, 0);
    printf("XR-HEADS count=%ld", n);
    for (long i = 0; i < n && i < 8; i++)
        printf(" h%ld=%ld,%ld,%ldx%ld", i, shot(0, 32 + i * 4, 0), shot(0, 33 + i * 4, 0), shot(0, 34 + i * 4, 0), shot(0, 35 + i * 4, 0));
    printf(" past=%ld\n", shot(0, 32 + n * 4, 0));
    return 0;
}

static int cmd_input(void)
{
    long ptr = tipp(0, 14, 0);
    printf("XR-INPUT total=%ld denied=%ld arms=%ld locked=%ld px=%ld py=%ld wheel=%ld hwheel=%ld buttons=%ld\n",
        tipp(0, 3, 0), tipp(0, 4, 0), tipp(0, 5, 0), tipp(0, 9, 0), ptr & 0xFFFFFFFFL, ptr >> 32, tipp(0, 15, 0), tipp(0, 16, 0), tipp(0, 17, 0));
    return 0;
}

static int cmd_wheel(void)
{
    long deny = tipp(9, 1, 0);
    long after_deny = tipp(0, 15, 0);
    long arm = tipp(1, 0, 0);
    long too_big = tipp(9, 100, 0);
    long bad_axis = tipp(9, 1, 2);
    long after_bad = tipp(0, 15, 0);
    long down = tipp(9, 5, 0);
    long up = tipp(9, -3, 0);
    long sum = tipp(0, 15, 0);
    long right = tipp(9, 2, 1);
    long hsum = tipp(0, 16, 0);
    tipp(9, -2, 0);
    tipp(9, -2, 1);
    long drop = tipp(2, 0, 0);
    printf("XR-WHEEL deny=%ld after_deny=%ld arm=%ld too_big=%ld bad_axis=%ld after_bad=%ld down=%ld up=%ld sum=%ld right=%ld hsum=%ld drop=%ld final=%ld hfinal=%ld\n",
        deny, after_deny, arm, too_big, bad_axis, after_bad, down, up, sum, right, hsum, drop, tipp(0, 15, 0), tipp(0, 16, 0));
    return 0;
}

static unsigned long fnv(const unsigned char *p, long n)
{
    unsigned long h = 0xcbf29ce484222325UL;
    for (long i = 0; i < n; i++)
        h = (h ^ p[i]) * 0x100000001b3UL;
    return h;
}

static long clip_set(const unsigned char *p, long n)
{
    long seg = 0;
    if (n > 192) {
        long id = bus(7, (n + 4095) / 4096, 0, 0, 0);
        if (id < 0)
            return id;
        long w = bus(26, id | (1L << 8), 0, (long)p, n);
        if (w < 0)
            return w;
        seg = id + 1;
    }
    return bus(10, 1, (long)p, n, seg);
}

static long clip_get(unsigned char *out, long max)
{
    long types = bus(12, 0, 0, 0, 0);
    if (types < 0 || !(types & 1))
        return 0;
    long len = bus(12, 0, 1, 0, 0);
    if (len <= 0 || len > max)
        return 0;
    unsigned long meta[6] = {0};
    long window = len < 192 ? len : 192;
    if (bus(11, 1L << 16, (long)out, window, (long)meta) < 0)
        return 0;
    if (meta[3] == 0)
        return (long)meta[4] < 192 ? (long)meta[4] : 192;
    if (bus(26, (long)meta[3] - 1, 0, (long)out, (long)meta[4]) < 0)
        return 0;
    return (long)meta[4];
}

static unsigned char clipbuf[8192];

static void clip_report(const char *tag, long n)
{
    printf("XR-CLIP %s len=%ld sum=%lx head=%.24s\n", tag, n, n > 0 ? fnv(clipbuf, n) : 0UL, n > 0 ? (const char *)clipbuf : "");
}

static int cmd_clipget(void)
{
    clip_report("get", clip_get(clipbuf, sizeof clipbuf - 1));
    return 0;
}

static int cmd_clipput(const char *text)
{
    long n = (long)strlen(text);
    long r = clip_set((const unsigned char *)text, n);
    printf("XR-CLIP put rc=%ld len=%ld sum=%lx\n", r, n, fnv((const unsigned char *)text, n));
    return r < 0;
}

static int cmd_clipbig(long n)
{
    if (n > (long)sizeof clipbuf - 1)
        n = sizeof clipbuf - 1;
    memcpy(clipbuf, "GUEST-BIG-", 10);
    for (long i = 10; i < n; i++)
        clipbuf[i] = 'a' + (i % 26);
    long r = clip_set(clipbuf, n);
    printf("XR-CLIP putbig rc=%ld len=%ld sum=%lx\n", r, n, fnv(clipbuf, n));
    return r < 0;
}

static int cmd_clipwait(const char *prefix, int secs)
{
    long plen = (long)strlen(prefix);
    for (int i = 0; i < secs * 5; i++) {
        long n = clip_get(clipbuf, sizeof clipbuf - 1);
        if (n >= plen && !memcmp(clipbuf, prefix, plen)) {
            clip_report("wait", n);
            return 0;
        }
        usleep(200000);
    }
    printf("XR-CLIP wait timeout\n");
    return 1;
}

extern char **environ;

static int cmd_env(void)
{
    int n = 0;
    for (char **e = environ; e && *e; e++, n++)
        printf("XR-ENV %s\n", *e);
    printf("XR-ENVN %d\n", n);
    for (int i = 0; i < 4 && environ; i++)
        printf("XR-RAW %d %p\n", i, (void *)environ[i]);
    return 0;
}

static int cmd_exec(int count)
{
    static char names[64][16];
    char *envp[65];
    char *args[] = {"xrprobe", "env", 0};
    int i;
    for (i = 0; i < count && i < 64; i++) {
        snprintf(names[i], sizeof names[i], "V%d=value%d", i, i);
        envp[i] = names[i];
    }
    envp[i] = 0;
    execve("/opt/xr/xrprobe", args, envp);
    perror("execve");
    return 1;
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

static int cmd_headlit(void)
{
    long w = shot(0, 1, 0), h = shot(0, 2, 0), rb = shot(0, 3, 0), rows = shot(0, 5, 0), n = shot(0, 15, 0);
    if (w <= 0 || h <= 0 || rb <= 0 || rows <= 0)
        return 1;
    if (shot(1, 0, 0) < 0)
        return 2;
    long lit[8] = {0};
    long xmin[8], xmax[8];
    for (int i = 0; i < 8; i++) { xmin[i] = 1 << 30; xmax[i] = -1; }
    unsigned char *chunk = malloc((size_t)rows * rb);
    long y = 0;
    while (y < h) {
        long got = shot(2, (long)chunk, rows * rb);
        if (got <= 0)
            return 3;
        long m = got / rb;
        for (long r = 0; r < m; r++) {
            for (long x = 0; x < w; x++) {
                unsigned char *p = chunk + r * rb + x * 3;
                if (p[0] <= 64 && p[1] <= 64 && p[2] <= 64)
                    continue;
                for (long i = 0; i < n && i < 8; i++) {
                    long hx = shot(0, 32 + i * 4, 0), hy = shot(0, 33 + i * 4, 0), hw = shot(0, 34 + i * 4, 0), hh = shot(0, 35 + i * 4, 0);
                    if (x >= hx && x < hx + hw && y + r >= hy && y + r < hy + hh) {
                        lit[i]++;
                        if (x - hx < xmin[i]) xmin[i] = x - hx;
                        if (x - hx > xmax[i]) xmax[i] = x - hx;
                    }
                }
            }
        }
        y += m;
    }
    printf("XR-HEADLIT n=%ld", n);
    for (long i = 0; i < n && i < 8; i++)
        printf(" l%ld=%ld x%ld=%ld..%ld", i, lit[i], i, lit[i] ? xmin[i] : -1L, xmax[i]);
    printf("\n");
    return 0;
}

int main(int argc, char **argv)
{
    if (argc < 2)
        return 64;
    if (!strcmp(argv[1], "screen"))
        return cmd_screen();
    if (!strcmp(argv[1], "heads"))
        return cmd_heads();
    if (!strcmp(argv[1], "input"))
        return cmd_input();
    if (!strcmp(argv[1], "wheel"))
        return cmd_wheel();
    if (!strcmp(argv[1], "clipget"))
        return cmd_clipget();
    if (!strcmp(argv[1], "clipput") && argc > 2)
        return cmd_clipput(argv[2]);
    if (!strcmp(argv[1], "clipbig") && argc > 2)
        return cmd_clipbig(atol(argv[2]));
    if (!strcmp(argv[1], "clipwait") && argc > 3)
        return cmd_clipwait(argv[2], atoi(argv[3]));
    if (!strcmp(argv[1], "env"))
        return cmd_env();
    if (!strcmp(argv[1], "exec") && argc > 2)
        return cmd_exec(atoi(argv[2]));
    if (!strcmp(argv[1], "headlit"))
        return cmd_headlit();
    if (!strcmp(argv[1], "grab"))
        return cmd_grab();
    return 64;
}
