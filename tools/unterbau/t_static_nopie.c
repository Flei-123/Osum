/* SPDX-License-Identifier: GPL-2.0-only
 * static non-PIE executable linked at 0x400000 (gcc -static -no-pie): the low-window alias of the product kernel. */
#define TNAME "static_nopie"
#include "t.h"
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>

static int initial_data = 41;
static int zero_bss[4096];
static const char ro_text[] = "read-only text";
static char *argv0;

static uintptr_t here(void) { return (uintptr_t)&initial_data; }

int main(int argc, char **argv)
{
    if (argc > 1 && strcmp(argv[1], "child") == 0) return 5;
    argv0 = argc > 0 ? argv[0] : "";
    CHECK("link_address", here() >= 0x400000 && here() < 0x1000000, "data at %#lx", (unsigned long)here());
    CHECK("data_initial", initial_data == 41, "got %d", initial_data);
    initial_data = 42;
    CHECK("data_write", initial_data == 42, "got %d", initial_data);
    zero_bss[4095] = 7;
    int sum = 0;
    for (int i = 0; i < 4095; i++) sum |= zero_bss[i];
    CHECK("bss_zero_and_write", sum == 0 && zero_bss[4095] == 7, "sum %d", sum);
    CHECK("rodata", strcmp(ro_text, "read-only text") == 0, "bad rodata");

    char *m = malloc(3 * 1024 * 1024);
    CHECK("malloc_large", m != NULL, "null");
    if (m) { memset(m, 0xab, 3 * 1024 * 1024); CHECK("malloc_touch", (unsigned char)m[3 * 1024 * 1024 - 1] == 0xab, "bad byte"); }
    unsigned long b0 = syscall(SYS_brk, 0UL);
    unsigned long b1 = syscall(SYS_brk, b0 + 65536);
    ((char *)b0)[100] = 1;
    CHECK("brk_grow", b1 == b0 + 65536 && ((char *)b0)[100] == 1, "brk %#lx -> %#lx", b0, b1);

    void *p = mmap(NULL, 8192, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECKC("mmap_anon", p != MAP_FAILED);
    if (p != MAP_FAILED) { ((char *)p)[8191] = 1; CHECK("mmap_write", ((char *)p)[8191] == 1, "bad"); munmap(p, 8192); }

    uintptr_t page = (uintptr_t)&initial_data & ~4095UL;
    int rc = mprotect((void *)page, 4096, PROT_READ | PROT_WRITE);
    CHECKC("mprotect_data_page", rc == 0);
    rc = mprotect((void *)page, 4096, PROT_READ);
    CHECKC("mprotect_relro_like", rc == 0);
    int fd = open("/dev/null", O_WRONLY);
    ssize_t w = write(fd, ro_text, sizeof ro_text);
    CHECK("syscall_buffer_from_low", w == (ssize_t)sizeof ro_text, "wrote %ld", (long)w);
    int pf[2]; (void)!pipe(pf);
    w = write(pf[1], &initial_data, sizeof initial_data);
    int got = 0; ssize_t r = read(pf[0], &got, sizeof got);
    CHECK("pipe_roundtrip_low", w == 4 && r == 4 && got == 42, "w %ld r %ld got %d", (long)w, (long)r, got);
    mprotect((void *)page, 4096, PROT_READ | PROT_WRITE);

    pid_t c = fork();
    if (c == 0) { initial_data = 99; zero_bss[0] = 5; _exit(initial_data == 99 && zero_bss[0] == 5 ? 3 : 4); }
    int st = 0; pid_t wp = c > 0 ? waitpid(c, &st, 0) : -1;
    CHECK("fork_child_ran", wp == c && WIFEXITED(st) && WEXITSTATUS(st) == 3, "wp %d st %#x", (int)wp, st);
    CHECK("fork_copy_private", initial_data == 42 && zero_bss[0] == 0, "data %d bss0 %d", initial_data, zero_bss[0]);

    c = fork();
    if (c == 0) {
        char *args[] = { argv0, "child", NULL };
        execv(argv0, args);
        _exit(77);
    }
    wp = c > 0 ? waitpid(c, &st, 0) : -1;
    CHECK("exec_self", wp == c && WIFEXITED(st) && WEXITSTATUS(st) == 5, "st %#x", st);

    c = fork();
    if (c == 0) {
        char *args[] = { "/bin/echo", "x", NULL };
        execv("/bin/echo", args);
        _exit(77);
    }
    wp = c > 0 ? waitpid(c, &st, 0) : -1;
    CHECK("exec_into_other_image", wp == c && WIFEXITED(st) && WEXITSTATUS(st) == 0, "st %#x", st);

    FILE *f = fopen("/proc/self/maps", "r");
    int saw_low = 0;
    if (f) {
        char line[256];
        while (fgets(line, sizeof line, f)) if (strncmp(line, "00000000004", 11) == 0 || strncmp(line, "00000000005", 11) == 0) saw_low = 1;
        fclose(f);
    }
    CHECK("proc_maps_low_image", saw_low, "no 0x4xxxxx line");
    return 0;
}
