/* child program of t_proc: prints its arguments and one environment variable, exits with a code */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
int main(int argc, char **argv)
{
    if (argc > 1 && !strcmp(argv[1], "exit7")) return 7;
    if (argc > 1 && !strcmp(argv[1], "cat")) { char b[256]; int n; while ((n = read(0, b, sizeof b)) > 0) write(1, b, n); return 0; }
    if (argc > 1 && !strcmp(argv[1], "sleep")) { sleep(1); return 3; }
    if (argc > 1 && !strcmp(argv[1], "count")) { printf("argc=%d last=%s\n", argc, argv[argc - 1]); fflush(stdout); return 0; }
    const char *x = getenv("UB_X");
    printf("child argc=%d a1=%s a2=%s env=%s\n", argc, argc > 1 ? argv[1] : "-", argc > 2 ? argv[2] : "-", x ? x : "-");
    fflush(stdout);
    return 42;
}
