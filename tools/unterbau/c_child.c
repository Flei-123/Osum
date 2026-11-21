/* child program of t_proc: prints its arguments and one environment variable, exits with a code */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
int main(int argc, char **argv)
{
    if (argc > 1 && !strcmp(argv[1], "exit7")) return 7;
    if (argc > 1 && !strcmp(argv[1], "cat")) { char b[256]; int n; while ((n = read(0, b, sizeof b)) > 0) write(1, b, n); return 0; }
    if (argc > 1 && !strcmp(argv[1], "fdscan")) { int lo = 0, hi = 0; for (int fd = 3; fd < 512; fd++) if (fcntl(fd, F_GETFD) >= 0) { if (fd < 64) lo++; else hi++; } printf("fdscan lo=%d hi=%d\n", lo, hi); fflush(stdout); return 0; }
    if (argc > 1 && !strcmp(argv[1], "sleep")) { sleep(1); return 3; }
    if (argc > 1 && !strcmp(argv[1], "count")) { printf("argc=%d last=%s\n", argc, argv[argc - 1]); fflush(stdout); return 0; }
    if (argc > 2 && !strcmp(argv[1], "verify")) {
        size_t total = 0; int bad = 0;
        for (int i = 2; i < argc; i++) { size_t n = strlen(argv[i]); total += n; for (size_t k = 0; k < n; k++) if (argv[i][k] != 'a' + i % 26) bad++; }
        const char *e = getenv("UB_X");
        printf("verify argc=%d total=%zu bad=%d env=%s\n", argc, total, bad, e ? e : "-"); fflush(stdout); return 0;
    }
    const char *x = getenv("UB_X");
    printf("child argc=%d a1=%s a2=%s env=%s\n", argc, argc > 1 ? argv[1] : "-", argc > 2 ? argv[2] : "-", x ? x : "-");
    fflush(stdout);
    return 42;
}
